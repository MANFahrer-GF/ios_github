import Foundation

/// ATHOS „WasteManagementServlet“: Formular-Portale mit Sitzungs-ID in versteckten Feldern.
/// Ablauf wie im Browser: Startseite → `CITYCHANGED` (Ort bzw. Anfangsbuchstabe) → `STREETCHANGED`
/// (wenn die Hausnummern als Liste kommen) → `forward` (Terminliste) → `filedownload_ICAL`.
/// Bietet das Portal mehrere Zeiträume an (z. B. Vogtland), wird jeder abgerufen.
public struct WasteManagementServletProvider: WasteProvider {
    /// Ein Betreiber: Basis-URLs (die erste, die antwortet, gilt) und Name; `city` nur bei Portalen,
    /// die statt Orten Anfangsbuchstaben der Straße anbieten.
    public struct Portal: Sendable {
        public let name: String
        public let bases: [String]
        public let city: String?

        init(_ name: String, _ bases: [String], city: String? = nil) {
            self.name = name
            self.bases = bases
            self.city = city
        }
    }

    public static let portals: [String: Portal] = [
        "pforzheim": Portal("Abfallwirtschaft Pforzheim", ["https://onlineservices.abfallwirtschaft-pforzheim.de/WasteManagementPforzheim"], city: "Pforzheim"),
        "zweibruecken": Portal("UBZ Zweibrücken", ["https://leerungen.ubzzw.com/WasteManagementZweibruecken"], city: "Zweibrücken"),
        // Bielefeld betreibt das Portal produktiv unter „…Test“; die alte Adresse bleibt als Rückfall.
        "bielefeld": Portal("Umweltbetrieb Bielefeld", ["https://anwendungen.bielefeld.de/WasteManagementBielefeldTest", "https://anwendungen.bielefeld.de/WasteManagementBielefeld"], city: "Bielefeld"),
        // Bamberg und SBAZV: Adressen aus HACS bzw. sbazv.de, live noch nicht geprüft (aus dem Testnetz nicht erreichbar).
        "bamberg": Portal("Entsorgungs- und Baubetrieb Bamberg", ["https://ebbweb.stadt.bamberg.de/WasteManagementBamberg"], city: "Bamberg"),
        "hameln": Portal("KAW Hameln-Pyrmont", ["https://om.kaw-hameln.de/WasteManagementHameln"]),
        "alzeyworms": Portal("Abfallwirtschaft Alzey-Worms", ["https://abfall.alzey-worms.de/WasteManagementAlzeyworms"]),
        "suedwestsachsen": Portal("ZAS Südwestsachsen", ["https://online-portal.za-sws.de/WasteManagementSuedwestsachsen"]),
        "vogtland": Portal("Abfallwirtschaft Vogtlandkreis", ["https://awi.vogtlandkreis.de/WasteManagementVogtland"]),
        "suedbrandenburg": Portal("SBAZV Südbrandenburg", ["https://fahrzeuge.sbazv.de/WasteManagementSuedbrandenburg"]),
        "pfaffenhofen": Portal("AWP Pfaffenhofen", ["https://abfuhrtermine.awp-paf.de/WasteManagementPfaffenhofen"]),
    ]

    public let kind: ProviderKind = .wasteManagementServlet
    public let serviceKey: String
    public var displayName: String { Self.portals[serviceKey]?.name ?? "WasteManagement-Portal" }
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    private var portal: Portal {
        get throws {
            guard let portal = Self.portals[serviceKey] else { throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }
            return portal
        }
    }

    // MARK: - Assistent

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        let session = try await Session.start(portal: try portal, client: client)
        switch selections.count {
        case 0:
            let places = session.page.options(of: "Ort").filter { !$0.value.isEmpty }
            guard !places.isEmpty else { throw ProviderError.noDataGeneric }
            let letters = places.allSatisfy { $0.value.count <= 2 }
            let title = letters ? L10n.t("Anfangsbuchstabe der Straße", "First letter of the street") : SelectionStep.cityTitle
            return SelectionStep(title: title, options: places.map { SelectionOption(id: $0.value, title: $0.label) }, searchable: !letters)
        case 1:
            let page = try await session.submit(session.page, action: "CITYCHANGED", values: ["Ort": selections[0].id])
            let streets = page.options(of: "Strasse").filter { !$0.value.isEmpty }
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0.value, title: $0.label) })
        case 2:
            let page = try await session.submit(session.page, action: "CITYCHANGED", values: ["Ort": selections[0].id])
            guard page.hasSelect("Hausnummer") else {
                return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 12 oder 12a", "e.g. 12 or 12a"))
            }
            let street = try await session.submit(page, action: "STREETCHANGED", values: ["Ort": selections[0].id, "Strasse": selections[1].id])
            let numbers = street.options(of: "Hausnummer").filter { !$0.value.isEmpty }
            guard !numbers.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: numbers.map { SelectionOption(id: $0.value, title: $0.label) })
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let session = try await Session.start(portal: try portal, client: client)
        var values = ["Ort": selections[0].id, "Strasse": selections[1].id]
        var address = try await session.submit(session.page, action: "CITYCHANGED", values: values)
        if address.hasSelect("Hausnummer") {
            address = try await session.submit(address, action: "STREETCHANGED", values: values)
            values["Hausnummer"] = selections[2].id
        } else {
            // Freitext „12a“ / „29-33“ → Hausnummer + Zusatz
            let input = selections[2].id.trimmingCharacters(in: .whitespaces)
            let number = String(input.prefix { $0.isNumber })
            guard !number.isEmpty else { throw ProviderError.invalidSelection(L10n.t("Bitte eine Hausnummer eingeben.", "Please enter a house number.")) }
            values["Hausnummer"] = number
            values["Hausnummerzusatz"] = input.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        }

        // Zeiträume (Jahresübersichten) – fehlen sie, gilt der Standard des Portals.
        let periods: [String?] = {
            let all = address.radioValues(of: "Zeitraum") + address.options(of: "Zeitraum").map(\.value)
            return all.isEmpty ? [nil] : all.map { $0 }
        }()

        var pickups: [Pickup] = []
        var problem: String?
        for period in periods {
            var request = values
            if let period { request["Zeitraum"] = period }
            let list = try await session.submit(address, action: "forward", values: request)
            guard list.offersICal else {
                problem = problem ?? list.message
                continue
            }
            let text = try await session.download(list, action: "filedownload_ICAL")
            guard text.contains("BEGIN:VCALENDAR") else { continue }
            for event in ICS.parse(text, calendar: calendar) {
                guard let name = Self.cleanName(event.summary) else { continue }
                pickups.append(Pickup(date: event.date, name: name))
            }
        }
        if pickups.isEmpty {
            if let problem, !problem.isEmpty { throw ProviderError.invalidSelection(problem) }
            throw ProviderError.noDataGeneric
        }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        let place = (try? portal)?.city ?? selections.first?.title ?? ""
        let street = selections.dropFirst().map(\.title).filter { !$0.isEmpty }.joined(separator: " ")
        return [place, street].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Fraktionsnamen ohne Umlaut-Ersatz; Hinweis-Termine („neue ICal-Datei“) entfallen.
    static func cleanName(_ raw: String) -> String? {
        if raw.lowercased().contains("kalenderdatei") { return nil }
        var name = raw.replacingOccurrences(of: " ,", with: ",")
        let fixes = [("Grossmuellbehaelter", "Restmüll-Großbehälter"), ("muell", "müll"), ("Muell", "Müll"), ("behaelter", "behälter"),
                     ("Behaelter", "Behälter"), ("taeglich", "täglich"), ("woechentl", "wöchentl"), ("Woechentl", "Wöchentl")]
        for (from, to) in fixes { name = name.replacingOccurrences(of: from, with: to) }
        let cleaned = NameCleaner.clean(name)
        return WasteCategory.isIgnorableTitle(cleaned) ? nil : cleaned
    }
}

// MARK: - Formular-Sitzung

private struct Session {
    let servlet: String
    let page: ServletPage
    let client: HTTPClient

    static func start(portal: WasteManagementServletProvider.Portal, client: HTTPClient) async throws -> Session {
        var lastError: Error = ProviderError.noDataGeneric
        for base in portal.bases {
            let servlet = base + "/WasteManagementServlet"
            do {
                let data = try await client.get(servlet + "?SubmitAction=wasteDisposalServices&InFrameMode=TRUE")
                let page = ServletPage(HTTPClient.text(from: data))
                guard page.field("SessionId") != nil else { continue }
                return Session(servlet: servlet, page: page, client: client)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Schickt das Formular einer Seite ab – mit allen Feldern wie im Browser, ergänzt um `values`.
    func submit(_ page: ServletPage, action: String, values: [String: String]) async throws -> ServletPage {
        ServletPage(HTTPClient.text(from: try await post(page, action: action, values: values)))
    }

    func download(_ page: ServletPage, action: String) async throws -> String {
        HTTPClient.text(from: try await post(page, action: action, values: [:]))
    }

    private func post(_ page: ServletPage, action: String, values: [String: String]) async throws -> Data {
        var fields = page.fields.filter { values[$0.0] == nil && $0.0 != "SubmitAction" }
        fields += values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        fields.append(("SubmitAction", action))
        let body = fields.map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }.joined(separator: "&")
        return try await client.post(servlet, body: Data(body.utf8), contentType: "application/x-www-form-urlencoded; charset=UTF-8")
    }

    /// Strikt ASCII kodieren – Umlaute und geschützte Leerzeichen als UTF-8-Prozentfolgen.
    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: "%20", with: "+") ?? value
    }
}

/// Eine Seite des Servlets. Bielefeld liefert die eigentliche Seite als JavaScript-String
/// (`var text = '…'`) aus – der wird vorher ausgepackt.
private struct ServletPage {
    let html: String

    init(_ raw: String) {
        html = Self.unwrap(raw)
    }

    /// Felder, wie der Browser sie senden würde: versteckte und Textfelder, Behälter-Häkchen (alle an),
    /// gewählte Radio-Knöpfe und die gewählte Option jeder Auswahlliste.
    var fields: [(String, String)] {
        var result: [(String, String)] = []
        for tag in HTMLText.matches(#"<input\b[^>]*>"#, in: html, wholeMatch: true).map({ $0[0] }) {
            guard let name = Self.attribute("name", in: tag), !name.isEmpty else { continue }
            let type = (Self.attribute("type", in: tag) ?? "text").lowercased()
            let value = Self.attribute("value", in: tag) ?? ""
            let checked = tag.range(of: #"\schecked\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            switch type {
            case "hidden", "text": result.append((name, value))
            case "checkbox" where name.hasPrefix("ContainerGewaehlt") || checked: result.append((name, value.isEmpty ? "on" : value))
            case "radio" where checked: result.append((name, value))
            default: break
            }
        }
        for match in HTMLText.matches(#"<select\b([^>]*)>([\s\S]*?)</select>"#, in: html) {
            guard let name = Self.attribute("name", in: match[0]) else { continue }
            let options = Self.optionTags(in: match[1])
            if let chosen = options.first(where: { $0.selected }) ?? options.first { result.append((name, chosen.value)) }
        }
        return result
    }

    func field(_ name: String) -> String? {
        fields.first { $0.0 == name }?.1
    }

    func hasSelect(_ name: String) -> Bool {
        select(name) != nil
    }

    /// Optionen einer Auswahlliste: Wert roh (mit geschützten Leerzeichen, so erwartet es der Server), Text lesbar.
    func options(of name: String) -> [(value: String, label: String)] {
        guard let body = select(name) else { return [] }
        return Self.optionTags(in: body).map { (value: $0.value, label: Self.readable($0.label)) }
    }

    func radioValues(of name: String) -> [String] {
        HTMLText.matches(#"<input\b[^>]*>"#, in: html, wholeMatch: true).map { $0[0] }.compactMap { tag in
            guard Self.attribute("name", in: tag) == name, Self.attribute("type", in: tag)?.lowercased() == "radio" else { return nil }
            return Self.attribute("value", in: tag)
        }
    }

    /// Terminliste erreicht, wenn die Seite den ICS-Download anbietet.
    var offersICal: Bool {
        html.range(of: "filedownload_ICAL", options: .caseInsensitive) != nil
    }

    /// Hinweis des Portals (z. B. „keine Behälter angemeldet“).
    var message: String? {
        guard let block = HTMLText.firstMatch(#"id=["']Informations["'][^>]*>([\s\S]*?)</div>"#, in: html, group: 1) else { return nil }
        let text = Self.readable(HTMLText.decodeEntities(HTMLText.stripTags(block)))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func select(_ name: String) -> String? {
        for match in HTMLText.matches(#"<select\b([^>]*)>([\s\S]*?)</select>"#, in: html) where Self.attribute("name", in: match[0]) == name {
            return match[1]
        }
        return nil
    }

    private static func optionTags(in body: String) -> [(value: String, label: String, selected: Bool)] {
        HTMLText.matches(#"<option\b([^>]*)>([\s\S]*?)(?=<option\b|</option>|$)"#, in: body).compactMap { groups in
            guard let value = attribute("value", in: groups[0]) else { return nil }
            let label = decode(HTMLText.stripTags(groups[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            let selected = groups[0].range(of: #"\bselected\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            return (value, label.isEmpty ? value : label, selected)
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...3 where match.range(at: group).location != NSNotFound {
            return decode(ns.substring(with: match.range(at: group)))
        }
        return nil
    }

    /// Entities auflösen, `&nbsp;` aber als geschütztes Leerzeichen behalten (Teil der Werte).
    private static func decode(_ text: String) -> String {
        HTMLText.decodeEntities(text.replacingOccurrences(of: "&nbsp;", with: "\u{00A0}"))
    }

    private static func readable(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Packt `var text = '…';` aus und löst die JavaScript-Escapes auf.
    static func unwrap(_ raw: String) -> String {
        guard raw.range(of: #"name="SessionId""#, options: .caseInsensitive) == nil,
              let literal = HTMLText.firstMatch(#"var\s+text\s*=\s*'((?:[^'\\]|\\[\s\S])*)'"#, in: raw, group: 1) else { return raw }
        var result = ""
        var iterator = Array(literal.unicodeScalars).makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "\\", let next = iterator.next() else { result.unicodeScalars.append(scalar); continue }
            switch next {
            case "n": result += "\n"
            case "r": result += "\r"
            case "t": result += "\t"
            case "u":
                var hex = ""
                for _ in 0..<4 { if let h = iterator.next() { hex.unicodeScalars.append(h) } }
                if let code = UInt32(hex, radix: 16), let decoded = Unicode.Scalar(code) { result.unicodeScalars.append(decoded) }
            default: result.unicodeScalars.append(next)
            }
        }
        return result
    }
}
