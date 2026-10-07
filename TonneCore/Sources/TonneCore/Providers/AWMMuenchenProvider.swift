import Foundation

/// AWM München (Abfallwirtschaftsbetrieb München): TYPO3-Formular „Abfuhrkalender“ auf awm-muenchen.de.
/// Ablauf wie im Browser: Straße + Hausnummer absenden, je nach Adresse Stellplatz und/oder
/// Leerungszyklus je Tonne wählen (eigene Listenschritte), dann die ICS-Links der Ergebnisseite laden
/// (mit cHash, daher nicht selbst baubar). Die Straßenliste steht inline auf der Seite.
/// Das Formular arbeitet ohne Sitzung: jeder Schritt spielt den Ablauf von vorn ab.
public struct AWMMuenchenProvider: WasteProvider {
    public let kind: ProviderKind = .awmMuenchen
    public let serviceKey: String
    public var displayName: String { kind.displayName }
    private let client: HTTPClient

    static let base = "https://www.awm-muenchen.de"
    static let pageURL = base + "/abfall-entsorgen/muelltonnen/abfuhrkalender"
    static let prefix = "tx_awmabfuhrkalender_abfuhrkalender"

    public init(service: String = "muenchen", client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.pageURL)
            let streets = Self.streets(in: html)
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets)
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 1 oder 10a", "e.g. 1 or 10a"))
        default:
            switch try await run(selections) {
            case .choice(let step): return step
            case .calendar: return nil
            }
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard case .calendar(let links) = try await run(selections) else {
            throw ProviderError.invalidSelection(L10n.t("Bitte Stellplatz bzw. Leerungszyklus neu wählen.", "Please choose the bin location or collection cycle again."))
        }
        var byKey: [String: Pickup] = [:]
        for link in links {
            let text = try await client.string(link)
            for pickup in Self.parseICS(text, calendar: calendar) {
                let key = Days.iso(pickup.date, calendar: calendar) + "|" + pickup.name
                if byKey[key] == nil || byKey[key]?.note != nil { byKey[key] = pickup }
            }
        }
        guard !byKey.isEmpty else { throw ProviderError.noDataGeneric }
        return byKey.values.sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        let address = selections.prefix(2).map(\.title).filter { !$0.isEmpty }.joined(separator: " ")
        return address.isEmpty ? "München" : "München, " + address
    }

    // MARK: - Formularablauf

    private enum Outcome {
        case choice(SelectionStep)
        case calendar([String])
    }

    /// Spielt das Formular mit Adresse und den bisherigen Zusatzauswahlen durch. Zusatzschritte tragen
    /// als ID „Feld|Wert“ (Feld ohne Plugin-Präfix, z. B. `[leerungszyklus][R]|001;U`).
    private func run(_ selections: [SelectionOption]) async throws -> Outcome {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let street = selections[0].id
        let number = selections[1].title.replacingOccurrences(of: " ", with: "")
        guard !number.isEmpty else {
            throw ProviderError.invalidSelection(L10n.t("Bitte eine Hausnummer eingeben.", "Please enter a house number."))
        }
        var answers: [String: String] = [:]
        for option in selections.dropFirst(2) {
            let parts = option.id.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { answers[Self.prefix + parts[0]] = parts[1] }
        }

        let start = try await client.string(Self.pageURL)
        guard var form = Self.form(in: start) else { throw ProviderError.noDataGeneric }
        var fields = form.fields
        Self.set(Self.prefix + "[strasse]", street, in: &fields)
        Self.set(Self.prefix + "[hausnummer]", number, in: &fields)

        // Höchstens Adresse → Stellplatz → Leerungszyklus → Ergebnis
        for _ in 0..<4 {
            let data = try await client.postForm(form.action, fields: fields, headers: ["Origin": Self.base, "Referer": Self.pageURL])
            let html = HTTPClient.text(from: data)
            let links = Self.icsLinks(in: html)
            if !links.isEmpty { return .calendar(links) }
            if let message = Self.errorMessage(in: html) { throw ProviderError.invalidSelection(message) }
            guard let next = Self.form(in: html), !next.selects.isEmpty else { throw ProviderError.noDataGeneric }
            fields = next.fields
            for select in next.selects {
                if let value = answers[select.name], select.options.contains(where: { $0.value == value }) {
                    Self.set(select.name, value, in: &fields)
                } else {
                    return .choice(Self.step(for: select))
                }
            }
            form = next
        }
        throw ProviderError.noDataGeneric
    }

    struct Select {
        var name: String
        var options: [(value: String, label: String)]
    }

    struct Form {
        var action: String
        var fields: [(String, String)]
        var selects: [Select]
    }

    private static func set(_ name: String, _ value: String, in fields: inout [(String, String)]) {
        if let index = fields.firstIndex(where: { $0.0 == name }) {
            fields[index].1 = value
        } else {
            fields.append((name, value))
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        HTMLText.firstMatch(#"\s\#(name)\s*=\s*"([^"]*)""#, in: tag, group: 1).map(HTMLText.decodeEntities)
    }

    /// Das Formular `id="abfuhrkalender"`: Ziel, alle Eingabefelder (inkl. benanntem Absendeknopf) und Auswahllisten.
    static func form(in html: String) -> Form? {
        guard let match = HTMLText.matches(#"(<form[^>]*\sid="abfuhrkalender"[^>]*>)([\s\S]*?)</form>"#, in: html).first,
              let action = attribute("action", in: match[0]) else { return nil }
        let body = match[1]
        var fields: [(String, String)] = []
        for tag in HTMLText.matches(#"<input\b[^>]*>"#, in: body, wholeMatch: true).map({ $0[0] }) {
            guard let name = attribute("name", in: tag), !name.isEmpty else { continue }
            let type = (attribute("type", in: tag) ?? "text").lowercased()
            if type == "checkbox" || type == "radio" || type == "button" { continue }
            fields.append((name, attribute("value", in: tag) ?? ""))
        }
        let selects = HTMLText.matches(#"<select\b([^>]*)>([\s\S]*?)</select>"#, in: body).compactMap { groups -> Select? in
            guard let name = attribute("name", in: " " + groups[0]) else { return nil }
            let options = HTMLText.matches(#"<option[^>]*value="([^"]*)"[^>]*>([\s\S]*?)</option>"#, in: groups[1]).map { option in
                (value: HTMLText.decodeEntities(option[0]),
                 label: HTMLText.decodeEntities(HTMLText.stripTags(option[1])).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return options.isEmpty ? nil : Select(name: name, options: options)
        }
        return Form(action: action.hasPrefix("http") ? action : base + action, fields: fields, selects: selects)
    }

    static func step(for select: Select) -> SelectionStep {
        let field = String(select.name.dropFirst(prefix.count))
        let lower = field.lowercased()
        let bin: (de: String, en: String)
        if lower.contains("[r]") || lower.contains("rest") {
            bin = ("Restmülltonne", "residual waste bin")
        } else if lower.contains("[b]") || lower.contains("bio") {
            bin = ("Biotonne", "organic waste bin")
        } else if lower.contains("[p]") || lower.contains("papier") {
            bin = ("Papiertonne", "paper bin")
        } else {
            bin = ("Tonne", "bin")
        }
        let title = lower.contains("stellplatz")
            ? L10n.t("Stellplatz \(bin.de)", "Location of \(bin.en)")
            : L10n.t("Leerungszyklus \(bin.de)", "Collection cycle of \(bin.en)")
        let options = select.options.map { option in
            SelectionOption(id: field + "|" + option.value, title: option.label.isEmpty ? option.value : option.label)
        }
        return SelectionStep(title: title, options: options, searchable: options.count > 12)
    }

    static func icsLinks(in html: String) -> [String] {
        var seen = Set<String>()
        return HTMLText.matches(#"<a\b[^>]*>"#, in: html, wholeMatch: true).map { $0[0] }
            .filter { $0.contains("downloadics") }
            .compactMap { attribute("href", in: $0) }
            .map { $0.hasPrefix("http") ? $0 : base + $0 }
            .filter { seen.insert($0).inserted }
    }

    static func errorMessage(in html: String) -> String? {
        guard let raw = HTMLText.firstMatch(#"class="message messageError"[^>]*>([\s\S]*?)</div>"#, in: html, group: 1) else { return nil }
        let text = HTMLText.decodeEntities(HTMLText.stripTags(raw.replacingOccurrences(of: "<br", with: " <br")))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? L10n.t("Adresse nicht gefunden.", "Address not found.") : text
    }

    // MARK: - Straßenliste

    /// `<span class="aostrasse">Bellinzonastr.</span>` – ID bleibt die Schreibweise des Portals,
    /// der Titel wird ausgeschrieben („Marienpl.“ → „Marienplatz“), damit die Suche greift.
    static func streets(in html: String) -> [SelectionOption] {
        var seen = Set<String>()
        return HTMLText.matches(#"<span class="aostrasse">([^<]*)</span>"#, in: html)
            .map { HTMLText.decodeEntities($0[0]).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { SelectionOption(id: $0, title: expandStreet($0)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func expandStreet(_ name: String) -> String {
        name.replacingOccurrences(of: #"str\.(?=$|[\s-])"#, with: "straße", options: .regularExpression)
            .replacingOccurrences(of: #"Str\.(?=$|[\s-])"#, with: "Straße", options: .regularExpression)
            .replacingOccurrences(of: #"pl\.(?=$|[\s-])"#, with: "platz", options: .regularExpression)
            .replacingOccurrences(of: #"Pl\.(?=$|[\s-])"#, with: "Platz", options: .regularExpression)
    }

    // MARK: - ICS

    /// Die AWM-ICS beschreibt jede Tonne als Serie (WEEKLY mit INTERVAL/BYDAY/UNTIL) samt EXDATEs;
    /// Feiertagstermine stehen zusätzlich als Einzeltermine „Achtung: …“. Der Grundparser kennt
    /// weder BYDAY noch EXDATE, deshalb wird hier selbst aufgelöst.
    static func parseICS(_ text: String, calendar: Calendar) -> [Pickup] {
        var pickups: [Pickup] = []
        var inEvent = false
        var summary = "", rrule: String?, start: Date?, excluded = Set<String>()
        for line in ICS.unfold(text) {
            if line.hasPrefix("BEGIN:VEVENT") {
                inEvent = true; summary = ""; rrule = nil; start = nil; excluded = []
                continue
            }
            if line.hasPrefix("END:VEVENT") {
                inEvent = false
                guard let start else { continue }
                let isNotice = summary.lowercased().hasPrefix("achtung")
                let base = summary.replacingOccurrences(of: #"^\s*Achtung:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                let name = NameCleaner.clean(base.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? base)
                guard !name.isEmpty else { continue }
                let note = isNotice ? L10n.t("Feiertagszeitraum: Leerung evtl. vor oder nach dem gewohnten Tag.", "Holiday period: collection may be earlier or later than usual.") : nil
                for date in expand(start: start, rrule: rrule, calendar: calendar) where !excluded.contains(Days.iso(date, calendar: calendar)) {
                    pickups.append(Pickup(date: date, name: name, note: note))
                }
                continue
            }
            guard inEvent else { continue }
            let (key, params, value) = ICS.split(line)
            switch key {
            case "SUMMARY": summary = ICS.unescape(value)
            case "DTSTART": start = ICS.parseDate(value, params: params, calendar: calendar)
            case "RRULE": rrule = value
            case "EXDATE":
                for part in value.split(separator: ",") {
                    if let date = ICS.parseDate(String(part), params: params, calendar: calendar) { excluded.insert(Days.iso(date, calendar: calendar)) }
                }
            default: break
            }
        }
        return pickups
    }

    /// FREQ=WEEKLY (INTERVAL, BYDAY, UNTIL, COUNT) und DAILY; alles andere als Einzeltermin.
    static func expand(start: Date, rrule: String?, calendar: Calendar) -> [Date] {
        guard let rrule, !rrule.isEmpty else { return [start] }
        var fields: [String: String] = [:]
        for part in rrule.components(separatedBy: ";") {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 { fields[kv[0].uppercased()] = kv[1] }
        }
        let interval = max(1, Int(fields["INTERVAL"] ?? "1") ?? 1)
        let maxCount = min(Int(fields["COUNT"] ?? "") ?? 400, 400)
        let until = fields["UNTIL"].flatMap { ICS.parseDate($0, calendar: calendar) }
            ?? calendar.date(byAdding: .year, value: 1, to: start) ?? start
        var dates: [Date] = []
        switch fields["FREQ"]?.uppercased() {
        case "DAILY":
            var current = start
            while dates.count < maxCount && current <= until {
                dates.append(current)
                current = Days.add(interval, to: current, calendar: calendar)
            }
        case "WEEKLY":
            // Wochentage als Abstand zum Montag (MO = 0 … SU = 6)
            let codes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
            let startOffset = (calendar.component(.weekday, from: start) + 5) % 7
            var offsets = (fields["BYDAY"] ?? "").split(separator: ",")
                .compactMap { code in codes.firstIndex(of: String(code.filter(\.isLetter)).uppercased()) }
            if offsets.isEmpty { offsets = [startOffset] }
            offsets = Array(Set(offsets)).sorted()
            var weekStart = Days.add(-startOffset, to: start, calendar: calendar)
            while dates.count < maxCount && weekStart <= until {
                for offset in offsets {
                    let date = Days.add(offset, to: weekStart, calendar: calendar)
                    if date >= start && date <= until && dates.count < maxCount { dates.append(date) }
                }
                weekStart = Days.add(7 * interval, to: weekStart, calendar: calendar)
            }
        default:
            return [start]
        }
        return dates
    }
}
