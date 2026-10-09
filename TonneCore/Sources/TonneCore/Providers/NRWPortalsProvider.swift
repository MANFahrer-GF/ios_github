import Foundation

/// Portale einzelner Entsorger in Nordrhein-Westfalen, je Betreiber eine Kennung (`serviceKey`):
/// - `awista`: AWISTA Düsseldorf – Adresssuche über eine Next.js-Server-Action, ICS je Adress-UUID
/// - `mags`: mags Mönchengladbach – Straßenliste + ICS (`/ics/icscal.php`) mit Leerungsrhythmus
/// - `awg`: AWG Wuppertal – Straßensuche (Autocomplete), Formular liefert ICS-Links je Jahr
/// - `rsag`: RSAG Rhein-Sieg-Kreis – JSON-API (Ort → Straße) mit ICS
/// - `gelsendienste`, `best`: Gelsenkirchen und Bottrop (abisapp) – Straßenliste + Hausnummer, ICS
/// - `herford`: Kreis Herford – iKISS-Portale der neun Kommunen, vCal-Export je Straße
/// - `enni`: ENNI Moers – Straßenliste, ICS je Straße
/// - `espelkamp`: Stadt Espelkamp (Kreis Minden-Lübbecke) – iKISS wie Kreis Herford, ohne Ortswahl
/// - `prezero`: PreZero Bad Oeynhausen – Straßenliste + Hausnummer, ICS je Jahr
public struct NRWPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsNRW
    public let serviceKey: String
    public var displayName: String { Self.names[serviceKey] ?? kind.displayName }
    private let client: HTTPClient
    /// Nur für Tests: festes „heute“ für die Jahreswahl bei Kreis Herford/Espelkamp und PreZero.
    var referenceDate: Date?

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    static let names: [String: String] = [
        "awista": "AWISTA Düsseldorf", "mags": "mags Mönchengladbach", "awg": "AWG Wuppertal",
        "rsag": "RSAG Rhein-Sieg", "gelsendienste": "Gelsendienste", "best": "BEST Bottrop",
        "herford": "Kreis Herford","enni": "ENNI Moers",
        "espelkamp": "Stadt Espelkamp", "prezero": "PreZero Bad Oeynhausen",
    ]

    /// abisapp-Portale: Straßenliste im `<select name="street">`, ICS über `format=ical`.
    static let abisapp: [String: (url: String, city: String)] = [
        "gelsendienste": ("https://gelsendienste.abisapp.de/abfuhrkalender", "Gelsenkirchen"),
        "best": ("https://www.best-bottrop.de/abfuhrkalender", "Bottrop"),
    ]

    /// Kommunen im Kreis Herford: gemeinsamer iKISS-Datenbestand, Export aber nur über den eigenen Host.
    static let herfordPlaces: [(name: String, ort: String, host: String)] = [
        ("Bünde", "393.3", "www.buende.de"), ("Enger", "393.6", "www.enger.de"), ("Herford", "393.9", "swk.herford.de"),
        ("Hiddenhausen", "393.7", "www.hiddenhausen.de"), ("Kirchlengern", "393.2", "www.kirchlengern.de"),
        ("Löhne", "393.4", "www.loehne.de"), ("Rödinghausen", "393.1", "www.roedinghausen.de"),
        ("Spenge", "393.5", "www.spenge.de"), ("Vlotho", "393.8", "www.vlotho.de"),
    ]

    /// Weitere iKISS-Kommunen mit demselben Export; eine einzelne Kommune braucht keine Ortswahl.
    static let ikissPlaces: [String: [(name: String, ort: String, host: String)]] = [
        "herford": herfordPlaces,
        "espelkamp": [("Espelkamp", "322.4", "www.espelkamp.de")],
    ]

    // MARK: - Assistent

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "awista": return try await awistaStep(selections)
        case "mags": return try await magsStep(selections)
        case "awg": return try await awgStep(selections)
        case "rsag": return try await rsagStep(selections)
        case "gelsendienste", "best": return try await abisappStep(selections)
        case "herford", "espelkamp": return try await herfordStep(selections)
        case "enni": return try await enniStep(selections)
        case "prezero": return try await prezeroStep(selections)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let result: [Pickup]
        switch serviceKey {
        case "awista": result = try await awistaPickups(selections, calendar: calendar)
        case "mags": result = try await magsPickups(selections, calendar: calendar)
        case "awg": result = try await awgPickups(selections, calendar: calendar)
        case "rsag": result = try await rsagPickups(selections, calendar: calendar)
        case "gelsendienste", "best": result = try await abisappPickups(selections, calendar: calendar)
        case "herford", "espelkamp": result = try await herfordPickups(selections, calendar: calendar)
        case "enni": result = try await enniPickups(selections, calendar: calendar)
        case "prezero": result = try await prezeroPickups(selections, calendar: calendar)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map(\.title)
        func join(_ city: String, _ parts: [String]) -> String {
            ([city] + [parts.filter { !$0.isEmpty }.joined(separator: " ")]).filter { !$0.isEmpty }.joined(separator: ", ")
        }
        switch serviceKey {
        case "awista": return join("Düsseldorf", [titles.count > 3 ? titles[3] : titles.dropFirst().first ?? ""])
        case "mags": return join("Mönchengladbach", Array(titles.prefix(2)))
        case "awg": return join("Wuppertal", Array(titles.dropFirst().prefix(1)))
        case "gelsendienste", "best": return join(Self.abisapp[serviceKey]?.city ?? "", Array(titles.prefix(2)))
        case "enni": return join("Moers", Array(titles.prefix(1)))
        case "espelkamp": return join("Espelkamp", Array(titles.prefix(1)))
        case "prezero": return join("Bad Oeynhausen", Array(titles.prefix(2)))
        default: return titles.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    // MARK: - Gemeinsame Helfer

    /// Erinnerungsblöcke entfernen – manche Portale haben dort ein eigenes SUMMARY, das den Termin-Titel überschreiben würde.
    static func stripAlarms(_ ics: String) -> String {
        ics.replacingOccurrences(of: #"BEGIN:VALARM[\s\S]*?END:VALARM\r?\n?"#, with: "", options: .regularExpression)
    }

    static func sortedOptions(_ options: [SelectionOption]) -> [SelectionOption] {
        var seen = Set<String>()
        return options.filter { !$0.title.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func notFound(_ what: String) -> ProviderError {
        .invalidSelection(L10n.t("Keine passende \(what) gefunden – bitte Schreibweise prüfen.", "No matching \(what) found – please check the spelling."))
    }

    // MARK: - AWISTA Düsseldorf

    private static let awistaDomain = "https://www.awista-kommunal.de"
    private static let awistaBase = awistaDomain + "/abfallkalender"

    private struct AwistaResult: Decodable {
        struct Item: Decodable { let title: String; let id: String? }
        let items: [Item]?
        let addressIdForQuery: String?
    }

    private static func isUUID(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil
    }

    /// Kennungen der Server-Action `searchAddressAction` aus den JS-Chunks der Seite. Es gibt mehrere;
    /// die gesuchte steht im Chunk mit `addressIdForQuery` (liefert Adress-UUIDs) und kommt zuerst.
    private func awistaActions() async throws -> [String] {
        let page = try await client.string(Self.awistaBase)
        let chunks = HTMLText.matches(#"src="(/_next/static/chunks/[^"?]+\.js)"#, in: page).compactMap(\.first)
        var preferred: [String] = [], others: [String] = []
        // Seitenspezifische Chunks stehen hinten – rückwärts suchen und beim ersten Treffer aufhören.
        var seen = Set<String>()
        for path in chunks.filter({ seen.insert($0).inserted }).reversed() {
            guard let js = try? await client.string(Self.awistaDomain + path), js.contains("searchAddressAction") else { continue }
            let ids = HTMLText.matches(#"\("([0-9a-f]{40,})"[^)]{0,200}?"searchAddressAction""#, in: js).compactMap(\.first)
            if js.contains("addressIdForQuery") { preferred += ids } else { others += ids }
            if !preferred.isEmpty { break }
        }
        let all = preferred + others
        guard !all.isEmpty else { throw ProviderError.noData(L10n.t("Die Adresssuche von AWISTA hat sich geändert.", "The AWISTA address search has changed.")) }
        return all
    }

    private func awistaSearch(action: String, query: String) async throws -> AwistaResult? {
        let body = try JSONSerialization.data(withJSONObject: [query])
        let data = try await client.post(Self.awistaBase, body: body, contentType: "text/plain;charset=UTF-8",
                                         headers: ["Accept": "text/x-component", "Next-Action": action])
        // Antwort im React-Server-Components-Format: Zeile „1:{…}“ enthält das Ergebnis.
        for line in HTTPClient.text(from: data).components(separatedBy: "\n") where line.hasPrefix("1:") {
            return try? JSONDecoder().decode(AwistaResult.self, from: Data(line.dropFirst(2).utf8))
        }
        return nil
    }

    private func awistaStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Merkurstraße", "e.g. Merkurstraße"))
        case 1:
            let query = selections[0].title.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else { throw Self.notFound(L10n.t("Straße", "street")) }
            for action in try await awistaActions() {
                guard let result = try await awistaSearch(action: action, query: query) else { continue }
                // Straßen ohne Kennung; hat der Nutzer schon eine Hausnummer getippt, kommen Adressen – dann Nummer abschneiden.
                let streets = (result.items ?? []).map { item in
                    Self.isUUID(item.id) ? item.title.replacingOccurrences(of: #"\s+\d[^\s]*$"#, with: "", options: .regularExpression) : item.title
                }.map { $0.trimmingCharacters(in: .whitespaces) }
                let options = Self.sortedOptions(streets.map { SelectionOption(id: "\(action)|\($0)", title: $0) })
                guard !options.isEmpty else { throw Self.notFound(L10n.t("Straße", "street")) }
                return SelectionStep(title: SelectionStep.streetTitle, options: options)
            }
            throw ProviderError.noDataGeneric
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 45", "e.g. 45"))
        case 3:
            let parts = selections[1].id.components(separatedBy: "|")
            guard parts.count == 2 else { throw ProviderError.selectAddressFirst }
            let number = selections[2].title.trimmingCharacters(in: .whitespaces)
            guard let result = try await awistaSearch(action: parts[0], query: "\(parts[1]) \(number)") else { throw ProviderError.noDataGeneric }
            var options = (result.items ?? []).filter { Self.isUUID($0.id) }.map { SelectionOption(id: $0.id ?? "", title: $0.title.trimmingCharacters(in: .whitespaces)) }
            if options.isEmpty, Self.isUUID(result.addressIdForQuery), let id = result.addressIdForQuery {
                options = [SelectionOption(id: id, title: "\(parts[1]) \(number)")]
            }
            guard !options.isEmpty else { throw Self.notFound(L10n.t("Hausnummer", "house number")) }
            return SelectionStep(title: L10n.t("Adresse", "Address"), options: options, searchable: options.count > 8)
        default:
            return nil
        }
    }

    private func awistaPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 4, Self.isUUID(selections[3].id) else { throw ProviderError.selectAddressFirst }
        let text = try await client.string("\(Self.awistaBase)/\(selections[3].id)/calendar.ics")
        return ICS.parse(text, calendar: calendar).map { event in
            // „Restmüll (Vollservice)“ → „Restmüll“
            let name = event.summary.replacingOccurrences(of: #"\s*\((Voll|Teil)?[Ss]ervice\)"#, with: "", options: .regularExpression)
            return Pickup(date: event.date, name: NameCleaner.clean(name))
        }
    }

    // MARK: - mags Mönchengladbach

    private struct MagsStreets: Decodable { let data: [String] }

    private func magsStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let streets: MagsStreets = try await client.json("https://mags.de/proxy/proxy_streets.php")
            let options = Self.sortedOptions(streets.data.map { SelectionOption(id: $0, title: $0) })
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 43 oder 43a", "e.g. 43 or 43a"))
        case 2:
            let options = [("2", L10n.t("alle 2 Wochen", "every 2 weeks")), ("1", L10n.t("wöchentlich", "weekly")), ("4", L10n.t("alle 4 Wochen", "every 4 weeks"))]
            return SelectionStep(title: L10n.t("Leerung Restmüll", "Residual waste collection"),
                                 options: options.map { SelectionOption(id: $0.0, title: $0.1) }, searchable: false)
        default:
            return nil
        }
    }

    private func magsPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let raw = selections[1].title.trimmingCharacters(in: .whitespaces)
        let number = HTMLText.firstMatch(#"^(\d+)"#, in: raw, group: 1) ?? raw
        let addition = raw.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        let turnus = selections.count > 2 ? selections[2].id : "2"
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        // Das Folgejahr liefert vor Veröffentlichung wieder das laufende Jahr – Duplikate fallen später heraus.
        for target in [year, year + 1] {
            let url = "https://mags.de/ics/icscal.php?building_number=\(HTTPClient.query(number))&building_number_addition=\(HTTPClient.query(addition))"
                + "&street_name=\(HTTPClient.query(selections[0].id))&start_month=1&end_month=12&start_year=\(target)&end_year=\(target)&turnus=\(turnus)"
            guard let text = try? await client.string(url) else { continue }
            result += ICS.parse(text, calendar: calendar).map { event in
                Pickup(date: event.date, name: NameCleaner.clean(event.summary.replacingOccurrences(of: "// GEM", with: "")))
            }
        }
        return result
    }

    // MARK: - AWG Wuppertal

    private static let awgURL = "https://awg-wuppertal.de/privatkunden/abfallkalender.html"

    private func awgStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Friedrich-Engels-Allee", "e.g. Friedrich-Engels-Allee"))
        case 1:
            // Autocomplete sucht nach Wortanfang; ohne Treffer schrittweise kürzen.
            var term = selections[0].title.trimmingCharacters(in: .whitespaces)
            var attempts = 0
            while term.count >= 3, attempts < 5 {   // höchstens 5 Anfragen, damit der Assistent nicht lange hängt
                attempts += 1
                let streets: [String]
                do { streets = try await client.json("\(Self.awgURL)?eID=wastecalendar_autocomplete&term=\(HTTPClient.query(term))") }
                catch let error as HTTPError { if case .transport = error { throw error }; streets = [] }
                catch { streets = [] }
                if !streets.isEmpty {
                    return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets.map { SelectionOption(id: $0, title: $0) }))
                }
                term = String(term.dropLast())
            }
            throw Self.notFound(L10n.t("Straße", "street"))
        default:
            return nil
        }
    }

    private func awgPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let page = try await client.string(Self.awgURL)
        guard let action = HTMLText.firstMatch(#"<form action="([^"]+)"[^>]*name="demand""#, in: page, group: 1),
              let form = HTMLText.firstMatch(#"<form[^>]*name="demand"[^>]*>([\s\S]*?)</form>"#, in: page, group: 1) else { throw ProviderError.noDataGeneric }
        var fields = HTMLText.hiddenInputs(in: form).map { ($0.name, $0.value) }
        fields.append(("tx_bwwastecalendar_pi1[demand][streetname]", selections[1].id))
        let html = HTTPClient.text(from: try await client.postForm("https://awg-wuppertal.de" + HTMLText.decodeEntities(action), fields: fields))
        // Ein Link je Jahr („für 2026 als iCal“)
        let links = HTMLText.matches(#"<a[^>]*href="([^"]+)"[^>]*>[^<]*als iCal\s*</a>"#, in: html).compactMap(\.first)
        var result: [Pickup] = []
        for link in links {
            let href = HTMLText.decodeEntities(link)
            guard let text = try? await client.string(href.hasPrefix("/") ? "https://awg-wuppertal.de" + href : href) else { continue }
            for event in ICS.parse(Self.stripAlarms(text), calendar: calendar) {
                // „Restmüll/Bio/Papier/ !!! Terminverschiebung !!!“ → einzelne Termine mit Hinweis
                let parts = event.summary.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let moved = parts.contains { $0.contains("Terminverschiebung") }
                for part in parts where !part.contains("Terminverschiebung") {
                    result.append(Pickup(date: event.date, name: NameCleaner.clean(part), note: moved ? L10n.t("Terminverschiebung", "Rescheduled") : nil))
                }
            }
        }
        return result
    }

    // MARK: - RSAG Rhein-Sieg-Kreis

    private struct RsagCity: Decodable { let city_id: Int; let name: String }
    private struct RsagStreet: Decodable { let street_id: Int; let name: String }
    private struct RsagType: Decodable { let wastetype_id: Int; let selected_default: Bool? }

    private func rsagStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let cities: [RsagCity] = try await client.json("https://www.rsag.de/api/city/all")
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(cities.map { SelectionOption(id: String($0.city_id), title: $0.name) }))
        case 1:
            let streets: [RsagStreet] = try await client.json("https://www.rsag.de/api/street/filter/\(selections[0].id)")
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets.map { SelectionOption(id: String($0.street_id), title: $0.name) }))
        default:
            return nil
        }
    }

    private func rsagPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        // Standard-Abfallarten des Portals (ohne Großbehälter für Wohnanlagen)
        let types: [RsagType] = try await client.json("https://www.rsag.de/api/wastetype/all")
        let ids = types.filter { $0.selected_default ?? true }.map { String($0.wastetype_id) }.joined(separator: ",")
        let year = calendar.component(.year, from: Date())
        let months = [year, year + 1].flatMap { y in (1...12).map { String(format: "%d-%02d", y, $0) } }.joined(separator: ",")
        let text = try await client.string("https://www.rsag.de/api/pickup/filter/\(selections[1].id)/\(ids)/\(months)/ics")
        return ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: - Gelsendienste / BEST Bottrop (abisapp)

    private func abisappStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let portal = Self.abisapp[serviceKey] else { throw ProviderError.noDataGeneric }
        switch selections.count {
        case 0:
            let html = try await client.string(portal.url)
            let options = HTMLText.options(ofSelect: "street", in: html).filter { !$0.value.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 10", "e.g. 10"))
        default:
            return nil
        }
    }

    private func abisappPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let portal = Self.abisapp[serviceKey], selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let number = selections[1].title.trimmingCharacters(in: .whitespaces)
        let text = try await client.string("\(portal.url)?format=ical&street=\(HTTPClient.query(selections[0].id))&number=\(HTTPClient.query(number))")
        return ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: - Kreis Herford (iKISS)

    /// Gewählte Kommune und Anzahl der Auswahlschritte davor (0, wenn es nur eine Kommune gibt).
    private func ikissPlace(_ selections: [SelectionOption]) -> (place: (name: String, ort: String, host: String)?, offset: Int) {
        let places = Self.ikissPlaces[serviceKey] ?? []
        if places.count == 1 { return (places[0], 0) }
        return (selections.first.flatMap { selection in places.first { $0.ort == selection.id } }, 1)
    }

    private func herfordStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let (place, offset) = ikissPlace(selections)
        if offset == 1, selections.isEmpty {
            let places = Self.ikissPlaces[serviceKey] ?? []
            return SelectionStep(title: SelectionStep.cityTitle, options: places.map { SelectionOption(id: $0.ort, title: $0.name) }, searchable: false)
        }
        guard selections.count == offset else { return nil }
        guard let place else { throw ProviderError.selectAddressFirst }
        let html = try await client.string("https://\(place.host)/index.php?La=1&ffmod=abf&ort=\(place.ort)&call=sfm")
        var options = HTMLText.options(ofSelect: "strasse", in: html).filter { !$0.value.isEmpty }
            .map { SelectionOption(id: $0.value, title: $0.label) }
        if serviceKey == "espelkamp" { options = Self.withoutSplitStreets(options) }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
    }

    /// Espelkamp führt bei aufgeteilten Straßen den alten Gesamteintrag weiter („Fabbenstedter Straße“ neben
    /// „Fabbenstedter Straße 1-32“ …); der liefert keine oder nur einzelne Termine – nur die Abschnitte anbieten.
    static func withoutSplitStreets(_ options: [SelectionOption]) -> [SelectionOption] {
        let titles = options.map(\.title)
        return options.filter { option in !titles.contains { $0.hasPrefix(option.title + " ") } }
    }

    private func herfordPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let (place, offset) = ikissPlace(selections)
        guard selections.count > offset, let place else { throw ProviderError.selectAddressFirst }
        let year = calendar.component(.year, from: referenceDate ?? Date())
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
        var result: [Pickup] = []
        for target in [year, year + 1] {
            let url = "https://\(place.host)/output/abfall_export.php?csv_export=1&mode=vcal&ort=\(place.ort)&strasse=\(HTTPClient.query(selections[offset].id))"
                + "&vtyp=2&vMo=01&vJ=\(target)&bMo=12"
            guard let text = try? await client.string(url, headers: ["Referer": "https://\(place.host)/"]) else { continue }
            // Vlotho liefert alle Jahre seit 2020 – nur ab dem laufenden Jahr übernehmen.
            for event in ICS.parse(text, calendar: calendar) where event.date >= start {
                result += Self.herfordNames(event.summary, place: place.name).map { Pickup(date: event.date, name: $0) }
            }
        }
        return result
    }

    /// „HF Gelbe Tonne, Blaue Tonne, Altkleider, 4 wöchentlich: Herford“ → [„Gelbe Tonne“, „Blaue Tonne“, „Altkleider“];
    /// Kürzel der Kommune (HF, BÜ, Hi, _KI, Vl- …) und „: Ort“ entfernen.
    static func herfordNames(_ summary: String, place: String) -> [String] {
        var name = repairDoubleUTF8(summary).trimmingCharacters(in: .whitespaces)
        if name.hasSuffix(": \(place)") { name = String(name.dropLast(place.count + 2)) }
        if name.hasPrefix("Vl-") {
            name = vlothoName(String(name.dropFirst(3)))
        } else {
            name = name.replacingOccurrences(of: #"^_?[A-ZÄÖÜ][A-Za-zÄÖÜ]?\s+"#, with: "", options: .regularExpression)
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        // Farbige Deckel unterscheiden Restmüll-Touren – die Farbe darf die Sortierung nicht auf Papier/Gelb lenken.
        name = name.replacingOccurrences(of: "blauer Deckel", with: "bl. Deckel").replacingOccurrences(of: "gelber Deckel", with: "ge. Deckel")
        if name == "Leichtstoff" { name = "Leichtstoffverpackungen" }
        if place == "Espelkamp", name.hasPrefix("Leichtstoffe") { name = "Leichtstoffverpackungen" + name.dropFirst(12) }
        // In Enger ist die grüne Tonne die Verpackungstonne.
        if place == "Enger", name == "Grüne Tonne" { name = "Grüne Tonne (Verpackungen)" }
        guard name.contains("Tonne, ") else { return [NameCleaner.clean(name)] }
        return name.components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.range(of: #"^\d+\s*w"#, options: .regularExpression) == nil }
            .map(NameCleaner.clean)
    }

    /// Vlotho-Kürzel („RM-4-w“, „BMS-2w“ …) in die Bezeichnungen der Online-Übersicht übersetzen.
    static func vlothoName(_ code: String) -> String {
        let fixed = ["E-Schrott": "Elektroschrott", "Mülltonnentausch": "Mülltonnentauschdienst"]
        if let name = fixed[code] { return name }
        let names = ["RM": "Restmüll", "BM": "Biotonne", "BMS": "Bio+Biosaisontonne", "PM": "Papier/Pappe", "GS": "Gelbe Tonne", "Windel": "Windelsack", "AK": "Altkleider"]
        let parts = HTMLText.matches(#"^([A-Za-zäöü]+)-(\d+)-?w$"#, in: code).first
        guard let parts, let base = names[parts[0]] else { return code }
        return "\(base) \(parts[1])-wöchentlich"
    }

    /// Kirchlengern liefert UTF-8, das noch einmal als ISO-8859-15 kodiert wurde („RestmÃŒll“) – zurückwandeln.
    static func repairDoubleUTF8(_ text: String) -> String {
        guard text.contains("Ã") || text.contains("Â") else { return text }
        let latin9: [Character: UInt8] = ["€": 0xA4, "Š": 0xA6, "š": 0xA8, "Ž": 0xB4, "ž": 0xB8, "Œ": 0xBC, "œ": 0xBD, "Ÿ": 0xBE]
        var bytes: [UInt8] = []
        for char in text {
            if let byte = latin9[char] {
                bytes.append(byte)
            } else if let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1, scalar.value < 256 {
                bytes.append(UInt8(scalar.value))
            } else {
                return text
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? text
    }

    // MARK: - ENNI Moers

    private static let enniURL = "https://abfallkalender.enni.de/"

    private func enniStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let html = try await client.string(Self.enniURL)
        let options = HTMLText.options(ofSelect: "street_id", in: html).filter { !$0.value.isEmpty }
            .map { SelectionOption(id: $0.value, title: $0.label) }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
    }

    private func enniPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first?.id else { throw ProviderError.selectAddressFirst }
        // Das Formular leitet auf /abholtermine/<slug> weiter; dort steht der ICS-Link.
        let html = HTTPClient.text(from: try await client.postForm(Self.enniURL, fields: [("street_id", street)]))
        guard let slug = HTMLText.firstMatch(#"href="/ics-kalender/([^"]+)""#, in: html, group: 1) else { throw ProviderError.noDataGeneric }
        let text = try await client.string(Self.enniURL + "ics-kalender/" + slug)
        return ICS.parse(Self.stripAlarms(text), calendar: calendar).map { event in
            Pickup(date: event.date, name: NameCleaner.clean(event.summary.replacingOccurrences(of: #"^Abholung\s+"#, with: "", options: .regularExpression)))
        }
    }

    // MARK: - PreZero Bad Oeynhausen

    private static let prezeroURL = "https://abfallkalender.prezero.network/bad-oeynhausen"

    private func prezeroStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.prezeroURL)
            let options = HTMLText.options(ofSelect: "street", in: html).filter { !$0.value.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 10", "e.g. 10"))
        default:
            return nil
        }
    }

    private func prezeroPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let number = selections[1].title.trimmingCharacters(in: .whitespaces)
        // Das Formular leitet auf /calendar/<Straße>/<Nr> weiter; dort steht das Download-Formular je Jahr.
        let html = HTTPClient.text(from: try await client.postForm(Self.prezeroURL, fields: [("street", selections[0].id), ("houseNo", number)]))
        guard let path = Self.prezeroDownloadPath(html) else { throw ProviderError.noDataGeneric }
        let year = calendar.component(.year, from: referenceDate ?? Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            guard let data = try? await client.postForm("https://abfallkalender.prezero.network\(path)/\(target)", fields: []) else { continue }
            result += Self.prezeroPickups(HTTPClient.text(from: data), calendar: calendar)
        }
        return result
    }

    /// `action="/bad-oeynhausen/download/ical/787/1/2026"` → „/bad-oeynhausen/download/ical/787/1“.
    static func prezeroDownloadPath(_ html: String) -> String? {
        HTMLText.firstMatch(#"action="(/[a-z0-9-]+/download/ical/\d+/[^/"]+)/\d{4}""#, in: html, group: 1)
    }

    /// Termine der Tonnenreinigung sind keine Abfuhr und würden sonst als Biotonne einsortiert.
    static func prezeroPickups(_ ics: String, calendar: Calendar) -> [Pickup] {
        ICS.parse(stripAlarms(ics), calendar: calendar).filter { !$0.summary.contains("Reinigung") }
            .map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }
}
