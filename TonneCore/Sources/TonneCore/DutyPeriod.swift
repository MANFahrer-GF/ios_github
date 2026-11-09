import Foundation

/// Ein Zeitraum, in dem man für die Tonnen zuständig ist (z. B. wechselnder Dienst in einer Wohnanlage).
/// Die Tage stehen als „2026-10-07“ drin, damit eine Zeitzonen-Änderung sie nicht verschiebt.
public struct DutyPeriod: Codable, Hashable, Identifiable {
    public var id: UUID
    public var startKey: String
    public var endKey: String
    /// Ab dem Startjahr jedes Jahr wieder.
    public var yearly: Bool

    public init(id: UUID = UUID(), startKey: String, endKey: String, yearly: Bool) {
        self.id = id
        self.startKey = startKey
        self.endKey = endKey
        self.yearly = yearly
    }
}

public enum DutyStatus: Equatable {
    /// Keine Zeiträume eingetragen: bei jeder Abfuhr zuständig.
    case always
    case onDuty(until: Date)
    case upcoming(from: Date)
    /// Alle Zeiträume sind vorbei: Es kommt keine Erinnerung mehr.
    case ended
}

/// Beantwortet für alle Stellen gleich, ob man an einem Tag zuständig ist.
public enum DutySchedule {
    public static func decode(_ json: String) -> [DutyPeriod] {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DutyPeriod].self, from: data)) ?? []
    }

    public static func encode(_ periods: [DutyPeriod]) -> String {
        guard !periods.isEmpty, let data = try? JSONEncoder().encode(periods) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func isOnDuty(on date: Date, periods: [DutyPeriod], calendar: Calendar = .current) -> Bool {
        guard !periods.isEmpty else { return true }
        let day = calendar.startOfDay(for: date)
        return intervals(of: periods, around: day, calendar: calendar).contains { $0.start <= day && day <= $0.end }
    }

    public static func status(of periods: [DutyPeriod], today: Date, calendar: Calendar = .current) -> DutyStatus {
        guard !periods.isEmpty else { return .always }
        let day = calendar.startOfDay(for: today)
        let all = intervals(of: periods, around: day, calendar: calendar)
        if let until = all.filter({ $0.start <= day && day <= $0.end }).map(\.end).max() { return .onDuty(until: until) }
        if let from = all.filter({ $0.start > day }).map(\.start).min() { return .upcoming(from: from) }
        return .ended
    }

    /// Die konkreten Von-bis-Tage rund um `day`: das Jahr davor (für Zeiträume über Silvester), dieses und das nächste.
    private static func intervals(of periods: [DutyPeriod], around day: Date, calendar: Calendar) -> [(start: Date, end: Date)] {
        let year = calendar.component(.year, from: day)
        return periods.flatMap { period -> [(start: Date, end: Date)] in
            guard let start = Days.parse(period.startKey, calendar: calendar),
                  let end = Days.parse(period.endKey, calendar: calendar), start <= end else { return [] }
            guard period.yearly else { return [(start, end)] }
            let startYear = calendar.component(.year, from: start)
            return (max(0, year - startYear - 1)...max(0, year - startYear + 1)).compactMap { offset in
                // byAdding macht aus dem 29. Februar in Nicht-Schaltjahren den 28.
                guard let shiftedStart = calendar.date(byAdding: .year, value: offset, to: start),
                      let shiftedEnd = calendar.date(byAdding: .year, value: offset, to: end) else { return nil }
                return (shiftedStart, shiftedEnd)
            }
        }
    }
}
