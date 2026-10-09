import Foundation

/// Wiederholungsregel für eigene Termine (TÜV, Rauchmelder, Hochzeitstag …).
public enum Recurrence: Hashable, Codable {
    case once
    case everyWeeks(Int)
    case everyMonths(Int)
    case yearly
    /// Jeden Monat am selben Wochentag, z. B. „jeden 1. Montag“. `ordinal` 1…4 oder -1 = letzter; `weekday` 1 = Sonntag … 7 = Samstag.
    case monthlyWeekday(ordinal: Int, weekday: Int)

    /// Die Regel „jeden n-ten Wochentag im Monat“, die zu diesem Datum passt; der 5. Wochentag gilt als „letzter“.
    public static func monthlyWeekday(matching date: Date, calendar: Calendar = .current) -> Recurrence {
        let day = calendar.component(.day, from: date)
        let ordinal = (day - 1) / 7 + 1
        return .monthlyWeekday(ordinal: ordinal > 4 ? -1 : ordinal, weekday: calendar.component(.weekday, from: date))
    }

    public var label: String {
        switch self {
        case .once: return L10n.t("Einmalig", "Once")
        case .everyWeeks(let n): return n == 1 ? L10n.t("Jede Woche", "Every week") : L10n.t("Alle \(n) Wochen", "Every \(n) weeks")
        case .everyMonths(let n): return n == 1 ? L10n.t("Jeden Monat", "Every month") : (n == 12 ? L10n.t("Jedes Jahr", "Every year") : L10n.t("Alle \(n) Monate", "Every \(n) months"))
        case .yearly: return L10n.t("Jedes Jahr", "Every year")
        case .monthlyWeekday(let ordinal, let weekday):
            let names = L10n.t("Sonntag,Montag,Dienstag,Mittwoch,Donnerstag,Freitag,Samstag", "Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday").split(separator: ",").map(String.init)
            let name = names[(max(1, min(7, weekday)) - 1)]
            if ordinal < 0 { return L10n.t("Jeden letzten \(name) im Monat", "Last \(name) of every month") }
            let english = ["first", "second", "third", "fourth"][max(1, min(4, ordinal)) - 1]
            return L10n.t("Jeden \(ordinal). \(name) im Monat", "Every \(english) \(name) of the month")
        }
    }

    /// Alle Vorkommen ab `start` im Zeitraum `from...to`.
    public func occurrences(start: Date, from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        guard fromDay <= toDay, startDay <= toDay else { return [] }
        var result: [Date] = []
        // Jedes Vorkommen wird vom Start aus berechnet (Start + k × Abstand). So rutscht ein Termin am 31.
        // nach einem kurzen Monat nicht dauerhaft auf den 28., und der 29. Februar bleibt in Schaltjahren erhalten.
        for k in 0..<5000 {
            let current: Date
            switch self {
            case .once:
                current = startDay
            case .everyWeeks(let n):
                current = Days.add(max(1, n) * 7 * k, to: startDay, calendar: calendar)
            case .everyMonths(let n):
                guard let date = calendar.date(byAdding: .month, value: max(1, n) * k, to: startDay) else { return result }
                current = date
            case .yearly:
                guard let date = calendar.date(byAdding: .year, value: k, to: startDay) else { return result }
                current = date
            case .monthlyWeekday(let ordinal, let weekday):
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: startDay)),
                      let month = calendar.date(byAdding: .month, value: k, to: monthStart),
                      let date = Self.weekday(weekday, ordinal: ordinal, in: month, calendar: calendar) else { return result }
                // Im Startmonat kann der passende Wochentag vor dem ersten Termin liegen
                if date < startDay { continue }
                current = date
            }
            if current > toDay { break }
            if current >= fromDay { result.append(current) }
            if case .once = self { break }
        }
        return result
    }

    /// Der n-te (bzw. bei -1 letzte) Wochentag im Monat von `month`.
    static func weekday(_ weekday: Int, ordinal: Int, in month: Date, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let days = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        if ordinal < 0 {
            let last = Days.add(days - 1, to: first, calendar: calendar)
            let back = (calendar.component(.weekday, from: last) - weekday + 7) % 7
            return Days.add(-back, to: last, calendar: calendar)
        }
        let forward = (weekday - calendar.component(.weekday, from: first) + 7) % 7
        return Days.add(forward + 7 * (max(1, min(4, ordinal)) - 1), to: first, calendar: calendar)
    }

    public func next(start: Date, from: Date = Date(), calendar: Calendar = .current) -> Date? {
        let horizon = calendar.date(byAdding: .year, value: 3, to: from) ?? from
        return occurrences(start: start, from: from, to: horizon, calendar: calendar).first
    }
}
