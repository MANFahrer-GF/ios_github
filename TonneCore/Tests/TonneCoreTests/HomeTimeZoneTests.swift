import XCTest
@testable import TonneCore

final class HomeTimeZoneTests: XCTestCase {
    private func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: id)!; return c
    }

    private let winter = Days.parse("2026-12-01", calendar: Calendar(identifier: .gregorian))!

    func testFirstInstallAdoptsDeviceZone() {
        XCTAssertEqual(HomeTimeZone.resolve(stored: nil, device: "America/New_York", existingInstall: false, now: winter), "America/New_York")
    }

    /// Festgelegte Heimat bleibt – auch auf Reisen und auch dauerhaft woanders (sonst lägen alle alten Tage daneben).
    func testStoredHomeNeverChanges() {
        XCTAssertEqual(HomeTimeZone.resolve(stored: "Europe/Berlin", device: "Europe/Lisbon", existingInstall: true, now: winter), "Europe/Berlin")
    }

    /// Update auf Reisen: die östlichere von Gerätezone und Berlin, bei Gleichstand Berlin (Prüfbefunde 20.11.2026).
    func testUpdateWhileTravellingPicksEasternZone() {
        XCTAssertEqual(HomeTimeZone.resolve(stored: nil, device: "Europe/Lisbon", existingInstall: true, now: winter), "Europe/Berlin")
        XCTAssertEqual(HomeTimeZone.resolve(stored: nil, device: "Africa/Algiers", existingInstall: true, now: winter), "Europe/Berlin")
        XCTAssertEqual(HomeTimeZone.resolve(stored: nil, device: "Asia/Dubai", existingInstall: true, now: winter), "Asia/Dubai")
        XCTAssertEqual(HomeTimeZone.resolve(stored: nil, device: "Europe/Berlin", existingInstall: true, now: winter), "Europe/Berlin")
    }

    /// Warum „östlicher“ immer passt: Mitternacht aus Berlin bzw. New York ist in der gewählten Zone derselbe Tag.
    func testEasternZoneKeepsBothPossibleDataZones() {
        let berlinMidnight = Days.parse("2026-12-01", calendar: calendar("Europe/Berlin"))!
        let newYorkMidnight = Days.parse("2026-12-01", calendar: calendar("America/New_York"))!
        let dubai = calendar("Asia/Dubai"), berlin = calendar("Europe/Berlin")
        XCTAssertEqual(Days.iso(berlinMidnight, calendar: dubai), "2026-12-01")      // Reise nach Dubai: Daten aus Berlin
        XCTAssertEqual(Days.iso(newYorkMidnight, calendar: berlin), "2026-12-01")    // Auswanderer in New York: Berlin gewählt
        // Sommer: Berliner Mitternacht (UTC+2) in Algier (UTC+1) wäre der Vortag – darum bei Gleichstand im Winter Berlin
        let summer = Days.parse("2026-07-01", calendar: berlin)!
        XCTAssertEqual(Days.iso(summer, calendar: calendar("Africa/Algiers")), "2026-06-30")
    }

    /// Die eigentliche Wirkung: Eine in Berlin gespeicherte Mitternacht ist in Berliner Rechnung derselbe Tag, in Lissabon
    /// der Vortag (der alte Fehler).
    func testStoredMidnightStaysOnItsDayInHomeZone() {
        let stored = Days.parse("2026-12-01", calendar: calendar("Europe/Berlin"))!
        XCTAssertEqual(Days.iso(stored, calendar: calendar("Europe/Berlin")), "2026-12-01")
        XCTAssertEqual(Days.iso(stored, calendar: calendar("Europe/Lisbon")), "2026-11-30")
    }

    /// Die Watch bekommt die Heimat im Schnappschuss; ältere Schnappschüsse ohne Feld bleiben lesbar.
    func testSnapshotCarriesHomeZone() throws {
        var snapshot = WidgetSnapshot(); snapshot.homeTimeZone = "Europe/Berlin"
        XCTAssertEqual(try WidgetSnapshot.decode(try snapshot.encoded()).homeTimeZone, "Europe/Berlin")
        XCTAssertNil(try WidgetSnapshot.decode(try WidgetSnapshot().encoded()).homeTimeZone)
    }
}

