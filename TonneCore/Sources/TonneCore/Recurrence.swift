import Foundation

/// Wiederholungsregel für eigene Termine (TÜV, Rauchmelder, Hochzeitstag …).
public enum Recurrence: Hashable, Codable {
    case once
    case everyWeeks(Int)
    case everyMonths(Int)
    case yearly

    public var label: String {
        switch self {
        case .once: return "Einmalig"
        case .everyWeeks(let n): return n == 1 ? "Jede Woche" : "Alle \(n) Wochen"
        case .everyMonths(let n): return n == 1 ? "Jeden Monat" : (n == 12 ? "Jedes Jahr" : "Alle \(n) Monate")
        case .yearly: return "Jedes Jahr"
        }
    }

    /// Alle Vorkommen ab `start` im Zeitraum `from...to`.
    public func occurrences(start: Date, from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        guard fromDay <= toDay, startDay <= toDay else { return [] }
        var result: [Date] = []
        var current = startDay
        var guardCounter = 0
        while current <= toDay && guardCounter < 5000 {
            if current >= fromDay { result.append(current) }
            guardCounter += 1
            switch self {
            case .once:
                return result
            case .everyWeeks(let n):
                current = Days.add(max(1, n) * 7, to: current, calendar: calendar)
            case .everyMonths(let n):
                current = calendar.date(byAdding: .month, value: max(1, n), to: current) ?? toDay.addingTimeInterval(1)
            case .yearly:
                current = calendar.date(byAdding: .year, value: 1, to: current) ?? toDay.addingTimeInterval(1)
            }
        }
        return result
    }

    public func next(start: Date, from: Date = Date(), calendar: Calendar = .current) -> Date? {
        let horizon = calendar.date(byAdding: .year, value: 3, to: from) ?? from
        return occurrences(start: start, from: from, to: horizon, calendar: calendar).first
    }
}
