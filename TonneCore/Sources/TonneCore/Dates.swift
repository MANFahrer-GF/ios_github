import Foundation

/// Hilfsfunktionen rund um Kalendertage. Alle Termine werden als Tagesanfang (00:00 Uhr)
/// im jeweiligen Kalender gespeichert, damit Vergleiche und Set-Operationen stabil sind.
public enum Days {
    public static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func today(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: Date())
    }

    public static func add(_ days: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func between(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// Tage bis zu einem Datum, gezählt ab heute (negativ für vergangene Tage).
    public static func until(_ date: Date, calendar: Calendar = .current) -> Int {
        between(today(calendar: calendar), date, calendar: calendar)
    }

    /// „2026-10-07“ → Tagesanfang, nil bei ungültigem Format.
    public static func parse(_ iso: String, calendar: Calendar = .current) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard parts[1] >= 1, parts[1] <= 12, parts[2] >= 1, parts[2] <= 31,
              let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Tagesanfang → „2026-10-07“
    public static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func make(year: Int, month: Int, day: Int, calendar: Calendar = .current) -> Date? {
        parse(String(format: "%04d-%02d-%02d", year, month, day), calendar: calendar)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Uhrzeit (Minuten seit Mitternacht) an einem Tag.
    public static func at(minutes: Int, on day: Date, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return calendar.date(from: components)
    }
}

/// Relative Beschriftungen wie „Heute“, „Morgen“, „in 5 Tagen“.
public enum DateText {
    public static func countdown(_ date: Date, calendar: Calendar = .current) -> String {
        let diff = Days.until(date, calendar: calendar)
        switch diff {
        case 0: return L10n.t("Heute", "Today")
        case 1: return L10n.t("Morgen", "Tomorrow")
        case 2: return L10n.t("Übermorgen", "In 2 days")
        case -1: return L10n.t("Gestern", "Yesterday")
        case ..<0: return L10n.t("vor \(-diff) Tagen", "\(-diff) days ago")
        default: return L10n.t("in \(diff) Tagen", "in \(diff) days")
        }
    }

    public static func short(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    public static func long(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    public static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    public static func time(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
