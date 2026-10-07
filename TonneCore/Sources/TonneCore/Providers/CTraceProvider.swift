import Foundation

/// C-Trace-Portale (z. B. Bremer Stadtreinigung, Landkreis Augsburg, WZV Segeberg …):
/// Ort/Straße/Hausnummer werden eingegeben, die Termine kommen als ICS.
public struct CTraceProvider: WasteProvider {
    public let kind: ProviderKind = .cTrace
    public let serviceKey: String
    public var displayName: String { "C-Trace" }
    private let client: HTTPClient

    /// Kennung → (Subdomain, voller Dienstname, ICS-Datei, fester Ort oder nil)
    struct Service { let subdomain: String; let name: String; let icsFile: String; let fixedCity: String? }
    static let services: [String: Service] = [
        "bremenabfallkalender": Service(subdomain: "web", name: "bremenabfallkalender", icsFile: "cal", fixedCity: "Bremen"),
        "augsburglandkreis": Service(subdomain: "web", name: "augsburglandkreis", icsFile: "cal", fixedCity: nil),
        "segebergwzv-abfallkalender": Service(subdomain: "web", name: "segebergwzv-abfallkalender", icsFile: "cal", fixedCity: nil),
        "maintauberkreis-abfallkalender": Service(subdomain: "web", name: "maintauberkreis-abfallkalender", icsFile: "cal", fixedCity: nil),
        "dietzenbach": Service(subdomain: "web", name: "dietzenbach", icsFile: "cal", fixedCity: "Dietzenbach"),
        "rheingauleerungen": Service(subdomain: "web", name: "rheingauleerungen", icsFile: "cal", fixedCity: nil),
        "grossgeraulandkreis-abfallkalender": Service(subdomain: "web", name: "grossgeraulandkreis-abfallkalender", icsFile: "cal", fixedCity: nil),
        "bayreuthstadt-abfallkalender": Service(subdomain: "web", name: "bayreuthstadt-abfallkalender", icsFile: "cal", fixedCity: "Bayreuth"),
        "arnsberg-abfallkalender": Service(subdomain: "web", name: "arnsberg-abfallkalender", icsFile: "cal", fixedCity: "Arnsberg"),
        "landau": Service(subdomain: "apps", name: "web.landau", icsFile: "downloadcal", fixedCity: "Landau"),
        "roth": Service(subdomain: "apps", name: "web.roth", icsFile: "cal", fixedCity: nil),
        "aurich-abfallkalender": Service(subdomain: "apps", name: "web.aurich-abfallkalender", icsFile: "cal", fixedCity: nil),
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
            return .text(title: SelectionStep.cityTitle, placeholder: L10n.t("Ort, z. B. Königsbrunn", "Town, e.g. Königsbrunn"))
        case 1:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname", "Street name"))
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: "1")
        default:
            return nil
        }
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
        let all = (0..<300).map(String.init).joined(separator: "|")
        let query = ["Ort": values[0], "Gemeinde": values[0], "Strasse": values[1], "Hausnr": values[2], "Abfall": all]
            .map { "\($0.key)=\(HTTPClient.query($0.value))" }.joined(separator: "&")
        let text = try await client.string("\(base)/\(service.name)/\(sessionPath)abfallkalender/\(service.icsFile)?\(query)")
        let cleaned = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let events = ICS.parse(cleaned, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noDataGeneric }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary.replacingOccurrences(of: "Abfuhr: ", with: ""))) }
    }
}
