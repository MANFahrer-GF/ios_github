import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Entsorger in Sachsen mit eigenem Portal. Ein Betreiber je `serviceKey`:
/// - `dresden`: Stadt Dresden (AbfallApp, Wicket-Sitzung) → ICS je Behälterstandort
/// - `zaoe`: ZAOE (Landkreise Meißen und Sächsische Schweiz-Osterzgebirge) → ICS je Straße
/// - `kecl`: KECL (Altkreis Chemnitzer Land, Teile von Zwickau) → ICS je Straße
/// - `lkzwickau`: Landkreis Zwickau, Tourenplan (Wochentag + gerade/ungerade KW) → berechnete Termine
/// - `ekm`: EKM Mittelsachsen → JSON-Termine je Ort/Straße
public struct SachsenPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsSachsen
    public let serviceKey: String
    public var displayName: String { Self.names[serviceKey] ?? kind.displayName }
    private let client: HTTPClient

    static let names: [String: String] = [
        "dresden": "Stadtreinigung Dresden",
        "zaoe": "ZAOE",
        "kecl": "KECL",
        "lkzwickau": "Landkreis Zwickau",
        "ekm": "EKM Mittelsachsen",
    ]

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "dresden": return try await dresdenStep(after: selections)
        case "zaoe": return try await zaoeStep(after: selections)
        case "kecl": return try await keclStep(after: selections)
        case "lkzwickau": return try await zwickauStep(after: selections)
        case "ekm": return try await ekmStep(after: selections)
        default: throw ProviderError.notSupported(L10n.t("Unbekannter Entsorger.", "Unknown operator."))
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let pickups: [Pickup]
        switch serviceKey {
        case "dresden": pickups = try await dresdenPickups(selections, calendar: calendar)
        case "zaoe": pickups = try await zaoePickups(selections, calendar: calendar)
        case "kecl": pickups = try await keclPickups(selections, calendar: calendar)
        case "lkzwickau": pickups = try await zwickauPickups(selections, calendar: calendar)
        case "ekm": pickups = try await ekmPickups(selections, calendar: calendar)
        default: throw ProviderError.notSupported(L10n.t("Unbekannter Entsorger.", "Unknown operator."))
        }
        let result = Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
        guard !result.isEmpty else { throw ProviderError.noDataGeneric }
        return result
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map(\.title)
        switch serviceKey {
        case "dresden":
            // Suchtext weglassen, nur „Dresden, Straße Nr“
            let street = titles.count > 1 ? titles[1] : (titles.first ?? "")
            let number = titles.count > 2 ? " " + titles[2] : ""
            return "Dresden, " + street + number
        case "zaoe":
            // Ort, (Ortsteil), Straße – ohne Behälterauswahl; Ortsteil nur, wenn er sich vom Ort unterscheidet
            guard titles.count >= 3 else { return titles.joined(separator: ", ") }
            let district = titles[1].replacingOccurrences(of: "OT ", with: "")
            return (district == titles[0] ? [titles[0], titles[2]] : [titles[0], district, titles[2]]).joined(separator: ", ")
        default:
            return titles.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    // MARK: - Gemeinsame Hilfen

    static var binTitle: String { L10n.t("Behälter", "Bins") }

    static func sortedOptions(_ options: [SelectionOption]) -> [SelectionOption] {
        var seen = Set<String>()
        return options.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// ICS mit verschobenen Einzelterminen (RECURRENCE-ID) und EXDATE: Der Grundparser kennt nur
    /// einfache Wiederholungen, deshalb werden die Ereignisse hier einzeln ausgewertet und die
    /// ersetzten oder ausgenommenen Tage aus der Serie entfernt.
    static func parseICS(_ text: String, calendar: Calendar) -> [ICSEvent] {
        var blocks: [[String]] = []
        var current: [String]?
        for line in ICS.unfold(text) {
            if line.hasPrefix("BEGIN:VEVENT") {
                current = [line]
            } else if line.hasPrefix("END:VEVENT") {
                if var block = current { block.append(line); blocks.append(block) }
                current = nil
            } else {
                current?.append(line)
            }
        }
        // UID kann nach RECURRENCE-ID stehen – deshalb erst UIDs sammeln, dann die Ausnahmen zuordnen
        let uids = blocks.map { block in block.lazy.map(ICS.split).first { $0.key == "UID" }?.value ?? "" }
        let isOverride = blocks.map { block in block.contains { $0.hasPrefix("RECURRENCE-ID") } }
        var removed: [String: Set<Date>] = [:]
        for (index, block) in blocks.enumerated() {
            for line in block {
                let (key, params, value) = ICS.split(line)
                if key == "RECURRENCE-ID", let date = ICS.parseDate(value, params: params, calendar: calendar) {
                    removed[uids[index], default: []].insert(date)
                } else if key == "EXDATE" {
                    for part in value.split(separator: ",") {
                        if let date = ICS.parseDate(String(part), params: params, calendar: calendar) { removed[uids[index], default: []].insert(date) }
                    }
                }
            }
        }
        var events: [ICSEvent] = []
        for (index, block) in blocks.enumerated() {
            let single = ICS.parse((["BEGIN:VCALENDAR"] + block + ["END:VCALENDAR"]).joined(separator: "\n"), calendar: calendar)
            if isOverride[index] {
                events += single
            } else {
                let skip = removed[uids[index]] ?? []
                events += single.filter { !skip.contains($0.date) }
            }
        }
        return events.sorted { $0.date != $1.date ? $0.date < $1.date : $0.summary < $1.summary }
    }

    // MARK: - Dresden

    static let dresdenBase = "https://www.dresden.de/apps_ext/AbfallApp/"

    private func dresdenStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("z. B. Neumarkt", "e.g. Neumarkt"))
        case 1:
            let query = selections[0].title.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                throw ProviderError.invalidSelection(L10n.t("Bitte mindestens zwei Buchstaben eingeben.", "Please enter at least two letters."))
            }
            let portal = try await DresdenPortal.open()
            defer { portal.close() }
            let streets = try await portal.streets(matching: query)
            guard !streets.isEmpty else {
                throw ProviderError.invalidSelection(L10n.t("Keine passende Straße in Dresden gefunden.", "No matching street found in Dresden."))
            }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0, title: $0) })
        case 2:
            let portal = try await DresdenPortal.open()
            defer { portal.close() }
            let numbers = try await portal.houseNumbers(street: selections[1].id)
            guard !numbers.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: numbers.map { SelectionOption(id: $0.value, title: $0.label) })
        default:
            return nil
        }
    }

    private func dresdenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let portal = try await DresdenPortal.open()
        defer { portal.close() }
        let locations = try await portal.locations(street: selections[1].id, number: selections[2].id)
        guard !locations.isEmpty else { throw ProviderError.noDataGeneric }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        let today = Days.today(calendar: calendar)
        let from = formatter.string(from: Days.add(-14, to: today, calendar: calendar))
        let to = formatter.string(from: Days.add(365, to: today, calendar: calendar))

        var pickups: [Pickup] = []
        for location in locations {
            let primary = "https://stadtplan.dresden.de/project/cardo3Apps/IDU_DDStadtplan/abfall/ical.ashx?STANDORT=\(location)&DATUM_VON=\(from)&DATUM_BIS=\(to)"
            var text = (try? await client.string(primary)) ?? ""
            if !text.contains("BEGIN:VCALENDAR") {
                // Ersatz: iCal-Abo der AbfallApp (kürzerer Zeitraum)
                text = (try? await client.string(Self.dresdenBase + "rest/collection-calendar/v1/stand/\(location)")) ?? ""
            }
            for event in Self.parseICS(text, calendar: calendar) {
                // „Leerung Gelbe Tonne, Bio-Tonne“ → zwei Termine
                var summary = event.summary
                if summary.hasPrefix("Leerung ") { summary.removeFirst("Leerung ".count) }
                guard !summary.lowercased().contains("kalender endet") else { continue }
                for part in summary.components(separatedBy: ", ") where !part.isEmpty {
                    pickups.append(Pickup(date: event.date, name: NameCleaner.clean(part)))
                }
            }
        }
        return pickups
    }

    // MARK: - ZAOE

    static let zaoeBase = "https://www.zaoe.de/abfallkalender/entsorgungstermine/abholtermine/"

    /// Gemeinden je Region des Portals (Region, Ort-ID, Name) – Stand der Gebietszuordnung 06/2025.
    static let zaoeTowns: [(region: String, id: String, name: String)] = [
        // Meißen
        ("1", "7226", "Coswig"), ("1", "7398", "Diera-Zehren"), ("1", "7491", "Käbschütztal"), ("1", "845", "Klipphausen"), ("1", "7445", "Lommatzsch"),
        ("1", "7245", "Meißen"), ("1", "9208", "Moritzburg"), ("1", "7471", "Niederau"), ("1", "7376", "Nossen"), ("1", "7276", "Radebeul"),
        ("1", "7266", "Radeburg"), ("1", "7507", "Weinböhla"),
        // Riesa-Großenhain
        ("2", "36054", "Ebersbach"), ("2", "31971", "Glaubitz"), ("2", "31320", "Gröditz"), ("2", "31401", "Großenhain"), ("2", "12504", "Hirschstein"),
        ("2", "31284", "Lampertswalde"), ("2", "31697", "Nünchritz"), ("2", "31336", "Priestewitz"), ("2", "31490", "Riesa"), ("2", "37785", "Röderaue"),
        ("2", "31429", "Schönfeld"), ("2", "31480", "Stauchitz"), ("2", "33484", "Strehla"), ("2", "31901", "Thiendorf"), ("2", "32295", "Wülknitz"),
        ("2", "31504", "Zeithain"),
        // Sächsische Schweiz
        ("3", "13771", "Bad Gottleuba-Berggießhübel"), ("3", "15101", "Bad Schandau"), ("3", "13928", "Bahretal"), ("3", "13781", "Dohma"), ("3", "14370", "Dohna"),
        ("3", "15568", "Dürrröhrsdorf-Dittersbach"), ("3", "14531", "Gohrisch"), ("3", "14518", "Heidenau"), ("3", "18546", "Hohnstein"), ("3", "14535", "Königstein"),
        ("3", "29583", "Kurort Rathen"), ("3", "14434", "Liebstadt"), ("3", "14839", "Lohmen"), ("3", "480", "Müglitztal"), ("3", "14464", "Neustadt in Sachsen"),
        ("3", "577", "Pirna"), ("3", "14611", "Rathmannsdorf"), ("3", "16713", "Reinhardtsdorf-Schöna"), ("3", "13957", "Rosenthal-Bielatal"), ("3", "14627", "Sebnitz"),
        ("3", "14831", "Stadt Wehlen"), ("3", "14643", "Stolpen"), ("3", "15022", "Struppen"),
        // Weißeritzkreis
        ("4", "18", "Altenberg"), ("4", "72", "Bannewitz"), ("4", "158", "Dippoldiswalde"), ("4", "162", "Dorfhain"), ("4", "229", "Freital"),
        ("4", "254", "Glashütte"), ("4", "311", "Hartmannsdorf-Reichenau"), ("4", "325", "Hermsdorf/Erzgeb."), ("4", "347", "Klingenberg"), ("4", "402", "Kreischa"),
        ("4", "591", "Rabenau"), ("4", "731", "Tharandt"), ("4", "789", "Wilsdruff"),
    ]

    private static func zaoeURL(_ fields: [(String, String)]) -> String {
        zaoeBase + "?" + fields.map { "tx_kalenderausgaben_pi2%5B\($0.0)%5D=\(HTTPClient.query($0.1))" }.joined(separator: "&")
    }

    private func zaoeStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = Self.zaoeTowns.map { SelectionOption(id: "\($0.region)|\($0.id)", title: $0.name) }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(options))
        case 1, 2:
            let parts = selections[0].id.split(separator: "|").map(String.init)
            guard parts.count == 2 else { throw ProviderError.selectAddressFirst }
            var fields = [("auswahl_region", parts[0]), ("auswahl_ort", parts[1])]
            if selections.count == 2 { fields.append(("auswahl_ortsteil", selections[1].id)) }
            let html = try await client.string(Self.zaoeURL(fields))
            let select = selections.count == 1 ? "tx_kalenderausgaben_pi2[auswahl_ortsteil]" : "tx_kalenderausgaben_pi2[auswahl_strasse]"
            let options = HTMLText.options(ofSelect: select, in: html)
                .filter { !$0.value.isEmpty }
                .map { SelectionOption(id: $0.value, title: $0.label) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            let title = selections.count == 1 ? SelectionStep.districtTitle : SelectionStep.streetTitle
            return SelectionStep(title: title, options: selections.count == 1 ? options : Self.sortedOptions(options))
        case 3:
            // Behälterarten des Portals: 1/2 Restabfall, 3 Bio, 4/5 Papier, 6/7 Gelbe Tonne (klein/groß)
            return SelectionStep(title: Self.binTitle, options: [
                SelectionOption(id: "1-3-4-6", title: L10n.t("Haushaltstonnen (80–240 l)", "Household bins (80–240 l)")),
                SelectionOption(id: "2-3-5-7", title: L10n.t("Großbehälter (660/1.100 l)", "Large containers (660/1,100 l)")),
                SelectionOption(id: "1-2-3-4-5-6-7", title: L10n.t("Alle Behältergrößen", "All bin sizes")),
            ], searchable: false)
        default:
            return nil
        }
    }

    private func zaoePickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let street = selections[2].id
        let bins = selections.count > 3 ? selections[3].id : "1-3-4-6"
        // Der Abo-Link enthält immer die laufenden Jahrestermine; „32“ ist der feste Zeitraum-Schlüssel des Portals.
        let text = try await client.string("https://www.zaoe.de/kalender/ical/\(HTTPClient.query(street))/_\(bins)/32/")
        return Self.parseICS(text, calendar: calendar).map { event in
            // „Restabfall 80-240l Behälter / Meißen - Albert-Mücke-Ring“ → „Restabfall 80-240l“
            var name = event.summary.components(separatedBy: " / ").first ?? event.summary
            if name.hasSuffix(" Behälter") { name = String(name.dropLast(" Behälter".count)) }
            // Größe nur nennen, wenn beide Größen gewählt sind
            if bins != "1-2-3-4-5-6-7" {
                name = name.replacingOccurrences(of: #"\s+[0-9][0-9./\-]*l$"#, with: "", options: .regularExpression)
            }
            return Pickup(date: event.date, name: NameCleaner.clean(name))
        }
    }

    // MARK: - KECL

    static let keclBase = "https://www.kecl.de"

    private static func keclURL(_ path: String) -> String {
        keclBase + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
    }

    /// Orte der Sammeltermin-Übersicht: Pfad → Name (Unterorte wie „Schönberg/Breitenbach“ mit Hauptort).
    private func keclTowns() async throws -> [(path: String, title: String)] {
        let html = try await client.string(Self.keclURL("/sammeltermine"))
        var titles: [String: String] = [:]
        var result: [(path: String, title: String)] = []
        for groups in HTMLText.matches(##"<a[^>]*href="(/sammeltermine/[^"#]+)"[^>]*>([^<]+)</a>"##, in: html) {
            let path = HTMLText.decodeEntities(groups[0])
            let name = HTMLText.decodeEntities(groups[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !result.contains(where: { $0.path == path }) else { continue }
            let segments = path.split(separator: "/")
            var title = name
            if segments.count > 2, let parent = titles["/" + segments.prefix(2).joined(separator: "/")] { title = parent + " – " + name }
            titles[path] = title
            result.append((path, title))
        }
        return result
    }

    private func keclStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let towns = try await keclTowns()
            guard !towns.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: towns.map { SelectionOption(id: $0.path, title: $0.title) })
        case 1:
            let town = selections[0].id
            let towns = Set(try await keclTowns().map(\.path))
            let html = try await client.string(Self.keclURL(town))
            let prefix = NSRegularExpression.escapedPattern(for: town + "/")
            let options = HTMLText.matches(##"<a[^>]*href="(\##(prefix)[^"#]+)"[^>]*>([^<]+)</a>"##, in: html).compactMap { groups -> SelectionOption? in
                let path = HTMLText.decodeEntities(groups[0])
                // Unterorte erscheinen ebenfalls als Link unter dem Hauptort
                guard !towns.contains(path) else { return nil }
                return SelectionOption(id: path, title: HTMLText.decodeEntities(groups[1]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func keclPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let html = try await client.string(Self.keclURL(selections[1].id))
        guard let ids = HTMLText.matches(#"ical_kalender\.php\?ort_id=(\d+)&(?:amp;)?strasse_id=(\d+)"#, in: html).first else {
            throw ProviderError.noDataGeneric
        }
        let base = Self.keclBase + "/ical_kalender.php?ort_id=\(ids[0])&strasse_id=\(ids[1])"
        let year = calendar.component(.year, from: Date())
        var pickups: [Pickup] = []
        // Abo-Link = laufendes Jahr; Folgejahr, sobald veröffentlicht
        for url in [base, base + "&jahr=\(year + 1)"] {
            guard let text = try? await client.string(url), text.contains("BEGIN:VCALENDAR") else { continue }
            pickups += Self.parseICS(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        }
        return pickups
    }

    // MARK: - Landkreis Zwickau (Tourenplan)

    static let zwickauURL = "https://www.landkreis-zwickau.de/Tourenplan/tourenplan.aspx"

    /// ASP.NET-Formular: Ort und Straße werden per Postback gewählt, jeweils mit allen versteckten Feldern.
    private func zwickauPostback(_ html: String, fields: [(String, String)], target: String) async throws -> String {
        var form = HTMLText.hiddenInputs(in: html).filter { $0.name.hasPrefix("__") }.map { ($0.name, $0.value) }
        form.removeAll { $0.0 == "__EVENTTARGET" || $0.0 == "__EVENTARGUMENT" }
        form += [("__EVENTTARGET", target), ("__EVENTARGUMENT", "")] + fields
        let data = try await client.postForm(Self.zwickauURL, fields: form)
        return HTTPClient.text(from: data)
    }

    /// Optionswert passend zum gespeicherten (getrimmten) Wert – das Portal füllt Werte mit Leerzeichen auf.
    private static func zwickauValue(_ wanted: String, select: String, in html: String) -> String? {
        let key = wanted.trimmingCharacters(in: .whitespaces).lowercased()
        return HTMLText.options(ofSelect: select, in: html).first { $0.value.trimmingCharacters(in: .whitespaces).lowercased() == key }?.value
    }

    private func zwickauStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.zwickauURL)
            let options = HTMLText.options(ofSelect: "DropDownList1", in: html).compactMap { option -> SelectionOption? in
                let id = option.value.trimmingCharacters(in: .whitespaces)
                return id.isEmpty ? nil : SelectionOption(id: id, title: option.label)
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(options))
        case 1:
            let start = try await client.string(Self.zwickauURL)
            guard let town = Self.zwickauValue(selections[0].id, select: "DropDownList1", in: start) else { throw ProviderError.selectAddressFirst }
            let html = try await zwickauPostback(start, fields: [("DropDownList1", town)], target: "DropDownList1")
            let options = HTMLText.options(ofSelect: "DropDownList2", in: html).compactMap { option -> SelectionOption? in
                let id = option.value.trimmingCharacters(in: .whitespaces)
                return id.isEmpty ? nil : SelectionOption(id: id, title: option.label.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression))
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func zwickauPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let start = try await client.string(Self.zwickauURL)
        guard let town = Self.zwickauValue(selections[0].id, select: "DropDownList1", in: start) else { throw ProviderError.selectAddressFirst }
        let streets = try await zwickauPostback(start, fields: [("DropDownList1", town)], target: "DropDownList1")
        guard let street = Self.zwickauValue(selections[1].id, select: "DropDownList2", in: streets) else {
            throw ProviderError.invalidSelection(L10n.t("Die Straße steht nicht mehr im Tourenplan.", "The street is no longer listed in the collection plan."))
        }
        let html = try await zwickauPostback(streets, fields: [("DropDownList1", town), ("DropDownList2", street)], target: "DropDownList2")
        let rows = HTMLText.matches(#"<td[^>]*font-weight:\s*bold;?"?>([^<]*):\s*</td>\s*<td>([^<]*)</td>"#, in: html)
        let today = Days.today(calendar: calendar)
        let range = (Days.add(-14, to: today, calendar: calendar), Days.add(365, to: today, calendar: calendar))
        var pickups: [Pickup] = []
        for row in rows {
            let name = HTMLText.decodeEntities(row[0]).trimmingCharacters(in: .whitespaces)
            let rhythm = HTMLText.decodeEntities(row[1]).trimmingCharacters(in: .whitespaces)
            guard !["stadt / gemeinde", "straße"].contains(name.lowercased()) else { continue }
            for date in Self.rhythmDates(rhythm, from: range.0, to: range.1, calendar: calendar) {
                pickups.append(Pickup(date: date, name: NameCleaner.clean(name), note: rhythm))
            }
        }
        return pickups
    }

    /// „donnerstags ungerade KW“, „mittwochs ungerade KW / donnerstags gerade KW“ → Tage im Zeitraum.
    /// Grundlage ist die ISO-Kalenderwoche; Feiertagsverschiebungen kennt der Tourenplan nicht.
    static func rhythmDates(_ rhythm: String, from: Date, to: Date, calendar: Calendar) -> [Date] {
        let weekdays = ["sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6, "samstag": 7]
        var rules: [(weekday: Int, parity: Int?)] = []
        for part in rhythm.lowercased().components(separatedBy: "/") {
            guard let weekday = weekdays.first(where: { part.contains($0.key) })?.value else { continue }
            if part.contains("ungerade") {
                rules.append((weekday, 1))
            } else if part.contains("gerade") {
                rules.append((weekday, 0))
            } else if part.contains("wöchentlich") || part.contains("jede") {
                rules.append((weekday, nil))
            }
        }
        guard !rules.isEmpty else { return [] }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        var dates: [Date] = []
        var day = calendar.startOfDay(for: from)
        while day <= to {
            let weekday = calendar.component(.weekday, from: day)
            let week = iso.component(.weekOfYear, from: day)
            if rules.contains(where: { $0.weekday == weekday && ($0.parity == nil || week % 2 == $0.parity) }) { dates.append(day) }
            day = Days.add(1, to: day, calendar: calendar)
        }
        return dates
    }

    // MARK: - EKM Mittelsachsen

    static let ekmBase = "https://www.ekm-mittelsachsen.de/service-dienstleistungen/entsorgungstermine-abfallkalender"

    private struct EKMCity: Decodable {
        let id: String
        let name: String
        let district_id: String?
        let has_streets: Bool?
    }

    private struct EKMStreet: Decodable {
        let id: String
        let name: String
    }

    private struct EKMEvents: Decodable {
        struct Kind: Decodable {
            struct Day: Decodable { let date: String }
            let name: String
            let key: String?
            let dates: [Day]
        }
        let events: [Kind]
    }

    private static func ekmURL(_ plugin: String, _ fields: [(String, String)]) -> String {
        ekmBase + "?" + fields.map { "tx_ekmabfallkalender_\(plugin)%5B\($0.0)%5D=\(HTTPClient.query($0.1))" }.joined(separator: "&")
    }

    /// Orte und Straßen haben je Jahr eigene IDs – verglichen wird deshalb über den Namen.
    private static func ekmKey(_ name: String) -> String {
        name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func ekmCities(year: Int) async throws -> [EKMCity] {
        try await client.json(Self.ekmURL("cities", [("action", "getCities"), ("year", String(year))]))
    }

    private func ekmStreets(city: String) async throws -> [EKMStreet] {
        try await client.json(Self.ekmURL("streets", [("action", "getStreets"), ("city_id", city)]))
    }

    private func ekmStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        let year = Calendar.current.component(.year, from: Date())
        switch selections.count {
        case 0:
            let options = try await ekmCities(year: year).map { city in
                // Kennung: „1|Name“ = Ort mit Straßenauswahl
                SelectionOption(id: ((city.has_streets ?? false) ? "1|" : "0|") + city.name,
                                title: city.name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces))
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sortedOptions(options))
        case 1:
            guard selections[0].id.hasPrefix("1|") else { return nil }
            let key = Self.ekmKey(String(selections[0].id.dropFirst(2)))
            guard let city = try await ekmCities(year: year).first(where: { Self.ekmKey($0.name) == key }) else { throw ProviderError.selectAddressFirst }
            let options = try await ekmStreets(city: city.id).map { street in
                SelectionOption(id: street.name, title: street.name.trimmingCharacters(in: .whitespaces))
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func ekmPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let first = selections.first, first.id.count > 2 else { throw ProviderError.selectAddressFirst }
        let cityKey = Self.ekmKey(String(first.id.dropFirst(2)))
        let streetKey = selections.count > 1 ? Self.ekmKey(selections[1].id) : nil
        if first.id.hasPrefix("1|"), streetKey == nil { throw ProviderError.selectAddressFirst }
        let names = ["r": "Restmüll", "p": "Papier", "l": "Gelbe Tonne", "b": "Bioabfall"]
        let year = calendar.component(.year, from: Date())
        var pickups: [Pickup] = []
        for year in [year, year + 1] {
            // Folgejahr gibt es erst ab Herbst – Fehler dort still übergehen
            guard let cities = try? await ekmCities(year: year),
                  let city = cities.first(where: { Self.ekmKey($0.name) == cityKey }) else { continue }
            var fields = [("action", "getEvents"), ("city_id", city.id)]
            if let streetKey {
                guard let streets = try? await ekmStreets(city: city.id),
                      let street = streets.first(where: { Self.ekmKey($0.name) == streetKey }) else { continue }
                fields.append(("street_id", street.id))
            }
            if let district = city.district_id, !district.isEmpty { fields.append(("district_id", district)) }
            fields.append(("year", String(year)))
            guard let response: EKMEvents = try? await client.json(Self.ekmURL("events", fields)) else { continue }
            for kind in response.events {
                let name = kind.key.flatMap { names[$0] } ?? kind.name
                for day in kind.dates {
                    let parts = day.date.split(separator: ".")
                    guard parts.count == 3, let date = Days.parse("\(parts[2])-\(parts[1])-\(parts[0])", calendar: calendar) else { continue }
                    pickups.append(Pickup(date: date, name: NameCleaner.clean(name)))
                }
            }
        }
        return pickups
    }
}

// MARK: - Dresden: Wicket-Sitzung

/// Die AbfallApp der Stadt Dresden ist eine Wicket-Anwendung mit Sitzung: Ohne Cookie leitet sie
/// endlos um. Die Cookies werden deshalb selbst verwaltet (auch über Weiterleitungen hinweg),
/// danach laufen Straßensuche, Hausnummernliste und Suche als Ajax-Aufrufe derselben Seite.
private final class DresdenPortal: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var cookies: [String: String] = [:]
    private var urlSession: URLSession?
    private var page = ""
    private var baseQuery = "wastebins?0"
    private var behaviors: [(url: String, options: String)] = []

    static func open() async throws -> DresdenPortal {
        let portal = DresdenPortal()
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        portal.urlSession = URLSession(configuration: config, delegate: portal, delegateQueue: nil)
        let (html, url) = try await portal.request(SachsenPortalsProvider.dresdenBase + "wastebins", ajax: false)
        portal.page = html
        if let query = url?.query { portal.baseQuery = "wastebins?" + query }
        portal.absorbBehaviors(html)
        guard portal.behaviors.contains(where: { $0.url.contains("searchForm-street") }) else { throw ProviderError.noDataGeneric }
        return portal
    }

    /// Bricht den Verweis Sitzung → Delegate wieder auf.
    func close() { urlSession?.finishTasksAndInvalidate() }

    // MARK: Schritte

    func streets(matching query: String) async throws -> [String] {
        guard let url = HTMLText.firstMatch(#"Wicket\.AutoComplete\(\{"u":"\./([^"]+)""#, in: page, group: 1) else { return [] }
        let (html, _) = try await request(SachsenPortalsProvider.dresdenBase + url + "&q=" + HTTPClient.query(query), ajax: true)
        return HTMLText.matches(#"textvalue="([^"]*)""#, in: html).map { HTMLText.decodeEntities($0[0]) }.filter { !$0.isEmpty }
    }

    func houseNumbers(street: String) async throws -> [(value: String, label: String)] {
        let html = try await selectStreet(street)
        return HTMLText.options(ofSelect: numberField(in: html), in: html).filter { !$0.value.isEmpty }
    }

    /// Standort-IDs der Abfallbehälter für eine Adresse (meist genau einer).
    func locations(street: String, number: String) async throws -> [String] {
        let numbers = try await selectStreet(street)
        let field = numberField(in: numbers)
        if let change = behavior(containing: "hnr") {
            let (html, _) = try await request(SachsenPortalsProvider.dresdenBase + change, ajax: true, fields: [(field, number)])
            absorbBehaviors(html)
        }
        guard let search = behavior(containing: "searchLink") else { return [] }
        let (html, _) = try await request(SachsenPortalsProvider.dresdenBase + search, ajax: true,
                                          fields: [("street", street), (field, number), ("buttonContainer:searchLink", "1")])
        var ids: [String] = []
        for match in HTMLText.matches(#"(?:STANDORT=|collection-calendar/v1/stand/)(\d+)"#, in: html) where !ids.contains(match[0]) {
            ids.append(match[0])
        }
        return ids
    }

    private func selectStreet(_ street: String) async throws -> String {
        // Wie im Browser: erst das Modell setzen (POST), dann die Hausnummern holen (GET)
        if let post = behaviors.first(where: { $0.url.hasSuffix("searchForm-street") && $0.options.contains("POST") && $0.options.contains("change") }) {
            _ = try? await request(SachsenPortalsProvider.dresdenBase + post.url, ajax: true, fields: [("street", street)])
        }
        guard let get = behaviors.first(where: { $0.url.hasSuffix("searchForm-street") && !$0.options.contains("POST") && $0.options.contains("change") }) else {
            throw ProviderError.noDataGeneric
        }
        let (html, _) = try await request(SachsenPortalsProvider.dresdenBase + get.url + "&street=" + HTTPClient.query(street), ajax: true)
        absorbBehaviors(html)
        return html
    }

    private func numberField(in html: String) -> String {
        HTMLText.firstMatch(#"<select name="([^"]*hnr[^"]*)""#, in: html, group: 1) ?? "hnrContainer:hnr"
    }

    private func behavior(containing part: String) -> String? {
        behaviors.last { $0.url.contains(part) }?.url
    }

    /// Merkt sich alle Ajax-Ziele („u“) aus Seite und Antworten.
    private func absorbBehaviors(_ html: String) {
        for match in HTMLText.matches(#"Wicket\.Ajax\.ajax\(\{"u":"\./([^"]+)"([^}]*)\}"#, in: html) {
            behaviors.append((HTMLText.decodeEntities(match[0]), match[1]))
        }
    }

    // MARK: HTTP mit eigener Cookie-Verwaltung

    private var cookieHeader: String {
        lock.lock(); defer { lock.unlock() }
        return cookies.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
    }

    private func absorbCookies(_ response: URLResponse?) {
        guard let http = response as? HTTPURLResponse, let url = http.url else { return }
        var fields: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            // Unter HTTP/2 kommen die Namen klein geschrieben an
            if let key = key as? String, let value = value as? String { fields[key.lowercased() == "set-cookie" ? "Set-Cookie" : key] = value }
        }
        let found = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        lock.lock(); defer { lock.unlock() }
        for cookie in found { cookies[cookie.name] = cookie.value }
    }

    private func request(_ urlString: String, ajax: Bool, fields: [(String, String)]? = nil) async throws -> (String, URL?) {
        guard let url = URL(string: urlString), let urlSession else { throw HTTPError.badURL(urlString) }
        var request = URLRequest(url: url)
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        let cookie = cookieHeader
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if ajax {
            request.setValue("true", forHTTPHeaderField: "Wicket-Ajax")
            request.setValue(baseQuery, forHTTPHeaderField: "Wicket-Ajax-BaseURL")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        if let fields {
            request.httpMethod = "POST"
            request.httpBody = Data(fields.map { "\(HTTPClient.formEncode($0.0))=\(HTTPClient.formEncode($0.1))" }.joined(separator: "&").utf8)
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        absorbCookies(response)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode, url.host ?? "Server")
        }
        return (HTTPClient.text(from: data), response.url)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Cookies aus der Weiterleitung übernehmen und an die neue Anfrage hängen
        absorbCookies(response)
        var next = request
        let cookie = cookieHeader
        if !cookie.isEmpty { next.setValue(cookie, forHTTPHeaderField: "Cookie") }
        completionHandler(next)
    }
}
