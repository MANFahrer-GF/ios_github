import Foundation

/// Eigene Portale in Hessen und Baden-Württemberg, je Betreiber ein `serviceKey`:
/// - `frankfurt`: FES/FrankfurtPlus – Adresssuche (JSON) → ICS je Adress-ID
/// - `stuttgart`: AWS Stuttgart – Straßenvorschläge → Formular-POST mit Terminliste (HTML)
/// - `wiesbaden`: ELW – Straßensuche → Hausnummern (Objekt-GUID) → ICS
/// - `heidelberg`: Open-Data-API – Wochentag und KW-Rhythmus je Straße, Feiertagsverschiebungen
/// - `heidenheim`: AW Landkreis Heidenheim – Gemeinde → Ortsteil → ggf. Straße → ICS per POST
/// - `badenbaden`: Stadtwerke Baden-Baden Umweltkalender – Stadtteil → ggf. Straße → ICS
/// - `kreiskassel`: Abfallentsorgung Kreis Kassel – Gemeinde → ggf. Gebiet → ICS je Kalender-ID
/// - `reso`: RESO Odenwaldkreis – Ort → Ortsteil → ICS per POST
/// - `muellmann`: Müllmann-App (Landkreis Konstanz, Karlsruhe) – Gemeinde → ggf. Straße → ggf. Hausnummernabschnitt (JSON)
/// - `zvawmk`: ZVA Werra-Meißner-Kreis – Ort → Straße → ICS je Jahresseite
/// - `kelkheim`: Stadt Kelkheim (Taunus) – Straße + Hausnummer per POST → ICS-Link des Bezirks
/// - `floersheim`: Flörsheimer Umweltkalender – Straßensuche → ggf. Hausnummer → Bezirk → ICS
public struct SuedwestPortalsProvider: WasteProvider {
    public static let services = ["frankfurt", "stuttgart", "wiesbaden", "heidelberg", "heidenheim", "badenbaden", "kreiskassel", "reso",
                                  "muellmann", "zvawmk", "kelkheim", "floersheim"]

    public let kind: ProviderKind = .portalsSuedwest
    public let serviceKey: String
    public var displayName: String { kind.displayName }
    private let client: HTTPClient
    /// Stichtag für Jahresangaben in URLs (nil = heute); Tests setzen ihn auf den Abruftag der Beispielantworten.
    var referenceDate: Date?

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "frankfurt": return try await frankfurtStep(selections)
        case "stuttgart": return try await stuttgartStep(selections)
        case "wiesbaden": return try await wiesbadenStep(selections)
        case "heidelberg": return try await heidelbergStep(selections)
        case "heidenheim": return try await heidenheimStep(selections)
        case "badenbaden": return try await badenBadenStep(selections)
        case "kreiskassel": return try await kasselStep(selections)
        case "reso": return try await resoStep(selections)
        case "muellmann": return try await muellmannStep(selections)
        case "zvawmk": return try await zvaStep(selections)
        case "kelkheim": return try await kelkheimStep(selections)
        case "floersheim": return try await floersheimStep(selections)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let result: [Pickup]
        switch serviceKey {
        case "frankfurt": result = try await frankfurtPickups(selections, calendar: calendar)
        case "stuttgart": result = try await stuttgartPickups(selections, calendar: calendar)
        case "wiesbaden": result = try await wiesbadenPickups(selections, calendar: calendar)
        case "heidelberg": result = try await heidelbergPickups(selections, calendar: calendar)
        case "heidenheim": result = try await heidenheimPickups(selections, calendar: calendar)
        case "badenbaden": result = try await badenBadenPickups(selections, calendar: calendar)
        case "kreiskassel": result = try await kasselPickups(selections, calendar: calendar)
        case "reso": result = try await resoPickups(selections, calendar: calendar)
        case "muellmann": result = try await muellmannPickups(selections, calendar: calendar)
        case "zvawmk": result = try await zvaPickups(selections, calendar: calendar)
        case "kelkheim": result = try await kelkheimPickups(selections, calendar: calendar)
        case "floersheim": result = try await floersheimPickups(selections, calendar: calendar)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map(\.title)
        func part(_ i: Int) -> String { i < titles.count ? titles[i] : "" }
        switch serviceKey {
        case "frankfurt":
            // Bei Suche mit Hausnummer steht die vollständige Adresse schon in Schritt 2.
            let street = selections.count > 2 ? "\(part(1)) \(part(2))" : part(1)
            return Self.join(["Frankfurt am Main", street])
        case "stuttgart": return Self.join(["Stuttgart", "\(part(1)) \(part(2))".trimmingCharacters(in: .whitespaces)])
        case "wiesbaden":
            let street = selections.count > 1 ? (selections[1].id.components(separatedBy: ", ").first ?? part(1)) : ""
            let city = selections.count > 1 ? (selections[1].id.components(separatedBy: ", ").dropFirst().first ?? "Wiesbaden") : "Wiesbaden"
            return Self.join([city, "\(street) \(part(2))".trimmingCharacters(in: .whitespaces)])
        case "heidelberg": return Self.join(["Heidelberg", part(0)])
        case "heidenheim":
            // Ortsteil nur nennen, wenn er nicht der Hauptort ist.
            let sameName = selections.count > 1 && selections[1].id == selections[0].id
            let place = sameName || part(1).isEmpty ? part(0) : "\(part(0)) – \(part(1))"
            return Self.join([place, part(3)])
        case "badenbaden":
            let place = part(0) == "Baden-Baden" ? "Baden-Baden" : "Baden-Baden – \(part(0))"
            return Self.join([place, part(1)])
        case "kreiskassel": return selections.count > 1 ? part(1) : part(0)
        case "reso": return part(1) == "Kernstadt" || part(1) == "Kerngemeinde" ? part(0) : Self.join([part(0), part(1)])
        case "muellmann": return Self.join([part(0), selections.count > 2 ? "\(part(1)) \(part(2))" : part(1)])
        case "zvawmk":
            // „Wehretal - Reichensachsen“: Ortsteil nur nennen, wenn er nicht wie die Gemeinde heißt.
            let place = part(0).components(separatedBy: " - ")
            let town = place.count == 2 && place[0] == place[1] ? place[0] : place.joined(separator: " – ")
            return Self.join([town, part(1)])
        case "kelkheim": return Self.join(["Kelkheim (Taunus)", "\(part(0)) \(part(1))".trimmingCharacters(in: .whitespaces)])
        case "floersheim": return Self.join(["Flörsheim am Main", "\(part(1)) \(part(2))".trimmingCharacters(in: .whitespaces)])
        default: return Self.join(titles)
        }
    }

    // MARK: - Gemeinsame Helfer

    private static func join(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func sortedOptions(_ options: [SelectionOption]) -> [SelectionOption] {
        var seen = Set<String>()
        return options.filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func notFound(_ what: String) -> ProviderError {
        .invalidSelection(L10n.t("„\(what)“ wurde nicht gefunden. Bitte die Schreibweise prüfen.", "“\(what)” was not found. Please check the spelling."))
    }

    /// ICS-Termine mit Namensaufbereitung; `clean` darf einen Eintrag in mehrere Fraktionen aufteilen.
    private static func icsPickups(_ text: String, calendar: Calendar, clean: (String) -> [String]) -> [Pickup] {
        ICS.parse(text, calendar: calendar).flatMap { event in
            clean(event.summary).map(NameCleaner.clean).filter { !$0.isEmpty }.map { Pickup(date: event.date, name: $0) }
        }
    }

    private static func split(_ name: String, at separator: String) -> [String] {
        name.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// „31.01.2027“ → Datum.
    private static func germanDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".")
        guard parts.count == 3 else { return nil }
        return Days.parse("\(parts[2])-\(parts[1])-\(parts[0])", calendar: calendar)
    }

    private static func germanDateString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", c.day ?? 1, c.month ?? 1, c.year ?? 2000)
    }

    /// Abschnitt `<form id="…">…</form>` mit Ziel-URL.
    private static func form(_ id: String, in html: String, base: String) -> (action: String, body: String)? {
        let escaped = NSRegularExpression.escapedPattern(for: id)
        guard let tag = HTMLText.firstMatch(#"(<form[^>]*id="\#(escaped)"[^>]*>)"#, in: html, group: 1),
              let body = HTMLText.firstMatch(#"<form[^>]*id="\#(escaped)"[^>]*>([\s\S]*?)</form>"#, in: html, group: 1) else { return nil }
        let action = HTMLText.decodeEntities(HTMLText.firstMatch(#"action="([^"]*)""#, in: tag, group: 1) ?? "")
        let url = action.hasPrefix("http") ? action : base + action
        return (url, body)
    }

    // MARK: - Frankfurt (FES / FrankfurtPlus)

    private struct FrankfurtAddress: Decodable {
        let id: Int
        let street: String
        let house_number: String?
        let label: String
        let street_code: String?
    }

    private func frankfurtStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Zeil", "e.g. Zeil"))
        case 1:
            let query = selections[0].title.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else { throw Self.notFound(query) }
            let found: [FrankfurtAddress] = try await client.json("https://frankfurtplus.de/api/addresses/search?query=\(HTTPClient.query(query))")
            // Ohne Hausnummer liefert die Suche Straßen (mit Straßencode), mit Hausnummer fertige Adressen.
            let options = found.map { entry -> SelectionOption in
                if entry.house_number != nil { return SelectionOption(id: "a:\(entry.id)", title: entry.label) }
                return SelectionOption(id: "s:\(entry.street_code ?? "")", title: entry.label)
            }
            guard !options.isEmpty else { throw Self.notFound(query) }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        case 2:
            guard selections[1].id.hasPrefix("s:") else { return nil }
            let code = String(selections[1].id.dropFirst(2))
            let found: [FrankfurtAddress] = try await client.json("https://frankfurtplus.de/api/addresses/search?street_code=\(HTTPClient.query(code))")
            let options = found.compactMap { entry in entry.house_number.map { SelectionOption(id: "a:\(entry.id)", title: $0) } }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func frankfurtPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let address = selections.last(where: { $0.id.hasPrefix("a:") }) else { throw ProviderError.selectAddressFirst }
        let text = try await client.string("https://frankfurtplus.de/abfallkalender/\(address.id.dropFirst(2))/ical")
        // „Zeil 10 : Restabfall-Abholung“ → „Restabfall“
        return Self.icsPickups(text, calendar: calendar) { summary in
            let name = summary.components(separatedBy: " : ").last ?? summary
            return [name.replacingOccurrences(of: "-Abholung", with: "").replacingOccurrences(of: " Abholung", with: "")]
        }
    }

    // MARK: - Stuttgart (AWS)

    private static let stuttgartBase = "https://service.stuttgart.de/lhs-services/aws"

    private struct StuttgartSuggestions: Decodable {
        struct Item: Decodable { let value: String; let data: String }
        let suggestions: [Item]
    }

    private func stuttgartStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Königstraße", "e.g. Königstraße"))
        case 1:
            // Das Portal kürzt „straße“ zu „str.“ – die Suche klappt mit dem Wortanfang.
            var query = selections[0].title.trimmingCharacters(in: .whitespaces)
            for long in ["straße", "strasse", "Straße", "Strasse"] where query.hasSuffix(long) {
                query = String(query.dropLast(long.count)) + "str"
            }
            let found: StuttgartSuggestions = try await client.json("\(Self.stuttgartBase)/strassennamen?street=\(HTTPClient.query(query))")
            let options = found.suggestions.map { SelectionOption(id: $0.data, title: $0.value) }
            guard !options.isEmpty else { throw Self.notFound(selections[0].title) }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 7", "e.g. 7"))
        case 3:
            // Hausnummer gegen die Vorschlagsliste prüfen – das Formular antwortet sonst mit HTTP 500.
            let number = selections[2].title.replacingOccurrences(of: " ", with: "")
            let found: StuttgartSuggestions = try await client.json("\(Self.stuttgartBase)/hausnummern?street=\(HTTPClient.query(selections[1].id))&streetnr=\(HTTPClient.query(number))")
            guard found.suggestions.contains(where: { $0.data.caseInsensitiveCompare(number) == .orderedSame }) else {
                throw Self.notFound("\(selections[1].title) \(selections[2].title)")
            }
            return nil
        default:
            return nil
        }
    }

    private func stuttgartPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let url = "\(Self.stuttgartBase)/abfuhrtermine"
        let page = try await client.string(url)
        let types = HTMLText.matches(#"name="calendar\[wastetype\]\[\]"[^>]*value="([^"]+)""#, in: page).compactMap(\.first)
        // Zeitraum: Jahresanfang bzw. frühestes erlaubtes Datum bis zum letzten angebotenen Tag.
        let start = HTMLText.firstMatch(#"data-date-start-date="([0-9.]+)""#, in: page, group: 1)
            ?? "01.01.\(calendar.component(.year, from: Date()))"
        let end = HTMLText.firstMatch(#"data-date-end-date="([0-9.]+)""#, in: page, group: 1)
            ?? Self.germanDateString(calendar.date(byAdding: .month, value: 6, to: Date()) ?? Date())
        var fields: [(String, String)] = [("calendar[street]", selections[1].id),
                                          ("calendar[streetnr]", selections[2].title.replacingOccurrences(of: " ", with: "")),
                                          ("calendar[datefrom]", start), ("calendar[dateto]", end)]
        fields += (types.isEmpty ? ["restmuell", "biomuell", "altpapier", "gelbersack"] : types).map { ("calendar[wastetype][]", $0) }
        fields.append(("calendar[submit]", ""))
        let html: String
        do {
            html = HTTPClient.text(from: try await client.postForm(url, fields: fields))
        } catch HTTPError.status(500, _) {
            throw Self.notFound("\(selections[1].title) \(selections[2].title)")
        }
        return Self.parseStuttgart(html, calendar: calendar)
    }

    /// Tabelle `#awstable`: Kopfzeile je Fraktion, darunter Zeilen „Wochentag | Datum | Rhythmus“.
    /// Hat eine Fraktion mehrere Rhythmen (z. B. Restabfall wöchentlich und 14-täglich), steht er im Namen.
    static func parseStuttgart(_ html: String, calendar: Calendar) -> [Pickup] {
        guard let table = HTMLText.firstMatch(#"<table[^>]*id="awstable"[^>]*>([\s\S]*?)</table>"#, in: html, group: 1) else { return [] }
        var rows: [(type: String, date: Date, rhythm: String)] = []
        var current = ""
        for row in HTMLText.matches(#"<tr[^>]*>([\s\S]*?)</tr>"#, in: table).compactMap(\.first) {
            if let head = HTMLText.firstMatch(#"<th[^>]*>([\s\S]*?)</th>"#, in: row, group: 1) {
                current = HTMLText.decodeEntities(HTMLText.stripTags(head)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            let cells = HTMLText.matches(#"<td[^>]*>([\s\S]*?)</td>"#, in: row).compactMap(\.first)
                .map { HTMLText.decodeEntities(HTMLText.stripTags($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cells.count >= 2, !current.isEmpty, let date = germanDate(cells[1], calendar: calendar) else { continue }
            rows.append((current, date, cells.count > 2 ? cells[2] : ""))
        }
        var rhythms: [String: Set<String>] = [:]
        for row in rows { rhythms[row.type, default: []].insert(row.rhythm) }
        return rows.map { row in
            guard (rhythms[row.type]?.count ?? 0) > 1 else { return Pickup(date: row.date, name: NameCleaner.clean(row.type)) }
            return Pickup(date: row.date, name: NameCleaner.clean("\(row.type) (\(stuttgartRhythm(row.rhythm)))"))
        }
    }

    /// „01-wöchentl.“ → „wöchentlich“, „02-wöchentl.“ → „2-wöchentlich“
    private static func stuttgartRhythm(_ text: String) -> String {
        guard let weeks = HTMLText.firstMatch(#"^0*(\d+)"#, in: text, group: 1).flatMap(Int.init) else { return text }
        return weeks == 1 ? L10n.t("wöchentlich", "weekly") : L10n.t("\(weeks)-wöchentlich", "every \(weeks) weeks")
    }

    // MARK: - Wiesbaden (ELW)

    private struct ELWStreet: Decodable { let street: String; let city: String }
    private struct ELWNumber: Decodable { let objid: String; let housenumber: String; let housenumberadd: String }

    private func wiesbadenStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let base = "https://www.elw.de/abfallkalender"
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Rheinstraße", "e.g. Rheinstraße"))
        case 1:
            let query = selections[0].title.trimmingCharacters(in: .whitespaces)
            let found: [ELWStreet] = try await client.json("\(base)?type=4712&sword=\(HTTPClient.query(query))")
            let options = found.map { SelectionOption(id: "\($0.street), \($0.city)", title: $0.street, subtitle: $0.city) }
            guard !options.isEmpty else { throw Self.notFound(query) }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        case 2:
            let found: [ELWNumber] = try await client.json("\(base)?type=4713&street=\(HTTPClient.query(selections[1].id))&housenumber=")
            // Hausnummer 0 steht für Objekte ohne Nummer – nur anbieten, wenn es nichts anderes gibt.
            let numbered = found.filter { $0.housenumber != "0" }
            let options = (numbered.isEmpty ? found : numbered).map { SelectionOption(id: $0.objid, title: $0.housenumber + $0.housenumberadd) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func wiesbadenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let text = try await client.string("https://www.elw.de/fileadmin/elw/php/downloads.php?func=ical&obj=\(HTTPClient.query(selections[2].id))&location=0")
        return Self.icsPickups(text, calendar: calendar) { summary in
            // „ELW - Baumsammlung“ ist die Abfuhr der Weihnachtsbäume im Januar.
            [summary.replacingOccurrences(of: "ELW - ", with: "").replacingOccurrences(of: "Baumsammlung", with: "Weihnachtsbaumsammlung")]
        }
    }

    // MARK: - Heidelberg (Open-Data-API)

    private static let heidelbergAPI = "https://garbage.datenplattform.heidelberg.de"

    private struct HeidelbergData: Decodable {
        struct Collection: Decodable {
            let calendar_week_bio: String?, calendar_week_dsd: String?, calendar_week_paper: String?, calendar_week_rest: String?
            let day_of_week_bio: String?, day_of_week_dsd: String?, day_of_week_paper: String?, day_of_week_rest: String?
        }
        struct Shift: Decodable { let shift_from_date: String; let shift_to_date: String }
        struct Christmas: Decodable { let collection_date: String }
        let collections: [Collection]
        let exceptions: [Shift]?
        let christmas: [Christmas]?
    }

    /// Straßenliste: `[["Adlerstraße Nr. 1-53", false], …]`
    private struct HeidelbergStreet: Decodable {
        let name: String
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            name = try container.decode(String.self)
        }
    }

    private func heidelbergData(_ street: String) async throws -> HeidelbergData {
        try await client.json("\(Self.heidelbergAPI)/collections?street=\(HTTPClient.query(street))")
    }

    private func heidelbergStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let streets: [HeidelbergStreet] = try await client.json("\(Self.heidelbergAPI)/streetnames")
            let options = streets.map { SelectionOption(id: $0.name, title: $0.name) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            // Restabfall ist wöchentlich; auf Antrag 14-täglich, dann nach gerader/ungerader Hausnummer.
            let data = try await heidelbergData(selections[0].id)
            guard let entry = data.collections.first else { throw ProviderError.noDataGeneric }
            guard entry.calendar_week_rest == "A" else { return nil }
            return SelectionStep(title: L10n.t("Leerung Restabfall", "Residual waste collection"), options: [
                SelectionOption(id: "A", title: L10n.t("wöchentlich", "weekly")),
                SelectionOption(id: "G", title: L10n.t("14-täglich (gerade Hausnummer)", "every 2 weeks (even house number)")),
                SelectionOption(id: "U", title: L10n.t("14-täglich (ungerade Hausnummer)", "every 2 weeks (odd house number)")),
            ], searchable: false)
        default:
            return nil
        }
    }

    private func heidelbergPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first?.id else { throw ProviderError.selectAddressFirst }
        let data = try await heidelbergData(street)
        guard let entry = data.collections.first else { throw ProviderError.noDataGeneric }
        let restRhythm = selections.count > 1 ? selections[1].id : entry.calendar_week_rest
        let year = calendar.component(.year, from: Date())
        let shifts = Dictionary((data.exceptions ?? []).map { (String($0.shift_from_date.prefix(10)), String($0.shift_to_date.prefix(10))) }) { a, _ in a }
        // Bis Jahresende, bei bekannten Verschiebungen im neuen Jahr auch etwas länger.
        let end = max("\(year)-12-31", shifts.keys.max() ?? "")
        let fractions: [(String, String?, String?)] = [
            ("Restabfall", entry.day_of_week_rest, restRhythm),
            ("Bioabfall", entry.day_of_week_bio, entry.calendar_week_bio),
            ("Gelbe Tonne", entry.day_of_week_dsd, entry.calendar_week_dsd),
            ("Papiertonne", entry.day_of_week_paper, entry.calendar_week_paper),
        ]
        var result: [Pickup] = []
        for (name, day, rhythm) in fractions {
            guard let day, let rhythm else { continue }
            for iso in Self.heidelbergDates(weekday: day, rhythm: rhythm, from: "\(year)-01-01", to: end) {
                if let date = Days.parse(shifts[iso] ?? iso, calendar: calendar) { result.append(Pickup(date: date, name: name)) }
            }
        }
        for tree in data.christmas ?? [] {
            if let date = Days.parse(String(tree.collection_date.prefix(10)), calendar: calendar) { result.append(Pickup(date: date, name: "Weihnachtsbaum")) }
        }
        return result
    }

    /// Alle Tage eines Wochentags („Mo“ … „Sa“) im Zeitraum; Rhythmus A = jede Woche,
    /// G/U = gerade/ungerade Kalenderwoche (ISO 8601). Ergebnis als „yyyy-MM-dd“.
    static func heidelbergDates(weekday: String, rhythm: String, from: String, to: String) -> [String] {
        let weekdays = ["So": 1, "Mo": 2, "Di": 3, "Mi": 4, "Do": 5, "Fr": 6, "Sa": 7]
        guard let target = weekdays[weekday] else { return [] }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard var day = Days.parse(from, calendar: iso), let last = Days.parse(to, calendar: iso) else { return [] }
        while iso.component(.weekday, from: day) != target {
            guard let next = iso.date(byAdding: .day, value: 1, to: day) else { return [] }
            day = next
        }
        var result: [String] = []
        while day <= last {
            let week = iso.component(.weekOfYear, from: day)
            if rhythm == "A" || (rhythm == "G" && week % 2 == 0) || (rhythm == "U" && week % 2 == 1) {
                let c = iso.dateComponents([.year, .month, .day], from: day)
                result.append(String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            }
            guard let next = iso.date(byAdding: .day, value: 7, to: day) else { break }
            day = next
        }
        return result
    }

    // MARK: - Landkreis Heidenheim

    private static let heidenheimBase = "https://mobil.abfallwirtschaft-heidenheim.de"
    /// Amtliche Namen für die Kurzformen des Portals.
    private static let heidenheimNames = ["Giengen": "Giengen an der Brenz", "Heidenheim": "Heidenheim an der Brenz",
                                          "Sontheim": "Sontheim an der Brenz", "Steinheim": "Steinheim am Albuch"]

    /// Links `index.php?…&<param>=Wert` einer Auswahlseite.
    private static func heidenheimLinks(_ html: String, param: String) -> [String] {
        HTMLText.matches(#"href="/index\.php\?[^"]*?&amp;\#(param)=([^"&]+)""#, in: html).compactMap(\.first)
            .map { HTMLText.decodeEntities($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? $0 }
    }

    private func heidenheimPage(_ query: String) async throws -> String {
        try await client.string("\(Self.heidenheimBase)/index.php?\(query)")
    }

    private func heidenheimYears() async throws -> [Int] {
        let html = try await client.string("\(Self.heidenheimBase)/")
        let years = Set(HTMLText.matches(#"jahr=(\d{4})"#, in: html).compactMap { $0.first.flatMap(Int.init) })
        return years.isEmpty ? [Calendar.current.component(.year, from: Date())] : years.sorted()
    }

    /// Kürzel für die Straßensuche, falls der Ortsteil nach Straßen getrennt ist (z. B. `hdh`).
    private func heidenheimStreetKey(_ selections: [SelectionOption], year: Int) async throws -> String? {
        let html = try await heidenheimPage("jahr=\(year)&gemeinde=\(HTTPClient.query(selections[0].id))&ortsteil=\(HTTPClient.query(selections[1].id))")
        return HTMLText.firstMatch(#"searchSuggest\('([^']+)'"#, in: html, group: 1)
    }

    private func heidenheimStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let year = try await heidenheimYears().first { $0 >= Calendar.current.component(.year, from: Date()) } ?? Calendar.current.component(.year, from: Date())
        switch selections.count {
        case 0:
            let html = try await heidenheimPage("jahr=\(year)")
            let options = Self.heidenheimLinks(html, param: "gemeinde").map { SelectionOption(id: $0, title: Self.heidenheimNames[$0] ?? $0) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(options))
        case 1:
            let html = try await heidenheimPage("jahr=\(year)&gemeinde=\(HTTPClient.query(selections[0].id))")
            let options = Self.heidenheimLinks(html, param: "ortsteil").map { SelectionOption(id: $0, title: $0) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.districtTitle, options: Self.sortedOptions(options))
        case 2:
            guard try await heidenheimStreetKey(selections, year: year) != nil else { return nil }
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Hauptstraße", "e.g. Hauptstraße"))
        case 3:
            guard let key = try await heidenheimStreetKey(selections, year: year) else { return nil }
            let query = selections[2].title.trimmingCharacters(in: .whitespaces)
            let text = try await client.string("\(Self.heidenheimBase)/strassen.php?jahr=\(year)&stadt=\(HTTPClient.query(key))&search=\(HTTPClient.query(query))")
            let options = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                .map { SelectionOption(id: $0, title: $0) }
            guard !options.isEmpty else { throw Self.notFound(query) }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func heidenheimPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let street = selections.count >= 4 ? selections[3].id : ""
        var result: [Pickup] = []
        for year in try await heidenheimYears() {
            let fields = [("jahr", String(year)), ("gemeinde", selections[0].id), ("ortsteil", selections[1].id), ("strasse", street),
                          ("tag", "0"), ("uhrzeit", ""), ("bio", "1"), ("garten", "1"), ("gs", "1"), ("rest", "1"), ("papier", "1"), ("papiertonne", "1")]
            guard let data = try? await client.postForm("\(Self.heidenheimBase)/ical.php", fields: fields) else { continue }
            // „Restmüll+Gelber Sack Bereitstellung“ → „Restmüll“, „Gelber Sack“
            result += Self.icsPickups(HTTPClient.text(from: data), calendar: calendar) { summary in
                Self.split(summary.replacingOccurrences(of: " Bereitstellung", with: ""), at: "+")
            }
        }
        return result
    }

    // MARK: - Baden-Baden (Stadtwerke, Umweltkalender)

    private static let badenBadenPage = "https://www.stadtwerke-baden-baden.de/de/entsorgung/umweltkalender.php"

    private func badenBadenStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.badenBadenPage)
            let options = HTMLText.options(ofSelect: "location", in: html).filter { !$0.value.isEmpty }.map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Stadtteil", "District"), options: options, searchable: false)
        case 1:
            // Nur die Kernstadt (data-city) ist nach Straßen getrennt.
            guard selections[0].id == "0" else { return nil }
            let html = try await client.string(Self.badenBadenPage)
            let options = HTMLText.options(ofSelect: "street", in: html).filter { !$0.value.isEmpty }.map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func badenBadenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let location = selections.first?.id else { throw ProviderError.selectAddressFirst }
        if location == "0" && selections.count < 2 { throw ProviderError.selectAddressFirst }
        // Gartenabfälle, Gelbe Tonne, Altpapier, Restmüll, Biotonne (ohne Sondermüll-Sammelstelle)
        var query = "location=\(HTTPClient.query(location))"
        if location == "0" { query += "&street=\(HTTPClient.query(selections[1].id))" }
        query += "&wastetype1=on&wastetype2=on&wastetype3=on&wastetype5=on&wastetype6=on&submit=submit"
        let text = try await client.string("https://www.stadtwerke-baden-baden.de/wLayout/wGlobal/scripts/php/umweltkalender/output/outputIcal.php?\(query)")
        return Self.icsPickups(text, calendar: calendar) { [$0.replacingOccurrences(of: " - Stadt Baden-Baden", with: "")] }
    }

    // MARK: - Abfallentsorgung Kreis Kassel

    private static let kasselBase = "https://webapp.abfall-kreis-kassel.de"

    /// Schickt eines der TYPO3-Formulare (Gemeinde oder Gebiet) samt versteckter Felder ab.
    private func kasselSubmit(_ html: String, form id: String, field: String, value: String) async throws -> String {
        guard let form = Self.form(id, in: html, base: Self.kasselBase) else { throw ProviderError.noDataGeneric }
        var fields = HTMLText.hiddenInputs(in: form.body).filter { $0.name != field }.map { ($0.name, $0.value) }
        fields.append((field, value))
        return HTTPClient.text(from: try await client.postForm(form.action, fields: fields))
    }

    private func kasselCommunityPage(_ community: String) async throws -> String {
        let start = try await client.string("\(Self.kasselBase)/abfallkalender")
        return try await kasselSubmit(start, form: "select-community-form", field: "tx_abfallkalender_pi2[community]", value: community)
    }

    private func kasselStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string("\(Self.kasselBase)/abfallkalender")
            let options = HTMLText.options(ofSelect: "tx_abfallkalender_pi2[community]", in: html).filter { !$0.value.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(options))
        case 1:
            // Gemeinden mit mehreren Abfuhrgebieten zeigen eine weitere Auswahl, sonst direkt den Kalender.
            let html = try await kasselCommunityPage(selections[0].id)
            let options = HTMLText.options(ofSelect: "tx_abfallkalender_pi2[territory]", in: html).filter { !$0.value.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            return options.isEmpty ? nil : SelectionStep(title: L10n.t("Abfuhrgebiet", "Collection area"), options: options)
        default:
            return nil
        }
    }

    private func kasselPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let community = selections.first?.id else { throw ProviderError.selectAddressFirst }
        var html = try await kasselCommunityPage(community)
        if selections.count > 1 {
            html = try await kasselSubmit(html, form: "select-territory-form", field: "tx_abfallkalender_pi2[territory]", value: selections[1].id)
        }
        // Kalender-IDs für dieses und (falls schon da) nächstes Jahr.
        let ids = Array(Set(HTMLText.matches(#"tx_abfallkalender_pi2%5Bcalendar%5D=(\d+)"#, in: html).compactMap(\.first)))
        guard !ids.isEmpty else { throw ProviderError.noDataGeneric }
        var result: [Pickup] = []
        for id in ids.sorted() {
            let url = "\(Self.kasselBase)/abfallkalender?no_cache=1&tx_abfallkalender_pi2%5Baction%5D=ical&tx_abfallkalender_pi2%5Bcontroller%5D=Export"
                + "&cHash=b75e567196581fb1832c0a09b943f2bc&tx_abfallkalender_pi2%5Bcalendar%5D=\(id)&tx_abfallkalender_pi2%5Bfractions%5D=1,2,3,4,5,6,7"
            guard let text = try? await client.string(url) else { continue }
            result += Self.icsPickups(text, calendar: calendar) { [$0] }
        }
        return result
    }

    // MARK: - RESO (Odenwaldkreis)

    private static let resoBase = "https://reso-gmbh.abfallkalender.services/php"

    private func resoStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string("\(Self.resoBase)/AuswahlMuellkalender.php?lang=Deutsch&nr=0&pfad=Deutsch.muellkalender&browser=Firefox&mobil=nein")
            let options = HTMLText.options(ofSelect: "Ort", in: html).filter { !$0.value.isEmpty }.map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: options)
        case 1:
            let html = try await client.string("\(Self.resoBase)/AuswahlMuellkalender.php?pfad=Deutsch.muellkalender&Ot=\(HTTPClient.query(selections[0].id))&nr=0&browser=Firefox&jahr=")
            let options = HTMLText.options(ofSelect: "Ortsteil", in: html).filter { !$0.value.isEmpty && $0.value != "Alle" }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.districtTitle, options: options)
        default:
            return nil
        }
    }

    private func resoPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            let fields = [("Ort", selections[0].id), ("Ortsteil", selections[1].id), ("Jahr", String(target)), ("art", "1"), ("downOderurl2", "Semikolon")]
            guard let data = try? await client.postForm("\(Self.resoBase)/Kalender-2-ICS.php", fields: fields) else { continue }
            // „Restmüll + Gelber-Sack“ → zwei Termine; Sammelstellen-Zusätze nach dem Bindestrich weglassen.
            result += Self.icsPickups(HTTPClient.text(from: data), calendar: calendar) { summary in
                Self.split(summary, at: " + ").map { part in
                    part.components(separatedBy: " - ").first?.replacingOccurrences(of: "Gelber-Sack", with: "Gelber Sack") ?? part
                }
            }
        }
        return result
    }

    // MARK: - Müllmann-App (Landkreis Konstanz, Karlsruhe)

    private static let muellmannBase = "https://muellmann.gering.dev"
    /// Öffentlicher Schlüssel aus dem Web-Client der App; ohne ihn antwortet die API mit HTTP 401.
    private static let muellmannHeaders = ["X-API-Key": "fz2LM67Xurs1sXjmHEIAlhssIS1mBlf8"]

    private struct MuellmannItem: Decodable { let key: String; let name: String }
    private struct MuellmannStreet: Decodable {
        struct Range: Decodable { let selector: String; let name: String?; let info: String? }
        let ranges: [Range]
    }
    private struct MuellmannEvent: Decodable { let type: String; let date: String }

    private func muellmann<T: Decodable>(_ path: String) async throws -> T {
        try await client.json(Self.muellmannBase + path, headers: Self.muellmannHeaders)
    }

    private func muellmannStreet(_ region: String, _ street: String) async throws -> MuellmannStreet {
        try await muellmann("/\(HTTPClient.query(region))/streets/\(HTTPClient.query(street))")
    }

    private func muellmannStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let regions: [MuellmannItem] = try await muellmann("/")
            let options = regions.map { SelectionOption(id: $0.key, title: $0.name) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(options))
        case 1:
            // Kleine Gemeinden haben einen Kalender für alle, dann ist die Straßenliste leer.
            let streets: [MuellmannItem] = try await muellmann("/\(HTTPClient.query(selections[0].id))/streets")
            guard !streets.isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets.map { SelectionOption(id: $0.key, title: $0.name) }))
        case 2:
            // Lange Straßen sind in Hausnummern-Abschnitte geteilt.
            let street = try await muellmannStreet(selections[0].id, selections[1].id)
            guard street.ranges.count > 1 else { return nil }
            let options = street.ranges.map { SelectionOption(id: $0.selector, title: $0.name ?? $0.selector, subtitle: $0.info) }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: options, searchable: false)
        default:
            return nil
        }
    }

    private func muellmannPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let region = selections.first.map({ HTTPClient.query($0.id) }) else { throw ProviderError.selectAddressFirst }
        var path = "/\(region)/events"
        if selections.count > 1 {
            let selector: String
            if selections.count > 2 {
                selector = selections[2].id
            } else {
                selector = try await muellmannStreet(selections[0].id, selections[1].id).ranges.first?.selector ?? "*"
            }
            path += "/\(HTTPClient.query(selections[1].id))/\(HTTPClient.query(selector))"
        }
        let headers = Self.muellmannHeaders.merging(["Accept": "application/json"]) { a, _ in a }
        let events = try await client.get(Self.muellmannBase + path, headers: headers)
        let types = try await client.get("\(Self.muellmannBase)/\(region)/types", headers: headers)
        return Self.muellmannPickups(events: events, types: types, calendar: calendar)
    }

    /// Termine `{"type":"bio","date":"12.10.2026"}` mit den Namen aus der Abfallarten-Liste der Gemeinde.
    static func muellmannPickups(events: Data, types: Data, calendar: Calendar) -> [Pickup] {
        guard let events: [MuellmannEvent] = try? HTTPClient.decode(events) else { return [] }
        let list: [MuellmannItem] = (try? HTTPClient.decode(types)) ?? []
        let names = Dictionary(list.map { ($0.key, $0.name) }) { a, _ in a }
        return events.compactMap { event in
            guard let name = names[event.type], let date = germanDate(event.date, calendar: calendar) else { return nil }
            return Pickup(date: date, name: NameCleaner.clean(name))
        }
    }

    // MARK: - ZVA Werra-Meißner-Kreis

    /// Je Jahr eine eigene Seite; die des Folgejahres gibt es erst gegen Jahresende (vorher HTTP 404).
    private static func zvaPage(_ year: Int) -> String {
        "https://www.zva-wmk.de/termine/pers%C3%B6nlicher-terminkalender-\(year)"
    }

    private func zvaStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let page = Self.zvaPage(Calendar.current.component(.year, from: referenceDate ?? Date()))
        // Die Werte im Auswahlfeld sind schon URL-kodiert („WEI%C3%9FENBORN_RAMBACH“) und gehen unverändert zurück.
        switch selections.count {
        case 0:
            let html = try await client.string(page)
            let options = HTMLText.options(ofSelect: "city", in: html).filter { !$0.value.isEmpty }.map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: options)
        case 1:
            let html = try await client.string("\(page)?city=\(selections[0].id)")
            let options = HTMLText.options(ofSelect: "street", in: html).filter { !$0.value.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label.localizedCapitalized) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        default:
            return nil
        }
    }

    private func zvaPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let year = calendar.component(.year, from: referenceDate ?? Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            let url = "\(Self.zvaPage(target))?city=\(selections[0].id)&street=\(selections[1].id)&type=all&link=ical&fullday=1"
            guard let text = try? await client.string(url) else { continue }
            result += Self.icsPickups(text, calendar: calendar) { [$0.replacingOccurrences(of: " Und ", with: " und ")] }
        }
        return result
    }

    // MARK: - Kelkheim (Taunus)

    /// Ohne „www“: Die Weiterleitung von www.kelkheim.de würde aus dem POST ein GET ohne Formularfelder machen.
    private static let kelkheimPage = "https://kelkheim.de/mod_abfallkalender/"
    /// Abfallarten des Formulars ohne Großcontainer, Annahmestellen und Veranstaltungen (Repair-Café …).
    private static let kelkheimTypes = [("Restmuell", "Restmüll"), ("Blaue Tonne", "Blaue Tonne"), ("Bio-Tonne", "Bio-Tonne"), ("Gelber Sack", "Gelber Sack"),
                                        ("Gruenabfuhr", "Grünabfuhr"), ("Sperrmuell", "Sperrmüll"), ("Sondermuell", "Sondermüll")]

    /// Straßenliste aus dem Autocomplete-Skript `var availableTags = ["…", …];`
    static func kelkheimStreets(_ html: String) -> [SelectionOption] {
        guard let list = HTMLText.firstMatch(#"availableTags\s*=\s*\[([\s\S]*?)\]"#, in: html, group: 1) else { return [] }
        let names = HTMLText.matches(#""([^"]+)""#, in: list).compactMap(\.first)
        return sortedOptions(names.map { SelectionOption(id: $0, title: $0.trimmingCharacters(in: .whitespaces)) })
    }

    /// „Restmuell Bezirk B-5, S-5 Di“ → „Restmüll“
    static func kelkheimName(_ summary: String) -> String {
        let type = summary.replacingOccurrences(of: #"\s+Bezirk\s.*$"#, with: "", options: .regularExpression)
        return kelkheimTypes.first { $0.0 == type }?.1 ?? type
    }

    private func kelkheimStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = Self.kelkheimStreets(try await client.string(Self.kelkheimPage))
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 7", "e.g. 7"))
        default:
            return nil
        }
    }

    private func kelkheimPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let number = selections[1].title.trimmingCharacters(in: .whitespaces)
        // Das Formular leitet auf die Kalenderseite des Bezirks weiter; dort steht der ICS-Link.
        let fields = [("action", "areas_search"), ("street", selections[0].id), ("number", number)] + Self.kelkheimTypes.map { ("datetype[]", $0.0) }
        let html = HTTPClient.text(from: try await client.postForm(Self.kelkheimPage, fields: fields))
        guard let link = HTMLText.firstMatch(#"(https://[^"'<>\s]*mod_abfallkalender/index\.php\?action=ical[^"'<>\s]*)"#, in: html, group: 1) else {
            throw Self.notFound("\(selections[0].title) \(number)")
        }
        let text = try await client.string(HTMLText.decodeEntities(link))
        return Self.icsPickups(text, calendar: calendar) { [Self.kelkheimName($0)] }
    }

    // MARK: - Flörsheim am Main (Umweltkalender)

    private static let floersheimBase = "https://www.floersheim-umweltkalender.de/"
    /// Restmüll, Altpapier, Bio-Tonne, Gelber Sack, Gartenabfall, Sonderabfälle – ohne Großcontainer
    /// sowie Sperrmüll und E-Schrott, die nur nach Anmeldung abgeholt werden.
    private static let floersheimTypes = "1_3_7_4_8_6"

    /// Vorschlagsliste der Straßensuche: `<span id="astr0" …>Hauptstraße</span>`
    static func floersheimStreets(_ html: String) -> [SelectionOption] {
        let names = HTMLText.matches(#"<span id="astr\d+"[^>]*>([^<]+)</span>"#, in: html).compactMap(\.first).map(HTMLText.decodeEntities)
        return sortedOptions(names.map { SelectionOption(id: $0, title: $0.trimmingCharacters(in: .whitespaces)) })
    }

    /// „Sonderabfälle, Flörsheim, Sportanlagen Hauptstraße 8.00-10.00 Uhr“ → „Schadstoffmobil“;
    /// Termine an der Deponie Wicker sind Annahmezeiten, keine Abholung vor der Tür.
    static func floersheimNames(_ summary: String) -> [String] {
        guard !summary.contains("Deponie") else { return [] }
        let type = summary.components(separatedBy: ",")[0].trimmingCharacters(in: .whitespaces)
        return [type == "Sonderabfälle" ? "Schadstoffmobil" : type]
    }

    private func floersheimStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Hauptstraße", "e.g. Hauptstraße"))
        case 1:
            let query = selections[0].title.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { throw Self.notFound(query) }
            let html = HTTPClient.text(from: try await client.postForm("\(Self.floersheimBase)ajaxsearch/ajaxseachstr.html", fields: [("searchstr", query)]))
            let options = Self.floersheimStreets(html)
            guard !options.isEmpty else { throw Self.notFound(query) }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        case 2:
            // Antwort > 0: Die Straße ist nach Hausnummern auf mehrere Bezirke verteilt.
            let answer = HTTPClient.text(from: try await client.postForm("\(Self.floersheimBase)ajaxsearch/searchnachnr.html", fields: [("strname", selections[1].id)]))
            guard (Int(answer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0 else { return nil }
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 7", "e.g. 7"))
        default:
            return nil
        }
    }

    private func floersheimPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let street = selections[1].id
        let number = selections.count > 2 ? selections[2].title.trimmingCharacters(in: .whitespaces) : ""
        var fields = [("strnamesearch", street), ("checkedarts", Self.floersheimTypes)]
        if !number.isEmpty { fields.append(("hsnrsearch", number)) }
        // „1|||<Bezirk>|||<Straßen-ID>|||“ oder „0|||||||||<Fehlermeldung>“
        let answer = HTTPClient.text(from: try await client.postForm("\(Self.floersheimBase)ajaxsearch/searchnachnrundstr.html", fields: fields))
        let parts = answer.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "|||")
        guard parts.count > 1, parts[0] == "1", !parts[1].isEmpty else {
            throw Self.notFound("\(selections[1].title) \(number)".trimmingCharacters(in: .whitespaces))
        }
        let url = "\(Self.floersheimBase)icalkalender.html?jahr=1&selectedmonat=&selectedwoche=&bezirk=\(HTTPClient.query(parts[1]))"
            + "&hausnr=\(HTTPClient.query(number))&strasse=\(HTTPClient.query(street))&checkedarts=\(Self.floersheimTypes)"
        return Self.icsPickups(try await client.string(url), calendar: calendar, clean: Self.floersheimNames)
    }
}
