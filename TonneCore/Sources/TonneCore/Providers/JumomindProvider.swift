import Foundation

/// Jumomind / MyMüll-App: `https://{service}.jumomind.com/mmapp/api.php`.
/// Ablauf: Ort → (Straße) → (Hausnummer, wenn die Straße mehrere Bezirke hat) → Termine.
public struct JumomindProvider: WasteProvider {
    public let kind: ProviderKind = .jumomind
    public let serviceKey: String
    public var displayName: String { serviceKey == "mymuell" ? "MyMüll" : "Jumomind" }
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    private var api: String { "https://\(serviceKey).jumomind.com/mmapp/api.php" }

    private struct City: Decodable {
        let id: FlexibleID; let name: String; let area_id: FlexibleID; let has_streets: FlexibleBool
    }
    private struct Street: Decodable {
        let name: String; let area_id: FlexibleID; let houseNumbers: [[FlexibleID]]?
    }
    private struct Trash: Decodable { let name: String; let title: String }
    private struct Entry: Decodable { let day: String; let trash_name: String }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let cities: [City] = try await client.json("\(api)?r=cities_web")
            // ID kodiert: city:<cityId>:<areaId>:<hasStreets>
            return SelectionStep(title: SelectionStep.cityTitle, options: cities.map {
                SelectionOption(id: "city:\($0.id.value):\($0.area_id.value):\($0.has_streets.value ? 1 : 0)", title: $0.name)
            })
        case 1:
            let parts = selections[0].id.split(separator: ":").map(String.init)
            guard parts.count == 4, parts[3] == "1" else { return nil }
            let streets: [Street] = try await client.json("\(api)?r=streets&city_id=\(parts[1])")
            if streets.isEmpty { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.enumerated().map { index, street in
                let numbers = street.houseNumbers ?? []
                let encodedNumbers = numbers.compactMap { pair -> String? in
                    guard pair.count >= 2 else { return nil }
                    return "\(pair[0].value)=\(pair[1].value)"
                }.joined(separator: "|")
                return SelectionOption(id: "street:\(street.area_id.value):\(index):\(encodedNumbers)", title: street.name)
            })
        case 2:
            // Hausnummern nur, wenn die Straße mehrere Bezirke abdeckt
            let parts = selections[1].id.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, !parts[3].isEmpty else { return nil }
            let pairs = parts[3].split(separator: "|").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }.filter { $0.count == 2 }
            let distinctAreas = Set(pairs.map { $0[1] })
            guard distinctAreas.count > 1 else { return nil }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: pairs.map { SelectionOption(id: "house:\($0[1])", title: $0[0]) })
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let city = selections.first else { throw ProviderError.invalidSelection("Bitte einen Ort wählen.") }
        let cityParts = city.id.split(separator: ":").map(String.init)
        guard cityParts.count == 4 else { throw ProviderError.invalidSelection("Ungültige Auswahl.") }
        var areaID = cityParts[2]
        if selections.count >= 2 {
            let streetParts = selections[1].id.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            if streetParts.count >= 2 { areaID = streetParts[1] }
            if let pairs = streetParts.count == 4 ? streetParts[3].split(separator: "|").map({ $0.split(separator: "=", maxSplits: 1).map(String.init) }).filter({ $0.count == 2 }) : nil,
               pairs.count == 1 {
                areaID = pairs[0][1]
            }
        }
        if selections.count >= 3, selections[2].id.hasPrefix("house:") {
            areaID = String(selections[2].id.dropFirst("house:".count))
        }
        let cityID = cityParts[1]
        let trash: [Trash] = try await client.json("\(api)?r=trash&city_id=\(cityID)&area_id=\(areaID)")
        var titles: [String: String] = [:]
        for item in trash { titles[item.name] = NameCleaner.clean(item.title) }
        let entries: [Entry] = try await client.json("\(api)?r=dates/0&city_id=\(cityID)&area_id=\(areaID)&ws=3")
        let pickups = entries.compactMap { entry -> Pickup? in
            guard let date = Days.parse(entry.day, calendar: calendar) else { return nil }
            return Pickup(date: date, name: titles[entry.trash_name] ?? NameCleaner.clean(entry.trash_name))
        }
        guard !pickups.isEmpty else { throw ProviderError.noData("Jumomind hat keine Termine für diese Adresse geliefert.") }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }
}

/// Manche Portale liefern IDs mal als Zahl, mal als String.
public struct FlexibleID: Decodable, Hashable {
    public let value: String
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = String(int) }
        else if let string = try? container.decode(String.self) { value = string }
        else if let double = try? container.decode(Double.self) { value = String(Int(double)) }
        else { value = "" }
    }
}

public struct FlexibleBool: Decodable, Hashable {
    public let value: Bool
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) { value = bool }
        else if let int = try? container.decode(Int.self) { value = int != 0 }
        else if let string = try? container.decode(String.self) { value = ["1", "true", "yes"].contains(string.lowercased()) }
        else { value = false }
    }
}
