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

    /// Ist `serviceKey` selbst ein Kalender-Link? Sonst ist es die Webseite eines Portals, auf der
    /// man sich den persönlichen iCal-Link holt (z. B. mein-abfallkalender.de).
    private var isDirectLink: Bool {
        let lower = serviceKey.lowercased()
        return lower.hasPrefix("webcal://") || lower.contains(".ics") || lower.contains("ical") || lower.contains("icalendar")
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard !isDirectLink, selections.isEmpty else { return nil }
        let host = URL(string: serviceKey)?.host ?? serviceKey
        return .text(title: L10n.t("iCal-Link von \(host)", "iCal link from \(host)"),
                     placeholder: L10n.t("Auf \(host) den Link „iCal / Kalender abonnieren“ kopieren und hier einfügen", "Copy the “iCal / subscribe” link on \(host) and paste it here"))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        var link = isDirectLink ? serviceKey : (selections.last?.id ?? "")
        guard !link.isEmpty else { throw ProviderError.selectAddressFirst }
        if link.lowercased().hasPrefix("webcal://") { link = "https://" + link.dropFirst("webcal://".count) }
        let year = calendar.component(.year, from: Date())
        link = link.replacingOccurrences(of: "{%Y}", with: String(year))
        let text = try await client.string(link)
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noData("Die ICS-Datei enthält keine Termine.") }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary), note: $0.location) }
    }
}
