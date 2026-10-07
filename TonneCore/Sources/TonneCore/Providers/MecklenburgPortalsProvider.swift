import Foundation

/// Portale in Mecklenburg-Vorpommern. Ein Anbieter für mehrere Betreiber, unterschieden über `serviceKey`:
/// - `lro`: Abfallwirtschaft Landkreis Rostock – Ortsliste (PDF-Links mit Tourbuchstaben), ICS mit Leerungsrhythmus
/// - `rostock`: Stadtentsorgung Rostock – Straßensuche, Objektschlüssel per Formular, ICS je Objekt
/// - `nwm`: Landkreis Nordwestmecklenburg – statische ICS-Dateien je Ortsteil (Verzeichnisliste)
/// - `vevg`: VEVG Vorpommern-Greifswald – Orts-/Straßenlisten, ICS je Ort und Kreis-Kennung
/// - `schwerin`: SDS Schwerin – Gemos WasteBox (Kunde `sds`) mit Auswahl des Leerungsrhythmus (Kategorie)
public struct MecklenburgPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsMV
    public let serviceKey: String
    public var displayName: String {
        switch serviceKey {
        case "lro": return "Abfallwirtschaft Landkreis Rostock"
        case "rostock": return "Stadtentsorgung Rostock"
        case "nwm": return "Landkreis Nordwestmecklenburg"
        case "vevg": return "VEVG Vorpommern-Greifswald"
        case "schwerin": return "SDS Schwerin"
        default: return kind.displayName
        }
    }
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "lro": return try await LRO(client: client).nextStep(after: selections)
        case "rostock": return try await Rostock(client: client).nextStep(after: selections)
        case "nwm": return try await NWM(client: client).nextStep(after: selections)
        case "vevg": return try await VEVG(client: client).nextStep(after: selections)
        case "schwerin": return try await Schwerin(client: client).nextStep(after: selections)
        default: throw Self.unknownService
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let pickups: [Pickup]
        switch serviceKey {
        case "lro": pickups = try await LRO(client: client).pickups(for: selections, calendar: calendar)
        case "rostock": pickups = try await Rostock(client: client).pickups(for: selections, calendar: calendar)
        case "nwm": pickups = try await NWM(client: client).pickups(for: selections, calendar: calendar)
        case "vevg": pickups = try await VEVG(client: client).pickups(for: selections, calendar: calendar)
        case "schwerin": pickups = try await Schwerin(client: client).pickups(for: selections, calendar: calendar)
        default: throw Self.unknownService
        }
        guard !pickups.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        // Rhythmus-Schritte (Kennung „rhythm…“) gehören nicht zur Adresse.
        switch serviceKey {
        case "rostock":
            // Auswahl: Suchtext, Straße, Hausnummer
            let address = selections.dropFirst().prefix(2).map { $0.title.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return address.isEmpty ? "Rostock" : "Rostock, " + address.joined(separator: " ")
        case "schwerin":
            // Auswahl: Straße, Hausnummer (+ Rhythmus)
            let address = selections.filter { !$0.id.hasPrefix(Self.rhythmPrefix) }.map(\.title).filter { !$0.isEmpty }
            return address.isEmpty ? "Schwerin" : "Schwerin, " + address.joined(separator: " ")
        default:
            return selections.filter { !$0.id.hasPrefix(Self.rhythmPrefix) }.map(\.title).filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    static let rhythmPrefix = "rhythm:"

    static var unknownService: ProviderError {
        .notSupported(L10n.t("Dieser Betreiber wird nicht unterstützt.", "This operator is not supported."))
    }

    static func rhythmOption(_ value: String, _ title: String) -> SelectionOption {
        SelectionOption(id: rhythmPrefix + value, title: title)
    }

    static func rhythmValue(_ option: SelectionOption?) -> String? {
        guard let id = option?.id, id.hasPrefix(rhythmPrefix) else { return nil }
        return String(id.dropFirst(rhythmPrefix.count))
    }

    static func sorted(_ options: [SelectionOption]) -> [SelectionOption] {
        options.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func collapse(_ text: String) -> String {
        HTMLText.decodeEntities(text)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Landkreis Rostock (abfall-lro.de)

/// Ortsliste aus den PDF-Links (Dateiname = Tourbuchstaben, z. B. `B_B_O_A`), Güstrow mit eigener Straßenliste.
/// Der ICS-Export braucht zusätzlich den Rhythmus der schwarzen (Restmüll) und grünen Tonne (Bio).
private struct LRO {
    let client: HTTPClient
    static let base = "https://www.abfall-lro.de"
    static let overview = base + "/de/abfuhrtermine/"
    static let guestrow = base + "/de/abfuhrtermine/guestrow.php"
    static let ical = base + "/default-wGlobal/wGlobal/abfuhrtermine/ical.php"
    static let guestrowID = "guestrow"

    struct Entry { let year: Int; let letters: String; let title: String }

    /// Alle PDF-Links einer Seite; der Zusatz hinter dem Link („(Kröpelin)“) gehört zum Namen.
    static func entries(in html: String) -> [Entry] {
        HTMLText.matches(#"<a href="/default-wAssets/docs/abfuhrtermine/(\d{4})/pdf/([^"/]+)\.pdf"[^>]*>([^<]*)</a>([^<]*)"#, in: html).compactMap { g in
            guard let year = Int(g[0]) else { return nil }
            var suffix = MecklenburgPortalsProvider.collapse(g[3])
            if suffix.allSatisfy({ $0 == "." || $0 == " " }) { suffix = "" }
            let title = MecklenburgPortalsProvider.collapse(g[2] + " " + suffix)
            return title.isEmpty ? nil : Entry(year: year, letters: g[1], title: title)
        }
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        let isGuestrow = selections.first?.id == Self.guestrowID
        let base = isGuestrow ? 2 : 1
        switch selections.count {
        case 0:
            let entries = Self.entries(in: try await client.string(Self.overview))
            var seen = Set<String>()
            var options: [SelectionOption] = []
            for entry in entries.sorted(by: { $0.year > $1.year }) where seen.insert(entry.title).inserted {
                options.append(SelectionOption(id: entry.letters, title: entry.title))
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            options.append(SelectionOption(id: Self.guestrowID, title: "Güstrow", subtitle: L10n.t("Stadt, mit Straßenauswahl", "Town, choose street")))
            return SelectionStep(title: SelectionStep.cityTitle, options: MecklenburgPortalsProvider.sorted(options))
        case 1 where isGuestrow:
            let entries = Self.entries(in: try await client.string(Self.guestrow))
            var seen = Set<String>()
            let options = entries.filter { seen.insert($0.title).inserted }.map { SelectionOption(id: $0.letters, title: $0.title) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: MecklenburgPortalsProvider.sorted(options))
        case base:
            return SelectionStep(title: L10n.t("Schwarze Tonne (Restmüll)", "Black bin (residual waste)"),
                                 options: Self.rhythms(letters: selections[base - 1].id, weekly: "RW", twice: "RZW"), searchable: false)
        case base + 1:
            return SelectionStep(title: L10n.t("Grüne Tonne (Bioabfall)", "Green bin (organic waste)"),
                                 options: Self.rhythms(letters: selections[base - 1].id, weekly: "BW", twice: "BZW"), searchable: false)
        default:
            return nil
        }
    }

    /// Rhythmus-Auswahl wie im Formular des Portals; „Saison“ = nur in der Saison geleert.
    static func rhythms(letters: String, weekly: String, twice: String) -> [SelectionOption] {
        var options = [
            MecklenburgPortalsProvider.rhythmOption("2w", L10n.t("Alle 2 Wochen", "Every 2 weeks")),
            MecklenburgPortalsProvider.rhythmOption("4w", L10n.t("Alle 4 Wochen", "Every 4 weeks")),
            MecklenburgPortalsProvider.rhythmOption("2w|s", L10n.t("Alle 2 Wochen, nur Saison", "Every 2 weeks, season only")),
            MecklenburgPortalsProvider.rhythmOption("4w|s", L10n.t("Alle 4 Wochen, nur Saison", "Every 4 weeks, season only")),
        ]
        if letters.contains(weekly) { options.insert(MecklenburgPortalsProvider.rhythmOption("w", L10n.t("Wöchentlich", "Weekly")), at: 0) }
        if letters.contains(twice) { options.insert(MecklenburgPortalsProvider.rhythmOption("zw", L10n.t("2x pro Woche", "Twice a week")), at: 0) }
        options.append(MecklenburgPortalsProvider.rhythmOption("none", L10n.t("Keine Tonne", "No bin")))
        return options
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let isGuestrow = selections.first?.id == Self.guestrowID
        let base = isGuestrow ? 2 : 1
        guard selections.count >= base + 2,
              let black = MecklenburgPortalsProvider.rhythmValue(selections[base]),
              let green = MecklenburgPortalsProvider.rhythmValue(selections[base + 1]) else { throw ProviderError.selectAddressFirst }
        let place = selections[base - 1]
        let year = calendar.component(.year, from: Date())

        // Tourbuchstaben je Jahr frisch von der Seite holen (sie können sich zum Jahreswechsel ändern).
        var lettersByYear: [Int: String] = [:]
        if let html = try? await client.string(isGuestrow ? Self.guestrow : Self.overview) {
            for entry in Self.entries(in: html) where entry.title == place.title && entry.year >= year {
                lettersByYear[entry.year] = lettersByYear[entry.year] ?? entry.letters
            }
        }
        if lettersByYear[year] == nil { lettersByYear[year] = place.id }

        var result: [Pickup] = []
        for (target, letters) in lettersByYear.sorted(by: { $0.key < $1.key }) {
            var query = "letters=\(HTTPClient.query(letters))&year=\(target)&place=\(HTTPClient.query(isGuestrow ? "Alle" : place.title))&yellow=y&blue=y"
            query += Self.rhythmQuery(black, field: "black", season: "bsaison")
            query += Self.rhythmQuery(green, field: "green", season: "gsaison")
            guard let text = try? await client.string(Self.ical + "?" + query) else { continue }
            result += ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: Self.clean($0.summary)) }
        }
        return result
    }

    static func rhythmQuery(_ value: String, field: String, season: String) -> String {
        if value == "none" { return "&\(field)=" }
        let parts = value.components(separatedBy: "|")
        return "&\(field)=\(parts[0])" + (parts.count > 1 ? "&\(season)=y" : "")
    }

    /// „Leerung Schwarze Tonne (2W) Alt Kätwin“ → „Schwarze Tonne“.
    static func clean(_ summary: String) -> String {
        var name = summary.replacingOccurrences(of: #"^\s*Leerung\s+"#, with: "", options: .regularExpression)
        if let range = name.range(of: "Tonne") { name = String(name[..<range.upperBound]) }
        return NameCleaner.clean(name)
    }
}

// MARK: - Stadtentsorgung Rostock

/// Straßensuche (JSONP), Objektschlüssel `AWI~…-GEG~…` aus dem Formular, dann ICS fürs laufende Jahr.
private struct Rostock {
    let client: HTTPClient
    static let base = "https://www.stadtentsorgung-rostock.de"

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Bahnhofstr.", "e.g. Bahnhofstr."))
        case 1:
            let term = selections[0].title.trimmingCharacters(in: .whitespaces)
            guard term.count >= 2 else {
                throw ProviderError.invalidSelection(L10n.t("Bitte mindestens zwei Buchstaben eingeben.", "Please enter at least two letters."))
            }
            let text = try await client.string("\(Self.base)/service/ekalend_form_data_get_address?maxRows=100&q=\(HTTPClient.query(term))")
            let options = HTMLText.matches(#""label"\s*:\s*"[^"]*"\s*,\s*"value"\s*:\s*"([^"]*)"\s*,\s*"zip"\s*:\s*"([^"]*)""#, in: text).map { g -> SelectionOption in
                let street = (g[0].removingPercentEncoding ?? g[0]).trimmingCharacters(in: .whitespaces)
                return SelectionOption(id: "\(street)|\(g[1])", title: street, subtitle: g[1])
            }
            guard !options.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Keine passende Straße in Rostock gefunden.", "No matching street found in Rostock."))
            }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 1", "e.g. 1"))
        case 3:
            // Adresse gleich prüfen, damit ein Tippfehler nicht erst bei den Terminen auffällt.
            _ = try await addressKey(for: selections)
            return nil
        default:
            return nil
        }
    }

    func addressKey(for selections: [SelectionOption]) async throws -> String {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let parts = selections[1].id.components(separatedBy: "|")
        let number = selections[2].title.trimmingCharacters(in: .whitespaces)
        let data = try await client.postForm("\(Self.base)/service/ekalend_form_data/1216/SearchByAddress", fields: [
            ("Input[address][street]", parts[0]),
            ("Input[address][no]", number),
            ("Input[address][zip]", parts.count > 1 ? parts[1] : ""),
            ("Input[address][legit]", "on"),
            ("Input[address][key]", ""),
            ("SearchByAddress", "Abfuhrtermine anzeigen"),
        ])
        let html = HTTPClient.text(from: data)
        guard let key = HTMLText.firstMatch(#"name="Input\[address\]\[key\]" value="([^"]+)""#, in: html, group: 1), key.contains("~") else {
            throw ProviderError.invalidSelection(L10n.t("Die Adresse wurde nicht gefunden – bitte Hausnummer prüfen.", "Address not found – please check the house number."))
        }
        return key
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let key = try await addressKey(for: selections)
        let text = try await client.string("\(Self.base)/service/ekalend_ical/(key)/\(key)/(period)/year")
        return ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }
}

// MARK: - Landkreis Nordwestmecklenburg (geoport-nwm.de)

/// Statische ICS-Dateien je Ortsteil und Jahr: `Ortsteil_<Name>.ics` (Rest/Bio/Wertstoff) plus
/// `Papiertonne_<Firma>_Ortsteil_<Name>.ics` und `Schadstoffmobil_Ortsteil_<Name>.ics`.
private struct NWM {
    let client: HTTPClient
    static let base = "https://www.geoport-nwm.de/nwm-download/Abfuhrtermine/ICS"

    /// Dateinamen aus der Verzeichnisliste (Apache, Filter über `P=`).
    func files(year: Int, pattern: String) async throws -> [String] {
        let html = try await client.string("\(Self.base)/\(year)/?P=\(pattern)")
        return Array(Set(HTMLText.matches(#"href="([^"?/]+\.ics)""#, in: html).map { $0[0].removingPercentEncoding ?? $0[0] }))
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        var names: [String] = []
        for target in [year, year - 1] where names.isEmpty {
            names = (try? await files(year: target, pattern: "Ortsteil_*")) ?? []
        }
        let options = names.filter { $0.hasPrefix("Ortsteil_") }.map { file -> SelectionOption in
            let stem = String(file.dropFirst("Ortsteil_".count).dropLast(".ics".count))
            return SelectionOption(id: stem, title: Self.title(for: stem))
        }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.districtTitle, options: MecklenburgPortalsProvider.sorted(options))
    }

    /// Lesbarer Name aus dem Dateinamen: „Gross_Stieten_1100_l“ → „Groß Stieten (1.100-l-Behälter)“.
    static func title(for stem: String) -> String {
        var words = stem.components(separatedBy: "_").filter { !$0.isEmpty }
        var suffix = ""
        if words.suffix(2) == ["1100", "l"] {
            words.removeLast(2)
            suffix = " (1.100-l-Behälter)"
        }
        let text = words.map { word -> String in
            if word == "u" { return "u." }
            if word == "Gross" { return "Groß" }
            if word.hasPrefix("Gross") { return "Groß" + word.dropFirst(5) }
            return umlauts(word)
        }.joined(separator: " ")
        return text + suffix
    }

    /// Umlaute zurückholen: ue/oe/ae → ü/ö/ä, außer nach Vokal oder q („Neuendorf“, „Questin“)
    /// und am Wortanfang („Oertzenhof“).
    static func umlauts(_ word: String) -> String {
        let chars = Array(word)
        var result = ""
        var i = 0
        let map: [Character: Character] = ["u": "ü", "o": "ö", "a": "ä"]
        while i < chars.count {
            if i > 0, i + 1 < chars.count, chars[i + 1] == "e", let umlaut = map[chars[i]],
               !"aeiouqAEIOUQ".contains(chars[i - 1]) {
                result.append(umlaut)
                i += 2
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let stem = selections.first?.id, !stem.isEmpty else { throw ProviderError.selectAddressFirst }
        let year = calendar.component(.year, from: Date())
        // Einzeldateien je Tonne sind im Sammelkalender „Ortsteil_…“ schon enthalten.
        let skip = ["Biotonne_", "Gelbe_Tonne_", "Restabfalltonne_"]
        var result: [Pickup] = []
        for target in [year, year + 1] {
            guard let names = try? await files(year: target, pattern: "*Ortsteil_\(HTTPClient.query(stem)).ics") else { continue }
            for file in names.sorted() where !skip.contains(where: { file.hasPrefix($0) }) {
                guard let text = try? await client.string("\(Self.base)/\(target)/\(HTTPClient.query(file))") else { continue }
                result += ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
            }
        }
        return result
    }
}

// MARK: - VEVG Vorpommern-Greifswald (vevg-karlsburg.de)

/// Vier Gebiete mit eigener Seite; Optionswerte „<Orts-ID>#<Name>#<Kreis>#[lesen]“. „lesen“ heißt:
/// es folgt eine Straßen- bzw. Hausnummernliste. Termine als ICS je Orts-ID und Kreis-Kennung.
private struct VEVG {
    let client: HTTPClient
    static let base = "https://vevg-karlsburg.de"
    /// Gebiete der Ortsliste (Kürzel der Seite); Greifswald-Stadt („uhgw“) wird als ein Ort angeboten.
    static let regions = ["ovp", "jtpl", "uer"]
    static let areaNames = ["A": "Anklam", "W": "Wolgast", "G": "Greifswald-Land", "L": "Jarmen-Tutow / Peenetal-Loitz", "U": "Uecker-Randow", "H": "Greifswald"]

    /// Gespeicherte Kennung: „<Gebiet>|<Kreis>|<Optionswert>“.
    struct Key {
        let region: String
        let kreis: String
        let raw: String
        var ort: String { String(raw.prefix { $0.isNumber }) }
        var needsMore: Bool { raw.hasSuffix("lesen") }
        /// Einträge der ersten Liste („id#Name#Kreis#“) stehen auf Teil 2, Unterlisten auf Teil 3.
        var detailPart: Int { raw.components(separatedBy: "#").count >= 4 ? 2 : 3 }
        static let greifswald = Key(region: "uhgw", kreis: "H", raw: "stadt#lesen")

        init(region: String, kreis: String, raw: String) { self.region = region; self.kreis = kreis; self.raw = raw }
        init?(_ id: String) {
            let parts = id.components(separatedBy: "|")
            guard parts.count >= 3 else { return nil }
            self.init(region: parts[0], kreis: parts[1], raw: parts.dropFirst(2).joined(separator: "|"))
        }
        var id: String { "\(region)|\(kreis)|\(raw)" }
    }

    func page(region: String, query: String = "") async throws -> String {
        try await client.string("\(Self.base)/online-abfallkalender-\(region).html" + (query.isEmpty ? "" : "?" + query))
    }

    /// Optionen der Auswahlliste `key` im Formular `form`.
    static func options(form: String, in html: String) -> [(value: String, label: String)] {
        guard let block = HTMLText.firstMatch(#"name='\#(form)'[\s\S]*?<select name="key">([\s\S]*?)</select>"#, in: html, group: 1) else { return [] }
        return HTMLText.matches(#"<option value="([^"]*)"[^>]*>([^<]*)"#, in: block).map {
            (value: HTMLText.decodeEntities($0[0]), label: MecklenburgPortalsProvider.collapse($0[1]))
        }.filter { !$0.value.isEmpty }
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        if selections.isEmpty { return try await places() }
        let locations = selections.filter { MecklenburgPortalsProvider.rhythmValue($0) == nil }
        guard let last = locations.last, let key = Key(last.id) else { throw ProviderError.selectAddressFirst }

        if key.id == Key.greifswald.id {
            // Greifswald-Stadt: Straßenliste ist die erste Liste der eigenen Seite.
            let options = Self.options(form: "form1", in: try await page(region: key.region)).compactMap { option -> SelectionOption? in
                let parts = option.value.components(separatedBy: "#")
                guard parts.count >= 3 else { return nil }
                return SelectionOption(id: Key(region: key.region, kreis: parts[2], raw: option.value).id, title: option.label)
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: options)
        }

        if key.needsMore {
            let html = try await page(region: key.region, query: "part=2&param=K&anz=1&key=\(HTTPClient.query(key.raw))")
            let options = Self.options(form: "form2", in: html).map {
                SelectionOption(id: Key(region: key.region, kreis: key.kreis, raw: $0.value).id, title: $0.label)
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            let title = html.contains("Hausnummernbereich") ? SelectionStep.houseNumberTitle : SelectionStep.streetTitle
            return SelectionStep(title: title, options: options)
        }

        // Ort steht fest: Rhythmus der Restmülltonne fragen, wenn die Seite beides anbietet.
        guard selections.last.flatMap(MecklenburgPortalsProvider.rhythmValue) == nil else { return nil }
        let html = try await page(region: key.region, query: "part=\(key.detailPart)&param=K&anz=1&key=\(HTTPClient.query(key.raw))")
        let boxes = Set(HTMLText.matches(#"type="checkbox" name="(ical_\d+)""#, in: html).map { $0[0] })
        guard boxes.contains("ical_1"), boxes.contains("ical_11") else { return nil }
        return SelectionStep(title: L10n.t("Restmülltonne", "Residual waste bin"), options: [
            MecklenburgPortalsProvider.rhythmOption("1", L10n.t("14-täglich", "Every 2 weeks")),
            MecklenburgPortalsProvider.rhythmOption("11", L10n.t("Wöchentlich", "Weekly")),
        ], searchable: false)
    }

    /// Gemeinsame Ortsliste aller Gebiete, dazu Greifswald (Stadt) mit Straßenliste.
    func places() async throws -> SelectionStep {
        var collected: [(key: Key, label: String)] = []
        for region in Self.regions {
            guard let html = try? await page(region: region) else { continue }
            for option in Self.options(form: "form1", in: html) {
                let parts = option.value.components(separatedBy: "#")
                guard parts.count >= 3, !parts[2].isEmpty else { continue }
                collected.append((Key(region: region, kreis: parts[2], raw: option.value), option.label))
            }
        }
        guard !collected.isEmpty else { throw ProviderError.noDataGeneric }
        // Gleichnamige Orte in verschiedenen Bereichen unterscheidbar machen.
        var counts: [String: Int] = [:]
        for item in collected { counts[item.label, default: 0] += 1 }
        var options = collected.map { item -> SelectionOption in
            let area = Self.areaNames[item.key.kreis] ?? item.key.kreis
            let title = (counts[item.label] ?? 0) > 1 && !item.label.contains("Kreis") ? "\(item.label) (\(area))" : item.label
            return SelectionOption(id: item.key.id, title: title, subtitle: area)
        }
        options.append(SelectionOption(id: Key.greifswald.id, title: "Greifswald",
                                       subtitle: L10n.t("Stadt, mit Straßenauswahl", "Town, choose street")))
        return SelectionStep(title: SelectionStep.cityTitle, options: MecklenburgPortalsProvider.sorted(options))
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let locations = selections.filter { MecklenburgPortalsProvider.rhythmValue($0) == nil }
        guard let last = locations.last, let key = Key(last.id), !key.needsMore, !key.ort.isEmpty else { throw ProviderError.selectAddressFirst }
        let rhythm = selections.compactMap(MecklenburgPortalsProvider.rhythmValue).last
        // Ohne Rhythmus-Auswahl gibt es nur eine Variante – das Portal liefert dann nur die passende.
        var flags = rhythm.map { ["ical_\($0)"] } ?? ["ical_1", "ical_11"]
        flags += ["ical_2", "ical_12", "ical_3", "ical_4", "ical_5"]
        let script = key.kreis == "H" ? "ical_uhgw_get_utf8.php" : "ical_rest_get_utf8.php"
        let now = Date()
        let year = calendar.component(.year, from: now)
        let years = calendar.component(.month, from: now) >= 11 ? [year, year + 1] : [year]
        var result: [Pickup] = []
        for target in years {
            let query = flags.map { "\($0)=1" }.joined(separator: "&")
                + "&ical_ort=\(key.ort)&ical_kreis=\(HTTPClient.query(key.kreis))&ical_monat=1&ical_year=\(target)&gesendet=Termine+herunterladen"
            guard let text = try? await client.string("\(Self.base)/abfallkalender/\(script)?\(query)") else { continue }
            result += ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: Self.clean($0.summary)) }
        }
        return result
    }

    /// „Leerung der gelben Säcke“ → „Gelbe Säcke“, „Leerung der Restmülltonne“ → „Restmülltonne“.
    static func clean(_ summary: String) -> String {
        var name = summary.replacingOccurrences(of: #"^\s*Leerung der\s+"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "gelben Säcke", with: "Gelbe Säcke")
        return NameCleaner.clean(name)
    }
}

// MARK: - SDS Schwerin (Gemos WasteBox, Kunde „sds“)

/// Adressauswahl wie bei Gemos WasteBox; der ICS-Export braucht aber die Kategorie (Leerungsrhythmus)
/// je Abfallart, sonst liefert er nur einen Hinweistext. Bei mehreren Kategorien fragt ein Zusatzschritt.
private struct Schwerin {
    let client: HTTPClient
    static let host = "https://sds.wastebox.gemos-management.de/Gemos/WasteBox/Frontend/TourSchedule"

    struct Category { let id: String; let label: String; let selected: Bool }
    struct CategorySelect { let wasteType: String; let name: String; let options: [Category] }

    func page(year: Int, node: String) async throws -> String {
        try await client.string("\(Self.host)/Name/\(year)/?selectedNodeID=\(HTTPClient.query(node))")
    }

    /// Kategorie-Auswahllisten („wtcsl<Abfallart>“) samt Namen der Abfallart.
    static func categories(in html: String) -> [CategorySelect] {
        HTMLText.matches(#"<span>([^<]*)</span>\s*<select id="wtcsl(\d+)"[^>]*>([\s\S]*?)</select>"#, in: html).map { g in
            let options = HTMLText.matches(#"<option value="(\d+)"([^>]*)>([^<]*)</option>"#, in: g[2]).map {
                Category(id: $0[0], label: MecklenburgPortalsProvider.collapse($0[2]), selected: $0[1].contains("selected"))
            }
            return CategorySelect(wasteType: g[1], name: MecklenburgPortalsProvider.collapse(g[0]), options: options)
        }
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        let address = selections.filter { MecklenburgPortalsProvider.rhythmValue($0) == nil }
        let answered = selections.count - address.count
        if answered == 0, let step = try await GemosWasteBoxProvider(customer: "sds", client: client).nextStep(after: address) {
            return step
        }
        guard let node = address.last?.id else { throw ProviderError.selectAddressFirst }
        let year = Calendar.current.component(.year, from: Date())
        let open = Self.categories(in: try await page(year: year, node: node)).filter { $0.options.count > 1 }
        guard answered < open.count else { return nil }
        let select = open[answered]
        return SelectionStep(title: L10n.t("\(select.name): Leerung", "\(select.name): collection"),
                             options: select.options.map { MecklenburgPortalsProvider.rhythmOption($0.id, $0.label) }, searchable: false)
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let address = selections.filter { MecklenburgPortalsProvider.rhythmValue($0) == nil }
        guard let node = address.last?.id else { throw ProviderError.selectAddressFirst }
        let chosen = Set(selections.compactMap(MecklenburgPortalsProvider.rhythmValue))
        let year = calendar.component(.year, from: Date())
        var result: [Pickup] = []
        for target in [year, year + 1] {
            guard let html = try? await page(year: target, node: node),
                  let types = HTMLText.firstMatch(#"id="selectedWasteTypes" name="selectedWasteTypes" value="([^"]+)""#, in: html, group: 1) else { continue }
            // Gewählte Kategorie, sonst die vorausgewählte bzw. erste der Liste.
            let picks = Self.categories(in: html).compactMap { select in
                select.options.first { chosen.contains($0.id) } ?? select.options.first { $0.selected } ?? select.options.first
            }
            let categoryPart = picks.isEmpty ? "" : "/" + picks.map(\.id).joined(separator: ",")
            let url = "\(Self.host)/Raw/Name/\(target)/List/\(HTTPClient.query(node))/\(types)\(categoryPart)/Print/ics/Default/Abfuhrtermine.ics"
            guard let text = try? await client.string(url) else { continue }
            for event in ICS.parse(text, calendar: calendar) {
                let lower = event.summary.lowercased()
                // Hinweistexte des Portals sind keine Termine.
                if lower.contains("abfuhrtermine verfügbar") || lower.contains("gebühr") { continue }
                var name = event.summary
                for pick in picks where name.hasSuffix(" " + pick.label) { name = String(name.dropLast(pick.label.count + 1)) }
                result.append(Pickup(date: event.date, name: NameCleaner.clean(name)))
            }
        }
        return result
    }
}
