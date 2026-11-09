import XCTest
@testable import TonneCore

/// Tonnendienst: Wer nur in bestimmten Zeiträumen dran ist, wird nur dann erinnert.
final class DutyPeriodTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func day(_ iso: String) -> Date { Days.parse(iso, calendar: calendar)! }
    private func onDuty(_ iso: String, _ periods: [DutyPeriod]) -> Bool {
        DutySchedule.isOnDuty(on: day(iso), periods: periods, calendar: calendar)
    }

    func testWithoutPeriodsAlwaysOnDuty() {
        XCTAssertTrue(onDuty("2026-07-15", []))
        XCTAssertEqual(DutySchedule.status(of: [], today: day("2026-07-15"), calendar: calendar), .always)
    }

    /// Erster und letzter Tag zählen mit, der Tag davor und danach nicht.
    func testBoundariesAreInclusive() {
        let periods = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: false)]
        XCTAssertFalse(onDuty("2026-02-28", periods))
        XCTAssertTrue(onDuty("2026-03-01", periods))
        XCTAssertTrue(onDuty("2026-04-30", periods))
        XCTAssertFalse(onDuty("2026-05-01", periods))
    }

    func testOneTimePeriodDoesNotComeBackNextYear() {
        let periods = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: false)]
        XCTAssertFalse(onDuty("2027-03-15", periods))
    }

    func testYearlyPeriodRepeatsButNotBeforeItsStartYear() {
        let periods = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: true)]
        XCTAssertTrue(onDuty("2029-03-15", periods))
        XCTAssertFalse(onDuty("2029-05-01", periods))
        XCTAssertFalse(onDuty("2025-03-15", periods))
    }

    /// Dienst über Silvester: gilt im Dezember und im Januar des Folgejahres.
    func testYearlyPeriodAcrossNewYear() {
        let periods = [DutyPeriod(startKey: "2026-12-01", endKey: "2027-01-31", yearly: true)]
        XCTAssertTrue(onDuty("2028-01-15", periods))
        XCTAssertTrue(onDuty("2028-12-15", periods))
        XCTAssertFalse(onDuty("2028-02-15", periods))
    }

    func testLeapDayInNonLeapYear() {
        let periods = [DutyPeriod(startKey: "2028-02-29", endKey: "2028-02-29", yearly: true)]
        XCTAssertTrue(onDuty("2029-02-28", periods))
        XCTAssertFalse(onDuty("2029-03-01", periods))
    }

    func testSeveralPeriods() {
        let periods = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-03-31", yearly: false),
                       DutyPeriod(startKey: "2026-09-01", endKey: "2026-09-30", yearly: false)]
        XCTAssertTrue(onDuty("2026-09-10", periods))
        XCTAssertFalse(onDuty("2026-06-10", periods))
    }

    func testStatus() {
        let oneTime = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: false)]
        XCTAssertEqual(DutySchedule.status(of: oneTime, today: day("2026-03-10"), calendar: calendar), .onDuty(until: day("2026-04-30")))
        XCTAssertEqual(DutySchedule.status(of: oneTime, today: day("2026-01-10"), calendar: calendar), .upcoming(from: day("2026-03-01")))
        XCTAssertEqual(DutySchedule.status(of: oneTime, today: day("2026-05-01"), calendar: calendar), .ended)
        let yearly = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: true)]
        XCTAssertEqual(DutySchedule.status(of: yearly, today: day("2026-11-09"), calendar: calendar), .upcoming(from: day("2027-03-01")))
    }

    /// Ein erst in Jahren beginnender jährlicher Zeitraum darf nicht als „vorbei“ gelten.
    func testYearlyPeriodStartingFarAheadIsUpcoming() {
        let periods = [DutyPeriod(startKey: "2030-03-01", endKey: "2030-04-30", yearly: true)]
        XCTAssertEqual(DutySchedule.status(of: periods, today: day("2026-11-09"), calendar: calendar), .upcoming(from: day("2030-03-01")))
    }

    func testRoundTripAndBrokenData() {
        let periods = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: true)]
        XCTAssertEqual(DutySchedule.decode(DutySchedule.encode(periods)), periods)
        XCTAssertEqual(DutySchedule.encode([]), "")
        // Kaputte Daten dürfen niemanden still um seine Erinnerungen bringen
        XCTAssertEqual(DutySchedule.decode("{kaputt"), [])
    }

    /// Über den Schalter `remindersEnabled` fällt der ganze Erinnerungsablauf eines Tages weg – auch „wieder reinholen“.
    func testOffDutyPickupGetsNoWasteReminder() {
        let periods = [DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: false)]
        let pickup = day("2026-11-10")
        var settings = ReminderSettings()
        settings.morningEnabled = true
        let onDutyToday = DutySchedule.isOnDuty(on: pickup, periods: periods, calendar: calendar)
        let off = PlannedPickup(date: pickup, name: "Restmüll", symbolName: "trash.fill", remindersEnabled: onDutyToday)
        let on = PlannedPickup(date: pickup, name: "Restmüll", symbolName: "trash.fill", remindersEnabled: true)
        let now = calendar.date(byAdding: .hour, value: 12, to: day("2026-11-09"))!
        func wasteCount(_ pickups: [PlannedPickup]) -> Int {
            ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: now, calendar: calendar).filter { $0.threadIdentifier == "waste" }.count
        }
        XCTAssertEqual(wasteCount([off]), 0)
        XCTAssertGreaterThan(wasteCount([on]), 0)
    }
}
