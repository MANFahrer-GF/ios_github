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
    func testEveningEntryOnTheDayBefore() {
        let e = CalendarWastePlacement.make(pickupDay: friday, name: "Restmüll", suffix: " (Gifhorn)", alarms: [-300, 420], evening: true,
                                            eveningMinutes: 19 * 60, stayOnDay: false, today: thursday, calendar: berlin)
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
    func testEveningAcrossYearEnd() {
        let e = CalendarWastePlacement.make(pickupDay: Days.parse("2027-01-01", calendar: berlin)!, name: "Papier", alarms: [], evening: true,
                                            eveningMinutes: 18 * 60 + 30, stayOnDay: false, today: Days.parse("2026-12-30", calendar: berlin)!, calendar: berlin)
        XCTAssertEqual(Days.iso(e.date, calendar: berlin), "2026-12-31")
        XCTAssertEqual(e.timeMinutes, 18 * 60 + 30)
    }

    /// Abgleich am Abholtag selbst: Der Vorabend ist vorbei – ganztägig am Abholtag, sonst entstünde bei jedem Abgleich ein Doppel
    /// am Vortag, den die App (räumt ab heute auf) nie entfernt.
    func testPickupTodayStaysAllDay() {
        let e = CalendarWastePlacement.make(pickupDay: friday, name: "Restmüll", alarms: [-300], evening: true, eveningMinutes: 19 * 60,
                                            stayOnDay: false, today: friday, calendar: berlin)
        XCTAssertEqual(e, .init(date: friday, timeMinutes: nil, alarms: [-300], text: "Restmüll"))
    }
}

