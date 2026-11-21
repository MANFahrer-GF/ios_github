import XCTest
@testable import TonneCore

final class CalendarWastePlacementTests: XCTestCase {
    override func setUp() { L10n.forcedLanguage = "de" }
    override func tearDown() { L10n.forcedLanguage = nil }
    private var berlin: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }
    private var friday: Date { Days.parse("2026-12-04", calendar: berlin)! }
    private var thursday: Date { Days.parse("2026-12-03", calendar: berlin)! }

    /// Standard wie bisher: ganztägig am Abholtag, Alarme unverändert.
    func testDefaultIsAllDayOnPickupDay() {
        let e = CalendarWastePlacement.make(pickupDay: friday, name: "Restmüll", alarms: [-300, 420], evening: false, eveningMinutes: 19 * 60,
                                            stayOnDay: false, today: thursday, calendar: berlin)
        XCTAssertEqual(e, .init(date: friday, timeMinutes: nil, alarms: [-300, 420], text: "Restmüll"))
    }

    /// Vorabend: Donnerstag 19:00 „Restmüll rausstellen“; Abend-Alarm genau zum Termin, Morgen-Alarm (7:00 am Abholtag) bleibt.
    func testEveningEntryOnTheDayBefore() throws {
        let e = try XCTUnwrap(CalendarWastePlacement.make(pickupDay: friday, name: "Restmüll", suffix: " (Gifhorn)", alarms: [-300, 420], evening: true,
                                            eveningMinutes: 19 * 60, stayOnDay: false, today: thursday, calendar: berlin))
        XCTAssertEqual(Days.iso(e.date, calendar: berlin), "2026-12-03")
        XCTAssertEqual(e.timeMinutes, 19 * 60)
        XCTAssertEqual(e.alarms, [19 * 60, 1440 + 7 * 60])
        XCTAssertEqual(e.text, "Restmüll rausstellen (Gifhorn)")
    }

    /// Hinbringen (Schadstoffmobil): bleibt am Tag selbst, auch mit Vorabend-Einstellung.
    func testDropOffStaysOnTheDay() {
        let e = CalendarWastePlacement.make(pickupDay: friday, name: "Schadstoffmobil", alarms: [-300], evening: true, eveningMinutes: 19 * 60,
                                            stayOnDay: true, today: thursday, calendar: berlin)
        XCTAssertEqual(e, .init(date: friday, timeMinutes: nil, alarms: [-300], text: "Schadstoffmobil"))
    }

    /// Monatswechsel: Abholung am 1. Januar → Eintrag am 31. Dezember.
    func testEveningAcrossYearEnd() throws {
        let e = try XCTUnwrap(CalendarWastePlacement.make(pickupDay: Days.parse("2027-01-01", calendar: berlin)!, name: "Papier", alarms: [], evening: true,
                                            eveningMinutes: 18 * 60 + 30, stayOnDay: false, today: Days.parse("2026-12-30", calendar: berlin)!, calendar: berlin))
        XCTAssertEqual(Days.iso(e.date, calendar: berlin), "2026-12-31")
        XCTAssertEqual(e.timeMinutes, 18 * 60 + 30)
    }

    /// Abgleich am Abholtag selbst: Der Vorabend-Eintrag steht seit gestern im Kalender (die App räumt ab heute auf) – kein
    /// zweiter Eintrag, weder am Vortag noch ganztägig heute (Prüfbefunde 20./21.11.2026).
    func testPickupTodayAddsNothing() {
        XCTAssertNil(CalendarWastePlacement.make(pickupDay: friday, name: "Restmüll", alarms: [-300], evening: true, eveningMinutes: 19 * 60,
                                                 stayOnDay: false, today: friday, calendar: berlin))
        // Am Vorabend selbst (heute 19:00) wird er noch geschrieben
        XCTAssertNotNil(CalendarWastePlacement.make(pickupDay: friday, name: "Restmüll", alarms: [-300], evening: true, eveningMinutes: 19 * 60,
                                                    stayOnDay: false, today: thursday, calendar: berlin))
    }

    /// Zeitumstellung: Abholung Sonntag 28.3.2027 (Beginn Sommerzeit), Termin Samstag 19:00, Morgen-Erinnerung 7:00 am Sonntag
    /// liegt 11 Stunden später (nicht 12); im Herbst (31.10.2027) 13 Stunden.
    func testMorningAlarmAcrossDaylightSaving() throws {
        let spring = try XCTUnwrap(CalendarWastePlacement.make(pickupDay: Days.parse("2027-03-28", calendar: berlin)!, name: "Papier", alarms: [-300, 420],
                                                               evening: true, eveningMinutes: 19 * 60, stayOnDay: false,
                                                               today: Days.parse("2027-03-20", calendar: berlin)!, calendar: berlin))
        XCTAssertEqual(spring.alarms, [19 * 60, 19 * 60 + 11 * 60])
        let autumn = try XCTUnwrap(CalendarWastePlacement.make(pickupDay: Days.parse("2027-10-31", calendar: berlin)!, name: "Papier", alarms: [-300, 420],
                                                               evening: true, eveningMinutes: 19 * 60, stayOnDay: false,
                                                               today: Days.parse("2027-10-20", calendar: berlin)!, calendar: berlin))
        XCTAssertEqual(autumn.alarms, [19 * 60, 19 * 60 + 13 * 60])
    }
}

