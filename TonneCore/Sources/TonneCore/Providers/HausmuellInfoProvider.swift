import Foundation

/// hausmüll.info (ATURIS „AbfallKalenderWeb“): Erfurt, Chemnitz, Börde, Wartburgkreis, Schmalkalden-Meiningen,
/// Eichsfeld, Suhl und Wesel. Auswahl über die Suchskripte des Portals (Ort → Ortsteil → Straße → Hausnummer,
/// je nach Betreiber), danach liefert `ics/ics.php` den Kalender. Sobald ein Eintrag ein Entsorgungsgebiet
/// (`egebiet`) trägt, ist die Auswahl fertig.
public struct HausmuellInfoProvider: WasteProvider {
    public let kind: ProviderKind = .hausmuellInfo
    public let serviceKey: String
    public var displayName: String { Self.operators[serviceKey]?.title ?? "hausmüll.info" }
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    // MARK: - Betreiber

    /// Auswahlebenen des Formulars; `code` ist die Nummer für `proxy.php?url=…`.
    enum Level: String, CaseIterable, Sendable {
        case ort, ortsteil, str, hnr, objekt

        var code: Int {
            switch self {
            case .ort: return 0
            case .ortsteil: return 1
            case .str: return 2
            case .hnr: return 3
            case .objekt: return 7
            }
        }

        /// Direktes Suchskript; Objektnummern gibt es nur über `proxy.php`.
        var script: String? {
            switch self {
            case .ort: return "search/search_orte.php"
            case .ortsteil: return "search/search_ortsteile.php"
            case .str: return "search/search_strassen.php"
            case .hnr: return "search/search_hnr.php"
            case .objekt: return nil
            }
        }

        var title: String {
            switch self {
            case .ort: return SelectionStep.cityTitle
            case .ortsteil: return SelectionStep.districtTitle
            case .str: return SelectionStep.streetTitle
            case .hnr: return SelectionStep.houseNumberTitle
            case .objekt: return L10n.t("Objektnummer", "Object number")
            }
        }
    }

    struct Operator: Sendable {
        let title: String
        let base: String
        /// true: Suche über `proxy.php` mit Ebenen-Code, sonst direkt über `search/*.php`.
        let proxy: Bool
        let levels: [Level]
        /// Ebene, die nur mit Suchtext (≥ 3 Zeichen) antwortet.
        var textLevel: Level? = nil
    }

    static let operators: [String: Operator] = [
        "erfurt": Operator(title: "Stadtwerke Erfurt (SWE)", base: "https://abfallkalender.stadtwerke-erfurt.de/", proxy: false, levels: [.str, .hnr]),
        "asc": Operator(title: "ASR Chemnitz", base: "https://asc.hausmuell.info/", proxy: true, levels: [.str, .hnr, .objekt], textLevel: .str),
        "boerde": Operator(title: "Kommunalservice Landkreis Börde", base: "https://boerde.hausmuell.info/", proxy: false, levels: [.ort, .str, .hnr]),
        "azv": Operator(title: "AZV Wartburgkreis", base: "https://azv.hausmuell.info/", proxy: true, levels: [.ort, .ortsteil, .str, .hnr]),
        "schmalkalden-meiningen": Operator(title: "Kreiswerke Schmalkalden-Meiningen", base: "https://schmalkalden-meiningen.hausmuell.info/", proxy: false, levels: [.ort, .ortsteil, .str, .hnr]),
        "ew": Operator(title: "Eichsfeldwerke", base: "https://ew.hausmuell.info/", proxy: false, levels: [.ort, .ortsteil, .str, .hnr]),
        "ebkds": Operator(title: "EB KDS Suhl", base: "https://ebkds.hausmuell.info/", proxy: false, levels: [.ort, .str, .hnr]),
        "wesel": Operator(title: "ASG Wesel", base: "https://wesel.hausmuell.info/", proxy: true, levels: [.ort, .ortsteil, .str, .hnr]),
    ]

    private var op: Operator? { Self.operators[serviceKey] }

    // MARK: - Auswahlzustand

    /// Eine getroffene Auswahl; die Option-ID lautet `ebene:id:egebiet`.
    struct Choice: Equatable {
        let level: Level
        let id: String
        let area: String
        let title: String

        var hasArea: Bool { !area.isEmpty && area != "0" }

        static func parse(_ option: SelectionOption) -> Choice? {
            let parts = option.id.components(separatedBy: ":")
            guard parts.count == 3, let level = Level(rawValue: parts[0]), Int(parts[1]) != nil else { return nil }
            return Choice(level: level, id: parts[1], area: parts[2], title: option.title)
        }
    }

    struct State {
        var choices: [Choice] = []
        /// Suchtext, wenn die letzte Auswahl eine Texteingabe war.
        var query: String?

        func id(_ level: Level) -> String? { choices.first { $0.level == level }?.id }
        func title(_ level: Level) -> String? { choices.first { $0.level == level }?.title }
        /// Gebiets-ID der zuletzt gewählten Ebene mit Gebiet.
        var area: String? { choices.last(where: \.hasArea)?.area }
        /// Genaueste Orts-ID (Ortsteil vor Ort).
        var placeID: String { id(.ortsteil) ?? id(.ort) ?? "0" }
    }

    static func state(from selections: [SelectionOption]) -> State {
        var state = State()
        for option in selections {
            if let choice = Choice.parse(option) {
                state.choices.append(choice)
                state.query = nil
            } else {
                state.query = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return state
    }

    // MARK: - Assistent

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let op else { throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }
        let state = Self.state(from: selections)
        if state.choices.last?.hasArea == true { return nil }
        var index = state.choices.last.flatMap { last in op.levels.firstIndex(of: last.level).map { $0 + 1 } } ?? 0
        var requested = false
        while index < op.levels.count {
            let level = op.levels[index]
            if level == op.textLevel {
                guard let query = state.query, !query.isEmpty else {
                    return .text(title: level.title, placeholder: L10n.t("mind. 3 Buchstaben, z. B. Hübschmannstr", "at least 3 letters"))
                }
                let options = try await searchText(level, query: query, state: state, op: op)
                guard !options.isEmpty else {
                    throw ProviderError.invalidSelection(L10n.t("Keine passende Straße gefunden.", "No matching street found."))
                }
                return SelectionStep(title: level.title, options: options)
            }
            if requested { await Self.pause() }
            let options = try await list(level, input: "", state: state, op: op)
            requested = true
            if !options.isEmpty { return SelectionStep(title: level.title, options: options) }
            // Leere Ebene (z. B. Ort ohne Ortsteile) überspringen.
            index += 1
        }
        return nil
    }

    /// Suchtext-Ebene: erst wie eingegeben, dann mit „str“ statt „straße“, zuletzt nur mit dem Wortanfang.
    private func searchText(_ level: Level, query: String, state: State, op: Operator) async throws -> [SelectionOption] {
        var variants = [query]
        let short = query.replacingOccurrences(of: #"(?i)stra(ß|ss)e\b"#, with: "str", options: .regularExpression)
        if short != query { variants.append(short) }
        let head = String(query.prefix(while: { !$0.isWhitespace && $0 != "-" }).prefix(5))
        if head.count >= 3, !variants.contains(head) { variants.append(head) }
        for (i, variant) in variants.enumerated() {
            if i > 0 { await Self.pause() }
            let options = try await list(level, input: variant, state: state, op: op)
            if !options.isEmpty { return options }
        }
        return []
    }

    /// Ruft eine Auswahlliste ab (Parameter zusätzlich in der URL, weil manche Skripte `$_GET` lesen).
    private func list(_ level: Level, input: String, state: State, op: Operator) async throws -> [SelectionOption] {
        var fields: [(String, String)] = [
            ("input", input),
            ("input_\(level.rawValue)", input),
            ("ort_id", state.placeID),
            ("ortsteil_id", state.id(.ortsteil) ?? ""),
            ("str_id", state.id(.str) ?? "0"),
            ("hnr_id", state.id(.hnr) ?? "0"),
            ("input_str", state.title(.str) ?? ""),
            ("input_hnr", level == .objekt ? (state.title(.hnr) ?? "") : input),
            ("hidden_kalenderart", "privat"),
        ]
        let path: String
        if op.proxy {
            fields += [("url", String(level.code)), ("server", "0")]
            path = "proxy.php"
        } else if let script = level.script {
            path = script
        } else {
            return []
        }
        let query = fields.map { "\(HTTPClient.formEncode($0.0))=\(HTTPClient.formEncode($0.1))" }.joined(separator: "&")
        let data = try await client.postForm(op.base + path + "?" + query, fields: fields)
        return Self.parseList(Self.decode(data), level: level)
    }

    /// `<li … get_value("str", 123, 456)> <span hidden>…</span><span>Name</span></li>` → Optionen.
    static func parseList(_ html: String, level: Level) -> [SelectionOption] {
        let rows = HTMLText.matches(#"<li[^>]*get_value\(\s*["']?\w+["']?\s*,\s*(\d+)(?:\s*,\s*(\d+))?\s*\)[^>]*>([\s\S]*?)</li>"#, in: html)
        var seen = Set<String>()
        return rows.compactMap { groups -> SelectionOption? in
            let visible = groups[2].replacingOccurrences(of: #"<span[^>]*display:\s*none[^>]*>[\s\S]*?</span>"#, with: "", options: [.regularExpression, .caseInsensitive])
            var title = HTMLText.decodeEntities(HTMLText.stripTags(visible)).trimmingCharacters(in: .whitespacesAndNewlines)
            if title == "-" || title.isEmpty { return nil }
            if title == "-Stadt-" { title = L10n.t("Kernstadt", "Town centre") }
            let id = "\(level.rawValue):\(groups[0]):\(groups[1].isEmpty ? "0" : groups[1])"
            guard seen.insert(id).inserted else { return nil }
            return SelectionOption(id: id, title: title)
        }
    }

    // MARK: - Termine

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let op else { throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }
        let state = Self.state(from: selections)
        // Fertig ist eine Auswahl mit Gebiet oder bis zur Hausnummer (Erfurt/Suhl arbeiten ohne Gebiets-ID).
        guard let last = state.choices.last, last.hasArea || last.level == .hnr || last.level == .objekt else {
            throw ProviderError.selectAddressFirst
        }
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        var areaOnly = false
        // Leeres Jahr = laufendes Jahr ab heute; das Folgejahr gibt es erst, wenn es veröffentlicht ist.
        for (i, target) in ["", String(year + 1)].enumerated() {
            if i > 0 { await Self.pause() }
            var text = await calendarText(op, state: state, year: target, areaOnly: areaOnly)
            // Mit vollen IDs schreibt das Portal Umlaute Latin-1-kodiert in den Dateinamen-Header, an dem
            // manche HTTP-Stacks scheitern; dann nur mit der Gebiets-ID fragen (gleiche Termine, ASCII-Header).
            if text == nil, !areaOnly, i == 0, state.area != nil {
                await Self.pause()
                areaOnly = true
                text = await calendarText(op, state: state, year: target, areaOnly: true)
            }
            guard let text else { continue }
            result += ICS.parse(text, calendar: calendar).map { event in
                let (name, note) = Self.cleanName(event.summary)
                return Pickup(date: event.date, name: name, note: note)
            }
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    /// ICS-Text oder nil, wenn das Portal keinen Kalender liefert.
    private func calendarText(_ op: Operator, state: State, year: String, areaOnly: Bool) async -> String? {
        guard let data = try? await client.postForm(op.base + "ics/ics.php", fields: Self.icsFields(state, year: year, areaOnly: areaOnly)) else { return nil }
        let text = Self.decode(data)
        return text.contains("BEGIN:VCALENDAR") ? text : nil
    }

    static func icsFields(_ state: State, year: String, areaOnly: Bool = false) -> [(String, String)] {
        let id: (Level) -> String? = { areaOnly ? nil : state.id($0) }
        let name: (Level) -> String = { areaOnly ? ascii(state.title($0)) : (state.title($0) ?? "") }
        let ort = id(.ort) ?? "0"
        let hnr = id(.hnr) ?? "0"
        var fields: [(String, String)] = [
            ("hidden_id_ort", ort),
            ("hidden_id_ortsteil", id(.ortsteil) ?? ort),
            ("hidden_id_str", id(.str) ?? "0"),
            ("hidden_id_hnr", hnr),
            ("hidden_id_zusatz", hnr),
            ("hidden_id_egebiet", state.area ?? "0"),
            ("input_ort", name(.ort)),
            ("input_ortsteil", name(.ortsteil)),
            ("input_str", name(.str)),
            ("input_hnr", name(.hnr)),
            ("input_objektnr", name(.objekt)),
            ("hidden_kalenderart", "privat"),
            ("hidden_send_btn", "ics"),
            ("hiddenYear", year),
        ]
        // Alle Fraktionen einschalten (Feldnamen je Portal verschieden; unbekannte werden ignoriert).
        for bin in ["Rest", "Rest_rc", "Dsd", "DSD", "Bio", "Prob", "Papier", "Xmas", "Organic"] {
            fields.append(("showBins" + bin, "on"))
        }
        return fields
    }

    /// Eingaben ohne Umlaute (für die Abfrage nur mit Gebiets-ID).
    static func ascii(_ text: String?) -> String {
        guard let text else { return "" }
        let replaced = text.replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "Ä", with: "Ae")
            .replacingOccurrences(of: "Ö", with: "Oe").replacingOccurrences(of: "Ü", with: "Ue")
            .replacingOccurrences(of: "ß", with: "ss")
        let folded = replaced.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return String(folded.unicodeScalars.filter(\.isASCII).map(Character.init))
    }

    /// „Entsorgung: Restabfall“ → „Restabfall“; „Verschobene Abholung: …“ mit Hinweis.
    static func cleanName(_ summary: String) -> (String, String?) {
        var name = summary
        var note: String?
        for prefix in ["Entsorgung:", "Verschobene Abholung:"] where name.lowercased().hasPrefix(prefix.lowercased()) {
            name = String(name.dropFirst(prefix.count))
            if prefix.hasPrefix("Verschobene") { note = L10n.t("Verschobene Abholung", "Rescheduled pickup") }
        }
        return (NameCleaner.clean(name), note)
    }

    /// Manche Portale mischen UTF-8 und Latin-1 in einer Antwort: zeilenweise dekodieren.
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text.replacingOccurrences(of: "\u{FEFF}", with: "") }
        return data.split(separator: 0x0A, omittingEmptySubsequences: false).map { line in
            String(data: Data(line), encoding: .utf8) ?? String(data: Data(line), encoding: .isoLatin1) ?? ""
        }.joined(separator: "\n")
    }

    /// Kurze Pause zwischen zwei Anfragen an denselben Server.
    static func pause() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    public func label(for selections: [SelectionOption]) -> String {
        let state = Self.state(from: selections)
        var parts: [String] = []
        if serviceKey == "erfurt" { parts.append("Erfurt") }
        if serviceKey == "asc" { parts.append("Chemnitz") }
        if serviceKey == "ebkds" { parts.append("Suhl") }
        if serviceKey == "wesel" { parts.append("Wesel") }
        for level in [Level.ort, .ortsteil] {
            if let title = state.title(level), !parts.contains(title) { parts.append(title) }
        }
        let street = [state.title(.str), state.title(.hnr)].compactMap { $0 }.joined(separator: " ")
        if !street.isEmpty { parts.append(street) }
        if let object = state.title(.objekt) { parts.append(L10n.t("Objekt ", "Object ") + object) }
        return parts.joined(separator: ", ")
    }
}
