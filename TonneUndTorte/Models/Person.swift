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
    /// Eigenes Foto (ab 2.0.3), verkleinert; liegt außerhalb der Datenbank und geht als Asset zu iCloud.
    @Attribute(.externalStorage) var photoData: Data?

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
    var knownYear: Int? { ContactsImport.realYear(year) }
    var annual: AnnualDate { AnnualDate(day: day, month: month, year: knownYear) }
    var initials: String { NameText.initials(name) }
    var nextBirthday: Date? { annual.next() }
    /// Sternzeichen mit farbigem Emoji (♎️) – das schlichte Textzeichen kennt die App-Schrift nicht, es erscheint dann winzig.
    var zodiacLabel: String { annual.zodiac.replacingOccurrences(of: "\u{FE0E}", with: "\u{FE0F}") }
    var ageAtNext: Int? { nextBirthday.flatMap { annual.years(on: $0) } }
}
