import Foundation
import SwiftData
import TonneCore

/// Eigene wiederkehrende Termine: Hochzeitstag, TÜV, Rauchmelder, Reifenwechsel …
@Model
final class CustomEvent {
    var id: UUID = UUID()
    var title: String = ""
    var symbolName: String = "star.fill"
    var colorHex: String = "#7C3AED"
    var startDate: Date = Date()
    var recurrenceJSON: String = ""
    var remindDaysBefore: Int = 1
    var remindersEnabled: Bool = true
    var notes: String = ""
    var createdAt: Date = Date()
    /// Uhrzeit in Minuten ab Mitternacht, -1 = ganztägig (ab 2.0.3). Als Zahl statt in `startDate`, damit sie beim
    /// Wechsel der Zeitzone gleich bleibt und ein Gerät mit 2.0.2 sie beim Bearbeiten nicht überschreibt.
    var timeOfDay: Int = -1
    /// „Jeden n-ten Wochentag im Monat“ (ab 2.0.3): 1…4 oder -1 = letzter, 0 = keine solche Regel; Wochentag 1 = Sonntag.
    /// In `recurrenceJSON` steht dann „jeden Monat“ – das versteht auch 2.0.2 und lässt diese Felder beim Speichern stehen.
    var weekdayOrdinal: Int = 0
    var weekdayNumber: Int = 0

    init(title: String, symbolName: String = "star.fill", colorHex: String = "#7C3AED", startDate: Date, recurrence: Recurrence, remindDaysBefore: Int = 1) {
        self.id = UUID()
        self.title = title
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.startDate = Days.start(of: startDate)
        self.recurrence = recurrence
        self.remindDaysBefore = remindDaysBefore
        self.createdAt = Date()
    }

    var recurrence: Recurrence {
        get {
            guard let data = recurrenceJSON.data(using: .utf8), let value = try? JSONDecoder().decode(Recurrence.self, from: data) else { return .yearly }
            // Hat 2.0.2 die Wiederholung inzwischen geändert, gilt deren Regel und die Wochentag-Felder sind überholt
            if value == .everyMonths(1), weekdayOrdinal != 0, (1...7).contains(weekdayNumber) {
                return .monthlyWeekday(ordinal: weekdayOrdinal, weekday: weekdayNumber)
            }
            return value
        }
        set {
            let stored: Recurrence
            if case .monthlyWeekday(let ordinal, let weekday) = newValue {
                stored = .everyMonths(1); weekdayOrdinal = ordinal; weekdayNumber = weekday
            } else {
                stored = newValue; weekdayOrdinal = 0; weekdayNumber = 0
            }
            recurrenceJSON = (try? JSONEncoder().encode(stored)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    var nextOccurrence: Date? { recurrence.next(start: startDate) }

    /// Uhrzeit des Termins (Minuten ab Mitternacht), nil = ganztägig.
    var timeMinutes: Int? {
        get { (0..<1440).contains(timeOfDay) ? timeOfDay : nil }
        set { timeOfDay = newValue.map { min(1439, max(0, $0)) } ?? -1 }
    }

    var timeText: String? { timeMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } }

    func occurrences(from: Date, to: Date) -> [Date] {
        recurrence.occurrences(start: startDate, from: from, to: to)
    }

    /// Vorlagen für häufige Haushaltstermine.
    static let templates: [(title: String, symbol: String, color: String, recurrence: Recurrence)] = [
        ("Hochzeitstag", "heart.fill", "#EC4899", .yearly),
        ("TÜV / Hauptuntersuchung", "car.fill", "#2F6FED", .everyMonths(24)),
        ("Rauchmelder testen", "flame.fill", "#DC2626", .everyMonths(6)),
        ("Reifenwechsel", "car.fill", "#5B6470", .everyMonths(6)),
        ("Zahnarzt-Kontrolle", "stethoscope", "#0EA5E9", .everyMonths(6)),
        ("Heizung warten", "wrench.and.screwdriver.fill", "#F97316", .yearly),
        ("Versicherung prüfen", "creditcard.fill", "#16A34A", .yearly),
        ("Wurmkur / Tierarzt", "pawprint.fill", "#8B5E34", .everyMonths(3)),
    ]
}
