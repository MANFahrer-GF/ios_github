import Foundation

/// Müllmax (USB Bochum, AWM Münster, EB Mainz, EVS Saar, Hamm, Darmstadt …): Formular-Dialog
/// mit Sitzungs-Token; am Ende gibt es eine ICS-Datei. Müllmax sperrt bei zu vielen Abfragen
/// für 24 Stunden – deshalb nur einmal pro Woche abgleichen.
public struct MuellmaxProvider: WasteProvider {
    public let kind: ProviderKind = .muellmax
    public let serviceKey: String
    public var displayName: String { "Müllmax" }
    private let client: HTTPClient

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    private var url: String { "https://www.muellmax.de/abfallkalender/\(serviceKey.lowercased())/res/\(serviceKey)Start.php" }

    private func checkLimit(_ html: String) throws {
        if html.contains("Abfragelimit wurde überschritten") {
            throw ProviderError.noData(L10n.t("Müllmax hat die Abfrage für 24 Stunden gesperrt (Abfragelimit). Bitte später erneut versuchen.", "Müllmax blocked requests for 24 hours (rate limit). Please try again later."))
        }
    }

    private func post(_ fields: [(String, String)]) async throws -> String {
        let html = HTTPClient.text(from: try await client.postForm(url, fields: fields))
        try checkLimit(html)
        return html
    }

    private func token(_ html: String) -> String {
        HTMLText.hiddenInputs(in: html).first { $0.name == "mm_ses" }?.value ?? ""
    }

    /// Spielt die Auswahl durch: Start → (Ort) → Straße suchen → (Straße wählen) → (Hausnummer).
    private func replay(_ selections: [SelectionOption]) async throws -> (html: String, session: String) {
        var html = HTTPClient.text(from: try await client.get(url))
        try checkLimit(html)
        var ses = token(html)
        html = try await post([("mm_ses", ses), ("mm_aus_ort.x", "0"), ("mm_aus_ort.y", "0")])
        ses = token(html)
        for selection in selections {
            let parts = selection.id.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "ort":
                html = try await post([("mm_ses", ses), ("xxx", "1"), ("mm_frm_ort_sel", parts[1]), ("mm_aus_ort_submit", "weiter")])
            case "strsearch":
                html = try await post([("mm_ses", ses), ("xxx", "1"), ("mm_frm_str_name", parts[1]), ("mm_aus_str_txt_submit", "suchen")])
            case "str":
                html = try await post([("mm_ses", ses), ("xxx", "1"), ("mm_frm_str_sel", parts[1]), ("mm_aus_str_sel_submit", "weiter")])
            case "hnr":
                let number = parts[1].components(separatedBy: Self.streetMarker)[0]
                html = try await post([("mm_ses", ses), ("xxx", "1"), ("mm_frm_hnr_sel", number), ("mm_aus_hnr_sel_submit", "weiter")])
            default: break
            }
            ses = token(html)
        }
        return (html, ses)
    }

    /// Trenner in der Kennung einer Hausnummer: „hnr:5|straße:Kortumstraße“. Die Straße reist in der Kennung statt im Untertitel,
    /// damit die Suche in der Hausnummernliste nicht über den Straßennamen trifft („2a“ fände sonst auch „12“ in der „…allee 2a“).
    static let streetMarker = "|straße:"

    /// Adresskopf der Seite: „<strong>Abfuhrtermine</strong><br />Hauptstraße<br />Mainz“ → „Hauptstraße“.
    static func chosenStreet(in html: String) -> String? {
        guard let raw = HTMLText.firstMatch(#"class="m_symadr">[\s\S]*?</strong>\s*<br\s*/?>\s*([^<]+?)\s*<br"#, in: html, group: 1) else { return nil }
        let street = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return street.isEmpty ? nil : street
    }

    /// „Musterstadt, Hauptstraße, 10“ ohne den getippten Suchtext (Texteingaben haben keine Kennung mit „:“) – aber nur, wenn
    /// danach eine Straße gewählt wurde. Findet das Portal genau eine Straße, springt es gleich zu den Hausnummern
    /// (Bochum „Kortum“, Mainz „Haupt“); dann steht die echte Straße in der Kennung der Hausnummer und ersetzt den Suchtext.
    public func label(for selections: [SelectionOption]) -> String {
        let hasStreet = selections.contains { $0.id.hasPrefix("str:") }
        // Ohne Straßenliste: echte Straße aus dem Adresskopf (in der Kennung der Hausnummer) statt des getippten Suchtexts
        let found = selections.first { $0.id.hasPrefix("hnr:") }?.id.components(separatedBy: Self.streetMarker).dropFirst().first
        return selections.compactMap { option -> String? in
            if option.id.contains(":") { return option.title }
            if hasStreet { return nil }
            return found ?? option.title
        }
            .filter { !$0.isEmpty && $0.lowercased() != "alle hausnummern" && $0.lowercased() != "alle straßen" }
            .joined(separator: ", ")
    }

    /// Texteingaben (id == title) sind die Straßensuche.
    private func normalized(_ selections: [SelectionOption]) -> [SelectionOption] {
        selections.map { option in
            option.id.contains(":") ? option : SelectionOption(id: "strsearch:\(option.title)", title: option.title)
        }
    }

    public func nextStep(after rawSelections: [SelectionOption]) async throws -> SelectionStep? {
        let selections = normalized(rawSelections)
        let (html, _) = try await replay(selections)
        let chosen = Set(selections.compactMap { $0.id.split(separator: ":").first.map(String.init) })
        if !chosen.contains("ort") {
            let cities = HTMLText.options(ofSelect: "mm_frm_ort_sel", in: html).filter { !$0.value.isEmpty }
            if !cities.isEmpty { return SelectionStep(title: SelectionStep.cityTitle, options: cities.map { SelectionOption(id: "ort:\($0.value)", title: $0.label) }) }
        }
        if !chosen.contains("strsearch") {
            return .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Straßenname (Anfang reicht)", "Street name (beginning is enough)"))
        }
        if !chosen.contains("str") {
            let streets = HTMLText.options(ofSelect: "mm_frm_str_sel", in: html).filter { !$0.value.isEmpty }
            if !streets.isEmpty { return SelectionStep(title: SelectionStep.streetTitle, options: streets.map { SelectionOption(id: "str:\($0.value)", title: $0.label) }) }
        }
        if !chosen.contains("hnr") {
            let numbers = HTMLText.options(ofSelect: "mm_frm_hnr_sel", in: html).filter { !$0.value.isEmpty }
            // Ohne Straßenliste (Portal fand genau eine Straße) steht die echte Straße nur im Adresskopf – sie reist in der Kennung mit.
            let street = chosen.contains("str") ? nil : Self.chosenStreet(in: html)
            let suffix = street.map { Self.streetMarker + $0 } ?? ""
            if !numbers.isEmpty { return SelectionStep(title: SelectionStep.houseNumberTitle, options: numbers.map { SelectionOption(id: "hnr:\($0.value)" + suffix, title: $0.label) }) }
        }
        return nil
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        var (html, ses) = try await replay(normalized(selections))
        html = try await post([("mm_ses", ses), ("xxx", "1"), ("mm_ica_auswahl", "iCalendar-Datei")])
        ses = token(html)
        let fractions = HTMLText.matches(#"<input[^>]*name=["'](mm_frm_fra[^"']*)["'][^>]*value=["']([^"']*)["']"#, in: html)
        guard !fractions.isEmpty else { throw ProviderError.noDataGeneric }
        var fields: [(String, String)] = [("mm_ses", ses), ("xxx", "1"), ("mm_frm_type", "termine")]
        for fraction in fractions where fraction.count == 2 { fields.append((fraction[0], fraction[1])) }
        fields.append(("mm_ica_gen", "iCalendar-Datei laden"))
        let ics = try await post(fields)
        let events = ICS.parse(ics, calendar: calendar)
        guard !events.isEmpty else { throw ProviderError.noDataGeneric }
        return events.map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }
}
