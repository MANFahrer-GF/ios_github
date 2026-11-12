import Foundation

/// Ein Zeitraum, in dem man für die Tonnen zuständig ist (z. B. wechselnder Dienst in einer Wohnanlage).
/// Die Tage stehen als „2026-10-07“ drin, damit eine Zeitzonen-Änderung sie nicht verschiebt.
public struct DutyPeriod: Codable, Hashable, Identifiable {
    public var id: UUID
    public var startKey: String
    public var endKey: String
    /// Ab dem Startjahr jedes Jahr wieder.
    public var yearly: Bool
    /// Wiederkehrender Dienst („alle 2 Wochen, 1 Woche lang“). `startKey` ist der erste Diensttag, `endKey` der letzte Tag
    /// des ersten Dienstes; `yearly` gilt dann nicht.
    public var rhythm: DutyRhythm?

    public init(id: UUID = UUID(), startKey: String, endKey: String, yearly: Bool, rhythm: DutyRhythm? = nil) {
        self.id = id
        self.startKey = startKey
        self.endKey = endKey
        self.yearly = rhythm == nil ? yearly : false
        self.rhythm = rhythm
    }

    /// Dienst nach Rhythmus ab `start`: Das Ende des ersten Dienstes folgt aus Länge und Einheit.
    public static func rhythm(id: UUID = UUID(), start: Date, _ rhythm: DutyRhythm, calendar: Calendar = .current) -> DutyPeriod {
        let first = Days.start(of: start, calendar: calendar)
        let end = rhythm.block(0, from: first, calendar: calendar).end
        return DutyPeriod(id: id, startKey: Days.iso(first, calendar: calendar), endKey: Days.iso(end, calendar: calendar), yearly: false, rhythm: rhythm)
    }

    private enum CodingKeys: String, CodingKey { case id, startKey, endKey, yearly, rhythm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startKey = try c.decode(String.self, forKey: .startKey)
        endKey = try c.decode(String.self, forKey: .endKey)
        rhythm = try c.decodeIfPresent(DutyRhythm.self, forKey: .rhythm)
        yearly = try c.decodeIfPresent(Bool.self, forKey: .yearly) ?? false
    }

    /// Ein Rhythmus-Eintrag schreibt kein `yearly`. Ältere App-Versionen (bis 2.0.9, z. B. auf einem zweiten Gerät über iCloud)
    /// verlangen das Feld, können die Liste dann nicht lesen und erinnern wie ohne Tonnendienst an jede Abfuhr –
    /// statt den ersten Dienst für den einzigen zu halten und danach gar nicht mehr zu erinnern.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(startKey, forKey: .startKey)
        try c.encode(endKey, forKey: .endKey)
        if let rhythm {
            try c.encode(rhythm, forKey: .rhythm)
        } else {
            try c.encode(yearly, forKey: .yearly)
        }
    }
}

/// „Alle `every` Wochen/Monate, jeweils `length` Wochen/Monate lang“. Gezählt wird ab dem ersten Dienst, nicht nach
/// Kalenderwoche: 2026 hat 53 Wochen, „ungerade KW“ wäre zum Jahreswechsel zwei Wochen hintereinander dran.
public struct DutyRhythm: Codable, Hashable {
    public enum Unit: String, Codable, CaseIterable { case weeks, months }
    public var every: Int
    public var unit: Unit
    public var length: Int

    public init(every: Int, unit: Unit, length: Int = 1) {
        self.every = max(1, every)
        self.unit = unit
        self.length = min(max(1, length), max(1, every))
    }

    private enum CodingKeys: String, CodingKey { case every, unit, length }

    /// Auch Gelesenes geht durch die Grenzen von `init` (ein Abstand von 0 würde durch null teilen).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(every: try c.decode(Int.self, forKey: .every), unit: try c.decode(Unit.self, forKey: .unit),
                  length: try c.decodeIfPresent(Int.self, forKey: .length) ?? 1)
    }

    /// Erster und letzter Tag des `index`-ten Dienstes (0 = erster). Immer vom ersten Dienst aus gerechnet, nicht vom vorigen:
    /// Sonst würde aus dem 31. nach einem Februar dauerhaft der 28. und es blieben Tage ohne Dienst.
    func block(_ index: Int, from first: Date, calendar: Calendar) -> (start: Date, end: Date) {
        (blockStart(index, from: first, calendar: calendar), Days.add(-1, to: offset(index * every + length, from: first, calendar: calendar), calendar: calendar))
    }

    func blockStart(_ index: Int, from first: Date, calendar: Calendar) -> Date {
        offset(index * every, from: first, calendar: calendar)
    }

    private func offset(_ units: Int, from first: Date, calendar: Calendar) -> Date {
        switch unit {
        case .weeks: return Days.add(units * 7, to: first, calendar: calendar)
        case .months: return calendar.date(byAdding: .month, value: units, to: first).map { calendar.startOfDay(for: $0) } ?? first
        }
    }

    /// Index des Dienstes, in dessen Takt `day` fällt (kann negativ sein, wenn `day` vor dem ersten Dienst liegt).
    func index(of day: Date, from first: Date, calendar: Calendar) -> Int {
        switch unit {
        case .weeks:
            let days = Days.between(first, day, calendar: calendar)
            let period = every * 7
            return days >= 0 ? days / period : -((-days + period - 1) / period)
        case .months:
            let months = calendar.dateComponents([.month], from: first, to: day).month ?? 0
            var index = months >= 0 ? months / every : -((-months + every - 1) / every)
            // dateComponents rundet ab; ein Takt, der erst nach `day` beginnt, zählt noch nicht
            while blockStart(index, from: first, calendar: calendar) > day { index -= 1 }
            while blockStart(index + 1, from: first, calendar: calendar) <= day { index += 1 }
            return index
        }
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

    /// Vertagte Müll-Erinnerungen („In 1 Stunde nochmal“) für Tage, an denen man nicht mehr dran ist.
    /// Andere vertagte Erinnerungen, etwa zu eigenen Terminen, bleiben unberührt.
    public static func snoozesOutsideDuty(_ identifiers: [String], offDutyDays: Set<String>) -> [String] {
        identifiers.filter { identifier in
            ["waste-snooze-", "waste-bringin-snooze-"].contains { prefix in
                identifier.hasPrefix(prefix) && offDutyDays.contains(String(identifier.dropFirst(prefix.count)))
            }
        }
    }

    /// Die nächsten `count` Dienste ab `day` (auch der laufende), für die Vorschau beim Eintragen. Überlappende oder direkt
    /// aneinander anschließende Einträge werden zu einem Dienst zusammengefasst, so wie man tatsächlich dran ist.
    public static func upcoming(_ periods: [DutyPeriod], from day: Date, count: Int, calendar: Calendar = .current) -> [(start: Date, end: Date)] {
        let today = calendar.startOfDay(for: day)
        let limit = Days.add(3 * 366, to: today, calendar: calendar)
        var result: [(start: Date, end: Date)] = []
        var probe = today
        // Dienst für Dienst weiter, bis genug beisammen sind (höchstens drei Jahre voraus)
        while result.count < count, probe < limit {
            let near = intervals(of: periods, around: probe, calendar: calendar).filter { $0.end >= probe }
            guard var block = near.min(by: { $0.start < $1.start }) else { break }
            // Alles anhängen, was den Dienst überlappt oder am Folgetag weiterführt
            var grown = true
            while grown {
                grown = false
                let reach = Days.add(1, to: block.end, calendar: calendar)
                let candidates = intervals(of: periods, around: block.end, calendar: calendar) + near
                if let longer = candidates.filter({ $0.start <= reach && $0.end > block.end }).map(\.end).max() {
                    block.end = longer
                    grown = true
                }
            }
            result.append(block)
            probe = Days.add(1, to: block.end, calendar: calendar)
        }
        return result
    }

    /// Die konkreten Von-bis-Tage rund um `day`: das Jahr davor (für Zeiträume über Silvester), dieses und das nächste.
    /// Bei einem Rhythmus der Dienst davor, der laufende Takt und die zwei danach.
    private static func intervals(of periods: [DutyPeriod], around day: Date, calendar: Calendar) -> [(start: Date, end: Date)] {
        let year = calendar.component(.year, from: day)
        return periods.flatMap { period -> [(start: Date, end: Date)] in
            guard let start = Days.parse(period.startKey, calendar: calendar),
                  let end = Days.parse(period.endKey, calendar: calendar), start <= end else { return [] }
            if let rhythm = period.rhythm {
                let index = max(0, rhythm.index(of: day, from: start, calendar: calendar))
                return (max(0, index - 1)...(index + 2)).map { rhythm.block($0, from: start, calendar: calendar) }
            }
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
