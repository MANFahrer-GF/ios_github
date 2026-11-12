import Foundation

/// Beliebige ICS-Datei im Internet, z. B. der „Sync zu Kalender“-Link eines Abfall-Portals.
public struct ICSURLProvider: WasteProvider {
    public let kind: ProviderKind = .icsURL
    public let serviceKey: String
    public var displayName: String { "ICS-Link" }
    private let client: HTTPClient

    public init(url: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = url
        self.client = client
    }

    /// Ist `serviceKey` selbst ein Kalender-Link? Nur die Portalseiten von mein-abfallkalender.online sind keine –
    /// dort holt man sich den persönlichen iCal-Link. Direktlinks heißen nicht immer „….ics“
    /// (z. B. `admin-post.php?action=mzv_ics_download&slug=Engen`).
    /// `<Seite>#einfuegen`: Portalseite eines Entsorgers, der den Kalender je Straße ausgibt – wie bei
    /// mein-abfallkalender.online kopiert man dort seinen iCal-Link und fügt ihn ein.
    static let pasteMarker = "#einfuegen"

    /// `<Seite>#adresse-zbg`: Zentrale Betriebe Gladbeck – Straße aus der Liste der Seite, Hausnummer als Text; der Kalender
    /// kommt von `<Seite>?format=ical&street=<Kennung>&number=<Nr.>` (der Verlauf hängt an der Hausnummer).
    static let addressMarker = "#adresse-zbg"

    var isDirectLink: Bool {
        if serviceKey.hasSuffix(Self.pasteMarker) || serviceKey.hasSuffix(Self.addressMarker) { return false }
        let lower = serviceKey.lowercased()
        if lower.hasPrefix("webcal://") || lower.contains(".ics") || lower.contains("ical") { return true }
        let host = URL(string: serviceKey)?.host?.lowercased() ?? ""
        return !host.hasSuffix("mein-abfallkalender.online")
    }

    /// Portalseite von mein-abfallkalender.online (keine Kopiervorlage): Straße wählen, Termine aus der Jahresübersicht lesen.
    /// Den iCal-Link verschickt das Portal nur per E-Mail mit Rechenaufgabe; bis 2.0.9 musste der Nutzer ihn selbst
    /// besorgen und einfügen (Portal-Prüfung 12.11.2026: 78 Orte so nicht automatisch nutzbar).
    var isMeinAbfallkalender: Bool {
        !isDirectLink && !serviceKey.hasSuffix(Self.pasteMarker)
            && (URL(string: serviceKey)?.host?.lowercased().hasSuffix("mein-abfallkalender.online") ?? false)
    }

    /// Kennung einer gewählten Straße bei mein-abfallkalender.online.
    static let streetPrefix = "mak:"

    /// Mit dem iPhone-User-Agent der App leitet das Portal auf seine Handy-Ansicht um (ohne Formular, ohne Cookie in
    /// einer Weiterleitungsschleife) – die Desktop-Seite hat Straßenliste und Jahresübersicht.
    static let desktopHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"]

    private var addressPage: String { String(serviceKey.dropLast(Self.addressMarker.count)) }

    private var portalRoot: String {
        guard let url = URL(string: serviceKey), let scheme = url.scheme, let host = url.host else { return serviceKey }
        return "\(scheme)://\(host)/"
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        if serviceKey.hasSuffix(Self.addressMarker) {
            switch selections.count {
            case 0:
                let streets = HTMLText.options(ofSelect: "street", in: try await client.string(addressPage)).filter { !$0.value.isEmpty }
                guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
                return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: $0.value, title: $0.label) })
            case 1:
                return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 12 oder 12a", "e.g. 12 or 12a"))
            default:
                return nil
            }
        }
        if isMeinAbfallkalender {
            guard selections.isEmpty else { return nil }
            let streets = HTMLText.options(ofSelect: "street_id", in: try await client.string(portalRoot, headers: Self.desktopHeaders)).filter { !$0.value.isEmpty }
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: Self.streetPrefix + $0.value, title: $0.label) })
        }
        guard !isDirectLink, selections.isEmpty else { return nil }
        let host = URL(string: serviceKey)?.host ?? serviceKey
        return .text(title: L10n.t("ICS-Link von \(host)", "ICS link from \(host)"),
                     placeholder: L10n.t("Auf \(host) den Link „iCal / Kalender abonnieren“ kopieren und hier einfügen", "Copy the “iCal / subscribe” link on \(host) and paste it here"))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        if let street = selections.last?.id, street.hasPrefix(Self.streetPrefix) {
            return try await meinAbfallkalenderPickups(street: String(street.dropFirst(Self.streetPrefix.count)), calendar: calendar)
        }
        if serviceKey.hasSuffix(Self.addressMarker) {
            guard selections.count >= 2 else { throw ProviderError.selectAddressFirst }
            let number = selections[1].title.trimmingCharacters(in: .whitespaces)
            guard !number.isEmpty else { throw ProviderError.selectAddressFirst }
            let link = "\(addressPage)?format=ical&street=\(HTTPClient.query(selections[0].id))&number=\(HTTPClient.query(number))"
            return Array(Set(try await load(link, year: calendar.component(.year, from: Date()), calendar: calendar))).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
        }
        var link = isDirectLink ? serviceKey : (selections.last?.id ?? "")
        guard !link.isEmpty else { throw ProviderError.selectAddressFirst }
        if link.lowercased().hasPrefix("webcal://") { link = "https://" + link.dropFirst("webcal://".count) }
        let template = link
        let year = calendar.component(.year, from: Date())
        var pickups = try await load(template, year: year, calendar: calendar)
        // Kalender je Jahr ({%Y}): ab November auch die Datei fürs Folgejahr – sonst fehlen dessen Termine bis Neujahr.
        // Gibt es sie noch nicht, bleibt es still beim laufenden Jahr.
        if template.contains("{%Y}"), calendar.component(.month, from: Date()) >= 11,
           let next = try? await load(template, year: year + 1, calendar: calendar) {
            pickups += next
        }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    /// Abfuhrtermine aus dem Kalender eines Jahres.
    private func load(_ template: String, year: Int, calendar: Calendar) async throws -> [Pickup] {
        var link = template.replacingOccurrences(of: "{%Y}", with: String(year))
        var excluded: [String] = []
        var excludedPlaces: [String] = []
        if let marker = link.range(of: Self.excludePlaceMarker) {
            // Eine Datei für mehrere Bezirke, der Bezirk steht im Ort des Termins (MZV Rotenburg-Bebra: „Bebra Bebra 2“).
            excludedPlaces = link[marker.upperBound...].split(separator: "|").map { $0.lowercased() }
            link = String(link[..<marker.lowerBound])
        }
        if let marker = link.range(of: Self.excludeMarker) {
            // Eine Datei für mehrere Bezirke: Termine mit diesen Texten im Titel gehören nicht zur Auswahl.
            excluded = link[marker.upperBound...].split(separator: "|").map { $0.lowercased() }
            link = String(link[..<marker.lowerBound])
        }
        if let marker = link.range(of: Self.pageMarker) {
            // Seite mit wechselndem Kalenderlink (Jahr/Kennung im Dateinamen): den passenden Link auf der Seite suchen.
            let page = String(link[..<marker.lowerBound]), needle = String(link[marker.upperBound...])
            guard let base = URL(string: page), let found = Self.link(in: try await client.string(page), base: base, matching: needle) else {
                throw ProviderError.noData(L10n.t("Kein aktueller Kalender auf \(URL(string: page)?.host ?? page) gefunden.",
                                                  "No current calendar found on \(URL(string: page)?.host ?? page)."))
            }
            link = found.absoluteString
        }
        var form: String?
        if let marker = link.range(of: Self.postMarker) {
            form = String(link[marker.upperBound...])
            link = String(link[..<marker.lowerBound])
        }
        let text: String
        if let form {
            text = HTTPClient.text(from: try await client.post(link, body: Data(form.utf8), contentType: "application/x-www-form-urlencoded"))
        } else {
            text = try await client.string(link)
        }
        let events = ICS.parse(text, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noData("Die ICS-Datei enthält keine Termine.") }
        return events.filter { event in
            !WasteCategory.isIgnorableTitle(event.summary) && !excluded.contains { event.summary.lowercased().contains($0) }
                && !excludedPlaces.contains { (event.location ?? "").lowercased().contains($0) }
        }
            .flatMap { event in Self.names(event.summary).map { Pickup(date: event.date, name: $0, note: event.location) } }
    }

    /// Jahresübersichten („all.2026“, „all.2027“) ab dem laufenden Jahr abrufen; gespeicherte Kopierlinks laufen weiter über ICS.
    private func meinAbfallkalenderPickups(street: String, calendar: Calendar) async throws -> [Pickup] {
        let page = try await client.string(portalRoot, headers: Self.desktopHeaders)
        let year = calendar.component(.year, from: Date())
        let periods = HTMLText.options(ofSelect: "filter_period", in: page).map(\.value)
            .filter { value in value.hasPrefix("all.") && (Int(value.dropFirst(4)) ?? 0) >= year }
        var pickups: [Pickup] = []
        for period in periods.isEmpty ? ["next_20"] : periods {
            let html = HTTPClient.text(from: try await client.postForm(portalRoot, fields: [("street_id", street), ("filter_period", period), ("submit", "Meine Termine anzeigen")], headers: Self.desktopHeaders))
            pickups += Self.meinAbfallkalenderRows(html, calendar: calendar)
        }
        guard !pickups.isEmpty else { throw ProviderError.noDataGeneric }
        return Array(Set(pickups)).sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
    }

    /// Zeilen der Terminliste: „<div class="RM">“ · „Restmüll“ · Wochentag · „07.01.2026“. Öffnungszeiten des Wertstoffhofs
    /// stehen in derselben Liste, sind aber keine Abfuhr.
    static func meinAbfallkalenderRows(_ html: String, calendar: Calendar) -> [Pickup] {
        guard let start = html.range(of: #"id="dates_table""#) else { return [] }
        let table = html[start.upperBound...]
        let end = table.range(of: "</table>")?.lowerBound ?? table.endIndex
        return HTMLText.matches(#"<tr[^>]*class="dates"[^>]*>([\s\S]*?)</tr>"#, in: String(table[..<end])).compactMap { row -> Pickup? in
            let cells = HTMLText.matches(#"<td[^>]*>([\s\S]*?)</td>"#, in: row[0]).map { $0[0] }
            guard cells.count >= 4 else { return nil }
            let code = HTMLText.firstMatch(#"class="([^"]+)""#, in: cells[0], group: 1) ?? ""
            let name = HTMLText.decodeEntities(HTMLText.stripTags(cells[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = HTMLText.stripTags(cells[3]).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3, !name.isEmpty, code != "WeSt", !name.lowercased().contains("wertstoffhof"),
                  let date = Days.parse(String(format: "%04d-%02d-%02d", parts[2], parts[1], parts[0]), calendar: calendar) else { return nil }
            return Pickup(date: date, name: NameCleaner.clean(name))
        }
    }

    /// `<Seite>#link=<Text>`: Kalender ist der erste ICS-Link der Seite, dessen Adresse oder Linktext `<Text>` enthält
    /// (`{%Y}` wird vorher durch das Jahr ersetzt).
    static let pageMarker = "#link="

    /// `<Link>#ohne=<Text>|<Text>`: Termine, deren Titel einen dieser Texte enthält, weglassen
    /// (z. B. Steinbach: eine Datei für Bezirk 1 und 2, Titel „Restmüll (Bezirk 2)“).
    static let excludeMarker = "#ohne="

    /// `<Link>#ohne-ort=<Text>|<Text>`: Termine, deren Ort (LOCATION) einen dieser Texte enthält, weglassen; steht als letzter
    /// Marker (MZV Rotenburg-Bebra: eine Datei für die Kernstadt, Gelbe Tonne in vier Bezirken „Bebra 1“ … „Bebra 4“).
    static let excludePlaceMarker = "#ohne-ort="

    /// `<Link>#post=<Formular>`: Kalender gibt es nur als Antwort auf ein Formular (POST, `a=1&b=2`, `{%Y}` erlaubt);
    /// steht vor `#ohne=`/`#ohne-ort=` (Ginsheim-Gustavsburg: `/export/ical` mit Zeitraum, Bezirk und Abfuhrarten).
    static let postMarker = "#post="

    static func link(in html: String, base: URL, matching needle: String) -> URL? {
        let wanted = needle.lowercased()
        for anchor in HTMLText.matches(#"<a\s[^>]*?href="([^"]+)"[^>]*>([\s\S]*?)</a>"#, in: html) {
            let href = anchor[0].replacingOccurrences(of: "&amp;", with: "&")
            let text = anchor[1].replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let lower = href.lowercased()
            guard lower.contains(".ics") || lower.contains("ical") || lower.hasPrefix("webcal:") else { continue }
            if lower.contains(wanted) || text.lowercased().contains(wanted) {
                return URL(string: href, relativeTo: base)?.absoluteURL
            }
        }
        return nil
    }

    /// Abfallart(en) aus einem Kalendertitel: „Abholung: Biomüll“ → „Biomüll“, „Abfalltermin (Restmüll)“ → „Restmüll“.
    /// Sammeltermine („Biomüll, Restmüll“, „Restmüll / Gelbe Tonne“) werden aufgeteilt, wenn jeder Teil eine andere
    /// Tonnenart ist – sonst ginge die Erinnerung an die zweite Tonne verloren.
    /// Gehört ein früher gespeicherter Titel (vor der Bereinigung durch `names`) zu diesem Namen?
    /// „Abholung: Biomüll“ → „Biomüll“; bei einem früheren Sammeltermin „Biomüll, Restmüll“ nur der erste Teil,
    /// damit genau eine Müllart die Termine weiterführt und der zweite Teil eine neue bekommt.
    public static func formerTitle(_ old: String, matches name: String) -> Bool {
        old != name && names(old).first == name
    }

    /// „Biotonne (Abholzeit)“ → „Biotonne“ (Stadtreinigung Leipzig).
    static func withoutPickupTimeSuffix(_ summary: String) -> String {
        summary.replacingOccurrences(of: #"\s*\(Abholzeit\)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    static func names(_ summary: String) -> [String] {
        var name = NameCleaner.clean(withoutPickupTimeSuffix(summary))
            .replacingOccurrences(of: #"^(Abholung|Abfuhr|Leerung)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let inner = HTMLText.firstMatch(#"^Abfalltermin\s*\((.+)\)$"#, in: name, group: 1) { name = inner }
        // MZV Rotenburg-Bebra: „Entsorgung Gelbe Tonne“ (zweite SUMMARY-Zeile des Termins)
        if let inner = HTMLText.firstMatch(#"^Entsorgung\s+(.+)$"#, in: name, group: 1) { name = inner }
        // VUE Waltrop: „Abfuhr Rest+Bio Bezirk 1“ – der Bezirk steht schon im Eintrag, nicht in der Müllart
        if let inner = HTMLText.firstMatch(#"^Abfuhr\s+(.+?)\s+Bezirk\s+\d+$"#, in: name, group: 1) { name = inner }
        // Wachtendonk: „Bezirk 1 - Restmuell (grau)“, „Bezirk 1 - 4 - Glaskoerbe“ – Bezirk und Tonnenfarbe stehen schon im
        // Eintrag; die Umschrift wechselt zwischen den Jahresdateien („Restmuell“ 2026, „Restmüll“ 2027)
        if let inner = HTMLText.firstMatch(#"^Bezirk\s+\d+(?:\s*-\s*\d+)?\s+-\s+(.+)$"#, in: name, group: 1) {
            name = inner.replacingOccurrences(of: #"\s*\((grau|braun|gruen|grün|gelb|blau)\)$"#, with: "", options: .regularExpression)
            for (from, to) in [("muell", "müll"), ("Muell", "Müll"), ("gruen", "grün"), ("Gruen", "Grün"), ("koerbe", "körbe")] {
                name = name.replacingOccurrences(of: from, with: to)
            }
        }
        // Ginsheim-Gustavsburg: „Grüne Tonne - Ginsheim“, „Gelbe Tonne - Alle“ – der Bezirk steht schon im Eintrag
        if let inner = HTMLText.firstMatch(#"^(.+?)\s+-\s+\p{Lu}\p{Ll}+$"#, in: name, group: 1), WasteCategory.classify(inner) != .other {
            name = inner
        }
        let parts = name.components(separatedBy: CharacterSet(charactersIn: ",/+"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let categories = parts.map(WasteCategory.classify)
        if parts.count > 1, !categories.contains(.other), Set(categories).count == parts.count { return parts }
        return [name.isEmpty ? NameCleaner.clean(summary) : name]
    }
}

/// Ordnet Termintitel beim Abgleich vorhandenen Müllarten zu. Jede Müllart höchstens einmal – sonst ersetzt
/// ein zweiter Titel beim Abgleich die Termine des ersten (z. B. früherer Sammeltermin, auf den zweiten Teil umbenannt).
/// Reihenfolge: gleicher Quellen-Titel, dann früherer Titel vor der Bereinigung (`ICSURLProvider.formerTitle`), dann gleicher Name.
public enum WasteTitleMatching {
    public struct Existing {
        public let sourceKey: String?
        public let name: String
        public init(sourceKey: String?, name: String) { self.sourceKey = sourceKey; self.name = name }
    }

    /// Titel → Index in `existing`; nicht zugeordnete Titel fehlen im Ergebnis.
    /// `exclusive: false` (Datei-Import): eine Müllart darf mehreren Titeln zugeordnet werden.
    public static func assign(_ summaries: [String], to existing: [Existing], exclusive: Bool = true) -> [String: Int] {
        var result: [String: Int] = [:]
        var used = Set<Int>()
        func pass(_ match: (Existing, String) -> Bool) {
            for summary in summaries where result[summary] == nil {
                if let index = existing.indices.first(where: { !used.contains($0) && match(existing[$0], summary) }) {
                    result[summary] = index
                    if exclusive { used.insert(index) }
                }
            }
        }
        pass { $0.sourceKey == $1 }
        pass { type, summary in type.sourceKey.map { ICSURLProvider.formerTitle($0, matches: summary) } ?? false }
        pass { $0.name.lowercased() == $1.lowercased() }
        return result
    }
}
