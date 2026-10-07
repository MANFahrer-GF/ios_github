import Foundation

/// Portale Thüringen/Sachsen-Anhalt – Platzhalter, wird ausgebaut.
public struct MitteldeutschlandPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsMitte
    public let serviceKey: String
    public var displayName: String { "Portale Thüringen/Sachsen-Anhalt" }
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        throw ProviderError.notSupported(L10n.t("Noch nicht verfügbar.", "Not available yet."))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        throw ProviderError.notSupported(L10n.t("Noch nicht verfügbar.", "Not available yet."))
    }
}
