import Foundation

/// AWIDO-Portal (awido.cubefour.de), u. a. Landkreis Gifhorn.
/// Ablauf: Ort → Straße → (Hausnummer) → Termine als JSON.
public struct AwidoProvider: WasteProvider {
    public let kind: ProviderKind = .awido
    public let serviceKey: String
    public var displayName: String { "AWIDO" }
    private let client: HTTPClient
    private let base = "https://awido.cubefour.de/WebServices/Awido.Service.svc/secure"

    public init(customer: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = customer
        self.client = client
    }

    private struct Entry: Decodable { let key: String; let value: String }
    private struct Fraction: Decodable { let snm: String; let nm: String }
    private struct CalendarItem: Decodable { let dt: String; let fr: [String]?; let ad: [String?]? }
    private struct Payload: Decodable { let fracts: [Fraction]; let calendar: [CalendarItem] }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let places: [Entry] = try await client.json("\(base)/getPlaces/client=\(serviceKey)")
            return SelectionStep(title: SelectionStep.cityTitle, options: places.map { SelectionOption(id: $0.key, title: $0.value) })
        case 1:
            let streets: [Entry] = try await client.json("\(base)/getGroupedStreets/\(selections[0].id)?client=\(serviceKey)")
            if streets.isEmpty { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0.key, title: $0.value) })
        case 2:
            let numbers: [Entry] = try await client.json("\(base)/getStreetAddons/\(selections[1].id)?client=\(serviceKey)")
            let real = numbers.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            if real.isEmpty { return nil }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: real.map { SelectionOption(id: $0.key, title: $0.value) })
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let oid = selections.last?.id else { throw ProviderError.invalidSelection("Bitte zuerst eine Adresse wählen.") }
        let payload: Payload = try await client.json("\(base)/getData/\(oid)?fractions=&client=\(serviceKey)")
        var names: [String: String] = [:]
        for fraction in payload.fracts { names[fraction.snm] = NameCleaner.clean(fraction.nm) }
        var result: [Pickup] = []
        for item in payload.calendar {
            guard let codes = item.fr, item.ad != nil, let date = ICS.parseDate(item.dt, calendar: calendar) else { continue }
            for (index, code) in codes.enumerated() {
                let note = item.ad?.indices.contains(index) == true ? item.ad?[index] : nil
                result.append(Pickup(date: date, name: names[code] ?? code, note: note))
            }
        }
        guard !result.isEmpty else { throw ProviderError.noData("Das AWIDO-Portal hat keine Termine für diese Adresse geliefert.") }
        return Array(Set(result)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }
}
