import Foundation

/// Export von Geburtstagen als CSV (Excel-tauglich) – Datenaufbereitung auch für das PDF.
public enum BirthdayExport {
    public struct Row: Hashable {
        public var name: String
        public var annual: AnnualDate
        public var notes: String
        public var giftIdeas: [String]
        public var phone: String?
        public var remindersEnabled: Bool
        public var remindDaysBefore: Int

        public init(name: String, annual: AnnualDate, notes: String = "", giftIdeas: [String] = [], phone: String? = nil, remindersEnabled: Bool = true, remindDaysBefore: Int = 1) {
            self.name = name; self.annual = annual; self.notes = notes; self.giftIdeas = giftIdeas; self.phone = phone; self.remindersEnabled = remindersEnabled; self.remindDaysBefore = remindDaysBefore
        }
    }

    /// Zeilen sortiert nach dem nächsten Geburtstag.
    public static func sorted(_ rows: [Row], from: Date = Date(), calendar: Calendar = .current) -> [Row] {
        rows.sorted { ($0.annual.next(from: from, calendar: calendar) ?? .distantFuture) < ($1.annual.next(from: from, calendar: calendar) ?? .distantFuture) }
    }

    /// „07.10.1948“ bzw. „07.10.“ ohne Jahr.
    public static func dateString(_ annual: AnnualDate) -> String {
        if let year = annual.year { return String(format: "%02d.%02d.%04d", annual.day, annual.month, year) }
        return String(format: "%02d.%02d.", annual.day, annual.month)
    }

    /// CSV mit Semikolon (deutsches Excel) und UTF-8-BOM, damit Umlaute in Excel stimmen.
    public static func csv(_ rows: [Row], from: Date = Date(), calendar: Calendar = .current) -> String {
        let header = [
            L10n.t("Name", "Name"), L10n.t("Geburtstag", "Birthday"), L10n.t("Geburtsjahr", "Birth year"), L10n.t("Alter", "Age"),
            L10n.t("Nächster Geburtstag", "Next birthday"), L10n.t("Tage bis", "Days until"), L10n.t("Wird", "Turns"), L10n.t("Sternzeichen", "Zodiac"),
            L10n.t("Erinnerung", "Reminder"), L10n.t("Tage vorher", "Days before"), L10n.t("Geschenkideen", "Gift ideas"), L10n.t("Telefon", "Phone"), L10n.t("Notizen", "Notes"),
        ]
        var lines = [header.map(escape).joined(separator: ";")]
        for row in sorted(rows, from: from, calendar: calendar) {
            let next = row.annual.next(from: from, calendar: calendar)
            let fields: [String] = [
                row.name,
                dateString(row.annual),
                row.annual.year.map(String.init) ?? "",
                currentAge(row.annual, from: from, calendar: calendar).map(String.init) ?? "",
                next.map { Days.iso($0, calendar: calendar) } ?? "",
                next.map { String(Days.between(from, $0, calendar: calendar)) } ?? "",
                next.flatMap { row.annual.years(on: $0, calendar: calendar) }.map(String.init) ?? "",
                row.annual.zodiac,
                row.remindersEnabled ? L10n.t("ja", "yes") : L10n.t("nein", "no"),
                String(row.remindDaysBefore),
                row.giftIdeas.joined(separator: ", "),
                row.phone ?? "",
                row.notes,
            ]
            lines.append(fields.map(escape).joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Aktuelles Alter (vollendete Jahre) oder nil ohne Geburtsjahr.
    public static func currentAge(_ annual: AnnualDate, from: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let year = annual.year else { return nil }
        let today = calendar.startOfDay(for: from)
        let thisYear = calendar.component(.year, from: today)
        guard let birthdayThisYear = annual.occurrence(inYear: thisYear, calendar: calendar) else { return nil }
        return thisYear - year - (birthdayThisYear > today ? 1 : 0)
    }

    static func escape(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        if cleaned.contains(";") || cleaned.contains("\"") || cleaned.contains(",") {
            return "\"" + cleaned.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return cleaned
    }
}
