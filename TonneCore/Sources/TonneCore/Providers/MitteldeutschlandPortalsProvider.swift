import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Portale in Thüringen und Sachsen-Anhalt mit eigener Technik. `serviceKey` wählt den Betreiber:
/// - `hws` – HWS Halle (Saale): Straßenliste, Hausnummern/Gewerbe per AJAX, ICS je Jahr
/// - `jena` – KSJ Jena: Straßen/Hausnummern aus `getMainSelectMenus`, ICS über `makeICSAll`
/// - `nordhausen` – Landkreis Nordhausen: Adressliste als JSON, ICS je Adresse
/// - `uhk` – Unstrut-Hainich-Kreis: statische ICS-Datei je Ort/Stadttour
/// - `awvot` – AWV Ostthüringen (Gera, Greiz): Formular-Schritte (Latin-1), ICS aus der PHP-Sitzung
/// - `kyffhaeuser` – Kyffhäuserkreis: WordPress „The Events Calendar“-API je Ort/Tour
/// - `sonneberg` – Landkreis Sonneberg: Ort/Ortsteil/Straße per AJAX, ICS per POST
/// - `ajl` – AJL Jerichower Land: Orts-/Straßenauswahl, Termine aus der HTML-Seite
/// - `weimar` – KS Weimar: Straßentabelle (Wochentag + gerade/ungerade KW) → berechnete Termine
public struct MitteldeutschlandPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsMitte
    public let serviceKey: String
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    static let names: [String: String] = [
        "hws": "HWS Halle (Saale)",
        "jena": "KSJ Jena",
        "nordhausen": "Abfallwirtschaft Nordhausen",
        "uhk": "AWB Unstrut-Hainich-Kreis",
        "awvot": "AWV Ostthüringen",
        "kyffhaeuser": "Abfallwirtschaft Kyffhäuserkreis",
        "sonneberg": "Abfallwirtschaft Sonneberg",
        "ajl": "AJL Jerichower Land",
        "weimar": "Kommunalservice Weimar",
    ]

    public var displayName: String { Self.names[serviceKey] ?? kind.displayName }

    private var unknownService: ProviderError {
        .invalidSelection(L10n.t("Unbekannter Betreiber: \(serviceKey)", "Unknown operator: \(serviceKey)"))
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "hws": return try await hwsStep(selections)
        case "jena": return try await jenaStep(selections)
        case "nordhausen": return try await nordhausenStep(selections)
        case "uhk": return try await uhkStep(selections)
        case "awvot": return try await awvStep(selections)
        case "kyffhaeuser": return try await kyffhaeuserStep(selections)
        case "sonneberg": return try await sonnebergStep(selections)
        case "ajl": return try await ajlStep(selections)
        case "weimar": return try await weimarStep(selections)
        default: throw unknownService
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard !selections.isEmpty else { throw ProviderError.selectAddressFirst }
        let result: [Pickup]
        switch serviceKey {
        case "hws": result = try await hwsPickups(selections, calendar: calendar)
        case "jena": result = try await jenaPickups(selections, calendar: calendar)
        case "nordhausen": result = try await nordhausenPickups(selections, calendar: calendar)
        case "uhk": result = try await uhkPickups(selections, calendar: calendar)
        case "awvot": result = try await awvPickups(selections, calendar: calendar)
        case "kyffhaeuser": result = try await kyffhaeuserPickups(selections, calendar: calendar)
        case "sonneberg": result = try await sonnebergPickups(selections, calendar: calendar)
        case "ajl": result = try await ajlPickups(selections, calendar: calendar)
        case "weimar": result = try await weimarPickups(selections, calendar: calendar)
        default: throw unknownService
        }
        let unique = Array(Set(result.filter { !WasteCategory.isIgnorableTitle($0.name) }))
        guard !unique.isEmpty else { throw ProviderError.noDataGeneric }
        return unique.sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map { $0.title.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func address(_ city: String, _ parts: ArraySlice<String>) -> String {
            guard let street = parts.first else { return city }
            return ([city, ([street] + parts.dropFirst()).joined(separator: " ")]).joined(separator: ", ")
        }
        switch serviceKey {
        case "hws":
            // Gewerbe-Auswahl gehört nicht in die Adresse.
            return address("Halle (Saale)", titles.prefix(2)[...])
        case "jena": return address("Jena", titles[...])
        case "weimar": return address("Weimar", titles.prefix(1)[...])
        case "nordhausen", "awvot":
            guard let city = titles.first else { return "" }
            return address(city, titles.dropFirst())
        default: return titles.joined(separator: ", ")
        }
    }

    // MARK: - Hilfen

    private static func sortedOptions(_ pairs: [(id: String, title: String)]) -> [SelectionOption] {
        var seen = Set<String>()
        return pairs.filter { !$0.title.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { SelectionOption(id: $0.id, title: $0.title) }
    }

    private static func years(_ calendar: Calendar, nextFromMonth: Int = 1) -> [Int] {
        let now = Date()
        let year = calendar.component(.year, from: now)
        return calendar.component(.month, from: now) >= nextFromMonth ? [year, year + 1] : [year]
    }

    /// ICS-Text → Termine; `split` trennt Sammeltermine („Restmüll, Papier“) auf.
    private static func icsPickups(_ text: String, calendar: Calendar, split: String? = nil, rename: (String) -> String? = { $0 }) -> [Pickup] {
        ICS.parse(text, calendar: calendar).flatMap { event -> [Pickup] in
            let parts = split.map { event.summary.components(separatedBy: $0) } ?? [event.summary]
            return parts.compactMap { part in
                guard let name = rename(part.trimmingCharacters(in: .whitespaces)) else { return nil }
                return Pickup(date: event.date, name: NameCleaner.clean(name))
            }
        }
    }

    /// Optionen eines `<select>`-Fragments ohne umschließendes Element (AJAX-Antworten).
    private static func fragmentOptions(_ html: String) -> [(value: String, label: String)] {
        HTMLText.options(ofSelect: "fragment", in: #"<select name="fragment">"# + html + "</select>")
    }

    // MARK: - HWS Halle

    private static let hwsBase = "https://hws-halle.de"

    private func hwsStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.hwsBase + "/produkte-dienstleistungen/entsorgung/entsorgungskalender")
            let list = HTMLText.firstMatch(#"<datalist id="street-name-datalist">([\s\S]*?)</datalist>"#, in: html, group: 1) ?? ""
            let streets = HTMLText.matches(#"<option value="([^"]+)""#, in: list).map { HTMLText.decodeEntities($0[0]) }
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets.map { ($0, $0) }))
        case 1:
            let data = try await client.postForm(Self.hwsBase + "/hws_entsorgungskalender_autocomplete_housenumber", fields: [("street", selections[0].id)])
            let numbers: [String] = (try? HTTPClient.decode(data)) ?? []
            guard !numbers.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sortedOptions(numbers.map { ($0, $0) }))
        case 2:
            // Privat/Gewerbe: nur fragen, wenn es an der Adresse Gewerbe-Kalender gibt.
            let data = try await client.postForm(Self.hwsBase + "/hws_entsorgungskalender_autocomplete_customer",
                                                 fields: [("street", selections[0].id), ("number", selections[1].id)])
            let customers: [String] = (try? HTTPClient.decode(data)) ?? []
            guard customers.contains(where: { $0 != "kein Gewerbe" }) else { return nil }
            let options = customers.map { SelectionOption(id: $0 == "kein Gewerbe" ? "" : $0, title: $0 == "kein Gewerbe" ? L10n.t("Privathaushalt", "Private household") : $0) }
            return SelectionStep(title: L10n.t("Gewerbe", "Business"), options: options, searchable: false)
        default:
            return nil
        }
    }

    private func hwsPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let customer = selections.count > 2 ? selections[2].id : ""
        var result: [Pickup] = []
        for year in Self.years(calendar) {
            let url = Self.hwsBase + "/entsorgungskalender_ics?streetName=\(HTTPClient.query(selections[0].id))&houseNumber=\(HTTPClient.query(selections[1].id))&customer=\(HTTPClient.query(customer))&year=\(year)"
            // Ohne Daten antwortet das Portal mit einer JSON-Meldung statt ICS.
            guard let text = try? await client.string(url), text.contains("BEGIN:VCALENDAR") else { continue }
            for event in ICS.parse(text, calendar: calendar) {
                // ★ markiert Ersatztermine an Feiertagen.
                let holiday = event.summary.hasPrefix("★")
                let summary = event.summary.replacingOccurrences(of: "★", with: "")
                for part in summary.components(separatedBy: ", ") where !part.isEmpty {
                    result.append(Pickup(date: event.date, name: NameCleaner.clean(part),
                                         note: holiday ? L10n.t("Feiertags-Ersatztermin", "Holiday replacement date") : nil))
                }
            }
        }
        return result
    }

    // MARK: - KSJ Jena

    private static let jenaBase = "https://entsorgungstermine.jena.de"

    private func jenaStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.jenaBase + "/getMainSelectMenus?lang=de")
            let streets = HTMLText.options(ofSelect: "comboboxStreet", in: html).map { ($0.value, $0.label) }
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets))
        case 1:
            let html = try await client.string(Self.jenaBase + "/getMainSelectMenus?lang=de&street=\(HTTPClient.query(selections[0].id))")
            // Der erste Eintrag „Hausnummer“ ist nur Platzhalter.
            let numbers = HTMLText.options(ofSelect: "hnummer", in: html).filter { $0.label != "Hausnummer" }.map { ($0.value, $0.label) }
            guard !numbers.isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sortedOptions(numbers))
        default:
            return nil
        }
    }

    private func jenaPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let number = selections.count > 1 ? selections[1].id : ""
        let text = try await client.string(Self.jenaBase + "/makeICSAll?x=true&street=\(HTTPClient.query(selections[0].id))&hnummer=\(HTTPClient.query(number))")
        // „Restabfall4R“ → „Restabfall“ (Rhythmus-Kürzel abschneiden)
        return Self.icsPickups(text, calendar: calendar) { $0.replacingOccurrences(of: #"\d+[A-Z]?$"#, with: "", options: .regularExpression) }
    }

    // MARK: - Landkreis Nordhausen

    private struct NordhausenAddress: Decodable {
        let id: Int
        let location: String?
        let street: String?
        let houseNumbers: String?
    }

    private static let nordhausenBase = "https://abfallportal-nordhausen.de/api/public"

    private func nordhausenStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        // Einzelne Einträge ohne Ort/Straße auslassen.
        let all: [NordhausenAddress] = try await client.json(Self.nordhausenBase + "/addresses")
        let trim = { (s: String?) in (s ?? "").trimmingCharacters(in: .whitespaces) }
        switch selections.count {
        case 0:
            let places = all.map { (trim($0.location), trim($0.location)) }.filter { !$0.0.isEmpty }
            guard !places.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(places))
        case 1:
            let inPlace = all.filter { trim($0.location) == selections[0].id && !trim($0.street).isEmpty }
            let groups = Dictionary(grouping: inPlace) { trim($0.street) }
            // Eindeutige Straße → gleich die Adress-ID, sonst folgt die Hausnummer.
            let options = groups.map { street, entries in (entries.count == 1 ? String(entries[0].id) : "s:" + street, street) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 2 where selections[1].id.hasPrefix("s:"):
            let street = String(selections[1].id.dropFirst(2))
            let entries = all.filter { trim($0.location) == selections[0].id && trim($0.street) == street }
            let options = entries.map { entry -> (String, String) in
                let number = trim(entry.houseNumbers)
                return (String(entry.id), number.isEmpty ? L10n.t("übrige Hausnummern", "other numbers") : number)
            }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func nordhausenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let id = selections.last?.id, Int(id) != nil else { throw ProviderError.selectAddressFirst }
        let text = try await client.string(Self.nordhausenBase + "/calendar/ics?addressid=\(id)")
        return Self.icsPickups(text, calendar: calendar) { name in
            // Reinigungstermine der Biotonne sind keine Abholung.
            if name.contains("gereinigt") { return nil }
            return name.replacingOccurrences(of: #"\s+(wird|werden) abgeholt$"#, with: "", options: .regularExpression)
        }
    }

    // MARK: - Unstrut-Hainich-Kreis

    private static let uhkSite = "https://www.abfallwirtschaft-uhk.de"
    private static let uhkICS = "https://awb-ics.unstrut-hainich-kreis.de/icalendar"

    /// Die Übersichtsseite heißt je Jahr anders; der Link steht im Menü der Startseite.
    private func uhkOverview() async throws -> String {
        let year = Calendar.current.component(.year, from: Date())
        var paths = ["/tourenpl%C3%A4ne-als-icalendar-f%C3%BCr-das-jahr-\(year)"]
        if let home = try? await client.string(Self.uhkSite + "/") {
            let found = HTMLText.matches(#"href="(/tourenpl[^"]*icalendar[^"]*?(\d{4}))""#, in: home)
                .sorted { $0[1] > $1[1] }
                .compactMap { $0[0].removingPercentEncoding?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
            paths = found + paths
        }
        for path in paths {
            if let html = try? await client.string(Self.uhkSite + path), html.contains("awb-ics.") { return html }
        }
        throw ProviderError.noDataGeneric
    }

    private func uhkStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let html = try await uhkOverview()
        let places = HTMLText.matches(#"<a[^>]*href="https?://awb-ics\.unstrut-hainich-kreis\.de/icalendar/\d{4}/([^"/]+)\.ics"[^>]*>([\s\S]*?)</a>"#, in: html)
            .map { ($0[0], HTMLText.decodeEntities(HTMLText.stripTags($0[1])).trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard !places.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: L10n.t("Ort / Stadttour", "Town / tour"), options: Self.sortedOptions(places))
    }

    private func uhkPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let file = selections.first?.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw ProviderError.selectAddressFirst }
        var result: [Pickup] = []
        for year in Self.years(calendar) {
            guard let text = try? await client.string("\(Self.uhkICS)/\(year)/\(file).ics") else { continue }
            // „gelber Behälter, Bioabfallbehälter“ → zwei Termine
            result += Self.icsPickups(text, calendar: calendar, split: ",") { name in
                name.isEmpty ? nil : name.prefix(1).uppercased() + name.dropFirst()
            }
        }
        return result
    }

    // MARK: - AWV Ostthüringen

    private static let awvForm = "https://www.awv-ot.de/tourenauskunft/auskunftbatix.php"
    private static let awvICS = "https://www.awv-ot.de/tourenauskunft/ics/ics.php"

    /// Das Portal erwartet Formulardaten in ISO-8859-1.
    static func latin1Form(_ fields: [(String, String)]) -> Data {
        func encode(_ value: String) -> String {
            var out = ""
            for scalar in value.unicodeScalars {
                if scalar == " " { out += "+"; continue }
                if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) || "-._".unicodeScalars.contains(scalar) {
                    out.unicodeScalars.append(scalar)
                } else if scalar.value < 256 {
                    out += String(format: "%%%02X", scalar.value)
                } else {
                    // Außerhalb von Latin-1 als UTF-8 (kommt im Portal nicht vor).
                    for byte in String(scalar).utf8 { out += String(format: "%%%02X", byte) }
                }
            }
            return out
        }
        return Data(fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&").utf8)
    }

    private func awvPost(_ fields: [(String, String)]) async throws -> String {
        let data = try await client.post(Self.awvForm, body: Self.latin1Form(fields), contentType: "application/x-www-form-urlencoded")
        return HTTPClient.text(from: data)
    }

    /// Die Auswahllisten haben keine `value`-Attribute; der Text ist der Wert.
    private static func awvOptions(_ html: String, select: String) -> [String] {
        guard let block = HTMLText.firstMatch(#"<select[^>]*name="\#(select)"[^>]*>([\s\S]*?)</select>"#, in: html, group: 1) else { return [] }
        return HTMLText.matches(#"<option[^>]*>([^<]*)</option>"#, in: block).map { HTMLText.decodeEntities($0[0]) }
    }

    private func awvStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let year = String(Calendar.current.component(.year, from: Date()))
        let (title, values): (String, [String])
        switch selections.count {
        case 0:
            let html = HTTPClient.text(from: try await client.get(Self.awvForm))
            (title, values) = (SelectionStep.cityTitle, Self.awvOptions(html, select: "Ort"))
        case 1:
            let html = try await awvPost([("JAHR", year), ("Ort", selections[0].id)])
            (title, values) = (SelectionStep.streetTitle, Self.awvOptions(html, select: "Strasse"))
        case 2:
            let html = try await awvPost([("JAHR", year), ("Ort", selections[0].id), ("Step", "2"), ("Strasse", selections[1].id)])
            (title, values) = (SelectionStep.houseNumberTitle, Self.awvOptions(html, select: "HSN"))
        default:
            return nil
        }
        guard !values.isEmpty else { throw ProviderError.noDataGeneric }
        // Werte unverändert (teils mit Leerzeichen am Ende) als ID behalten.
        let options = values.map { ($0, $0.trimmingCharacters(in: .whitespaces)) }
        return SelectionStep(title: title, options: selections.count == 2 ? Self.sortedOptions(options) : options.map { SelectionOption(id: $0.0, title: $0.1) })
    }

    private func awvPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        var result: [Pickup] = []
        for year in Self.years(calendar, nextFromMonth: 11) {
            let fields = [("JAHR", String(year)), ("Ort", selections[0].id), ("Step", "3"), ("Strasse", selections[1].id), ("HSN", selections[2].id)]
            // Die Auswahl liegt in der PHP-Sitzung; das ICS gibt es nur mit deren Cookie.
            guard let text = try? await AWVSession().calendar(form: Self.awvForm, ics: Self.awvICS, body: Self.latin1Form(fields)) else { continue }
            result += Self.icsPickups(text, calendar: calendar) { $0.replacingOccurrences(of: #"^Leerung\s+"#, with: "", options: .regularExpression) }
        }
        return result
    }

    /// Eigene Sitzung mit Cookie-Weitergabe von Hand (zuverlässig auch unter Linux).
    private struct AWVSession {
        /// Gemeinsame Sitzung ohne Cookie-Speicher (keine neue URLSession je Abruf)
        var session: URLSession { HTTPClient.defaultSession }

        func calendar(form: String, ics: String, body: Data) async throws -> String {
            guard let formURL = URL(string: form), let icsURL = URL(string: ics) else { throw HTTPError.badURL(form) }
            var post = URLRequest(url: formURL)
            post.httpMethod = "POST"
            post.httpBody = body
            post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            post.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
            let (_, response) = try await session.data(for: post)
            let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie") ?? ""
            guard let cookie = HTMLText.firstMatch(#"(PHPSESSID=[^;,\s]+)"#, in: header, group: 1) else { throw ProviderError.noDataGeneric }
            var get = URLRequest(url: icsURL)
            get.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
            get.setValue(cookie, forHTTPHeaderField: "Cookie")
            let (data, _) = try await session.data(for: get)
            return HTTPClient.text(from: data)
        }
    }

    // MARK: - Kyffhäuserkreis

    private static let kyffBase = "https://abfall-kyffhaeuser.de"

    /// Roßleben ist doppelt angelegt: Gelbe Tonne an neuen Orten, die übrigen Tonnen an alten.
    /// Beide werden zu einer Auswahl zusammengefasst (alte ID → zugehörige neue ID).
    static let kyffMerge: [String: String] = ["1753": "4984", "1755": "4986", "1756": "4986"]

    private struct KyffEvents: Decodable {
        struct Event: Decodable { let title: String; let start_date: String }
        let events: [Event]?
        let total_pages: Int?
    }

    private func kyffhaeuserStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        // Die Ortsliste des Filters enthält nur echte Abfuhrorte (die API kennt auch Straßen-Orte ohne Termine).
        let html = try await client.string(Self.kyffBase + "/kalender/")
        let segment = html.range(of: #""tribe_venues[]","options":["#).map { String(html[$0.upperBound...].prefix(40_000)) } ?? ""
        var venues: [(id: String, title: String)] = HTMLText.matches(#"\{"text":"((?:[^"\\]|\\.)*)","id":"(\d+)""#, in: segment).map { groups in
            let text = (try? JSONDecoder().decode(String.self, from: Data("\"\(groups[0])\"".utf8))) ?? groups[0]
            return (groups[1], HTMLText.decodeEntities(text).replacingOccurrences(of: "–", with: "-"))
        }
        guard !venues.isEmpty else { throw ProviderError.noDataGeneric }
        let present = Set(venues.map(\.id))
        let absorbed = Set(Self.kyffMerge.filter { present.contains($0.key) }.values)
        venues = venues.filter { !absorbed.contains($0.id) }.map { venue in
            guard let partner = Self.kyffMerge[venue.id], present.contains(partner) else { return venue }
            return (venue.id + "," + partner, venue.title)
        }
        return SelectionStep(title: L10n.t("Ort / Tour", "Town / tour"), options: Self.sortedOptions(venues))
    }

    private func kyffhaeuserPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let ids = selections.first?.id.split(separator: ",") else { throw ProviderError.selectAddressFirst }
        let start = Days.today(calendar: calendar)
        let range = "start_date=\(Days.iso(start, calendar: calendar))&end_date=\(Days.iso(Days.add(400, to: start, calendar: calendar), calendar: calendar))"
        var result: [Pickup] = []
        for id in ids {
            var page = 1
            while page <= 20 {
                let response: KyffEvents = try await client.json(Self.kyffBase + "/wp-json/tribe/events/v1/events?venue=\(id)&\(range)&per_page=50&page=\(page)")
                for event in response.events ?? [] {
                    guard let date = Days.parse(String(event.start_date.prefix(10)), calendar: calendar) else { continue }
                    result.append(Pickup(date: date, name: NameCleaner.clean(HTMLText.decodeEntities(event.title))))
                }
                if page >= (response.total_pages ?? 1) { break }
                page += 1
            }
        }
        return result
    }

    // MARK: - Landkreis Sonneberg

    private static let sonBase = "https://www.abfallwirtschaft-sonneberg.de"

    private func sonnebergStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let (title, options): (String, [(value: String, label: String)])
        switch selections.count {
        case 0:
            let html = try await client.string(Self.sonBase + "/abfallkalender/")
            (title, options) = (SelectionStep.cityTitle, HTMLText.options(ofSelect: "ort", in: html))
        case 1:
            let html = HTTPClient.text(from: try await client.postForm(Self.sonBase + "/ajax_stadtteil.php", fields: [("ort", selections[0].id)]))
            (title, options) = (SelectionStep.districtTitle, Self.fragmentOptions(html))
        case 2:
            let html = HTTPClient.text(from: try await client.postForm(Self.sonBase + "/ajax_strasse.php", fields: [("stadtteil", selections[1].id)]))
            (title, options) = (SelectionStep.streetTitle, Self.fragmentOptions(html))
        default:
            return nil
        }
        let list = Self.sortedOptions(options.filter { !$0.value.isEmpty }.map { ($0.value, $0.label) })
        // Nur manche Ortsteile sind nach Straßen unterteilt.
        if list.isEmpty { if selections.count == 2 { return nil }; throw ProviderError.noDataGeneric }
        return SelectionStep(title: title, options: list)
    }

    private func sonnebergPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let fields = [("ort", selections[0].id), ("stadtteil", selections[1].id), ("strasse", selections.count > 2 ? selections[2].id : "")]
        var result: [Pickup] = []
        for year in Self.years(calendar) {
            guard let data = try? await client.postForm(Self.sonBase + "/PHPtoICS\(year).php", fields: fields) else { continue }
            result += Self.icsPickups(HTTPClient.text(from: data), calendar: calendar)
        }
        return result
    }

    // MARK: - AJL Jerichower Land

    private static let ajlBase = "https://www.ajl-mbh.de/abfallkalender/entsorgungstermine"

    private func ajlStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let year = Calendar.current.component(.year, from: Date())
        switch selections.count {
        case 0:
            let html = try await client.string(Self.ajlBase)
            let towns = HTMLText.matches(#"<a[^>]*class="[^"]*stadtbutton[^"]*"[^>]*>"#, in: html, wholeMatch: true).compactMap { tag -> (String, String)? in
                guard let id = HTMLText.firstMatch(#"town=(\d+)"#, in: tag[0], group: 1),
                      let name = HTMLText.firstMatch(#"name="([^"]*)""#, in: tag[0], group: 1) else { return nil }
                return (id, HTMLText.decodeEntities(name).trimmingCharacters(in: .whitespaces))
            }
            guard !towns.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(towns))
        case 1:
            let html = try await client.string("\(Self.ajlBase)?year=\(year)&town=\(selections[0].id)")
            // Orte mit nur einem Abholbereich zeigen gleich den Kalender.
            let streets = HTMLText.options(ofSelect: "street", in: html).filter { $0.value != "-1" && !$0.value.isEmpty }.map { ($0.value, $0.label) }
            guard !streets.isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets))
        default:
            return nil
        }
    }

    private func ajlPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        var result: [Pickup] = []
        for year in Self.years(calendar, nextFromMonth: 11) {
            var url = "\(Self.ajlBase)?year=\(year)&town=\(selections[0].id)"
            if selections.count > 1 { url += "&street=\(selections[1].id)" }
            guard let html = try? await client.string(url) else { continue }
            result += Self.ajlParse(html, fallbackYear: year, calendar: calendar)
        }
        return result
    }

    /// Kalenderseite: je Abfallart ein `div.cat` mit `h3` und Tagen „Mo 19.01.“; das Jahr steht in der Überschrift.
    static func ajlParse(_ html: String, fallbackYear: Int, calendar: Calendar) -> [Pickup] {
        guard let start = html.range(of: #"id="calenderview""#) else { return [] }
        let view = String(html[start.upperBound...])
        let heading = HTMLText.firstMatch(#"<h2[^>]*>[^<]*?(\d{4})"#, in: view, group: 1)
        let year = heading.flatMap(Int.init) ?? fallbackYear
        var result: [Pickup] = []
        for chunk in view.components(separatedBy: #"<div class="cat">"#).dropFirst() {
            guard let title = HTMLText.firstMatch(#"<h3[^>]*>([\s\S]*?)</h3>"#, in: chunk, group: 1) else { continue }
            let name = NameCleaner.clean(HTMLText.decodeEntities(HTMLText.stripTags(title)))
            for day in HTMLText.matches(#"class="dayprint">[^<]*?(\d{1,2})\.(\d{1,2})\."#, in: chunk) {
                guard let d = Int(day[0]), let m = Int(day[1]), let date = Days.make(year: year, month: m, day: d, calendar: calendar) else { continue }
                result.append(Pickup(date: date, name: name))
            }
        }
        return result
    }

    // MARK: - KS Weimar (Entsorgungsplan)

    static let weimarURL = "https://ks-weimar.de/entsorgung/entsorgungsplan-fuer-abfallbehaelter/"

    /// Eine Zeile des Entsorgungsplans: Tag der Zweirad-Tonnen und – falls vorhanden – Tag der 1100-l-Restmüllbehälter.
    struct WeimarStreet: Equatable {
        let name: String
        let regular: String
        let large: String
    }

    /// Tabellenzeilen „Nr. | Straße | Entsorgungstag Zweirad | Entsorgungstag Vierrad 1100 l“.
    static func weimarPlan(_ html: String) -> [WeimarStreet] {
        HTMLText.matches(#"<tr[^>]*>([\s\S]*?)</tr>"#, in: html).compactMap { row in
            let cells = HTMLText.matches(#"<td[^>]*>([\s\S]*?)</td>"#, in: row[0]).map {
                HTMLText.decodeEntities(HTMLText.stripTags($0[0]))
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            guard cells.count >= 4, !cells[1].isEmpty else { return nil }
            return WeimarStreet(name: cells[1], regular: cells[2], large: cells[3])
        }
    }

    /// „Mittwoch ungerade Kalenderwoche“, „Montag gerade und ungerade Kalenderwoche“ oder Kürzel wie „Fr uKw“
    /// → Wochentag (1 = Sonntag) und Parität der ISO-Kalenderwoche (nil = jede Woche).
    /// `weekly`: Spalte der 1100-l-Behälter, die laut Kopfzeile wöchentlich geleert werden.
    static func weimarRule(_ text: String, weekly: Bool = false) -> (weekday: Int, parity: Int?)? {
        let words = text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let days = ["mo": 2, "di": 3, "mi": 4, "do": 5, "fr": 6, "sa": 7]
        guard let first = words.first, let weekday = days[String(first.prefix(2))] else { return nil }
        if weekly { return (weekday, nil) }
        let odd = words.contains { ["ungerade", "ukw", "ugkw"].contains($0) }
        let even = words.contains { ["gerade", "gkw"].contains($0) }
        switch (odd, even) {
        case (true, true): return (weekday, nil)
        case (true, false): return (weekday, 1)
        case (false, true): return (weekday, 0)
        default: return nil
        }
    }

    static func weimarDates(weekday: Int, parity: Int?, from: Date, to: Date, calendar: Calendar) -> [Date] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        var dates: [Date] = []
        var day = calendar.startOfDay(for: from)
        while day <= to {
            if calendar.component(.weekday, from: day) == weekday,
               parity.map({ iso.component(.weekOfYear, from: day) % 2 == $0 }) ?? true {
                dates.append(day)
            }
            day = Days.add(1, to: day, calendar: calendar)
        }
        return dates
    }

    private static func weimarNote(_ rule: (weekday: Int, parity: Int?)) -> String {
        let de = ["", "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"][rule.weekday]
        let en = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][rule.weekday]
        switch rule.parity {
        case nil: return L10n.t("Jeden \(de)", "Every \(en)")
        case 1: return L10n.t("\(de) in ungeraden Kalenderwochen", "\(en) in odd calendar weeks")
        default: return L10n.t("\(de) in geraden Kalenderwochen", "\(en) in even calendar weeks")
        }
    }

    /// Rest-, Bio-, Papier- und gelbe Tonne am Tag der Zweirad-Spalte (14-täglich laut Abfallsatzung § 28 Abs. 2,
    /// Biotonne „alle 2 Wochen“, gelbe Tonne laut KS Weimar am selben Tag). Mit `large` kommt Restmüll stattdessen
    /// wöchentlich aus der 1100-l-Spalte. Feiertagsverschiebungen gibt der KS Weimar nur einzeln bekannt – sie fehlen hier.
    static func weimarPickups(_ street: WeimarStreet, large: Bool, from: Date? = nil, calendar: Calendar) -> [Pickup] {
        let start = from ?? Days.today(calendar: calendar)
        let end = Days.add(365, to: start, calendar: calendar)
        var result: [Pickup] = []
        func add(_ names: [String], _ rule: (weekday: Int, parity: Int?)?) {
            guard let rule else { return }
            let note = weimarNote(rule)
            for date in weimarDates(weekday: rule.weekday, parity: rule.parity, from: start, to: end, calendar: calendar) {
                result += names.map { Pickup(date: date, name: $0, note: note) }
            }
        }
        let largeRule = large ? weimarRule(street.large, weekly: true) : nil
        add((largeRule == nil ? ["Restmüll"] : []) + ["Biotonne", "Papier", "Gelbe Tonne"], weimarRule(street.regular))
        add(["Restmüll"], largeRule)
        return result
    }

    private var weimarGone: ProviderError {
        .invalidSelection(L10n.t("Die Straße steht nicht mehr im Entsorgungsplan.", "The street is no longer listed in the collection plan."))
    }

    /// Tabelle bei jedem Schritt frisch laden, damit Änderungen des KS Weimar ankommen.
    private func weimarStreets() async throws -> [WeimarStreet] {
        let streets = Self.weimarPlan(try await client.string(Self.weimarURL)).filter { Self.weimarRule($0.regular) != nil }
        guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
        return streets
    }

    private func weimarStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let streets = try await weimarStreets()
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets.map { ($0.name, $0.name) }))
        case 1:
            guard let street = try await weimarStreets().first(where: { $0.name == selections[0].id }) else { throw weimarGone }
            guard Self.weimarRule(street.large, weekly: true) != nil else { return nil }
            return SelectionStep(title: L10n.t("Restmüllbehälter", "Residual waste bin"), options: [
                SelectionOption(id: "zweirad", title: L10n.t("Tonne bis 240 l", "Bin up to 240 l")),
                SelectionOption(id: "1100", title: L10n.t("1100-l-Behälter, wöchentliche Leerung", "1100 l container, emptied weekly")),
            ], searchable: false)
        default:
            return nil
        }
    }

    private func weimarPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = try await weimarStreets().first(where: { $0.name == selections[0].id }) else { throw weimarGone }
        return Self.weimarPickups(street, large: selections.count > 1 && selections[1].id == "1100", calendar: calendar)
    }
}
