import Foundation
import SwiftData
import TonneCore

/// Holt Termine aus den Online-Quellen, ordnet sie Müllarten zu und erkennt Verschiebungen.
enum SyncService {
    struct Result {
        var importedCount: Int

        /// Text für Hinweise nach dem Abgleich.
        var summaryText: String {
            var text = L10n.t("\(L10n.dates(importedCount)) übernommen.", "\(L10n.dates(importedCount)) imported.")
            if !changes.isEmpty {
                text += "\n"
                text += changes.joined(separator: "\n")
            }
            return text
        }
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

    /// `exclusive`: jede vorhandene Müllart höchstens einem Titel vorschlagen (Abgleich). Beim Datei-Import (`false`)
    /// dürfen mehrere Titel dieselbe Müllart treffen – ihre Termine werden in `apply` vereinigt.
    static func suggestMappings(for pickups: [Pickup], location: Location?, exclusive: Bool = true) -> [Mapping] {
        let existing = location?.sortedWasteTypes ?? []
        let grouped = Dictionary(grouping: pickups, by: \.name)
        let summaries = grouped.keys.sorted()
        let assigned = WasteTitleMatching.assign(summaries.filter { !WasteCategory.isIgnorableTitle($0) },
                                                 to: existing.map { .init(sourceKey: $0.sourceKey, name: $0.name) }, exclusive: exclusive)
        return summaries.map { summary in
            let count = grouped[summary]?.count ?? 0
            if WasteCategory.isIgnorableTitle(summary) {
                return Mapping(summary: summary, count: count, target: .ignore)
            }
            return Mapping(summary: summary, count: count, target: assigned[summary].map { .existing(existing[$0]) } ?? .new(WasteCategory.classify(summary)))
        }
    }

    /// Übernimmt Termine. `replace` ersetzt die bisherigen Einzeltermine (Abgleich), sonst werden sie ergänzt.
    @discardableResult
    static func apply(pickups: [Pickup], mappings: [Mapping], location: Location?, context: ModelContext, replace: Bool, activeCategories: Set<WasteCategory>? = nil) -> Result {
        let grouped = Dictionary(grouping: pickups, by: \.name)
        var imported = 0
        var changes: [String] = []
        var nextSortOrder = ((location?.wasteTypes ?? []).map(\.sortOrder).max() ?? -1) + 1
        // Termine je Müllart sammeln: Zeigen mehrere Titel auf dieselbe Müllart, werden sie vereinigt statt nacheinander ersetzt
        var collected: [(target: WasteType, days: Set<Date>)] = []

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
            if let old = target.sourceKey, ICSURLProvider.formerTitle(old, matches: mapping.summary) {
                // Bereinigter Titel: Schlüssel nachziehen, Namen nur, wenn der Nutzer ihn nicht geändert hat
                if target.name == old { target.name = mapping.summary }
                target.sourceKey = mapping.summary
            }
            if target.sourceKey == nil { target.sourceKey = mapping.summary }
            let days = Set(items.map { Days.start(of: $0.date) })
            if let index = collected.firstIndex(where: { $0.target === target }) {
                collected[index].days.formUnion(days)
            } else {
                collected.append((target, days))
            }
        }
        for (target, days) in collected {
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
        location.lastSyncMessage = L10n.t("\(L10n.dates(result.importedCount)) übernommen", "\(L10n.dates(result.importedCount)) imported")
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

    /// Liest eine ICS- oder CSV-Datei des Nutzers; das Format wird am Inhalt erkannt.
    static func readPickupFile(at url: URL) throws -> [Pickup] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        // Koordiniert lesen, damit auch noch nicht geladene iCloud-Dateien zuverlässig kommen
        var readError: Error?
        var data = Data()
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do { data = try Data(contentsOf: readURL) } catch { readError = error }
        }
        if let error = readError ?? coordinatorError { throw error }
        // Numbers-/Excel-Dateien (ZIP) und Pakete sind keine Tabellen im Textformat
        if data.starts(with: [0x50, 0x4B]) || (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
            throw ImportError.spreadsheet
        }
        let text = decodeText(data)
        if text.contains("BEGIN:VCALENDAR") {
            return ICS.parse(text).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary), note: $0.location) }
        }
        return PickupCSV.parse(text)
    }

    enum ImportError: LocalizedError {
        case spreadsheet
        var errorDescription: String? {
            L10n.t("Das ist eine Numbers- oder Excel-Datei. Bitte als CSV speichern: In Numbers „Teilen › Exportieren › CSV“, in Excel „Speichern unter › CSV UTF-8“.",
                   "This is a Numbers or Excel file. Please save it as CSV: in Numbers “Share › Export › CSV”, in Excel “Save As › CSV UTF-8”.")
        }
    }

    /// UTF-8 (mit/ohne BOM), UTF-16 (Excel „Unicode-Text“), sonst Windows-1252 (älteres Excel).
    static func decodeText(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .windowsCP1252) ?? HTTPClient.text(from: data)
    }

    /// Termine eines Standorts (letzte 30 Tage bis 1 Jahr voraus) für den CSV-Export.
    static func csvRows(for location: Location) -> [PickupCSV.Row] {
        let from = Days.add(-30, to: Days.today()), to = Days.add(366, to: Days.today())
        return location.sortedWasteTypes.filter(\.isActive).flatMap { type in
            type.pickupDates(from: from, to: to).map { PickupCSV.Row(date: $0, name: type.name) }
        }
    }

    static func bundledPickups(named resource: String) -> [Pickup] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "ics"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ICS.parse(text).map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary), note: $0.location) }
    }
}
