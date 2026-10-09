import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Portale bayerischer Entsorger ohne gemeinsame Plattform. Ein Betreiber je `serviceKey`:
/// - `cham`: Landkreis Cham (PWA, Tourendaten als JSON)
/// - `schwandorf`: Landkreis Schwandorf (entsorgung-sad.de, ICS)
/// - `bamberg_lk`, `forchheim`: abfalltermine-bamberg.de / abfalltermine-forchheim.de (ICS je Ortsteil)
/// - `eva`: EVA Weilheim-Schongau (JSON-Export je Jahr)
/// - `erh`: Landkreis Erlangen-Höchstadt (ICS je Jahr)
/// - `neumarkt`, `schwabach`: abfuhrplan-*.de (ICS per POST `/getical`)
/// - `heinz`: Heinz Entsorgung, Landkreis Freising (JSON-API mit kodiertem `param`)
/// - `coburg`: CEB Coburg (ICS je Straße und Jahr)
/// - `fuerth`: Stadt Fürth (Straßensuche, Hausnummer, ICS)
/// - `schweinfurt`: Stadt Schweinfurt (Termin-JSON des Stadtportals)
/// - `hof_stadt`, `hof_lk`: AZV Hof für Stadt und Landkreis Hof (TYPO3-Formular, ICS)
/// - `amberg`: Stadt Amberg (Straßenverzeichnis als JSON, Termine aus der XLSX-Datei des Abfuhrgebiets)
/// - `nuernberger_land`: Landkreis Nürnberger Land (Ort → Ortsteil → Straße → ggf. Hausnummer, ICS)
/// - `rhoen_grabfeld`: Landkreis Rhön-Grabfeld (alle Termine als JSON, gefiltert nach Gemeinde/Ortsteil)
/// - `landkreis_as`: Landkreis Amberg-Sulzbach (Gemeinde → ggf. Ortsteil oder Straße, ICS nach Formular-POST)
public struct BayernPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsBayern
    public let serviceKey: String
    public var displayName: String { Self.titles[serviceKey] ?? kind.displayName }

    public var restriction: String? {
        serviceKey == "landkreis_as" ? L10n.t("Nur Restmüll und Altpapier.", "Residual waste and paper only.") : nil
    }

    /// Das Portal des Landratsamts Amberg-Sulzbach führt nur Restmüll und Altpapier.
    public var notice: String? {
        guard serviceKey == "landkreis_as" else { return nil }
        return L10n.t("Das Portal liefert nur Restmüll und Altpapier. Bio- und Wertstofftermine bitte als Rhythmus bei der Müllart einstellen.",
                      "The portal only provides residual waste and paper. Please set organic and recycling dates as a schedule on the waste type.")
    }
    private let client: HTTPClient
    /// Stichtag für Jahr/„heute“ (nil = jetzt); nur Tests setzen ihn, bisher nur `landkreis_as`.
    var referenceDate: Date?

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    static let titles: [String: String] = [
        "cham": "Abfallwirtschaft Landkreis Cham",
        "schwandorf": "Abfallwirtschaft Landkreis Schwandorf",
        "bamberg_lk": "Abfalltermine Landkreis Bamberg",
        "forchheim": "Abfalltermine Landkreis Forchheim",
        "eva": "EVA Weilheim-Schongau",
        "erh": "Landkreis Erlangen-Höchstadt",
        "neumarkt": "Abfuhrplan Landkreis Neumarkt",
        "schwabach": "Abfuhrplan Schwabach",
        "heinz": "Heinz Entsorgung (Landkreis Freising)",
        "coburg": "CEB Coburg",
        "fuerth": "Abfallwirtschaft Stadt Fürth",
        "schweinfurt": "Abfallwirtschaft Stadt Schweinfurt",
        "hof_stadt": "AZV Hof (Stadt Hof)",
        "hof_lk": "AZV Hof (Landkreis Hof)",
        "amberg": "Abfallberatung Stadt Amberg",
        "nuernberger_land": "Abfallwirtschaft Nürnberger Land",
        "rhoen_grabfeld": "Abfallwirtschaft Landkreis Rhön-Grabfeld",
        "landkreis_as": "Abfallwirtschaft Landkreis Amberg-Sulzbach",
    ]

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "cham": return try await chamStep(selections)
        case "schwandorf": return try await sadStep(selections)
        case "bamberg_lk", "forchheim": return try await abfalltermineStep(selections)
        case "eva": return try await evaStep(selections)
        case "erh": return try await erhStep(selections)
        case "neumarkt", "schwabach": return try await abfuhrplanStep(selections)
        case "heinz": return try await heinzStep(selections)
        case "coburg": return try await coburgStep(selections)
        case "fuerth": return try await fuerthStep(selections)
        case "schweinfurt": return try await schweinfurtStep(selections)
        case "hof_stadt", "hof_lk": return try await hofStep(selections)
        case "amberg": return try await ambergStep(selections)
        case "nuernberger_land": return try await nlStep(selections)
        case "rhoen_grabfeld": return try await rhoenStep(selections)
        case "landkreis_as": return try await asStep(selections)
        default: throw Self.unknown
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard !selections.isEmpty else { throw ProviderError.selectAddressFirst }
        let result: [Pickup]
        switch serviceKey {
        case "cham": result = try await chamPickups(selections, calendar: calendar)
        case "schwandorf": result = try await sadPickups(selections, calendar: calendar)
        case "bamberg_lk", "forchheim": result = try await abfallterminePickups(selections, calendar: calendar)
        case "eva": result = try await evaPickups(selections, calendar: calendar)
        case "erh": result = try await erhPickups(selections, calendar: calendar)
        case "neumarkt", "schwabach": result = try await abfuhrplanPickups(selections, calendar: calendar)
        case "heinz": result = try await heinzPickups(selections, calendar: calendar)
        case "coburg": result = try await coburgPickups(selections, calendar: calendar)
        case "fuerth": result = try await fuerthPickups(selections, calendar: calendar)
        case "schweinfurt": result = try await schweinfurtPickups(selections, calendar: calendar)
        case "hof_stadt", "hof_lk": result = try await hofPickups(selections, calendar: calendar)
        case "amberg": result = try await ambergPickups(selections, calendar: calendar)
        case "nuernberger_land": result = try await nlPickups(selections, calendar: calendar)
        case "rhoen_grabfeld": result = try await rhoenPickups(selections, calendar: calendar)
        case "landkreis_as": result = try await asPickups(selections, calendar: calendar)
        default: throw Self.unknown
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map(\.title).filter { !$0.isEmpty }
        switch serviceKey {
        case "cham", "schwandorf":
            // Ort, Straße Hausnummer+Zusatz
            guard let place = titles.first else { return "" }
            let street = titles.dropFirst().first ?? ""
            let number = titles.dropFirst(2).joined()
            return [place, [street, number].filter { !$0.isEmpty }.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: ", ")
        case "fuerth":
            // Erste Auswahl ist nur der Suchtext.
            return "Fürth, " + selections.dropFirst().map(\.title).filter { !$0.isEmpty }.joined(separator: " ")
        case "schwabach": return "Schwabach, " + titles.joined(separator: ", ")
        case "coburg": return "Coburg, " + titles.joined(separator: ", ")
        case "schweinfurt": return "Schweinfurt, " + titles.joined(separator: ", ")
        case "hof_stadt": return "Hof, " + titles.joined(separator: ", ")
        case "amberg": return "Amberg, " + titles.joined(separator: ", ")
        case "landkreis_as":
            // Bei der Straßensuche ist die zweite Auswahl nur der Suchtext.
            return (selections.count > 2 ? [selections[0], selections[2]] : selections).map(\.title).filter { !$0.isEmpty }.joined(separator: ", ")
        default: return titles.joined(separator: ", ")
        }
    }

    // MARK: - Gemeinsame Hilfen

    private static var unknown: ProviderError { .notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }

    private static func list(_ title: String, _ options: [SelectionOption], sort: Bool = true) throws -> SelectionStep {
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        var seen = Set<String>()
        let unique = options.filter { seen.insert($0.id).inserted }
        let sorted = sort ? unique.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } : unique
        return SelectionStep(title: title, options: sorted)
    }

    /// Termine aus einer ICS-Datei; `split` zerlegt einen Titel in einzelne Fraktionen (mit optionaler Notiz).
    private static func ics(_ text: String, calendar: Calendar, split: (String) -> [(name: String, note: String?)] = { [($0, nil)] }) -> [Pickup] {
        ICS.parse(text, calendar: calendar).flatMap { event in
            split(event.summary).compactMap { part -> Pickup? in
                let name = NameCleaner.clean(part.name)
                guard !name.isEmpty, !WasteCategory.isIgnorableTitle(name) else { return nil }
                return Pickup(date: event.date, name: name, note: part.note)
            }
        }
    }

    private static func query(_ fields: [(String, String)]) -> String {
        fields.map { "\($0.0)=\(HTTPClient.formEncode($0.1))" }.joined(separator: "&")
    }

    /// Pfad mit Umlauten/Leerzeichen sicher kodieren (bereits kodierte Pfade bleiben gleich).
    private static func encodePath(_ path: String) -> String {
        let plain = path.removingPercentEncoding ?? path
        return plain.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? plain
    }

    private static func json(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    private static func currentYear(_ calendar: Calendar) -> Int {
        calendar.component(.year, from: Date())
    }

    /// Sitzungs-Cookies einer Seite als `Cookie`-Kopfzeile (HTTPClient gibt keine Antwort-Header heraus).
    private static func cookies(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await HTTPClient.defaultSession.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        var fields: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            // HTTP/2 liefert „set-cookie“ klein – für HTTPCookie die übliche Schreibweise
            if let key = key as? String, let value = value as? String { fields[key.lowercased() == "set-cookie" ? "Set-Cookie" : key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        return cookies.isEmpty ? nil : cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

// MARK: - Landkreis Cham (pwa.entsorgung-cham.de)

extension BayernPortalsProvider {
    private static let chamBase = "https://pwa.entsorgung-cham.de/php/"

    /// `complete = [{ label: '93474 Arrach', value: '2' }, …]`
    private static func chamCompletes(_ html: String) -> [(label: String, value: String)] {
        HTMLText.matches(#"label:\s*'((?:[^'\\]|\\.)*)',\s*value:\s*'([^']*)'"#, in: html).map {
            (HTMLText.decodeEntities($0[0].replacingOccurrences(of: "\\'", with: "'")), $0[1])
        }
    }

    private static func chamQuery(_ s: [SelectionOption]) -> String {
        let place = s[0].id.components(separatedBy: "|")
        return query([
            ("ort", place.first ?? ""), ("ort_ID", place.count > 1 ? place[1] : ""),
            ("strasse", s.count > 1 ? s[1].id : ""), ("nr", s.count > 2 ? s[2].id : ""), ("zusatz", s.count > 3 ? s[3].id : ""),
        ])
    }

    private func chamStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let html = try await client.string(Self.chamBase + "loadCompletes.php?what=ort")
            let options = Self.chamCompletes(html).map { item -> SelectionOption in
                let parts = item.label.split(separator: " ", maxSplits: 1).map(String.init)
                let hasZip = parts.count == 2 && parts[0].allSatisfy(\.isNumber)
                return SelectionOption(id: "\(item.label)|\(item.value)", title: hasZip ? parts[1] : item.label, subtitle: hasZip ? parts[0] : nil)
            }
            return try Self.list(SelectionStep.cityTitle, options)
        case 1:
            let html = try await client.string(Self.chamBase + "loadCompletes.php?what=strasse&" + Self.chamQuery(s))
            let streets = Self.chamCompletes(html).map { SelectionOption(id: $0.label, title: $0.label) }
            return streets.isEmpty ? nil : try Self.list(SelectionStep.streetTitle, streets)
        case 2, 3:
            // Nur wenn die Straße mehrere Touren hat, fragt das Portal Hausnummer bzw. Zusatz ab.
            let result = try await client.string(Self.chamBase + "queryTouren.php?" + Self.chamQuery(s))
            guard result.contains("mehrere") else { return nil }
            let what = s.count == 2 ? "nr" : "zusatz"
            let html = try await client.string(Self.chamBase + "loadCompletes.php?what=\(what)&" + Self.chamQuery(s))
            let options = Self.chamCompletes(html).map { SelectionOption(id: $0.label, title: $0.label) }
            return try Self.list(s.count == 2 ? SelectionStep.houseNumberTitle : L10n.t("Hausnummernzusatz", "House number suffix"), options, sort: false)
        default:
            return nil
        }
    }

    private func chamPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let html = try await client.string(Self.chamBase + "queryTouren.php?" + Self.chamQuery(s))
        if html.contains("mehrere") {
            throw ProviderError.invalidSelection(L10n.t("Bitte die Hausnummer wählen.", "Please choose the house number."))
        }
        guard let raw = HTMLText.firstMatch(#"daten\s*=\s*(\{[^;]*\})\s*;"#, in: html, group: 1),
              let daten = Self.json(Data(raw.utf8)) as? [String: [String]] else { throw ProviderError.noDataGeneric }
        let names = ["rm": "Restmüll", "pt": "Papiertonne", "ws": "Biotonne", "um": "Umweltmobil (Schadstoffe)", "pm": "Problemmüll-Sammelstelle (Schadstoffe)"]
        return daten.flatMap { day, codes -> [Pickup] in
            guard let date = Days.parse(day, calendar: calendar) else { return [] }
            return Set(codes).map { Pickup(date: date, name: names[$0] ?? $0) }
        }
    }
}

// MARK: - Landkreis Schwandorf (entsorgung-sad.de)

extension BayernPortalsProvider {
    private static let sadBase = "https://entsorgung-sad.de/"

    /// `var strasseTags = [ "A", "B" ];` → ["A", "B"]
    private static func sadTags(_ name: String, in html: String) -> [String] {
        guard let block = HTMLText.firstMatch(name + #"Tags\s*=\s*\[([\s\S]*?)\]"#, in: html, group: 1) else { return [] }
        return HTMLText.matches(#""((?:[^"\\]|\\.)*)""#, in: block).compactMap { $0.first }.map(HTMLText.decodeEntities).filter { !$0.isEmpty }
    }

    /// Adressteil der Anfrage: Ort (plz|ort|ort_ID aus der Straßen-Kennung), Straße, Nummer, Zusatz.
    private static func sadAddress(_ s: [SelectionOption]) -> [(String, String)] {
        guard s.count > 1 else { return [] }
        let parts = s[1].id.components(separatedBy: "|")
        guard parts.count == 4 else { return [] }
        var fields = [("plz", parts[0]), ("ort", parts[1]), ("ort_ID", parts[2]), ("strasse", parts[3])]
        if s.count > 2 { fields.append(("nr", s[2].id)) }
        if s.count > 3 { fields.append(("zusatz", s[3].id)) }
        return fields
    }

    /// Antwort des jeweils letzten Prüfschritts (strasse.php / nr.php / zusatz.php).
    private func sadCheck(_ s: [SelectionOption]) async throws -> String {
        let script = ["strasse", "nr", "zusatz"][min(s.count, 4) - 2]
        return try await client.string(Self.sadBase + "steuerung/\(script).php?" + Self.query(Self.sadAddress(s)))
    }

    private func sadStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let html = try await client.string(Self.sadBase)
            let options = Self.sadTags("plz", in: html).map { label -> SelectionOption in
                let parts = label.split(separator: " ", maxSplits: 1).map(String.init)
                return SelectionOption(id: label, title: parts.count == 2 ? parts[1] : label, subtitle: parts.count == 2 ? parts[0] : nil)
            }
            return try Self.list(SelectionStep.cityTitle, options)
        case 1:
            let place = try await client.string(Self.sadBase + "steuerung/plz.php?plz=" + HTTPClient.formEncode(s[0].id))
            let hidden = Dictionary(HTMLText.hiddenInputs(in: place).map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
            guard let zip = hidden["plz"], let town = hidden["ort"], let townID = hidden["ort_ID"] else { throw ProviderError.noDataGeneric }
            let html = try await client.string(Self.sadBase + "steuerung/autocomplete.php?check=strasse&" + Self.query([("plz", zip), ("ort", town), ("ort_ID", townID)]))
            let options = Self.sadTags("strasse", in: html).map { SelectionOption(id: "\(zip)|\(town)|\(townID)|\($0)", title: $0) }
            return try Self.list(SelectionStep.streetTitle, options)
        case 2, 3:
            let html = try await sadCheck(s)
            guard !html.contains("id=\"fertig\"") else { return nil }
            let check = s.count == 2 ? "nr" : "zusatz"
            let tags = try await client.string(Self.sadBase + "steuerung/autocomplete.php?check=\(check)&" + Self.query(Self.sadAddress(s)))
            let options = Self.sadTags(check, in: tags).map { SelectionOption(id: $0, title: $0) }
            return try Self.list(s.count == 2 ? SelectionStep.houseNumberTitle : L10n.t("Hausnummernzusatz", "House number suffix"), options, sort: false)
        default:
            return nil
        }
    }

    private func sadPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 2 else { throw ProviderError.selectAddressFirst }
        let html = try await sadCheck(s)
        guard html.contains("id=\"fertig\"") else {
            throw ProviderError.invalidSelection(L10n.t("Bitte die Hausnummer wählen.", "Please choose the house number."))
        }
        // Tourennummern (rm, pt, ws, spm) stehen als versteckte Felder in der Antwort.
        var fields = Self.sadAddress(s)
        let known = Set(fields.map(\.0))
        fields += HTMLText.hiddenInputs(in: html).filter { !known.contains($0.name) }.map { ($0.name, $0.value) }
        for name in ["nr", "zusatz", "email"] where !fields.contains(where: { $0.0 == name }) { fields.append((name, "")) }
        let text = try await client.string(Self.sadBase + "steuerung/ics.php?" + Self.query(fields))
        // Titel „Restmüll 13.01.2026“ → „Restmüll“
        return Self.ics(text, calendar: calendar) { [($0.replacingOccurrences(of: #"\s*\d{2}\.\d{2}\.\d{4}$"#, with: "", options: .regularExpression), nil)] }
    }
}

// MARK: - abfalltermine-bamberg.de / abfalltermine-forchheim.de

extension BayernPortalsProvider {
    private var abfallterminePortal: (host: String, path: String) {
        serviceKey == "forchheim"
            ? ("https://www.abfalltermine-forchheim.de", "/Forchheim/Landkreis/")
            : ("https://www.abfalltermine-bamberg.de", "/Bamberg/Landkreis/")
    }

    /// Alle Einträge „Gemeinde - Ortsteil“ (oder nur „Gemeinde“) aus den Links der Startseite.
    private func abfallterminePlaces() async throws -> [String] {
        let portal = abfallterminePortal
        let html = try await client.string(portal.host + "/")
        let escaped = NSRegularExpression.escapedPattern(for: portal.path)
        let keys = HTMLText.matches(#"href="\#(escaped)([^"/?#]+)""#, in: html).compactMap { $0.first }
            .map { HTMLText.decodeEntities($0.removingPercentEncoding ?? $0) }
        return Array(Set(keys))
    }

    private func abfalltermineStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let towns = Set(try await abfallterminePlaces().map { $0.components(separatedBy: " - ")[0] })
            return try Self.list(SelectionStep.cityTitle, towns.map { SelectionOption(id: $0, title: $0) })
        case 1:
            let town = s[0].id
            let entries = try await abfallterminePlaces().filter { $0 == town || $0.hasPrefix(town + " - ") }
            if entries == [town] { return nil }
            let options = entries.map { key in
                SelectionOption(id: key, title: key == town ? town : String(key.dropFirst(town.count + 3)))
            }
            return try Self.list(SelectionStep.districtTitle, options)
        default:
            return nil
        }
    }

    private func abfallterminePickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let portal = abfallterminePortal
        let key = s.count > 1 ? s[1].id : s[0].id
        let text = try await client.string(portal.host + Self.encodePath(portal.path + key) + "/ics")
        return Self.ics(text, calendar: calendar)
    }
}

// MARK: - EVA Weilheim-Schongau (eva-abfallentsorgung.de)

extension BayernPortalsProvider {
    private static let evaBase = "https://www.eva-abfallentsorgung.de/json_export/"
    private struct EvaID: Decodable { let id: Int }
    private struct EvaPlace: Decodable { let strassen: [String: Int] }

    private func evaPlaces(_ year: Int) async throws -> [String: EvaID] {
        try await client.json(Self.evaBase + "\(year)/main.json")
    }

    private func evaStreets(_ year: Int, place: String) async throws -> [String: Int] {
        guard let id = try await evaPlaces(year)[place]?.id else { throw ProviderError.noDataGeneric }
        let result: EvaPlace = try await client.json(Self.evaBase + "\(year)/ort_\(id).json")
        return result.strassen
    }

    private func evaStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        let year = Self.currentYear(.current)
        switch s.count {
        case 0:
            let places = try await evaPlaces(year)
            return try Self.list(SelectionStep.cityTitle, places.keys.map { SelectionOption(id: $0, title: $0) })
        case 1:
            let streets = try await evaStreets(year, place: s[0].id)
            return try Self.list(L10n.t("Straße / Ortsteil", "Street / district"), streets.keys.map { SelectionOption(id: $0, title: $0) })
        default:
            return nil
        }
    }

    private func evaPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 2 else { throw ProviderError.selectAddressFirst }
        let names = ["Rest": "Restmüll", "Bio": "Biomüll", "Papier": "Papiersammlung", "Gelb": "Gelber Sack", "Gift": "Giftmobil (Schadstoffsammlung)"]
        let year = Self.currentYear(calendar)
        var result: [Pickup] = []
        // Kennungen können je Jahr wechseln – daher pro Jahr über die Namen auflösen.
        for target in [year, year + 1] {
            guard let streets = try? await evaStreets(target, place: s[0].id), let id = streets[s[1].id],
                  let data = try? await client.get(Self.evaBase + "\(target)/strasse_\(id).json"),
                  let root = Self.json(data) as? [String: Any], let all = root["all"] as? [String: Any] else { continue }
            for (day, value) in all {
                guard let date = Days.parse(day, calendar: calendar) else { continue }
                for (kind, note) in Self.evaEntries(value) where kind != "Zeitung" {
                    result.append(Pickup(date: date, name: names[kind] ?? kind, note: note))
                }
            }
        }
        return result
    }

    /// Ein Tageseintrag ist ein Name, eine Liste oder ein Objekt (Schlüssel = Art, z. B. Giftmobil mit Standort).
    private static func evaEntries(_ value: Any) -> [(String, String?)] {
        switch value {
        case let name as String:
            return [(name, nil)]
        case let list as [Any]:
            return list.flatMap { evaEntries($0) }
        case let object as [String: Any]:
            return object.flatMap { key, inner -> [(String, String?)] in
                if let name = inner as? String { return [(name, nil)] }
                let location = (inner as? [String: Any])?["location"] as? String
                return [(key, location?.trimmingCharacters(in: .whitespaces))]
            }
        default:
            return []
        }
    }
}

// MARK: - Landkreis Erlangen-Höchstadt

extension BayernPortalsProvider {
    private static let erhBase = "https://www.erlangen-hoechstadt.de/"
    private struct ErhStreet: Decodable { let Strasse: String }

    private func erhStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let html = try await client.string(Self.erhBase + "aktuelles/abfallkalender/")
            let options = HTMLText.options(ofSelect: "ldOrt", in: html).filter { $0.value != "-1" && !$0.value.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            return try Self.list(SelectionStep.cityTitle, options)
        case 1:
            let body = try JSONSerialization.data(withJSONObject: ["ort": s[0].id])
            let data = try await client.post(Self.erhBase + "komx/surface/dfxabfall/GetByOrt", body: body, contentType: "application/json; charset=utf-8")
            let streets: [ErhStreet] = try HTTPClient.decode(data)
            return try Self.list(L10n.t("Ortsteil / Straße", "District / street"), streets.map { SelectionOption(id: $0.Strasse, title: $0.Strasse) })
        default:
            return nil
        }
    }

    private func erhPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 2 else { throw ProviderError.selectAddressFirst }
        let year = Self.currentYear(calendar)
        var result: [Pickup] = []
        for target in [year, year + 1] {
            let url = Self.erhBase + "komx/surface/dfxabfallics/GetAbfallIcs?" + Self.query([("ort", s[0].id), ("strasse", s[1].id), ("abfallart", "Alle"), ("jahr", String(target))])
            guard let text = try? await client.string(url) else { continue }
            result += Self.ics(text, calendar: calendar, split: Self.erhSplit)
        }
        return result
    }

    /// „Restmülltonne / Biotonne / Restmüllcontainer , Di“ → Restmülltonne, Biotonne;
    /// „Gartenabfall , Fr, 16.00 - 18.00, Trautenauer Str., Süd“ → Gartenabfall mit Ort und Zeit als Notiz.
    static func erhSplit(_ summary: String) -> [(name: String, note: String?)] {
        let parts = summary.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let weekdays: Set<String> = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let details = parts.dropFirst().filter { !$0.isEmpty && !weekdays.contains($0) }
        let note = details.isEmpty ? nil : details.joined(separator: ", ")
        return (parts.first ?? summary).components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().hasSuffix("container") }
            .map { ($0, note) }
    }
}

// MARK: - abfuhrplan-landkreis-neumarkt.de / abfuhrplan-schwabach.de

extension BayernPortalsProvider {
    private var abfuhrplanBase: String {
        serviceKey == "schwabach" ? "https://www.abfuhrplan-schwabach.de" : "https://www.abfuhrplan-landkreis-neumarkt.de"
    }

    /// Einträge `<li class="list-group-item"><a href="…">Name</a>`.
    private func abfuhrplanLinks(_ url: String) async throws -> [SelectionOption] {
        let html = try await client.string(url)
        return HTMLText.matches(#"list-group-item[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>([^<]+)<"#, in: html).map {
            let title = HTMLText.decodeEntities($0[1]).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return SelectionOption(id: HTMLText.decodeEntities($0[0]), title: title.trimmingCharacters(in: .whitespaces))
        }
    }

    private func abfuhrplanStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        let levels = serviceKey == "schwabach" ? 1 : 2
        guard s.count < levels else { return nil }
        let url = s.isEmpty ? abfuhrplanBase + "/" : s[0].id
        let title = s.isEmpty && levels == 2 ? SelectionStep.cityTitle : L10n.t("Straße / Ortsteil", "Street / district")
        return try Self.list(title, try await abfuhrplanLinks(url), sort: s.isEmpty && levels == 2 ? false : true)
    }

    private func abfuhrplanPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = s.last?.id, s.count == (serviceKey == "schwabach" ? 1 : 2) else { throw ProviderError.selectAddressFirst }
        let html = try await client.string(street)
        guard let form = HTMLText.firstMatch(#"<form[^>]*action="/getical"[^>]*>([\s\S]*?)</form>"#, in: html, group: 1) else { throw ProviderError.noDataGeneric }
        // Formular wie im Browser absenden: versteckte Felder, voreingestellte Häkchen, keine Erinnerung.
        var fields: [(String, String)] = []
        for tag in HTMLText.matches(#"<input[^>]*>"#, in: form, wholeMatch: true).map({ $0[0] }) {
            guard let name = HTMLText.firstMatch(#"name="([^"]*)""#, in: tag, group: 1) else { continue }
            let value = HTMLText.decodeEntities(HTMLText.firstMatch(#"value="([^"]*)""#, in: tag, group: 1) ?? "")
            let type = HTMLText.firstMatch(#"type="([^"]*)""#, in: tag, group: 1)?.lowercased() ?? "text"
            if type == "checkbox" && !tag.contains("checked") { continue }
            fields.append((HTMLText.decodeEntities(name), value))
        }
        for name in HTMLText.matches(#"<select[^>]*name="([^"]*)""#, in: form).compactMap(\.first) { fields.append((name, "0")) }
        // „embed“ leitet auf webcal:// um – daher den Download-Knopf nehmen.
        let buttons = HTMLText.matches(#"<button[^>]*name="([^"]*)"[^>]*value="([^"]*)""#, in: form)
        if let button = buttons.first(where: { $0[1] == "download" }) ?? buttons.first { fields.append((button[0], button[1])) }
        let data = try await client.postForm(abfuhrplanBase + "/getical", fields: fields)
        return Self.ics(HTTPClient.text(from: data), calendar: calendar)
    }
}

// MARK: - Heinz Entsorgung, Landkreis Freising

extension BayernPortalsProvider {
    private static let heinzAPI = "https://api-enttermine.heinz-entsorgung.net/"
    private struct HeinzPlace: Decodable { let ort: String }
    private struct HeinzStreet: Decodable { let strasse: String }
    private struct HeinzDate: Decodable { let termin: String; let fraktion: String; let zusatz: String? }

    /// Die Web-App verschickt JSON als Base64, bei dem je zwei Zeichen vertauscht sind.
    static func heinzParam(_ fields: [(String, String)]) -> String {
        let escape = { (value: String) in value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let json = "{" + fields.map { "\"\($0.0)\":\"\(escape($0.1))\"" }.joined(separator: ",") + "}"
        var chars = Array(Data(json.utf8).base64EncodedString())
        var index = 0
        while index + 1 < chars.count {
            chars.swapAt(index, index + 1)
            index += 2
        }
        return String(chars)
    }

    private func heinzGet<T: Decodable>(_ endpoint: String, _ fields: [(String, String)]) async throws -> T {
        let param = Self.heinzParam([("landkreis", "Landkreis Freising")] + fields)
        return try await client.json(Self.heinzAPI + endpoint + "?param=" + HTTPClient.query(param))
    }

    private func heinzStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let places: [HeinzPlace] = try await heinzGet("orte", [])
            return try Self.list(SelectionStep.cityTitle, places.map { SelectionOption(id: $0.ort, title: $0.ort) })
        case 1:
            let streets: [HeinzStreet] = try await heinzGet("strassen", [("ort", s[0].id)])
            return try Self.list(SelectionStep.streetTitle, streets.map { SelectionOption(id: $0.strasse, title: $0.strasse) })
        default:
            return nil
        }
    }

    private func heinzPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 2 else { throw ProviderError.selectAddressFirst }
        let names = ["BIO": "Biotonne", "Papier": "Papiertonne"]
        let year = Self.currentYear(calendar)
        var result: [Pickup] = []
        for target in [year, year + 1] {
            guard let dates: [HeinzDate] = try? await heinzGet("termine", [("ort", s[0].id), ("strasse", s[1].id), ("jahr", String(target))]) else { continue }
            result += dates.compactMap { item in
                guard let date = Days.parse(item.termin, calendar: calendar) else { return nil }
                // Zusatz unterscheidet Behältergrößen („nur 240“, „nur 1,1 m³“).
                let base = names[item.fraktion] ?? item.fraktion
                let extra = item.zusatz?.trimmingCharacters(in: .whitespaces) ?? ""
                return Pickup(date: date, name: NameCleaner.clean(extra.isEmpty ? base : "\(base) (\(extra))"))
            }
        }
        return result
    }
}

// MARK: - CEB Coburg

extension BayernPortalsProvider {
    private static let coburgBase = "https://abfuhrkalender.ceb-coburg.de"

    private func coburgStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        guard s.isEmpty else { return nil }
        let html = try await client.string(Self.coburgBase + "/")
        let options = HTMLText.matches(#"class="street[^"]*"\s*href="([^"]+)"[^>]*>([^<]+)<"#, in: html).map {
            SelectionOption(id: HTMLText.decodeEntities($0[0]), title: HTMLText.decodeEntities($0[1]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Self.list(SelectionStep.streetTitle, options)
    }

    private func coburgPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let url = Self.coburgBase + Self.encodePath(s[0].id)
        var result: [Pickup] = []
        for parameter in ["getCalendarDates", "getCalendarDatesNextyear"] {
            guard let text = try? await client.string(url + "?\(parameter)=1") else { continue }
            result += Self.ics(text, calendar: calendar) { summary in
                // In Coburg ist die grüne Tonne die Papiertonne.
                let lower = summary.lowercased()
                if lower.contains("schwarz") { return [("Restmüll (schwarze Tonne)", nil)] }
                if lower.contains("grün") { return [("Papiertonne (grüne Tonne)", nil)] }
                if lower.contains("gelb") { return [("Gelbe Tonne", nil)] }
                if lower.contains("braun") { return [("Biotonne (braune Tonne)", nil)] }
                return [(summary.replacingOccurrences(of: "Abholung ", with: ""), nil)]
            }
        }
        return result
    }
}

// MARK: - Stadt Fürth (abfallwirtschaft.fuerth.eu)

extension BayernPortalsProvider {
    private static let fuerthURL = "https://abfallwirtschaft.fuerth.eu/termine.php"
    private static let ajax = ["Accept": "application/json", "X-Requested-With": "XMLHttpRequest"]
    private struct FuerthStreet: Decodable { let value: String }
    private struct FuerthNumber: Decodable { let i: String; let n: String }

    private func fuerthStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Mühltalstraße", "e.g. Mühltalstraße"))
        case 1:
            let text = s[0].title.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else {
                throw ProviderError.invalidSelection(L10n.t("Bitte mindestens zwei Buchstaben eingeben.", "Please enter at least two letters."))
            }
            let data = try await client.get(Self.fuerthURL + "?c=" + HTTPClient.query(text), headers: Self.ajax)
            let streets: [FuerthStreet] = try HTTPClient.decode(data)
            guard !streets.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Keine passende Straße gefunden.", "No matching street found."))
            }
            return try Self.list(SelectionStep.streetTitle, streets.map { SelectionOption(id: $0.value, title: $0.value) })
        case 2:
            let data = try await client.get(Self.fuerthURL + "?r=" + HTTPClient.query(s[1].id), headers: Self.ajax)
            let numbers: [FuerthNumber] = try HTTPClient.decode(data)
            let options = numbers.map {
                SelectionOption(id: $0.i, title: $0.n.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces))
            }
            return try Self.list(SelectionStep.houseNumberTitle, options, sort: false)
        default:
            return nil
        }
    }

    private func fuerthPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 3 else { throw ProviderError.selectAddressFirst }
        let text = try await client.string(Self.fuerthURL + "?icalexport=" + HTTPClient.query(s[2].id))
        return Self.ics(text, calendar: calendar) { $0.components(separatedBy: "/").map { ($0.trimmingCharacters(in: .whitespaces), nil) } }
    }
}

// MARK: - Stadt Schweinfurt

extension BayernPortalsProvider {
    private static let schweinfurtURL = "https://www.schweinfurt.de/umweltverkehr/abfall--entsorgung/mllkalender/14894.Aktuelle-Abfuhrtermine-und-Muellkalender.html"

    private func schweinfurtStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        guard s.isEmpty else { return nil }
        let html = try await client.string(Self.schweinfurtURL)
        let options = HTMLText.options(ofSelect: "ev[addr]", in: html).filter { !$0.value.isEmpty }
            .map { SelectionOption(id: $0.value, title: $0.label) }
        return try Self.list(SelectionStep.streetTitle, options)
    }

    private func schweinfurtPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        // Erst die Seite laden: Das Portal liefert Termine nur mit dem dabei gesetzten Cookie.
        var headers = ["Referer": Self.schweinfurtURL, "Accept": "application/json"]
        if let cookie = await Self.cookies(from: Self.schweinfurtURL) { headers["Cookie"] = cookie }
        let year = Self.currentYear(calendar)
        let url = Self.schweinfurtURL + "?_func=evList&_mod=events&" + Self.query([
            ("ev[start]", "\(year)-01-01"), ("ev[end]", "\(year + 1)-12-31"), ("ev[addr]", s[0].id),
        ])
        let data = try await client.get(url, headers: headers)
        guard let root = Self.json(data) as? [String: Any], let contents = root["contents"] as? [String: Any] else { return [] }
        return contents.values.compactMap { $0 as? [String: Any] }.flatMap { entry -> [Pickup] in
            guard let title = entry["title"] as? String, let start = entry["start"] as? String,
                  let date = Days.parse(String(start.prefix(10)), calendar: calendar) else { return [] }
            // Wertstoffhof-Hinweise (geschlossen, mobiler Wertstoffhof) sind keine Abholungen an der Adresse.
            let lower = title.lowercased()
            if lower.contains("wertstoffhof") || lower.contains("geschlossen") || lower.contains("kompostverkauf") { return [] }
            return title.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .map { Pickup(date: date, name: NameCleaner.clean($0)) }
        }
    }
}

// MARK: - Stadt Amberg (Straßenverzeichnis als JSON, Termine als XLSX je Abfuhrgebiet)

extension BayernPortalsProvider {
    private static let ambergBase = "https://amberg.de/fileadmin/Abfallberatung/Abfuhrkalender/"

    /// Straße → Abfuhrgebiet (z. B. „C4“) eines Jahres.
    private func ambergZones(_ year: Int) async throws -> [String: String] {
        let data = try await client.get(Self.ambergBase + "\(year)/ICS/\(year)_Strassenverzeichnis.json")
        guard let list = Self.json(data) as? [[String: Any]] else { throw ProviderError.noDataGeneric }
        var zones: [String: String] = [:]
        for entry in list {
            guard let zone = entry["gebiet"] as? String,
                  let street = entry.first(where: { $0.key != "gebiet" })?.value as? String else { continue }
            zones[street.trimmingCharacters(in: .whitespaces)] = zone.uppercased().trimmingCharacters(in: .whitespaces)
        }
        return zones
    }

    private func ambergStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        guard s.isEmpty else { return nil }
        let year = Self.currentYear(.current)
        var zones = (try? await ambergZones(year)) ?? [:]
        if zones.isEmpty { zones = try await ambergZones(year + 1) }
        let options = zones.map { SelectionOption(id: $0.key, title: $0.key, subtitle: L10n.t("Abfuhrgebiet \($0.value)", "Area \($0.value)")) }
        return try Self.list(SelectionStep.streetTitle, options)
    }

    private func ambergPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let year = Self.currentYear(calendar)
        var result: [Pickup] = []
        for target in [year, year + 1] {
            guard let zone = try? await ambergZones(target)[s[0].id], zone.count == 2,
                  let data = try? await client.get(Self.ambergBase + "\(target)/ICS/Abfuhrkalender_\(target)_Online\(zone).xlsx"),
                  let rows = XLSX.rows(of: "Dateneingabe", in: data) else { continue }
            result += Self.ambergParse(rows, zone: zone, calendar: calendar)
        }
        return result
    }

    /// Tabelle „Dateneingabe“: A = Datum (Excel-Zahl), C = Gebietsbuchstabe, F–I = Unternummern je Fraktion
    /// (z. B. „34“ = Gebiete 3 und 4). Spalten J–L (Problemmüll, Häckselgut, Sperrmüll) sind keinem Gebiet zugeordnet.
    static func ambergParse(_ rows: [[String: String]], zone: String, calendar: Calendar) -> [Pickup] {
        let letter = String(zone.prefix(1)), number = String(zone.suffix(1))
        let columns = ["F": "Restmüll", "G": "Biomüll", "H": "Papiertonne", "I": "Gelber Sack"]
        guard let epoch = Days.make(year: 1899, month: 12, day: 30, calendar: calendar) else { return [] }
        return rows.flatMap { row -> [Pickup] in
            guard row["C"] == letter, let serial = Double(row["A"] ?? ""), serial > 0 else { return [] }
            let date = Days.add(Int(serial), to: epoch, calendar: calendar)
            return columns.compactMap { column, name in
                guard let value = row[column], value.contains(number) else { return nil }
                return Pickup(date: date, name: name)
            }
        }
    }
}

// MARK: - Landkreis Nürnberger Land (abfuhrkalender.nuernberger-land.de)

extension BayernPortalsProvider {
    private static let nlBase = "https://abfuhrkalender.nuernberger-land.de/waste_calendar/"
    private struct NLItem: Decodable { let id: String; let name: String }
    private struct NLSections: Decodable {
        let type: String
        let id: String?
        let numbers: [NLNumber]?
    }
    private struct NLNumber: Decodable {
        let id: String
        let name: String
        enum CodingKeys: String, CodingKey { case id, name }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            // Hausnummern kommen teils als Zahl, teils als Text.
            if let number = try? container.decode(Int.self, forKey: .name) { name = String(number) } else { name = try container.decode(String.self, forKey: .name) }
        }
    }

    /// Die Seite liefert doppelt kodiertes UTF-8 („NÃ¼rnberg“).
    private static func repairUTF8(_ text: String) -> String {
        guard text.contains("Ã") else { return text }
        return text.data(using: .isoLatin1).flatMap { String(data: $0, encoding: .utf8) } ?? text
    }

    private func nlJSON<T: Decodable>(_ path: String) async throws -> T {
        let data = try await client.get(Self.nlBase + path, headers: Self.ajax)
        return try HTTPClient.decode(data)
    }

    private func nlStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let html = Self.repairUTF8(try await client.string(Self.nlBase + "calendar"))
            let options = HTMLText.options(ofSelect: "filter_city_id", in: html).filter { !$0.value.isEmpty && $0.value != "0" && !$0.label.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            return try Self.list(SelectionStep.cityTitle, options)
        case 1:
            let districts: [NLItem] = try await nlJSON("get_city_districts?id=" + HTTPClient.query(s[0].id))
            return try Self.list(SelectionStep.districtTitle, districts.map { SelectionOption(id: $0.id, title: $0.name) })
        case 2:
            let streets: [NLItem] = try await nlJSON("get_city_streets?id=\(HTTPClient.query(s[1].id))&city_id=\(HTTPClient.query(s[0].id))")
            return try Self.list(SelectionStep.streetTitle, streets.map { SelectionOption(id: $0.id, title: $0.name) })
        case 3:
            let sections: NLSections = try await nlJSON("get_street_sections?id=" + HTTPClient.query(s[2].id))
            guard sections.type == "multi", let numbers = sections.numbers else { return nil }
            // Mehrere Hausnummern teilen sich einen Abschnitt – Kennung daher mit Nummer.
            return try Self.list(SelectionStep.houseNumberTitle, numbers.map { SelectionOption(id: "\($0.id)|\($0.name)", title: $0.name) }, sort: false)
        default:
            return nil
        }
    }

    private func nlPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 3 else { throw ProviderError.selectAddressFirst }
        let section: String
        if s.count > 3 {
            section = s[3].id.components(separatedBy: "|")[0]
        } else {
            let sections: NLSections = try await nlJSON("get_street_sections?id=" + HTTPClient.query(s[2].id))
            guard let id = sections.id ?? sections.numbers?.first?.id else { throw ProviderError.noDataGeneric }
            section = id
        }
        // Die Kalenderansicht nennt die Gruppe, die zur ICS-Kennung gehört.
        let page = try await client.string(Self.nlBase + "get_calendar_data?id=\(HTTPClient.query(section))&cid=false", headers: Self.ajax)
        guard let group = HTMLText.firstMatch(#"id="tg_group_id"[^>]*value="([^"]*)""#, in: page, group: 1) else { throw ProviderError.noDataGeneric }
        let data = try await client.get(Self.nlBase + "ical?id=\(HTTPClient.query(group))-\(HTTPClient.query(section))&filter=rm:bio:p:dsd:poison&reminder=")
        // Gekürzte Titel enden teils mitten in einem Umlaut – nachsichtig als UTF-8 lesen statt Latin-1.
        return Self.ics(String(decoding: data, as: UTF8.self), calendar: calendar) { summary in
            // „Giftmobil Ort/Standort“ ist ein Termin mit Ort; sonst „Restmüll/Biotonne“ = zwei Fraktionen.
            if summary.hasPrefix("Giftmobil") {
                return [("Giftmobil (Schadstoffe)", String(summary.dropFirst("Giftmobil".count)).trimmingCharacters(in: .whitespaces))]
            }
            return summary.components(separatedBy: "/").map { part in
                let name = part.trimmingCharacters(in: .whitespaces)
                return (name.prefix(1).uppercased() + name.dropFirst(), nil)
            }
        }
    }
}

// MARK: - Landkreis Rhön-Grabfeld (abfallinfo-rhoen-grabfeld.de, offizium/sqronline)

extension BayernPortalsProvider {
    private static let rhoenURL = "https://aht1gh-api.sqronline.de/api/modules/abfall/webshow?module_division_uuid=fde08d95-111b-11ef-bbd4-b2fd53c2005a"

    private struct RhoenData: Decodable {
        let mdiv: Division
        let abfall_dates: [Event]
        struct Division: Decodable { let config: Config }
        struct Config: Decodable { let cities: [City]; let areas: [Area]; let abfall_types: Types }
        struct City: Decodable { let id: String; let name: String }
        struct Area: Decodable { let id: String; let name: String; let city_id: String }
        struct Types: Decodable { let normal: [Kind]; let special: [Kind] }
        struct Kind: Decodable { let id: String; let name: String }
        struct Event: Decodable { let date: String; let abfall_city_id: Int?; let abfall_area_id: Int?; let abfall_type_id: Int; let comment: String? }
    }

    private func rhoenStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let data: RhoenData = try await client.json(Self.rhoenURL)
            return try Self.list(SelectionStep.cityTitle, data.mdiv.config.cities.map { SelectionOption(id: $0.id, title: $0.name) })
        case 1:
            let data: RhoenData = try await client.json(Self.rhoenURL)
            let areas = data.mdiv.config.areas.filter { $0.city_id == s[0].id }
            return areas.count < 2 ? nil : try Self.list(SelectionStep.districtTitle, areas.map { SelectionOption(id: $0.id, title: $0.name) })
        default:
            return nil
        }
    }

    private func rhoenPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let data: RhoenData = try await client.json(Self.rhoenURL)
        let types = data.mdiv.config.abfall_types
        var names: [Int: String] = [:]
        for kind in types.normal + types.special { names[Int(kind.id) ?? -1] = kind.name }
        let renamed = ["Bio": "Biotonne", "Papier": "Papiertonne"]
        let city = Int(s[0].id), area = s.count > 1 ? Int(s[1].id) : nil
        return data.abfall_dates.compactMap { event in
            guard event.abfall_city_id == city, area == nil || event.abfall_area_id == area,
                  let name = names[event.abfall_type_id], !name.hasPrefix("Wertstoff"),
                  let date = Days.parse(String(event.date.prefix(10)), calendar: calendar) else { return nil }
            let comment = event.comment?.trimmingCharacters(in: .whitespaces) ?? ""
            return Pickup(date: date, name: renamed[name] ?? name, note: comment.isEmpty ? nil : comment)
        }
    }
}

// MARK: - Landkreis Amberg-Sulzbach (landkreis-as.de/abfallwirtschaft)

extension BayernPortalsProvider {
    private static let asBase = "https://landkreis-as.de/abfallwirtschaft/"

    /// `<option value="21">Ammerthal<option value="5">Auerbach…` – die Optionen haben kein schließendes Tag.
    static func asOptions(_ name: String, in html: String) -> [SelectionOption] {
        guard let select = HTMLText.firstMatch(#"<select[^>]*name="\#(name)"[^>]*>([\s\S]*?)</select>"#, in: html, group: 1) else { return [] }
        return HTMLText.matches(#"<option value="([^"]+)"[^>]*>([^<]*)"#, in: select).compactMap {
            let title = HTMLText.decodeEntities($0[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return $0[0] == "x" || title.isEmpty ? nil : SelectionOption(id: HTMLText.decodeEntities($0[0]), title: title)
        }
    }

    /// Formular „Kalenderübersicht anzeigen“: Ziel und versteckte Felder `muell_*`; nil, solange die Adresse unvollständig ist.
    static func asCalendarForm(_ html: String) -> (action: String, fields: [(String, String)])? {
        guard let match = HTMLText.matches(#"<form action="(abfuhrtermine_kalender\.php[^"]*)"[^>]*>([\s\S]*?)</form>"#, in: html).first else { return nil }
        let fields = HTMLText.hiddenInputs(in: match[1]).map { ($0.name, $0.value) }
        guard !fields.isEmpty else { return nil }
        return (HTMLText.decodeEntities(match[0]), fields + [("submit_kalender", "Kalenderübersicht anzeigen")])
    }

    /// Link auf die ICS-Datei, die erst durch das Absenden des Kalender-Formulars entsteht.
    static func asICSLink(_ html: String) -> String? {
        HTMLText.firstMatch(#"href="(abfuhrtermine_kalender_\d{4}_[^"]+\.ics)""#, in: html, group: 1)
    }

    /// „Restmüll  ! vorgefahren ! | Abfuhrkalender - Landkreis Amberg-Sulzbach“ → „Restmüll“ mit Notiz „vorgefahren“.
    static func asSplit(_ summary: String) -> [(name: String, note: String?)] {
        var name = summary.components(separatedBy: "|")[0]
        var note: String?
        if let range = name.range(of: #"!\s*[^!]+?\s*!"#, options: .regularExpression) {
            note = name[range].trimmingCharacters(in: CharacterSet(charactersIn: "! "))
            name.removeSubrange(range)
        }
        return [(name.trimmingCharacters(in: .whitespaces), note)]
    }

    private static func asHasStreetField(_ html: String) -> Bool { html.contains(#"name="abhol_gde_str_suro_bez""#) }

    private func asPost(_ path: String, _ fields: [(String, String)]) async throws -> String {
        HTTPClient.text(from: try await client.postForm(Self.asBase + path, fields: fields))
    }

    private func asTownPage(_ town: String, year: Int) async throws -> String {
        try await asPost("abfuhrtermine.php?jahr=\(year)", [("abhol_gde", town), ("submit_gde", "")])
    }

    private func asStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        let year = Calendar.current.component(.year, from: referenceDate ?? Date())
        switch s.count {
        case 0:
            let html = try await client.string(Self.asBase + "abfuhrtermine.php")
            return try Self.list(L10n.t("Gemeinde", "Municipality"), Self.asOptions("abhol_gde", in: html))
        case 1:
            // Auerbach, Kümmersbruck, Vilseck: Ortsteil; Sulzbach-Rosenberg: Straße; sonst gleich der Kalender.
            let html = try await asTownPage(s[0].id, year: year)
            let districts = Self.asOptions("abhol_gde_ot", in: html)
            if !districts.isEmpty { return try Self.list(SelectionStep.districtTitle, districts) }
            if Self.asHasStreetField(html) {
                return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Adam-Stegerwald-Straße", "e.g. Adam-Stegerwald-Straße"))
            }
            return nil
        case 2:
            let html = try await asTownPage(s[0].id, year: year)
            guard Self.asHasStreetField(html) else { return nil }
            let text = s[1].title.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else {
                throw ProviderError.invalidSelection(L10n.t("Bitte mindestens zwei Buchstaben eingeben.", "Please enter at least two letters."))
            }
            // Die Suche findet nichts, sobald Bindestrich oder Leerzeichen im Begriff stehen:
            // mit dem längsten Wort suchen und die übrigen Wörter selbst prüfen.
            let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            let term = words.max { $0.count < $1.count } ?? text
            let data = try await client.get(Self.asBase + "abfuhrtermine_ort_autocomplete.php?term=" + HTTPClient.query(term))
            let found: [String] = (try? HTTPClient.decode(data)) ?? []
            let streets = found.filter { street in
                words.allSatisfy { street.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            guard !streets.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Keine passende Straße gefunden.", "No matching street found."))
            }
            return try Self.list(SelectionStep.streetTitle, streets.map { SelectionOption(id: $0, title: $0) })
        default:
            return nil
        }
    }

    private func asPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let year = calendar.component(.year, from: referenceDate ?? Date())
        var pickups = try await asYearPickups(s, year: year, calendar: calendar)
        // Folgejahr nur, wenn das Portal es schon kennt (sonst leere Datei oder Fehler).
        if let next = try? await asYearPickups(s, year: year + 1, calendar: calendar) { pickups += next }
        return pickups
    }

    private func asYearPickups(_ s: [SelectionOption], year: Int, calendar: Calendar) async throws -> [Pickup] {
        let town = s[0].id
        var html = try await asTownPage(town, year: year)
        if Self.asCalendarForm(html) == nil {
            let street = Self.asHasStreetField(html)
            guard s.count > (street ? 2 : 1) else { throw ProviderError.selectAddressFirst }
            html = try await asPost("abfuhrtermine.php?abhol_gde=\(HTTPClient.query(town))&jahr=\(year)", street
                ? [("abhol_gde_str_suro_bez", s[2].id), ("abhol_gde", town), ("submit_str", "anzeigen")]
                : [("abhol_gde_ot", s[1].id), ("abhol_gde", town), ("submit_ot", "anzeigen")])
        }
        guard let form = Self.asCalendarForm(html) else { throw ProviderError.noDataGeneric }
        let result = try await asPost(form.action, form.fields)
        guard let link = Self.asICSLink(result) else { throw ProviderError.noDataGeneric }
        return Self.ics(try await client.string(Self.asBase + link), calendar: calendar, split: Self.asSplit)
    }
}

// MARK: - XLSX/ZIP/DEFLATE (nur für Amberg)

extension BayernPortalsProvider {
    /// Liest Tabellen aus XLSX-Dateien (ZIP mit DEFLATE, XML) – nur, was für Abfuhrkalender nötig ist.
    enum XLSX {
        /// Zeilen eines Tabellenblatts als Spaltenbuchstabe → Wert (geteilte Texte aufgelöst).
        static func rows(of sheetName: String, in data: Data) -> [[String: String]]? {
            guard let files = try? Zip.entries(Array(data)),
                  let workbook = files["xl/workbook.xml"].map(text), let rels = files["xl/_rels/workbook.xml.rels"].map(text) else { return nil }
            let escaped = NSRegularExpression.escapedPattern(for: sheetName)
            guard let sheetTag = HTMLText.matches(#"<sheet [^>]*name="\#(escaped)"[^>]*>"#, in: workbook, wholeMatch: true).first?.first,
                  let relID = HTMLText.firstMatch(#"r:id="([^"]+)""#, in: sheetTag, group: 1) else { return nil }
            let relTag = HTMLText.matches(#"<Relationship [^>]*>"#, in: rels, wholeMatch: true).map { $0[0] }
                .first { HTMLText.firstMatch(#"Id="([^"]+)""#, in: $0, group: 1) == relID }
            guard let target = relTag.flatMap({ HTMLText.firstMatch(#"Target="([^"]+)""#, in: $0, group: 1) }) else { return nil }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard let sheet = files[path].map(text) else { return nil }
            let shared = files["xl/sharedStrings.xml"].map(text).map { strings in
                HTMLText.matches(#"<si>([\s\S]*?)</si>"#, in: strings).map { item in
                    HTMLText.decodeEntities(HTMLText.matches(#"<t[^>]*>([^<]*)</t>"#, in: item[0]).map { $0[0] }.joined())
                }
            } ?? []
            return HTMLText.matches(#"<row[^>]*>([\s\S]*?)</row>"#, in: sheet).map { row in
                var cells: [String: String] = [:]
                for cell in HTMLText.matches(#"<c r="([A-Z]+)\d+"([^>]*?)(?:/>|>([\s\S]*?)</c>)"#, in: row[0]) {
                    guard let value = HTMLText.firstMatch(#"<v>([^<]*)</v>"#, in: cell[2], group: 1) else { continue }
                    if cell[1].contains(#"t="s""#), let index = Int(value), index < shared.count {
                        cells[cell[0]] = shared[index]
                    } else {
                        cells[cell[0]] = HTMLText.decodeEntities(value)
                    }
                }
                return cells
            }
        }

        private static func text(_ bytes: [UInt8]) -> String {
            String(decoding: bytes, as: UTF8.self)
        }
    }

    /// Minimaler ZIP-Leser (gespeichert oder DEFLATE).
    enum Zip {
        struct Failure: Error {}

        static func entries(_ bytes: [UInt8]) throws -> [String: [UInt8]] {
            func u16(_ at: Int) throws -> Int {
                guard at + 2 <= bytes.count else { throw Failure() }
                return Int(bytes[at]) | Int(bytes[at + 1]) << 8
            }
            func u32(_ at: Int) throws -> Int { try u16(at) | u16(at + 2) << 16 }
            // Ende des zentralen Verzeichnisses von hinten suchen.
            var end = bytes.count - 22
            while end >= 0, (try? u32(end)) != 0x0605_4B50 { end -= 1 }
            guard end >= 0 else { throw Failure() }
            let count = try u16(end + 10)
            var offset = try u32(end + 16)
            var result: [String: [UInt8]] = [:]
            for _ in 0..<count {
                guard try u32(offset) == 0x0201_4B50 else { throw Failure() }
                let method = try u16(offset + 10), size = try u32(offset + 20)
                let nameLength = try u16(offset + 28), extraLength = try u16(offset + 30), commentLength = try u16(offset + 32)
                let local = try u32(offset + 42)
                guard offset + 46 + nameLength <= bytes.count else { throw Failure() }
                let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
                offset += 46 + nameLength + extraLength + commentLength
                guard try u32(local) == 0x0403_4B50 else { throw Failure() }
                let start = try local + 30 + u16(local + 26) + u16(local + 28)
                guard start + size <= bytes.count else { throw Failure() }
                let raw = Array(bytes[start..<(start + size)])
                switch method {
                case 0: result[name] = raw
                case 8: result[name] = try Inflate.decompress(raw)
                default: continue
                }
            }
            return result
        }
    }

    /// DEFLATE-Entpacker nach RFC 1951 (Aufbau wie zlibs „puff“).
    enum Inflate {
        struct Failure: Error {}

        private struct Bits {
            let bytes: [UInt8]
            var position = 0
            var bit = 0

            mutating func read(_ count: Int) throws -> Int {
                var value = 0
                for index in 0..<count {
                    guard position < bytes.count else { throw Failure() }
                    value |= Int((bytes[position] >> UInt8(bit)) & 1) << index
                    bit += 1
                    if bit == 8 { bit = 0; position += 1 }
                }
                return value
            }
        }

        private struct Huffman {
            var counts = [Int](repeating: 0, count: 16)
            var symbols: [Int]

            init(_ lengths: [Int]) {
                symbols = [Int](repeating: 0, count: lengths.count)
                for length in lengths { counts[length] += 1 }
                counts[0] = 0
                var offsets = [Int](repeating: 0, count: 16)
                for length in 1..<16 { offsets[length] = offsets[length - 1] + counts[length - 1] }
                for (symbol, length) in lengths.enumerated() where length != 0 {
                    symbols[offsets[length]] = symbol
                    offsets[length] += 1
                }
            }

            func decode(_ bits: inout Bits) throws -> Int {
                var code = 0, first = 0, index = 0
                for length in 1..<16 {
                    code |= try bits.read(1)
                    let count = counts[length]
                    if code - count < first { return symbols[index + code - first] }
                    index += count
                    first = (first + count) << 1
                    code <<= 1
                }
                throw Failure()
            }
        }

        private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
        private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
        private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
        private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
        private static let codeOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

        static func decompress(_ input: [UInt8]) throws -> [UInt8] {
            var bits = Bits(bytes: input)
            var output: [UInt8] = []
            output.reserveCapacity(input.count * 4)
            var isLast = false
            while !isLast {
                isLast = try bits.read(1) == 1
                switch try bits.read(2) {
                case 0:
                    // Ungepackter Block
                    if bits.bit > 0 { bits.bit = 0; bits.position += 1 }
                    guard bits.position + 4 <= input.count else { throw Failure() }
                    let length = Int(input[bits.position]) | Int(input[bits.position + 1]) << 8
                    bits.position += 4
                    guard bits.position + length <= input.count else { throw Failure() }
                    output += input[bits.position..<(bits.position + length)]
                    bits.position += length
                case 1:
                    let literal = Huffman([Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112) + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8))
                    try inflateBlock(&bits, &output, literal: literal, distance: Huffman([Int](repeating: 5, count: 30)))
                case 2:
                    let literalCount = try bits.read(5) + 257, distanceCount = try bits.read(5) + 1, codeCount = try bits.read(4) + 4
                    var codeLengths = [Int](repeating: 0, count: 19)
                    for index in 0..<codeCount { codeLengths[codeOrder[index]] = try bits.read(3) }
                    let lengthCode = Huffman(codeLengths)
                    var lengths: [Int] = []
                    while lengths.count < literalCount + distanceCount {
                        let symbol = try lengthCode.decode(&bits)
                        switch symbol {
                        case 0..<16: lengths.append(symbol)
                        case 16:
                            guard let previous = lengths.last else { throw Failure() }
                            lengths += [Int](repeating: previous, count: try 3 + bits.read(2))
                        case 17: lengths += [Int](repeating: 0, count: try 3 + bits.read(3))
                        default: lengths += [Int](repeating: 0, count: try 11 + bits.read(7))
                        }
                    }
                    guard lengths.count == literalCount + distanceCount else { throw Failure() }
                    try inflateBlock(&bits, &output, literal: Huffman(Array(lengths[0..<literalCount])), distance: Huffman(Array(lengths[literalCount...])))
                default:
                    throw Failure()
                }
            }
            return output
        }

        private static func inflateBlock(_ bits: inout Bits, _ output: inout [UInt8], literal: Huffman, distance: Huffman) throws {
            while true {
                let symbol = try literal.decode(&bits)
                if symbol < 256 {
                    output.append(UInt8(symbol))
                } else if symbol == 256 {
                    return
                } else {
                    let index = symbol - 257
                    guard index < lengthBase.count else { throw Failure() }
                    let length = try lengthBase[index] + bits.read(lengthExtra[index])
                    let code = try distance.decode(&bits)
                    guard code < distanceBase.count else { throw Failure() }
                    let back = try distanceBase[code] + bits.read(distanceExtra[code])
                    guard back <= output.count else { throw Failure() }
                    let start = output.count - back
                    for offset in 0..<length { output.append(output[start + offset]) }
                }
            }
        }
    }
}

// MARK: - AZV Hof (Stadt und Landkreis)

extension BayernPortalsProvider {
    private static let hofHost = "https://www.azv-hof.de"

    private var hofPortal: (page: String, form: String, prefix: String) {
        serviceKey == "hof_lk"
            ? (Self.hofHost + "/privat/abfuhrtermine/abfuhrkalender-landkreis-hof.html", "landFrm", "tx_abfuhrkalender_country")
            : (Self.hofHost + "/privat/abfuhrtermine/abfuhrkalender-stadt-hof.html", "stadtFrm", "tx_abfuhrkalender_city")
    }

    /// Formular (Ziel, versteckte Felder, Inhalt) aus einer TYPO3-Seite.
    private static func hofForm(_ id: String, in html: String) -> (action: String, hidden: [(String, String)], body: String)? {
        guard let match = HTMLText.matches(#"<form[^>]*id="\#(id)"[^>]*action="([^"]*)"[^>]*>([\s\S]*?)</form>"#, in: html).first else { return nil }
        let action = HTMLText.decodeEntities(match[0]).components(separatedBy: "#")[0]
        return (action, HTMLText.hiddenInputs(in: match[1]).map { ($0.name, $0.value) }, match[1])
    }

    private static func hofOptions(_ name: String, in form: String) -> [SelectionOption] {
        HTMLText.options(ofSelect: name, in: form).filter { $0.value != "0" && !$0.value.isEmpty }
            .map { SelectionOption(id: $0.value, title: $0.label) }
    }

    /// Formular mit den gewählten Werten absenden; liefert die Ergebnisseite.
    private func hofSubmit(_ html: String, values: [(String, String)]) async throws -> String {
        let portal = hofPortal
        guard let form = Self.hofForm(portal.form, in: html) else { throw ProviderError.noDataGeneric }
        let fields = form.hidden + values.map { ("\(portal.prefix)[\($0.0)]", $0.1) }
        let data = try await client.postForm(Self.hofHost + form.action, fields: fields)
        return HTTPClient.text(from: data)
    }

    private func hofStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        let portal = hofPortal
        let isCounty = serviceKey == "hof_lk"
        switch s.count {
        case 0:
            let html = try await client.string(portal.page)
            guard let form = Self.hofForm(portal.form, in: html) else { throw ProviderError.noDataGeneric }
            let options = Self.hofOptions("\(portal.prefix)[\(isCounty ? "ort" : "strasse")]", in: form.body)
            return try Self.list(isCounty ? SelectionStep.cityTitle : SelectionStep.streetTitle, options)
        case 1 where isCounty:
            // Größere Orte haben zusätzlich eine Straßenauswahl.
            let page = try await client.string(portal.page)
            let result = try await hofSubmit(page, values: [("ort", s[0].id)])
            guard let form = Self.hofForm(portal.form, in: result) else { return nil }
            let streets = Self.hofOptions("\(portal.prefix)[strasse]", in: form.body)
            return streets.isEmpty ? nil : try Self.list(SelectionStep.streetTitle, streets)
        default:
            return nil
        }
    }

    private func hofPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let portal = hofPortal
        let page = try await client.string(portal.page)
        var values: [(String, String)]
        var result: String
        if serviceKey == "hof_lk" {
            values = [("ort", s[0].id)]
            result = try await hofSubmit(page, values: values)
            if s.count > 1 {
                values.append(("strasse", s[1].id))
                result = try await hofSubmit(result, values: values)
            }
        } else {
            values = [("strasse", s[0].id)]
            result = try await hofSubmit(page, values: values)
        }
        // Link „Kalender (ICS)“ der Ergebnisseite (mit cHash, daher nicht selbst bauen).
        let escaped = NSRegularExpression.escapedPattern(for: portal.prefix)
        let icsLinks = { (html: String) in
            HTMLText.matches(#"href="([^"]*\#(escaped)%5Bansicht%5D=ico[^"]*)""#, in: html).compactMap(\.first).map(HTMLText.decodeEntities)
        }
        var links = Set(icsLinks(result))
        // Steht das Folgejahr schon zur Wahl, auch dessen Kalender holen.
        let year = Self.currentYear(calendar)
        if let form = Self.hofForm(portal.form, in: result) {
            for option in HTMLText.options(ofSelect: "\(portal.prefix)[jahr]", in: form.body) where (Int(option.value) ?? 0) > year {
                if let next = try? await hofSubmit(result, values: values + [("jahr", option.value)]) { links.formUnion(icsLinks(next)) }
            }
        }
        guard !links.isEmpty else { throw ProviderError.noDataGeneric }
        var pickups: [Pickup] = []
        for link in links {
            guard let text = try? await client.string(link.hasPrefix("http") ? link : Self.hofHost + link) else { continue }
            // „Restmülltonne + Wertstoffhof … geschlossen.“ → nur die Tonne
            pickups += Self.ics(text, calendar: calendar) { summary in
                summary.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.lowercased().contains("geschlossen") }.map { ($0, nil) }
            }
        }
        return pickups
    }
}
