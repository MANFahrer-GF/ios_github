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
    ///
    /// Erkannt werden: Kopfzeile (Datum/Abfallart/Hinweis), zusätzliche Spalten mit Wochentag oder laufender Nummer,
    /// mehrere Abfallarten in einer Zeile und das „breite“ Format (Kopfzeile = Abfallarten, darunter Daten).
    /// Das Trennzeichen wird gewählt, mit dem die meisten Termine lesbar sind.
    public static func parse(_ text: String, calendar: Calendar = .current, today: Date = Date()) -> [Pickup] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = clean.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var best: [Pickup] = []
        for separator in [";", "\t", ","] as [Character] {
            let rows = lines.map { split($0, separator: separator).map { $0.trimmingCharacters(in: .whitespaces) } }
            let result = parse(rows: rows, calendar: gregorian, today: today)
            if result.count > best.count { best = result }
        }
        return best
    }

    private enum Column { case date, name, note }

    private static func parse(rows: [[String]], calendar: Calendar, today: Date) -> [Pickup] {
        let dayFirst = prefersDayFirst(rows.flatMap { $0 })
        let read = { (text: String) in date(from: text, calendar: calendar, dayFirst: dayFirst, today: today) }

        // Kopfzeile: erste Zeile ohne Datum mit mindestens zwei Feldern
        var header: [String]? = nil
        var dataRows = rows
        if let first = rows.first, first.filter({ !$0.isEmpty }).count >= 2, !first.contains(where: { read($0) != nil }) {
            header = first
            dataRows = Array(rows.dropFirst())
        }
        var roles: [Int: Column] = [:]
        if let header {
            for (index, title) in header.enumerated() {
                let lower = title.lowercased()
                if ["datum", "date", "abfuhrtag", "termin"].contains(where: lower.contains) { roles[index] = .date }
                else if ["abfallart", "müllart", "abfall", "tonne", "fraktion", "art", "waste", "type", "bin"].contains(where: lower.contains) { roles[index] = .name }
                else if ["hinweis", "notiz", "bemerkung", "note", "info", "kommentar"].contains(where: lower.contains) { roles[index] = .note }
            }
        }

        var result: [Pickup] = []
        var seen = Set<String>()
        func add(_ day: Date, _ rawName: String, _ note: String?) {
            let name = NameCleaner.clean(rawName)
            guard !name.isEmpty, !isFiller(name), read(name) == nil else { return }
            guard seen.insert("\(Days.iso(day, calendar: calendar))|\(name.lowercased())").inserted else { return }
            result.append(Pickup(date: day, name: name, note: note?.isEmpty == false ? note : nil))
        }

        // Breites Format: Spaltenköpfe sind Abfallarten, Zellen sind Termine
        if let header, !roles.values.contains(.date) {
            let dateColumns = header.indices.filter { column in
                !header[column].isEmpty && dataRows.contains { column < $0.count && read($0[column]) != nil }
            }
            if dateColumns.count >= 2 || (dateColumns.count == 1 && !roles.values.contains(.name)) {
                for row in dataRows {
                    for column in dateColumns where column < row.count {
                        if let day = read(row[column]) { add(day, header[column], nil) }
                    }
                }
                return result.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
            }
        }

        for fields in dataRows {
            let dateIndex = roles.first(where: { $0.value == .date }).map(\.key).flatMap { $0 < fields.count && read(fields[$0]) != nil ? $0 : nil }
                ?? fields.firstIndex(where: { read($0) != nil })
            guard let dateIndex, let day = read(fields[dateIndex]) else { continue }
            let noteIndex = roles.first(where: { $0.value == .note })?.key
            let note = noteIndex.flatMap { $0 < fields.count ? fields[$0] : nil }
            if let nameIndex = roles.first(where: { $0.value == .name })?.key, nameIndex < fields.count {
                add(day, fields[nameIndex], note)
                continue
            }
            // Ohne Kopfzeile: erste echte Abfallart; weitere Felder sind weitere Abfallarten, wenn sie als solche erkennbar sind, sonst Hinweis
            let candidates = fields.enumerated()
                .filter { $0.offset != dateIndex && $0.offset != noteIndex && !$0.element.isEmpty && !isFiller($0.element) && read($0.element) == nil }
                .map(\.element)
            guard let first = candidates.first else { continue }
            var notes: [String] = []
            add(day, first, nil)
            for extra in candidates.dropFirst() {
                if WasteCategory.classify(extra) != .other { add(day, extra, nil) } else { notes.append(extra) }
            }
            let joined = ([note].compactMap { $0 } + notes).filter { !$0.isEmpty }.joined(separator: " · ")
            if !joined.isEmpty, let last = result.indices.last, Days.iso(result[last].date, calendar: calendar) == Days.iso(day, calendar: calendar) {
                result[last].note = joined
            }
        }
        return result.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
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

    /// Wochentag, laufende Nummer oder Uhrzeit – keine Abfallart.
    static func isFiller(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,")).lowercased()
        if value.isEmpty || value.allSatisfy({ $0.isNumber }) { return true }
        if value.range(of: #"^\d{1,2}:\d{2}( uhr)?$"#, options: .regularExpression) != nil { return true }
        return weekdays.contains(value)
    }

    private static let weekdays: Set<String> = ["mo", "di", "mi", "do", "fr", "sa", "so", "montag", "dienstag", "mittwoch", "donnerstag",
                                                "freitag", "samstag", "sonnabend", "sonntag", "mon", "tue", "wed", "thu", "fri", "sat", "sun",
                                                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    private static let months: [String: Int] = [
        "jan": 1, "januar": 1, "january": 1, "jänner": 1, "feb": 2, "februar": 2, "february": 2, "mär": 3, "märz": 3, "maerz": 3, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "mai": 5, "may": 5, "jun": 6, "juni": 6, "june": 6, "jul": 7, "juli": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "okt": 10, "oktober": 10, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dez": 12, "dezember": 12, "dec": 12, "december": 12,
    ]

    /// Bei „/“-Daten: Tag zuerst, außer die Datei enthält eindeutig Monat zuerst (zweite Zahl > 12, z. B. US-Excel „10/27/2026“).
    static func prefersDayFirst(_ fields: [String]) -> Bool {
        var dayFirst = false, monthFirst = false
        for field in fields {
            guard let match = field.range(of: #"\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b"#, options: .regularExpression) else { continue }
            let parts = field[match].split(separator: "/").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            if parts[0] > 12 { dayFirst = true }
            if parts[1] > 12 { monthFirst = true }
        }
        return dayFirst || !monthFirst
    }

    /// `07.10.2026`, `7.10.26`, `2026-10-07`, `07-10-2026`, `07/10/2026`, `7. Oktober 2026`, `07. Okt` (ohne Jahr),
    /// jeweils optional mit Wochentag davor („Mi, “, „Mi. “, „Mittwoch “) und Uhrzeit dahinter.
    static func date(from text: String, calendar: Calendar, dayFirst: Bool = true, today: Date = Date()) -> Date? {
        var value = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty, value.count <= 40 else { return nil }
        // ISO mit Uhrzeit: 2026-10-07T00:00:00
        if let t = value.firstIndex(of: "t"), value[..<t].allSatisfy({ $0.isNumber || $0 == "-" }) { value = String(value[..<t]) }
        // Wochentag davor
        if let first = value.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "." }).first, weekdays.contains(String(first)) {
            value = String(value.dropFirst(first.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
        }
        // Uhrzeit dahinter
        value = value.replacingOccurrences(of: #"\s+\d{1,2}:\d{2}(:\d{2})?( uhr)?$"#, with: "", options: .regularExpression)

        var year: Int?, month: Int?, day: Int?
        if let match = value.range(of: #"^(\d{1,2})\.?\s*([a-zäöü]+)\.?\s*(\d{2,4})?$"#, options: .regularExpression), match == value.startIndex..<value.endIndex {
            // „7. Oktober 2026“, „07. Okt“
            let parts = value.split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
            guard parts.count >= 2, let d = Int(parts[0]), let m = months[parts[1]] else { return nil }
            day = d; month = m
            if parts.count >= 3 { year = Int(parts[2]) }
        } else {
            guard value.first?.isNumber == true, value.last?.isNumber == true || value.last == "." else { return nil }
            let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            let allSeparators = value.filter { !$0.isNumber }
            if numbers.count == 3, allSeparators.allSatisfy({ $0 == "-" }), numbers[0] > 999 {
                (year, month, day) = (numbers[0], numbers[1], numbers[2])
            } else if numbers.count == 3, allSeparators.allSatisfy({ $0 == "." || $0 == "-" }) {
                (day, month, year) = (numbers[0], numbers[1], numbers[2])
            } else if numbers.count == 3, allSeparators.allSatisfy({ $0 == "/" }) {
                (day, month, year) = dayFirst ? (numbers[0], numbers[1], numbers[2]) : (numbers[1], numbers[0], numbers[2])
            } else if numbers.count == 2, allSeparators == "..", value.last == "." {
                (day, month) = (numbers[0], numbers[1])            // „07.10.“ ohne Jahr (nicht „2.5“ o. Ä.)
            } else {
                return nil
            }
        }
        guard let d = day, let m = month, (1...12).contains(m), (1...31).contains(d) else { return nil }
        let resolvedYear: Int
        if var y = year {
            if y < 100 { y += 2000 }
            resolvedYear = y
        } else {
            // Ohne Jahr (Excel zeigt „07. Okt“): das Jahr, in dem der Termin am nächsten bei heute liegt (bis 3 Monate zurück)
            let current = calendar.component(.year, from: today)
            let candidate = calendar.date(from: DateComponents(year: current, month: m, day: d)) ?? today
            resolvedYear = candidate < calendar.date(byAdding: .month, value: -3, to: today) ?? today ? current + 1 : current
        }
        guard (2000...2100).contains(resolvedYear),
              let date = calendar.date(from: DateComponents(year: resolvedYear, month: m, day: d)),
              calendar.component(.day, from: date) == d else { return nil }   // 31.02. abweisen
        return calendar.startOfDay(for: date)
    }

    // MARK: - Export

    /// CSV mit Semikolon und UTF-8-BOM (Excel öffnet Umlaute dann richtig).
    public static func build(_ rows: [Row], calendar: Calendar = .current) -> String {
        var lines = [[L10n.t("Datum", "Date"), L10n.t("Müllart", "Waste type"), L10n.t("Hinweis", "Note")].joined(separator: ";")]
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
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d.%02d.%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 2000)
    }

    static func escape(_ value: String) -> String {
        var cleaned = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        // Excel würde „=…“, „+…“, „-…“, „@…“ als Formel ausführen
        if let first = cleaned.first, "=+-@".contains(first) { cleaned = "'" + cleaned }
        if cleaned.contains(";") || cleaned.contains("\"") || cleaned.contains(",") {
            return "\"" + cleaned.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return cleaned
    }
}
