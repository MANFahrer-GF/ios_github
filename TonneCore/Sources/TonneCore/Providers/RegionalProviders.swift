import Foundation

// MARK: - Gemos WasteBox (z. B. Ludwigslust-Parchim)

/// Gemos WasteBox: Ortsauswahl als Baum, am Ende eine ICS-Datei pro Knoten.
/// `serviceKey` ist der Kunde, z. B. `lwl` → lwl.wastebox.gemos-management.de.
public struct GemosWasteBoxProvider: WasteProvider {
    public let kind: ProviderKind = .gemosWasteBox
    public let serviceKey: String
    public var displayName: String { "Gemos WasteBox" }
    private let client: HTTPClient

    public init(customer: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = customer
        self.client = client
    }

    private var host: String { "https://\(serviceKey).wastebox.gemos-management.de/Gemos/WasteBox/Frontend/TourSchedule" }

    private func page(year: Int, node: String?) async throws -> String {
        var url = "\(host)/Name/\(year)/"
        if let node { url += "?selectedNodeID=\(node)" }
        return try await client.string(url)
    }

    /// Auswahllisten der Navigation (Ort, ggf. Straße …) mit der gewählten Option.
    static func navigation(_ html: String) -> [[(value: String, label: String, selected: Bool)]] {
        HTMLText.matches(#"<select class="form-control" onchange[^>]*>([\s\S]*?)</select>"#, in: html).map { groups in
            HTMLText.matches(#"<option([^>]*)value="([^"]*)"([^>]*)>([^<]*)</option>"#, in: groups[0]).map { o in
                (value: o[1], label: HTMLText.decodeEntities(o[3]).trimmingCharacters(in: .whitespaces), selected: (o[0] + o[2]).contains("selected"))
            }
        }
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        let year = Calendar.current.component(.year, from: Date())
        let html = try await page(year: year, node: selections.last?.id)
        let levels = Self.navigation(html)
        // Die nächste Ebene ist die erste Liste ohne getroffene Auswahl.
        let depth = selections.count
        guard depth < levels.count else { return nil }
        let options = levels[depth].filter { !$0.value.isEmpty && $0.value != "0" }
        guard !options.isEmpty else { return nil }
        if depth > 0, options.contains(where: { $0.selected }), levels.count == depth + 1, options.count == 1 { return nil }
        let title = depth == 0 ? L10n.t("Gemeinde / Ortsteil", "Town / district") : SelectionStep.streetTitle
        return SelectionStep(title: title, options: options.map { SelectionOption(id: $0.value, title: $0.label) })
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let node = selections.last?.id else { throw ProviderError.selectAddressFirst }
        let now = Date()
        let year = calendar.component(.year, from: now)
        var result: [Pickup] = []
        var lastError: Error?
        for target in [year, year + 1] {
            guard let html = try? await page(year: target, node: node) else { continue }
            let types = HTMLText.firstMatch(#"id="selectedWasteTypes" name="selectedWasteTypes" value="([^"]*)""#, in: html, group: 1) ?? ""
            let categories = HTMLText.firstMatch(#"id="selectedWasteTypeCategories" name="selectedWasteTypeCategories" value="([^"]*)""#, in: html, group: 1) ?? ""
            guard !types.isEmpty else { continue }
            // Ohne Kategorien das Segment weglassen (z. B. Anhalt-Bitterfeld, Schwerin liefern mit „/0“ nur einen Hinweis);
            // ältere Mandanten erwarten „/0“ – darauf zurückfallen.
            let base = "\(host)/Raw/Name/\(target)/List/\(node)/\(types)"
            let urls = categories.isEmpty ? ["\(base)/Print/ics/Default/Abfuhrtermine.ics", "\(base)/0/Print/ics/Default/Abfuhrtermine.ics"]
                                          : ["\(base)/\(categories)/Print/ics/Default/Abfuhrtermine.ics"]
            var events: [ICSEvent] = []
            for url in urls {
                let text: String
                do { text = try await client.string(url) } catch { lastError = error; break }   // Netzfehler nicht als „keine Termine“ verschleiern
                events = ICS.parse(text, calendar: calendar).filter { !Self.isNotice($0.summary) }
                if !events.isEmpty { break }
            }
            for event in events {
                let name = Self.clean(event.summary)
                if name.lowercased().contains("gebühr") { continue }
                result.append(Pickup(date: event.date, name: name))
            }
        }
        guard !result.isEmpty else { throw lastError ?? ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date < $1.date }
    }

    static func clean(_ name: String) -> String {
        NameCleaner.clean(name.replacingOccurrences(of: " Alle Tonnen", with: ""))
    }

    /// Hinweis statt Termin („Es sind neue Abfuhrtermine verfügbar …“).
    static func isNotice(_ summary: String) -> Bool {
        let lower = summary.lowercased()
        return lower.contains("neue abfuhrtermine") || lower.contains("termine verfügbar")
    }
}

// MARK: - AWSH (Kreis Herzogtum Lauenburg, Kreis Stormarn)

public struct AWSHProvider: WasteProvider {
    public let kind: ProviderKind = .awsh
    public let serviceKey: String
    public var displayName: String { serviceKey == "awsh" ? "AWSH" : kind.displayName }
    private let client: HTTPClient
    private let base: String

    /// Gleiche Schnittstelle (api_v2) bei mehreren Kreisen in Schleswig-Holstein und Niedersachsen.
    static let hosts: [String: String] = [
        "awsh": "https://www.awsh.de",                    // Herzogtum Lauenburg, Stormarn
        "steinburg": "https://abfall.steinburg.de",       // Kreis Steinburg
        "awd": "https://api.awd-online.de",               // Dithmarschen
        "awr": "https://www.awr.de",                      // Rendsburg-Eckernförde
        "asf": "https://www.asf-online.de",               // Schleswig-Flensburg
        "stade": "https://abfall.landkreis-stade.de",     // Landkreis Stade
    ]

    public init(region: String = "awsh", client: HTTPClient = HTTPClient()) {
        self.serviceKey = region
        self.client = client
        self.base = (Self.hosts[region] ?? Self.hosts["awsh"]!) + "/api_v2/collection_dates/1"
    }

    private struct Places: Decodable { let orte: [Place] }
    private struct Place: Decodable { let ortsnummer: Flexible; let ortsbezeichnung: String }
    private struct Streets: Decodable { let strassen: [Street] }
    private struct Street: Decodable { let strassennummer: Flexible; let strassenbezeichnung: String }
    private struct Types: Decodable { let abfallarten: [WasteType] }
    struct WasteType: Decodable, Hashable {
        let id: String
        let bezeichnung: String
        let zyklus: String?
        /// Gruppe nach Kennbuchstabe: R = Restabfall, B = Bio, P = Papier, D = Wertstoff …
        var group: String { String(id.prefix(1)) }
        var label: String { [bezeichnung, zyklus].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
    }

    /// Abfallarten eines Ortes, gruppiert. Gruppen mit mehreren Varianten (Tonnengröße, Rhythmus)
    /// werden im Assistenten abgefragt, damit nur die eigene Tonne im Kalender landet.
    private func groups(city: String) async throws -> [(key: String, types: [WasteType])] {
        let types: Types = try await client.json("\(base)/ort/\(city)/abfallarten")
        var order: [String] = []
        var map: [String: [WasteType]] = [:]
        for type in types.abfallarten {
            if map[type.group] == nil { order.append(type.group) }
            map[type.group, default: []].append(type)
        }
        return order.map { (key: $0, types: map[$0] ?? []) }
    }

    private static func groupTitle(_ types: [WasteType]) -> String {
        let first = types.first?.bezeichnung ?? ""
        let base = first.components(separatedBy: CharacterSet.decimalDigits).first?.trimmingCharacters(in: .whitespaces) ?? first
        return L10n.t("\(base.isEmpty ? first : base): welche Tonne hast du?", "\(base.isEmpty ? first : base): which bin do you have?")
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let places: Places = try await client.json("\(base)/orte")
            return SelectionStep(title: SelectionStep.cityTitle, options: places.orte.map { SelectionOption(id: $0.ortsnummer.value, title: $0.ortsbezeichnung) })
        case 1:
            let streets: Streets = try await client.json("\(base)/ort/\(selections[0].id)/strassen")
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.strassen.map { SelectionOption(id: $0.strassennummer.value, title: $0.strassenbezeichnung) })
        default:
            let choices = try await groups(city: selections[0].id).filter { $0.types.count > 1 }
            let index = selections.count - 2
            guard index < choices.count else { return nil }
            let group = choices[index]
            var options = group.types.map { SelectionOption(id: "type:\($0.id)", title: $0.label) }
            options.append(SelectionOption(id: "type:none:\(group.key)", title: L10n.t("Habe ich nicht", "I don't have one")))
            return SelectionStep(title: Self.groupTitle(group.types), options: options, searchable: false)
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let city = selections[0].id, street = selections[1].id
        let all = try await groups(city: city)
        let chosen = Set(selections.dropFirst(2).compactMap { $0.id.hasPrefix("type:") && !$0.id.hasPrefix("type:none:") ? String($0.id.dropFirst(5)) : nil })
        let answered = Set(selections.dropFirst(2).compactMap { option -> String? in
            if option.id.hasPrefix("type:none:") { return String(option.id.dropFirst("type:none:".count)) }
            if option.id.hasPrefix("type:") { return String(option.id.dropFirst(5).prefix(1)) }
            return nil
        })
        var ids: [String] = []
        for group in all {
            if group.types.count == 1 { ids.append(group.types[0].id) }
            else if answered.contains(group.key) { ids += group.types.map(\.id).filter(chosen.contains) }
            else { ids += group.types.map(\.id) }
        }
        guard !ids.isEmpty else { throw ProviderError.noDataGeneric }
        let text = try await client.string("\(base)/ort/\(city)/strasse/\(street)/hausnummern/0/abfallarten/\(ids.joined(separator: "-"))/kalender.ics")
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noDataGeneric }
        return events.map { Pickup(date: $0.date, name: Self.cleanName($0.summary)) }
    }

    /// Nur Ort und Straße – die Tonnenauswahl gehört nicht in den Namen des Standorts.
    public func label(for selections: [SelectionOption]) -> String {
        selections.prefix(2).map(\.title).joined(separator: ", ")
    }

    /// „Restabfall 40L-240L(2-wöchentlich)“ → „Restabfall 40L-240L“, „Biotonne(14tgl.)“ → „Biotonne“
    static func cleanName(_ name: String) -> String {
        let rhythm = #"\s*\((?:[^)]*wöchentlich|[^)]*täglich|\d+\s*tgl\.?|\d+\s*wö\.?|monatlich)\)"#
        return NameCleaner.clean(name.replacingOccurrences(of: rhythm, with: "", options: .regularExpression))
    }
}

/// Zahl oder Text in JSON, als Text gelesen.
struct Flexible: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = String(int) }
        else if let double = try? container.decode(Double.self) { value = String(Int(double)) }
        else { value = try container.decode(String.self) }
    }
}

// MARK: - Lobbe (Sauerland, Märkischer Kreis, Hochsauerland, Waldeck-Frankenberg …)

public struct LobbeProvider: WasteProvider {
    public let kind: ProviderKind = .lobbe
    public let serviceKey: String = "lobbe"
    public var displayName: String { "Lobbe App" }
    private let client: HTTPClient
    private let api = "https://lobbe.app/wp-admin/admin-ajax.php"

    public init(client: HTTPClient = HTTPClient()) { self.client = client }

    private struct Entry: Decodable { let id: Flexible; let text: String }
    private struct ICalLink: Decodable { let url: String }

    private func list(_ action: String, id: String? = nil) async throws -> [Entry] {
        var url = "\(api)?action=\(action)"
        if let id { url += "&id=\(HTTPClient.query(id))" }
        return try await client.json(url)
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let states = try await list("state")
            return SelectionStep(title: L10n.t("Bundesland", "State"), options: states.map { SelectionOption(id: $0.id.value, title: $0.text) })
        case 1:
            let places = try await list("place", id: selections[0].id)
            return SelectionStep(title: SelectionStep.cityTitle, options: places.map { SelectionOption(id: $0.id.value, title: $0.text) })
        case 2:
            let streets = try await list("street", id: selections[1].id)
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0.id.value, title: $0.text) })
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            let params: [(String, String)] = [
                ("year[id]", "1"), ("year[text]", String(target)),
                ("state[id]", selections[0].id), ("state[text]", selections[0].title),
                ("place[id]", selections[1].id), ("place[text]", selections[1].title),
                ("street[id]", selections[2].id), ("street[text]", selections[2].title),
                ("gelber", "1"), ("biobfall", "1"), ("restabfall", "1"), ("altpapier", "1"), ("additional_types", "1"),
                ("hours", "18"), ("minutes", "0"), ("action", "create_ical"),
            ]
            let query = params.map { "\(HTTPClient.query($0.0))=\(HTTPClient.query($0.1))" }.joined(separator: "&")
            guard let link: ICalLink = try? await client.json("\(api)?\(query)"),
                  let text = try? await client.string(link.url) else { continue }
            result += ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date < $1.date }
    }
}

// MARK: - Nerdbridge (Landkreis Northeim)

public struct NerdbridgeProvider: WasteProvider {
    public let kind: ProviderKind = .nerdbridge
    public let serviceKey: String = "northeim"
    public var displayName: String { "abfall.nerdbridge.de" }
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient()) { self.client = client }

    private struct Index: Decodable { let towns: [Town]; let years: [Int]? }
    private struct Town: Decodable { let id: Flexible; let name: String }
    private struct Dates: Decodable { let dates: [Item] }
    private struct Item: Decodable { let date: String; let name: String }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let index: Index = try await client.json("https://abfall.nerdbridge.de/ical/index.json")
        return SelectionStep(title: L10n.t("Ortschaft", "Town"), options: index.towns.map { SelectionOption(id: $0.id.value, title: $0.name) })
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let town = selections.first?.id else { throw ProviderError.selectAddressFirst }
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            guard let data: Dates = try? await client.json("https://abfall.nerdbridge.de/json/\(target)/abfall-nom-\(town)-\(target).json") else { continue }
            for item in data.dates {
                let digits = item.date.prefix(10).replacingOccurrences(of: "-", with: "")
                if let date = ICS.parseDate(digits, params: ["VALUE": "DATE"], calendar: calendar) {
                    result.append(Pickup(date: date, name: NameCleaner.clean(item.name)))
                }
            }
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return result.sorted { $0.date < $1.date }
    }
}

// MARK: - BSR Berlin (Hausmüll, Bio, Laub, Weihnachtsbaum und Wertstofftonne von ALBA/Berlin Recycling)

public struct BSRProvider: WasteProvider {
    public let kind: ProviderKind = .bsr
    public let serviceKey: String = "berlin"
    public var displayName: String { "BSR Berlin" }
    private let client: HTTPClient
    private let base = "https://umnewforms.bsr.de/p/de.bsr.adressen.app"

    public init(client: HTTPClient = HTTPClient()) { self.client = client }

    private struct Option: Decodable { let value: String; let label: String }
    private struct Events: Decodable { let dates: [String: [Event]] }
    private struct Event: Decodable {
        let category: String
        let serviceDate_actual: String
        let disposalComp: String?
    }

    static func name(for category: String, company: String?) -> String {
        let base: String
        switch category {
        case "HM": base = "Hausmüll"
        case "BI": base = "Biogut"
        case "LT": base = "Laubtonne"
        case "WS": base = "Wertstofftonne"
        case "WB": base = "Weihnachtsbaum"
        default: base = category
        }
        if let company, !company.isEmpty, company != "BSR", category != "WS" { return "\(base) (\(company))" }
        return base
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname, z. B. Alexanderstr", "Street name, e.g. Alexanderstr"))
        case 1:
            let options: [Option] = try await client.json("\(base)/streetNames?searchQuery=\(HTTPClient.query(selections[0].id))")
            guard !options.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Keine Berliner Straße gefunden, die zu „\(selections[0].id)“ passt.", "No Berlin street matches “\(selections[0].id)”."))
            }
            return SelectionStep(title: SelectionStep.streetTitle, options: options.map { SelectionOption(id: $0.value, title: $0.label) })
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: "1")
        case 3:
            let query = "\(selections[1].id):::\(selections[2].id)"
            let options: [Option] = try await client.json("\(base)/plzSet/plzSet?searchQuery=\(HTTPClient.query(query))")
            guard !options.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Diese Hausnummer kennt die BSR nicht.", "BSR does not know this house number."))
            }
            return SelectionStep(title: L10n.t("Adresse", "Address"), options: options.map { SelectionOption(id: $0.value, title: $0.label) })
        default:
            return nil
        }
    }

    public func label(for selections: [SelectionOption]) -> String {
        selections.last?.title ?? "Berlin"
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 4 else { throw ProviderError.selectAddressFirst }
        let key = selections[3].id
        let now = Date()
        let year = calendar.component(.year, from: now), month = calendar.component(.month, from: now)
        let from = String(format: "%04d-%02d-01T00:00:00", year, month)
        let to = String(format: "%04d-%02d-01T00:00:00", year + 1, month)
        let filter = "AddrKey eq '\(key)' and DateFrom eq datetime'\(from)' and DateTo eq datetime'\(to)'"
        let events: Events = try await client.json("\(base)/abfuhrEvents?filter=\(HTTPClient.query(filter))")
        var result: [Pickup] = []
        for list in events.dates.values {
            for event in list {
                let parts = event.serviceDate_actual.split(separator: ".")
                guard parts.count == 3 else { continue }
                let digits = "\(parts[2])\(parts[1])\(parts[0])"
                if let date = ICS.parseDate(digits, params: ["VALUE": "DATE"], calendar: calendar) {
                    let note = event.category == "WS" ? event.disposalComp : nil
                    result.append(Pickup(date: date, name: Self.name(for: event.category, company: event.disposalComp), note: note))
                }
            }
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return result.sorted { $0.date < $1.date }
    }
}
