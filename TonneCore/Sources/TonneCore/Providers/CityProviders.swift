import Foundation

// MARK: - AWB Köln

/// Abfallwirtschaftsbetriebe Köln: Straße und Hausnummer eingeben, Treffer wählen, JSON-Kalender.
public struct AWBKoelnProvider: WasteProvider {
    public let kind: ProviderKind = .awbKoeln
    public let serviceKey: String = "koeln"
    public var displayName: String { "AWB Köln" }
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient()) { self.client = client }

    /// „Köln, Aachener Straße 50“: Straße und Hausnummer sind nur getippte Suche, zählen tut die gefundene Adresse.
    public func label(for selections: [SelectionOption]) -> String {
        guard let address = selections.first(where: { $0.id.hasPrefix("addr:") }) else { return "Köln" }
        return "Köln, " + address.title
    }

    private struct Street: Decodable { let street_name: String; let building_number: String; let street_code: String; let district: String?; let zipcode: String? }
    private struct Streets: Decodable { let data: [Street] }
    private struct Entry: Decodable { let day: Int; let month: Int; let year: Int; let type: String }
    private struct CalendarPayload: Decodable { let data: [Entry] }

    static let typeNames: [String: String] = ["grey": "Restmüll", "blue": "Papiertonne", "brown": "Biotonne", "wertstoff": "Wertstofftonne", "yellow": "Wertstofftonne", "green": "Biotonne"]

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0: return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Aachener Str.", "e.g. Aachener Str."))
        case 1: return .text(title: SelectionStep.houseNumberTitle, placeholder: "50")
        case 2:
            // Die API will eine reine Zahl, Zusätze getrennt – „50-52“ oder „50/1“ ergaben sonst HTTP 422 (12.11.2026)
            let (number, addition) = Self.splitNumber(selections[1].title)
            guard !number.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Bitte eine Hausnummer mit Zahl eingeben, z. B. 50 oder 50a.", "Please enter a house number, e.g. 50 or 50a."))
            }
            let url = "https://www.awbkoeln.de/api/streets?street_name=\(HTTPClient.query(selections[0].title))&building_number=\(number)"
                + (addition.isEmpty ? "" : "&building_number_addition=\(HTTPClient.query(addition))")
            let result: Streets = try await client.json(url)
            guard !result.data.isEmpty else { throw ProviderError.noData(L10n.t("Keine passende Adresse in Köln gefunden.", "No matching address found in Cologne.")) }
            return SelectionStep(title: L10n.t("Adresse", "Address"), options: result.data.map {
                SelectionOption(id: "addr:\($0.street_code):\($0.building_number)", title: "\($0.street_name) \($0.building_number)", subtitle: [$0.zipcode, $0.district].compactMap { $0 }.joined(separator: " "))
            }, searchable: false)
        default: return nil
        }
    }

    /// „ 50 a“ → („50“, „a“), „50-52“ → („50“, „-52“)
    static func splitNumber(_ raw: String) -> (number: String, addition: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let number = String(text.prefix { $0.isASCII && $0.isNumber })
        return (number, text.dropFirst(number.count).trimmingCharacters(in: .whitespaces))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let address = selections.last(where: { $0.id.hasPrefix("addr:") }) else { throw ProviderError.selectAddressFirst }
        let parts = address.id.split(separator: ":").map(String.init)
        guard parts.count == 3 else { throw ProviderError.selectAddressFirst }
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let url = "https://www.awbkoeln.de/api/calendar?street_code=\(parts[1])&building_number=\(HTTPClient.query(parts[2]))&start_year=\(year)&start_month=\(month)&end_year=\(year + 1)&end_month=\(month)"
        let payload: CalendarPayload = try await client.json(url)
        let pickups = payload.data.compactMap { entry -> Pickup? in
            guard let date = Days.make(year: entry.year, month: entry.month, day: entry.day, calendar: calendar) else { return nil }
            return Pickup(date: date, name: AWBKoelnProvider.typeNames[entry.type.lowercased()] ?? entry.type.capitalized)
        }
        guard !pickups.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }
}

// MARK: - Stadtreinigung Leipzig

/// Stadtreinigung Leipzig: Straße suchen, Hausnummer wählen, ICS laden.
public struct LeipzigProvider: WasteProvider {
    public let kind: ProviderKind = .leipzig
    public let serviceKey: String = "leipzig"
    public var displayName: String { "Stadtreinigung Leipzig" }
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient()) { self.client = client }

    /// „Leipzig, Hamburger Straße 10“: Der getippte Suchtext („Hamburger Str.“) gehört nicht zur Adresse.
    public func label(for selections: [SelectionOption]) -> String {
        let street = selections.first { $0.id.hasPrefix("street:") }?.title ?? ""
        let house = selections.first { $0.id.hasPrefix("house:") }?.title ?? ""
        let address = [street, house].filter { !$0.isEmpty }.joined(separator: " ")
        return address.isEmpty ? "Leipzig" : "Leipzig, " + address
    }

    /// Antwort von `rest/odata/Streets` (seit November 2026; der Vorgänger `rest/Navision/Streets` antwortet mit 405).
    struct Streets: Decodable {
        struct Street: Decodable {
            struct Number: Decodable { let number: String; let position_nos: [String] }
            let name: String
            var postalcode: String?
            var district: String?
            let numbers: [Number]
            var place: String { [postalcode, district].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
        }
        let results: [Street]
    }

    private func search(_ term: String) async throws -> [Streets.Street] {
        let result: Streets = try await client.json("https://stadtreinigung-leipzig.de/rest/odata/Streets?search=\(HTTPClient.query(term))")
        return result.results
    }

    /// Gleichnamige Straßen unterscheidet nur Postleitzahl und Ortsteil – in der Kennung hinter „|“ und als Unterzeile.
    static func streetOptions(_ streets: [Streets.Street]) -> [SelectionOption] {
        let counts = Dictionary(streets.map { ($0.name, 1) }, uniquingKeysWith: +)
        return streets.sorted { ($0.name, $0.place) < ($1.name, $1.place) }.map {
            let twin = (counts[$0.name] ?? 0) > 1
            return SelectionOption(id: twin ? "street:\($0.name)|\($0.place)" : "street:\($0.name)", title: $0.name, subtitle: twin ? $0.place : nil)
        }
    }

    /// Straßenname und (bei gleichnamigen Straßen) Postleitzahl mit Ortsteil aus der Kennung.
    static func streetParts(_ id: String) -> (name: String, place: String?) {
        let parts = id.dropFirst("street:".count).split(separator: "|", maxSplits: 1).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : nil)
    }

    /// Eine Hausnummer kann mehrere Standplätze haben; der Kalender braucht alle (so ruft ihn auch die Webseite ab).
    static func houseOptions(_ streets: [Streets.Street], for street: SelectionOption) -> [SelectionOption]? {
        let wanted = streetParts(street.id)
        let sameName = streets.filter { $0.name == wanted.name }
        guard let match = sameName.first(where: { $0.place == wanted.place }) ?? sameName.first else { return nil }
        let sorted = match.numbers.sorted { (Int($0.number.filter(\.isNumber)) ?? 0, $0.number) < (Int($1.number.filter(\.isNumber)) ?? 0, $1.number) }
        return sorted.map { SelectionOption(id: "house:\($0.position_nos.joined(separator: ",")):\($0.number)", title: $0.number) }
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0: return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Bahnhofsallee", "e.g. Bahnhofsallee"))
        case 1:
            let streets = try await search(selections[0].title)
            guard !streets.isEmpty else { throw ProviderError.noData(L10n.t("Straße nicht gefunden.", "Street not found.")) }
            return SelectionStep(title: SelectionStep.streetTitle, options: LeipzigProvider.streetOptions(streets))
        case 2:
            let streets = try await search(LeipzigProvider.streetParts(selections[1].id).name)
            guard let options = LeipzigProvider.houseOptions(streets, for: selections[1]) else { return nil }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: options)
        default: return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let house = selections.last(where: { $0.id.hasPrefix("house:") }), let street = selections.first(where: { $0.id.hasPrefix("street:") }) else { throw ProviderError.selectAddressFirst }
        let parts = house.id.split(separator: ":").map(String.init)
        guard parts.count == 3 else { throw ProviderError.selectAddressFirst }
        let name = HTTPClient.query("\(LeipzigProvider.streetParts(street.id).name) \(parts[2])")
        let text = try await client.string("https://stadtreinigung-leipzig.de/wir-kommen-zu-ihnen/abfallkalender/ical.ics?position_nos=\(parts[1])&name=\(name)&mode=download")
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noDataGeneric }
        return events.map { Pickup(date: $0.date, name: LeipzigProvider.cleanName($0.summary)) }
    }

    /// Der Kalender hängt an jeden Titel „(Abholzeit)“ – das ist keine Müllart.
    static func cleanName(_ summary: String) -> String {
        let edges = CharacterSet(charactersIn: ", ")
        return NameCleaner.clean(ICSURLProvider.withoutPickupTimeSuffix(summary.trimmingCharacters(in: edges)).trimmingCharacters(in: edges))
    }
}

// MARK: - aha Region Hannover

/// Zweckverband Abfallwirtschaft Region Hannover: Gemeinde → Anfangsbuchstabe → Straße → Hausnummer → (Ladeort) → ICS.
public struct AhaHannoverProvider: WasteProvider {
    public let kind: ProviderKind = .ahaHannover
    public let serviceKey: String = "hannover"
    public var displayName: String { "aha Region Hannover" }
    private let client: HTTPClient
    private let api = "https://www.aha-region.de/abholtermine/abfuhrkalender"

    public init(client: HTTPClient = HTTPClient()) { self.client = client }

    /// „Hannover, Hauptstraße 10“: Der zweite Schritt ist nur der getippte Suchtext für die Straßenliste.
    public func label(for selections: [SelectionOption]) -> String {
        let city = selections.first { $0.id.hasPrefix("city:") }?.title ?? ""
        let street = selections.first { $0.id.hasPrefix("street:") }?.title ?? ""
        let number = selections.count > 3 ? selections[3].title.trimmingCharacters(in: .whitespaces) : ""
        let place = selections.first { $0.id.hasPrefix("ladeort:") }?.title ?? ""
        return [city, [street, number].filter { !$0.isEmpty }.joined(separator: " "), place].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(api)
            let cities = HTMLText.options(ofSelect: "gemeinde", in: html).filter { !$0.value.isEmpty }
            guard !cities.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Gemeinde", "Municipality"), options: cities.map { SelectionOption(id: "city:\($0.value)", title: $0.label) })
        case 1:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Anfangsbuchstabe oder Name", "First letter or name"))
        case 2:
            let city = String(selections[0].id.dropFirst("city:".count))
            let letter = String(selections[1].title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            let html = try await client.string("\(api)?gemeinde=\(HTTPClient.query(city))&von=\(HTTPClient.query(letter))")
            let needle = selections[1].title.lowercased()
            var streets = HTMLText.options(ofSelect: "strasse", in: html).filter { !$0.value.isEmpty }
            if needle.count > 1 {
                let filtered = streets.filter { $0.label.lowercased().contains(needle) }
                if !filtered.isEmpty { streets = filtered }
            }
            guard !streets.isEmpty else { throw ProviderError.noData(L10n.t("Keine Straße gefunden.", "No street found.")) }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: "street:\($0.value)", title: $0.label) })
        case 3:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: "1")
        case 4:
            // Manche Adressen haben mehrere Ladeorte
            let html = try await overview(selections)
            let places = HTMLText.options(ofSelect: "ladeort", in: html).filter { !$0.value.isEmpty }
            if places.count > 1 {
                return SelectionStep(title: L10n.t("Ladeort", "Pickup point"), options: places.map { SelectionOption(id: "ladeort:\($0.value)", title: $0.label) })
            }
            return nil
        default:
            return nil
        }
    }

    private func formFields(_ selections: [SelectionOption]) -> [(String, String)] {
        let city = String(selections[0].id.dropFirst("city:".count))
        let street = String(selections[2].id.dropFirst("street:".count))
        let number = selections[3].title.trimmingCharacters(in: .whitespaces)
        let digits = number.prefix { $0.isNumber }
        let addon = number.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        return [("gemeinde", city), ("jsaus", ""), ("von", String(selections[1].title.prefix(1)).uppercased()), ("strasse", street), ("hausnr", String(digits)), ("hausnraddon", addon)]
    }

    private func overview(_ selections: [SelectionOption]) async throws -> String {
        HTTPClient.text(from: try await client.postForm(api, fields: formFields(selections) + [("anzeigen", "Suchen")]))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 4 else { throw ProviderError.selectAddressFirst }
        var fields = formFields(selections)
        if let chosen = selections.first(where: { $0.id.hasPrefix("ladeort:") }) {
            fields.append(("ladeort", String(chosen.id.dropFirst("ladeort:".count))))
        } else {
            let html = try await overview(selections)
            let single = HTMLText.firstMatch(#"<input[^>]*name=["']ladeort["'][^>]*value=["']([^"']*)["']"#, in: html, group: 1)
                ?? HTMLText.options(ofSelect: "ladeort", in: html).first(where: { !$0.value.isEmpty })?.value
            guard let single else { throw ProviderError.noData(L10n.t("Adresse nicht gefunden.", "Address not found.")) }
            fields.append(("ladeort", single))
        }
        fields.append(("ical", "ICAL Jahresübersicht"))
        let text = HTTPClient.text(from: try await client.postForm(api, fields: fields))
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noDataGeneric }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary.replacingOccurrences(of: "Abfuhr", with: "").replacingOccurrences(of: " *", with: ""))) }
    }
}
