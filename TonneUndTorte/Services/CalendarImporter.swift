import Foundation
import SwiftData

/// Übernimmt Termine (aus ICS-Dateien, ICS-Abos oder dem AWIDO-Portal) in die Müllarten eines Standorts.
enum CalendarImporter {

    /// Wohin ein Titel aus der Quelle (z. B. „Gelber Sack“) geschrieben werden soll.
    enum Target: Hashable {
        case ignore
        case existing(WasteType)
        case new(WastePreset)
    }

    /// Ein Titel aus der Quelle mit Anzahl der Termine und dem vorgeschlagenen Ziel.
    struct Mapping: Identifiable {
        let summary: String
        let count: Int
        var target: Target
        var id: String { summary }
    }

    /// Titel, die keine Abholung sind und standardmäßig ignoriert werden.
    private static let ignoredKeywords = ["repair", "café", "cafe", "feiertag", "sprechstunde"]

    /// Schlägt für jeden Titel ein Ziel vor: erst passende vorhandene Müllart (per `sourceKey`
    /// oder Namen), sonst eine neue Müllart auf Basis einer Vorlage.
    static func suggestMappings(for events: [ICSEvent], location: Location?) -> [Mapping] {
        let existing = location?.sortedWasteTypes ?? []
        let grouped = Dictionary(grouping: events, by: { $0.summary })

        return grouped.keys.sorted().map { summary -> Mapping in
            let count = grouped[summary]?.count ?? 0
            let lower = summary.lowercased()

            if ignoredKeywords.contains(where: { lower.contains($0) }) {
                return Mapping(summary: summary, count: count, target: .ignore)
            }
            if let bySource = existing.first(where: { $0.sourceKey == summary }) {
                return Mapping(summary: summary, count: count, target: .existing(bySource))
            }
            if let byName = existing.first(where: { $0.name.lowercased() == lower }) {
                return Mapping(summary: summary, count: count, target: .existing(byName))
            }
            if let guessed = ICSParser.guessWasteType(for: summary, in: existing), guessed.sourceKey == nil {
                return Mapping(summary: summary, count: count, target: .existing(guessed))
            }
            return Mapping(summary: summary, count: count, target: .new(ICSParser.guessPreset(for: summary)))
        }
    }

    /// Schreibt die Termine gemäß Zuordnung in die Müllarten.
    /// - Parameter replace: true ersetzt die bisherigen Einzeltermine der Ziel-Müllart (Abgleich),
    ///   false ergänzt sie nur (Datei-Import).
    @discardableResult
    static func apply(
        events: [ICSEvent],
        mappings: [Mapping],
        location: Location?,
        context: ModelContext,
        replace: Bool,
        calendar: Calendar = .current
    ) -> Int {
        let grouped = Dictionary(grouping: events, by: { $0.summary })
        var importedCount = 0
        var nextSortOrder = (location?.wasteTypes.map(\.sortOrder).max() ?? -1) + 1

        for mapping in mappings {
            guard let dates = grouped[mapping.summary], !dates.isEmpty else { continue }

            let target: WasteType
            switch mapping.target {
            case .ignore:
                continue
            case .existing(let type):
                target = type
            case .new(let preset):
                let type = WasteType(
                    name: mapping.summary,
                    colorHex: preset.colorHex,
                    symbolName: preset.symbolName,
                    sortOrder: nextSortOrder,
                    location: location,
                    sourceKey: mapping.summary
                )
                nextSortOrder += 1
                context.insert(type)
                target = type
            }

            if target.sourceKey == nil {
                target.sourceKey = mapping.summary
            }
            let days = Set(dates.map { calendar.startOfDay(for: $0.date) })
            if replace {
                // Beim Abgleich gilt die Quelle: Rhythmus abschalten, Einzeltermine ersetzen.
                target.intervalWeeks = 0
                target.explicitDates = days.sorted()
                target.skippedDates.removeAll { days.contains(calendar.startOfDay(for: $0)) }
            } else {
                for day in days {
                    target.addExplicitDate(day, calendar: calendar)
                }
            }
            importedCount += days.count
        }

        try? context.save()
        return importedCount
    }

    // MARK: - Online-Abgleich

    /// Lädt die Termine eines Standorts aus seiner Online-Quelle und ersetzt sie lokal.
    @MainActor
    static func sync(location: Location, context: ModelContext) async throws -> Int {
        let events: [ICSEvent]
        switch location.sourceKind {
        case .manual:
            return 0
        case .awido:
            guard let customer = location.awidoCustomer, let oid = location.awidoOid else { return 0 }
            events = try await AwidoClient().pickups(customer: customer, oid: oid)
        case .icsURL:
            guard let urlString = location.icsURLString, let url = URL(string: urlString) else { return 0 }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw URLError(.cannotDecodeContentData)
            }
            events = ICSParser.parse(text)
        }

        let mappings = suggestMappings(for: events, location: location)
        let count = apply(events: events, mappings: mappings, location: location, context: context, replace: true)
        location.lastSyncAt = Date()
        location.lastSyncMessage = "\(count) Termine übernommen"
        try? context.save()
        return count
    }

    // MARK: - Dateien

    /// Lädt eine ICS-Datei aus dem App-Bundle.
    static func bundledEvents(named resource: String) -> [ICSEvent] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "ics"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ICSParser.parse(text)
    }

    /// Liest eine vom Nutzer gewählte Datei (Security-Scoped) ein.
    static func readICSFile(at url: URL) throws -> [ICSEvent] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }
        return ICSParser.parse(text)
    }
}
