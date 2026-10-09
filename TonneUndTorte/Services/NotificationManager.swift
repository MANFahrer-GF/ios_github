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
    static let callAction = "BIRTHDAY_CALL"
    static let messageAction = "BIRTHDAY_MESSAGE"
    static let bringInAction = "PICKUP_BROUGHT_IN"
    static let customDoneAction = "CUSTOM_DONE"

    /// Was ein Tipp auf eine Geburtstags- oder Termin-Mitteilung öffnet.
    enum OpenTarget { case birthdays, person(UUID), event(UUID) }

    /// Wird aufgerufen, wenn der Nutzer in einer Mitteilung „Erledigt“ tippt (dayKey).
    var onPickupDone: ((String) -> Void)?
    /// „Erledigt“ bei einem eigenen Termin (Termin-ID, Tag).
    var onCustomDone: ((UUID, String) -> Void)?
    /// Kann beim Kaltstart aus einer Mitteilung erst nach dem Tipp gesetzt werden – das Ziel wird dann nachgereicht.
    var onOpen: ((OpenTarget) -> Void)? {
        didSet { if let target = pendingOpen, let onOpen { pendingOpen = nil; onOpen(target) } }
    }
    private var pendingOpen: OpenTarget?

    private func open(_ target: OpenTarget) {
        if let onOpen { onOpen(target) } else { pendingOpen = target }
    }

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        let done = UNNotificationAction(identifier: NotificationManager.doneAction, title: L10n.t("✅ Erledigt – steht draußen", "✅ Done – it's out"), options: [])
        let snooze = UNNotificationAction(identifier: NotificationManager.snoozeAction, title: L10n.t("⏰ In 1 Stunde nochmal", "⏰ Remind me in 1 hour"), options: [])
        let waste = UNNotificationCategory(identifier: "WASTE", actions: [done, snooze], intentIdentifiers: [], options: [])
        let inside = UNNotificationAction(identifier: NotificationManager.bringInAction, title: L10n.t("✅ Ist drin", "✅ It's in"), options: [])
        let later = UNNotificationAction(identifier: NotificationManager.snoozeAction, title: L10n.t("⏰ In 1 Stunde nochmal", "⏰ Remind me in 1 hour"), options: [])
        let bringIn = UNNotificationCategory(identifier: "WASTE_BRINGIN", actions: [inside, later], intentIdentifiers: [], options: [])
        // Geburtstag: „Anrufen“ nur, wenn eine Nummer hinterlegt ist; mehrere Personen in einer Mitteilung bekommen keine Knöpfe
        let call = UNNotificationAction(identifier: NotificationManager.callAction, title: L10n.t("📞 Anrufen", "📞 Call"), options: [.foreground])
        let message = UNNotificationAction(identifier: NotificationManager.messageAction, title: L10n.t("💬 Glückwunsch schreiben", "💬 Send wishes"), options: [.foreground])
        let gift = UNNotificationAction(identifier: NotificationManager.giftAction, title: L10n.t("🎁 Geschenkideen ansehen", "🎁 View gift ideas"), options: [.foreground])
        let birthdayPhone = UNNotificationCategory(identifier: "BIRTHDAY_PHONE", actions: [call, message], intentIdentifiers: [], options: [])
        let birthday = UNNotificationCategory(identifier: "BIRTHDAY", actions: [message], intentIdentifiers: [], options: [])
        let birthdayPre = UNNotificationCategory(identifier: "BIRTHDAY_PRE", actions: [gift], intentIdentifiers: [], options: [])
        let birthdayGroup = UNNotificationCategory(identifier: "BIRTHDAY_MULTI", actions: [], intentIdentifiers: [], options: [])
        let customDone = UNNotificationAction(identifier: NotificationManager.customDoneAction, title: L10n.t("✅ Erledigt", "✅ Done"), options: [])
        let customLater = UNNotificationAction(identifier: NotificationManager.snoozeAction, title: L10n.t("⏰ In 1 Stunde nochmal", "⏰ Remind me in 1 hour"), options: [])
        let custom = UNNotificationCategory(identifier: "CUSTOM", actions: [customDone, customLater], intentIdentifiers: [], options: [])
        center.setNotificationCategories([waste, bringIn, birthdayPhone, birthday, birthdayPre, birthdayGroup, custom])
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
        // Alles Geplante ersetzen – nur „In 1 Stunde nochmal“ bleibt, das ist eine Bitte des Nutzers
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !$0.contains("-snooze-") })
        // Die bleibenden „In 1 Stunde nochmal“ zählen beim iOS-Limit (64) mit
        let snoozed = pending.filter { $0.contains("-snooze-") }.count
        for item in plan.prefix(max(0, maxRequests - snoozed)) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.threadIdentifier
            var info: [String: String] = ["dayKey": item.dayKey, "category": item.category.rawValue]
            info["targetID"] = item.targetID
            info["name"] = item.personName
            info["phone"] = item.phone
            content.userInfo = info
            switch item.category {
            case .wasteEvening, .wasteMorning, .wasteEscalation:
                content.categoryIdentifier = "WASTE"
                content.interruptionLevel = item.category == .wasteEscalation ? .timeSensitive : .active
            case .wasteBringIn:
                content.categoryIdentifier = "WASTE_BRINGIN"
            case .birthday:
                content.categoryIdentifier = item.targetID == nil ? "BIRTHDAY_MULTI" : (item.phone == nil ? "BIRTHDAY" : "BIRTHDAY_PHONE")
            case .birthdayPre:
                content.categoryIdentifier = item.targetID == nil ? "BIRTHDAY_MULTI" : "BIRTHDAY_PRE"
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

    /// Nachrichten-App mit vorbereitetem Glückwunsch – mit Empfänger, wenn eine Nummer bekannt ist.
    nonisolated static func greetingURL(name: String, phone: String?) -> URL? {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let text = L10n.t("Alles Gute zum Geburtstag, \(first)! 🎂🎉", "Happy birthday, \(first)! 🎂🎉")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let phone, !phone.isEmpty {
            return URL(string: "sms:\(phone.filter { "+0123456789".contains($0) })&body=\(encoded)")
        }
        return URL(string: "sms:&body=\(encoded)")
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = L10n.t("Morgen: Gelber Sack", "Tomorrow: Yellow bag")
        content.body = L10n.t("So sieht eine Erinnerung von Tonne & Torte aus. 🎉", "This is what a Tonne & Torte reminder looks like. 🎉")
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
        let category = userInfo["category"] as? String ?? ""
        let targetID = (userInfo["targetID"] as? String).flatMap(UUID.init(uuidString:))
        switch response.actionIdentifier {
        case NotificationManager.callAction:
            let digits = (userInfo["phone"] as? String ?? "").filter { "+0123456789".contains($0) }
            if let url = URL(string: "tel:\(digits)") { await MainActor.run { UIApplication.shared.open(url) } }
        case NotificationManager.messageAction:
            if let url = NotificationManager.greetingURL(name: userInfo["name"] as? String ?? "", phone: userInfo["phone"] as? String) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
        case NotificationManager.giftAction:
            if let targetID { await MainActor.run { self.open(.person(targetID)) } }
        case UNNotificationDefaultActionIdentifier where category == PlannedNotification.Category.birthday.rawValue || category == PlannedNotification.Category.birthdayPre.rawValue:
            await MainActor.run { self.open(targetID.map { .person($0) } ?? .birthdays) }
        case UNNotificationDefaultActionIdentifier where category == PlannedNotification.Category.custom.rawValue:
            if let targetID { await MainActor.run { self.open(.event(targetID)) } }
        case NotificationManager.customDoneAction:
            // Der Knopf startet die App nur im Hintergrund – dort gibt es evtl. noch kein App-Modell. Darum hier selbst
            // speichern und die übrigen Mitteilungen dieses Termins an diesem Tag entfernen; das Modell plant danach neu.
            guard let targetID else { break }
            await MainActor.run { SettingsKeys.setCustomDone(true, id: targetID, dayKey: dayKey) }
            let suffix = "-\(dayKey)-\(targetID.uuidString)"
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("custom") && $0.hasSuffix(suffix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            await MainActor.run { self.onCustomDone?(targetID, dayKey) }
        case NotificationManager.doneAction:
            await MainActor.run {
                SnapshotStore.markDone(dayKey: dayKey)
                self.onPickupDone?(dayKey)
            }
        case NotificationManager.bringInAction:
            await MainActor.run { SnapshotStore.markBroughtIn(dayKey: dayKey) }
        case NotificationManager.snoozeAction:
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let originalCategory = response.notification.request.content.categoryIdentifier
            content.categoryIdentifier = originalCategory
            content.userInfo = userInfo
            let identifier: String
            switch originalCategory {
            case "WASTE_BRINGIN": identifier = "waste-bringin-snooze-\(dayKey)"
            case "CUSTOM": identifier = "custom-snooze-\(dayKey)-\(targetID?.uuidString ?? "")"
            default: identifier = "waste-snooze-\(dayKey)"
            }
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false))
            try? await center.add(request)
        default:
            break
        }
    }
}
