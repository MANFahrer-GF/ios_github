import Foundation

/// Bürgerportal mit Abfallkalender nach Tonnenfarbe (AWL Neuss; dieselbe Software läuft bei weiteren Entsorgern).
/// Auswahl Straße (geteilte Straßen stehen mit ihrem Hausnummernbereich als eigene Zeile in der Liste) → Termine.
/// `calendar?isYear=true` liefert ein ganzes Jahr: `{"0-2026": {"3": ["grau", "gelb"]}}`, der Monat zählt ab 0.
public struct CalendarPortalProvider: WasteProvider {
    public static let operators: [String: String] = [
        "awl_neuss": "https://buergerportal.awl-neuss.de/api/v1",
    ]

    /// Bezeichnungen wie in der Legende des Portals („Restmülltonne (pink)“).
    static let names: [String: String] = [
        "grau": "Restmülltonne (grau)", "pink": "Restmülltonne (pink)", "magenta": "Restmülltonne (magenta)",
        "weiss": "Restmülltonne (weiß)", "braun": "Biotonne", "blau": "Papiertonne", "gelb": "Gelbe Tonne",
    ]

    public let kind: ProviderKind = .calendarPortal
    public let serviceKey: String
    public var displayName: String { L10n.t("Bürgerportal", "Citizen portal") }
    private let client: HTTPClient

    public init(operator op: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = op
        self.client = client
    }

    private var api: String? { Self.operators[serviceKey] }

    struct Street: Decodable { let strasseNummer: Int; let strasseBezeichnung: String }
    typealias Year = [String: [String: [String]]]

    static func streetOptions(_ streets: [Street]) -> [SelectionOption] {
        streets.map { SelectionOption(id: "street:\($0.strasseNummer)", title: $0.strasseBezeichnung) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Termine eines Jahres; unbekannte Farben bleiben mit ihrem Namen sichtbar, statt still zu fehlen.
    static func pickups(_ year: Year, calendar: Calendar) -> [Pickup] {
        var result: [Pickup] = []
        for (key, days) in year {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            for (day, colors) in days {
                guard let dayNumber = Int(day),
                      let date = calendar.date(from: DateComponents(year: parts[1], month: parts[0] + 1, day: dayNumber)),
                      calendar.component(.month, from: date) == parts[0] + 1 else { continue }
                for color in Set(colors) {
                    result.append(Pickup(date: date, name: names[color] ?? color))
                }
            }
        }
        return result.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let api else { throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }
        guard selections.isEmpty else { return nil }
        let streets: [Street] = try await client.json("\(api)/calendar/townarea-streets")
        guard !streets.isEmpty else { throw ProviderError.noData(L10n.t("Das Portal liefert keine Straßen.", "The portal returned no streets.")) }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.streetOptions(streets))
    }

    private func year(_ year: Int, street: String, api: String, calendar: Calendar) async throws -> [Pickup] {
        let url = "\(api)/calendar?startMonth=\(HTTPClient.query("Jan \(year)"))&streetNum=\(street)&isTreeMonthRange=false&isYear=true&homeNumber="
        let data: Year = try await client.json(url)
        return Self.pickups(data, calendar: calendar)
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let api else { throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal.")) }
        guard let street = selections.first(where: { $0.id.hasPrefix("street:") })?.id.dropFirst("street:".count), Int(street) != nil else {
            throw ProviderError.selectAddressFirst
        }
        let current = calendar.component(.year, from: Date())
        // Das laufende Jahr muss kommen; das Folgejahr stellt das Portal erst zum Jahresende bereit.
        var result = try await year(current, street: String(street), api: api, calendar: calendar)
        result += (try? await year(current + 1, street: String(street), api: api, calendar: calendar)) ?? []
        guard !result.isEmpty else { throw ProviderError.noData(L10n.t("Für diese Straße liegen keine Termine vor.", "No dates for this street.")) }
        return result
    }
}
