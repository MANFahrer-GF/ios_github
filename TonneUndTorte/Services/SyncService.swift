import Foundation
import SwiftData
import TonneCore

/// Holt Termine aus den Online-Quellen, ordnet sie Müllarten zu und erkennt Verschiebungen.
enum SyncService {
    struct Result {
        var importedCount: Int
        var changes: [String]   // lesbare Änderungen, z. B. „Gelber Sack: 8. Okt. → 9. Okt.“
    }

    /// Zuordnung eines Quellen-Titels zu einer Müllart.
    enum Target: Hashable {
        case ignore
        case existing(WasteType)
        case new(WasteCategory)
    }

    struct Mapping: Identifiable {
        let summary: String
        let count: Int
        var target: Target
        var id: String { summary }
    }

    static func suggestMappings(for pickups: [Pickup], location: Location?) -> [Mapping] {
        let existing = location?.sortedWasteTypes ?? []
        let grouped = Dictionary(grouping: pickups, by: \.name)
        return grouped.keys.sorted().map { summary in
            let count = grouped[summary]?.count ?? 0
            if WasteCategory.isIgnorableTitle(summary) {
                return Mapping(summary: summary, count: count, target: .ignore)
            }
            if let bySource = existing.first(where: { $0.sourceKey == summary }) {
                return Mapping(summary: summary, count: count, target: .existing(bySource))
            }
            if let byName = existing.first(where: { $0.name.lowercased() == summary.lowercased() }) {
                return Mapping(summary: summary, count: count, target: .existing(byName))
            }
            return Mapping(summary: summary, count: count, target: .new(WasteCategory.classify(summary)))
        }
    }

    /// Übernimmt Termine. `replace` ersetzt die bisherigen Einzeltermine (Abgleich), sonst werden sie ergänzt.
    @discardableResult
    static func apply(pickups: [Pickup], mappings: [Mapping], location: Location?, context: ModelContext, replace: Bool, activeCategories: Set<WasteCategory>? = nil) -> Result {
        let grouped = Dictionary(grouping: pickups, by: \.name)
        var imported = 0
        var changes: [String] = []
        var nextSortOrder = ((location?.wasteTypes ?? []).map(\.sortOrder).max() ?? -1) + 1

        for mapping in mappings {
            guard let items = grouped[mapping.summary], !items.isEmpty else { continue }
            let target: WasteType
            switch mapping.target {
            case .ignore:
                continue
            case .existing(let type):
                target = type
            case .new(let category):
                let type = WasteType(name: mapping.summary, category: category, sortOrder: nextSortOrder, sourceKey: mapping.summary)
                if let activeCategories { type.isActive = activeCategories.contains(category) }
                nextSortOrder += 1
                context.insert(type)
                type.location = location
                target = type
            }
            if target.sourceKey == nil { target.sourceKey = mapping.summary }
            let days = Set(items.map { Days.start(of: $0.date) })
            if replace {
                let diff = ScheduleEngine.diff(old: target.explicitDates, new: Array(days))
                if !target.explicitDates.isEmpty {
                    for removed in diff.removed.prefix(3) {
                        let replacement = diff.added.first { abs(Days.between(removed, $0)) <= 7 }
                        changes.append(replacement.map { "\(target.name): \(DateText.short(removed)) → \(DateText.short($0))" } ?? "\(target.name): \(DateText.short(removed)) entfällt")
                    }
                }
                target.intervalWeeks = 0
                target.explicitDates = days.sorted()
            } else {
                for day in days { target.addExplicitDate(day) }
            }
            imported += days.count
        }
        try? context.save()
        return Result(importedCount: imported, changes: changes)
    }

    /// Online-Abgleich eines Standorts.
    @MainActor
    static func sync(location: Location, context: ModelContext) async throws -> Result {
        guard let config = location.source else { return Result(importedCount: 0, changes: []) }
        let provider = ProviderFactory.make(config)
        let pickups = try await provider.pickups(for: config.selections)
        let mappings = suggestMappings(for: pickups, location: location)
        let result = apply(pickups: pickups, mappings: mappings, location: location, context: context, replace: true)
        location.lastSyncAt = Date()
        location.lastSyncMessage = "\(result.importedCount) Termine übernommen"
        try? context.save()
        return result
    }

    /// Liest eine ICS-Datei des Nutzers.
    static func readICSFile(at url: URL) throws -> [Pickup] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = HTTPClient.text(from: data)
        return ICS.parse(text).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary), note: $0.location) }
    }

    static func bundledPickups(named resource: String) -> [Pickup] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "ics"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ICS.parse(text).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary), note: $0.location) }
    }
}
