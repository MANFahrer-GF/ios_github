import Foundation

/// Sitepark IES / abto: Abfallkalender-Modul vieler Kreis- und Stadtportale (Landkreis Peine, Goslar,
/// Kreis Plön, Mecklenburgische Seenplatte, Wittmund, Ostprignitz-Ruppin, Ilm-Kreis …).
///
/// Ablauf: Ort wählen → Straße wählen → ICS über `/output/options.php?ModID=48&call=ical&pois=…`.
/// Portale mit Ortsliste (`sf_locid` auf der Kalenderseite) liefern die Straßen je Ort; alle anderen
/// liefern alle Straßen als „Straße (Ort)“, daraus werden die Orte gebildet.
/// Jede Anfrage braucht einen Referer auf das Portal, sonst antwortet der Server mit 403.
public struct SiteparkProvider: WasteProvider {
    public struct Tenant: Hashable {
        public let id: String
        public let base: String
        /// Seite mit der Ortsauswahl (`sf_locid`), falls das Portal Straßen nur je Ort liefert.
        public let page: String?
        /// Feste Bereichs-ID für die Straßensuche.
        public let refid: String?
        /// Zusätzliche Parameter für den ICS-Download (bereits URL-kodiert).
        public let download: String?
    }

    public static let tenants: [String: Tenant] = [
        "peine": Tenant(id: "peine", base: "https://www.ab-peine.de", page: "/Abfuhrtermine/", refid: nil, download: nil),
        "wittmund": Tenant(id: "wittmund", base: "https://www.landkreis-wittmund.de", page: "/Leben-Wohnen/Wohnen/Abfall/Abfuhrkalender/", refid: nil,
                           download: "ArtID%5B0%5D=3105.1&ArtID%5B1%5D=1.4&ArtID%5B2%5D=1.2&ArtID%5B3%5D=1.3&ArtID%5B4%5D=1.1&alarm=0"),
        "goslar": Tenant(id: "goslar", base: "https://www.kwb-goslar.de", page: nil, refid: nil, download: nil),
        "ploen": Tenant(id: "ploen", base: "https://www.kreis-ploen.de", page: nil, refid: nil, download: nil),
        "seenplatte": Tenant(id: "seenplatte", base: "https://www.lk-mecklenburgische-seenplatte.de", page: nil, refid: nil, download: nil),
        "muehlenkreis": Tenant(id: "muehlenkreis", base: "https://www.muehlenkreis.de", page: nil, refid: nil, download: nil),
        "ostprignitz-ruppin": Tenant(id: "ostprignitz-ruppin", base: "https://www.ostprignitz-ruppin.de", page: nil, refid: nil, download: "monat=&alarm=0"),
        "ilm-kreis": Tenant(id: "ilm-kreis", base: "https://aik.ilm-kreis.de", page: nil, refid: nil, download: nil),
        "neunkirchen-siegerland": Tenant(id: "neunkirchen-siegerland", base: "https://www.neunkirchen-siegerland.de", page: nil, refid: "3362.1", download: "kat=1&alarm=0"),
        "hilchenbach": Tenant(id: "hilchenbach", base: "https://hilchenbach.de", page: nil, refid: nil, download: "kat=1&alarm=0"),
        "gross-gerau": Tenant(id: "gross-gerau", base: "https://www.gross-gerau.de", page: nil, refid: "3411.1", download: nil),
    ]

    public let kind: ProviderKind = .sitepark
    public let serviceKey: String
    public var displayName: String { "Sitepark" }
    private let client: HTTPClient

    public init(tenant: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = tenant
        self.client = client
    }

    private var tenant: Tenant? { Self.tenants[serviceKey] }
    private var referer: [String: String] { ["Referer": (tenant?.base ?? "") + "/"] }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let tenant else { throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }
        switch selections.count {
        case 0:
            let places = try await places(tenant)
            guard !places.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: places)
        case 1:
            let streets = try await streets(tenant, place: selections[0])
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets)
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let tenant, selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        var url = "\(tenant.base)/output/options.php?ModID=48&call=ical&pois=\(HTTPClient.query(selections[1].id))"
        if let download = tenant.download { url += "&" + download }
        let text = try await client.string(url, headers: referer)
        let pickups = ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        guard !pickups.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(pickups)).sorted { $0.date < $1.date }
    }

    // MARK: - Orte und Straßen

    private func places(_ tenant: Tenant) async throws -> [SelectionOption] {
        if let page = tenant.page {
            let html = try await client.string(tenant.base + page, headers: referer)
            guard let select = HTMLText.firstMatch(#"<select[^>]*id="sf_locid"[^>]*>(.*?)</select>"#, in: html.replacingOccurrences(of: "\n", with: " "), group: 1) else { return [] }
            return HTMLText.matches(#"<option[^>]*value="([^"]+)"[^>]*>([^<]*)<"#, in: select).compactMap { match in
                guard match.count >= 2 else { return nil }
                let title = HTMLText.decodeEntities(match[1]).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : SelectionOption(id: match[0], title: title)
            }
        }
        let entries = try await autocomplete(tenant, refid: tenant.refid)
        let names = Set(entries.map { Self.split($0.label).place })
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { SelectionOption(id: $0, title: $0.isEmpty ? L10n.t("Weitere Straßen", "Other streets") : $0) }
    }

    private func streets(_ tenant: Tenant, place: SelectionOption) async throws -> [SelectionOption] {
        let entries: [(pois: String, label: String)]
        if tenant.page != nil {
            entries = try await autocomplete(tenant, refid: place.id)
        } else {
            entries = try await autocomplete(tenant, refid: tenant.refid).filter { Self.split($0.label).place == place.id }
        }
        return entries
            .map { entry -> SelectionOption in
                let street = Self.split(entry.label).street
                // „Broistedt - alle Straßen“ → „Alle Straßen“ (der Ort steht schon in der Auswahl davor)
                if street.lowercased().contains("alle straßen") { return SelectionOption(id: entry.pois, title: L10n.t("Alle Straßen", "All streets")) }
                return SelectionOption(id: entry.pois, title: street.isEmpty ? entry.label : street)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// `/output/autocomplete.php` liefert `[[pois, "Straße (Ort)"], …]` oder `null`.
    private func autocomplete(_ tenant: Tenant, refid: String?) async throws -> [(pois: String, label: String)] {
        var url = "\(tenant.base)/output/autocomplete.php?out=json&type=abto&select=2&term="
        if let refid { url += "&refid=\(HTTPClient.query(refid))" }
        let data = try await client.get(url, headers: referer.merging(["X-Requested-With": "XMLHttpRequest", "Accept": "application/json"]) { a, _ in a })
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return rows.compactMap { row in
            guard row.count >= 2, let label = row[1] as? String else { return nil }
            let pois = (row[0] as? String) ?? (row[0] as? NSNumber)?.stringValue
            return pois.map { ($0, label.trimmingCharacters(in: .whitespaces)) }
        }
    }

    /// „Adlerstraße (Peine-Kernstadt (mit Telgte))“ → Straße „Adlerstraße“, Ort „Peine-Kernstadt (mit Telgte)“.
    /// Die letzte, ggf. verschachtelte Klammer ist der Ort.
    static func split(_ label: String) -> (street: String, place: String) {
        let text = label.trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix(")") else { return (text, "") }
        var depth = 0
        var index = text.endIndex
        while index > text.startIndex {
            index = text.index(before: index)
            switch text[index] {
            case ")": depth += 1
            case "(":
                depth -= 1
                if depth == 0 {
                    let street = text[..<index].trimmingCharacters(in: .whitespaces)
                    let place = text[text.index(after: index)..<text.index(before: text.endIndex)].trimmingCharacters(in: .whitespaces)
                    return (street, place)
                }
            default: break
            }
        }
        return (text, "")
    }
}
