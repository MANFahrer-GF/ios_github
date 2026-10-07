import Foundation

/// Beliebige ICS-Datei im Internet, z. B. der „Sync zu Kalender“-Link eines Abfall-Portals.
public struct ICSURLProvider: WasteProvider {
    public let kind: ProviderKind = .icsURL
    public let serviceKey: String
    public var displayName: String { "ICS-Link" }
    private let client: HTTPClient

    public init(url: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = url
        self.client = client
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? { nil }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let text = try await client.string(serviceKey)
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noData("Die ICS-Datei enthält keine Termine.") }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary), note: $0.location) }
    }
}
