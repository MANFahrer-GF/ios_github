import Foundation
import TonneCore
#if os(iOS)
import UserNotifications
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Liest und schreibt den Widget-Snapshot sowie „Erledigt“-Markierungen in der App-Gruppe.
/// Wird von App, Widget und App Intents gemeinsam genutzt.
enum SnapshotStore {
    static let appGroup = WidgetSnapshot.appGroup
    static let doneKey = "pickup.doneDays"
    static let notificationName = Notification.Name("de.manfahrer.TonneUndTorte.snapshotChanged")

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(WidgetSnapshot.fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? snapshot.encoded() else { return }
        try? data.write(to: url, options: .atomic)
        reloadWidgets()
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - „Erledigt“-Markierungen (Tag als ISO-String)

    static func doneDays() -> Set<String> {
        Set(defaults.stringArray(forKey: doneKey) ?? [])
    }

    static func markDone(dayKey: String) {
        var days = doneDays()
        days.insert(dayKey)
        defaults.set(Array(days).sorted(), forKey: doneKey)
        // Neuer Zeitstempel, außer der Tag war schon erledigt (sonst gälte eine alte Markierung)
        let wasDone = load()?.pickupDays.first(where: { Days.iso($0.date) == dayKey })?.done ?? false
        let at = recordDoneTime(dayKey: dayKey, overwrite: !wasDone)
        clearUndo(dayKey: dayKey)
        #if os(iOS)
        // Erinnerungen für diesen Tag sofort entfernen – auch wenn die App gerade nicht läuft
        let ids = ["evening", "escalation", "morning", "snooze"].map { "waste-\($0)-\(dayKey)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        #endif
        if var snapshot = load() {
            snapshot.pickupDays = snapshot.pickupDays.map { day in
                var copy = day
                if Days.iso(day.date) == dayKey { copy.done = true; copy.doneAt = at }
                return copy
            }
            save(snapshot)
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: notificationName, object: nil) }
    }

    static func clearDone(dayKey: String) {
        var days = doneDays()
        days.remove(dayKey)
        defaults.set(Array(days).sorted(), forKey: doneKey)
    }

    // MARK: - „Erledigt“ zurücknehmen (versehentlich getippt)

    static let undoKey = "pickup.undoDays"

    static func undoDays() -> Set<String> {
        Set(defaults.stringArray(forKey: undoKey) ?? [])
    }

    /// Nimmt die Markierung im Snapshot sofort zurück und merkt den Tag für die App vor.
    static func markUndone(dayKey: String) {
        var done = doneDays()
        done.remove(dayKey)
        defaults.set(Array(done).sorted(), forKey: doneKey)
        clearDoneTime(dayKey: dayKey)
        var undo = undoDays()
        undo.insert(dayKey)
        defaults.set(Array(undo).sorted(), forKey: undoKey)
        if var snapshot = load() {
            snapshot.pickupDays = snapshot.pickupDays.map { day in
                var copy = day
                if Days.iso(day.date) == dayKey { copy.done = false; copy.doneAt = nil }
                return copy
            }
            save(snapshot)
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: notificationName, object: nil) }
    }

    static func clearUndo(dayKey: String) {
        var days = undoDays()
        days.remove(dayKey)
        defaults.set(Array(days).sorted(), forKey: undoKey)
    }

    // MARK: - Zeitpunkt von „Erledigt“ (kurz danach bleibt der Tag zum Zurücknehmen stehen)

    static let doneAtKey = "pickup.doneAt"

    static func doneTimes() -> [String: Date] {
        (defaults.dictionary(forKey: doneAtKey) as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// Merkt, wann der Tag als erledigt markiert wurde, und gibt den Zeitpunkt zurück.
    /// `overwrite: false` behält einen vorhandenen Zeitpunkt (Markierung aus dem Widget, die die App nachträgt).
    @discardableResult
    static func recordDoneTime(dayKey: String, at date: Date = Date(), overwrite: Bool = true) -> Date {
        var times = defaults.dictionary(forKey: doneAtKey) as? [String: Double] ?? [:]
        if !overwrite, let existing = times[dayKey] { return Date(timeIntervalSince1970: existing) }
        let cutoff = Days.iso(Days.add(-14, to: Days.today()))
        times = times.filter { $0.key >= cutoff }
        times[dayKey] = date.timeIntervalSince1970
        defaults.set(times, forKey: doneAtKey)
        return date
    }

    static func clearDoneTime(dayKey: String) {
        var times = defaults.dictionary(forKey: doneAtKey) as? [String: Double] ?? [:]
        times.removeValue(forKey: dayKey)
        defaults.set(times, forKey: doneAtKey)
    }

    // MARK: - „Ist drin“: Tonnen nach der Abfuhr wieder hereingeholt (nur auf diesem Gerät gemerkt)

    static let broughtInKey = "pickup.broughtInDays"
    static let broughtInNotification = Notification.Name("de.manfahrer.TonneUndTorte.broughtIn")

    static func broughtInDays() -> Set<String> {
        Set(defaults.stringArray(forKey: broughtInKey) ?? [])
    }

    static func markBroughtIn(dayKey: String) {
        guard !dayKey.isEmpty else { return }
        // Nur die letzten Tage aufheben – ältere Markierungen braucht niemand mehr
        let cutoff = Days.iso(Days.add(-14, to: Days.today()))
        var days = broughtInDays().filter { $0 >= cutoff }
        days.insert(dayKey)
        defaults.set(Array(days).sorted(), forKey: broughtInKey)
        if var snapshot = load() {
            snapshot.pickupDays = snapshot.pickupDays.map { day in
                var copy = day
                if Days.iso(day.date) == dayKey { copy.broughtIn = true }
                return copy
            }
            save(snapshot)
        }
        #if os(iOS)
        // Erinnerung „wieder reinholen“ für diesen Tag entfernen (geplant und schon angezeigt)
        let ids = ["waste-bringin-\(dayKey)", "waste-bringin-snooze-\(dayKey)"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        #endif
        DispatchQueue.main.async { NotificationCenter.default.post(name: broughtInNotification, object: nil) }
    }
}
