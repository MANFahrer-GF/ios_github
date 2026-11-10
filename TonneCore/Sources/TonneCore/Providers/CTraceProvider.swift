import Foundation

/// C-Trace-Portale (z. B. Bremer Stadtreinigung, Landkreis Augsburg, WZV Segeberg …):
/// Ort und Straße kommen als Auswahlliste aus dem Portal (sonst Texteingabe), die Termine als ICS.
public struct CTraceProvider: WasteProvider {
    public let kind: ProviderKind = .cTrace
    public let serviceKey: String
    public var displayName: String { "C-Trace" }
    private let client: HTTPClient

    /// Kennung → (Subdomain, voller Dienstname, ICS-Datei, fester Ort oder nil)
    struct Service { let subdomain: String; let name: String; let icsFile: String; let fixedCity: String?
        /// Orte/Straßen kommen über OData.svc statt über die einfachen Listen-Aufrufe (Orte, Strassen).
        var odata = false
        /// Aurich lehnt die lange Abfallarten-Liste mit 500 ab, das Portal selbst schickt keine.
        var sendsWasteTypes = true
    }
    static let services: [String: Service] = [
        "bremenabfallkalender": Service(subdomain: "web", name: "bremenabfallkalender", icsFile: "cal", fixedCity: "Bremen"),
        "augsburglandkreis": Service(subdomain: "web", name: "augsburglandkreis", icsFile: "cal", fixedCity: nil, odata: true),
        "segebergwzv-abfallkalender": Service(subdomain: "web", name: "segebergwzv-abfallkalender", icsFile: "cal", fixedCity: nil),
        "maintauberkreis-abfallkalender": Service(subdomain: "web", name: "maintauberkreis-abfallkalender", icsFile: "cal", fixedCity: nil),
        "dietzenbach": Service(subdomain: "web", name: "dietzenbach", icsFile: "cal", fixedCity: "Dietzenbach"),
        "rheingauleerungen": Service(subdomain: "web", name: "rheingauleerungen", icsFile: "cal", fixedCity: nil, odata: true),
        "grossgeraulandkreis-abfallkalender": Service(subdomain: "web", name: "grossgeraulandkreis-abfallkalender", icsFile: "cal", fixedCity: nil),
        "bayreuthstadt-abfallkalender": Service(subdomain: "web", name: "bayreuthstadt-abfallkalender", icsFile: "cal", fixedCity: "Bayreuth"),
        "arnsberg-abfallkalender": Service(subdomain: "web", name: "arnsberg-abfallkalender", icsFile: "cal", fixedCity: "Arnsberg"),
        "landau": Service(subdomain: "apps", name: "web.landau", icsFile: "downloadcal", fixedCity: "Landau"),
        "roth": Service(subdomain: "apps", name: "web.roth", icsFile: "cal", fixedCity: nil, odata: true),
        "aurich-abfallkalender": Service(subdomain: "apps", name: "web.aurich-abfallkalender", icsFile: "cal", fixedCity: nil, odata: true, sendsWasteTypes: false),
        "stwendel": Service(subdomain: "apps", name: "web.stwendel", icsFile: "downloadcal", fixedCity: "St. Wendel"),
        "oberursel": Service(subdomain: "apps", name: "web.oberursel", icsFile: "cal", fixedCity: "Oberursel"),
    ]

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    private var service: Service {
        CTraceProvider.services[serviceKey] ?? Service(subdomain: "web", name: serviceKey, icsFile: "cal", fixedCity: nil)
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        // Schritte: Ort (nur wenn nicht fest vorgegeben) → Straße → Hausnummer
        let stepIndex = selections.count + (service.fixedCity == nil ? 0 : 1)
        switch stepIndex {
        case 0:
            let places = (try? await names("Orte", filter: nil)) ?? []
            guard !places.isEmpty else {
                return .text(title: SelectionStep.cityTitle, placeholder: L10n.t("Ort, z. B. Königsbrunn", "Town, e.g. Königsbrunn"))
            }
            return SelectionStep(title: SelectionStep.cityTitle, options: places.map { SelectionOption(id: $0, title: $0) })
        case 1:
            if service.fixedCity == nil, let place = selections.first?.title,
               let streets = try? await names("Strassen", filter: place), !streets.isEmpty {
                return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0, title: $0) })
            }
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname", "Street name"))
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: "1")
        default:
            return nil
        }
    }

    // MARK: Listen

    /// Aurich führt Gemeinde und Ort getrennt; im Auswahltext steht „Gemeinde / Ort“.
    static let areaSeparator = " / "

    private struct ODataRows: Decodable {
        struct Row: Decodable { struct Area: Decodable { let Name: String? }
            let Name: String?; let Gebiet: Area? }
        let d: [Row]
    }

    /// Namen aus einer Portalantwort: einfache Liste `["a","b"]` oder OData `{"d":[{"Name":…}]}`.
    /// Leere und doppelte Namen fallen weg, die Reihenfolge bleibt.
    static func parseNames(_ data: Data) throws -> [String] {
        let raw: [String]
        if let list = try? JSONDecoder().decode([String].self, from: data) {
            raw = list
        } else {
            raw = try JSONDecoder().decode(ODataRows.self, from: data).d.compactMap { row in
                let name = row.Name ?? ""
                guard let area = row.Gebiet?.Name, !area.isEmpty else { return name }
                if area == "Musterstadt" || area == "Emden" { return nil }
                return name.isEmpty || name == area ? area : area + areaSeparator + name
            }
        }
        var seen = Set<String>()
        return raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Ort-Liste (`filter == nil`) oder Straßenliste für den gewählten Ort.
    private func names(_ table: String, filter place: String?) async throws -> [String] {
        let base = "https://\(service.subdomain).c-trace.de/\(service.name)"
        let url: String
        if service.odata {
            func literal(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
            var query = "$format=json"
            if let place {
                let parts = place.components(separatedBy: Self.areaSeparator)
                let filter = parts.count == 2
                    ? "Ort/Gebiet/Name eq \(literal(parts[0])) and Ort/Name eq \(literal(parts[1]))"
                    : "Ort/Name eq \(literal(place))"
                query += "&$orderby=Name&$filter=" + HTTPClient.query(filter)
            } else {
                query += service.name.contains("aurich") ? "&$expand=Gebiet&$orderby=Gebiet/Name,Name" : "&$orderby=Name"
            }
            url = "\(base)/OData.svc/\(table)?\(query)"
        } else {
            url = "\(base)/\(table)" + (place.map { "?ort=\(HTTPClient.query($0))" } ?? "")
        }
        return try Self.parseNames(try await client.get(url))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        var values = selections.map(\.title)
        if let fixed = service.fixedCity { values.insert(fixed, at: 0) }
        guard values.count >= 3 else { throw ProviderError.selectAddressFirst }
        let base = "https://\(service.subdomain).c-trace.de"
        // Erst die Sitzung holen (Weiterleitung enthält die Session-ID im Pfad)
        var sessionPath = ""
        if let final = try? await client.finalURL("\(base)/\(service.name)/Abfallkalender"),
           let segment = final.path.split(separator: "/").first(where: { $0.hasPrefix("(S(") }) {
            sessionPath = String(segment) + "/"
        }
        let area = values[0].components(separatedBy: Self.areaSeparator)
        var fields = ["Ort": area.last ?? values[0], "Gemeinde": area.first ?? values[0], "Strasse": values[1], "Hausnr": values[2]]
        if service.sendsWasteTypes { fields["Abfall"] = (0..<300).map(String.init).joined(separator: "|") }
        let query = fields.map { "\($0.key)=\(HTTPClient.query($0.value))" }.joined(separator: "&")
        let text = try await client.string("\(base)/\(service.name)/\(sessionPath)abfallkalender/\(service.icsFile)?\(query)")
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let events = ICS.parse(cleaned, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noDataGeneric }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary.replacingOccurrences(of: "Abfuhr: ", with: ""))) }
    }
}
