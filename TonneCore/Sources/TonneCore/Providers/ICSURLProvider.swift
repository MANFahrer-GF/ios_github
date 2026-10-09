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

    /// Ist `serviceKey` selbst ein Kalender-Link? Nur die Portalseiten von mein-abfallkalender.online sind keine –
    /// dort holt man sich den persönlichen iCal-Link. Direktlinks heißen nicht immer „….ics“
    /// (z. B. `admin-post.php?action=mzv_ics_download&slug=Engen`).
    var isDirectLink: Bool {
        let lower = serviceKey.lowercased()
        if lower.hasPrefix("webcal://") || lower.contains(".ics") || lower.contains("ical") { return true }
        let host = URL(string: serviceKey)?.host?.lowercased() ?? ""
        return !host.hasSuffix("mein-abfallkalender.online")
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
        if let marker = link.range(of: Self.pageMarker) {
            // Seite mit wechselndem Kalenderlink (Jahr/Kennung im Dateinamen): den passenden Link auf der Seite suchen.
            let page = String(link[..<marker.lowerBound]), needle = String(link[marker.upperBound...])
            guard let base = URL(string: page), let found = Self.link(in: try await client.string(page), base: base, matching: needle) else {
                throw ProviderError.noData(L10n.t("Kein aktueller Kalender auf \(URL(string: page)?.host ?? page) gefunden.",
                                                  "No current calendar found on \(URL(string: page)?.host ?? page)."))
            }
            link = found.absoluteString
        }
        let text = try await client.string(link)
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noData("Die ICS-Datei enthält keine Termine.") }
        return events.filter { !WasteCategory.isIgnorableTitle($0.summary) }
            .flatMap { event in Self.names(event.summary).map { Pickup(date: event.date, name: $0, note: event.location) } }
    }

    /// `<Seite>#link=<Text>`: Kalender ist der erste ICS-Link der Seite, dessen Adresse oder Linktext `<Text>` enthält
    /// (`{%Y}` wird vorher durch das Jahr ersetzt).
    static let pageMarker = "#link="

    static func link(in html: String, base: URL, matching needle: String) -> URL? {
        let wanted = needle.lowercased()
        for anchor in HTMLText.matches(#"<a\s[^>]*?href="([^"]+)"[^>]*>([\s\S]*?)</a>"#, in: html) {
            let href = anchor[0].replacingOccurrences(of: "&amp;", with: "&")
            let text = anchor[1].replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let lower = href.lowercased()
            guard lower.contains(".ics") || lower.contains("ical") || lower.hasPrefix("webcal:") else { continue }
            if lower.contains(wanted) || text.lowercased().contains(wanted) {
                return URL(string: href, relativeTo: base)?.absoluteURL
            }
        }
        return nil
    }

    /// Abfallart(en) aus einem Kalendertitel: „Abholung: Biomüll“ → „Biomüll“, „Abfalltermin (Restmüll)“ → „Restmüll“.
    /// Sammeltermine („Biomüll, Restmüll“, „Restmüll / Gelbe Tonne“) werden aufgeteilt, wenn jeder Teil eine andere
    /// Tonnenart ist – sonst ginge die Erinnerung an die zweite Tonne verloren.
    static func names(_ summary: String) -> [String] {
        var name = NameCleaner.clean(summary)
            .replacingOccurrences(of: #"^(Abholung|Abfuhr|Leerung)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let inner = HTMLText.firstMatch(#"^Abfalltermin\s*\((.+)\)$"#, in: name, group: 1) { name = inner }
        let parts = name.components(separatedBy: CharacterSet(charactersIn: ",/+"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let categories = parts.map(WasteCategory.classify)
        if parts.count > 1, !categories.contains(.other), Set(categories).count == parts.count { return parts }
        return [name.isEmpty ? NameCleaner.clean(summary) : name]
    }
}
