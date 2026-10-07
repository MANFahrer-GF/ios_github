import Foundation

/// AbfallNavi (regio iT): REST-API unter `https://{service}-abfallapp.regioit.de/abfall-app-{service}/rest`.
/// Ablauf: Ort → Straße → (Hausnummer) → Termine.
public struct AbfallnaviProvider: WasteProvider {
    public let kind: ProviderKind = .abfallnavi
    public let serviceKey: String
    public var displayName: String { "Abfallnavi" }
    private let client: HTTPClient

    /// Dienste, deren eigene Subdomain nicht mehr existiert.
    private static let sharedDomainServices: Set<String> = ["unna", "frankenthal", "awvlippe", "kranenburg"]

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    private var baseURLs: [String] {
        let shared = "https://abfallapp.regioit.de/abfall-app-\(serviceKey)/rest"
        let own = "https://\(serviceKey)-abfallapp.regioit.de/abfall-app-\(serviceKey)/rest"
        return AbfallnaviProvider.sharedDomainServices.contains(serviceKey) ? [shared, own] : [own, shared]
    }

    private struct Named: Decodable { let id: FlexibleID; let name: String }
    private struct StreetDetail: Decodable { struct Number: Decodable { let id: FlexibleID; let nr: String }; let hausNrList: [Number]? }
    private struct Termin: Decodable { struct Bezirk: Decodable { let fraktionId: FlexibleID }; let datum: String; let bezirk: Bezirk }

    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        var lastError: Error = ProviderError.noData("Abfallnavi nicht erreichbar.")
        for base in baseURLs {
            do { return try await client.json("\(base)/\(path)") } catch { lastError = error }
        }
        throw lastError
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let cities: [Named] = try await fetch("orte")
            return SelectionStep(title: SelectionStep.cityTitle, options: cities.map { SelectionOption(id: "city:\($0.id.value)", title: $0.name) })
        case 1:
            let cityID = selections[0].id.replacingOccurrences(of: "city:", with: "")
            let streets: [Named] = try await fetch("orte/\(cityID)/strassen")
            if streets.isEmpty { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: "street:\($0.id.value)", title: $0.name) })
        case 2:
            let streetID = selections[1].id.replacingOccurrences(of: "street:", with: "")
            let detail: StreetDetail = try await fetch("strassen/\(streetID)")
            let numbers = detail.hausNrList ?? []
            if numbers.count <= 1 { return nil }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: numbers.map { SelectionOption(id: "house:\($0.id.value)", title: $0.nr) })
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let fractions: [Named] = try await fetch("fraktionen")
        var names: [String: String] = [:]
        for fraction in fractions { names[fraction.id.value] = NameCleaner.clean(fraction.name) }
        let query = fractions.map { "fraktion=\($0.id.value)" }.joined(separator: "&")
        let target: String
        if let house = selections.first(where: { $0.id.hasPrefix("house:") }) {
            target = "hausnummern/\(house.id.dropFirst("house:".count))"
        } else if let street = selections.first(where: { $0.id.hasPrefix("street:") }) {
            let streetID = String(street.id.dropFirst("street:".count))
            // Straßen mit genau einer Hausnummer-ID liefern Termine nur über diese ID
            let detail: StreetDetail = try await fetch("strassen/\(streetID)")
            if let only = detail.hausNrList, only.count == 1 { target = "hausnummern/\(only[0].id.value)" } else { target = "strassen/\(streetID)" }
        } else {
            throw ProviderError.invalidSelection("Bitte eine Straße wählen.")
        }
        let termine: [Termin] = try await fetch("\(target)/termine?\(query)")
        let pickups = termine.compactMap { termin -> Pickup? in
            guard let date = Days.parse(termin.datum, calendar: calendar) else { return nil }
            return Pickup(date: date, name: names[termin.bezirk.fraktionId.value] ?? "Abholung")
        }
        guard !pickups.isEmpty else { throw ProviderError.noData("Abfallnavi hat keine Termine für diese Adresse geliefert.") }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }
}
