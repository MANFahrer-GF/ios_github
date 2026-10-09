import Foundation

/// Eigene Termine als CSV (Excel) – Gegenstück zu `BirthdayExport`.
public enum CustomEventExport {
    public struct Row: Hashable {
        public var title: String
        public var recurrence: String
        public var start: Date
        public var timeMinutes: Int?
        public var next: Date?
        public var remindersEnabled: Bool
        public var remindDaysBefore: Int
        public var notes: String

        public init(title: String, recurrence: String, start: Date, timeMinutes: Int?, next: Date?, remindersEnabled: Bool, remindDaysBefore: Int, notes: String) {
            self.title = title; self.recurrence = recurrence; self.start = start; self.timeMinutes = timeMinutes; self.next = next
            self.remindersEnabled = remindersEnabled; self.remindDaysBefore = remindDaysBefore; self.notes = notes
        }

        public var timeText: String { timeMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? "" }
    }

    /// Nach nächstem Termin sortiert; Termine ohne weiteres Vorkommen ans Ende.
    public static func sorted(_ rows: [Row]) -> [Row] {
        rows.sorted { ($0.next ?? .distantFuture, $0.title) < ($1.next ?? .distantFuture, $1.title) }
    }

    public static func csv(_ rows: [Row], from: Date = Date(), calendar: Calendar = .current) -> String {
        let header = [
            L10n.t("Termin", "Event"), L10n.t("Wiederholung", "Repeats"), L10n.t("Erster Termin", "First date"), L10n.t("Uhrzeit", "Time"),
            L10n.t("Nächster Termin", "Next date"), L10n.t("Tage bis", "Days until"), L10n.t("Erinnerung", "Reminder"),
            L10n.t("Tage vorher", "Days before"), L10n.t("Notizen", "Notes"),
        ]
        var lines = [header.map(BirthdayExport.escape).joined(separator: ";")]
        for row in sorted(rows) {
            let fields: [String] = [
                row.title, row.recurrence, Days.iso(row.start, calendar: calendar), row.timeText,
                row.next.map { Days.iso($0, calendar: calendar) } ?? "",
                row.next.map { String(Days.between(from, $0, calendar: calendar)) } ?? "",
                row.remindersEnabled ? L10n.t("ja", "yes") : L10n.t("nein", "no"),
                String(row.remindDaysBefore), row.notes,
            ]
            lines.append(fields.map(BirthdayExport.escape).joined(separator: ";"))
        }
        // BOM, damit Excel die Umlaute richtig liest – wie beim Geburtstags-Export
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}
