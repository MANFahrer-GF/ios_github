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
            return value
        }
        set {
            recurrenceJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    var nextOccurrence: Date? { recurrence.next(start: startDate) }

    /// Uhrzeit des Termins (Minuten ab Mitternacht), nil = ganztägig. Sie steckt in der Tageszeit von `startDate`,
    /// damit kein neues Feld ins iCloud-Schema muss; die Wiederholung rechnet ohnehin nur mit dem Tag.
    /// Genau 0:00:00 heißt „ganztägig“ – wer 0:00 Uhr wählt, bekommt darum eine Sekunde dazu.
    var timeMinutes: Int? {
        get {
            let c = Calendar.current.dateComponents([.hour, .minute, .second], from: startDate)
            let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            return minutes == 0 && (c.second ?? 0) == 0 ? nil : minutes
        }
        set {
            let day = Days.start(of: startDate)
            guard let newValue, let date = Days.at(minutes: newValue, on: day) else { startDate = day; return }
            startDate = newValue == 0 ? date.addingTimeInterval(1) : date
        }
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
