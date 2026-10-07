import Foundation

/// AbfallPlus / abfall.io – neue GraphQL-Schnittstelle (widgets.abfall.io).
/// Ablauf: Ort → (Ortsteil) → Straße → Hausnummer → Termine.
public struct AbfallIOGraphQLProvider: WasteProvider {
    public let kind: ProviderKind = .abfallIOGraphQL
    public let serviceKey: String
    public var displayName: String { "AbfallPlus" }
    private let client: HTTPClient
    private let initURL = "https://api.abfall.io"
    private let graphQLURL = "https://widgets.abfall.io/graphql"

    public init(key: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = key
        self.client = client
    }

    private struct Config: Decodable { let apiKey: String }
    private struct Named: Decodable { let id: String; let name: String }
    private struct GraphQLError: Decodable { let message: String }
    private struct Envelope<T: Decodable>: Decodable { let data: T?; let errors: [GraphQLError]? }
    private struct CitiesData: Decodable { let cities: [Named] }
    private struct CityData: Decodable { struct City: Decodable { let streets: [Named]?; let districts: [Named]? }; let city: City? }
    private struct DistrictData: Decodable { struct District: Decodable { let streets: [Named]? }; let district: District? }
    private struct StreetData: Decodable { struct Street: Decodable { let houseNumbers: [Named]? }; let street: Street? }
    private struct AppointmentsData: Decodable {
        struct Appointment: Decodable { struct WasteType: Decodable { let name: String }; let date: String; let wasteType: WasteType }
        let appointments: [Appointment]
    }

    private func apiKey() async throws -> String {
        let config: Config = try await client.json("\(initURL)?key=\(serviceKey)")
        return config.apiKey
    }

    private func query<T: Decodable>(_ query: String, variables: [String: Any] = [:]) async throws -> T {
        let key = try await apiKey()
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let data = try await client.post(graphQLURL, body: body, contentType: "application/json", headers: ["x-abfallplus-api-key": key, "Accept": "application/json"])
        let envelope: Envelope<T> = try HTTPClient.decode(data)
        if let errors = envelope.errors, let first = errors.first { throw ProviderError.noData("AbfallPlus: \(first.message)") }
        guard let payload = envelope.data else { throw ProviderError.noData("AbfallPlus hat keine Daten geliefert.") }
        return payload
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        // Auswahlkette: city → [district] → street → houseNumber. Der Typ steckt in der Option-ID („district:123“).
        let last = selections.last
        if last == nil {
            let data: CitiesData = try await query("{ cities { id name } }")
            return SelectionStep(title: "Ort", options: data.cities.map { SelectionOption(id: "city:\($0.id)", title: $0.name) })
        }
        guard let last else { return nil }
        let parts = last.id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "city":
            let data: CityData = try await query("query($id: ID!) { city(id: $id) { streets { id name } districts { id name } } }", variables: ["id": parts[1]])
            if let districts = data.city?.districts, !districts.isEmpty {
                return SelectionStep(title: "Ortsteil", options: districts.map { SelectionOption(id: "district:\($0.id)", title: $0.name) })
            }
            let streets = data.city?.streets ?? []
            if streets.isEmpty { return nil }
            return SelectionStep(title: "Straße", options: streets.map { SelectionOption(id: "street:\($0.id)", title: $0.name) })
        case "district":
            let data: DistrictData = try await query("query($id: ID!) { district(id: $id) { streets { id name } } }", variables: ["id": parts[1]])
            let streets = data.district?.streets ?? []
            if streets.isEmpty { return nil }
            return SelectionStep(title: "Straße", options: streets.map { SelectionOption(id: "street:\($0.id)", title: $0.name) })
        case "street":
            let data: StreetData = try await query("query($id: ID!) { street(id: $id) { houseNumbers { id name } } }", variables: ["id": parts[1]])
            let numbers = data.street?.houseNumbers ?? []
            if numbers.isEmpty { return nil }
            if numbers.count == 1 { return SelectionStep(title: "Hausnummer", options: numbers.map { SelectionOption(id: "house:\($0.id)", title: $0.name) }, searchable: false) }
            return SelectionStep(title: "Hausnummer", options: numbers.map { SelectionOption(id: "house:\($0.id)", title: $0.name) })
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let house = selections.last(where: { $0.id.hasPrefix("house:") }) else {
            throw ProviderError.invalidSelection("Bitte eine Hausnummer wählen.")
        }
        let id = String(house.id.dropFirst("house:".count))
        let today = Days.today(calendar: calendar)
        let max = calendar.date(byAdding: .day, value: 400, to: today) ?? today
        let data: AppointmentsData = try await query(
            "query Q($idHouseNumber: ID!, $dateMin: Date, $dateMax: Date, $showInactive: Boolean) { appointments(idHouseNumber: $idHouseNumber, dateMin: $dateMin, dateMax: $dateMax, showInactive: $showInactive) { date wasteType { name } } }",
            variables: ["idHouseNumber": id, "dateMin": Days.iso(today, calendar: calendar), "dateMax": Days.iso(max, calendar: calendar), "showInactive": false]
        )
        let pickups = data.appointments.compactMap { item -> Pickup? in
            guard let date = Days.parse(item.date, calendar: calendar) else { return nil }
            return Pickup(date: date, name: NameCleaner.clean(item.wasteType.name))
        }
        guard !pickups.isEmpty else { throw ProviderError.noData("AbfallPlus hat keine Termine für diese Adresse geliefert.") }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }
}
