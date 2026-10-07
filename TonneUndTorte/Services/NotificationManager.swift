import Foundation
import SwiftData
import UserNotifications
import UIKit

/// Plant lokale Benachrichtigungen für Abholungen und Geburtstage.
///
/// iOS erlaubt maximal 64 anstehende lokale Benachrichtigungen pro App. Deshalb werden
/// alle anstehenden Erinnerungen berechnet, nach Zeitpunkt sortiert und nur die nächsten
/// 60 eingeplant. Bei jedem App-Start und nach jeder Änderung wird neu geplant.
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastScheduled: Date?

    private let center = UNUserNotificationCenter.current()
    private let maxRequests = 60
    private let horizonDays = 90

    private init() {}

    // MARK: - Berechtigung

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        let pending = await center.pendingNotificationRequests()
        pendingCount = pending.count
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            return granted
        } catch {
            await refreshStatus()
            return false
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Planung

    /// Lädt alle Daten aus dem Kontext und plant die Benachrichtigungen neu.
    func reschedule(using context: ModelContext) async {
        let wasteTypes = (try? context.fetch(FetchDescriptor<WasteType>())) ?? []
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        await reschedule(wasteTypes: wasteTypes, people: people, settings: ReminderSettings.load())
    }

    func reschedule(wasteTypes: [WasteType], people: [Person], settings: ReminderSettings) async {
        let planned = buildRequests(wasteTypes: wasteTypes, people: people, settings: settings)

        center.removeAllPendingNotificationRequests()
        for request in planned.prefix(maxRequests) {
            try? await center.add(request)
        }
        lastScheduled = Date()
        await refreshStatus()
    }

    /// Baut die Liste aller Benachrichtigungen (unsortiert → am Ende nach Zeitpunkt sortiert).
    private func buildRequests(
        wasteTypes: [WasteType],
        people: [Person],
        settings: ReminderSettings,
        calendar: Calendar = .current
    ) -> [UNNotificationRequest] {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) else { return [] }

        var entries: [(fireDate: Date, request: UNNotificationRequest)] = []

        // --- Müll: pro Tag alle Müllarten zusammenfassen -------------------------------
        let locationCount = Set(wasteTypes.compactMap { $0.location?.id }).count
        var pickupsByDay: [Date: [WasteType]] = [:]
        for type in wasteTypes where type.isActive && type.remindersEnabled {
            for day in EventEngine.pickupDates(for: type, from: today, to: horizon, calendar: calendar) {
                pickupsByDay[day, default: []].append(type)
            }
        }

        for (day, types) in pickupsByDay {
            let sortedTypes = types.sorted { $0.sortOrder < $1.sortOrder }
            let names = sortedTypes.map { type -> String in
                if locationCount > 1, let location = type.location {
                    return "\(type.name) (\(location.name))"
                }
                return type.name
            }
            let list = ListFormatter.localizedString(byJoining: names)
            let dayKey = Int(day.timeIntervalSince1970)

            if settings.eveningEnabled,
               let dayBefore = calendar.date(byAdding: .day, value: -1, to: day),
               let fire = at(minutes: settings.eveningMinutes, on: dayBefore, calendar: calendar),
               fire > now {
                let content = UNMutableNotificationContent()
                content.title = names.count == 1 ? "Morgen: \(names[0])" : "Morgen wird abgeholt"
                content.body = names.count == 1
                    ? "Heute Abend rausstellen – morgen kommt die Abfuhr."
                    : "\(list) – heute Abend rausstellen."
                content.sound = .default
                content.threadIdentifier = "waste"
                content.userInfo = ["kind": "waste", "day": dayKey]
                entries.append((fire, UNNotificationRequest(
                    identifier: "waste-evening-\(dayKey)",
                    content: content,
                    trigger: trigger(for: fire, calendar: calendar)
                )))
            }

            if settings.morningEnabled,
               let fire = at(minutes: settings.morningMinutes, on: day, calendar: calendar),
               fire > now {
                let content = UNMutableNotificationContent()
                content.title = names.count == 1 ? "Heute: \(names[0])" : "Heute wird abgeholt"
                content.body = names.count == 1
                    ? "Steht die Tonne schon draußen?"
                    : "\(list) – steht alles draußen?"
                content.sound = .default
                content.threadIdentifier = "waste"
                content.userInfo = ["kind": "waste", "day": dayKey]
                entries.append((fire, UNNotificationRequest(
                    identifier: "waste-morning-\(dayKey)",
                    content: content,
                    trigger: trigger(for: fire, calendar: calendar)
                )))
            }
        }

        // --- Geburtstage ---------------------------------------------------------------
        for person in people where person.remindersEnabled {
            guard let next = EventEngine.nextBirthday(for: person, after: today, calendar: calendar),
                  next <= horizon else { continue }
            let age = EventEngine.age(of: person, on: next, calendar: calendar)
            let dayKey = Int(next.timeIntervalSince1970)

            if let fire = at(minutes: settings.birthdayMinutes, on: next, calendar: calendar), fire > now {
                let content = UNMutableNotificationContent()
                content.title = "🎂 \(person.name) hat heute Geburtstag"
                if let age {
                    content.body = "\(person.name) wird heute \(age). Zeit zum Gratulieren!"
                } else {
                    content.body = "Zeit zum Gratulieren!"
                }
                content.sound = .default
                content.threadIdentifier = "birthday"
                content.userInfo = ["kind": "birthday", "day": dayKey]
                entries.append((fire, UNNotificationRequest(
                    identifier: "bday-\(person.id.uuidString)-\(dayKey)",
                    content: content,
                    trigger: trigger(for: fire, calendar: calendar)
                )))
            }

            if person.remindDaysBefore > 0,
               let beforeDay = calendar.date(byAdding: .day, value: -person.remindDaysBefore, to: next),
               let fire = at(minutes: settings.birthdayMinutes, on: beforeDay, calendar: calendar),
               fire > now {
                let content = UNMutableNotificationContent()
                let when = person.remindDaysBefore == 1 ? "morgen" : "in \(person.remindDaysBefore) Tagen"
                content.title = "🎁 \(person.name) hat \(when) Geburtstag"
                if let age {
                    content.body = "Wird \(age). Noch ein Geschenk besorgen?"
                } else {
                    content.body = "Noch ein Geschenk besorgen?"
                }
                content.sound = .default
                content.threadIdentifier = "birthday"
                content.userInfo = ["kind": "birthday", "day": dayKey]
                entries.append((fire, UNNotificationRequest(
                    identifier: "bday-pre-\(person.id.uuidString)-\(dayKey)",
                    content: content,
                    trigger: trigger(for: fire, calendar: calendar)
                )))
            }
        }

        return entries.sorted { $0.fireDate < $1.fireDate }.map(\.request)
    }

    private func at(minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return calendar.date(from: components)
    }

    private func trigger(for date: Date, calendar: Calendar) -> UNCalendarNotificationTrigger {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    // MARK: - Test

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Morgen: Gelber Sack"
        content.body = "So sieht eine Erinnerung von Tonne & Torte aus. 🎉"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        center.add(request)
    }
}

/// Sorgt dafür, dass Benachrichtigungen auch angezeigt werden, während die App geöffnet ist.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
