import Foundation

/// Wiederholungsregel für eigene Termine (TÜV, Rauchmelder, Hochzeitstag …).
public enum Recurrence: Hashable, Codable {
    case once
    case everyWeeks(Int)
    case everyMonths(Int)
    case yearly

    public var label: String {
        switch self {
        case .once: return L10n.t("Einmalig", "Once")
        case .everyWeeks(let n): return n == 1 ? L10n.t("Jede Woche", "Every week") : L10n.t("Alle \(n) Wochen", "Every \(n) weeks")
        case .everyMonths(let n): return n == 1 ? L10n.t("Jeden Monat", "Every month") : (n == 12 ? L10n.t("Jedes Jahr", "Every year") : L10n.t("Alle \(n) Monate", "Every \(n) months"))
        case .yearly: return L10n.t("Jedes Jahr", "Every year")
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
            }
            if current > toDay { break }
            if current >= fromDay { result.append(current) }
            if case .once = self { break }
        }
        return result
    }

    public func next(start: Date, from: Date = Date(), calendar: Calendar = .current) -> Date? {
        let horizon = calendar.date(byAdding: .year, value: 3, to: from) ?? from
        return occurrences(start: start, from: from, to: horizon, calendar: calendar).first
    }
}
