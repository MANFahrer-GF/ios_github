import Foundation
import TonneCore
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
        if var snapshot = load() {
            snapshot.pickupDays = snapshot.pickupDays.map { day in
                var copy = day
                if Days.iso(day.date) == dayKey { copy.done = true }
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
        var undo = undoDays()
        undo.insert(dayKey)
        defaults.set(Array(undo).sorted(), forKey: undoKey)
        if var snapshot = load() {
            snapshot.pickupDays = snapshot.pickupDays.map { day in
                var copy = day
                if Days.iso(day.date) == dayKey { copy.done = false }
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
}
