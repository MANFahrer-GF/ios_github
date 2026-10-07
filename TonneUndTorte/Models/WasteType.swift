import Foundation
import SwiftData

/// Eine Müllart (z. B. Restmüll, Biotonne, Gelber Sack) samt Abholrhythmus.
///
/// Termine ergeben sich aus zwei Quellen:
/// 1. einem wiederkehrenden Rhythmus („alle N Wochen ab Ankerdatum“), und/oder
/// 2. einer Liste expliziter Einzeltermine (manuell oder per ICS-Import).
/// Einzelne Rhythmus-Termine können über `skippedDates` ausgesetzt werden
/// (z. B. wenn die Abfuhr wegen eines Feiertags verschoben wird).
@Model
final class WasteType {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#6B7280"
    var symbolName: String = "trash.fill"
    var sortOrder: Int = 0
    var isActive: Bool = true
    var remindersEnabled: Bool = true

    /// Abstand in Wochen zwischen zwei Abholungen. 0 = kein fester Rhythmus.
    var intervalWeeks: Int = 0
    /// Ein beliebiger bekannter Abholtag, von dem aus der Rhythmus berechnet wird.
    var anchorDate: Date = Date()

    /// Zusätzliche Einzeltermine (werden auf Tagesanfang normalisiert gespeichert).
    var explicitDates: [Date] = []
    /// Termine, die trotz Rhythmus ausfallen.
    var skippedDates: [Date] = []

    var createdAt: Date = Date()

    /// Der Standort (Haushalt), zu dem diese Müllart gehört.
    var location: Location?
    /// Schlüssel der Datenquelle (z. B. ICS-SUMMARY oder AWIDO-Fraktion), damit ein
    /// erneuter Import/Abgleich die Termine dieser Müllart ersetzen kann.
    var sourceKey: String?

    init(
        name: String,
        colorHex: String,
        symbolName: String,
        sortOrder: Int = 0,
        intervalWeeks: Int = 0,
        anchorDate: Date = Date(),
        location: Location? = nil,
        sourceKey: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.intervalWeeks = intervalWeeks
        self.anchorDate = anchorDate
        self.createdAt = Date()
        self.location = location
        self.sourceKey = sourceKey
    }

    /// Hat diese Müllart überhaupt irgendwelche Termine?
    var hasSchedule: Bool {
        intervalWeeks > 0 || !explicitDates.isEmpty
    }

    // MARK: - Termine bearbeiten

    func addExplicitDate(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if !explicitDates.contains(day) {
            explicitDates.append(day)
            explicitDates.sort()
        }
        skippedDates.removeAll { calendar.isDate($0, inSameDayAs: day) }
    }

    func removeExplicitDate(_ date: Date, calendar: Calendar = .current) {
        explicitDates.removeAll { calendar.isDate($0, inSameDayAs: date) }
    }

    func skip(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        // Ein expliziter Termin wird einfach entfernt, ein Rhythmus-Termin ausgesetzt.
        if explicitDates.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            removeExplicitDate(day, calendar: calendar)
        } else if !skippedDates.contains(day) {
            skippedDates.append(day)
            skippedDates.sort()
        }
    }

    func unskip(_ date: Date, calendar: Calendar = .current) {
        skippedDates.removeAll { calendar.isDate($0, inSameDayAs: date) }
    }

    /// Verschiebt einen Termin (z. B. Feiertagsregelung): alter Tag fällt aus, neuer Tag kommt dazu.
    func move(_ date: Date, to newDate: Date, calendar: Calendar = .current) {
        skip(date, calendar: calendar)
        addExplicitDate(newDate, calendar: calendar)
    }

    /// Entfernt Einzeltermine, die länger als ein Jahr zurückliegen – hält die Liste schlank.
    func pruneOldDates(calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .year, value: -1, to: Date()) else { return }
        explicitDates.removeAll { $0 < cutoff }
        skippedDates.removeAll { $0 < cutoff }
    }
}
