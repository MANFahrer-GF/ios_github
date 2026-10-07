import Foundation
import SwiftData

/// Eine Person mit Geburtstag. Das Geburtsjahr ist optional – nicht jeder verrät es.
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var day: Int = 1
    var month: Int = 1
    var year: Int?
    var notes: String = ""
    var colorHex: String = "#EC4899"
    var remindersEnabled: Bool = true
    /// Zusätzliche Vorab-Erinnerung in Tagen (0 = nur am Tag selbst).
    var remindDaysBefore: Int = 1
    var createdAt: Date = Date()

    init(name: String, day: Int, month: Int, year: Int? = nil, colorHex: String = "#EC4899") {
        self.id = UUID()
        self.name = name
        self.day = day
        self.month = month
        self.year = year
        self.colorHex = colorHex
        self.createdAt = Date()
    }

    /// Initialen für den Avatar, z. B. „Max Mustermann“ → „MM“.
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
