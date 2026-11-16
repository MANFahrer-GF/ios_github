import Foundation
import SwiftUI
import TonneCore
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Wecker am Vorabend (AlarmKit, ab iOS 26): klingelt wie ein Wecker, auch stumm oder im Fokus.
/// Standard aus; nur auf diesem Gerät. Unter iOS 26 gibt es den Schalter nicht, die Erinnerungen bleiben wie bisher.
enum AlarmScheduler {
    /// Gibt es Wecker auf diesem Gerät überhaupt?
    static var isSupported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Erlaubnis erfragen (beim Einschalten). true = Wecker dürfen klingeln.
    static func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return true
            case .denied: return false
            case .notDetermined: return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
            @unknown default: return false
            }
        }
        #endif
        return false
    }

    /// Hat der Nutzer die Wecker-Erlaubnis in den Einstellungen entzogen?
    static var isDenied: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .denied }
        #endif
        return false
    }

    /// Zahl der geplanten Wecker der App (für die Einstellungen).
    static var scheduledCount: Int {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return ((try? AlarmManager.shared.alarms) ?? []).filter { $0.state == .scheduled }.count }
        #endif
        return 0
    }

    /// Geplante Wecker an den Plan angleichen: Fehlendes und Geändertes neu planen, alles andere entfernen.
    /// Ohne Erlaubnis (oder ausgeschaltet: leerer Plan) bleibt kein Wecker der App stehen.
    static func apply(_ plan: [PlannedAlarm]) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else { return }
        let manager = AlarmManager.shared
        let existing = (try? manager.alarms) ?? []
        let wanted = manager.authorizationState == .authorized ? plan : []
        let keep = Set(wanted.map(\.id))
        for alarm in existing where !keep.contains(alarm.id) { try? manager.cancel(id: alarm.id) }
        let scheduled = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in wanted {
            // Gleicher Zeitpunkt schon geplant: stehen lassen (der Titel ändert sich nur mit den Müllarten – dann neu)
            if case .fixed(let date)? = scheduled[item.id]?.schedule, date == item.fireDate,
               SettingsKeys.store.string(forKey: titleKey(item.id)) == item.title { continue }
            if scheduled[item.id] != nil { try? manager.cancel(id: item.id) }
            do {
                _ = try await manager.schedule(id: item.id, configuration: configuration(for: item))
                SettingsKeys.store.set(item.title, forKey: titleKey(item.id))
            } catch {
                // Zu viele Wecker o. Ä.: die späteren entfallen, die Mitteilungen kommen trotzdem
                break
            }
        }
        #endif
    }

    private static func titleKey(_ id: UUID) -> String { "alarm.title.\(id.uuidString)" }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func configuration(for item: PlannedAlarm) -> AlarmManager.AlarmConfiguration<PickupAlarmMetadata> {
        let title = LocalizedStringResource(String.LocalizationValue(item.title))
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(title: title, stopButton: AlarmButton(text: LocalizedStringResource(String.LocalizationValue(L10n.t("Aus", "Stop"))), textColor: .white, systemImageName: "stop.circle"))
        }
        let attributes = AlarmAttributes<PickupAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: Color(red: 0.18, green: 0.55, blue: 0.34))
        return .alarm(schedule: .fixed(item.fireDate), attributes: attributes)
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct PickupAlarmMetadata: AlarmMetadata {}
#endif
