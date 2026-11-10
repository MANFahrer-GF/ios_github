import Foundation

// MARK: - Einzelne Stadt- und Gemeindeportale außerhalb NRW (11.11.2026 live geprüft)

/// Je Gemeinde ein eigenes Portal ohne gemeinsame Plattform. Läuft wie `kirchhain` über `portalsNRW`,
/// weil die Weiche dort schon Einzelportale kennt:
/// - `eilenburg`: Stadt Eilenburg, ICS je Gebiet (Restmüll/Papier) und je Gelber-Sack-Bezirk, Links mit Token von der Seite
/// - `weimar_lahn`: Gemeinde Weimar (Lahn), ein Kalender für alle Bezirke, Bezirke je Ortsteil aus der Seitentabelle
/// - `ottobrunn`: Müll App (muellapp.com, Symvaro) – Straße → ggf. Hausnummernabschnitt → ICS je Adresse
/// - `ismaning`: Gemeinde Ismaning, WordPress-Ajax → ICS-Datei je Straße (ggf. Hausnummer) und Jahr
/// - `heilbronn`: Entsorgungsbetriebe Heilbronn, JSON-API (Straße → ggf. Hausnummer → Abfuhrbezirke → Termine)
/// - `erlensee`: Stadt Erlensee, Terminservice mit ICS-Download per Formular
/// - `frankenberg`: Stadt Frankenberg (Eder), Ortsteil → ggf. Straße → ICS per Formular je Jahr
/// - `wismar`: EVB Wismar, Abfuhrrhythmus je Straße (Wochentag, gerade/ungerade KW) plus Feiertagsverschiebungen
/// - `goettingen`: GEB Göttingen, Straßenliste im Seiten-JS, Hausnummer (Text) → ICS je Jahr (`forward.php`)
/// - `giessen`: Stadtreinigung Gießen, Durth-Roos-Kalender wie Herten, Hausnummer (Text) → ICS per Formular
/// - `wetzlar`: Stadt Wetzlar, Sitepark-Abfallkalender je Jahresseite (Straße mit Ortsteil) → ICS je Jahr
/// - `huerth`: Stadtverkehr Hürth (Tonnenalarm), Ortsteil → Straße → Monatsseite mit signiertem ICS-Link
/// - `eppelborn`: AFZE Eppelborn, Bezirksseite → öffentlicher Google-Kalender (Serien mit Ausnahmen)
/// - `waldeck`: Stadt Waldeck (city_info), Ortsteil → Straße aus dem Seiten-JS → ICS je Jahr
/// - `elchingen`, `nersingen`: Knittel Entsorgung, ICS-Dateien je Ortsbereich von der Jahresseite
/// - `ebsdorfergrund`: 123abfallkalender.de, Ortsteil → ICS (Seitenadresse + `.ics`)
/// - `brachttal`: Gemeinde Brachttal, ICS-Datei je Ortsteil aus der Downloadliste der Abfallseite
extension NRWPortalsProvider {
    static let einzelportale: [String: String] = [
        "eilenburg": "Stadt Eilenburg", "weimar_lahn": "Gemeinde Weimar (Lahn)", "ottobrunn": "Müll App Ottobrunn",
        "ismaning": "Gemeinde Ismaning", "heilbronn": "Entsorgungsbetriebe Heilbronn", "erlensee": "Stadt Erlensee",
        "frankenberg": "Stadt Frankenberg (Eder)", "wismar": "EVB Wismar", "goettingen": "GEB Göttingen",
        "giessen": "Stadtreinigung Gießen", "wetzlar": "Stadt Wetzlar", "huerth": "Stadtverkehr Hürth",
        "eppelborn": "AFZE Eppelborn", "waldeck": "Stadt Waldeck", "elchingen": "Knittel Entsorgung (Elchingen)",
        "nersingen": "Knittel Entsorgung (Nersingen)", "ebsdorfergrund": "Gemeinde Ebsdorfergrund", "brachttal": "Gemeinde Brachttal",
    ]

    static let einzelportalOrte: [String: String] = [
        "eilenburg": "Eilenburg", "weimar_lahn": "Weimar (Lahn)", "ottobrunn": "Ottobrunn", "ismaning": "Ismaning",
        "heilbronn": "Heilbronn", "erlensee": "Erlensee", "frankenberg": "Frankenberg (Eder)", "wismar": "Wismar",
        "goettingen": "Göttingen", "giessen": "Gießen", "wetzlar": "Wetzlar", "huerth": "Hürth",
        "eppelborn": "Eppelborn", "waldeck": "Waldeck", "elchingen": "Elchingen", "nersingen": "Nersingen",
        "ebsdorfergrund": "Ebsdorfergrund", "brachttal": "Brachttal",
    ]

    /// Gemeinde-Kennung in der Müll App je `serviceKey`.
    static let muellappTowns: [String: String] = ["ottobrunn": "9184136"]

    func einzelportalStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "eilenburg": return try await eilenburgStep(selections)
        case "weimar_lahn": return try await weimarStep(selections)
        case "ottobrunn": return try await muellappStep(selections)
        case "ismaning": return try await ismaningStep(selections)
        case "heilbronn": return try await heilbronnStep(selections)
        case "erlensee": return try await erlenseeStep(selections)
        case "frankenberg": return try await frankenbergStep(selections)
        case "wismar": return try await wismarStep(selections)
        case "goettingen": return try await goettingenStep(selections)
        case "giessen": return try await giessenStep(selections)
        case "wetzlar": return try await wetzlarStep(selections)
        case "huerth": return try await huerthStep(selections)
        case "eppelborn": return try await eppelbornStep(selections)
        case "waldeck": return try await waldeckStep(selections)
        case "elchingen", "nersingen": return try await knittelStep(selections)
        case "ebsdorfergrund": return try await ebsdorfergrundStep(selections)
        case "brachttal": return try await brachttalStep(selections)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
    }

    func einzelportalPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        switch serviceKey {
        case "eilenburg": return try await eilenburgPickups(selections, calendar: calendar)
        case "weimar_lahn": return try await weimarPickups(selections, calendar: calendar)
        case "ottobrunn": return try await muellappPickups(selections, calendar: calendar)
        case "ismaning": return try await ismaningPickups(selections, calendar: calendar)
        case "heilbronn": return try await heilbronnPickups(selections, calendar: calendar)
        case "erlensee": return try await erlenseePickups(selections, calendar: calendar)
        case "frankenberg": return try await frankenbergPickups(selections, calendar: calendar)
        case "wismar": return try await wismarPickups(selections, calendar: calendar)
        case "goettingen": return try await goettingenPickups(selections, calendar: calendar)
        case "giessen": return try await giessenPickups(selections, calendar: calendar)
        case "wetzlar": return try await wetzlarPickups(selections, calendar: calendar)
        case "huerth": return try await huerthPickups(selections, calendar: calendar)
        case "eppelborn": return try await eppelbornPickups(selections, calendar: calendar)
        case "waldeck": return try await waldeckPickups(selections, calendar: calendar)
        case "elchingen", "nersingen": return try await knittelPickups(selections, calendar: calendar)
        case "ebsdorfergrund": return try await ebsdorfergrundPickups(selections, calendar: calendar)
        case "brachttal": return try await brachttalPickups(selections, calendar: calendar)
        default: throw ProviderError.notSupported(L10n.t("Unbekanntes Portal.", "Unknown portal."))
        }
    }

    private var einzelYear: Int { Calendar(identifier: .gregorian).component(.year, from: referenceDate ?? Date()) }

    /// Text eines Links ohne Tags und mehrfache Leerzeichen.
    static func linkText(_ html: String) -> String {
        HTMLText.decodeEntities(html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Eilenburg

    private static let eilenburgPage = "https://www.eilenburg.de/portal/seiten/abfallwirtschaft-900000136-27670.html?vs=1"

    /// ICS-Links der Seite als (Linktext, Adresse); die Adressen tragen ein wechselndes Token.
    static func eilenburgCalendars(_ html: String) -> [(text: String, url: String)] {
        HTMLText.matches(#"<a\s([^>]*data-extension="ICS"[^>]*)>([\s\S]*?)</a>"#, in: html).compactMap { groups in
            guard let href = HTMLText.firstMatch(#"href="([^"]+)""#, in: groups[0], group: 1) else { return nil }
            return (linkText(groups[1]), HTMLText.decodeEntities(href))
        }
    }

    /// „Restabfallentsorgung - EB Berg“ → „Restabfallentsorgung“, „Entsorgung gelber Sack - EB 5“ → „Gelber Sack“,
    /// „Schadstoffmobil: 08:00 Uhr - 11:30 Uhr“ → („Schadstoffmobil“, Uhrzeit als Notiz).
    static func eilenburgName(_ summary: String) -> (name: String, note: String?) {
        let text = summary.trimmingCharacters(in: .whitespaces)
        if let name = HTMLText.firstMatch(#"^([^:]+):\s*(\d{1,2}:\d{2}.*)$"#, in: text, group: 1) {
            return (name, HTMLText.firstMatch(#"^[^:]+:\s*(.+)$"#, in: text, group: 1))
        }
        var name = text.replacingOccurrences(of: #"\s+-\s+EB\b.*$"#, with: "", options: .regularExpression)
        if name.lowercased() == "entsorgung gelber sack" { name = "Gelber Sack" }
        return (name, nil)
    }

    private func eilenburgStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.count < 2 else { return nil }
        let prefix = selections.isEmpty ? "Restmüll und Papier - " : "Gelber Sack - "
        var seen = Set<String>()
        let options = Self.eilenburgCalendars(try await client.string(Self.eilenburgPage)).compactMap { item -> SelectionOption? in
            guard item.text.hasPrefix(prefix) else { return nil }
            let area = String(item.text.dropFirst(prefix.count))
            return seen.insert(area).inserted ? SelectionOption(id: area, title: area) : nil
        }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        var step = SelectionStep(title: selections.isEmpty ? L10n.t("Gebiet Restmüll und Papier", "Area for residual waste and paper")
                                                           : L10n.t("Bezirk Gelber Sack", "Yellow bag district"),
                                 options: Self.sortedOptions(options), searchable: false)
        step.hint = L10n.t("Welches Gebiet für Ihre Straße gilt, steht im Abfallkalender der Stadt Eilenburg (eilenburg.de).",
                           "The town's waste calendar on eilenburg.de lists which area your street belongs to.")
        return step
    }

    private func eilenburgPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let wanted = ["Restmüll und Papier - " + selections[0].id, "Gelber Sack - " + selections[1].id]
        let links = Self.eilenburgCalendars(try await client.string(Self.eilenburgPage)).filter { wanted.contains($0.text) }
        guard !links.isEmpty else { throw ProviderError.invalidSelection(L10n.t("Das Gebiet steht nicht mehr auf der Seite der Stadt.", "The area is no longer listed by the town.")) }
        var pickups: [Pickup] = []
        for link in links {
            // Feiertagsverschiebungen stehen als Ausnahmen (RECURRENCE-ID) einer Serie in der Datei
            for event in SachsenPortalsProvider.parseICS(try await client.string(link.url), calendar: calendar) {
                let (name, note) = Self.eilenburgName(event.summary)
                pickups.append(Pickup(date: event.date, name: NameCleaner.clean(name), note: note))
            }
        }
        return pickups
    }

    // MARK: Weimar (Lahn)

    private static let weimarPage = "https://www.gemeinde-weimar.de/bauen-wohnen/abfallkalender.html"
    private static let weimarICS = "https://www.gemeinde-weimar.de/index.php?option=com_dpcalendar&task=ical.download&id=66"
    static let weimarNames = ["RM": "Restmüll", "P": "Papier", "GT": "Gelbe Tonne", "Bio": "Biotonne"]

    /// Tabelle „Allna RM 4 P 4 GT 1 Bio 4“ → Ortsteil mit Bezirkskürzeln als Kennung.
    static func weimarDistricts(_ html: String) -> [SelectionOption] {
        let text = linkText(html)
        return HTMLText.matches(#"(\p{Lu}[\p{L}\-]+)\s+RM\s+(\d+)\s+P\s+(\d+)\s+GT\s+(\d+)\s+Bio\s+(\d+)"#, in: text).map {
            SelectionOption(id: "RM \($0[1])|P \($0[2])|GT \($0[3])|Bio \($0[4])", title: $0[0])
        }
    }

    private func weimarStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let options = Self.weimarDistricts(try await client.string(Self.weimarPage))
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.districtTitle, options: Self.sortedOptions(options), searchable: false)
    }

    /// Termine des Gemeindekalenders, deren Titel eines der Bezirkskürzel ist („RM 4“).
    static func weimarPickups(_ events: [ICSEvent], codes: [String]) -> [Pickup] {
        events.compactMap { event in
            let code = event.summary.trimmingCharacters(in: .whitespaces)
            guard codes.contains(code), let kind = code.split(separator: " ").first, let name = weimarNames[String(kind)] else { return nil }
            return Pickup(date: event.date, name: name)
        }
    }

    private func weimarPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let id = selections.first?.id else { throw ProviderError.selectAddressFirst }
        let codes = id.components(separatedBy: "|")
        return Self.weimarPickups(ICS.parse(try await client.string(Self.weimarICS), calendar: calendar), codes: codes)
    }

    // MARK: Müll App (Ottobrunn)

    private static let muellappBase = "https://app.muellapp.com/web-reminder/"

    /// Adressliste: `areas/N` ist eine Adresse, `addresses/T/N` eine Straße mit Hausnummernabschnitten.
    static func muellappOptions(_ html: String) -> [SelectionOption] {
        HTMLText.matches(#"data-ic-get-from="[^"]*/web-reminder/(areas|addresses/\d+)/(\d+)"[^>]*data-name="([^"]*)""#, in: html).map {
            SelectionOption(id: ($0[0] == "areas" ? "a:" : "p:") + $0[1], title: HTMLText.decodeEntities($0[2]))
        }
    }

    private func muellappStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let town = Self.muellappTowns[serviceKey] else { throw ProviderError.noDataGeneric }
        if let last = selections.last, last.id.hasPrefix("a:") { return nil }
        let url: String
        if let last = selections.last { url = Self.muellappBase + "addresses/\(town)/" + last.id.dropFirst(2) } else { url = Self.muellappBase + "addresses/\(town)" }
        let options = Self.muellappOptions(try await client.string(url))
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: selections.isEmpty ? SelectionStep.streetTitle : SelectionStep.houseNumberTitle, options: selections.isEmpty ? Self.sortedOptions(options) : options)
    }

    private func muellappPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let last = selections.last, last.id.hasPrefix("a:") else { throw ProviderError.selectAddressFirst }
        let text = try await client.string("https://app.muellapp.com/ical/" + last.id.dropFirst(2))
        return ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: Ismaning

    private static let ismaningAjax = "https://ismaning.de/wp-admin/admin-ajax.php"
    private static let ismaningHeaders = ["Referer": "https://ismaning.de/umwelt-energie/abfall/abfallkalender/", "X-Requested-With": "XMLHttpRequest"]

    private func ismaningAjax(_ fields: [(String, String)]) async throws -> String {
        HTTPClient.text(from: try await client.postForm(Self.ismaningAjax, fields: fields, headers: Self.ismaningHeaders))
    }

    private func ismaningStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        let year = String(einzelYear)
        switch selections.count {
        case 0:
            let html = try await ismaningAjax([("action", "get_streets"), ("year", year)])
            let options = HTMLText.matches(#"<option data-gebietsnummer="(\d+)">([^<]+)</option>"#, in: html).map {
                SelectionOption(id: $0[0] + "|" + HTMLText.decodeEntities($0[1]), title: HTMLText.decodeEntities($0[1]))
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            let parts = selections[0].id.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw ProviderError.selectAddressFirst }
            let type = try await ismaningAjax([("action", "iap_get_first_at_frontend"), ("street", parts[1]), ("year", year)])
            guard type.trimmingCharacters(in: .whitespacesAndNewlines) == "2" else { return nil }
            let html = try await ismaningAjax([("action", "iap_get_erg_by_second"), ("street", parts[1]), ("year", year), ("gebietsnummer", parts[0])])
            var seen = Set<String>()
            let options = HTMLText.matches(#"<option[^>]*>([^<]+)</option>"#, in: html).compactMap { groups -> SelectionOption? in
                let number = groups[0].trimmingCharacters(in: .whitespaces)
                guard !number.isEmpty, number != "Bitte wählen", seen.insert(number).inserted else { return nil }
                return SelectionOption(id: number, title: number)
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: options)
        default:
            return nil
        }
    }

    private func ismaningPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first?.id.split(separator: "|", maxSplits: 1).last.map(String.init) else { throw ProviderError.selectAddressFirst }
        func year(_ y: Int) async throws -> [Pickup] {
            var fields = [("action", "ics_non_notification_generation"), ("street", street), ("year", String(y))]
            if selections.count > 1 { fields.append(("hnr", selections[1].id)) }
            let link = try await ismaningAjax(fields).trimmingCharacters(in: .whitespacesAndNewlines)
            guard link.hasPrefix("http"), let encoded = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw ProviderError.noDataGeneric }
            return ICS.parse(try await client.string(encoded), calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        }
        let y = einzelYear
        return try await year(y) + ((try? await year(y + 1)) ?? [])
    }

    // MARK: Heilbronn

    private static let heilbronnAPI = "https://api.heilbronn.de/garbage-calendar?method=get&datatype="

    /// Anzeigenamen wie im Abfallkalender der Stadt; die Großbehälter-Rhythmen sind an den Terminabständen gemessen.
    /// `residual_4` zeigt die Stadt nicht an, deshalb fehlt es hier auch.
    static let heilbronnNames: [String: String] = [
        "residual_2": "Restmüll", "residual_big_1": "Restmüll Großbehälter (wöchentlich)", "residual_big_2": "Restmüll Großbehälter (14-täglich)",
        "residual_big_1_2": "Restmüll Großbehälter (2× wöchentlich)", "residual_big_1_3": "Restmüll Großbehälter (3× wöchentlich)",
        "bio": "Biotonne", "bio_1": "Biotonne", "bio_2": "Biotonne", "paper": "Blaue Tonne",
        "paper_big_1": "Blaue Tonne Großbehälter (wöchentlich)", "paper_big_2": "Blaue Tonne Großbehälter (14-täglich)",
        "paper_big_4": "Blaue Tonne Großbehälter (4-wöchentlich)", "paper-bundle": "Altpapier Bündelsammlung",
        "light-packaging": "Gelbe Tonne", "green": "Grünabfälle Bündelsammlung", "christmastree": "Christbaumsammlung",
    ]

    /// Welche Termintypen zu welchem Bezirksfeld gehören (Bezirksfeld → Schlüssel in den Abfuhrdaten).
    static func heilbronnField(_ type: String) -> String? {
        if type == "light-packaging" { return "yellow" }
        if type.hasPrefix("paper") { return "paper" }
        if type.hasPrefix("residual") || type == "christmastree" { return "residual" }
        if type.hasPrefix("bio") { return "bio" }
        if type == "green" { return "green" }
        return nil
    }

    private func heilbronnData(_ type: String) async throws -> [String: Any] {
        let data = try await client.get(Self.heilbronnAPI + type)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let body = root["data"] as? [String: Any] else { throw ProviderError.noDataGeneric }
        return body
    }

    /// Bezirke einer Adresse: `[Postleitzahl][Straße][Hausnummer oder *]`.
    private func heilbronnDistricts(_ selections: [SelectionOption]) async throws -> [String: Any] {
        let parts = selections[0].id.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let street = (try await heilbronnData("districts"))[parts[0]].flatMap({ ($0 as? [String: Any])?[parts[1]] as? [String: Any] }) else {
            throw ProviderError.invalidSelection(L10n.t("Die Straße steht nicht mehr im Abfallkalender.", "The street is no longer listed."))
        }
        return street
    }

    private func heilbronnStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let data = try await heilbronnData("districts")
            var options: [SelectionOption] = []
            for (plz, value) in data {
                for (street, numbers) in (value as? [String: Any]) ?? [:] {
                    let first = ((numbers as? [String: Any])?.values.first as? [String: Any])?["city"] as? [String: Any]
                    let city = (first?["label"] as? String) ?? plz
                    options.append(SelectionOption(id: plz + "|" + street, title: street, subtitle: "\(plz) \(city)"))
                }
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            let street = try await heilbronnDistricts(selections)
            guard street["*"] == nil else { return nil }
            let options = street.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { SelectionOption(id: $0, title: $0) }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: options)
        default:
            return nil
        }
    }

    /// Termine aus den Abfuhrdaten für die Bezirke einer Adresse.
    static func heilbronnPickups(districts: [String: Any], dates: [String: Any], calendar: Calendar) -> [Pickup] {
        var pickups: [Pickup] = []
        for (field, key) in districts where field != "city" && field != "district" {
            guard let key = key as? String, let types = dates[key] as? [String: Any] else { continue }
            for (type, values) in types where heilbronnField(type) == field {
                guard let name = heilbronnNames[type], let values = values as? [String: Any] else { continue }
                for case let text as String in values.values {
                    if let day = isoDay(text, calendar: calendar) { pickups.append(Pickup(date: day, name: name)) }
                }
            }
        }
        return pickups
    }

    private func heilbronnPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard !selections.isEmpty else { throw ProviderError.selectAddressFirst }
        let street = try await heilbronnDistricts(selections)
        guard let districts = (street["*"] ?? (selections.count > 1 ? street[selections[1].id] : nil)) as? [String: Any] else { throw ProviderError.selectAddressFirst }
        return Self.heilbronnPickups(districts: districts, dates: try await heilbronnData("pickupdates"), calendar: calendar)
    }

    // MARK: Erlensee

    private static let erlenseeURL = "https://sperrmuell.erlensee.de/?type=reminder"

    private func erlenseeStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let options = HTMLText.options(ofSelect: "street", in: try await client.string(Self.erlenseeURL)).compactMap {
            $0.value.isEmpty ? nil : SelectionOption(id: $0.value, title: $0.label)
        }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
    }

    /// „Restmüll (Altenburgstraße)“ → „Restmüll“; „Restmüll (MT)“ bleibt (eigene Abfallart).
    static func erlenseeName(_ summary: String, street: String) -> String {
        let suffix = " (\(street))"
        return summary.hasSuffix(suffix) ? String(summary.dropLast(suffix.count)) : summary
    }

    private func erlenseePickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first else { throw ProviderError.selectAddressFirst }
        let page = try await client.string(Self.erlenseeURL)
        // Ganze Jahre und der Halbjahreszeitraum ab heute (reicht über den Jahreswechsel)
        let frames = HTMLText.options(ofSelect: "timeframe", in: page).filter { $0.label.hasPrefix("Gesamtes Jahr") || $0.label == "6 Monate" }.map(\.value)
        let types = HTMLText.matches(#"name='eventType\[\]' value='(\d+)'"#, in: page).map { $0[0] }
        guard !frames.isEmpty, !types.isEmpty else { throw ProviderError.noDataGeneric }
        var pickups: [Pickup] = []
        for frame in frames {
            let fields = [("street", street.id), ("timeframe", frame)] + types.map { ("eventType[]", $0) } + [("download", "ical")]
            let text = HTTPClient.text(from: try await client.postForm(Self.erlenseeURL, fields: fields))
            pickups += ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean(Self.erlenseeName($0.summary, street: street.title))) }
        }
        return pickups
    }

    // MARK: Frankenberg (Eder)

    private static let frankenbergBase = "https://abfall.frankenberg.de/module/abfallkalender/"

    /// `f.ak_ortsteil.options[1].value = '1-1'; f.ak_ortsteil.options[1].text = 'FKB-Kernstadt';` → Optionen.
    static func frankenbergOptions(_ script: String, field: String) -> [SelectionOption] {
        HTMLText.matches(#"\#(field)\.options\[(\d+)\]\.value = '?([^';]*)'?;\s*f\.\#(field)\.options\[\1\]\.text = '([^']*)'"#, in: script).map {
            SelectionOption(id: $0[1], title: HTMLText.decodeEntities($0[2]))
        }
    }

    private func frankenbergStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = Self.frankenbergOptions(try await client.string(Self.frankenbergBase + "get_ortsteile.php?bez_id=1"), field: "ak_ortsteil")
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.districtTitle, options: Self.sortedOptions(options))
        case 1:
            // „2-0“: Ortsteil ohne Straßen; „1-1“: Kernstadt mit Straßenliste
            let district = selections[0].id
            guard !district.hasSuffix("-0"), let id = district.split(separator: "-").first else { return nil }
            let options = Self.frankenbergOptions(try await client.string(Self.frankenbergBase + "get_strassen.php?ot_id=\(id)"), field: "ak_strasse")
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func frankenbergPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let district = selections.first?.id else { throw ProviderError.selectAddressFirst }
        func year(_ y: Int) async throws -> [Pickup] {
            var fields = [("year", String(y)), ("ak_bezirk", "1"), ("ak_ortsteil", district)]
            if selections.count > 1 { fields.append(("ak_strasse", selections[1].id)) }
            fields += [("alle_arten", ""), ("datum_von", "01.01.\(y)"), ("datum_bis", "31.12.\(y)")]
            let text = HTTPClient.text(from: try await client.postForm(Self.frankenbergBase + "generate_ical.php", fields: fields))
            return ICS.parse(text, calendar: calendar).map {
                Pickup(date: $0.date, name: NameCleaner.clean($0.summary.replacingOccurrences(of: #"\s+am\s+\d{1,2}\.\d{1,2}\.\d{4}.*$"#, with: "", options: .regularExpression)))
            }
        }
        let y = einzelYear
        return try await year(y) + ((try? await year(y + 1)) ?? [])
    }

    // MARK: Wismar (EVB)

    private static let wismarURL = "https://www.evb-wismar.de/entsorgung/abfuhrtermine"
    private static let wismarBins: [(header: String, name: String)] = [
        ("Restmüll Tonne", "Restmüll"), ("Gelbe Tonne / Gelbe Säcke", "Gelbe Tonne"), ("Papier-Tonne", "Papiertonne"), ("Bio-Tonne", "Biotonne"),
    ]

    private func wismarResult(_ street: String) async throws -> String {
        let html = HTTPClient.text(from: try await client.postForm(Self.wismarURL, fields: [("FORM_SUBMIT", "COLLECTION_DATE"), ("REQUEST_TOKEN", ""), ("street", street)]))
        guard let start = html.range(of: "collection-date__result") else { throw ProviderError.noDataGeneric }
        let rest = html[start.upperBound...]
        let end = rest.range(of: "Navigation überspringen")?.lowerBound ?? rest.endIndex
        return Self.linkText(String(rest[..<end]))
    }

    /// Ergebnistext → Regeltext je Tonne („Freitag, ungerade Woche“).
    static func wismarSegments(_ text: String) -> [String: String] {
        var body = text
        if let cut = body.range(of: "Fragen rund um die gelbe Tonne") {
            let after = body[cut.upperBound...]
            body = String(body[..<cut.lowerBound]) + " " + (after.range(of: "71030").map { String(after[$0.upperBound...]) } ?? "")
        }
        if let cut = body.range(of: "Von März bis November") { body = String(body[..<cut.lowerBound]) }
        let found = wismarBins.compactMap { bin in body.range(of: bin.header).map { ($0, bin.name) } }.sorted { $0.0.lowerBound < $1.0.lowerBound }
        var result: [String: String] = [:]
        for (index, item) in found.enumerated() {
            let end = index + 1 < found.count ? found[index + 1].0.lowerBound : body.endIndex
            result[item.1] = body[item.0.upperBound..<end].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    static func wismarNeedsNumber(_ segments: [String: String]) -> Bool {
        segments.values.contains { $0.contains("Hausnummer") || $0.contains("Nr.") }
    }

    /// Eine Regel: Wochentag (1 = Sonntag) und KW-Parität (nil = jede Woche).
    struct WismarRule: Equatable { let weekday: Int; let parity: Int? }

    /// Regeltext und Hausnummer → Regeln. Der Text zerfällt an Kommas und vor jedem Wochentag in Abschnitte; ein Abschnitt
    /// ohne Wochentag ergänzt den vorigen („Freitag, gerade Woche“) oder übernimmt dessen Wochentag, wenn der schon einen
    /// Rhythmus hat („Mittwoch gerade Woche Nr. 1-85, ungerade Woche Nr. 87-221“). Nennt ein Abschnitt einen ungeraden
    /// und einen geraden Bereich („Nr. 1-85 und 2-104“), gilt jeder nur für seine Straßenseite, ein einzelner („Nr. 7-9“) für alle; Abschnitte ohne Bereich gelten,
    /// wenn kein Bereich passt („Rest“, „alle anderen“). „(gerade Hausnummer - gerade Kalenderwoche, …)“ macht aus
    /// „wöchentlich“ die Kalenderwoche mit der Parität der Hausnummer. Gewerbe-Abschnitte zählen nicht.
    static func wismarRules(_ segment: String, number: Int?) -> [WismarRule]? {
        let weekdays = ["Montag": 2, "Dienstag": 3, "Mittwoch": 4, "Donnerstag": 5, "Freitag": 6, "Samstag": 7]
        let houseRulePattern = #"\(?gerade Hausnummer\s*-\s*gerade Kalenderwoche,\s*ungerade Hausnummer\s*-\s*ungerade Kalenderwoche\)?"#
        let houseRule = segment.range(of: houseRulePattern, options: .regularExpression) != nil
        let text = segment.replacingOccurrences(of: houseRulePattern, with: " ", options: .regularExpression)
        // Abschnitte: an Kommas/Semikolons und vor jedem Wochentag trennen
        let marked = text.replacingOccurrences(of: #"(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag)"#, with: "|$1", options: .regularExpression)
        let fragments = marked.components(separatedBy: CharacterSet(charactersIn: ",;|")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func weekday(_ f: String) -> Int? { weekdays.first { f.hasPrefix($0.key) }?.value }
        func hasRhythm(_ f: String) -> Bool { f.contains("gerade Woche") || f.contains("wöchentlich") }
        var clauses: [(day: Int, text: String)] = []
        var lead = ""
        for fragment in fragments {
            if let day = weekday(fragment) {
                clauses.append((day, (lead.isEmpty ? "" : lead + " ") + fragment))
                lead = ""
            } else if clauses.isEmpty {
                // „Nr. 7-9: Dienstag …“ – der Bereich steht vor dem Wochentag
                lead += (lead.isEmpty ? "" : " ") + fragment
            } else if let last = clauses.last {
                if hasRhythm(last.text) { clauses.append((last.day, fragment)) } else { clauses[clauses.count - 1].text += " " + fragment }
            }
        }
        guard !clauses.isEmpty else { return text.trimmingCharacters(in: .whitespaces).isEmpty ? [] : nil }
        var ranged: [WismarRule] = [], plain: [WismarRule] = []
        for clause in clauses where !clause.text.contains("Gewerbe") {
            var parity: Int?
            if clause.text.contains("ungerade Woche") {
                parity = 1
            } else if clause.text.contains("gerade Woche") {
                parity = 0
            } else if houseRule {
                guard let number else { return nil }
                parity = number % 2
            }
            let rule = WismarRule(weekday: clause.day, parity: parity)
            let ranges = HTMLText.matches(#"(\d+)\s*-\s*(\d+)"#, in: clause.text).compactMap { g -> (Int, Int)? in
                guard let a = Int(g[0]), let b = Int(g[1]) else { return nil }
                return (a, b)
            }
            let oddOnly = clause.text.contains("ungerade Hausnummern")
            let evenOnly = !oddOnly && clause.text.contains("gerade Hausnummern")
            if ranges.isEmpty && !oddOnly && !evenOnly {
                plain.append(rule)
                continue
            }
            guard let number else { return nil }
            // Seitenweise Bereiche nur, wenn ein gerader und ein ungerader Bereich genannt sind („Nr. 1-85 und 2-104“)
            let sided = Set(ranges.filter { $0.0 % 2 == $0.1 % 2 }.map { $0.0 % 2 }).count == 2
            let inRange = ranges.isEmpty || ranges.contains { a, b in a <= number && number <= b && (!sided || a % 2 != b % 2 || number % 2 == a % 2) }
            let parityOK = (!oddOnly || number % 2 == 1) && (!evenOnly || number % 2 == 0)
            if inRange && parityOK { ranged.append(rule) }
        }
        let rules = ranged.isEmpty ? plain : ranged
        return rules.isEmpty ? nil : rules
    }

    /// Feiertagstabelle: ursprünglicher Tag → (neuer Tag Restmüll/Bio/Papier, neuer Tag Gelbe Tonne); nil = bleibt.
    static func wismarShifts(_ html: String, calendar: Calendar) -> [Date: (Date?, Date?)] {
        func day(_ text: String) -> Date? {
            let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[2], month: parts[1], day: parts[0]))
        }
        var result: [Date: (Date?, Date?)] = [:]
        for row in HTMLText.matches(#"<tr[^>]*>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>"#, in: html) {
            guard let original = day(row[0]) else { continue }
            result[original] = (day(row[1]), day(row[2]))
        }
        return result
    }

    static func wismarDates(_ rules: [WismarRule], bio: Bool, from: Date, to: Date, calendar: Calendar) -> [Date] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        var dates: [Date] = []
        var day = calendar.startOfDay(for: from)
        while day <= to {
            let weekday = calendar.component(.weekday, from: day), week = iso.component(.weekOfYear, from: day)
            let month = calendar.component(.month, from: day)
            for rule in rules where rule.weekday == weekday {
                // Biotonne ohne eigene Angabe: März–November wöchentlich, Dezember–Februar in geraden Kalenderwochen
                let parity = rule.parity ?? (bio && (month == 12 || month <= 2) ? 0 : nil)
                if parity == nil || week % 2 == parity { dates.append(day); break }
            }
            day = Days.add(1, to: day, calendar: calendar)
        }
        return dates
    }

    private func wismarStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let html = try await client.string(Self.wismarURL)
            guard let list = html.range(of: "<datalist") else { throw ProviderError.noDataGeneric }
            let options = HTMLText.matches(#"<option[^>]*>([^<]+)</option>"#, in: String(html[list.lowerBound...])).compactMap { g -> SelectionOption? in
                let name = HTMLText.decodeEntities(g[0]).trimmingCharacters(in: .whitespaces)
                return name.isEmpty || name == "Straße" ? nil : SelectionOption(id: name, title: name)
            }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            guard Self.wismarNeedsNumber(Self.wismarSegments(try await wismarResult(selections[0].id))) else { return nil }
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("Hausnummer, z. B. 12", "House number, e.g. 12"))
        default:
            return nil
        }
    }

    private func wismarPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = selections.first?.id else { throw ProviderError.selectAddressFirst }
        let number = selections.count > 1 ? Int(selections[1].id.prefix { $0.isNumber }) : nil
        let segments = Self.wismarSegments(try await wismarResult(street))
        let shifts = Self.wismarShifts((try? await client.string(Self.wismarURL + "/terminverschiebung")) ?? "", calendar: calendar)
        let today = Days.today(calendar: calendar)
        let (from, to) = (Days.add(-14, to: today, calendar: calendar), Days.add(365, to: today, calendar: calendar))
        let note = L10n.t("Aus dem Abfuhrrhythmus der EVB berechnet", "Calculated from the EVB collection schedule")
        var pickups: [Pickup] = []
        for bin in Self.wismarBins {
            guard let segment = segments[bin.name], let rules = Self.wismarRules(segment, number: number) else { continue }
            for date in Self.wismarDates(rules, bio: bin.name == "Biotonne", from: from, to: to, calendar: calendar) {
                var shifted: Date? = date
                if let shift = shifts[calendar.startOfDay(for: date)] { shifted = (bin.name == "Gelbe Tonne" ? shift.1 : shift.0) ?? date }
                if let shifted { pickups.append(Pickup(date: shifted, name: bin.name, note: note)) }
            }
        }
        return pickups
    }

    // MARK: Göttingen (GEB)

    private static let goettingenURL = "https://www.geb-goettingen.de/abfall/abfallwirtschaft-in-der-stadt-goettingen/abfuhrkalender/"

    /// `const strassen = JSON.parse("{\"146809\":\"Abich-Thiele-Straße\",…}")` → Straßennamen (der Kalender will den Namen).
    static func goettingenStreets(_ html: String) -> [SelectionOption] {
        guard let literal = HTMLText.firstMatch(#"const strassen = JSON\.parse\(("(?:[^"\\]|\\.)*")\)"#, in: html, group: 1),
              let inner = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed) as? String,
              let map = try? JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String: String] else { return [] }
        return Set(map.values).map { SelectionOption(id: $0, title: $0) }
    }

    /// „[GEB] Abfuhr der Restmülltonne“ → „Restmülltonne“, „[GEB] Abfuhr des gelben Sacks“ → „Gelber Sack“.
    static func goettingenName(_ summary: String) -> String {
        let name = summary.replacingOccurrences(of: #"^\[GEB\]\s*(Abfuhr\s+(der|des)\s+)?"#, with: "", options: .regularExpression)
        return name == "gelben Sacks" ? "Gelber Sack" : name
    }

    private func goettingenStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = Self.goettingenStreets(try await client.string(Self.goettingenURL))
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        case 1:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("Hausnummer, z. B. 12", "House number, e.g. 12"))
        default:
            return nil
        }
    }

    private func goettingenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        // Der Kalenderordner trägt das Jahr der Seite (`/2026/preview.php`) und liefert auch das Folgejahr.
        let folder = HTMLText.firstMatch(#"abfuhr\.geb-goettingen\.de/(\d{4})/preview\.php"#, in: try await client.string(Self.goettingenURL), group: 1) ?? String(einzelYear)
        let number = selections[1].id.trimmingCharacters(in: .whitespaces)
        func year(_ y: Int) async throws -> [Pickup] {
            let url = "https://abfuhr.geb-goettingen.de/\(folder)/forward.php?str=\(HTTPClient.query(selections[0].id))&nr=\(HTTPClient.query(number))&year=\(y)"
            return ICS.parse(try await client.string(url), calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean(Self.goettingenName($0.summary))) }
        }
        let y = einzelYear
        let pickups = try await year(y) + ((try? await year(y + 1)) ?? [])
        guard !pickups.isEmpty else { throw Self.notFound(L10n.t("Hausnummer", "house number")) }
        return pickups
    }

    // MARK: Gießen (Durth Roos)

    private static let giessenPage = "https://stadtreinigung.giessen.de/akal/akal1.php"

    private func giessenStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0: return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname, z. B. Alicenstraße", "Street name, e.g. Alicenstraße"))
        case 1: return try await durthRoosStreetStep(Self.giessenPage, query: selections[0].id)
        // Die Hausnummer wählt den Straßenabschnitt und die Behälter der Adresse
        case 2: return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("Hausnummer, z. B. 12", "House number, e.g. 12"))
        default: return nil
        }
    }

    private func giessenPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 3 else { throw ProviderError.selectAddressFirst }
        let parts = selections[1].id.split(separator: "|")
        guard parts.count == 2, let letter = parts[0].first else { throw ProviderError.selectAddressFirst }
        let fields = [("strasse", String(parts[1])), ("hausnr", selections[2].id.trimmingCharacters(in: .whitespaces)), ("ical", "iCalendar")]
        let text = HTTPClient.text(from: try await client.postForm(Self.durthRoosPage(Self.giessenPage, letter), fields: fields))
        guard text.contains("BEGIN:VCALENDAR") else { throw ProviderError.noDataGeneric }
        return ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: Wetzlar (Sitepark-Abfallkalender)

    private static func wetzlarPage(_ year: Int) -> String { "https://www.wetzlar.de/leben-in-wetzlar/abfall-und-entsorgung/abfuhrtermine-\(year).php" }

    /// `<datalist id="sp_garbagecalendar_location--list"><option value="Abelsgasse (Wetzlar)" >…` → Orte.
    static func wetzlarLocations(_ html: String) -> [SelectionOption] {
        guard let list = html.range(of: "sp_garbagecalendar_location--list"), let end = html.range(of: "</datalist>", range: list.upperBound..<html.endIndex) else { return [] }
        return HTMLText.matches(#"<option value="([^"]+)""#, in: String(html[list.upperBound..<end.lowerBound])).map {
            let name = HTMLText.decodeEntities($0[0])
            return SelectionOption(id: name, title: name)
        }
    }

    private func wetzlarStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let options = Self.wetzlarLocations(try await client.string(Self.wetzlarPage(einzelYear)))
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
    }

    private func wetzlarPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let location = selections.first?.id else { throw ProviderError.selectAddressFirst }
        func year(_ y: Int) async throws -> [Pickup] {
            let text = try await client.string(Self.wetzlarPage(y) + "?sp_garbagecalendar_location=\(HTTPClient.query(location))&sp_garbagecalender_icalDownload=true")
            guard text.contains("BEGIN:VCALENDAR") else { return [] }
            return ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        }
        let y = einzelYear
        return try await year(y) + ((try? await year(y + 1)) ?? [])
    }

    // MARK: Hürth (Tonnenalarm der Stadtwerke)

    private static let huerthBase = "https://www.swhmobil.de"

    /// `<select … id="selectDistrict" …>` bzw. `id="selectStreet"` → Optionen (Wert, Text).
    static func huerthOptions(_ html: String, select id: String) -> [SelectionOption] {
        guard let start = html.range(of: "id=\"\(id)\""), let end = html.range(of: "</select>", range: start.upperBound..<html.endIndex) else { return [] }
        return HTMLText.matches(#"<option[^>]*value="([^"]+)"[^>]*>([^<]*)"#, in: String(html[start.upperBound..<end.lowerBound])).compactMap {
            let title = HTMLText.decodeEntities($0[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : SelectionOption(id: HTMLText.decodeEntities($0[0]), title: title)
        }
    }

    /// Relativer Link aus einem Attribut, dessen Wert `marker` enthält (TYPO3-Links tragen ein `cHash`, darum nie selbst bauen).
    static func huerthLink(_ html: String, containing marker: String) -> String? {
        HTMLText.firstMatch(#"(?:href|value|data-url)="(/muellkalender\?[^"]*"# + NSRegularExpression.escapedPattern(for: marker) + #"[^"]*)""#, in: html, group: 1).map(HTMLText.decodeEntities)
    }

    private func huerthStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = Self.huerthOptions(try await client.string(Self.huerthBase + "/muellkalender"), select: "selectDistrict")
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.districtTitle, options: options)
        case 1:
            guard let url = Self.huerthLink(try await client.string(Self.huerthBase + "/muellkalender"), containing: "action%5D=streets") else { throw ProviderError.noDataGeneric }
            let html = HTTPClient.text(from: try await client.postForm(Self.huerthBase + url, fields: [("tx_swhtonnenalarm_pi1[district]", selections[0].id)]))
            let options = Self.huerthOptions(html, select: "selectStreet")
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(options))
        default:
            return nil
        }
    }

    private func huerthPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
        let page = try await client.string(Self.huerthBase + "/muellkalender")
        let types = (HTMLText.firstMatch(#"name="tx_swhtonnenalarm_pi1\[selectedTypes\]" value="([0-9,]+)""#, in: page, group: 1) ?? "1,5,4,2,6,3,7").split(separator: ",")
        let fields = [("tx_swhtonnenalarm_pi1[selectedDistrict]", selections[0].id), ("tx_swhtonnenalarm_pi1[selectedStreet]", selections[1].id)]
            + types.map { ("tx_swhtonnenalarm_pi1[selectedTypes][]", String($0)) }
        // Monatsseite für die Adresse → signierter ICS-Link (Jahr der Monatsseite); im Dezember zusätzlich der Januar
        func calendarFile(_ pageURL: String) async throws -> (ics: [Pickup], next: String?) {
            let html = HTTPClient.text(from: try await client.postForm(Self.huerthBase + pageURL, fields: fields))
            guard let file = Self.huerthLink(html, containing: "action%5D=calendarFile") else { throw ProviderError.noDataGeneric }
            let text = try await client.string(Self.huerthBase + file)
            guard text.contains("BEGIN:VCALENDAR") else { throw ProviderError.noDataGeneric }
            let next = HTMLText.firstMatch(#"id="nextMonthLink"[^>]*value="([^"]+)""#, in: html, group: 1).map(HTMLText.decodeEntities)
            return (ICS.parse(text, calendar: calendar).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }, next)
        }
        guard let current = Self.huerthLink(page, containing: "action%5D=calendarPage") else { throw ProviderError.noDataGeneric }
        let first = try await calendarFile(current)
        var pickups = first.ics
        if calendar.component(.month, from: referenceDate ?? Date()) == 12, let next = first.next {
            pickups += (try? await calendarFile(next).ics) ?? []
        }
        return pickups
    }
}

// MARK: - Eppelborn, Waldeck, Knittel (Elchingen, Nersingen), Ebsdorfergrund, Brachttal (11.11.2026 live geprüft)

extension NRWPortalsProvider {
    /// Jahre, deren Dateien abgefragt werden: das laufende, im Dezember zusätzlich das folgende (darf noch fehlen).
    private var einzelYears: [Int] {
        let today = referenceDate ?? Date()
        return Calendar(identifier: .gregorian).component(.month, from: today) == 12 ? [einzelYear, einzelYear + 1] : [einzelYear]
    }

    private static func year(of date: Date, _ calendar: Calendar) -> Int { calendar.component(.year, from: date) }

    // MARK: Eppelborn (AFZE)

    private static let eppelbornPage = "https://www.afze.de/abfuhrkalender.html"

    /// Bezirksseiten von der Übersicht (jede steht zweimal da, einmal als „Weiterlesen …“).
    static func eppelbornDistricts(_ html: String) -> [SelectionOption] {
        var seen = Set<String>()
        return HTMLText.matches(#"<a[^>]+href="([^"]*abfuhrkalender/articles/[^"]+\.html)"[^>]*>([\s\S]*?)</a>"#, in: html).compactMap { groups in
            let title = linkText(groups[1])
            guard !title.isEmpty, !title.hasPrefix("Weiterlesen"), seen.insert(groups[0]).inserted else { return nil }
            return SelectionOption(id: groups[0], title: title)
        }
    }

    /// „Papier (Rest vom 8. Mai)“ → („Papier“, Notiz); Ziffern („Papier (2)“, zwei Touren im Bezirk) bleiben im Namen.
    static func eppelbornName(_ summary: String) -> (name: String, note: String?) {
        let text = summary.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard let note = HTMLText.firstMatch(#"\(([^)]*)\)\s*$"#, in: text, group: 1), Int(note) == nil else {
            return (text.prefix(1).uppercased() + text.dropFirst(), nil)
        }
        let name = text.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        return (name.prefix(1).uppercased() + name.dropFirst(), note)
    }

    private func eppelbornStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let options = Self.eppelbornDistricts(try await client.string(Self.eppelbornPage))
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        var step = SelectionStep(title: L10n.t("Bezirk", "District"), options: Self.sortedOptions(options), searchable: false)
        step.hint = L10n.t("Welcher Bezirk für Ihre Straße gilt, steht auf afze.de beim jeweiligen Bezirk.",
                           "afze.de lists the streets of each district.")
        return step
    }

    private func eppelbornPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let district = selections.first else { throw ProviderError.selectAddressFirst }
        guard !district.id.contains("://") else { throw ProviderError.invalidSelection(L10n.t("Unbekannter Bezirk.", "Unknown district.")) }
        let page = try await client.string("https://www.afze.de/" + district.id.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard let link = HTMLText.firstMatch(#"(https://calendar\.google\.com/calendar/ical/[^"'<\s]+?/public/basic\.ics)"#, in: page, group: 1) else {
            throw ProviderError.invalidSelection(L10n.t("Der Bezirk hat keinen Kalender mehr.", "The district no longer has a calendar."))
        }
        // Termine als Serien (RRULE mit UNTIL) mit verschobenen Einzelterminen (RECURRENCE-ID) und EXDATE
        return SachsenPortalsProvider.parseICS(try await client.string(HTMLText.decodeEntities(link)), calendar: calendar).map { event in
            let (name, note) = Self.eppelbornName(event.summary)
            return Pickup(date: event.date, name: NameCleaner.clean(name), note: note)
        }
    }

    // MARK: Waldeck (city_info)

    private static let waldeckPage = "https://www.waldeck-stadt.de/Buergerservice/Muellbeseitigung/Muellkalender.htm"

    /// Einträge `{ 'label': "…", 'value': "…" }` der JS-Liste `var <name> = [...]`.
    static func waldeckOptions(_ html: String, list name: String) -> [SelectionOption] {
        guard let body = HTMLText.firstMatch(#"var \#(name) = \[([\s\S]*?)\];"#, in: html, group: 1) else { return [] }
        return HTMLText.matches(#"'label':\s*"([^"]*)",\s*'value':\s*"(\d+)""#, in: body).map {
            SelectionOption(id: $0[1], title: HTMLText.decodeEntities($0[0]))
        }
    }

    private func waldeckStreets(_ city: String) async throws -> [SelectionOption] {
        Self.waldeckOptions(try await client.string("\(Self.waldeckPage)/Abfuhrkalender?&az=all&city_id=\(HTTPClient.query(city))&street_id=0"), list: "streets")
    }

    private func waldeckStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        switch selections.count {
        case 0:
            let options = Self.waldeckOptions(try await client.string(Self.waldeckPage), list: "cities")
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.districtTitle, options: Self.sortedOptions(options), searchable: false)
        case 1:
            let streets = try await waldeckStreets(selections[0].id)
            return streets.isEmpty ? nil : SelectionStep(title: SelectionStep.streetTitle, options: Self.sortedOptions(streets))
        default:
            return nil
        }
    }

    private func waldeckPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let city = selections.first else { throw ProviderError.selectAddressFirst }
        let street = selections.count > 1 ? selections[1].id : "0"
        var pickups: [Pickup] = []
        for (index, year) in einzelYears.enumerated() {
            let url = "https://www.waldeck-stadt.de/city_info/display/ical/m_calendar_ical.cfm?region_id=83&year=\(year)&city_id=\(HTTPClient.query(city.id))&street_id=\(HTTPClient.query(street))"
            // Die Datei des Folgejahres ist bis Dezember leer oder fehlt.
            guard let text = index == 0 ? try await client.string(url) : try? await client.string(url) else { continue }
            pickups += SachsenPortalsProvider.parseICS(text, calendar: calendar).filter { Self.year(of: $0.date, calendar) == year }
                .map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        }
        return pickups
    }

    // MARK: Knittel Entsorgung (Elchingen, Nersingen)

    /// ICS-Dateien der Jahresseite mit Präfix (`ELCHINGEN_`), als (Bereich, Adresse). Der Upload-Pfad wechselt je Jahr.
    static func knittelFiles(_ html: String, prefix: String) -> [(area: String, url: String)] {
        var seen = Set<String>()
        return HTMLText.matches(#"(https?:(?:\\?/){2}[^"'\s<>]+?/\#(prefix)([^"'\s<>/]+?)_\d{4}\.ics)"#, in: html).compactMap { groups in
            seen.insert(groups[1]).inserted ? (groups[1], groups[0].replacingOccurrences(of: "\\/", with: "/")) : nil
        }
    }

    private var knittelPrefix: String { serviceKey.uppercased() + "_" }

    private func knittelYearFiles(_ year: Int) async throws -> [(area: String, url: String)] {
        Self.knittelFiles(try await client.string("https://www.knittel-entsorgung.com/abfuhrkalender-\(year)/"), prefix: knittelPrefix)
    }

    private func knittelStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let files = try await knittelYearFiles(einzelYear)
        guard !files.isEmpty else { throw ProviderError.noDataGeneric }
        // Nur eine Datei (Nersingen): kein Auswahlschritt
        guard files.count > 1 else { return nil }
        let options = files.map { SelectionOption(id: $0.area, title: $0.area.replacingOccurrences(of: "_", with: ", ")) }
        return SelectionStep(title: L10n.t("Ortsbereich", "Area"), options: Self.sortedOptions(options), searchable: false)
    }

    private func knittelPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        var pickups: [Pickup] = []
        for (index, year) in einzelYears.enumerated() {
            // Die Jahresseite des Folgejahres gibt es erst ab Ende des Jahres (sonst 404).
            guard let files = index == 0 ? try await knittelYearFiles(year) : try? await knittelYearFiles(year) else { continue }
            let file: (area: String, url: String)?
            if let area = selections.first?.id { file = files.first { $0.area == area } } else { file = files.count == 1 ? files.first : nil }
            guard let file else {
                if index == 0 { throw selections.isEmpty ? ProviderError.selectAddressFirst
                                                         : ProviderError.invalidSelection(L10n.t("Der Bereich steht nicht mehr auf der Seite.", "The area is no longer listed.")) }
                continue
            }
            pickups += SachsenPortalsProvider.parseICS(try await client.string(file.url), calendar: calendar).filter { Self.year(of: $0.date, calendar) == year }
                .map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        }
        return pickups
    }

    // MARK: Ebsdorfergrund (123abfallkalender.de)

    private static let ebsdorfergrundPage = "https://www.123abfallkalender.de/Ebsdorfergrund"
    private static let abfallkalender123 = "https://www.123abfallkalender.de/abfallkalender/"

    /// Ortsteil-Seiten (`…/abfallkalender/<kalender>/<n>-<ortsteil>`) mit Linktext.
    static func ebsdorfergrundDistricts(_ html: String) -> [SelectionOption] {
        var seen = Set<String>()
        return HTMLText.matches(#"href="(https://www\.123abfallkalender\.de/abfallkalender/[^"?#]+)"[^>]*>([\s\S]*?)</a>"#, in: html).compactMap { groups in
            let title = linkText(groups[1])
            return !title.isEmpty && seen.insert(groups[0]).inserted ? SelectionOption(id: groups[0], title: title) : nil
        }
    }

    private func ebsdorfergrundStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        let options = Self.ebsdorfergrundDistricts(try await client.string(Self.ebsdorfergrundPage))
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.districtTitle, options: Self.sortedOptions(options), searchable: false)
    }

    private func ebsdorfergrundPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let district = selections.first else { throw ProviderError.selectAddressFirst }
        guard district.id.hasPrefix(Self.abfallkalender123) else { throw ProviderError.invalidSelection(L10n.t("Unbekannter Ortsteil.", "Unknown district.")) }
        // Ohne `alert` antwortet der Server mit 500; die Datei enthält alle freigegebenen Jahre.
        return SachsenPortalsProvider.parseICS(try await client.string(district.id + ".ics?alert=never"), calendar: calendar)
            .map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: Brachttal

    private static let brachttalPage = "https://www.brachttal.de/rathaus-buergerschaft/gemeindeverwaltung/abfallentsorgung/"

    /// ICS-Dateien der Downloadliste als (Ortsteil-Kürzel, Jahr, Adresse).
    static func brachttalFiles(_ html: String) -> [(area: String, year: Int, url: String)] {
        var seen = Set<String>()
        return HTMLText.matches(#"(//www\.brachttal\.de/[\w/.-]+/muellkalender-([a-z0-9-]+)-(\d{4})\.ics)"#, in: html).compactMap { groups in
            guard let year = Int(groups[2]), seen.insert(groups[0]).inserted else { return nil }
            return (groups[1], year, "https:" + groups[0])
        }
    }

    /// Einträge der Datei, die keine Abfuhr sind.
    static func brachttalIsPickup(_ summary: String) -> Bool {
        !["Fälligkeit", "Anmeldeschluss"].contains { summary.localizedCaseInsensitiveContains($0) }
    }

    private func brachttalStep(_ selections: [SelectionOption]) async throws -> SelectionStep? {
        guard selections.isEmpty else { return nil }
        var seen = Set<String>()
        let options = Self.brachttalFiles(try await client.string(Self.brachttalPage)).compactMap { file -> SelectionOption? in
            let title = file.area.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            return seen.insert(file.area).inserted ? SelectionOption(id: file.area, title: title) : nil
        }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.districtTitle, options: Self.sortedOptions(options), searchable: false)
    }

    private func brachttalPickups(_ selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let area = selections.first?.id else { throw ProviderError.selectAddressFirst }
        let files = Self.brachttalFiles(try await client.string(Self.brachttalPage)).filter { $0.area == area }
        guard !files.isEmpty else { throw ProviderError.invalidSelection(L10n.t("Der Ortsteil steht nicht mehr auf der Seite der Gemeinde.", "The district is no longer listed by the municipality.")) }
        var pickups: [Pickup] = []
        for file in files {
            // Wiederkehrende Einträge (Serien) nur im Jahr der Datei
            pickups += SachsenPortalsProvider.parseICS(try await client.string(file.url), calendar: calendar)
                .filter { Self.year(of: $0.date, calendar) == file.year && Self.brachttalIsPickup($0.summary) }
                .map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
        }
        return pickups
    }
}
