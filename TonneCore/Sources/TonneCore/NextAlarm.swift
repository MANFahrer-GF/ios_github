import Foundation

/// Nächster Wecker für die Einstellungen (Thomas 19.11.2026: man sah nicht, ob und wann der Wecker klingelt).
public enum NextAlarm {
    /// Ein Wecker, wie AlarmKit ihn meldet: fester Zeitpunkt (nil = kein fester), noch geplant oder schon gelaufen.
    public struct Item: Equatable {
        public let id: UUID
        public let date: Date?
        public let isScheduled: Bool
        public init(id: UUID, date: Date?, isScheduled: Bool) { self.id = id; self.date = date; self.isScheduled = isScheduled }
    }

    /// Der früheste noch geplante Wecker mit festem Zeitpunkt.
    public static func pick(_ items: [Item]) -> (id: UUID, date: Date)? {
        items.compactMap { item in item.isScheduled ? item.date.map { (item.id, $0) } : nil }.min { $0.1 < $1.1 }
    }

    /// „Fr., 27. Nov., 20:00 · Restmüll rausstellen“ – mit Datum, weil bis zu zwei Wochen voraus geplant wird.
    public static func text(date: Date, title: String?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        style.calendar = Calendar(identifier: .gregorian)
        let when = date.formatted(style)
        guard let title, !title.isEmpty else { return when }
        return when + " · " + title
    }
}
