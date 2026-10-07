import Foundation
import SwiftData
import TonneCore

/// Eine Müllart (Restmüll, Gelber Sack …) mit Rhythmus und/oder Einzelterminen.
@Model
final class WasteType {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#5B6470"
    /// Immer ein SF-Symbolname, damit auch ältere App-Versionen ein Symbol zeigen.
    var symbolName: String = "trash.fill"
    /// Ausdrücklich gewähltes eigenes Piktogramm („tt.sack“ …), unabhängig vom Namen.
    var glyphName: String?
    var categoryRaw: String = WasteCategory.other.rawValue
    var sortOrder: Int = 0
    var isActive: Bool = true
    var remindersEnabled: Bool = true
    var intervalWeeks: Int = 0
    var anchorDate: Date?
    var explicitDates: [Date] = []
    var skippedDates: [Date] = []
    /// Tage, an denen „Erledigt“ bestätigt wurde.
    var doneDates: [Date] = []
    /// Schlüssel in der Online-Quelle (Titel der Fraktion), damit ein Abgleich die Termine ersetzt.
    var sourceKey: String?
    var createdAt: Date = Date()

    var location: Location?

    init(name: String, category: WasteCategory, colorHex: String? = nil, symbolName: String? = nil, sortOrder: Int = 0, sourceKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.colorHex = colorHex ?? category.colorHex
        self.symbolName = symbolName ?? category.symbolName
        self.sortOrder = sortOrder
        self.sourceKey = sourceKey
        self.createdAt = Date()
    }

    /// Angezeigtes Symbol, einmal aufgelöst: das gewählte Piktogramm, sonst das aus SF-Name und Name abgeleitete,
    /// sonst der SF-Name. Ein gewähltes Piktogramm gilt nur, solange `symbolName` noch dazu passt – ändert eine
    /// ältere App-Version (iCloud) nur `symbolName`, gewinnt diese neuere Wahl.
    var displaySymbol: String {
        get {
            if let glyphName, WasteGlyph.sfFallback(for: glyphName) == symbolName { return glyphName }
            return WasteGlyph.assetName(for: symbolName, name: name) ?? symbolName
        }
        set {
            if WasteGlyph.all.contains(newValue) {
                glyphName = newValue
                symbolName = WasteGlyph.sfFallback(for: newValue)
            } else {
                glyphName = nil
                symbolName = newValue
            }
        }
    }

    var category: WasteCategory {
        get { WasteCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var schedule: PickupSchedule {
        PickupSchedule(intervalWeeks: intervalWeeks, anchorDate: anchorDate, explicitDates: explicitDates, skippedDates: skippedDates)
    }

    var hasSchedule: Bool { schedule.hasAnyDates }

    func pickupDates(from: Date, to: Date) -> [Date] {
        ScheduleEngine.pickupDates(schedule, from: from, to: to)
    }

    var nextPickup: Date? { ScheduleEngine.nextPickup(schedule) }

    // MARK: - Termine bearbeiten

    func addExplicitDate(_ date: Date) {
        let day = Days.start(of: date)
        if !explicitDates.contains(day) { explicitDates.append(day); explicitDates.sort() }
        skippedDates.removeAll { Days.start(of: $0) == day }
    }

    func skip(_ date: Date) {
        let day = Days.start(of: date)
        if !skippedDates.contains(day) { skippedDates.append(day); skippedDates.sort() }
    }

    func unskip(_ date: Date) {
        let day = Days.start(of: date)
        skippedDates.removeAll { Days.start(of: $0) == day }
    }

    func move(_ date: Date, to newDate: Date) {
        skip(date)
        addExplicitDate(newDate)
    }

    func isDone(on date: Date) -> Bool {
        let day = Days.start(of: date)
        return doneDates.contains { Days.start(of: $0) == day }
    }

    func markDone(on date: Date) {
        let day = Days.start(of: date)
        if !isDone(on: day) { doneDates.append(day) }
    }

    func unmarkDone(on date: Date) {
        let day = Days.start(of: date)
        doneDates.removeAll { Days.start(of: $0) == day }
    }

    /// Entfernt Einzeltermine und Markierungen, die älter als ein Jahr sind.
    func prune() {
        let cutoff = Days.add(-400, to: Days.today())
        explicitDates.removeAll { $0 < cutoff }
        skippedDates.removeAll { $0 < cutoff }
        doneDates.removeAll { $0 < cutoff }
    }
}
