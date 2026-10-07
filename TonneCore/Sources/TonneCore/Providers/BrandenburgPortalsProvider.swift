import Foundation

/// Portale brandenburgischer Entsorger ohne gemeinsame Plattform:
/// - `potsdam`: Stadt Potsdam – Gatsby-JSON je Jahr mit Abfuhrregeln, Termine werden lokal berechnet
/// - `kwu`: KWU Entsorgung (LK Oder-Spree) – Ort → Straße → Hausnummer, ICS-Link nach Formular-POST
/// - `spn`: Eigenbetrieb Abfallwirtschaft Spree-Neiße – Termine als JSON im versteckten ICS-Feld der Seite
/// - `kaev`: KAEV Niederlausitz – Adresssuche (ajax) und ICS je Ort/Ortsteil/Straße
/// - `ffo`: Frankfurt (Oder) – FDH nutzt AbfallPlus (api.abfall.io), daher Weitergabe an `AbfallIOLegacyProvider`
public struct BrandenburgPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsBrandenburg
    public let serviceKey: String
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public var displayName: String {
        switch serviceKey {
        case "potsdam": return "Stadt Potsdam"
        case "kwu": return "KWU Entsorgung"
        case "spn": return L10n.t("Abfallwirtschaft Spree-Neiße", "Spree-Neiße waste management")
        case "kaev": return "KAEV Niederlausitz"
        case "ffo": return "FDH Frankfurt (Oder)"
        default: return kind.displayName
        }
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "potsdam": return try await Potsdam(client: client).nextStep(after: selections)
        case "kwu": return try await KWU(client: client).nextStep(after: selections)
        case "spn": return try await SpreeNeisse(client: client).nextStep(after: selections)
        case "kaev": return try await KAEV(client: client).nextStep(after: selections)
        case "ffo": return try await frankfurtOder.nextStep(after: selections)
        default: throw unknownService
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard !selections.isEmpty else { throw ProviderError.selectAddressFirst }
        let pickups: [Pickup]
        switch serviceKey {
        case "potsdam": pickups = try await Potsdam(client: client).pickups(for: selections, calendar: calendar)
        case "kwu": pickups = try await KWU(client: client).pickups(for: selections, calendar: calendar)
        case "spn": pickups = try await SpreeNeisse(client: client).pickups(for: selections, calendar: calendar)
        case "kaev": pickups = try await KAEV(client: client).pickups(for: selections, calendar: calendar)
        case "ffo": return try await frankfurtOder.pickups(for: selections, calendar: calendar)
        default: throw unknownService
        }
        guard !pickups.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map(\.title).filter { !$0.isEmpty }
        switch serviceKey {
        case "potsdam":
            // Rhythmus-Auswahlen gehören nicht zur Adresse.
            return (["Potsdam"] + titles.prefix(2)).joined(separator: ", ")
        case "kwu":
            // „Erkner, Heinrich-Heine-Straße 11“
            guard titles.count >= 3 else { return titles.joined(separator: ", ") }
            return "\(titles[0]), \(titles[1]) \(titles[2])"
        case "ffo":
            return "Frankfurt (Oder), " + frankfurtOder.label(for: selections)
        default:
            return titles.joined(separator: ", ")
        }
    }

    private var frankfurtOder: AbfallIOLegacyProvider {
        AbfallIOLegacyProvider(key: "727d02ea16b7dd4b34781c8b167d5d9f", client: client)
    }

    private var unknownService: ProviderError {
        .invalidSelection(L10n.t("Unbekannter Entsorger.", "Unknown waste operator."))
    }
}

// MARK: - Hilfen

private enum BBDate {
    /// Tag im Kalender des Nutzers (Tagesanfang).
    static func day(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date? {
        Days.parse(String(format: "%04d-%02d-%02d", year, month, day), calendar: calendar)
    }

    static func currentYear(calendar: Calendar) -> Int {
        calendar.component(.year, from: Date())
    }
}

// MARK: - Potsdam

/// Potsdam: Die Seite geben-und-nehmen-markt.de/abfallkalender/potsdam liefert je Jahr ein großes JSON
/// (Gatsby page-data) mit Regeln je Straße. Welche Tonne in welchem Rhythmus geleert wird, wählt der Nutzer;
/// die Termine werden wie im JavaScript der Seite berechnet (ISO-Wochen, Ausnahmen bei Feiertagen).
private struct Potsdam {
    let client: HTTPClient

    struct PageData: Decodable {
        struct Result: Decodable { let data: DataNode }
        struct DataNode: Decodable { let dbapi: DBAPI }
        struct DBAPI: Decodable { let allRegionen: [Gruppe] }
        struct Gruppe: Decodable { let regionen: [Region] }
        struct Region: Decodable { let ortsteile: [Ortsteil] }
        struct Ortsteil: Decodable { let name: String; let strassen: [Strasse] }
        struct Strasse: Decodable { let name: String; let eintraege: [Eintrag] }
        let result: Result

        var ortsteile: [Ortsteil] { result.data.dbapi.allRegionen.flatMap(\.regionen).flatMap(\.ortsteile) }
    }

    struct Eintrag: Decodable {
        let typ: Int
        let rhythmus: Int
        let tag1: Int
        let tag2: Int
        let woche: Int
        let beginn: Int
        let termin1: String?
        let termin2: String?
        let ausnahmen: String?
        let hinweise: String?
    }

    /// Tonnenarten mit wählbarem Rhythmus (Typ im JSON).
    enum Bin: Int { case rest = 1, bio = 2, gelb = 3, papier = 4 }

    static let typeNames: [Int: String] = [
        1: "Restabfall", 2: "Bioabfall", 3: "Leichtverpackungen", 4: "Altpapier",
        5: "Biotonnenreinigung", 6: "Weihnachtsbaumabholung", 7: "Grünabfallsammlung",
    ]

    /// Rhythmus-Kennung im JSON → „Turnus“ der Seite (1 = 2× pro Woche, 2 = wöchentlich, 3 = 14-tägig, 4 = 4-wöchentlich).
    static let turnusForRhythmus: [Int: Int] = [4: 1, 1: 2, 2: 3, 3: 4]

    static func turnusTitle(_ turnus: Int) -> String {
        switch turnus {
        case 1: return L10n.t("2× pro Woche", "Twice a week")
        case 2: return L10n.t("wöchentlich", "Weekly")
        case 3: return L10n.t("14-tägig", "Every two weeks")
        case 4: return L10n.t("4-wöchentlich", "Every four weeks")
        case 5: return L10n.t("Kombileerung (April–Oktober wöchentlich, sonst 14-tägig)", "Combined (weekly April–October, otherwise every two weeks)")
        default: return L10n.t("keine Tonne", "No bin")
        }
    }

    func load(year: Int) async throws -> PageData {
        let data = try await client.get("https://www.geben-und-nehmen-markt.de/abfallkalender/potsdam/\(year)/page-data/index/page-data.json")
        return try HTTPClient.decode(data)
    }

    func street(in page: PageData, district: String, street: String) -> PageData.Strasse? {
        page.ortsteile.first { $0.name.trimmingCharacters(in: .whitespaces) == district }?
            .strassen.first { $0.name.trimmingCharacters(in: .whitespaces) == street }
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let page = try await load(year: BBDate.currentYear(calendar: .current))
            let names = Set(page.ortsteile.map { $0.name.trimmingCharacters(in: .whitespaces) }).filter { !$0.isEmpty }
            guard !names.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.districtTitle, options: names.sorted(by: Self.sortNames).map { SelectionOption(id: $0, title: $0) })
        case 1:
            let page = try await load(year: BBDate.currentYear(calendar: .current))
            let district = selections[0].id
            guard let ortsteil = page.ortsteile.first(where: { $0.name.trimmingCharacters(in: .whitespaces) == district }) else {
                throw ProviderError.invalidSelection(L10n.t("Ortsteil nicht gefunden.", "District not found."))
            }
            let names = Set(ortsteil.strassen.map { $0.name.trimmingCharacters(in: .whitespaces) }).filter { !$0.isEmpty }
            return SelectionStep(title: SelectionStep.streetTitle, options: names.sorted(by: Self.sortNames).map { SelectionOption(id: $0, title: $0) })
        case 2, 3, 4:
            let page = try await load(year: BBDate.currentYear(calendar: .current))
            guard let street = street(in: page, district: selections[0].id, street: selections[1].id) else {
                throw ProviderError.invalidSelection(L10n.t("Straße nicht gefunden.", "Street not found."))
            }
            let bin: Bin = [Bin.rest, .bio, .papier][selections.count - 2]
            var turnus = Set(street.eintraege.filter { $0.typ == bin.rawValue }.compactMap { Self.turnusForRhythmus[$0.rhythmus] })
            if bin == .bio, turnus.contains(2), turnus.contains(3) { turnus.insert(5) }
            let title: String
            switch bin {
            case .rest: title = L10n.t("Restabfall-Rhythmus", "General waste interval")
            case .bio: title = L10n.t("Biotonne-Rhythmus", "Organic bin interval")
            default: title = L10n.t("Papiertonne-Rhythmus", "Paper bin interval")
            }
            let options = (turnus.sorted() + [0]).map { SelectionOption(id: String($0), title: Self.turnusTitle($0)) }
            return SelectionStep(title: title, options: options, searchable: false)
        default:
            return nil
        }
    }

    static func sortNames(_ a: String, _ b: String) -> Bool {
        a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let rhythm = { (index: Int) in selections.count > index ? Int(selections[index].id) ?? 0 : 0 }
        let rules = Rules(rest: rhythm(2), bio: rhythm(3), papier: rhythm(4))
        let year = BBDate.currentYear(calendar: calendar)
        var pickups: [Pickup] = []
        for y in [year, year + 1] {
            // Das Folgejahr erscheint erst gegen Jahresende.
            guard let page = try? await load(year: y) else {
                if y == year { throw ProviderError.noDataGeneric }
                continue
            }
            guard let street = street(in: page, district: selections[0].id, street: selections[1].id) else { continue }
            pickups += rules.pickups(year: y, entries: street.eintraege, calendar: calendar)
        }
        return pickups
    }

    /// Nachbau der Berechnung aus dem Abfallkalender-JavaScript.
    struct Rules {
        let rest: Int
        let bio: Int
        let papier: Int

        private static let utc: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()

        private static let iso: Calendar = {
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()

        /// Ein Kalendertag ohne Uhrzeit.
        struct Day: Equatable {
            let year: Int, month: Int, day: Int
            var mmdd: Int { month * 100 + day }

            var date: Date { Rules.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }
            var isoWeek: Int { Rules.iso.component(.weekOfYear, from: date) }
            /// Montag = 1 … Sonntag = 7
            var weekday: Int { (Rules.utc.component(.weekday, from: date) + 5) % 7 + 1 }

            /// „dd.MM.yyyy“
            init?(german: String) {
                let parts = german.split(separator: ".").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                self.init(year: parts[2], month: parts[1], day: parts[0])
            }

            /// „2026-04-29T00:00:00.000Z“
            init?(iso text: String?) {
                guard let text, text.count >= 10 else { return nil }
                let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                self.init(year: parts[0], month: parts[1], day: parts[2])
            }

            init(year: Int, month: Int, day: Int) {
                self.year = year; self.month = month; self.day = day
            }
        }

        func pickups(year: Int, entries: [Eintrag], calendar: Calendar) -> [Pickup] {
            var result: [Pickup] = []
            for entry in entries {
                guard let name = Potsdam.typeNames[entry.typ] else { continue }
                // Ohne eigene Tonne keine Termine dieser Art (Reinigung nur mit Biotonne).
                if entry.typ == 1 && rest == 0 || entry.typ == 2 && bio == 0 || entry.typ == 4 && papier == 0 || entry.typ == 5 && bio == 0 { continue }
                var days: [Day] = []
                switch entry.typ {
                case 5, 6:
                    days = [Day(iso: entry.termin1), Day(iso: entry.termin2)].compactMap { $0 }
                case 7:
                    days = [Day(iso: entry.termin1)].compactMap { $0 }
                default:
                    let exceptions = Self.exceptions(entry.ausnahmen)
                    var date = Rules.utc.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12))!
                    while Rules.utc.component(.year, from: date) == year {
                        let c = Rules.utc.dateComponents([.year, .month, .day], from: date)
                        let day = Day(year: c.year!, month: c.month!, day: c.day!)
                        if isCollection(entry, day, exceptions: exceptions, checkExceptions: true) { days.append(day) }
                        date = Rules.utc.date(byAdding: .day, value: 1, to: date)!
                    }
                }
                let note = entry.typ == 7 ? Self.locations(entry.hinweise) : nil
                for day in days {
                    guard let date = BBDate.day(day.year, day.month, day.day, calendar: calendar) else { continue }
                    result.append(Pickup(date: date, name: NameCleaner.clean(name), note: note))
                }
            }
            return result
        }

        /// Ausnahmen „von → nach“ in Originalreihenfolge.
        static func exceptions(_ json: String?) -> [(from: Day, to: Day)] {
            guard let json else { return [] }
            return HTMLText.matches(#""(\d{2}\.\d{2}\.\d{4})"\s*:\s*"(\d{2}\.\d{2}\.\d{4})""#, in: json).compactMap { groups in
                guard let from = Day(german: groups[0]), let to = Day(german: groups[1]) else { return nil }
                return (from, to)
            }
        }

        /// Sammelstellen der Grünabfallsammlung als Notiz.
        static func locations(_ json: String?) -> String? {
            guard let json, let data = json.data(using: .utf8),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !items.isEmpty else { return nil }
            let lines = items.compactMap { item -> String? in
                guard let place = item["standort"] as? String else { return nil }
                let street = HTMLText.decodeEntities(item["strasse"] as? String ?? "")
                let time = [item["zeitvon"] as? String, item["zeitbis"] as? String].compactMap { $0 }.joined(separator: "–")
                return [street.isEmpty ? place : "\(street) (\(place))", time].filter { !$0.isEmpty }.joined(separator: ", ")
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }

        private func typeMatches(_ day: Day, typ: Int, turnus: Int) -> Bool {
            let summer = (401...1031).contains(day.mmdd)
            switch typ {
            case 1: return rest == turnus
            case 2: return bio == turnus || bio == 5 && (turnus == 2 && summer || turnus == 3 && !summer)
            case 3: return true
            case 4: return papier == turnus
            default: return false
            }
        }

        private func isCollection(_ entry: Eintrag, _ day: Day, exceptions: [(from: Day, to: Day)], checkExceptions: Bool) -> Bool {
            if checkExceptions {
                // Verlegter Termin: zählt, wenn der ursprüngliche Tag ein Abfuhrtag gewesen wäre.
                if let moved = exceptions.first(where: { $0.to == day }) {
                    return isCollection(entry, moved.from, exceptions: exceptions, checkExceptions: false)
                }
                if exceptions.contains(where: { $0.from == day }) { return false }
            }
            let week = day.isoWeek
            let even = week % 2 == 0
            let dow = day.weekday
            switch entry.rhythmus {
            case 1:
                return typeMatches(day, typ: entry.typ, turnus: 2)
                    && (entry.tag1 == dow && entry.tag2 == 0 || entry.tag1 == dow && !even || entry.tag2 == dow && even)
            case 2:
                return typeMatches(day, typ: entry.typ, turnus: 3)
                    && (entry.woche == 2 && !even || entry.woche == 3 && even) && entry.tag1 == dow
            case 3:
                return typeMatches(day, typ: entry.typ, turnus: 4)
                    && (week - entry.beginn) % 4 == 0 && entry.tag1 == dow
            case 4:
                return typeMatches(day, typ: entry.typ, turnus: 1)
                    && (entry.tag1 == dow || entry.tag2 > 0 && entry.tag2 == dow) && week >= entry.beginn
            default:
                return false
            }
        }
    }
}

// MARK: - KWU Entsorgung (Landkreis Oder-Spree)

private struct KWU {
    let client: HTTPClient
    static let base = "https://kalender.kwu-entsorgung.de"

    /// `<option value="…">Text</option>` ohne umgebendes `<select>`.
    static func options(_ html: String) -> [SelectionOption] {
        HTMLText.matches(#"<option[^>]*value="([^"]*)"[^>]*>([^<]*)"#, in: html).compactMap { groups in
            let title = HTMLText.decodeEntities(groups[1])
                .replacingOccurrences(of: " -- ", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !groups[0].isEmpty, !title.isEmpty else { return nil }
            return SelectionOption(id: HTMLText.decodeEntities(groups[0]), title: title)
        }
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.base + "/")
            let towns = HTMLText.options(ofSelect: "ort", in: html).map { SelectionOption(id: $0.value, title: $0.label) }
            guard !towns.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: towns.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        case 1:
            let html = try await client.string(Self.base + "/kal_str2ort.php?ort=\(HTTPClient.query(selections[0].id))")
            let streets = Self.options(html)
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets)
        case 2:
            let html = try await client.string(Self.base + "/kal_str2ort.php?ort=\(HTTPClient.query(selections[0].id))&strasse=\(HTTPClient.query(selections[1].id))")
            let numbers = Self.options(html)
            guard !numbers.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: numbers)
        default:
            return nil
        }
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let year = BBDate.currentYear(calendar: calendar)
        var pickups: [Pickup] = []
        for y in [year, year + 1] {
            do {
                let data = try await client.postForm(Self.base + "/kal_uebersicht-2023.php", fields: [
                    ("ort", selections[0].id), ("strasse", selections[1].id), ("objekt", selections[2].id), ("jahr", String(y)),
                ])
                // Der Link heißt intern teils „kalender.kwu.lokal“.
                guard let link = HTMLText.firstMatch(#"href="([^"]*kal_ical[^"]*)""#, in: HTTPClient.text(from: data), group: 1) else { continue }
                let url = HTMLText.decodeEntities(link).replacingOccurrences(of: "http://kalender.kwu.lokal", with: Self.base)
                let ics = try await client.string(url)
                pickups += ICS.parse(ics, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
            } catch {
                // Das Folgejahr gibt es erst gegen Jahresende.
                if y == year { throw error }
            }
        }
        return pickups
    }
}

// MARK: - Eigenbetrieb Abfallwirtschaft Landkreis Spree-Neiße

/// Seiten /termine/abfuhrtermine/<Jahr>/<Gemeinde>/<Ort-oder-Straße>.html; das versteckte Feld „ics“
/// enthält alle Termine des Jahres als JSON (Kürzel → „dd.MM.“).
private struct SpreeNeisse {
    let client: HTTPClient
    static let base = "https://www.eigenbetrieb-abfallwirtschaft.de"
    static let names = ["RM": "Restmüll", "BIO": "Biotonne", "PP": "Papier", "LVP": "Gelbe Tonne / Sack", "SP": "Sperrmüll"]

    /// Die Seiten sind Windows-1252-kodiert (sorbische Ortsnamen mit š, ž), melden aber ISO-8859-1.
    func page(_ path: String) async throws -> String {
        let data = try await client.get(Self.base + path)
        if let text = String(data: data, encoding: .utf8) { return text }
        return Self.decodeWindows1252(data)
    }

    /// Eigene Dekodierung, weil Foundation unter Linux die Zeichen 0x80–0x9F verwirft.
    static func decodeWindows1252(_ data: Data) -> String {
        let high: [UInt32] = [
            0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
            0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
        ]
        var scalars = String.UnicodeScalarView()
        for byte in data {
            let value = (0x80...0x9F).contains(byte) ? high[Int(byte) - 0x80] : UInt32(byte)
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
        return String(scalars)
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await page("/termine/abfuhrtermine.html")
            let options = HTMLText.options(ofSelect: "group", in: html).compactMap { option -> SelectionOption? in
                guard let id = HTMLText.firstMatch(#"/abfuhrtermine/\d{4}/(\d+)\.html"#, in: option.value, group: 1) else { return nil }
                return SelectionOption(id: id, title: option.label)
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Stadt / Gemeinde", "Town / municipality"), options: options.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        case 1:
            let year = BBDate.currentYear(calendar: .current)
            let group = selections[0].id
            let html = try await page("/termine/abfuhrtermine/\(year)/\(group).html")
            guard let select = HTMLText.firstMatch(#"<select name="type[\s\S]*?</select>"#, in: html, group: 0) else { throw ProviderError.noDataGeneric }
            var options: [SelectionOption] = []
            // Gruppen: „Gemeinde“, „Ortsteil“, „Straßenverzeichnis …“
            for part in select.components(separatedBy: "<optgroup").dropFirst() {
                let label = HTMLText.decodeEntities(HTMLText.firstMatch(#"label="([^"]*)""#, in: part, group: 1) ?? "")
                let subtitle = label.hasPrefix("Straßen") ? L10n.t("Straße", "Street") : (label == "Ortsteil" ? L10n.t("Ortsteil", "District") : L10n.t("Ort", "Town"))
                for groups in HTMLText.matches(#"value="[^"]*/abfuhrtermine/\d{4}/(\d+/\d+)\.html"[^>]*>([^<]*)"#, in: part) {
                    options.append(SelectionOption(id: groups[0], title: HTMLText.decodeEntities(groups[1]).trimmingCharacters(in: .whitespaces), subtitle: subtitle))
                }
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Ort / Straße", "Town / street"), options: options)
        default:
            return nil
        }
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let year = BBDate.currentYear(calendar: calendar)
        var pickups: [Pickup] = []
        for y in [year, year + 1] {
            guard let html = try? await page("/termine/abfuhrtermine/\(y)/\(selections[1].id).html") else {
                if y == year { throw ProviderError.noDataGeneric }
                continue
            }
            guard let json = HTMLText.firstMatch(#"name="ics" value='([^']*)'"#, in: html, group: 1),
                  let object = try? JSONSerialization.jsonObject(with: Data(HTMLText.decodeEntities(json).utf8)) as? [String: [String]] else { continue }
            for (key, dates) in object {
                let name = Self.names[key] ?? key
                for text in dates {
                    let parts = text.split(separator: ".").compactMap { Int($0) }
                    guard parts.count >= 2, let date = BBDate.day(y, parts[1], parts[0], calendar: calendar) else { continue }
                    pickups.append(Pickup(date: date, name: NameCleaner.clean(name)))
                }
            }
        }
        return pickups
    }
}

// MARK: - KAEV Niederlausitz

/// Adresssuche über ajax.aspx/getAddress (Teilstring), ICS über iCal.aspx mit Name, OrtId und OrtsteilId.
private struct KAEV {
    let client: HTTPClient
    static let base = "https://www.kaev.de/Templates/Content/DetailTourenplanWebsite"

    /// Orte des Verbands (OrtId → Name), aus der Adresssuche des Portals.
    static let towns: [(id: Int, name: String)] = [
        (19, "Altdöbern"), (26, "Alt Zauche"), (5, "Bersteland"), (20, "Bronkow"), (28, "Byhleguhre"), (29, "Byhlen"),
        (24, "Calau"), (15, "Drahnsdorf"), (14, "Golßen"), (72, "Großräschen"), (7, "Groß Wasserburg"), (18, "Heideblick"),
        (30, "Jamlitz"), (16, "Kasel-Golzig"), (6, "Krausnick"), (31, "Lieberose"), (1, "Lübben (Spreewald)"),
        (2, "Lübbenau/ Spreewald"), (23, "Luckaitztal"), (25, "Luckau"), (13, "Märkische Heide"), (22, "Neu-Seeland"),
        (21, "Neupetershain"), (32, "Neu Zauche"), (8, "Rietzneuendorf"), (10, "Schlepzig"), (11, "Schönwald"),
        (33, "Schwielochsee"), (34, "Spreewaldheide"), (9, "Staakow"), (17, "Steinreich"), (35, "Straupitz"),
        (12, "Unterspreewald"), (3, "Vetschau /Spreewald"), (27, "Wußwerk"),
    ]

    struct Address: Decodable {
        let name: String
        let ortId: Int
        let ortsteilId: Int?
    }

    struct Wrapper: Decodable { let d: String }

    func search(_ query: String) async throws -> [Address] {
        let body = try JSONSerialization.data(withJSONObject: ["query": query])
        let data = try await client.post(Self.base + "/ajax.aspx/getAddress", body: body, contentType: "application/json; charset=utf-8")
        let wrapper: Wrapper = try HTTPClient.decode(data)
        return try HTTPClient.decode(Data(wrapper.d.utf8))
    }

    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.towns.map { town in
                SelectionOption(id: String(town.id), title: town.name.replacingOccurrences(of: "/ ", with: "/").replacingOccurrences(of: " /", with: "/"))
            }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        case 1:
            guard let ortId = Int(selections[0].id), let town = Self.towns.first(where: { $0.id == ortId }) else {
                throw ProviderError.invalidSelection(L10n.t("Ort nicht gefunden.", "Town not found."))
            }
            let found = try await search(town.name).filter { $0.ortId == ortId }
            guard !found.isEmpty else { throw ProviderError.noDataGeneric }
            let prefix = town.name + " / "
            let options = found.map { address -> SelectionOption in
                let rest = address.name.hasPrefix(prefix) ? String(address.name.dropFirst(prefix.count)) : address.name
                let title = address.name == town.name ? L10n.t("ganzer Ort", "Whole town") : rest
                // Kennung: OrtId|OrtsteilId|Suchname (für die ICS-Adresse)
                return SelectionOption(id: "\(address.ortId)|\(address.ortsteilId.map(String.init) ?? "null")|\(address.name)", title: title)
            }
            return SelectionStep(title: L10n.t("Ortsteil / Straße", "District / street"), options: options.sorted { a, b in
                // „ganzer Ort“ zuerst, dann Ortsteile, dann Straßen
                func rank(_ o: SelectionOption) -> Int { o.id.hasSuffix("|" + town.name) ? 0 : (o.title.hasPrefix("OT ") || o.title.hasPrefix("GT ") ? 1 : 2) }
                return rank(a) != rank(b) ? rank(a) < rank(b) : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            })
        default:
            return nil
        }
    }

    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let parts = selections[1].id.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { throw ProviderError.selectAddressFirst }
        let url = Self.base + "/iCal.aspx?Ort=\(HTTPClient.query(parts[2]))&OrtId=\(parts[0])&OrtsteilId=\(parts[1])"
        var text = try await client.string(url)
        // Manche Dateien haben eine leere VTIMEZONE „W. Europe Standard Time“.
        text = text.replacingOccurrences(of: "TZID=W. Europe Standard Time;", with: "")
        return ICS.parse(text, calendar: calendar).map { event in
            var name = event.summary.trimmingCharacters(in: .whitespaces)
            if name.hasSuffix(",") { name.removeLast() }
            return Pickup(date: event.date, name: NameCleaner.clean(name))
        }
    }
}
