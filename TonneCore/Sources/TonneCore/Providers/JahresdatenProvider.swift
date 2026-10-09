import Foundation

/// Termine aus PDF-Abfallkalendern, die einmal im Jahr mit `tools/pdfkalender` ausgelesen werden
/// (Format: `tools/pdfkalender/FORMAT.md`). Die Daten liegen in `JahresdatenData.swift`; `serviceKey` ist der Ort.
public struct JahresdatenProvider: WasteProvider {
    public let kind: ProviderKind = .jahresdaten
    public let serviceKey: String
    public var displayName: String { data?.title ?? serviceKey }
    /// Stichtag für „künftige Termine“; nil = heute (nur Tests setzen ihn).
    var referenceDate: Date?
    private let data: Jahresdaten?

    public init(key: String) {
        self.init(key: key, json: JahresdatenData.files[key])
    }

    init(key: String, json: String?) {
        serviceKey = key
        data = json.flatMap { try? JSONDecoder().decode(Jahresdaten.self, from: Data($0.utf8)) }
    }

    struct Jahresdaten: Decodable {
        struct Area: Decodable { let id: String; let title: String; let group: String?; let plan: String }
        let title: String
        let source: String
        let stand: String
        let years: [Int]
        let groupTitle: String?
        let stepTitle: String
        let notice: String?
        let areas: [Area]
        let plans: [String: [[String]]]
    }

    static let groupPrefix = "gruppe:"

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        guard let data else { throw Self.missing }
        guard data.areas.count > 1 else { return nil }
        let last = selections.last
        if let last, !last.id.hasPrefix(Self.groupPrefix) { return nil }
        if let last {
            let group = String(last.id.dropFirst(Self.groupPrefix.count))
            return SelectionStep(title: data.stepTitle, options: Self.sorted(data.areas.filter { $0.group == group }.map { SelectionOption(id: $0.id, title: $0.title) }))
        }
        // Erste Stufe: Gruppen (z. B. Orte mit Straßen) und Einträge ohne Gruppe in einer Liste
        let groups = Set(data.areas.compactMap(\.group)).map { SelectionOption(id: Self.groupPrefix + $0, title: $0) }
        let single = data.areas.filter { $0.group == nil }.map { SelectionOption(id: $0.id, title: $0.title) }
        return SelectionStep(title: groups.isEmpty ? data.stepTitle : (data.groupTitle ?? data.stepTitle), options: Self.sorted(groups + single))
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let data else { throw Self.missing }
        let area = data.areas.count == 1 ? data.areas.first : data.areas.first { $0.id == selections.last?.id }
        guard let area, let plan = data.plans[area.plan] else { throw ProviderError.selectAddressFirst }
        let pickups = plan.compactMap { entry -> Pickup? in
            guard entry.count >= 2, let date = Days.parse(entry[0], calendar: calendar) else { return nil }
            return Pickup(date: date, name: entry[1], note: entry.count > 2 ? entry[2] : nil)
        }
        let today = Days.start(of: referenceDate ?? Date(), calendar: calendar)
        guard pickups.contains(where: { $0.date >= today }) else {
            let year = calendar.component(.year, from: today)
            throw ProviderError.noData(L10n.t("Der Abfallkalender \(year) für \(data.title) ist noch nicht eingepflegt – er kommt mit einem App-Update.",
                                              "The \(year) calendar for \(data.title) has not been added yet – it will come with an app update."))
        }
        return pickups
    }

    /// „Stadt Ansbach, Adlerstraße“ – bei einstufiger Auswahl fehlt sonst der Ort; zweistufig („Bürgel, Markt“) wie üblich.
    public func label(for selections: [SelectionOption]) -> String {
        guard let data else { return serviceKey }
        let titles = selections.map(\.title)
        if data.areas.count == 1 || titles.isEmpty { return data.title }
        if selections.first?.id.hasPrefix(Self.groupPrefix) == true { return titles.joined(separator: ", ") }
        return ([data.title] + titles).joined(separator: ", ")
    }

    public var notice: String? {
        guard let data else { return nil }
        let stand = Days.parse(data.stand).map { $0.formatted(.dateTime.day().month(.twoDigits).year()) } ?? data.stand
        let years = data.years.map(String.init).joined(separator: "/")
        var text = L10n.t("Termine aus dem PDF-Abfallkalender \(years) (\(data.title), Stand \(stand)). Kurzfristige Änderungen veröffentlicht nur der Entsorger.",
                          "Dates from the \(years) PDF waste calendar (\(data.title), as of \(stand)). Short-notice changes are published only by the provider.")
        if let extra = data.notice { text += " " + extra }
        return text
    }

    private static func sorted(_ options: [SelectionOption]) -> [SelectionOption] {
        options.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static var missing: ProviderError {
        .noData(L10n.t("Für diesen Ort sind keine Kalenderdaten hinterlegt.", "No calendar data for this place."))
    }
}
