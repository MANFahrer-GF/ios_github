import Foundation

/// Bürgerportal (C-Trace OData): Alb-Donau-Kreis, Cochem-Zell, MZV Biedenkopf, Bedburg, Kleve.
/// Auswahl Ort (mit Ortsteil) → Straße → Hausnummer (Eingabe; ohne sie liefern manche Portale nur Sammeltermine)
/// → Termine (`AbfuhrtermineAbJahr`).
public struct BuergerportalProvider: WasteProvider {
    public static let operators: [String: String] = [
        "alb_donau": "https://buerger-portal-albdonaukreisabfallwirtschaft.azurewebsites.net/api",
        "cochem_zell": "https://buerger-portal-cochemzell.azurewebsites.net/api",
        "biedenkopf": "https://biedenkopfmzv.buergerportal.digital/api",
        "bedburg": "https://buerger-portal-bedburg.azurewebsites.net/api",
        "klevestadt": "https://buerger-portal-klevestadt.azurewebsites.net/api",
        "neu_ulm": "https://buerger-portal-neuulmlandkreis.azurewebsites.net/api",
    ]

    public let kind: ProviderKind = .buergerportal
    public let serviceKey: String
    public var displayName: String { "Bürgerportal" }
    private let client: HTTPClient

    public init(operator op: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = op
        self.client = client
    }

    private var api: String? { Self.operators[serviceKey] }

    private struct List<T: Decodable>: Decodable { let d: [T] }
    private struct Place: Decodable { let OrteId: Int; let Ortsname: String; let Ortsteilname: String? }
    private struct Street: Decodable { let StrassenId: Int; let Name: String }
    private struct Item: Decodable { let Termin: String; let Abfuhrplan: Plan }
    private struct Plan: Decodable { let GefaesstarifArt: Tariff }
    private struct Tariff: Decodable { let Abfallart: Kind }
    private struct Kind: Decodable { let Name: String }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let api else { throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }
        switch selections.count {
        case 0:
            let places: List<Place> = try await client.json("\(api)/OrteMitOrtsteilen")
            let options = places.d.map { place -> SelectionOption in
                let title = place.Ortsteilname.map { "\(place.Ortsname) – \($0)" } ?? place.Ortsname
                return SelectionOption(id: "\(place.OrteId)|\(place.Ortsteilname ?? "")", title: title)
            }
            return SelectionStep(title: SelectionStep.cityTitle, options: options.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        case 1:
            let (placeID, district) = Self.split(selections[0].id)
            let districtFilter = district.isEmpty ? "null" : "'\(district.replacingOccurrences(of: "'", with: "''"))'"
            let filter = "Ort/OrteId eq \(placeID) and OrtsteilName eq \(districtFilter)"
            let streets: List<Street> = try await client.json("\(api)/Strassen?$filter=\(HTTPClient.query(filter))&$orderby=\(HTTPClient.query("Name asc"))")
            guard !streets.d.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.d.map { SelectionOption(id: String($0.StrassenId), title: $0.Name) })
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 3", "e.g. 3"))
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let api, selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let placeID = Self.split(selections[0].id).0
        let number = selections.count > 2 ? selections[2].title.trimmingCharacters(in: .whitespaces) : ""
        let houseParam = number.isEmpty ? "" : "&hausNr=" + HTTPClient.query("'\(number.replacingOccurrences(of: "'", with: "''"))'")
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            // Neuere Portale heißen „VolumenObj“, ältere „Volumen“ – bei Fehler die andere Variante probieren.
            for volume in ["VolumenObj", "Volumen"] {
                let expand = "Abfuhrplan,Abfuhrplan/GefaesstarifArt/Abfallart,Abfuhrplan/GefaesstarifArt/\(volume)"
                let url = "\(api)/AbfuhrtermineAbJahr?$expand=\(HTTPClient.query(expand))&orteId=\(placeID)&strassenId=\(selections[1].id)&jahr=\(target)\(houseParam)"
                guard let items: List<Item> = try? await client.json(url) else { continue }
                result += items.d.compactMap { item in
                    Self.date(item.Termin, calendar: calendar).map { Pickup(date: $0, name: NameCleaner.clean(item.Abfuhrplan.GefaesstarifArt.Abfallart.Name)) }
                }
                break
            }
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date < $1.date }
    }

    /// „Allmendingen, Allee 3“
    public func label(for selections: [SelectionOption]) -> String {
        guard selections.count >= 2 else { return selections.map(\.title).joined(separator: ", ") }
        let street = ([selections[1].title] + (selections.count > 2 ? [selections[2].title] : [])).joined(separator: " ")
        return "\(selections[0].title), \(street)"
    }

    private static func split(_ id: String) -> (String, String) {
        let parts = id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }

    /// „/Date(1767916800000)/“ (Mitternacht UTC) → Kalendertag.
    static func date(_ termin: String, calendar: Calendar) -> Date? {
        guard let ms = HTMLText.firstMatch(#"(-?\d+)"#, in: termin, group: 1).flatMap(Double.init) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: ms / 1000))
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return Days.parse(String(format: "%04d-%02d-%02d", y, m, d), calendar: calendar)
    }
}
