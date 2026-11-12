import Foundation

/// C-Trace-Portale (z. B. Bremer Stadtreinigung, Landkreis Augsburg, WZV Segeberg …):
/// Ort, Straße und Hausnummer kommen als Auswahlliste aus dem Portal (sonst Texteingabe), die Termine als ICS.
public struct CTraceProvider: WasteProvider {
    public let kind: ProviderKind = .cTrace
    public let serviceKey: String
    public var displayName: String { "C-Trace" }
    private let client: HTTPClient

    /// Woher die Portalseite ihre Auswahllisten holt (aus dem Abfallkalender.js des jeweiligen Portals, 12.11.2026).
    enum Lists {
        /// `Orte`, `Strassen?ort=`, `Hausnummern?ort=&strasse=` (Segeberg, Bayreuth, Arnsberg …)
        case plain
        /// dieselben Aufrufe unter `Data/` (Bremen)
        case data
        /// `OData.svc/Orte`, `OData.svc/Strassen` je Ort, `OData.svc/AktuelleObjekte` (Augsburg, Aurich …)
        case odata
        /// `OData.svc/AktuelleStrassen` ohne Ort (Dietzenbach, Oberursel)
        case odataCurrent
        /// `OData.svc/Strassen` ohne Ort (Landau, St. Wendel)
        case odataAll
    }

    /// Kennung → (Subdomain, voller Dienstname, ICS-Datei, fester Ort oder nil)
    struct Service { let subdomain: String; let name: String; let icsFile: String; let fixedCity: String?
        var lists = Lists.plain
        /// Aurich lehnt die lange Abfallarten-Liste mit 500 ab, das Portal selbst schickt keine.
        var sendsWasteTypes = true
        /// Portal führt keine aktuellen Termine mehr: Hinweis statt Auswahl, die ins Leere führt.
        var retired: (de: String, en: String)?
    }
    static let services: [String: Service] = [
        "bremenabfallkalender": Service(subdomain: "web", name: "bremenabfallkalender", icsFile: "cal", fixedCity: "Bremen", lists: .data),
        "augsburglandkreis": Service(subdomain: "web", name: "augsburglandkreis", icsFile: "cal", fixedCity: nil, lists: .odata),
        "segebergwzv-abfallkalender": Service(subdomain: "web", name: "segebergwzv-abfallkalender", icsFile: "cal", fixedCity: nil),
        "maintauberkreis-abfallkalender": Service(subdomain: "web", name: "maintauberkreis-abfallkalender", icsFile: "cal", fixedCity: nil),
        "dietzenbach": Service(subdomain: "web", name: "dietzenbach", icsFile: "cal", fixedCity: "Dietzenbach", lists: .odataCurrent),
        // Letzter Termin im Portal: 31.12.2025 (OData Abfuhrtermine, gemessen 12.11.2026); die EAW führt online nur den Untertaunus.
        "rheingauleerungen": Service(subdomain: "web", name: "rheingauleerungen", icsFile: "cal", fixedCity: nil, lists: .odata,
                                     retired: ("Das C-Trace-Portal für den Rheingau führt seit Ende 2025 keine Termine mehr. Die Rheingau-Gemeinden veröffentlichen ihre Termine bei Mein-Abfallkalender (z. B. eltville.mein-abfallkalender.online); für den Untertaunus „EAW Rheingau-Taunus-Kreis (Untertaunus)“ wählen.",
                                                     "The C-Trace portal for the Rheingau has had no dates since the end of 2025. The Rheingau towns publish their dates on Mein-Abfallkalender (e.g. eltville.mein-abfallkalender.online); for the Untertaunus choose “EAW Rheingau-Taunus-Kreis (Untertaunus)”.")),
        "grossgeraulandkreis-abfallkalender": Service(subdomain: "web", name: "grossgeraulandkreis-abfallkalender", icsFile: "cal", fixedCity: nil),
        "bayreuthstadt-abfallkalender": Service(subdomain: "web", name: "bayreuthstadt-abfallkalender", icsFile: "cal", fixedCity: "Bayreuth"),
        "arnsberg-abfallkalender": Service(subdomain: "web", name: "arnsberg-abfallkalender", icsFile: "cal", fixedCity: "Arnsberg"),
        "landau": Service(subdomain: "apps", name: "web.landau", icsFile: "downloadcal", fixedCity: "Landau", lists: .odataAll),
        // Letzter Termin im Portal: 03.01.2024 (OData Abfuhrtermine, gemessen 12.11.2026).
        "roth": Service(subdomain: "apps", name: "web.roth", icsFile: "cal", fixedCity: nil, lists: .odata,
                        retired: ("Das C-Trace-Portal des Landkreises Roth führt seit 2024 keine Termine mehr. Bitte den Eintrag „Landkreis Roth“ wählen.",
                                        "The C-Trace portal of Landkreis Roth has had no dates since 2024. Please choose the entry “Landkreis Roth”.")),
        "aurich-abfallkalender": Service(subdomain: "apps", name: "web.aurich-abfallkalender", icsFile: "cal", fixedCity: nil, lists: .odata, sendsWasteTypes: false),
        "stwendel": Service(subdomain: "apps", name: "web.stwendel", icsFile: "downloadcal", fixedCity: "St. Wendel", lists: .odataAll),
        "oberursel": Service(subdomain: "apps", name: "web.oberursel", icsFile: "cal", fixedCity: "Oberursel", lists: .odataCurrent),
    ]

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    private var service: Service {
        CTraceProvider.services[serviceKey] ?? Service(subdomain: "web", name: serviceKey, icsFile: "cal", fixedCity: nil)
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        if let retired = service.retired { throw ProviderError.noData(L10n.t(retired.de, retired.en)) }
        // Schritte: Ort (nur wenn nicht fest vorgegeben) → Straße → Hausnummer
        let place = service.fixedCity ?? selections.first?.title
        let stepIndex = selections.count + (service.fixedCity == nil ? 0 : 1)
        switch stepIndex {
        case 0:
            let places = (try? await placeNames()) ?? []
            guard !places.isEmpty else {
                return .text(title: SelectionStep.cityTitle, placeholder: L10n.t("Ort, z. B. Königsbrunn", "Town, e.g. Königsbrunn"))
            }
            return SelectionStep(title: SelectionStep.cityTitle, options: places.map { SelectionOption(id: $0, title: $0) })
        case 1:
            // Die Portale suchen nur nach dem vollen Namen; die ganze Liste lässt sich in der App nach Teilen durchsuchen.
            if let place, let streets = try? await streetNames(place: place), !streets.isEmpty {
                return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0, title: $0) })
            }
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname", "Street name"))
        case 2:
            // Eine Hausnummer, die das Portal nicht kennt, endet in HTTP 500 (Bremen, Aurich) oder nur in Sammelterminen (Arnsberg).
            if let place, let street = selections.last?.title,
               let numbers = try? await houseNumbers(place: place, street: street), !numbers.isEmpty {
                return SelectionStep(title: SelectionStep.houseNumberTitle, options: numbers.map { SelectionOption(id: $0, title: $0) })
            }
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
        return unique(raw)
    }

    private struct ObjectRows: Decodable {
        struct Row: Decodable { let HausNr: String?; let HausNrZus: String? }
        let d: [Row]
    }

    /// Hausnummern: einfache Liste `["2","2-10"]` oder OData `AktuelleObjekte` `{"d":[{"HausNr":"1","HausNrZus":"A"}]}`.
    static func parseHouseNumbers(_ data: Data) throws -> [String] {
        if let list = try? JSONDecoder().decode([String].self, from: data) { return unique(list) }
        return unique(try JSONDecoder().decode(ObjectRows.self, from: data).d.map { ($0.HausNr ?? "") + ($0.HausNrZus ?? "") })
    }

    private static func unique(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var base: String { "https://\(service.subdomain).c-trace.de/\(service.name)" }

    private static func literal(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }

    private func placeNames() async throws -> [String] {
        switch service.lists {
        case .plain: return try Self.parseNames(try await client.get("\(base)/Orte"))
        case .data: return try Self.parseNames(try await client.get("\(base)/Data/Orte"))
        case .odata:
            let order = service.name.contains("aurich") ? "&$expand=Gebiet&$orderby=Gebiet/Name,Name" : "&$orderby=Name"
            return try Self.parseNames(try await client.get("\(base)/OData.svc/Orte?$format=json\(order)"))
        case .odataCurrent, .odataAll: return []
        }
    }

    private func streetNames(place: String) async throws -> [String] {
        let url: String
        switch service.lists {
        case .plain: url = "\(base)/Strassen?ort=\(HTTPClient.query(place))"
        case .data: url = "\(base)/Data/Strassen?ort=\(HTTPClient.query(place))"
        case .odata:
            let parts = place.components(separatedBy: Self.areaSeparator)
            let filter = parts.count == 2
                ? "Ort/Gebiet/Name eq \(Self.literal(parts[0])) and Ort/Name eq \(Self.literal(parts[1]))"
                : "Ort/Name eq \(Self.literal(place))"
            url = "\(base)/OData.svc/Strassen?$format=json&$orderby=Name&$filter=" + HTTPClient.query(filter)
        case .odataCurrent: url = "\(base)/OData.svc/AktuelleStrassen?$format=json&strasse=" + HTTPClient.query("''")
        case .odataAll: url = "\(base)/OData.svc/Strassen?$format=json&$orderby=Name"
        }
        return try Self.parseNames(try await client.get(url))
    }

    private func houseNumbers(place: String, street: String) async throws -> [String] {
        let url: String
        switch service.lists {
        case .plain: url = "\(base)/Hausnummern?ort=\(HTTPClient.query(place))&strasse=\(HTTPClient.query(street))"
        case .data: url = "\(base)/Data/Hausnummern?ort=\(HTTPClient.query(place))&strasse=\(HTTPClient.query(street))"
        case .odata, .odataCurrent, .odataAll:
            var params = ["strasse": street]
            if service.lists == .odata {
                let parts = place.components(separatedBy: Self.areaSeparator)
                params["ort"] = parts.last ?? place
                if parts.count == 2 { params["gemeinde"] = parts[0] }
            }
            let query = params.sorted { $0.key < $1.key }.map { "\($0.key)=\(HTTPClient.query(Self.literal($0.value)))" }.joined(separator: "&")
            url = "\(base)/OData.svc/AktuelleObjekte?$format=json&\(query)"
        }
        return try Self.parseHouseNumbers(try await client.get(url))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        if let retired = service.retired { throw ProviderError.noData(L10n.t(retired.de, retired.en)) }
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
        let text: String
        do {
            text = try await client.string("\(base)/\(service.name)/\(sessionPath)abfallkalender/\(service.icsFile)?\(query)")
        } catch HTTPError.status(500, _) {
            // C-Trace antwortet mit 500, wenn es zur Adresse keinen Plan gibt; die Portalseite zeigt dann ebenfalls nichts
            // (Bremen „Irisweg 17“, 12.11.2026 – die einzige Hausnummer der Straße in der Portalliste).
            throw ProviderError.noData(L10n.t("Das Portal hat für diese Adresse keinen Abfuhrplan. Bitte eine Nachbar-Hausnummer versuchen oder beim Entsorger nachfragen.",
                                              "The portal has no collection plan for this address. Please try a neighbouring house number or ask the waste company."))
        }
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let events = ICS.parse(cleaned, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noDataGeneric }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary.replacingOccurrences(of: "Abfuhr: ", with: ""))) }
    }
}
