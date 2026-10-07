import Foundation
import SwiftData
import TonneCore

/// Eine Person mit Geburtstag, Geschenkideen und optionaler Verknüpfung zu einem Kontakt.
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
    var remindDaysBefore: Int = 1
    var giftIdeas: [String] = []
    var contactIdentifier: String?
    var phone: String?
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

    /// Geburtsjahr ohne Platzhalter: Manche Kontakte-Konten tragen 1604 für „ohne Jahr“ ein.
    var knownYear: Int? { year.flatMap { $0 > ContactsImport.placeholderYear ? $0 : nil } }
    var annual: AnnualDate { AnnualDate(day: day, month: month, year: knownYear) }
    var initials: String { NameText.initials(name) }
    var nextBirthday: Date? { annual.next() }
    var ageAtNext: Int? { nextBirthday.flatMap { annual.years(on: $0) } }
}
