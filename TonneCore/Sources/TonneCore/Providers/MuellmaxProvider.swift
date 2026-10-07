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
                html = try await post([("mm_ses", ses), ("xxx", "1"), ("mm_frm_hnr_sel", parts[1]), ("mm_aus_hnr_sel_submit", "weiter")])
            default: break
            }
            ses = token(html)
        }
        return (html, ses)
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
            if !numbers.isEmpty { return SelectionStep(title: SelectionStep.houseNumberTitle, options: numbers.map { SelectionOption(id: "hnr:\($0.value)", title: $0.label) }) }
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
