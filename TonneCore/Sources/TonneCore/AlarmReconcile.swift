import Foundation

/// Zustand eines vorhandenen Weckers (Abbild von AlarmKits `Alarm.State`, damit der Abgleich ohne AlarmKit testbar ist).
public enum AlarmRunState: Hashable {
    case scheduled, countdown, paused, alerting
}

/// Abgleich der vorhandenen Wecker mit dem Plan – als reine Funktionen, die App führt sie nur aus.
public enum AlarmReconcile {
    /// Wecker, die nicht mehr im Plan stehen, werden storniert – nur geplante. Ein Wecker, der gerade klingelt
    /// (oder schlummert/pausiert), gehört dem Nutzer: Der Plan kennt ihn nicht mehr (Weckzeit vorbei), stehen bleibt er trotzdem.
    public static func toCancel(existing: [(id: UUID, state: AlarmRunState)], plan: [PlannedAlarm]) -> [UUID] {
        let planned = Set(plan.map(\.id))
        return existing.filter { !planned.contains($0.id) && $0.state == .scheduled }.map(\.id)
    }

    /// Schlüssel, unter dem der Titel eines geplanten Weckers liegt (erkennt „Titel geändert“ ohne AlarmKit-Abfrage).
    public static let titleKeyPrefix = "alarm.title."
    public static func titleKey(_ id: UUID) -> String { titleKeyPrefix + id.uuidString }

    /// Titel-Schlüssel, deren Wecker weder geplant ist noch stehen bleibt – sonst bliebe je Abholtag einer für immer liegen.
    public static func staleTitleKeys(stored: some Sequence<String>, keeping ids: Set<UUID>) -> [String] {
        let keep = Set(ids.map(titleKey))
        return stored.filter { $0.hasPrefix(titleKeyPrefix) && !keep.contains($0) }.sorted()
    }
}

extension ReminderPlanner {
    /// Fingerabdruck der Termine, aus denen Mitteilungen und Wecker entstehen. Ändert er sich nach einem iCloud-Import
    /// (etwa „Erledigt“ oder „Diesmal nicht“ von einem anderen Gerät), wird neu geplant – sonst klingelte der Wecker trotzdem.
    public static func replanFingerprint(pickups: [PlannedPickup], calendar: Calendar = .current) -> [String] {
        pickups.map { pickup in
            [Days.iso(pickup.date, calendar: calendar), pickup.name, pickup.locationName ?? "",
             pickup.handling.map { "\($0)" } ?? "", "\(pickup.remindersEnabled)", "\(pickup.done)", "\(pickup.skipped)"].joined(separator: "|")
        }.sorted()
    }
}
