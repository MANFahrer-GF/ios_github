import Foundation

/// Portale auf abfall-app.net (z. B. Landkreis Stendal): Die Ortsliste steckt als JSON in der Startseite,
/// die Termine kommen als ICS über den „Sync zu Kalender“-Link.
/// Ablauf: Ort → (Ortsteil) → (Straße) → Termine.
public struct AbfallAppNetProvider: WasteProvider {
    public let kind: ProviderKind = .abfallAppNet
    public let serviceKey: String
    public var displayName: String { "Abfall-App" }
    private let client: HTTPClient

    public init(tenant: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = tenant
        self.client = client
    }

    private var base: String { "https://\(serviceKey).abfall-app.net" }

    struct City: Decodable { let id: FlexibleID; let name: String; let districts: [District] }
    struct District: Decodable { let id: FlexibleID; let name: String; let streets: [Street]? }
    struct Street: Decodable { let id: FlexibleID; let name: String }

    /// Liest die eingebettete Ortsliste (`:cities-base="[…]"`) aus der Startseite.
    func cities() async throws -> [City] {
        let html = try await client.string(base + "/")
        guard let raw = HTMLText.firstMatch(#":cities-base="(\[[\s\S]*?\])""#, in: html, group: 1)
            ?? HTMLText.firstMatch(#":cities="(\[[\s\S]*?\])""#, in: html, group: 1) else {
            throw ProviderError.noData("Die Ortsliste des Portals konnte nicht gelesen werden.")
        }
        let json = HTMLText.decodeEntities(raw)
        return try HTTPClient.decode(Data(json.utf8))
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            // Einträge ohne Ortsteile sind Karteileichen des Portals
            let list = try await cities().filter { !$0.districts.isEmpty }
            // Orte mit genau einem Ortsteil ohne Straßen direkt als Bezirk anbieten
            return SelectionStep(title: SelectionStep.cityTitle, options: list.map { city in
                if city.districts.count == 1, (city.districts[0].streets ?? []).isEmpty {
                    return SelectionOption(id: "district:\(city.districts[0].id.value)", title: city.name)
                }
                return SelectionOption(id: "city:\(city.id.value)", title: city.name)
            })
        case 1 where selections[0].id.hasPrefix("city:"):
            let cityID = String(selections[0].id.dropFirst("city:".count))
            guard let city = try await cities().first(where: { $0.id.value == cityID }) else { return nil }
            if city.districts.count == 1 {
                return streetStep(for: city.districts[0])
            }
            return SelectionStep(title: SelectionStep.districtTitle, options: city.districts.map { district in
                let streets = district.streets ?? []
                return SelectionOption(id: streets.isEmpty ? "district:\(district.id.value)" : "districtWithStreets:\(district.id.value)", title: district.name)
            })
        case 1, 2:
            guard let last = selections.last, last.id.hasPrefix("districtWithStreets:") else { return nil }
            let districtID = String(last.id.dropFirst("districtWithStreets:".count))
            let district = try await cities().flatMap(\.districts).first { $0.id.value == districtID }
            return district.flatMap { streetStep(for: $0) }
        default:
            return nil
        }
    }

    private func streetStep(for district: District) -> SelectionStep? {
        let streets = district.streets ?? []
        guard !streets.isEmpty else { return nil }
        return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: "street:\($0.id.value)", title: $0.name) })
    }

    public func downloadURL(for selections: [SelectionOption]) -> String? {
        if let street = selections.last(where: { $0.id.hasPrefix("street:") }) {
            return "\(base)/download?system=ical&period=2&street=\(street.id.dropFirst("street:".count))&categories=&view=month"
        }
        if let district = selections.last(where: { $0.id.hasPrefix("district:") || $0.id.hasPrefix("districtWithStreets:") }) {
            let id = district.id.split(separator: ":").last.map(String.init) ?? ""
            return "\(base)/download?system=ical&period=2&district=\(id)&categories=&view=month"
        }
        return nil
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let url = downloadURL(for: selections) else { throw ProviderError.invalidSelection("Bitte einen Ort wählen.") }
        let text = try await client.string(url)
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noData("Das Portal hat keine Termine geliefert.") }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }
}
