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
    /// Zusatzhinweis, wenn die Suche in diesem Schritt nichts findet.
    public var noMatchHint: String?
    /// Hinweis, der immer über der Liste steht (z. B. wenn das Portal die Trefferzahl begrenzt).
    public var hint: String?

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

    /// Schritt, in dem eine Gemeinde gewählt wird (Titel wie bei den Anbietern) – nur hier darf die Suche vorauswählen.
    public var isPlaceStep: Bool {
        [Self.cityTitle, L10n.t("Gemeinde", "Municipality"), L10n.t("Ortschaft", "Town"), L10n.t("Ortsgemeinde", "Municipality"),
         L10n.t("Stadt / Gemeinde", "Town / municipality"), L10n.t("Stadt / Verbandsgemeinde", "Municipality"),
         L10n.t("Verbandsgemeinde / Stadt", "Municipality"), L10n.t("Gemeinde / Ortsteil", "Town / district")].contains(title)
    }

    /// Option, die zur gesuchten Gemeinde passt – nur im Gemeinde-Schritt: bei genau gleichem Namen, sonst bei gleichem
    /// Kernnamen, wenn genau eine Option ihn trägt (Kelheim „Gemeinde Saal“ für „Saal a.d.Donau“, siehe `placeCore`).
    public func preselection(for place: String) -> SelectionOption? {
        guard isPlaceStep else { return nil }
        if let exact = options.first(where: { ProviderCatalog.fold($0.title) == ProviderCatalog.fold(place) }) { return exact }
        let core = Self.placeCore(place)
        // „Lambrecht ohne Iptestal und Dörrental“ schließt Teile der Gemeinde aus: nur bei genau gleichem Namen (Prüfbefund 14)
        let hits = options.filter { Self.placeCore($0.title) == core && !ProviderCatalog.fold($0.title).contains(" ohne ") }
        guard !core.isEmpty else { return nil }
        return hits.count == 1 ? hits[0] : Self.suffixMatch(hits, place: place)
    }

    /// Unter gleichen Kernen der mit dem Zusatz des Orts: Kusel „Rutsweiler/Glan“ für „Rutsweiler am Glan“,
    /// „Rutsweiler/Lauter“ für „Rutsweiler an der Lauter“ (Gemeinde-Prüfung 16.11.2026).
    static func suffixMatch(_ hits: [SelectionOption], place: String) -> SelectionOption? {
        guard hits.count > 1, let last = place.split(separator: " ").last.map(String.init), place.contains(" ") else { return nil }
        let fitting = hits.filter { option in
            guard let slash = option.title.lastIndex(of: "/") else { return false }
            return ProviderCatalog.fold(String(option.title[option.title.index(after: slash)...])) == ProviderCatalog.fold(last)
        }
        return fitting.count == 1 ? fitting[0] : nil
    }

    /// Ortsname ohne Verwaltungs-Vorsilbe und amtlichen Zusatz, wie Portale ihn verschieden schreiben (Gemeinde-Prüfung
    /// 16.11.2026): „Gemeinde Saal“ / „Saal a.d.Donau“ → „saal“, „Stadt Bingen“ / „Bingen am Rhein“ → „bingen“,
    /// „Brünn/Thür.“ → „brunn“, „Neufahrn i. Ndb.“ → „neufahrn“, „Beelitz (Stadt)“ → „beelitz“, „St.Johann“ → „sankt johann“,
    /// „Altleiningen mit Neuleiningen Tal“ → „altleiningen“. Ortsteile mit
    /// Bindestrich („Altenglan - Mühlbach“) bleiben ganz.
    static func placeCore(_ name: String) -> String {
        var text = spelling(name)
        for cut in ["(", "/", ","] { if let range = text.range(of: cut) { text = String(text[..<range.lowerBound]) } }
        for prefix in ["verbandsgemeinde ", "samtgemeinde ", "gemeinden ", "gemeinde ", "stadt ", "markt ", "amt "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)); break
        }
        // „St.Johann“ (KAW Mainz-Bingen) = „Sankt Johann“
        if text.hasPrefix("st.") || text.hasPrefix("st ") { text = "sankt " + text.dropFirst(3).trimmingCharacters(in: .whitespaces) }
        // „mit“/„ohne“: AWB Bad Dürkheim „Altleiningen mit Neuleiningen Tal“, „Lambrecht ohne Iptestal und Dörrental“
        let joins: Set<Substring> = ["am", "an", "im", "in", "bei", "ob", "unter", "vor", "auf", "mit", "ohne", "a.", "i.", "b."]
        var kept: [Substring] = []
        for word in text.split(separator: " ") {
            if !kept.isEmpty, joins.contains(word) || word.contains(".") { break }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }

    /// Gefaltet und ohne Unterschied zwischen Bindestrich und Leerzeichen, wie Portale und Suchende Ortsteile verschieden
    /// schreiben (Nachprüfung N1, 16.11.2026): „Dabel-Woland“ = „Dabel Woland“, „Hagenow Heide“ = „Hagenow-Heide“,
    /// „Altenglan - Mühlbach“ → „altenglan muhlbach“. Einzige Stelle dafür; `placeCore` baut darauf auf.
    static func spelling(_ name: String) -> String {
        ProviderCatalog.fold(name).replacingOccurrences(of: "-", with: " ").split(separator: " ").joined(separator: " ")
    }

    /// Wie `preselection(for:)`, kennt aber die Suche selbst (Prüfbefunde 1–3, 16.11.2026):
    /// - Mehrdeutige Kurzform: „Rutsweiler“ passt auf „Rutsweiler/Glan“ und „Rutsweiler/Lauter“, „Weisenheim“ auf „am Berg“
    ///   und „am Sand“ – keine Vorauswahl, auch wenn die gefundene Gemeinde genau in der Liste steht.
    /// - Gesuchter Ortsteil mit eigener Option schlägt seine Gemeinde: „Kummer“ wählt „Kummer“, nicht „Ludwigslust“
    ///   (Gemos „Gemeinde / Ortsteil“), „Damelack“ für Breddin (Ostprignitz-Ruppin); bei gleichnamigen Ortsteilen der mit dem
    ///   Zusatz der Gemeinde („Zahrensdorf (Kloster Tempzin)“), ohne eindeutige Option („Klein Krams + Ausbau“) die Liste.
    /// - „Ort / Ortsteil“ (C-Trace Groß-Gerau): „Erfelden“ oder „Riedstadt-Erfelden“ wählt „Riedstadt / Erfelden“.
    /// - Bindestrich und Leerzeichen gelten gleich (`spelling`): „Dabel Woland“ wählt „Dabel-Woland“ (Nachprüfung N1).
    /// - Nennt die Suche Wörter über die Gemeinde hinaus, die eine andere Option trägt, die aber nicht eindeutig zuzuordnen
    ///   ist, zeigt der Assistent die Liste statt die Gemeinde: Eine falsche Vorauswahl ist schlimmer als keine.
    public func preselection(for place: String, query: String) -> SelectionOption? {
        guard isPlaceStep else { return nil }
        let fold = ProviderCatalog.fold, spell = Self.spelling
        let searched = fold(query), placeCore = Self.placeCore(place)
        if searched != fold(place), Self.placeCore(query) == placeCore, !placeCore.isEmpty,
           options.filter({ Self.placeCore($0.title) == placeCore }).count > 1 { return nil }
        let found = fold(ProviderCatalog.resolve(searched).locality ?? query)
        let locality = spell(found), typed = spell(query)
        let localityCore = Self.placeCore(locality)
        if !localityCore.isEmpty, localityCore != placeCore {
            let own = options.filter {
                Self.placeCore($0.title) == localityCore || spell($0.title).hasPrefix(locality + " ") || spell($0.title) == typed
            }
            if !own.isEmpty {
                // Nur wenn der Ortsteil zur gesuchten Gemeinde gehört (Kränzlin ist nicht Breddin): laut Ortsteil-Liste, unter
                // dem gesuchten Namen oder dem der Option, oder weil die Option mit dem Gemeindenamen beginnt („Dabel-Woland“).
                let belongs = ([found] + own.map { fold($0.title) }).contains { name in
                    (LocalityIndex.byName[name] ?? []).contains { fold($0.municipality) == fold(place) }
                } || own.contains { spell($0.title).hasPrefix(spell(place) + " ") }
                guard belongs else { return nil }
                let withPlace = own.filter { Self.bracketSuffix($0.title) == fold(place) }
                if withPlace.count == 1 { return withPlace[0] }
                return own.count == 1 && [locality, typed].contains(spell(own[0].title)) ? own[0] : nil
            }
        }
        let words = Set(searched.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let hits = options.filter {
            let parts = $0.title.components(separatedBy: " / ")
            return parts.count == 2 && fold(parts[0]) == fold(place) && words.contains(fold(parts[1]))
        }
        if hits.count == 1 { return hits[0] }
        guard let exact = preselection(for: place) else { return nil }
        // Wörter der Suche über Gemeinde und gewählte Option hinaus („Ziegelscheune“), die alle als Wortanfang in einer anderen
        // Option stehen: Die Suche meint vermutlich diese, also keine Vorauswahl. Ein Ortsteil ohne eigene Option
        // („Stuttgart Vaihingen“) wählt weiter die Gemeinde.
        func wordsOf(_ text: String) -> [String] { spell(text).split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let extra = Set(wordsOf(query)).subtracting(wordsOf(place)).subtracting(wordsOf(exact.title))
        let named = !extra.isEmpty && options.contains { option in
            option.id != exact.id && extra.allSatisfy { word in wordsOf(option.title).contains { $0.hasPrefix(word) } }
        }
        return named ? nil : exact
    }

    /// Zusatz in Klammern am Ende: „Zahrensdorf (Kloster Tempzin)“ → „kloster tempzin“.
    static func bracketSuffix(_ title: String) -> String? {
        guard let open = title.lastIndex(of: "("), let close = title.lastIndex(of: ")"), open < close else { return nil }
        return ProviderCatalog.fold(String(title[title.index(after: open)..<close]))
    }
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

public extension SourceConfiguration {
    /// Andere Adresse als bisher? Ein Eintragswechsel an derselben Adresse (Kreisportal Reutlingen → TBR-App, beide
    /// „Hauptstraße, 5“) ist keiner (Prüfbefund 9). Adresse = Ort + Straße/Nummer: Der Ort muss auf beiden Seiten bestimmbar
    /// und gleich sein (`addressPlace`), die Wörter der übrigen Titel müssen genau übereinstimmen – „Hauptstraße 1“ gegen
    /// „10“, „12“ gegen „12a“ oder ein anderer bzw. unbekannter Ort zählen als Wechsel (Nachprüfung N2). Im Zweifel „geändert“:
    /// Dann bleiben nur markierte vergangene Termine stehen (`ScheduleEngine.datesAfterReplacingSync`).
    static func addressChanged(from old: SourceConfiguration?, to new: SourceConfiguration) -> Bool {
        guard let old else { return true }
        if old.providerKind == new.providerKind, old.serviceKey == new.serviceKey, old.selections.map(\.id) == new.selections.map(\.id) { return false }
        guard let a = old.addressPlace(), let b = new.addressPlace(), a.place == b.place else { return true }
        let words = addressWords(a.rest)
        return words.isEmpty || words != addressWords(b.rest)
    }

    /// Ort der Adresse (Kern wie `SelectionStep.placeCore`) und die übrigen Titel: Ist der erste gewählte Titel eine
    /// Gemeinde („Reutlingen“ im Kreisportal), gilt er; sonst der einzige Ort, den der Katalogeintrag belegt führt (TBR-App:
    /// nur Reutlingen). Sonst nil – der Ort ist unbekannt.
    private func addressPlace() -> (place: String, rest: [SelectionOption])? {
        if let first = selections.first, Self.municipalityCores.contains(SelectionStep.placeCore(first.title)) {
            return (SelectionStep.placeCore(first.title), Array(selections.dropFirst()))
        }
        let entries = ProviderCatalog.entries.filter { $0.kind == providerKind && $0.serviceKey == serviceKey }
        let mapped = Set(entries.flatMap { EntryPlacesIndex.pairs[$0.id] ?? [] }.map { SelectionStep.placeCore(String($0.split(separator: "|", maxSplits: 1).last ?? "")) })
        let listed = Set(entries.flatMap(\.places).map(SelectionStep.placeCore).filter(Self.municipalityCores.contains))
        let places = mapped.isEmpty ? listed : mapped
        return places.count == 1 ? (places.first!, selections) : nil
    }

    /// Kernnamen aller Gemeinden, einmal berechnet.
    private static let municipalityCores: Set<String> = Set(MunicipalityIndex.all.map { SelectionStep.placeCore($0.name) })

    /// „Hauptstr.“, „Hauptstraße“ → „hauptstr“; getippte Suchtexte („Haupt“ vor „Hauptstraße“) fallen als Wortanfang weg.
    private static func addressWords(_ selections: [SelectionOption]) -> Set<String> {
        let words = selections.flatMap { option -> [String] in
            ProviderCatalog.fold(option.title).replacingOccurrences(of: "ß", with: "ss")
                .replacingOccurrences(of: #"str(asse|\.)"#, with: "str", options: .regularExpression)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let set = Set(words)
        return set.filter { word in !word.allSatisfy(\.isLetter) || !set.contains { $0 != word && $0.hasPrefix(word) } }
    }

    /// Bis 2.0.9 enthielt der Name bei diesen Anbietern den getippten Suchtext („Hamburger Str., Hamburger Straße, 10“).
    /// Liefert den neuen Namen, wenn der gespeicherte noch genau der alte automatische ist – sonst nil (selbst benannt oder schon richtig).
    func repairedSearchTextLabel() -> String? {
        let titles = selections.map(\.title).filter { !$0.isEmpty }
        let legacy: String
        switch providerKind {
        case .leipzig, .awbKoeln, .ahaHannover, .muellmax:
            legacy = titles.filter { $0.lowercased() != "alle hausnummern" && $0.lowercased() != "alle straßen" }.joined(separator: ", ")
        case .portalsNRW where serviceKey == "sector27":
            legacy = titles.joined(separator: ", ")
        default:
            return nil
        }
        // Müllmax mit Direktsprung zu den Hausnummern: Build 12 (2.0.9) ließ den getippten Text weg und speicherte nur „2“
        let build12 = selections.filter { $0.id.contains(":") }.map(\.title)
            .filter { !$0.isEmpty && $0.lowercased() != "alle hausnummern" && $0.lowercased() != "alle straßen" }
            .joined(separator: ", ")
        guard label == legacy || (providerKind == .muellmax && label == build12) else { return nil }
        let fresh = ProviderFactory.make(kind: providerKind, serviceKey: serviceKey).label(for: selections)
        return fresh.isEmpty || fresh == label ? nil : fresh
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
    case calendarPortal
    case ahaHannover
    case abfallPlusApp
    case gemosWasteBox
    case awsh
    case lobbe
    case nerdbridge
    case bsr
    case sitepark
    case insertIT
    case muellabfuhrDeutschland
    case heimatInfo
    case buergerportal
    case magdeburg
    case hausmuellInfo
    case wasteManagementServlet
    case portalsSachsen
    case portalsMV
    case portalsMitte
    case portalsBayern
    case portalsBrandenburg
    case portalsNord
    case portalsNRW
    case portalsRP
    case portalsSuedwest
    case awmMuenchen
    case jahresdaten

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
        case .calendarPortal: return L10n.t("Bürgerportal", "Citizen portal")
        case .ahaHannover: return "aha Region Hannover"
        case .abfallPlusApp: return "AbfallPlus-App"
        case .gemosWasteBox: return "Gemos WasteBox"
        case .awsh: return L10n.t("Kreis-Abfallkalender", "District waste calendar")
        case .lobbe: return "Lobbe App"
        case .nerdbridge: return "Nerdbridge"
        case .bsr: return "BSR Berlin"
        case .sitepark: return L10n.t("Kreis-/Stadtportal", "District portal")
        case .insertIT: return "Insert IT"
        case .muellabfuhrDeutschland: return "Müllabfuhr Deutschland"
        case .heimatInfo: return "Heimat-Info"
        case .buergerportal: return "Bürgerportal"
        case .magdeburg: return "SAB Magdeburg"
        case .hausmuellInfo: return "hausmüll.info"
        case .wasteManagementServlet: return "WasteManagement-Portal"
        case .portalsSachsen, .portalsMV, .portalsMitte, .portalsBayern, .portalsBrandenburg, .portalsNord, .portalsNRW, .portalsRP, .portalsSuedwest:
            return L10n.t("Portal des Entsorgers", "Operator portal")
        case .awmMuenchen: return "AWM München"
        case .jahresdaten: return L10n.t("Abfallkalender (PDF)", "Waste calendar (PDF)")
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

    /// Liefert ein Portal nur noch Vergangenes, ist die Quelle veraltet (Feucht bei Heimat-Info, Stand 12.11.2026: nur Termine
    /// bis Ende 2025). Statt still „0 kommende Termine“ zu übernehmen, klar sagen, was zu tun ist.
    /// `setup`: beim Einrichten (anderen Entsorger wählen) statt beim Abgleich eines vorhandenen Standorts.
    public static func requireUpcoming(_ pickups: [Pickup], today: Date, setup: Bool = false, calendar: Calendar = .current) throws {
        let day = calendar.startOfDay(for: today)
        guard !pickups.isEmpty, !pickups.contains(where: { $0.date >= day }), let last = pickups.map(\.date).max() else { return }
        let text = last.formatted(.dateTime.day().month(.wide).year())
        if setup {
            throw ProviderError.noData(L10n.t(
                "Dieses Portal liefert keine kommenden Termine mehr, der letzte war am \(text). Bitte zurückgehen und einen anderen Entsorger wählen.",
                "This portal no longer provides upcoming dates; the last one was on \(text). Please go back and choose another provider."))
        }
        throw ProviderError.noData(L10n.t(
            "Dieses Portal liefert keine kommenden Termine mehr, der letzte war am \(text). Bitte den Entsorger neu wählen: Standort öffnen und „Entsorger oder Adresse ändern“ antippen.",
            "This portal no longer provides upcoming dates; the last one was on \(text). Please choose the provider again: open the location and tap “Change provider or address”."))
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

    /// Hinweis zur Herkunft der Termine, den die App beim Standort zeigt – z. B. „berechnet, Feiertage beachten“.
    var notice: String? { get }

    /// Kurzfassung der Einschränkung für Listen („Geht mein Ort?“); Standard ist der Hinweis selbst.
    var restriction: String? { get }
}

public extension WasteProvider {
    var notice: String? { nil }
    var restriction: String? { notice }

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
        case .calendarPortal: return CalendarPortalProvider(operator: serviceKey, client: client)
        case .ahaHannover: return AhaHannoverProvider(client: client)
        case .abfallPlusApp: return AbfallPlusAppProvider(appID: serviceKey)
        case .gemosWasteBox: return GemosWasteBoxProvider(customer: serviceKey, client: client)
        case .awsh: return AWSHProvider(region: serviceKey, client: client)
        case .lobbe: return LobbeProvider(client: client)
        case .nerdbridge: return NerdbridgeProvider(client: client)
        case .bsr: return BSRProvider(client: client)
        case .sitepark: return SiteparkProvider(tenant: serviceKey, client: client)
        case .insertIT: return InsertITProvider(city: serviceKey, client: client)
        case .muellabfuhrDeutschland: return MuellabfuhrDeutschlandProvider(mandator: serviceKey, client: client)
        case .heimatInfo: return HeimatInfoProvider(commune: serviceKey, client: client)
        case .buergerportal: return BuergerportalProvider(operator: serviceKey, client: client)
        case .magdeburg: return MagdeburgProvider(client: client)
        case .hausmuellInfo: return HausmuellInfoProvider(service: serviceKey, client: client)
        case .wasteManagementServlet: return WasteManagementServletProvider(service: serviceKey, client: client)
        case .portalsSachsen: return SachsenPortalsProvider(service: serviceKey, client: client)
        case .portalsMV: return MecklenburgPortalsProvider(service: serviceKey, client: client)
        case .portalsMitte: return MitteldeutschlandPortalsProvider(service: serviceKey, client: client)
        case .portalsBayern: return BayernPortalsProvider(service: serviceKey, client: client)
        case .portalsBrandenburg: return BrandenburgPortalsProvider(service: serviceKey, client: client)
        case .portalsNord: return NordPortalsProvider(service: serviceKey, client: client)
        case .portalsNRW: return NRWPortalsProvider(service: serviceKey, client: client)
        case .portalsRP: return RheinlandPfalzPortalsProvider(service: serviceKey, client: client)
        case .portalsSuedwest: return SuedwestPortalsProvider(service: serviceKey, client: client)
        case .awmMuenchen: return AWMMuenchenProvider(service: serviceKey, client: client)
        case .jahresdaten: return JahresdatenProvider(key: serviceKey)
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
