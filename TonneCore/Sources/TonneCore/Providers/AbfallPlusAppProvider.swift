import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// AbfallPlus-App (app.abfallplus.de): die Schnittstelle hinter vielen Landkreis-Apps wie
/// „ALBA Abfuhrtermine“, „Abfall+“ oder den k4systems-Apps. `serviceKey` ist die App-Kennung,
/// z. B. `de.albagroup.app`.
///
/// Ablauf wie in der echten App: Sitzung anmelden, Ort/Straße/Hausnummer über den Assistenten
/// wählen, Abfallarten bestätigen, danach liefert `struktur.xml.zip` alle Termine.
/// Jeder Aufruf startet eine eigene Sitzung, die Auswahlen tragen alle nötigen Kennungen.
public struct AbfallPlusAppProvider: WasteProvider {
    public let kind: ProviderKind = .abfallPlusApp
    public let serviceKey: String
    public var displayName: String { "AbfallPlus-App" }

    private static let base = "https://app.abfallplus.de/"
    private static let assistant = "https://app.abfallplus.de/assistent/"
    private static let assistantAgent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Abfallwecker"

    public init(appID: String) {
        self.serviceKey = appID
    }

    // MARK: - Zustand

    /// Alle Kennungen, die der Assistent braucht.
    struct State {
        var bundesland = "0"
        var landkreis = "0"
        var kommune = "0"
        var region = ""
        var bezirk = ""
        var strasse = ""
        var strasseForm = ""
        var hnr = ""
        var steps: [String] = []
        var stage = ""

        mutating func apply(_ fields: [String: String]) {
            if let v = fields["bl"], !v.isEmpty { bundesland = v }
            if let v = fields["lk"], !v.isEmpty { landkreis = v }
            if let v = fields["kom"], !v.isEmpty { kommune = v }
            if let v = fields["reg"], !v.isEmpty { region = v }
            if let v = fields["bez"] { bezirk = v }
            if let v = fields["str"], !v.isEmpty { strasse = v; strasseForm = v }
            if let v = fields["fstr"], !v.isEmpty { strasseForm = v }
            if let v = fields["hnr"] { hnr = v }
            if let v = fields["next"], !v.isEmpty { stage = v }
        }

        static func isFixed(_ id: String) -> Bool {
            guard !id.isEmpty, id != "0" else { return false }
            return id.split(separator: "|").first.map(String.init) != "0"
        }
    }

    /// Eine Sitzung bei app.abfallplus.de (Cookie und Client-Kennung).
    final class Session {
        let appID: String
        let client = UUID().uuidString.lowercased()
        let urlSession: URLSession

        init(appID: String) {
            self.appID = appID
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            config.timeoutIntervalForRequest = 30
            urlSession = URLSession(configuration: config)
        }

        private var cookieHeader: String {
            // Gleichwertig zum Cookie, den der Server setzt (falls die Cookie-Ablage versagt).
            "b1737207d4988cfaf08370df05cfd18c=\(HTTPClient.formEncode(appID))%7C\(client)"
        }

        func app(_ path: String, query: String = "") async throws -> Data {
            let fields = [("client", client), ("app_id", appID)]
            let name = AbfallPlusAppCatalog.userAgentName[appID] ?? "Abfall+"
            return try await send(AbfallPlusAppProvider.base + path + query, fields: fields, headers: [
                "User-Agent": "Android / \(name) 8.1.1 (1915081010) / DM=unknown;DT=vbox86p;SN=Google;SV=8.1.0 (27);MF=unknown",
                "x-abfallplus-client": client,
                "x-abfallplus-appid": appID,
            ])
        }

        func assistant(_ path: String, _ fields: [(String, String)]) async throws -> String {
            let data = try await send(AbfallPlusAppProvider.assistant + path, fields: fields, headers: [
                "User-Agent": AbfallPlusAppProvider.assistantAgent,
                "Accept": "*/*",
                "Origin": "https://app.abfallplus.de",
                "Referer": "https://app.abfallplus.de/login/",
                "X-Requested-With": "XMLHttpRequest",
            ])
            return HTTPClient.text(from: data)
        }

        func get(_ path: String) async throws -> String {
            guard let url = URL(string: AbfallPlusAppProvider.assistant + path) else { throw HTTPError.badURL(path) }
            var request = URLRequest(url: url)
            request.setValue(AbfallPlusAppProvider.assistantAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            return HTTPClient.text(from: try await perform(request))
        }

        private func send(_ urlString: String, fields: [(String, String)], headers: [String: String]) async throws -> Data {
            guard let url = URL(string: urlString) else { throw HTTPError.badURL(urlString) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data(fields.map { "\(HTTPClient.formEncode($0.0))=\(HTTPClient.formEncode($0.1))" }.joined(separator: "&").utf8)
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            return try await perform(request)
        }

        /// Zeitpunkt der letzten Anfrage. Der Server wertet sehr schnelle Folgen von Anfragen als
        /// Automatenzugriff und liefert dann Platzhalter statt Terminen – deshalb wie die echte App
        /// mindestens gut eine Sekunde Abstand halten.
        private var lastRequest: Date?
        static let minimumGap: TimeInterval = 1.15

        private func perform(_ request: URLRequest) async throws -> Data {
            if let lastRequest {
                let wait = Session.minimumGap - Date().timeIntervalSince(lastRequest)
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            }
            defer { lastRequest = Date() }
            var lastError: Error = HTTPError.transport("–")
            for attempt in 0..<3 {
                do {
                    let (data, response) = try await urlSession.data(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw HTTPError.status(http.statusCode, "app.abfallplus.de")
                    }
                    return data
                } catch let error as HTTPError {
                    throw error
                } catch {
                    lastError = HTTPError.transport(error.localizedDescription)
                    if attempt < 2 { try? await Task.sleep(nanoseconds: 700_000_000) }
                }
            }
            throw lastError
        }
    }

    // MARK: - Parser

    /// Ein Eintrag aus `awk_standort_auswahl_step_fertig('id','Name','typ','weiter','',{…})`.
    struct Item {
        var id: String
        var name: String
        var step: String
        var next: String
        var extra: [String: String]
        var formStreet: String?
    }

    static func items(in html: String) -> [Item] {
        let pattern = #"awk_standort_auswahl_step_fertig\('((?:[^'\\]|\\.)*)','((?:[^'\\]|\\.)*)','([^']*)','([^']*)','[^']*'(?:,\{(.*?)\})?\)([^"]*)""#
        return HTMLText.matches(pattern, in: html).map { groups in
            var extra: [String: String] = [:]
            // Werte in Anführungszeichen oder blank; verschachtelte Objekte ({…}) werden mit durchsucht.
            for pair in HTMLText.matches(#"'(\w+)':(?:'([^']*)'|([^,'{}]*))"#, in: groups[4]) where pair.count == 3 {
                extra[pair[0]] = pair[1].isEmpty ? pair[2] : pair[1]
            }
            let formStreet = HTMLText.firstMatch(#"#f_id_strasse'\)\.val\((\d+)\)"#, in: groups[5], group: 1)
            return Item(id: HTMLText.decodeEntities(groups[0].replacingOccurrences(of: "\\'", with: "'")),
                        name: HTMLText.decodeEntities(groups[1].replacingOccurrences(of: "\\'", with: "'")),
                        step: groups[2], next: groups[3], extra: extra, formStreet: formStreet)
        }
    }

    private static func encode(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.replacingOccurrences(of: ";", with: ","))" }.joined(separator: ";")
    }

    private static func decode(_ id: String) -> [String: String] {
        // Freitext aus einem Eingabeschritt (Straßensuche)
        guard id.contains("k=") else { return ["k": "q", "q": id] }
        var result: [String: String] = [:]
        for part in id.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { result[kv[0]] = kv[1] }
        }
        return result
    }

    // MARK: - Ablauf

    private func start() async throws -> (Session, State) {
        let session = Session(appID: serviceKey)
        _ = try await session.app("config.xml")
        let html = HTTPClient.text(from: try await session.app("login/"))
        var state = State()
        for (name, value) in HTMLText.allInputs(in: html) {
            switch name {
            case "f_id_bundesland": state.bundesland = value
            case "f_id_landkreis": state.landkreis = value
            case "f_id_kommune": state.kommune = value
            default: break
            }
        }
        state.steps = HTMLText.matches(#"#awk_assistent_step_standort_([a-z]+)"#, in: html).compactMap(\.first)
        guard !state.steps.isEmpty else {
            throw ProviderError.notSupported(L10n.t("Die App-Kennung \(serviceKey) wird vom Server nicht mehr angeboten.", "The app id \(serviceKey) is no longer offered by the server."))
        }
        return (session, state)
    }

    private func replay(_ selections: [SelectionOption]) async throws -> (Session, State, [String: String]) {
        var (session, state) = try await start()
        var last: [String: String] = [:]
        for selection in selections {
            let fields = Self.decode(selection.id)
            last = fields
            state.apply(fields)
        }
        return (session, state, last)
    }

    private func baseFields(_ state: State) -> [(String, String)] {
        [("id_bundesland", state.bundesland), ("id_landkreis", state.landkreis)]
    }

    /// Liste eines Assistenten-Schritts. Gibt es den Schritt bei dieser App nicht, antwortet der Server mit 401/404.
    private func list(_ session: Session, _ path: String, _ fields: [(String, String)]) async throws -> [Item] {
        do {
            return Self.items(in: try await session.assistant(path, fields))
        } catch HTTPError.status(let code, _) where code == 401 || code == 404 {
            return []
        }
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        let (session, state, last) = try await replay(selections)
        let lastKind = last["k"] ?? ""

        // Erster Schritt: Bundesland, Region/Landkreis oder Kommune.
        if selections.isEmpty {
            if state.steps.contains("bundesland"), !State.isFixed(state.bundesland) {
                let items = Self.items(in: try await session.get("bundesland/"))
                if !items.isEmpty { return listStep(L10n.t("Bundesland", "State"), items, kind: "bl") }
            }
            if !State.isFixed(state.kommune) {
                for path in ["kommune/", "region/", "landkreis/"] {
                    let items = try await list(session, path, baseFields(state))
                    if !items.isEmpty { return listStep(SelectionStep.cityTitle, items, kind: "reg") }
                }
            }
            return try await streetOrDistrict(session, state)
        }

        switch lastKind {
        case "bl":
            for path in ["landkreis/", "region/", "kommune/"] {
                let items = try await list(session, path, baseFields(state))
                if !items.isEmpty { return listStep(L10n.t("Landkreis", "District"), items, kind: "reg") }
            }
            return try await streetOrDistrict(session, state)
        case "reg":
            if state.stage == "kommune" || (!State.isFixed(state.kommune) && state.stage != "strasse" && state.stage != "bezirk") {
                var fields = baseFields(state)
                if State.isFixed(state.kommune) { fields.append(("id_kommune", state.kommune)) }
                let items = try await list(session, "kommune/", fields)
                if !items.isEmpty, state.stage == "kommune" || !items.contains(where: { $0.id == last["kom"] }) {
                    return listStep(L10n.t("Gemeinde", "Municipality"), items, kind: "kom")
                }
            }
            return try await streetOrDistrict(session, state)
        case "kom":
            return try await streetOrDistrict(session, state)
        case "bez":
            if last["done"] == "1" { return nil }
            return streetSearchStep
        case "q":
            return try await streetStep(session, state, query: last["q"] ?? "")
        case "str":
            if last["next"] == "hnr" { return try await houseStep(session, state) }
            return nil
        default:
            return nil
        }
    }

    private func listStep(_ title: String, _ items: [Item], kind: String) -> SelectionStep {
        SelectionStep(title: title, options: items.map { item in
            var fields: [String: String] = ["k": kind]
            switch kind {
            case "bl": fields["bl"] = item.id
            case "reg":
                fields["reg"] = item.id
                fields["bl"] = item.extra["set_id_bundesland"] ?? ""
                fields["lk"] = item.extra["set_id_landkreis"] ?? (item.step == "landkreis" ? item.id : "")
                fields["kom"] = item.extra["set_id_kommune"] ?? (item.step == "kommune" || item.step == "region" && item.extra["set_id_landkreis"] == nil ? item.id : "")
                fields["next"] = item.extra["next_step"] ?? (item.next == "auto" ? "" : item.next)
            case "kom":
                fields["kom"] = item.extra["set_id_kommune"] ?? item.id
                fields["bl"] = item.extra["set_id_bundesland"] ?? ""
                fields["lk"] = item.extra["set_id_landkreis"] ?? ""
                fields["next"] = item.extra["next_step"] ?? ""
            default: break
            }
            return SelectionOption(id: Self.encode(fields), title: item.name)
        })
    }

    private func streetOrDistrict(_ session: Session, _ state: State) async throws -> SelectionStep? {
        if state.steps.contains("bezirk") {
            var fields = baseFields(state)
            fields.append(("id_kommune", state.kommune))
            let items = try await list(session, "bezirk/", fields)
            if !items.isEmpty {
                return SelectionStep(title: SelectionStep.districtTitle, options: items.map { item in
                    var fields: [String: String] = ["k": "bez", "bez": item.id]
                    if let kom = item.extra["set_id_kommune"] { fields["kom"] = kom }
                    if let lk = item.extra["set_id_landkreis"] { fields["lk"] = lk }
                    if let bl = item.extra["set_id_bundesland"] { fields["bl"] = bl }
                    if item.extra["step_akt"] == "strasse" || item.next == "fertig" {
                        fields["done"] = "1"
                        // „alle Straßen“ des Bezirks: Die Straßen-Kennung steckt in step_follow_data (wie in der App).
                        fields["str"] = item.extra["step_akt"] == "strasse" ? (item.extra["id"] ?? item.id) : item.id
                    }
                    return SelectionOption(id: Self.encode(fields), title: item.name)
                })
            }
        }
        return streetSearchStep
    }

    private var streetSearchStep: SelectionStep {
        .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname oder Anfang davon", "Street name or its beginning"))
    }

    private func streets(_ session: Session, _ state: State, query: String) async throws -> [Item] {
        try await list(session, "strasse/", [
            ("id_landkreis", state.landkreis),
            ("id_bezirk", state.bezirk),
            ("id_kommune", state.kommune),
            ("id_kommune_qry", state.kommune),
            ("strasse_qry", query),
        ])
    }

    private func streetStep(_ session: Session, _ state: State, query: String) async throws -> SelectionStep? {
        let items = try await streets(session, state, query: query)
        if items.isEmpty {
            throw ProviderError.invalidSelection(L10n.t("Keine Straße gefunden, die mit „\(query)“ beginnt.", "No street found starting with “\(query)”."))
        }
        return SelectionStep(title: SelectionStep.streetTitle, options: items.map { item in
            var fields: [String: String] = ["k": "str", "str": item.id, "next": item.next]
            if let kom = item.extra["set_id_kommune"] { fields["kom"] = kom }
            if let bez = item.extra["set_id_bezirk"] { fields["bez"] = bez == "0" ? "" : bez }
            return SelectionOption(id: Self.encode(fields), title: item.name)
        })
    }

    private func houseStep(_ session: Session, _ state: State) async throws -> SelectionStep? {
        let html = try await session.assistant("hnr/", [
            ("id_landkreis", state.landkreis),
            ("id_kommune", state.kommune),
            ("id_bezirk", state.bezirk),
            ("id_strasse", state.strasse),
        ])
        let items = Self.items(in: html)
        guard !items.isEmpty else { return nil }
        return SelectionStep(title: SelectionStep.houseNumberTitle, options: items.map { item in
            var fields: [String: String] = ["k": "hnr", "hnr": item.id]
            if let form = item.formStreet { fields["fstr"] = form }
            let title = (item.id.removingPercentEncoding ?? item.id).split(separator: "|").first.map(String.init) ?? item.id
            return SelectionOption(id: Self.encode(fields), title: title.replacingOccurrences(of: "+", with: " "))
        })
    }

    /// Ohne die Suchtexte der Straßensuche.
    public func label(for selections: [SelectionOption]) -> String {
        selections.filter { $0.id.contains("k=") && !$0.title.lowercased().hasPrefix("alle ") }.map(\.title).joined(separator: ", ")
    }

    // MARK: - Termine

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let (session, state, _) = try await replay(selections)
        guard !state.strasseForm.isEmpty || !state.bezirk.isEmpty else { throw ProviderError.selectAddressFirst }

        let address: [(String, String)] = [
            ("f_id_bundesland", state.bundesland),
            ("f_id_landkreis", state.landkreis),
            ("f_id_kommune", state.kommune),
            ("f_id_bezirk", ""),
            ("f_id_strasse", state.strasseForm.isEmpty ? state.strasse : state.strasseForm),
            ("f_hnr", state.hnr),
            ("f_kdnr", ""),
        ]
        let typesHTML = try await session.assistant("abfallarten/", [("f_id_region", state.region)] + address)
        var typeIDs = HTMLText.matches(#"name="f_id_abfallart\[\]"[^>]*>"#, in: typesHTML, wholeMatch: true).compactMap { tag -> String? in
            let value = HTMLText.firstMatch(#"value="([^"]*)""#, in: tag[0], group: 1) ?? ""
            if value != "0", !value.isEmpty { return value }
            return HTMLText.firstMatch(#"id="f_id_abfallart_([^"]+)""#, in: tag[0], group: 1)
        }
        typeIDs = Array(Set(typeIDs))
        guard !typeIDs.isEmpty else { throw ProviderError.noDataGeneric }

        var finish = address + typeIDs.map { ("f_id_abfallart[]", $0) } + [
            ("f_uhrzeit_tag", "86400|0"), ("f_uhrzeit_stunden", "54000"), ("f_uhrzeit_minuten", "600"),
            ("f_anonym", "1"), ("f_ausgangspunkt", "1"), ("f_ueberspringen", "0"),
        ]
        _ = try await session.assistant("ueberpruefen/", finish)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMddHHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        finish.append(("f_datenschutz", stamp.string(from: Date())))
        _ = try await session.assistant("finish/", finish)

        // Der Server stellt die Termine erst kurz nach dem Abschluss bereit.
        var xml = ""
        for attempt in 0..<4 {
            try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (attempt + 1)))
            _ = try await session.app("version.xml")
            _ = try await session.app("version.xml", query: "?renew=1")
            xml = HTTPClient.text(from: try await session.app("struktur.xml.zip"))
            if xml.contains("<key>dates</key>") { break }
        }

        let result = Self.parseStructure(xml, typeIDs: Set(typeIDs), calendar: calendar).filter { !Self.isPlaceholder($0.name) }
        guard !result.isEmpty else {
            throw ProviderError.noData(L10n.t("Der AbfallPlus-Server hat gerade keine Termine geliefert. Bitte in ein paar Minuten erneut versuchen.", "The AbfallPlus server returned no dates right now. Please try again in a few minutes."))
        }
        return result
    }

    /// Platzhalter, die der Server bei zu schnellen Anfragen statt echter Abfallarten schickt („Leni (39)“).
    static func isPlaceholder(_ name: String) -> Bool {
        name.range(of: #"^[A-ZÄÖÜ][a-zäöüßéèá]+ \(\d{1,3}\)$"#, options: .regularExpression) != nil
    }

    /// Liest Kategorien und Termine aus der Plist von `struktur.xml.zip`.
    static func parseStructure(_ xml: String, typeIDs: Set<String>, calendar: Calendar) -> [Pickup] {
        func section(_ key: String) -> String {
            guard let start = xml.range(of: "<key>\(key)</key>") else { return "" }
            let rest = xml[start.upperBound...]
            guard let open = rest.range(of: "<array>") else { return "" }
            var depth = 0
            var index = open.lowerBound
            while index < rest.endIndex {
                if rest[index...].hasPrefix("<array>") { depth += 1 }
                if rest[index...].hasPrefix("</array>") {
                    depth -= 1
                    if depth == 0 { return String(rest[open.upperBound..<index]) }
                }
                index = rest.index(after: index)
            }
            return String(rest[open.upperBound...])
        }
        func dicts(_ text: String) -> [[String: String]] {
            HTMLText.matches(#"<dict>([\s\S]*?)</dict>"#, in: text).map { groups in
                var result: [String: String] = [:]
                for pair in HTMLText.matches(#"<key>([^<]+)</key>\s*<string>([\s\S]*?)</string>"#, in: groups[0]) where pair.count == 2 {
                    result[pair[0]] = pair[1].replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return result
            }
        }
        var names: [String: String] = [:]
        for category in dicts(section("categories")) {
            guard let id = category["id"], let name = category["name"] else { continue }
            names[id] = name.replacingOccurrences(of: " (verlegt)", with: "")
        }
        var pickups: [Pickup] = []
        for entry in dicts(section("dates")) {
            guard let categoryID = entry["category_id"], let raw = entry["pickup_date"] else { continue }
            let parts = categoryID.split(separator: "-").map(String.init)
            if parts.count >= 2, !typeIDs.contains(parts[1]) { continue }
            guard let name = names[categoryID], let date = ICS.parseDate(String(raw.prefix(10)).replacingOccurrences(of: "-", with: ""), params: ["VALUE": "DATE"], calendar: calendar) else { continue }
            pickups.append(Pickup(date: date, name: NameCleaner.clean(name)))
        }
        return pickups.sorted { $0.date < $1.date }
    }
}

extension HTMLText {
    /// Alle `<input name="…" value="…">`, unabhängig vom Typ.
    static func allInputs(in html: String) -> [(name: String, value: String)] {
        matches(#"<input[^>]*>"#, in: html, wholeMatch: true).compactMap { tag in
            guard let name = firstMatch(#"name=["']([^"']*)["']"#, in: tag[0], group: 1) else { return nil }
            let value = firstMatch(#"value=["']([^"']*)["']"#, in: tag[0], group: 1) ?? ""
            return (decodeEntities(name), decodeEntities(value))
        }
    }
}
