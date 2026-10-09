import Foundation

/// Portale von Entsorgern in Rheinland-Pfalz. Ein Provider für mehrere Betreiber, unterschieden über `serviceKey`:
/// - `art`: A.R.T. Region Trier (Strapi-API: Ortsliste und Termine je Schlüssel)
/// - `rheinlahn`: Rhein-Lahn-Kreis (Ort/Straße als HTML-Auswahl, ICS-Export je Jahr)
/// - `kaw`: KAW Mainz-Bingen (JSON-API, Termine je Ort)
/// - `birkenfeld`: AWB Birkenfeld (alle Daten als JS-Tabellen in einer Seite)
/// - `kusel`: Landkreis Kusel (Ortsauswahl + ICS)
/// - `kreuznach`: AWB Bad Kreuznach (blupassion-REST, Turnus + Feiertagsverlegungen)
/// - `germersheim`: AW Germersheim (Contao-Formular, ICS per POST)
/// - `speyer`: Stadtwerke Speyer (GIPS, ICS je Abfallgebiet)
/// - `worms`: ebwo Worms (ICS je Straße und Jahr)
/// - `koblenz`: Servicebetrieb Koblenz (ICS je Stadtteil, nur Wertstoffe/Grünschnitt/Schadstoffe)
/// - `donnersberg`: Abfall-App Donnersbergkreis (Softwareentwicklung Roth; Ort/Straße als HTML-Liste, ICS je Jahr)
public struct RheinlandPfalzPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsRP
    public let serviceKey: String
    private let client: HTTPClient
    /// Stichtag für `donnersberg` (Jahr im ICS-Pfad); nil = jetzt. Nur für Tests.
    var referenceDate: Date?

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public var displayName: String {
        switch serviceKey {
        case "art": return "A.R.T. Trier"
        case "rheinlahn": return "Rhein-Lahn-Kreis"
        case "kaw": return "KAW Mainz-Bingen"
        case "birkenfeld": return "AWB Birkenfeld"
        case "kusel": return "Landkreis Kusel"
        case "kreuznach": return "AWB Bad Kreuznach"
        case "germersheim": return "AW Germersheim"
        case "speyer": return "Stadtwerke Speyer"
        case "worms": return "ebwo Worms"
        case "koblenz": return "Servicebetrieb Koblenz"
        case "donnersberg": return "Donnersbergkreis"
        default: return kind.displayName
        }
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "art": return try await artStep(selections)
        case "rheinlahn": return try await rheinLahnStep(selections)
        case "kaw": return try await kawStep(selections)
        case "birkenfeld": return try await birkenfeldStep(selections)
        case "kusel": return try await kuselStep(selections)
        case "kreuznach": return try await kreuznachStep(selections)
        case "germersheim": return try await germersheimStep(selections)
        case "speyer": return try await speyerStep(selections)
        case "worms": return try await wormsStep(selections)
        case "koblenz": return try await koblenzStep(selections)
        case "donnersberg": return try await donnersbergStep(selections)
        default: throw unknownService
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard !selections.isEmpty else { throw ProviderError.selectAddressFirst }
        let result: [Pickup]
        switch serviceKey {
        case "art": result = try await artPickups(selections, calendar: calendar)
        case "rheinlahn": result = try await rheinLahnPickups(selections, calendar: calendar)
        case "kaw": result = try await kawPickups(selections, calendar: calendar)
        case "birkenfeld": result = try await birkenfeldPickups(selections, calendar: calendar)
        case "kusel": result = try await kuselPickups(selections, calendar: calendar)
        case "kreuznach": result = try await kreuznachPickups(selections, calendar: calendar)
        case "germersheim": result = try await germersheimPickups(selections, calendar: calendar)
        case "speyer": result = try await speyerPickups(selections, calendar: calendar)
        case "worms": result = try await wormsPickups(selections, calendar: calendar)
        case "koblenz": result = try await koblenzPickups(selections, calendar: calendar)
        case "donnersberg": result = try await donnersbergPickups(selections, calendar: calendar)
        default: throw unknownService
        }
        let unique = Array(Set(result)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
        guard !unique.isEmpty else { throw ProviderError.noDataGeneric }
        return unique
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map(\.title).filter { !$0.isEmpty }
        switch serviceKey {
        case "art", "kaw":
            // Erste Ebene ist Verbandsgemeinde/Bezirk – im Label überflüssig.
            return titles.dropFirst().joined(separator: ", ")
        case "kreuznach":
            var parts: [String] = []
            for option in selections {
                if option.id.hasPrefix("h:"), let last = parts.popLast() {
                    parts.append("\(last) \(option.title)")
                } else {
                    parts.append(option.title)
                }
            }
            return parts.joined(separator: ", ")
        case "speyer": return (["Speyer"] + titles).joined(separator: ", ")
        case "worms": return (["Worms"] + titles).joined(separator: ", ")
        case "koblenz": return (["Koblenz"] + titles).joined(separator: ", ")
        default: return titles.joined(separator: ", ")
        }
    }

    // MARK: - Gemeinsame Hilfen

    private var unknownService: ProviderError {
        .notSupported(L10n.t("Unbekannter Entsorger.", "Unknown operator."))
    }

    private static var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }

    private func thisYear(_ calendar: Calendar) -> Int { calendar.component(.year, from: Date()) }

    private static func sortedOptions(_ options: [SelectionOption]) -> [SelectionOption] {
        options.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// ICS-Text → Termine; `rename` liefert je SUMMARY einen oder mehrere Fraktionsnamen (leer = verwerfen).
    private static func icsPickups(_ text: String, calendar: Calendar, rename: (String) -> [String] = { [$0] }) -> [Pickup] {
        ICS.parse(text, calendar: calendar).flatMap { event in
            rename(event.summary).compactMap { raw -> Pickup? in
                guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return Pickup(date: event.date, name: NameCleaner.clean(raw))
            }
        }
    }

    /// Tagesdatum in Berliner Zeit aus Millisekunden seit 1970 → „yyyy-MM-dd“.
    private static func isoDay(millis: Double) -> String {
        let parts = berlin.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: millis / 1000))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func isoDay(_ date: Date) -> String {
        let parts = berlin.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - A.R.T. Trier

    private struct ARTEntry: Decodable {
        let plz: String?
        let ort: String
        let strasse: String?
        let ortsteil: String?
        let verbandsgemeinde: String?
        let key: String
    }

    private struct ARTResponse: Decodable { let data: [ARTEntry] }

    private struct ARTDates: Decodable {
        struct Kind: Decodable { struct Attributes: Decodable { let titel: String }; let attributes: Attributes }
        struct Kinds: Decodable { let data: [Kind]? }
        struct Attributes: Decodable { let datum: String; let feiertagLabel: String?; let abfallarten: Kinds? }
        struct Entry: Decodable { let attributes: Attributes }
        let data: [Entry]
    }

    private func artEntries() async throws -> [ARTEntry] {
        let response: ARTResponse = try await client.json("https://redaktion.art-trier.de/api/abfuhrtermine/search?pagination%5BpageSize%5D=5000")
        guard !response.data.isEmpty else { throw ProviderError.noDataGeneric }
        return response.data
    }

    private func artStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let groups = Set(try await artEntries().compactMap(\.verbandsgemeinde))
            return SelectionStep(title: L10n.t("Verbandsgemeinde / Stadt", "Municipality"),
                                 options: Self.sortedOptions(groups.map { SelectionOption(id: $0, title: $0) }))
        case 1:
            let entries = try await artEntries().filter { $0.verbandsgemeinde == selections[0].id }
            var places: [String: Set<String>] = [:]
            for entry in entries { places[entry.ort, default: []].insert(entry.plz ?? "") }
            guard !places.isEmpty else { throw ProviderError.invalidSelection(L10n.t("Keine Orte gefunden.", "No towns found.")) }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(places.map { ort, zips in
                SelectionOption(id: ort, title: ort, subtitle: zips.filter { !$0.isEmpty }.sorted().joined(separator: ", "))
            }))
        case 2:
            let entries = try await artEntries().filter { $0.verbandsgemeinde == selections[0].id && $0.ort == selections[1].id }
            guard entries.count > 1 else { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(entries.map { entry in
                let title = entry.strasse ?? entry.ortsteil ?? L10n.t("Übrige Straßen", "Other streets")
                let subtitle = entry.strasse != nil && entry.ortsteil != nil && entry.ortsteil != entry.ort ? entry.ortsteil : nil
                return SelectionOption(id: entry.key, title: title, subtitle: subtitle)
            }))
        default:
            return nil
        }
    }

    private func artPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let key: String
        if selections.count >= 3 {
            key = selections[2].id
        } else {
            guard selections.count == 2 else { throw ProviderError.selectAddressFirst }
            let entries = try await artEntries().filter { $0.verbandsgemeinde == selections[0].id && $0.ort == selections[1].id }
            guard let only = entries.first, entries.count == 1 else { throw ProviderError.selectAddressFirst }
            key = only.key
        }
        // Termine als JSON (der ICS-Feed schickt Umlaute im Header, daran scheitert FoundationNetworking).
        let url = "https://redaktion.art-trier.de/api/abfuhrtermine?filters%5Bkey%5D%5B%24eq%5D=\(HTTPClient.query(key))"
            + "&filters%5Bdatum%5D%5B%24gte%5D=\(Self.isoDay(Date()))&populate%5Babfallarten%5D=%2A"
            + "&sort%5B0%5D=datum%3Aasc&pagination%5BpageSize%5D=200"
        let response: ARTDates = try await client.json(url)
        return response.data.flatMap { entry -> [Pickup] in
            guard let date = Days.parse(entry.attributes.datum, calendar: calendar) else { return [] }
            let note = entry.attributes.feiertagLabel?.trimmingCharacters(in: .whitespaces)
            return (entry.attributes.abfallarten?.data ?? []).map {
                Pickup(date: date, name: NameCleaner.clean($0.attributes.titel), note: note?.isEmpty == false ? note : nil)
            }
        }
    }

    // MARK: - Rhein-Lahn-Kreis

    private static let rheinLahnBase = "https://www.rhein-lahn-kreis-abfallwirtschaft.de"

    private func rheinLahnStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string("\(Self.rheinLahnBase)/html/cs_6615.html")
            let places = HTMLText.options(ofSelect: "gemeinde", in: html).filter { !$0.value.isEmpty }
            guard !places.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(places.map { SelectionOption(id: $0.value, title: $0.label) }))
        case 1:
            let html = try await client.string("\(Self.rheinLahnBase)/html/cs_6615.html?gemeinde=\(HTTPClient.query(selections[0].id))")
            let streets = HTMLText.options(ofSelect: "strasse", in: html).filter { !$0.value.isEmpty }
            guard !streets.isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets.map { SelectionOption(id: $0.value, title: $0.label) }))
        default:
            return nil
        }
    }

    private func rheinLahnPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let place = HTTPClient.query(selections[0].id)
        let street = selections.count > 1 ? HTTPClient.query(selections[1].id) : ""
        var pickups: [Pickup] = []
        for year in [thisYear(calendar), thisYear(calendar) + 1] {
            let url = "\(Self.rheinLahnBase)/abfuhr_export.php?cs=6615&file=ics&gemeinde=\(place)&strasse=\(street)&jahr=\(year)"
            guard let text = try? await client.string(url) else { continue }
            pickups += Self.icsPickups(text, calendar: calendar)
        }
        return pickups
    }

    // MARK: - KAW Mainz-Bingen

    private static let kawAPI = "https://abfallkalender-api-lk.kaw-mainz-bingen.de/public/frontend"

    private struct KAWItem: Decodable {
        let id: Int
        let name: String
        let recordState: Int
        let districtId: Int?
        enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", recordState = "RecordState", districtId = "DistrictId" }
    }

    private struct KAWSettings: Decodable {
        struct Payload: Decodable {
            let districts: [KAWItem]
            let cities: [KAWItem]
            let wasteTypes: [KAWItem]
            enum CodingKeys: String, CodingKey { case districts = "Districts", cities = "Cities", wasteTypes = "WasteTypes" }
        }
        let data: Payload
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private struct KAWDates: Decodable {
        struct Entry: Decodable {
            let date: String
            let wasteTypeName: String
            let location: String?
            enum CodingKeys: String, CodingKey { case date = "Date", wasteTypeName = "WasteTypeName", location = "Location" }
        }
        let dataList: [Entry]?
        enum CodingKeys: String, CodingKey { case dataList = "DataList" }
    }

    private func kawSettings() async throws -> KAWSettings.Payload {
        let settings: KAWSettings = try await client.json("\(Self.kawAPI)/settings?Filter.IncludeStaticObjects=true")
        return settings.data
    }

    private func kawStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let districts = try await kawSettings().districts.filter { $0.id > 0 && $0.recordState == 1 }
            guard !districts.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Stadt / Verbandsgemeinde", "Municipality"),
                                 options: Self.sortedOptions(districts.map { SelectionOption(id: String($0.id), title: $0.name) }))
        case 1:
            let cities = try await kawSettings().cities.filter { $0.id > 0 && $0.recordState == 1 && String($0.districtId ?? -1) == selections[0].id }
            guard !cities.isEmpty else { throw ProviderError.invalidSelection(L10n.t("Keine Orte gefunden.", "No towns found.")) }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(cities.map { SelectionOption(id: String($0.id), title: $0.name) }))
        default:
            return nil
        }
    }

    private func kawPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let types = try await kawSettings().wasteTypes.filter { $0.id > 0 && $0.recordState == 1 }.map { String($0.id) }
        let from = Self.isoDay(Date())
        let url = "\(Self.kawAPI)/collectiondates?Filter.SearchTerm=&Filter.DistrictId=\(selections[0].id)&Filter.CityId=\(selections[1].id)"
            + "&Filter.StreetId=0&Filter.DateFrom=\(from)&Filter.DateTo=\(thisYear(calendar) + 1)-12-31"
            + "&Filter.WasteTypeIds=\(types.joined(separator: "%2C"))&Filter.ShowGroupedResults=false"
            + "&Filter.RecordsPerPage=999999&Filter.CurrentPage=1&Filter.SortColumn=Date"
        let response: KAWDates = try await client.json(url)
        return (response.dataList ?? []).compactMap { entry in
            // „13.10.2026“
            let parts = entry.date.split(separator: ".")
            guard parts.count == 3, let date = Days.parse("\(parts[2])-\(parts[1])-\(parts[0])", calendar: calendar) else { return nil }
            let location = entry.location?.trimmingCharacters(in: .whitespaces)
            return Pickup(date: date, name: NameCleaner.clean(entry.wasteTypeName), note: location?.isEmpty == false ? location : nil)
        }
    }

    // MARK: - AWB Birkenfeld

    /// Alle Tabellen stehen als `var tblX = [...]` in einer (großen) Seite.
    private func birkenfeldTables() async throws -> [String: [[String: String]]] {
        let html = try await client.string("https://www.awb-bir.de/Service/(0)Abfuhrkalender/")
        var tables: [String: [[String: String]]] = [:]
        for name in ["tblStrassen", "tblStrassenGruppen", "tblTermine", "tblMuellarten"] {
            guard let json = HTMLText.firstMatch(#"var \#(name) = (\[[\s\S]*?\]);"#, in: html, group: 1),
                  let rows = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else {
                throw ProviderError.noDataGeneric
            }
            tables[name] = rows.map { row in
                row.compactMapValues { value -> String? in
                    if let string = value as? String { return string }
                    if let number = value as? NSNumber { return number.stringValue }
                    return nil
                }
            }
        }
        return tables
    }

    private func birkenfeldStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let streets = try await birkenfeldTables()["tblStrassen"] ?? []
            var places: [String: SelectionOption] = [:]
            for row in streets {
                guard let id = row["GemeindeId"], let name = row["Gemeinde"] else { continue }
                // Oberstein ist in nummerierte Bezirke geteilt („1“ … „19“).
                let title = name.allSatisfy(\.isNumber) ? "\(row["Verbandsgemeinde"] ?? "") – \(L10n.t("Bezirk", "District")) \(name)" : name
                places[id] = SelectionOption(id: id, title: title, subtitle: row["Verbandsgemeinde"].map { "VG \($0)" })
            }
            guard !places.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(Array(places.values)))
        case 1:
            let streets = (try await birkenfeldTables()["tblStrassen"] ?? []).filter { $0["GemeindeId"] == selections[0].id }
            var options: [String: SelectionOption] = [:]
            for row in streets {
                guard let id = row["StrassenId"], let name = row["Strasse"] else { continue }
                options[id] = SelectionOption(id: id, title: name)
            }
            guard !options.isEmpty else { throw ProviderError.invalidSelection(L10n.t("Keine Straßen gefunden.", "No streets found.")) }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(Array(options.values)))
        default:
            return nil
        }
    }

    private func birkenfeldPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let tables = try await birkenfeldTables()
        let streetID = selections[1].id
        let groups = Set((tables["tblStrassenGruppen"] ?? []).filter { $0["StrassenId"] == streetID }.compactMap { $0["GruppenId"] })
        var names: [String: String] = [:]
        for row in tables["tblMuellarten"] ?? [] { if let id = row["MuellId"], let name = row["Art"] { names[id] = name } }
        return (tables["tblTermine"] ?? []).compactMap { row in
            let inGroup = row["GruppenId"].map { groups.contains($0) } ?? false
            guard inGroup || row["StrassenId"] == streetID,
                  let type = row["Muellart"], let name = names[type],
                  let day = row["Datum"], let date = Days.parse(day, calendar: calendar) else { return nil }
            // Problemabfälle mit Standort und Uhrzeit
            let place = [row["Standort"], row["Uhrzeit"].map { $0.isEmpty ? "" : "\($0) Uhr" }]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return Pickup(date: date, name: NameCleaner.clean(name), note: place.isEmpty ? nil : place)
        }
    }

    // MARK: - Landkreis Kusel

    private static let kuselBase = "https://abfallwirtschaft.landkreis-kusel.de"

    private func kuselStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let html = try await client.string(Self.kuselBase)
        let places = HTMLText.options(ofSelect: "waste_calendar_location", in: html).filter { !$0.value.isEmpty }
        guard !places.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: L10n.t("Ortsgemeinde", "Municipality"), options: Self.sortedOptions(places.map { SelectionOption(id: $0.value, title: $0.label) }))
    }

    private func kuselPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let start = Self.isoDay(Days.add(-7, to: Date()))
        let url = "\(Self.kuselBase)/ical?location=\(HTTPClient.query(selections[0].id))&startDate=\(start)&endDate=\(thisYear(calendar) + 1)-12-31"
        let text = try await client.string(url)
        // „LVP-Abfälle (Gelbe Säcke) ()“ → leere Klammern weg
        return Self.icsPickups(text, calendar: calendar) { summary in
            [summary.replacingOccurrences(of: #"\s*\(\s*\)\s*$"#, with: "", options: .regularExpression)]
        }
    }

    // MARK: - AWB Bad Kreuznach (blupassion)

    private static let kreuznachApp = 44

    private struct KHNode: Decodable { let id: Int; let name: String }

    private struct KHFilter: Decodable {
        struct Payload: Decodable {
            let regions: [KHNode]?
            let citys: [KHNode]?
            let partOfCitys: [KHNode]?
            let streets: [KHNode]?
            let houseNumbers: [KHNode]?
        }
        let data: Payload?
    }

    private struct KHCalendar: Decodable {
        struct Entry: Decodable { let name: String; let fromDate: Double; let toDate: Double?; let frequency: Int? }
        struct Holiday: Decodable { let holiday: Double; let shiftTo: Double }
        struct Payload: Decodable { let calendars: [Entry]?; let holidayViews: [Holiday]? }
        let data: Payload?
    }

    /// Auswahl-IDs tragen ein Präfix: c: Ort, p: Ortsteil, s: Straße, h: Hausnummer.
    private struct KHParams {
        var region: Int?
        var city: Int?
        var part: Int?
        var street: Int?
        var house: Int?

        init(region: Int?, selections: [SelectionOption]) {
            self.region = region
            for option in selections {
                let value = Int(option.id.dropFirst(2))
                switch option.id.prefix(2) {
                case "c:": city = value
                case "p:": part = value
                case "s:": street = value
                case "h:": house = value
                default: break
                }
            }
        }

        var body: [String: Any] {
            func value(_ number: Int?) -> Any { number.map { $0 as Any } ?? NSNull() }
            return ["active": true, "appId": RheinlandPfalzPortalsProvider.kreuznachApp, "hugeDataInfo": "",
                    "regionId": value(region), "cityId": value(city), "streetId": value(street),
                    "partOfCityId": value(part), "districtId": NSNull()]
        }
    }

    private func kreuznachFilter(_ params: KHParams) async throws -> KHFilter.Payload {
        let body = try JSONSerialization.data(withJSONObject: params.body)
        let data = try await client.post("https://blupassionsystem.de/city/rest/garbageregion/filterRegion", body: body,
                                         contentType: "application/json", headers: ["Accept": "application/json"])
        let response: KHFilter = try HTTPClient.decode(data)
        guard let payload = response.data else { throw ProviderError.noDataGeneric }
        return payload
    }

    private func kreuznachRegion() async throws -> Int? {
        try await kreuznachFilter(KHParams(region: nil, selections: [])).regions?.first?.id
    }

    private func kreuznachStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let params = KHParams(region: try await kreuznachRegion(), selections: selections)
        let data = try await kreuznachFilter(params)
        func options(_ nodes: [KHNode]?, prefix: String) -> [SelectionOption] {
            (nodes ?? []).map { SelectionOption(id: "\(prefix)\($0.id)", title: $0.name.trimmingCharacters(in: .whitespaces)) }
        }
        let last = selections.last.map { String($0.id.prefix(2)) }
        switch last {
        case nil:
            let cities = options(data.citys, prefix: "c:")
            guard !cities.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(cities))
        case "c:" where !(data.partOfCitys ?? []).isEmpty:
            return SelectionStep(title: SelectionStep.districtTitle, options: Self.sortedOptions(options(data.partOfCitys, prefix: "p:")))
        case "c:", "p:":
            guard !(data.streets ?? []).isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options(data.streets, prefix: "s:")))
        case "s:":
            let houses = options(data.houseNumbers, prefix: "h:")
            guard !houses.isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sortedOptions(houses))
        default:
            return nil
        }
    }

    private func kreuznachPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let params = KHParams(region: try await kreuznachRegion(), selections: selections)
        let today = Self.berlin.startOfDay(for: Date())
        let from = Days.add(-1, to: today, calendar: Self.berlin)
        let to = Days.add(400, to: today, calendar: Self.berlin)
        var query: [(String, String)] = [("active", "true"), ("appId", String(Self.kreuznachApp)), ("hugeDataInfo", "")]
        if let region = params.region { query.append(("regionId", String(region))) }
        if let city = params.city { query.append(("cityId", String(city))) }
        // Hausnummer ersetzt die Straße (so verlangt es das Portal)
        if let street = params.house ?? params.street { query.append(("streetId", String(street))) }
        if let part = params.part { query.append(("partOfCityId", String(part))) }
        query.append(("fromTime", String(Int64(from.timeIntervalSince1970 * 1000))))
        query.append(("toTime", String(Int64(to.timeIntervalSince1970 * 1000))))
        let url = "https://blupassionsystem.de/city/rest/garbageorte/getAllGarbageCalendar?"
            + query.map { "\($0.0)=\(HTTPClient.query($0.1))" }.joined(separator: "&")
        let data = try await client.get(url, headers: ["Accept": "application/json, text/plain, */*"])
        let response: KHCalendar = try HTTPClient.decode(data)
        guard let payload = response.data else { throw ProviderError.noDataGeneric }

        // Feiertagsverlegungen: je Feiertag ein Ersatztag
        var shifts: [String: String] = [:]
        for holiday in payload.holidayViews ?? [] { shifts[Self.isoDay(millis: holiday.holiday)] = Self.isoDay(millis: holiday.shiftTo) }

        var pickups: [Pickup] = []
        for entry in payload.calendars ?? [] {
            guard let step = entry.frequency, step > 0 else { continue }
            let end = entry.toDate.map { min(Date(timeIntervalSince1970: $0 / 1000), to) } ?? to
            var day = Self.berlin.startOfDay(for: Date(timeIntervalSince1970: entry.fromDate / 1000))
            // bis kurz vor den Zeitraum springen
            let gap = Days.between(day, from, calendar: Self.berlin)
            if gap > step { day = Days.add(gap / step * step, to: day, calendar: Self.berlin) }
            while day <= end {
                if day >= from {
                    let iso = Self.isoDay(day)
                    if let date = Days.parse(shifts[iso] ?? iso, calendar: calendar) {
                        pickups.append(Pickup(date: date, name: NameCleaner.clean(entry.name)))
                    }
                }
                day = Days.add(step, to: day, calendar: Self.berlin)
            }
        }
        return pickups
    }

    // MARK: - AW Germersheim

    private static let germersheimPage = "https://www.abfallwirtschaft-germersheim.de/online-service/abfall-termine/abfalltermine-ics-export-bis-240-liter.html"

    private func germersheimStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.germersheimPage)
            let places = HTMLText.options(ofSelect: "icsortschaft", in: html).filter { !$0.value.isEmpty }
            guard !places.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Ortschaft", "Town"), options: Self.sortedOptions(places.map { SelectionOption(id: $0.value, title: $0.label) }))
        case 1:
            let html = try await client.string("\(Self.germersheimPage)?icsortschaft=\(HTTPClient.query(selections[0].id))")
            let streets = HTMLText.options(ofSelect: "icsstrasse", in: html).filter { !$0.value.isEmpty }
            guard !streets.isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets.map { SelectionOption(id: $0.value, title: $0.label) }))
        default:
            return nil
        }
    }

    private func germersheimPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        var url = "\(Self.germersheimPage)?icsortschaft=\(HTTPClient.query(selections[0].id))"
        if selections.count > 1 { url += "&icsstrasse=\(HTTPClient.query(selections[1].id))" }
        var html = try await client.string(url)
        // Alle Abfallarten ankreuzen – erst dann bietet das Formular den ICS-Download an.
        let types = HTMLText.matches(#"name="icsabfallart\[\]"\s*value="([^"]*)""#, in: html).compactMap(\.first).map(HTMLText.decodeEntities)
        guard !types.isEmpty else { throw ProviderError.noDataGeneric }
        url += types.map { "&icsabfallart%5B%5D=\(HTTPClient.query($0))" }.joined()
        html = try await client.string(url)
        let hidden = HTMLText.hiddenInputs(in: html).filter { $0.name == "ICS_DOWNLOAD" || $0.name == "REQUEST_TOKEN" }
        guard hidden.count == 2 else { throw ProviderError.noDataGeneric }
        let data = try await client.postForm(url, fields: hidden.map { ($0.name, $0.value) })
        return Self.icsPickups(HTTPClient.text(from: data), calendar: calendar)
    }

    // MARK: - Stadtwerke Speyer

    private static let speyerGips = "https://www.stadtwerke-speyer.de/speyerGips/Gips"

    private func speyerStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let html = try await client.string("https://www.stadtwerke-speyer.de/muellkalender")
        // Links „…BezirkId=19&Container.Children:1.Strasse=Adenauerpark“ – je Straße einmal mit Straßen-, einmal mit Gebietsname
        let links = HTMLText.matches(#"BezirkId=(\d+)&(?:amp;)?Container\.Children:1\.Strasse=([^"&]*)"[^>]*>([\s\S]*?)</a>"#, in: html)
        var areas: [String: String] = [:]
        var streets: [String: SelectionOption] = [:]
        for link in links {
            let text = HTMLText.decodeEntities(HTMLText.stripTags(link[2])).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("Abfallgebiet") { areas[link[0]] = text; continue }
            let raw = link[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? link[1]
            let name = HTMLText.decodeEntities(raw).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            streets["\(link[0])|\(name)"] = SelectionOption(id: "\(link[0])|\(name)", title: name)
        }
        guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
        let options = streets.values.map { option -> SelectionOption in
            var option = option
            option.subtitle = areas[String(option.id.prefix { $0 != "|" })]
            return option
        }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
    }

    private func speyerPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let area = String(selections[0].id.prefix { $0 != "|" })
        guard Int(area) != nil else { throw ProviderError.selectAddressFirst }
        var pickups: [Pickup] = []
        for year in [thisYear(calendar), thisYear(calendar) + 1] {
            let url = "\(Self.speyerGips)?SessionMandant=Speyer&Anwendung=Abfuhrkalender&Methode=TermineAnzeigenICS&Mandant=Speyer&Abfuhrkalender=Speyer&Bezirk_ID=\(area)&Jahr=\(year)"
            guard let text = try? await client.string(url) else { continue }
            // „Papier Gewerbe“ betrifft nur Gewerbebetriebe
            pickups += Self.icsPickups(text, calendar: calendar) { $0.contains("Gewerbe") ? [] : [$0] }
        }
        return pickups
    }

    // MARK: - ebwo Worms

    /// Veröffentlichte Jahrgänge laut Startseite. Noch nicht freigegebene Jahre antworten mit 401 + Basic-Auth –
    /// daran bleibt URLSession unter Linux hängen, deshalb nur verlinkte Jahre abfragen.
    private func wormsYears() async throws -> [Int] {
        let html = try await client.string("https://www.ebwo.de/")
        let years = Set(HTMLText.matches(#"/de/abfallkalender/(\d{4})/"#, in: html).compactMap { Int($0[0]) })
        guard !years.isEmpty else { throw ProviderError.noDataGeneric }
        return years.sorted()
    }

    private func wormsStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let current = Calendar.current.component(.year, from: Date())
        guard let year = try await wormsYears().filter({ $0 <= current }).last else { throw ProviderError.noDataGeneric }
        let html = try await client.string("https://www.ebwo.de/de/abfallkalender/\(year)/")
        var streets: [String: SelectionOption] = [:]
        for link in HTMLText.matches(#"<a href="/de/abfallkalender/\d{4}/strasse\.php\?id=([^"]+)"[^>]*>([\s\S]*?)</a>"#, in: html) {
            let name = HTMLText.decodeEntities(HTMLText.stripTags(link[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            streets[link[0]] = SelectionOption(id: link[0], title: name)
        }
        guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(Array(streets.values)))
    }

    private func wormsPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        // Straßen-IDs bleiben über die Jahre gleich.
        var pickups: [Pickup] = []
        for year in try await wormsYears() where year >= thisYear(calendar) {
            let url = "https://www.ebwo.de/de/abfallkalender/\(year)/ical.php?id=\(HTTPClient.query(selections[0].id))"
            guard let text = try? await client.string(url) else { continue }
            // „Restmüll Abholung - Adam-Riese-Straße“
            pickups += Self.icsPickups(text, calendar: calendar) { summary in
                let head = summary.components(separatedBy: " - ").first ?? summary
                return [head.replacingOccurrences(of: " Abholung", with: "")]
            }
        }
        return pickups
    }

    // MARK: - Servicebetrieb Koblenz

    private static let koblenzPage = "https://servicebetrieb.koblenz.de/abfallwirtschaft/entsorgungstermine-digital/"

    private struct KoblenzFile { let url: String; let year: Int; let title: String; let key: String }

    /// „Güls 1_2026.ics“ / „Güls_1_2025.ics“ → Anzeige „Güls 1“, Schlüssel „güls1“.
    private static func koblenzFile(url: String, title: String) -> KoblenzFile? {
        let decoded = HTMLText.decodeEntities(HTMLText.stripTags(title))
        guard let year = Int(HTMLText.firstMatch(#"entsorgungstermine-(\d{4})-digital"#, in: url, group: 1)
                             ?? HTMLText.firstMatch(#"_(\d{4})\.ics"#, in: decoded, group: 1) ?? "") else { return nil }
        guard let base = HTMLText.firstMatch(#"^\s*(.+?)_\d{4}\.ics"#, in: decoded, group: 1) else { return nil }
        let name = base.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        let key = name.lowercased().replacingOccurrences(of: "ß", with: "ss").filter { $0.isLetter || $0.isNumber }
        return KoblenzFile(url: url, year: year, title: name, key: key)
    }

    private static func koblenzFiles(in text: String) -> [KoblenzFile] {
        let json = HTMLText.matches(#""downloadHref":"([^"]+\.ics[^"]*)"[^{}]*?"title":"([^"]+)""#, in: text)
        let anchors = HTMLText.matches(#"<a[^>]*href="(https://[^"]+\.ics[^"]*)"[^>]*>([\s\S]*?)</a>"#, in: text)
        return (json + anchors).compactMap { koblenzFile(url: HTMLText.decodeEntities($0[0]), title: $0[1]) }
    }

    /// Alle ICS-Dateien der Seite – die Download-Liste lädt weitere Seiten nach (`downloadItems.json?…&page=n`).
    private func koblenzAll(stopWhen done: ([KoblenzFile]) -> Bool = { _ in false }) async throws -> [KoblenzFile] {
        let html = HTMLText.decodeEntities(try await client.string(Self.koblenzPage))
        var files = Self.koblenzFiles(in: html)
        if done(files) { return files }
        let lists = HTMLText.matches(#"<filterable-downloads[^>]*>"#, in: html, wholeMatch: true).map { $0[0] }
        for tag in lists {
            guard let feed = HTMLText.firstMatch(#"pseudofile-url="([^"]+)""#, in: tag, group: 1),
                  let total = Int(HTMLText.firstMatch(#":initial-total-count="(\d+)""#, in: tag, group: 1) ?? "") else { continue }
            let first = Self.koblenzFiles(in: tag).count
            guard first > 0, total > first else { continue }
            let pages = min((total + first - 1) / first, 20)
            for page in stride(from: 2, through: pages, by: 1) {
                guard let text = try? await client.string("\(feed)&page=\(page)") else { break }
                files += Self.koblenzFiles(in: text)
                if done(files) { return files }
            }
        }
        return files
    }

    private func koblenzStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let files = try await koblenzAll()
        guard let newest = files.map(\.year).max() else { throw ProviderError.noDataGeneric }
        var options: [String: SelectionOption] = [:]
        for file in files where file.year == newest { options[file.key] = SelectionOption(id: file.key, title: file.title) }
        return SelectionStep(title: L10n.t("Stadtteil", "District"), options: Self.sortedOptions(Array(options.values)))
    }

    private func koblenzPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let key = selections[0].id
        let current = thisYear(calendar)
        let files = try await koblenzAll { files in files.contains { $0.key == key && $0.year >= current } }
        var urls: [Int: String] = [:]
        for file in files where file.key == key && file.year >= current { urls[file.year] = file.url }
        guard !urls.isEmpty else { throw ProviderError.noDataGeneric }
        var pickups: [Pickup] = []
        for url in urls.values {
            guard let text = try? await client.string(url) else { continue }
            pickups += Self.icsPickups(text, calendar: calendar)
        }
        return pickups
    }

    // MARK: - Abfall-App Donnersbergkreis (Softwareentwicklung Roth)

    private static let donnersbergBase = "https://abfallapp.softwareentwicklung-roth.de"
    /// Die Web-App antwortet auf `Accept: */*` (URLSession-Standard) mit 404 – nur HTML-Anfragen werden bedient.
    private static let donnersbergHTML = ["Accept": "text/html,application/xhtml+xml"]
    /// Präfix für Orte mit eigener Straßenliste (Eisenberg, Kirchheimbolanden, Rockenhausen, Winnweiler).
    static let donnersbergStreetPrefix = "orte/"

    /// Ortsliste: `…/kalender/Albisheim/muellarten` (Ort ohne Straßen) oder `…/kalender/orte/Eisenberg/strassen`.
    /// Die ID ist der Pfad hinter `/kalender/`; Orte mit Straßenliste behalten das Präfix `orte/`.
    static func donnersbergPlaces(_ html: String) -> [SelectionOption] {
        var options: [String: SelectionOption] = [:]
        for link in HTMLText.matches(#"href="/web/KIB/de/kalender/((?:orte/)?[^"]+?)/(?:muellarten|strassen)"[^>]*>([^<]*)</a>"#, in: html) {
            let title = HTMLText.decodeEntities(link[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let id = HTMLText.decodeEntities(link[0])
            options[id] = SelectionOption(id: id, title: title)
        }
        return sortedOptions(Array(options.values))
    }

    /// Straßenliste eines Orts: `…/kalender/Kirchheimbolanden/Amtsstrasse/muellarten`.
    static func donnersbergStreets(_ html: String) -> [SelectionOption] {
        donnersbergPlaces(html).filter { !$0.id.hasPrefix(donnersbergStreetPrefix) }
    }

    /// Abfallarten-Formular: `name="abfallart_Restabfall"` … → alle ankreuzen.
    static func donnersbergTypes(_ html: String) -> [String] {
        var seen = Set<String>()
        return HTMLText.matches(#"name="(abfallart_[^"]+)""#, in: html).compactMap(\.first).filter { seen.insert($0).inserted }
    }

    /// „Bioabfall\nVerlegt wg. Weihnachten“ → „Bioabfall“.
    static func donnersbergPickups(_ ics: String, calendar: Calendar) -> [Pickup] {
        icsPickups(ics, calendar: calendar) { summary in
            [summary.replacingOccurrences(of: #"\s+verlegt\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])]
        }
    }

    private func donnersbergStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string("\(Self.donnersbergBase)/web/KIB/de/kalender", headers: Self.donnersbergHTML)
            let places = Self.donnersbergPlaces(html)
            guard !places.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Ort", "Town"), options: places)
        case 1 where selections[0].id.hasPrefix(Self.donnersbergStreetPrefix):
            let html = try await client.string("\(Self.donnersbergBase)/web/KIB/de/kalender/\(selections[0].id)/strassen", headers: Self.donnersbergHTML)
            let streets = Self.donnersbergStreets(html)
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets)
        default:
            return nil
        }
    }

    private func donnersbergPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let path = selections.last?.id, !path.hasPrefix(Self.donnersbergStreetPrefix) else { throw ProviderError.selectAddressFirst }
        let form = try await client.string("\(Self.donnersbergBase)/web/KIB/de/kalender/\(path)/muellarten", headers: Self.donnersbergHTML)
        let types = Self.donnersbergTypes(form)
        guard !types.isEmpty else { throw ProviderError.noDataGeneric }
        let query = types.map { "\(HTTPClient.query($0))=on" }.joined(separator: "&")
        // Jahr steht im Pfad; das Folgejahr gibt es erst, wenn der neue Plan veröffentlicht ist (sonst 404).
        let current = calendar.component(.year, from: referenceDate ?? Date())
        var pickups: [Pickup] = []
        for year in [current, current + 1] {
            guard let text = try? await client.string("\(Self.donnersbergBase)/\(year)/KIB/\(path)/ics/de?\(query)") else { continue }
            pickups += Self.donnersbergPickups(text, calendar: calendar)
        }
        return pickups
    }
}
