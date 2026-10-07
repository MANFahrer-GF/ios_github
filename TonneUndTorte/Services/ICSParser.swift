import Foundation

/// Ein Termin aus einer ICS-Datei – nur das, was wir brauchen: Titel und Tag.
struct ICSEvent: Hashable {
    let summary: String
    let date: Date
}

/// Minimaler Parser für iCalendar-Dateien (.ics), wie sie viele Abfallwirtschaftsbetriebe
/// zum Download anbieten. Unterstützt DTSTART als DATE oder DATE-TIME (lokal oder UTC)
/// sowie einfache RRULEs (FREQ=DAILY/WEEKLY mit INTERVAL, COUNT, UNTIL).
enum ICSParser {

    static func parse(_ text: String, calendar: Calendar = .current) -> [ICSEvent] {
        let lines = unfold(text)
        var events: [ICSEvent] = []
        var inEvent = false
        var summary = ""
        var dtstart: Date?
        var rrule: String?

        for line in lines {
            if line.hasPrefix("BEGIN:VEVENT") {
                inEvent = true
                summary = ""
                dtstart = nil
                rrule = nil
                continue
            }
            if line.hasPrefix("END:VEVENT") {
                if inEvent, let start = dtstart {
                    let cleanSummary = summary.isEmpty ? "Unbenannt" : summary
                    for date in expand(start: start, rrule: rrule, calendar: calendar) {
                        events.append(ICSEvent(summary: cleanSummary, date: date))
                    }
                }
                inEvent = false
                continue
            }
            guard inEvent else { continue }

            let (key, params, value) = split(line)
            switch key {
            case "SUMMARY":
                summary = unescape(value)
            case "DTSTART":
                dtstart = parseDate(value, params: params, calendar: calendar)
            case "RRULE":
                rrule = value
            default:
                break
            }
        }

        // Duplikate entfernen, stabil sortieren
        var seen = Set<ICSEvent>()
        return events
            .filter { seen.insert($0).inserted }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Hilfsfunktionen

    /// Fasst „gefaltete“ Zeilen (Fortsetzung beginnt mit Leerzeichen/Tab) wieder zusammen.
    private static func unfold(_ text: String) -> [String] {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        for line in raw {
            if let first = line.first, first == " " || first == "\t", !result.isEmpty {
                result[result.count - 1] += line.dropFirst()
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// Zerlegt `KEY;PARAM=X;PARAM2=Y:VALUE` in Schlüssel, Parameter und Wert.
    private static func split(_ line: String) -> (key: String, params: [String: String], value: String) {
        guard let colon = line.firstIndex(of: ":") else { return (line.uppercased(), [:], "") }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])
        let headParts = head.components(separatedBy: ";")
        let key = headParts.first?.uppercased() ?? ""
        var params: [String: String] = [:]
        for part in headParts.dropFirst() {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0].uppercased()] = kv[1]
            }
        }
        return (key, params, value)
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Wandelt `20260107`, `20260107T060000` oder `20260106T230000Z` in einen lokalen Tagesanfang um.
    static func parseDate(_ value: String, params: [String: String] = [:], calendar: Calendar = .current) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 8 else { return nil }
        let digits = trimmed.prefix(8)
        guard let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)) else { return nil }

        var components = DateComponents(year: year, month: month, day: day)

        let isUTC = trimmed.hasSuffix("Z")
        if trimmed.count >= 15, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 8)] == "T" {
            let timePart = trimmed.dropFirst(9).prefix(6)
            components.hour = Int(timePart.prefix(2))
            components.minute = Int(timePart.dropFirst(2).prefix(2))
            components.second = Int(timePart.dropFirst(4).prefix(2))
        } else {
            components.hour = 12
        }

        var cal = calendar
        if isUTC {
            cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        } else if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) {
            cal.timeZone = tz
        }

        guard let date = cal.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Löst eine einfache RRULE in konkrete Tage auf. Ohne RRULE: nur der Starttag.
    private static func expand(start: Date, rrule: String?, calendar: Calendar) -> [Date] {
        guard let rrule, !rrule.isEmpty else { return [start] }

        var fields: [String: String] = [:]
        for part in rrule.components(separatedBy: ";") {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 { fields[kv[0].uppercased()] = kv[1] }
        }

        let interval = max(1, Int(fields["INTERVAL"] ?? "1") ?? 1)
        let stepDays: Int
        switch fields["FREQ"]?.uppercased() {
        case "DAILY": stepDays = interval
        case "WEEKLY": stepDays = 7 * interval
        default: return [start] // MONTHLY/YEARLY u. Ä. unterstützen wir nicht – nur der Starttag.
        }

        let maxCount = min(Int(fields["COUNT"] ?? "") ?? 200, 400)
        let until = fields["UNTIL"].flatMap { parseDate($0, calendar: calendar) }
            ?? calendar.date(byAdding: .year, value: 2, to: start)
            ?? start

        var dates: [Date] = []
        var current = start
        while dates.count < maxCount && current <= until {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: stepDays, to: current) else { break }
            current = next
        }
        return dates
    }

    // MARK: - Zuordnung

    /// Rät anhand des ICS-Titels, welche bekannte Müllart gemeint ist.
    static func guessWasteType(for summary: String, in types: [WasteType]) -> WasteType? {
        let lower = summary.lowercased()
        // Erst exakter Name
        if let exact = types.first(where: { lower.contains($0.name.lowercased()) }) {
            return exact
        }
        let keywords: [(words: [String], preset: WastePreset)] = [
            (["gelb", "wertstoff", "leichtverpack", "lvp", "plastik"], .gelberSack),
            (["bio", "grün", "gruen", "kompost", "organ"], .bio),
            (["papier", "pappe", "karton", "blau"], .papier),
            (["rest", "hausmüll", "hausmuell", "grau", "schwarz"], .restmuell),
            (["glas"], .glas),
            (["sperr"], .sperrmuell),
        ]
        for entry in keywords where entry.words.contains(where: { lower.contains($0) }) {
            if let match = types.first(where: { $0.name.lowercased() == entry.preset.name.lowercased() }) {
                return match
            }
        }
        return nil
    }

    static func guessPreset(for summary: String) -> WastePreset {
        let lower = summary.lowercased()
        if ["gelb", "wertstoff", "leichtverpack", "lvp", "plastik"].contains(where: { lower.contains($0) }) { return .gelberSack }
        if ["bio", "grün", "gruen", "kompost", "organ"].contains(where: { lower.contains($0) }) { return .bio }
        if ["papier", "pappe", "karton", "blau"].contains(where: { lower.contains($0) }) { return .papier }
        if ["rest", "hausmüll", "hausmuell", "grau", "schwarz"].contains(where: { lower.contains($0) }) { return .restmuell }
        if lower.contains("glas") { return .glas }
        if lower.contains("sperr") { return .sperrmuell }
        return .sonstiges
    }
}
