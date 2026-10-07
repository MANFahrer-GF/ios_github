import Foundation

/// Müllabfuhr Deutschland (portal.muellabfuhr-deutschland.de): Wittenberg, Burgenlandkreis, Dessau-Roßlau,
/// Saalekreis, Weimarer Land, Sömmerda, Hildburghausen. Die Orte bilden einen Baum (Ort → Ortsteil → Straße),
/// ausgewählt wird bis zu einem Eintrag mit `isFinal`.
public struct MuellabfuhrDeutschlandProvider: WasteProvider {
    public let kind: ProviderKind = .muellabfuhrDeutschland
    public let serviceKey: String
    public var displayName: String { "Müllabfuhr Deutschland" }
    private let client: HTTPClient
    private let api = "https://portal.muellabfuhr-deutschland.de/api-portal"

    public init(mandator: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = mandator
        self.client = client
    }

    private struct Config: Decodable { let calendarRootLocationId: String }
    private struct Node: Decodable { let id: String; let name: String; let isFinal: Bool?; let children: [Node]? }
    private struct Item: Decodable { let date: String; let fraction: Fraction }
    private struct Fraction: Decodable { let name: String }

    /// Auswahl-IDs tragen vorn „F:“ (letzte Ebene) oder „N:“ (es geht weiter).
    private static func encode(_ node: Node) -> SelectionOption {
        SelectionOption(id: ((node.isFinal ?? false) ? "F:" : "N:") + node.id, title: node.name)
    }
    private static func nodeID(_ option: SelectionOption) -> String { String(option.id.dropFirst(2)) }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        if let last = selections.last, last.id.hasPrefix("F:") { return nil }
        let parent: String
        if let last = selections.last {
            parent = Self.nodeID(last)
        } else {
            let config: Config = try await client.json("\(api)/mandators/\(HTTPClient.query(serviceKey))/config")
            parent = config.calendarRootLocationId
        }
        let node: Node = try await client.json("\(api)/mandators/\(HTTPClient.query(serviceKey))/cal/location/\(parent)?includeChildren=true")
        let children = (node.children ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !children.isEmpty else {
            // Keine weiteren Ebenen: der Knoten selbst ist die Adresse
            if selections.isEmpty { throw ProviderError.noDataGeneric }
            return nil
        }
        let title: String
        switch selections.count {
        case 0: title = SelectionStep.cityTitle
        case 1: title = L10n.t("Ortsteil oder Straße", "District or street")
        default: title = SelectionStep.streetTitle
        }
        return SelectionStep(title: title, options: children.map(Self.encode))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let last = selections.last else { throw ProviderError.selectAddressFirst }
        let items: [Item] = try await client.json("\(api)/mandators/\(HTTPClient.query(serviceKey))/cal/location/\(Self.nodeID(last))/pickups")
        let pickups = items.compactMap { item -> Pickup? in
            guard let date = Days.parse(String(item.date.prefix(10)), calendar: calendar) else { return nil }
            return Pickup(date: date, name: NameCleaner.clean(item.fraction.name))
        }
        guard !pickups.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(pickups)).sorted { $0.date < $1.date }
    }
}
