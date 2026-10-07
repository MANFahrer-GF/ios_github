import Foundation

/// Abfuhrtermine als CSV – für Regionen ohne Online-Anbindung: Termine aus einer Tabelle (Excel, Numbers,
/// abgetippter Abfallkalender) importieren oder die eigenen Termine weitergeben.
///
/// Format: `Datum;Abfallart;Hinweis` (Kopfzeile optional). Erkannt werden Semikolon, Komma und Tabulator,
/// Datumsangaben wie `07.10.2026`, `7.10.26` und `2026-10-07` sowie beide Spaltenreihenfolgen
/// (Datum zuerst oder Abfallart zuerst).
public enum PickupCSV {
    public struct Row: Hashable, Sendable {
        public var date: Date
        public var name: String
        public var note: String?

        public init(date: Date, name: String, note: String? = nil) {
            self.date = date; self.name = name; self.note = note
        }
    }

    // MARK: - Import

    /// Liest alle Zeilen mit gültigem Datum und Abfallart. Leere und unlesbare Zeilen werden übersprungen.
    public static func parse(_ text: String, calendar: Calendar = .current) -> [Pickup] {
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = clean.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let separator = detectSeparator(lines.prefix(10)) else { return [] }
        var result: [Pickup] = []
        var seen = Set<String>()
        for line in lines {
            let fields = split(line, separator: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let dateIndex = fields.firstIndex(where: { date(from: $0, calendar: calendar) != nil }),
                  let day = date(from: fields[dateIndex], calendar: calendar) else { continue }
            let others = fields.enumerated().filter { $0.offset != dateIndex && !$0.element.isEmpty }.map(\.element)
            guard let rawName = others.first else { continue }
            let name = NameCleaner.clean(rawName)
            guard !name.isEmpty else { continue }
            let note = others.dropFirst().joined(separator: " · ")
            let key = "\(Days.iso(day, calendar: calendar))|\(name.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(Pickup(date: day, name: name, note: note.isEmpty ? nil : note))
        }
        return result.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
    }

    /// Das häufigste Trennzeichen außerhalb von Anführungszeichen; Semikolon gewinnt bei Gleichstand (deutsches Excel).
    static func detectSeparator<S: Sequence>(_ lines: S) -> Character? where S.Element == String {
        var counts: [Character: Int] = [";": 0, "\t": 0, ",": 0]
        for line in lines {
            var quoted = false
            for char in line {
                if char == "\"" { quoted.toggle() }
                if !quoted, counts[char] != nil { counts[char, default: 0] += 1 }
            }
        }
        let best = [";", "\t", ","].max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        guard let best, (counts[best] ?? 0) > 0 else { return nil }
        // Gleichstand: das erste in der Liste (Semikolon vor Tab vor Komma)
        return [";", "\t", ","].first { counts[$0] == counts[best] }
    }

    /// Zerlegt eine Zeile; Felder in Anführungszeichen dürfen das Trennzeichen enthalten, `""` steht für `"`.
    static func split(_ line: String, separator: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        let chars = Array(line)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
                    current.append("\""); index += 1
                } else {
                    quoted.toggle()
                }
            } else if char == separator, !quoted {
                fields.append(current); current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        fields.append(current)
        return fields
    }

    /// `07.10.2026`, `7.10.26`, `2026-10-07`, `07/10/2026`; optional mit Wochentag davor („Mi, 07.10.2026“).
    static func date(from text: String, calendar: Calendar) -> Date? {
        var value = text.trimmingCharacters(in: .whitespaces)
        if let comma = value.firstIndex(of: ","), value[..<comma].allSatisfy(\.isLetter) {
            value = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        }
        let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let separators = value.filter { !$0.isNumber }
        guard numbers.count == 3, separators.count == 2, value.first?.isNumber == true, value.last?.isNumber == true else { return nil }
        var year: Int, month: Int, day: Int
        if separators.allSatisfy({ $0 == "-" }), numbers[0] > 999 {
            (year, month, day) = (numbers[0], numbers[1], numbers[2])
        } else if separators.allSatisfy({ $0 == "." || $0 == "/" }) {
            (day, month, year) = (numbers[0], numbers[1], numbers[2])
            if year < 100 { year += 2000 }
        } else {
            return nil
        }
        guard (2000...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }   // 31.02. abweisen
        return calendar.startOfDay(for: date)
    }

    // MARK: - Export

    /// CSV mit Semikolon und UTF-8-BOM (Excel öffnet Umlaute dann richtig).
    public static func build(_ rows: [Row], calendar: Calendar = .current) -> String {
        var lines = [[L10n.t("Datum", "Date"), L10n.t("Abfallart", "Waste type"), L10n.t("Hinweis", "Note")].joined(separator: ";")]
        for row in rows.sorted(by: { ($0.date, $0.name) < ($1.date, $1.name) }) {
            lines.append([germanDate(row.date, calendar: calendar), escape(row.name), escape(row.note ?? "")].joined(separator: ";"))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Vorlage zum Ausfüllen: Kopfzeile und drei Beispielzeilen ab dem nächsten Montag.
    public static func template(from start: Date = Date(), calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: start)
        let weekday = calendar.component(.weekday, from: today)            // 1 = Sonntag
        let monday = calendar.date(byAdding: .day, value: (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7, to: today) ?? today
        let examples: [(Int, String)] = [(0, L10n.t("Restmüll", "Residual waste")), (1, L10n.t("Gelber Sack", "Yellow bag")),
                                         (7, L10n.t("Biotonne", "Organic waste"))]
        return build(examples.map { Row(date: calendar.date(byAdding: .day, value: $0.0, to: monday) ?? monday, name: $0.1) }, calendar: calendar)
    }

    static func germanDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d.%02d.%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 2000)
    }

    static func escape(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        if cleaned.contains(";") || cleaned.contains("\"") || cleaned.contains(",") {
            return "\"" + cleaned.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return cleaned
    }
}
