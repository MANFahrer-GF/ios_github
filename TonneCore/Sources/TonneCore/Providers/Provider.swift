import Foundation

/// Ein Eintrag in einer Auswahlliste (Ort, Straße, Hausnummer …).
public struct SelectionOption: Identifiable, Hashable, Codable {
    public var id: String
    public var title: String
    public var subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

/// Ein Schritt im Einrichtungsassistenten: entweder eine Auswahlliste oder eine Texteingabe
/// (z. B. Straßenname bei Portalen ohne Straßenliste). Bei Texteingabe liefert der Nutzer
/// eine `SelectionOption` mit `id == title == eingegebener Text`.
public struct SelectionStep: Hashable {
    public enum Input: Hashable { case list, text }

    public var title: String
    public var options: [SelectionOption]
    public var searchable: Bool
    public var input: Input
    public var placeholder: String?

    public init(title: String, options: [SelectionOption], searchable: Bool = true) {
        self.title = title
        self.options = options
        self.searchable = searchable
        self.input = .list
        self.placeholder = nil
    }

    public static func text(title: String, placeholder: String? = nil) -> SelectionStep {
        var step = SelectionStep(title: title, options: [], searchable: false)
        step.input = .text
        step.placeholder = placeholder
        return step
    }

    /// Standard-Schrittnamen
    public static var cityTitle: String { L10n.t("Ort", "Town") }
    public static var districtTitle: String { L10n.t("Ortsteil", "District") }
    public static var streetTitle: String { L10n.t("Straße", "Street") }
    public static var houseNumberTitle: String { L10n.t("Hausnummer", "House number") }
}

/// Ein Abholtermin aus einer Online-Quelle.
public struct Pickup: Hashable, Codable {
    public var date: Date
    public var name: String
    public var note: String?

    public init(date: Date, name: String, note: String? = nil) {
        self.date = date
        self.name = name
        self.note = note
    }
}

/// Die vollständige Konfiguration einer Online-Quelle, wie sie am Standort gespeichert wird.
public struct SourceConfiguration: Hashable, Codable {
    public var providerKind: ProviderKind
    public var serviceKey: String
    public var selections: [SelectionOption]
    public var label: String

    public init(providerKind: ProviderKind, serviceKey: String, selections: [SelectionOption], label: String) {
        self.providerKind = providerKind
        self.serviceKey = serviceKey
        self.selections = selections
        self.label = label
    }

    public func encoded() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func decode(_ string: String?) -> SourceConfiguration? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SourceConfiguration.self, from: data)
    }
}

public enum ProviderKind: String, Codable, CaseIterable, Hashable {
    case awido
    case abfallIOGraphQL
    case abfallIOLegacy
    case jumomind
    case abfallnavi
    case abfallAppNet
    case icsURL
    case cTrace
    case muellmax
    case awbKoeln
    case leipzig
    case ahaHannover
    case abfallPlusApp
    case gemosWasteBox
    case awsh
    case lobbe
    case nerdbridge
    case bsr

    public var displayName: String {
        switch self {
        case .awido: return "AWIDO"
        case .abfallIOGraphQL, .abfallIOLegacy: return "AbfallPlus"
        case .jumomind: return "Jumomind / MyMüll"
        case .abfallnavi: return "Abfallnavi"
        case .abfallAppNet: return "Abfall-App"
        case .icsURL: return L10n.t("ICS-Link", "ICS link")
        case .cTrace: return "C-Trace"
        case .muellmax: return "Müllmax"
        case .awbKoeln: return "AWB Köln"
        case .leipzig: return "Stadtreinigung Leipzig"
        case .ahaHannover: return "aha Region Hannover"
        case .abfallPlusApp: return "AbfallPlus-App"
        case .gemosWasteBox: return "Gemos WasteBox"
        case .awsh: return "AWSH"
        case .lobbe: return "Lobbe App"
        case .nerdbridge: return "Nerdbridge"
        case .bsr: return "BSR Berlin"
        }
    }
}

public enum ProviderError: LocalizedError {
    case noData(String)
    case invalidSelection(String)
    case notSupported(String)

    public var errorDescription: String? {
        switch self {
        case .noData(let message): return message
        case .invalidSelection(let message): return message
        case .notSupported(let message): return message
        }
    }

    public static var noDataGeneric: ProviderError {
        .noData(L10n.t("Das Portal hat keine Termine für diese Adresse geliefert.", "The portal returned no dates for this address."))
    }

    public static var selectAddressFirst: ProviderError {
        .invalidSelection(L10n.t("Bitte zuerst eine Adresse wählen.", "Please choose an address first."))
    }
}

/// Eine Online-Quelle für Abfuhrtermine: liefert Auswahlschritte und am Ende die Termine.
public protocol WasteProvider {
    var kind: ProviderKind { get }
    var serviceKey: String { get }
    var displayName: String { get }

    /// Der nächste Auswahlschritt nach den bisherigen Auswahlen – nil, wenn die Auswahl vollständig ist.
    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep?

    /// Alle Abholtermine für die vollständige Auswahl.
    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup]

    /// Lesbare Bezeichnung der Adresse, z. B. „Gifhorn, Steinstraße 1“. Anbieter mit Zusatzschritten
    /// (Tonnengröße, Suchtext) liefern hier nur den Adressteil.
    func label(for selections: [SelectionOption]) -> String
}

public extension WasteProvider {
    /// Lesbare Bezeichnung einer Auswahl, z. B. „Gifhorn, Steinstraße 1“.
    func label(for selections: [SelectionOption]) -> String {
        let parts = selections.map(\.title).filter { !$0.isEmpty && $0.lowercased() != "alle hausnummern" && $0.lowercased() != "alle straßen" }
        return parts.joined(separator: ", ")
    }

    func pickups(for selections: [SelectionOption]) async throws -> [Pickup] {
        try await pickups(for: selections, calendar: .current)
    }
}

public enum ProviderFactory {
    public static func make(kind: ProviderKind, serviceKey: String, client: HTTPClient = HTTPClient()) -> WasteProvider {
        switch kind {
        case .awido: return AwidoProvider(customer: serviceKey, client: client)
        case .abfallIOGraphQL: return AbfallIOGraphQLProvider(key: serviceKey, client: client)
        case .abfallIOLegacy: return AbfallIOLegacyProvider(key: serviceKey, client: client)
        case .jumomind: return JumomindProvider(service: serviceKey, client: client)
        case .abfallnavi: return AbfallnaviProvider(service: serviceKey, client: client)
        case .abfallAppNet: return AbfallAppNetProvider(tenant: serviceKey, client: client)
        case .icsURL: return ICSURLProvider(url: serviceKey, client: client)
        case .cTrace: return CTraceProvider(service: serviceKey, client: client)
        case .muellmax: return MuellmaxProvider(service: serviceKey, client: client)
        case .awbKoeln: return AWBKoelnProvider(client: client)
        case .leipzig: return LeipzigProvider(client: client)
        case .ahaHannover: return AhaHannoverProvider(client: client)
        case .abfallPlusApp: return AbfallPlusAppProvider(appID: serviceKey)
        case .gemosWasteBox: return GemosWasteBoxProvider(customer: serviceKey, client: client)
        case .awsh: return AWSHProvider(client: client)
        case .lobbe: return LobbeProvider(client: client)
        case .nerdbridge: return NerdbridgeProvider(client: client)
        case .bsr: return BSRProvider(client: client)
        }
    }

    public static func make(_ configuration: SourceConfiguration, client: HTTPClient = HTTPClient()) -> WasteProvider {
        make(kind: configuration.providerKind, serviceKey: configuration.serviceKey, client: client)
    }
}

/// Entfernt HTML-Reste und Anbieterzusätze aus Fraktionsnamen.
public enum NameCleaner {
    public static func clean(_ name: String) -> String {
        var result = name
            .replacingOccurrences(of: "&shy;", with: "")
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = "Abholung" }
        return result
    }
}
