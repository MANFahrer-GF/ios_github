import XCTest
@testable import TonneCore

/// Fotos im Geburtstags-Widget (Wunsch Ralf, 21.11.2026).
final class BirthdayPhotoTests: XCTestCase {
    let person = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// Gleiches Foto → gleiche Kennung (App schreibt nichts neu); anderes Foto → neue Kennung (Widget zeigt nie ein altes Bild).
    func testIDFollowsPhoto() {
        let a = BirthdayPhoto.id(personID: person, photo: Data([1, 2, 3]))
        XCTAssertEqual(a, BirthdayPhoto.id(personID: person, photo: Data([1, 2, 3])))
        XCTAssertNotEqual(a, BirthdayPhoto.id(personID: person, photo: Data([1, 2, 4])))
        XCTAssertTrue(a.hasPrefix(person.uuidString + "-"))
        XCTAssertEqual(BirthdayPhoto.fileName(a), a + ".jpg")
    }

    /// Nur eigene Kennungen werden zu Dateinamen – keine Pfadangaben.
    func testFileNameRejectsPaths() {
        XCTAssertNil(BirthdayPhoto.fileName("../secret"))
        XCTAssertNil(BirthdayPhoto.fileName("a/b"))
        XCTAssertNil(BirthdayPhoto.fileName(""))
    }

    /// Schnappschuss trägt die Kennung; ältere Schnappschüsse ohne Feld bleiben lesbar (Initialen).
    func testSnapshotCarriesPhotoID() throws {
        var snapshot = WidgetSnapshot()
        snapshot.birthdays = [.init(date: Days.today(), name: "Oma Erika", years: 80, colorHex: "#FF5FA2", initials: "OE", photoID: "x-1")]
        XCTAssertEqual(try WidgetSnapshot.decode(try snapshot.encoded()).birthdays.first?.photoID, "x-1")
        let old = ##"{"date":0,"name":"Paul","years":null,"colorHex":"#2F6FED","initials":"P"}"##
        XCTAssertNil(try JSONDecoder().decode(WidgetSnapshot.BirthdayItem.self, from: Data(old.utf8)).photoID)
    }
}
