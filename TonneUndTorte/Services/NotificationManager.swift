import Foundation
import UserNotifications
import UIKit
import TonneCore

/// Plant lokale Mitteilungen mit Aktionen („Erledigt“, „In 1 Stunde“) und verarbeitet Antworten.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingCount: Int = 0

    private let center = UNUserNotificationCenter.current()
    private let maxRequests = 60

    static let doneAction = "PICKUP_DONE"
    static let snoozeAction = "PICKUP_SNOOZE"
    static let giftAction = "BIRTHDAY_GIFT"

    /// Wird aufgerufen, wenn der Nutzer in einer Mitteilung „Erledigt“ tippt (dayKey).
    var onPickupDone: ((String) -> Void)?

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        let done = UNNotificationAction(identifier: NotificationManager.doneAction, title: "✅ Erledigt – steht draußen", options: [])
        let snooze = UNNotificationAction(identifier: NotificationManager.snoozeAction, title: "⏰ In 1 Stunde nochmal", options: [])
        let waste = UNNotificationCategory(identifier: "WASTE", actions: [done, snooze], intentIdentifiers: [], options: [])
        let birthday = UNNotificationCategory(identifier: "BIRTHDAY", actions: [], intentIdentifiers: [], options: [])
        let custom = UNNotificationCategory(identifier: "CUSTOM", actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([waste, birthday, custom])
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        pendingCount = await center.pendingNotificationRequests().count
    }

    var isAuthorized: Bool {
        [.authorized, .provisional, .ephemeral].contains(authorizationStatus)
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

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Planung

    func apply(_ plan: [PlannedNotification]) async {
        center.removeAllPendingNotificationRequests()
        for item in plan.prefix(maxRequests) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.threadIdentifier
            content.userInfo = ["dayKey": item.dayKey, "category": item.category.rawValue]
            switch item.category {
            case .wasteEvening, .wasteMorning, .wasteEscalation:
                content.categoryIdentifier = "WASTE"
                content.interruptionLevel = item.category == .wasteEscalation ? .timeSensitive : .active
            case .birthday:
                content.categoryIdentifier = "BIRTHDAY"
            case .custom:
                content.categoryIdentifier = "CUSTOM"
            }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
        await refreshStatus()
    }

    /// Entfernt alle Müll-Mitteilungen eines Tages (nach „Erledigt“).
    func cancelWasteReminders(dayKey: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["waste-evening-\(dayKey)", "waste-escalation-\(dayKey)", "waste-morning-\(dayKey)", "waste-snooze-\(dayKey)"])
        center.removeDeliveredNotifications(withIdentifiers: ["waste-evening-\(dayKey)", "waste-escalation-\(dayKey)", "waste-morning-\(dayKey)", "waste-snooze-\(dayKey)"])
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Morgen: Gelber Sack"
        content.body = "So sieht eine Erinnerung von Tonne & Torte aus. 🎉"
        content.sound = .default
        content.categoryIdentifier = "WASTE"
        content.userInfo = ["dayKey": Days.iso(Days.add(1, to: Days.today())), "category": "WASTE_EVENING"]
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        center.add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let dayKey = userInfo["dayKey"] as? String ?? ""
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        switch response.actionIdentifier {
        case NotificationManager.doneAction:
            await MainActor.run {
                SnapshotStore.markDone(dayKey: dayKey)
                self.onPickupDone?(dayKey)
            }
        case NotificationManager.snoozeAction:
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = "WASTE"
            content.userInfo = userInfo
            let request = UNNotificationRequest(identifier: "waste-snooze-\(dayKey)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false))
            try? await center.add(request)
        default:
            break
        }
    }
}
