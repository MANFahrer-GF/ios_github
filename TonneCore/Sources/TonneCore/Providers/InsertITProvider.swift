import Foundation

/// Insert IT „BmsAbfallkalender“ – Mannheim, Kassel, Lübeck, Krefeld, Herne, Offenbach, Hattingen.
/// Ablauf: Straßenname eintippen → Straße wählen → Hausnummer wählen → ICS je Jahr.
public struct InsertITProvider: WasteProvider {
    /// serviceKey → Pfad unter https://www.insert-it.de/
    public static let cities: [String: String] = [
        "Hattingen": "BmsAbfallkalenderHattingen",
        "Herne": "BmsAbfallkalenderHerne",
        "Kassel": "BmsAbfallkalenderKassel",
        "Krefeld": "BmsAbfallkalenderKrefeld",
        "Luebeck": "BmsAbfallkalenderLuebeck",
        "Mannheim": "BmsAbfallkalenderMannheim",
        "Offenbach": "BmsAbfallkalenderOffenbach",
    ]

    public let kind: ProviderKind = .insertIT
    public let serviceKey: String
    public var displayName: String { "Insert IT" }
    private let client: HTTPClient

    public init(city: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = city
        self.client = client
    }

    private var base: String? { Self.cities[serviceKey].map { "https://www.insert-it.de/\($0)" } }

    /// Bis zu so vielen Treffern wird je Straße nachgesehen, ob es Hausnummern gibt (eine Abfrage je Straße)
    static let filterLimit = 12

    private struct Street: Decodable { let ID: Int; let Name: String }
    private struct Location: Decodable { let ID: Int; let Text: String }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let base else { throw ProviderError.notSupported(L10n.t("Unbekannte Stadt.", "Unknown city.")) }
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname, z. B. Kaiserstraße", "Street name"))
        case 1:
            let streets = try await searchStreets(base: base, text: selections[0].title)
            guard !streets.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Keine Straße gefunden. Bitte anders schreiben.", "No street found. Please try another spelling."))
            }
            // Kurze Trefferlisten: Straßen ohne Hausnummern (Plätze, „Hauptbahnhof“) gleich weglassen – dort gibt es keine Tonnen
            // und sie standen zuvor oben in der Liste (Lübeck „Haupt“: Hauptbahnhof, Hauptstraße; Offenbach: Haupteingangstraße)
            var usable = streets
            if streets.count > 1, streets.count <= Self.filterLimit {
                let client = self.client
                let withNumbers = await withTaskGroup(of: (Int, Bool?).self) { group -> (has: Set<Int>, failed: Bool) in
                    for street in streets {
                        group.addTask {
                            let found: [Location]? = try? await client.json("\(base)/Main/GetLocations?streetId=\(street.ID)")
                            return (street.ID, found.map { !$0.isEmpty })
                        }
                    }
                    var ok = Set<Int>(), failed = false
                    for await (id, has) in group {
                        if let has { if has { ok.insert(id) } } else { failed = true }
                    }
                    return (ok, failed)
                }
                // Abfragen gescheitert: Liste unverändert lassen; sonst nur Straßen mit Hausnummern, und keine davon ist ein Fehler
                if !withNumbers.failed {
                    guard !withNumbers.has.isEmpty else { throw Self.noStreetWithNumbers(typed: selections[0].title) }
                    usable = streets.filter { withNumbers.has.contains($0.ID) }
                }
            }
            return SelectionStep(title: SelectionStep.streetTitle, options: usable.map { SelectionOption(id: String($0.ID), title: $0.Name) })
        case 2:
            let locations: [Location] = try await client.json("\(base)/Main/GetLocations?streetId=\(selections[1].id)")
            // Das Portal listet auch Straßen ohne Hausnummern (Lübeck „Hauptstraße“, Kassel „Kirchplatz“, 12.11.2026) – dort gibt es keine Termine
            guard !locations.isEmpty else { throw Self.noHouseNumbers(selections[1].title) }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: locations.map { SelectionOption(id: String($0.ID), title: $0.Text) })
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let base, selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            guard let text = try? await client.string("\(base)/Main/Calender?bmsLocationId=\(selections[2].id)&year=\(target)") else { continue }
            result += ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: Self.cleanName($0.summary)) }
        }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(result)).sorted { $0.date < $1.date }
    }

    /// Manche Städte kürzen ab („Bahnhofstr.“). Darum nacheinander: Eingabe, „…str“, Wortanfang.
    private func searchStreets(base: String, text: String) async throws -> [Street] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        var terms = [typed]
        let short = typed.replacingOccurrences(of: #"(?i)(straße|strasse|str\.)$"#, with: "str", options: .regularExpression)
        if short != typed { terms.append(short) }
        if let first = typed.split(separator: " ").first, first.count > 5 { terms.append(String(first.prefix(5))) }
        for term in terms {
            let streets: [Street] = try await client.json("\(base)/Main/GetStreets?text=\(HTTPClient.query(term))")
            if !streets.isEmpty { return streets }
        }
        return []
    }

    static func noStreetWithNumbers(typed: String) -> ProviderError {
        .invalidSelection(L10n.t("Zu „\(typed)“ führt das Portal nur Straßen ohne Hausnummern (Plätze, Bahnhöfe). Bitte anders schreiben.",
                                 "The portal lists only streets without house numbers for “\(typed)”. Please try another spelling."))
    }

    static func noHouseNumbers(_ street: String) -> ProviderError {
        .invalidSelection(L10n.t("Zu „\(street)“ führt das Portal keine Hausnummern, also auch keine Tonnen (oft ein Platz oder eine Straße ohne Wohnhäuser). Bitte die Straße der Hausanschrift wählen.",
                                 "The portal lists no house numbers for “\(street)”, so there are no bins. Please choose the street of your address."))
    }

    /// Label ohne den Suchtext: „Kaiserstraße 1“.
    public func label(for selections: [SelectionOption]) -> String {
        selections.dropFirst().map(\.title).joined(separator: " ")
    }

    /// „Leerung: Biomüll (Kaiserstraße 1)“ → „Biomüll“; Mannheims Kurzformen ausgeschrieben.
    static func cleanName(_ summary: String) -> String {
        var name = summary.replacingOccurrences(of: #"^\s*Leerung:\s*"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s*\([^()]*\)\s*$"#, with: "", options: .regularExpression)
        let mannheim = ["Rest": "Restmüll", "Wertstoff": "Wertstofftonne", "Bio": "Biomüll", "Papier": "Altpapier"]
        return NameCleaner.clean(mannheim[name.trimmingCharacters(in: .whitespaces)] ?? name)
    }
}
