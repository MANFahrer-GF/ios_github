import Foundation

/// AbfallPlus / abfall.io – ältere Widget-Schnittstelle (api.abfall.io, HTML-Formulare).
/// Der Server merkt sich den Zustand in versteckten Feldern; deshalb wird die Auswahlkette
/// bei jedem Schritt vom Anfang an wiederholt (Kommune → Bezirk → Straße → Hausnummer).
public struct AbfallIOLegacyProvider: WasteProvider {
    public let kind: ProviderKind = .abfallIOLegacy
    public let serviceKey: String
    public var displayName: String { "AbfallPlus" }
    private let client: HTTPClient
    private static let modus = "d6c5855a62cf32a4dadbc2831f0f295f"
    private static let fieldOrder: [(field: String, action: String, title: String)] = [
        ("f_id_kommune", "auswahl_kommune_set", "Ort"),
        ("f_id_bezirk", "auswahl_bezirk_set", "Ortsteil"),
        ("f_id_strasse", "auswahl_strasse_set", "Straße"),
        ("f_id_strasse_hnr", "auswahl_hnr_set", "Hausnummer"),
    ]

    public init(key: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = key
        self.client = client
    }

    private func post(_ action: String, _ fields: [(String, String)]) async throws -> String {
        let url = "https://api.abfall.io?key=\(serviceKey)&modus=\(AbfallIOLegacyProvider.modus)&waction=\(action)"
        let data = try await client.postForm(url, fields: fields)
        return HTTPClient.text(from: data)
    }

    /// Spielt die bisherigen Auswahlen durch und liefert Formularzustand + letztes HTML.
    private func replay(_ selections: [SelectionOption]) async throws -> (fields: [(String, String)], html: String) {
        var html = try await post("init", [])
        var state: [String: String] = [:]
        var order: [String] = []
        func merge(_ html: String) {
            for (name, value) in HTMLText.hiddenInputs(in: html) {
                if state[name] == nil { order.append(name) }
                state[name] = value
            }
        }
        merge(html)
        for selection in selections {
            let parts = selection.id.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let step = AbfallIOLegacyProvider.fieldOrder.first(where: { $0.field == parts[0] }) else { continue }
            if state[parts[0]] == nil { order.append(parts[0]) }
            state[parts[0]] = parts[1]
            html = try await post(step.action, order.map { ($0, state[$0] ?? "") })
            merge(html)
        }
        return (order.map { ($0, state[$0] ?? "") }, html)
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        let (_, html) = try await replay(selections)
        let chosen = Set(selections.compactMap { $0.id.split(separator: ":").first.map(String.init) })
        for step in AbfallIOLegacyProvider.fieldOrder where !chosen.contains(step.field) {
            let options = HTMLText.options(ofSelect: step.field, in: html).filter { $0.value != "0" && !$0.value.isEmpty }
            if !options.isEmpty {
                return SelectionStep(title: step.title, options: options.map { SelectionOption(id: "\(step.field):\($0.value)", title: $0.label) })
            }
        }
        return nil
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        var (fields, html) = try await replay(selections)
        // Alle Abfallarten anhaken
        let types = HTMLText.matches(#"name="f_id_abfalltyp_(\d+)"[^>]*value="(\d+)""#, in: html)
        for type in types where type.count == 2 { fields.append(("f_id_abfalltyp_\(type[0])", type[1])) }
        fields.append(("f_abfallarten_index_max", String(types.count)))
        fields.append(("f_abfallarten", types.map { $0[1] }.joined(separator: ",")))
        fields.append(("f_export_als", "ics"))
        var periods = HTMLText.options(ofSelect: "f_zeitraum", in: html).map(\.value).filter { !$0.isEmpty }
        if periods.isEmpty {
            let year = calendar.component(.year, from: Date())
            periods = ["\(year)0101-\(year)1231", "\(year + 1)0101-\(year + 1)1231"]
        }
        var pickups: [Pickup] = []
        for period in periods {
            let text = try await post("export_ics", fields + [("f_zeitraum", period)])
            guard text.contains("BEGIN:VCALENDAR") else { continue }
            let cleaned = text.replacingOccurrences(of: #"<br.*|<b.*"#, with: "", options: .regularExpression)
            pickups += ICS.parse(cleaned, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary), note: $0.location) }
        }
        guard !pickups.isEmpty else { throw ProviderError.noData("AbfallPlus hat keine Termine für diese Adresse geliefert.") }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }
}
