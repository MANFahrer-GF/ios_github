import Foundation

/// Ein Geburtstag oder Jahrestag: Tag und Monat, Jahr optional.
public struct AnnualDate: Hashable, Codable {
    public var day: Int
    public var month: Int
    public var year: Int?

    public init(day: Int, month: Int, year: Int? = nil) {
        self.day = day
        self.month = month
        self.year = year
    }

    public var isValid: Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        return day <= 31 && Days.make(year: year ?? 2000, month: month, day: day) != nil
    }

    /// Das Datum in einem bestimmten Jahr; der 29. Februar wird in Nicht-Schaltjahren am 28. gefeiert.
    public func occurrence(inYear year: Int, calendar: Calendar = .current) -> Date? {
        var day = self.day
        if month == 2 && day == 29 && !Days.isLeapYear(year) { day = 28 }
        return Days.make(year: year, month: month, day: day, calendar: calendar)
    }

    /// Nächstes Vorkommen ab `from` (heute zählt mit).
    public func next(from: Date = Date(), calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: from)
        let year = calendar.component(.year, from: today)
        if let thisYear = occurrence(inYear: year, calendar: calendar), thisYear >= today { return thisYear }
        return occurrence(inYear: year + 1, calendar: calendar)
    }

    /// Alter bzw. Anzahl Jahre, die an diesem Vorkommen erreicht werden (nil ohne Jahr).
    public func years(on date: Date, calendar: Calendar = .current) -> Int? {
        guard let year else { return nil }
        let value = calendar.component(.year, from: date) - year
        return value >= 0 ? value : nil
    }

    /// Alle Vorkommen im Zeitraum.
    public func occurrences(from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: from)
        let endDay = calendar.startOfDay(for: to)
        let startYear = calendar.component(.year, from: startDay)
        let endYear = calendar.component(.year, from: endDay)
        guard startYear <= endYear else { return [] }
        return (startYear...endYear).compactMap { occurrence(inYear: $0, calendar: calendar) }
            .filter { $0 >= startDay && $0 <= endDay }
    }

    /// Runde Geburtstage (10, 18, 20, 30, …) verdienen eine besondere Erwähnung.
    public static func isMilestone(_ years: Int) -> Bool {
        years == 18 || years == 21 || (years > 0 && years % 10 == 0)
    }

    /// Sternzeichen zum Datum.
    public var zodiac: String {
        switch (month, day) {
        case (3, 21...31), (4, 1...19): return "♈︎ Widder"
        case (4, 20...30), (5, 1...20): return "♉︎ Stier"
        case (5, 21...31), (6, 1...20): return "♊︎ Zwillinge"
        case (6, 21...30), (7, 1...22): return "♋︎ Krebs"
        case (7, 23...31), (8, 1...22): return "♌︎ Löwe"
        case (8, 23...31), (9, 1...22): return "♍︎ Jungfrau"
        case (9, 23...30), (10, 1...22): return "♎︎ Waage"
        case (10, 23...31), (11, 1...21): return "♏︎ Skorpion"
        case (11, 22...30), (12, 1...21): return "♐︎ Schütze"
        case (12, 22...31), (1, 1...19): return "♑︎ Steinbock"
        case (1, 20...31), (2, 1...18): return "♒︎ Wassermann"
        default: return "♓︎ Fische"
        }
    }
}

public enum NameText {
    /// Initialen für Avatare: „Max Mustermann“ → „MM“.
    public static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
