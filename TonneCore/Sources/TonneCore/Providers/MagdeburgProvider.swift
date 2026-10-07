import Foundation

/// SAB Magdeburg: Straßenliste von sab.ssl.metageneric.de, Termine als ICS je „Straße Hausnummer“
/// über st-magdeburg.server.smart-village.app.
public struct MagdeburgProvider: WasteProvider {
    public let kind: ProviderKind = .magdeburg
    public let serviceKey: String = "magdeburg"
    public var displayName: String { "SAB Magdeburg" }
    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient()) { self.client = client }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string("https://sab.ssl.metageneric.de/app/sab_i_tp/index.php")
            let streets = Array(Set(HTMLText.matches(#"option value="([^"]+)""#, in: html).compactMap(\.first).map(HTMLText.decodeEntities)))
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0, title: $0) })
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 10 (kann leer bleiben)", "e.g. 10 (optional)"))
        default:
            return nil
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first?.id else { throw ProviderError.selectAddressFirst }
        let number = selections.count > 1 ? selections[1].title.trimmingCharacters(in: .whitespaces) : ""
        // Mit Hausnummer genauer; kennt das Portal die Nummer nicht, gilt die ganze Straße.
        for query in number.isEmpty ? [street] : ["\(street) \(number)", street] {
            let url = "https://st-magdeburg.server.smart-village.app/waste_calendar/export?street=\(HTTPClient.query(query))&city=Magdeburg"
            guard let text = try? await client.string(url) else { continue }
            let pickups = ICS.parse(text, calendar: calendar).map { event in
                Pickup(date: event.date, name: NameCleaner.clean(event.summary.replacingOccurrences(of: "Abfallkalender: ", with: "")))
            }
            if !pickups.isEmpty { return Array(Set(pickups)).sorted { $0.date < $1.date } }
        }
        throw ProviderError.noDataGeneric
    }

    public func label(for selections: [SelectionOption]) -> String {
        "Magdeburg, " + selections.map(\.title).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
