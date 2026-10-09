import Foundation

/// Ein Termin aus einer ICS-Datei: Titel und Tag (Tagesanfang).
public struct ICSEvent: Hashable, Codable {
    public let summary: String
    public let date: Date
    public let location: String?

    public init(summary: String, date: Date, location: String? = nil) {
        self.summary = summary
        self.date = date
        self.location = location
    }
}

/// Minimaler iCalendar-Parser (.ics): DTSTART als DATE oder DATE-TIME (lokal/UTC/TZID),
/// einfache RRULEs (FREQ=DAILY/WEEKLY mit INTERVAL, COUNT, UNTIL) und ein Generator für Feeds.
public enum ICS {

    public static func parse(_ text: String, calendar: Calendar = .current) -> [ICSEvent] {
        var events: [ICSEvent] = []
        var inEvent = false
        var summary = ""
        var location: String?
        var dtstart: Date?
        var rrule: String?

        for line in unfold(text) {
            if line.hasPrefix("BEGIN:VEVENT") {
                inEvent = true; summary = ""; location = nil; dtstart = nil; rrule = nil
                continue
            }
            if line.hasPrefix("END:VEVENT") {
                if inEvent, let start = dtstart {
                    let name = summary.isEmpty ? "Unbenannt" : summary
                    for date in expand(start: start, rrule: rrule, calendar: calendar) {
                        events.append(ICSEvent(summary: name, date: date, location: location))
                    }
                }
                inEvent = false
                continue
            }
            guard inEvent else { continue }
            let (key, params, value) = split(line)
            switch key {
            case "SUMMARY": summary = unescape(value)
            case "LOCATION": location = unescape(value)
            case "DTSTART": dtstart = parseDate(value, params: params, calendar: calendar)
            case "RRULE": rrule = value
            default: break
            }
        }
        var seen = Set<ICSEvent>()
        return events.filter { seen.insert($0).inserted }.sorted {
            $0.date != $1.date ? $0.date < $1.date : $0.summary < $1.summary
        }
    }

    static func unfold(_ text: String) -> [String] {
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

    static func split(_ line: String) -> (key: String, params: [String: String], value: String) {
        guard let colon = line.firstIndex(of: ":") else { return (line.uppercased(), [:], "") }
        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])
        let parts = head.components(separatedBy: ";")
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
        }
        return (parts.first?.uppercased() ?? "", params, value)
    }

    static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `20260107`, `20260107T060000`, `20260106T230000Z` → lokaler Tagesanfang.
    public static func parseDate(_ value: String, params: [String: String] = [:], calendar: Calendar = .current) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 8, let year = Int(trimmed.prefix(4)),
              let month = Int(trimmed.dropFirst(4).prefix(2)),
              let day = Int(trimmed.dropFirst(6).prefix(2)) else { return nil }

        var components = DateComponents(year: year, month: month, day: day)
        let isUTC = trimmed.hasSuffix("Z")
        if trimmed.count >= 15, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 8)] == "T" {
            let time = trimmed.dropFirst(9).prefix(6)
            components.hour = Int(time.prefix(2))
            components.minute = Int(time.dropFirst(2).prefix(2))
            components.second = Int(time.dropFirst(4).prefix(2))
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

    static func expand(start: Date, rrule: String?, calendar: Calendar) -> [Date] {
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
        default: return [start]
        }
        let maxCount = min(Int(fields["COUNT"] ?? "") ?? 200, 400)
        let until = fields["UNTIL"].flatMap { parseDate($0, calendar: calendar) }
            ?? calendar.date(byAdding: .year, value: 2, to: start) ?? start
        var dates: [Date] = []
        var current = start
        while dates.count < maxCount && current <= until {
            dates.append(current)
            current = Days.add(stepDays, to: current, calendar: calendar)
        }
        return dates
    }

    // MARK: - Erzeugen

    public struct FeedEvent {
        public var uid: String
        public var date: Date
        public var summary: String
        public var description: String?
        /// Alarme als Minuten relativ zum Tagesbeginn (negativ = vorher), z. B. -300 = 19:00 Uhr am Vortag.
        public var alarmMinutes: [Int]
        /// Uhrzeit (Minuten ab Mitternacht): dann ein einstündiger Termin zu dieser Ortszeit statt ganztägig.
        public var timeMinutes: Int?

        public init(uid: String, date: Date, summary: String, description: String? = nil, alarmMinutes: [Int] = [], timeMinutes: Int? = nil) {
            self.uid = uid; self.date = date; self.summary = summary; self.description = description; self.alarmMinutes = alarmMinutes; self.timeMinutes = timeMinutes
        }
    }

    public static func build(name: String, events: [FeedEvent], calendar: Calendar = .current) -> String {
        var out = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Tonne und Torte//iOS//DE", "CALSCALE:GREGORIAN", "METHOD:PUBLISH", "X-WR-CALNAME:" + escape(name)]
        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        stampFormatter.timeZone = TimeZone(identifier: "UTC")
        let stamp = stampFormatter.string(from: Date())
        for event in events {
            let day = Days.iso(event.date, calendar: calendar).replacingOccurrences(of: "-", with: "")
            let next = Days.iso(Days.add(1, to: event.date, calendar: calendar), calendar: calendar).replacingOccurrences(of: "-", with: "")
            out += ["BEGIN:VEVENT", "UID:" + event.uid, "DTSTAMP:" + stamp]
            if let time = event.timeMinutes {
                // Ortszeit ohne Zeitzone („floating“): 14:30 bleibt 14:30, wo auch immer der Kalender gerade ist
                // Eine Stunde – bei 23:30 also bis 00:30 am Folgetag
                let end = (time + 60) % 1440
                out += ["DTSTART:" + day + String(format: "T%02d%02d00", time / 60, time % 60),
                        "DTEND:" + (time + 60 >= 1440 ? next : day) + String(format: "T%02d%02d00", end / 60, end % 60)]
            } else {
                out += ["DTSTART;VALUE=DATE:" + day, "DTEND;VALUE=DATE:" + next]
            }
            out.append("SUMMARY:" + escape(event.summary))
            if let description = event.description, !description.isEmpty { out.append("DESCRIPTION:" + escape(description)) }
            out.append(event.timeMinutes == nil ? "TRANSP:TRANSPARENT" : "TRANSP:OPAQUE")
            for minutes in event.alarmMinutes {
                // Bei Terminen mit Uhrzeit beziehen sich Alarme auf den Beginn, nicht auf Mitternacht
                out += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:" + escape(event.summary), "TRIGGER:" + trigger(minutes: minutes - (event.timeMinutes ?? 0)), "END:VALARM"]
            }
            out.append("END:VEVENT")
        }
        out.append("END:VCALENDAR")
        return out.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var pieces: [String] = []
        var current = ""
        for char in line {
            let limit = pieces.isEmpty ? 75 : 74
            if current.utf8.count + String(char).utf8.count > limit {
                pieces.append(current)
                current = ""
            }
            current.append(char)
        }
        pieces.append(current)
        return pieces.joined(separator: "\r\n ")
    }

    /// ISO-8601-Dauer für einen Alarm relativ zum Tagesbeginn: -300 → "-PT5H", 540 → "PT9H".
    public static func trigger(minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : ""
        let abs = Swift.abs(minutes)
        let days = abs / 1440
        let hours = (abs % 1440) / 60
        let mins = abs % 60
        var out = sign + "P"
        if days > 0 { out += "\(days)D" }
        if hours > 0 || mins > 0 || days == 0 {
            out += "T"
            if hours > 0 { out += "\(hours)H" }
            if mins > 0 || (hours == 0 && days == 0) { out += "\(mins)M" }
        }
        return out
    }
}
