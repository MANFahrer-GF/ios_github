import Foundation

/// Heimat-Info (Gemeinde-App, vor allem kleinere Gemeinden in Bayern). Je Gemeinde ein Katalogeintrag
/// (serviceKey = Slug); Auswahl Abfuhrbezirk → Termine.
public struct HeimatInfoProvider: WasteProvider {
    public let kind: ProviderKind = .heimatInfo
    public let serviceKey: String
    public var displayName: String { "Heimat-Info" }
    private let client: HTTPClient
    private let api = "https://heimatinfo-api-platform.azurewebsites.net"

    public init(commune: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = commune
        self.client = client
    }

    private struct Area: Decodable { let id: String; let name: String }
    private struct Item: Decodable { let date: String; let type: String }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let areas: [Area] = try await client.json("\(api)/communes/\(HTTPClient.query(serviceKey))/garbagepickupareas")
        guard !areas.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: L10n.t("Abfuhrbezirk", "Collection area"),
                             options: areas.map { SelectionOption(id: $0.id, title: $0.name) }
                                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let area = selections.first else { throw ProviderError.selectAddressFirst }
        let items: [Item] = try await client.json("\(api)/communes/\(HTTPClient.query(serviceKey))/garbagepickupareas/\(area.id)/garbagepickupdates")
        let pickups = items.compactMap { item -> Pickup? in
            guard let date = Days.parse(String(item.date.prefix(10)), calendar: calendar) else { return nil }
            return Pickup(date: date, name: Self.name(for: item.type))
        }
        guard !pickups.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(pickups)).sorted { $0.date < $1.date }
    }

    static func name(for type: String) -> String {
        switch type {
        case "Residual": return L10n.t("Restmüll", "General waste")
        case "Organic": return L10n.t("Biotonne", "Organic waste")
        case "Paper": return L10n.t("Papier", "Paper")
        case "Recyclable": return L10n.t("Gelber Sack", "Packaging")
        case "BulkyWaste": return L10n.t("Sperrmüll", "Bulky waste")
        case "HazardousWaste": return L10n.t("Schadstoffmobil", "Hazardous waste")
        case "Glass": return L10n.t("Glas", "Glass")
        case "GreenWaste", "Garden": return L10n.t("Grünschnitt", "Garden waste")
        default: return NameCleaner.clean(type)
        }
    }
}
