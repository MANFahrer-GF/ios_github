import Foundation

// MARK: - Einzelne Stadtportale in NRW (11.11.2026 live geprüft)

/// Je Stadt ein eigenes Portal ohne gemeinsame Plattform:
/// - `detmold`: Straßenliste im Seiten-JavaScript, ICS je Straße und Jahr (`icsmaker.php`)
/// - `herten`: Durth-Roos-Kalender, Straßenseiten je Anfangsbuchstabe, ICS-Link auf der Ergebnisseite
/// - `castrop`: EUV Stadtbetrieb Castrop-Rauxel, JSON-API (Straße → Hausnummer → Termine mit Feiertagsverschiebung)
/// - `monheim`: Stadt Monheim am Rhein, zwei JSON-Listen (Straßen mit Bezirk, alle Termine je Bezirk)
/// - `roesrath`: Stadtwerke Rösrath, WordPress-Ajax liefert die Termine je Straße
/// - `bruehl`: Stadtservice Brühl, Bezirk über Straße + Hausnummer, ICS je Jahr per Formular
/// - `siegen`: Stadt Siegen (citko_abfall), Formular mit Straße + Hausnummer, ICS-Link auf der Ergebnisseite
/// - `verl`: Stadt Verl, ICS je Abfuhrbezirk (1–5) per Formular
/// - `velbert`: TBV Velbert, Adresssuche, Halbjahreskalender als HTML-Tabelle
extension NRWPortalsProvider {
    static let stadtportale: [String: String] = [
        "detmold": "Stadt Detmold", "herten": "ZBH Herten", "castrop": "EUV Stadtbetrieb Castrop-Rauxel",
        "monheim": "Stadt Monheim am Rhein", "roesrath": "Stadtwerke Rösrath", "bruehl": "Stadtservice Brühl",
        "siegen": "Stadt Siegen", "verl": "Stadt Verl", "velbert": "TBV Velbert",
    ]

    static let stadtportalOrte: [String: String] = [
        "detmold": "Detmold", "herten": "Herten", "castrop": "Castrop-Rauxel", "monheim": "Monheim am Rhein",
        "roesrath": "Rösrath", "bruehl": "Brühl", "siegen": "Siegen", "verl": "Verl", "velbert": "Velbert",
    ]

    func stadtportalStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "detmold": return try await detmoldStep(selections)
        case "herten": return try await hertenStep(selections)
        case "castrop": return try await castropStep(selections)
        case "monheim": return try await monheimStep(selections)
        case "roesrath": return try await roesrathStep(selections)
        case "bruehl": return try await bruehlStep(selections)
        case "siegen": return try await siegenStep(selections)
        case "verl": return verlStep(selections)
        case "velbert": return try await velbertStep(selections)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
    }

    func stadtportalPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        switch serviceKey {
        case "detmold": return try await detmoldPickups(selections, calendar: calendar)
        case "herten": return try await hertenPickups(selections, calendar: calendar)
        case "castrop": return try await castropPickups(selections, calendar: calendar)
        case "monheim": return try await monheimPickups(selections, calendar: calendar)
        case "roesrath": return try await roesrathPickups(selections, calendar: calendar)
        case "bruehl": return try await bruehlPickups(selections, calendar: calendar)
        case "siegen": return try await siegenPickups(selections, calendar: calendar)
        case "verl": return try await verlPickups(selections, calendar: calendar)
        case "velbert": return try await velbertPickups(selections, calendar: calendar)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
    }

    /// `2026-11-12` oder `2026-11-12T00:00:00+00:00` als Kalendertag.
    static func isoDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private var currentYear: Int { Calendar(identifier: .gregorian).component(.year, from: referenceDate ?? Date()) }

    // MARK: Detmold

    /// `strasse[N] = {"id":"N","name":"…",…};` im Seitenkopf.
    static func detmoldStreets(_ html: String) -> [SelectionOption] {
        HTMLText.matches(#"strasse\[\d+\]\s*=\s*\{"id":"(\d+)","name":"([^"]+)""#, in: html).map {
            SelectionOption(id: $0[0], title: HTMLText.decodeEntities($0[1]))
        }
    }

    private func detmoldStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let options = Self.detmoldStreets(try await client.string("https://abfuhrkalender.detmold.de/"))
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        var step = SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        step.hint = L10n.t("1.100-Liter-Behälter fährt die Stadt nach eigenem Plan ab, sie stehen nicht in diesem Kalender.",
                           "1,100-litre containers follow a separate plan and are not in this calendar.")
        return step
    }

    private func detmoldPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first?.id else { throw ProviderError.selectAddressFirst }
        func year(_ y: Int) async throws -> [Pickup] {
            let text = try await client.string("https://abfuhrkalender.detmold.de/icsmaker.php?strid=\(street)&year=\(y)")
            return ICS.parse(Self.stripAlarms(text), calendar: calendar).map {
                Pickup(date: $0.date, name: NameCleaner.clean($0.summary.replacingOccurrences(of: #"^Müllabfuhr:\s*"#, with: "", options: .regularExpression)))
            }
        }
        let y = currentYear
        return try await year(y) + ((try? await year(y + 1)) ?? [])
    }

    // MARK: Herten (Durth Roos)

    private static let hertenBase = "https://abfallkalender.durth-roos.de/herten/"

    /// Die Straßenliste kommt seitenweise je Anfangsbuchstabe; der Wert ist die Nummer auf dieser Seite.
    static func hertenPage(_ letter: Character) -> String { durthRoosPage(hertenBase + "index.php", letter) }

    /// Durth-Roos-Kalender (Herten, Gießen): Buchstabenseite `…?von=A&bis=B`.
    static func durthRoosPage(_ page: String, _ letter: Character) -> String {
        let next = letter == "Z" ? "[" : String(Character(UnicodeScalar(letter.unicodeScalars.first!.value + 1)!))
        return page + "?von=\(letter)&bis=\(next)"
    }

    /// Getippter Straßenname → Treffer der passenden Buchstabenseite (Kennung `Buchstabe|Nummer`).
    func durthRoosStreetStep(_ page: String, query raw: String) async throws -> SelectionStep {
        let query = raw.trimmingCharacters(in: .whitespaces)
        guard var letter = query.uppercased().first else { throw Self.notFound(L10n.t("Straße", "street")) }
        letter = ["Ä": "A", "Ö": "O", "Ü": "U"][letter] ?? letter
        guard letter.isASCII, letter.isLetter else { throw Self.notFound(L10n.t("Straße", "street")) }
        let options = Self.hertenStreets(try await client.string(Self.durthRoosPage(page, letter)), letter: letter)
            .filter { $0.title.localizedCaseInsensitiveContains(query) }
        guard !options.isEmpty else { throw Self.notFound(L10n.t("Straße", "street")) }
        return SelectionStep(title: SelectionStep.streetTitle, options: options)
    }

    /// Optionen einer Buchstabenseite; doppelte Namen (Abschnitte einer Straße) bekommen eine Nummer.
    static func hertenStreets(_ html: String, letter: Character) -> [SelectionOption] {
        let raw = HTMLText.matches(#"<option[^>]*value=(\d+)>([^<]+)"#, in: html).map { ($0[0], HTMLText.decodeEntities($0[1]).trimmingCharacters(in: .whitespaces)) }
        var count: [String: Int] = [:], seen: [String: Int] = [:]
        for (_, name) in raw { count[name, default: 0] += 1 }
        return raw.map { value, name in
            seen[name, default: 0] += 1
            let title = (count[name] ?? 0) > 1 ? "\(name) (Abschnitt \(seen[name]!))" : name
            return SelectionOption(id: "\(letter)|\(value)", title: title)
        }
    }

    private func hertenStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname, z. B. Ackerstraße", "Street name, e.g. Ackerstraße"))
        case 1:
            return try await durthRoosStreetStep(Self.hertenBase + "index.php", query: selections[0].id)
        default:
            return nil
        }
    }

    private func hertenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let parts = selections[1].id.split(separator: "|")
        guard parts.count == 2, let letter = parts[0].first else { throw ProviderError.selectAddressFirst }
        let html = HTTPClient.text(from: try await client.postForm(Self.hertenPage(letter), fields: [("strasse", String(parts[1])), ("hausnr", ""), ("anzeigen", "anzeigen")]))
        guard let path = HTMLText.firstMatch(#"(icalendar/[^'"]+\.ics)"#, in: html, group: 1),
              let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw ProviderError.noDataGeneric }
        let text = try await client.string(Self.hertenBase + encoded)
        return ICS.parse(Self.stripAlarms(text), calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: Castrop-Rauxel (EUV)

    private struct EUVResponse<T: Decodable>: Decodable { let response: T }
    private struct EUVItem: Decodable { let id: Int; let name: String? ; let nummer: String? }
    private struct EUVDate: Decodable { let leerung: String }

    private func euv<T: Decodable>(_ method: String, _ args: [(String, String)] = []) async throws -> T {
        var url = "https://www.euv-stadtbetrieb.de/?type=1452982642&tx_leerungsabfrage_api%5Baction%5D=api&tx_leerungsabfrage_api%5BapiMethod%5D=" + method
        for (key, value) in args { url += "&tx_leerungsabfrage_api%5Barguments%5D%5B\(key)%5D=\(value)" }
        return try await client.json(url, as: EUVResponse<T>.self).response
    }

    private func castropStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let streets: [EUVItem] = try await euv("apiGetStreets")
            let options = streets.compactMap { s in s.name.map { SelectionOption(id: String(s.id), title: $0) } }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            let numbers: [EUVItem] = try await euv("apiGetStreetNumbers", [("streetId", selections[0].id), ("holidayShift", "0")])
            let options = numbers.compactMap { n in n.nummer.map { SelectionOption(id: String(n.id), title: $0) } }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: options)
        default:
            return nil
        }
    }

    static let castropNames = ["grau": "Restabfall", "braun": "Bioabfall", "blau": "Papier", "gelb": "Gelbe Tonne"]

    private func castropPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        // holidayShift=1: Termine schon nach Feiertagen verschoben.
        let info: [String: [EUVDate]] = try await euvDates(selections[1].id)
        var result: [Pickup] = []
        for (key, name) in Self.castropNames {
            for entry in info[key] ?? [] {
                guard let day = Self.isoDay(entry.leerung, calendar: calendar) else { continue }
                result.append(Pickup(date: day, name: name))
            }
        }
        return result
    }

    /// Nur die Farblisten der Antwort; `haId`/`nummer` stehen daneben und werden übergangen.
    private func euvDates(_ numberId: String) async throws -> [String: [EUVDate]] {
        let url = "https://www.euv-stadtbetrieb.de/?type=1452982642&tx_leerungsabfrage_api%5Baction%5D=api&tx_leerungsabfrage_api%5BapiMethod%5D=apiGetEmptyInformation"
            + "&tx_leerungsabfrage_api%5Barguments%5D%5BstreetNumberId%5D=\(numberId)&tx_leerungsabfrage_api%5Barguments%5D%5BholidayShift%5D=1"
        let data = try await client.get(url, headers: ["Accept": "application/json"])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any] else { throw ProviderError.noDataGeneric }
        var result: [String: [EUVDate]] = [:]
        for key in Self.castropNames.keys {
            result[key] = (response[key] as? [[String: Any]] ?? []).compactMap { ($0["leerung"] as? String).map(EUVDate.init(leerung:)) }
        }
        return result
    }

    // MARK: Monheim am Rhein

    private struct MonheimStreets: Decodable {
        struct Street: Decodable { let uid: Int; let streetname: String; let district: String }
        let streets: [Street]
    }
    private struct MonheimDates: Decodable {
        struct Entry: Decodable { let dateOfCollection: String; let districts: String; let garbageTypes: String }
        let collectiondates: [Entry]
    }

    /// Abfallarten nach dem Code der Stadt; 1 (Öffnungstage des Wertstoffhofs) ist keine Abfuhr.
    static let monheimTypes: [String: String] = [
        "0": "Spülung und Leerung der Restmülltonnen", "2": "Schadstoffmobil", "3": "Grünabfälle",
        "4": "Spülung und Leerung der Biotonnen", "5": "Gelber Sack", "6": "Restmüll", "7": "Biotonne",
        "8": "Papiertonne", "9": "Zusätzliche Grünabgabe",
    ]

    private func monheimStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let streets = try await client.json("https://www.monheim.de/?type=1106181", as: MonheimStreets.self).streets
        // Kennung = Bezirk(e) der Straße, z. B. „10,6“
        let options = streets.map { SelectionOption(id: "\($0.uid)|\($0.district)", title: $0.streetname) }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
    }

    static func monheimPickups(_ entries: [(date: String, districts: String, type: String)], streetDistricts: String, calendar: Calendar) -> [Pickup] {
        let mine = Set(streetDistricts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        return entries.compactMap { entry in
            let districts = entry.districts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard districts.isEmpty || !mine.isDisjoint(with: districts), let name = monheimTypes[entry.type],
                  let day = isoDay(entry.date, calendar: calendar) else { return nil }
            return Pickup(date: day, name: name)
        }
    }

    private func monheimPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let id = selections.first?.id, let districts = id.split(separator: "|").last else { throw ProviderError.selectAddressFirst }
        let dates = try await client.json("https://www.monheim.de/?type=1106182", as: MonheimDates.self).collectiondates
        return Self.monheimPickups(dates.map { ($0.dateOfCollection, $0.districts, $0.garbageTypes) }, streetDistricts: String(districts), calendar: calendar)
    }

    // MARK: Rösrath (binalarm)

    private struct RoesrathEvent: Decodable { let title: String; let start: String }

    private func roesrathStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let html = try await client.string("https://www.stadtwerke-roesrath.de/service/abfuhrkalender/")
        let options = HTMLText.options(ofSelect: "street", in: html).filter { !$0.value.isEmpty }.map { SelectionOption(id: $0.value, title: $0.label) }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
    }

    private func roesrathPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first?.id else { throw ProviderError.selectAddressFirst }
        let data = try await client.postForm("https://www.stadtwerke-roesrath.de/wp-admin/admin-ajax.php?action=binalarm_filter", fields: [("street", street)],
                                             headers: ["Referer": "https://www.stadtwerke-roesrath.de/service/abfuhrkalender/"])
        let events = try JSONDecoder().decode([RoesrathEvent].self, from: data)
        return events.compactMap { e in Self.isoDay(e.start, calendar: calendar).map { Pickup(date: $0, name: NameCleaner.clean(e.title)) } }
    }

    // MARK: Brühl

    private static let bruehlBase = "https://services.stadtservice-bruehl.de/abfallkalender/"

    private func bruehlStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = HTMLText.options(ofSelect: "street", in: try await client.string(Self.bruehlBase))
                .filter { !$0.value.isEmpty }.map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 12", "e.g. 12"))
        default:
            return nil
        }
    }

    /// „Gelber Sack (gelb), Altpapier (blau) - Kölnstraße 1 (Bezirk: 5K) - Stadt Brühl | …“ → „Gelber Sack“, „Altpapier“
    static func bruehlNames(_ summary: String) -> [String] {
        let head = summary.components(separatedBy: " - ").first ?? summary
        return head.components(separatedBy: ",").map {
            NameCleaner.clean($0.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression))
        }.filter { !$0.isEmpty }
    }

    private func bruehlPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let street = selections[0].id, number = selections[1].id.trimmingCharacters(in: .whitespaces)
        let html = HTTPClient.text(from: try await client.postForm(Self.bruehlBase, fields: [("street", street), ("street_number", number), ("send_street_and_nummber_data", "")]))
        guard let district = HTMLText.firstMatch(#"name="post_district" value="([^"]+)""#, in: html, group: 1) else {
            throw ProviderError.invalidSelection(L10n.t("Diese Hausnummer kennt das Portal nicht.", "The portal does not know this house number."))
        }
        func year(_ y: Int) async throws -> [Pickup] {
            let fields: [(String, String)] = [("post_year", String(y)), ("post_district", district), ("post_street_name", street), ("post_street_number", number)]
                + ["hausmuell", "gelber_sack", "altpapier", "bio", "weihnachtsbaeume", "strassenlaub"].map { ("checked_waste_type_\($0)", "on") }
                + [("form_page_id", "9"), ("reminder_time", "8"), ("send_ics_download_configurator_data", "")]
            let text = HTTPClient.text(from: try await client.postForm(Self.bruehlBase + "individuellen-abfuhrkalender-herunterladen/", fields: fields))
            return ICS.parse(Self.stripAlarms(text), calendar: calendar).flatMap { e in Self.bruehlNames(e.summary).map { Pickup(date: e.date, name: $0) } }
        }
        let y = currentYear
        return try await year(y) + ((try? await year(y + 1)) ?? [])
    }

    // MARK: Siegen (citko_abfall)

    private static let siegenPage = "https://www.siegen.de/leben-in-siegen/buergerservice/abfallentsorgung/abfallkalender"

    private func siegenStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = HTMLText.options(ofSelect: "tx_citkoabfall_abfallkalender[strasse]", in: try await client.string(Self.siegenPage))
                .filter { !$0.value.isEmpty }.map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 12", "e.g. 12"))
        default:
            return nil
        }
    }

    private func siegenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let page = try await client.string(Self.siegenPage)
        guard let form = HTMLText.firstMatch(#"(<form[^>]*id="citko-abfall-form"[\s\S]*?</form>)"#, in: page, group: 1),
              let action = HTMLText.firstMatch(#"action="([^"]+)""#, in: form, group: 1) else { throw ProviderError.noDataGeneric }
        let prefix = "tx_citkoabfall_abfallkalender"
        let fields = HTMLText.hiddenInputs(in: form).filter { $0.name != "\(prefix)[strasse_completed]" }.map { ($0.name, $0.value) }
            + [("\(prefix)[strasse]", selections[0].id), ("\(prefix)[hausnummer]", selections[1].id.trimmingCharacters(in: .whitespaces)),
               ("\(prefix)[strasse_completed]", "1"), ("\(prefix)[submit]", "")]
        let result = HTTPClient.text(from: try await client.postForm("https://www.siegen.de" + HTMLText.decodeEntities(action), fields: fields))
        guard let link = HTMLText.firstMatch(#"href="([^"]*action%5D=ics[^"]*)""#, in: result, group: 1) else {
            throw ProviderError.invalidSelection(L10n.t("Für diese Adresse liefert das Portal keinen Kalender – Hausnummer prüfen.", "The portal has no calendar for this address – please check the house number."))
        }
        let text = try await client.string("https://www.siegen.de" + HTMLText.decodeEntities(link))
        return ICS.parse(Self.stripAlarms(text), calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: Verl

    private static let verlPage = "https://www.verl.de/service/abfallentsorgung/umwelt-und-abfallkalender.html"

    private func verlStep(_ selections: [SelectionOption]) -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        var step = SelectionStep(title: L10n.t("Abfuhrbezirk", "Collection district"),
                                 options: (1...5).map { SelectionOption(id: String($0), title: L10n.t("Abfuhrbezirk \($0)", "Collection district \($0)")) }, searchable: false)
        step.hint = L10n.t("Deinen Bezirk nennt die Stadt Verl unter verl.de → Abfallbezirke.", "The town of Verl lists your district at verl.de → Abfallbezirke.")
        return step
    }

    private func verlPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let district = selections.first?.id else { throw ProviderError.selectAddressFirst }
        // Der Schlüssel wechselt mit jeder Sitzung und steht im Formular der Seite.
        let page = try await client.string(Self.verlPage)
        guard let key = HTMLText.firstMatch(#"middlewareKey=([A-Za-z0-9]+)"#, in: page, group: 1) else { throw ProviderError.noDataGeneric }
        let fields: [(String, String)] = [("id", "50"), ("bezirk\(district)", "on"), ("abfall1", "on"), ("abfall2", "on"), ("abfall3", "on"), ("abfall4", "on"),
                                          ("abfuhr_tag", "0"), ("individuell", "Auswahl laden")]
        let text = HTTPClient.text(from: try await client.postForm("https://www.verl.de/?middlewareAction=createWastecalendarIcs&middlewareKey=\(key)", fields: fields,
                                                                   headers: ["Referer": Self.verlPage]))
        return ICS.parse(Self.stripAlarms(text), calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: Velbert (TBV)

    /// Eingabe → Trefferliste der Adressen (je Treffer eine Kennung `abstid`). Bis 2.0.10 gab es keine Auswahl: Alle Treffer wurden
    /// zusammengemischt („Haupt“: 219 Adressen, 438 Abrufe), und eine nicht vorhandene Nummer endete ohne Hilfe.
    private func velbertStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: L10n.t("Straße und Hausnummer", "Street and house number"), placeholder: L10n.t("z. B. Am Lindenkamp 33", "e.g. Am Lindenkamp 33"))
        case 1:
            let query = selections[0].id.trimmingCharacters(in: .whitespaces)
            var options = Self.velbertAddresses(try await velbertSearch(query))
            var hint: String?
            // Nummer unbekannt („Hauptstraße 1“): die Hausnummern der Straße zeigen
            if options.isEmpty, let street = HTMLText.firstMatch(#"^(.*\D)\s*\d+\s*\w?$"#, in: query, group: 1)?.trimmingCharacters(in: .whitespaces), street.count >= 3 {
                options = Self.velbertAddresses(try await velbertSearch(street))
                hint = L10n.t("„\(query)“ kennt das Portal nicht. Bitte die Adresse aus der Liste wählen.", "The portal does not know “\(query)”. Please choose the address from the list.")
            }
            guard !options.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Keine Adresse gefunden – bitte Straße und Hausnummer angeben, z. B. „Am Lindenkamp 33“.", "No address found – please enter street and house number, e.g. “Am Lindenkamp 33”."))
            }
            var step = SelectionStep(title: L10n.t("Adresse", "Address"), options: options)
            step.hint = hint
            return step
        default:
            return nil
        }
    }

    /// Treffer der Straßensuche: „<strong>Straße</strong><br/> Am Lindenkamp 1“ und die Kalender-Links mit `abstid`.
    static func velbertAddresses(_ html: String) -> [SelectionOption] {
        var seen = Set<String>()
        return html.components(separatedBy: #"class="container waste-result""#).dropFirst().compactMap { block in
            guard let title = HTMLText.firstMatch(#"<strong>Straße</strong><br\s*/?>\s*([^<]+?)\s*</p>"#, in: block, group: 1),
                  let id = HTMLText.firstMatch(#"tx_tbvabfall_kalender%5Babstid%5D=(\d+)"#, in: block, group: 1), seen.insert(id).inserted else { return nil }
            return SelectionOption(id: id, title: HTMLText.decodeEntities(title))
        }
    }

    private func velbertSearch(_ query: String) async throws -> String {
        let page = try await client.string("https://www.tbv-velbert.de/abfall")
        guard let form = HTMLText.firstMatch(#"(<form[^>]*tbvabfall[\s\S]*?</form>)"#, in: page, group: 1),
              let action = HTMLText.firstMatch(#"action="([^"]+)""#, in: form, group: 1) else { throw ProviderError.noDataGeneric }
        let fields = HTMLText.hiddenInputs(in: form).map { ($0.name, $0.value) } + [("tx_tbvabfall_strassensuche[suchbegriff]", query)]
        return HTTPClient.text(from: try await client.postForm("https://www.tbv-velbert.de" + HTMLText.decodeEntities(action), fields: fields))
    }

    static let germanMonths = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]

    /// Halbjahreskalender: Monatstabellen mit Kopf „Juli“, je Tag eine Zeile „08  Mi“ und Tonnen-Bildern; die Legende ordnet Bild → Name.
    static func velbertCalendar(_ html: String, calendar: Calendar) -> [Pickup] {
        guard let yearText = HTMLText.firstMatch(#"Abfallkalender\s+(\d{4})"#, in: html, group: 1), let year = Int(yearText) else { return [] }
        var legend: [String: String] = [:]
        for m in HTMLText.matches(#"Icons/([\w-]+)\.png[^>]*class="abfkalsymbleg"[\s\S]*?class="tonnetext">(?:<br>)?([^<]+)<"#, in: html) {
            legend[m[0]] = NameCleaner.clean(HTMLText.decodeEntities(m[1]))
        }
        var result: [Pickup] = []
        for block in html.components(separatedBy: #"class="abfkalmonrahm""#).dropFirst() {
            guard let monthName = HTMLText.firstMatch(#"class="abfkalmonkopf"[^>]*>([^<]+)<"#, in: block, group: 1),
                  let month = germanMonths.firstIndex(of: monthName.trimmingCharacters(in: .whitespaces)) else { continue }
            for row in HTMLText.matches(#"class="abfkaltaglinks[^"]*">(\d{1,2})&nbsp;[\s\S]*?<td class="abfkaltagrechts[^"]*">([\s\S]*?)</td>"#, in: block) {
                guard let day = Int(row[0]), let date = calendar.date(from: DateComponents(year: year, month: month + 1, day: day)) else { continue }
                for icon in HTMLText.matches(#"Icons/([\w-]+)\.png[^>]*class="abfkalsymb""#, in: row[1]) {
                    result.append(Pickup(date: date, name: legend[icon[0]] ?? icon[0]))
                }
            }
        }
        return result
    }

    private func velbertPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let query = selections.first?.id.trimmingCharacters(in: .whitespaces), !query.isEmpty else { throw ProviderError.selectAddressFirst }
        // Gewählte Adresse: mit ihrem Titel suchen und nur ihre Links nehmen (Halbjahre kommen so immer frisch). Bis 2.0.10
        // gespeicherte Standorte haben nur die Eingabe – dann wie damals alle Treffer.
        let chosen = selections.count > 1 ? selections[1] : nil
        let result = try await velbertSearch(chosen?.title ?? query)
        // Je Halbjahr ein Link mit Startdatum und Adress-Kennung; die Tabelle kommt ohne Druck-Parameter.
        let links = HTMLText.matches(#"tx_tbvabfall_kalender%5Babdate%5D=(\d{8})&(?:amp;)?tx_tbvabfall_kalender%5Babstid%5D=(\d+)"#, in: result)
            .filter { chosen == nil || $0[1] == chosen?.id }
        guard !links.isEmpty else {
            throw ProviderError.invalidSelection(L10n.t("Keine Adresse gefunden – bitte Straße und Hausnummer angeben, z. B. „Am Lindenkamp 33“.", "No address found – please enter street and house number, e.g. “Am Lindenkamp 33”."))
        }
        var pickups: [Pickup] = []
        var seen = Set<String>()
        for link in links where seen.insert(link[0] + link[1]).inserted {
            let url = "https://www.tbv-velbert.de/abfall/abfallkalender/abfallkalender?tx_tbvabfall_kalender%5Babdate%5D=\(link[0])&tx_tbvabfall_kalender%5Babstid%5D=\(link[1])&tx_tbvabfall_kalender%5Baction%5D=calender&tx_tbvabfall_kalender%5Bcontroller%5D=Abfalldaten"
            pickups += Self.velbertCalendar(try await client.string(url), calendar: calendar)
        }
        return pickups
    }
}
