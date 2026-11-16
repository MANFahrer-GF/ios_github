import XCTest
@testable import TonneCore

/// Wecker am Vorabend (AlarmKit): wann einer geplant wird und wann nicht.
final class AlarmPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private var on: ReminderSettings { var settings = ReminderSettings(); settings.alarmEnabled = true; return settings }

    func testOffByDefault() {
        XCTAssertFalse(ReminderSettings().alarmEnabled)
        let pickups = [PlannedPickup(date: at(18, 0), name: "Restmüll")]
        XCTAssertTrue(ReminderPlanner.alarms(pickups: pickups, settings: ReminderSettings(), now: at(16, 12), calendar: calendar).isEmpty)
    }

    func testOneAlarmPerDayOnTheEveningBefore() {
        let pickups = [PlannedPickup(date: at(18, 0), name: "Restmüll"), PlannedPickup(date: at(18, 0), name: "Papier"),
                       PlannedPickup(date: at(25, 0), name: "Gelber Sack")]
        let alarms = ReminderPlanner.alarms(pickups: pickups, settings: on, now: at(16, 12), calendar: calendar)
        XCTAssertEqual(alarms.map(\.dayKey), ["2026-11-18", "2026-11-25"])
        XCTAssertEqual(alarms[0].fireDate, at(17, 20))
        XCTAssertTrue(alarms[0].title.contains("Restmüll") && alarms[0].title.contains("Papier"), alarms[0].title)
        XCTAssertEqual(alarms[0].id, UUID(uuidString: "7A1A0000-0000-4000-8000-000020261118"))
    }

    func testOwnTime() {
        var settings = on
        settings.alarmMinutes = 18 * 60 + 45
        let alarms = ReminderPlanner.alarms(pickups: [PlannedPickup(date: at(18, 0), name: "Restmüll")], settings: settings, now: at(16, 12), calendar: calendar)
        XCTAssertEqual(alarms.first?.fireDate, at(17, 18, 45))
    }

    func testDoneSkippedMutedAndDropOffDaysDoNotRing() {
        let pickups = [
            PlannedPickup(date: at(18, 0), name: "Restmüll", done: true),
            PlannedPickup(date: at(19, 0), name: "Papier", skipped: true),
            PlannedPickup(date: at(20, 0), name: "Biotonne", remindersEnabled: false),
            PlannedPickup(date: at(21, 0), name: "Schadstoffmobil", handling: .bringTo),
        ]
        XCTAssertTrue(ReminderPlanner.alarms(pickups: pickups, settings: on, now: at(16, 12), calendar: calendar).isEmpty)
    }

    func testMixedDayNamesOnlyWhatGoesOut() {
        let pickups = [PlannedPickup(date: at(18, 0), name: "Restmüll"), PlannedPickup(date: at(18, 0), name: "Schadstoffmobil", handling: .bringTo)]
        let alarm = ReminderPlanner.alarms(pickups: pickups, settings: on, now: at(16, 12), calendar: calendar).first
        XCTAssertNotNil(alarm)
        XCTAssertFalse(alarm!.title.contains("Schadstoffmobil"), alarm!.title)
    }

    func testPastTimeAndBeyondTwoWeeksAreLeftOut() {
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        let pickups = [PlannedPickup(date: at(17, 0), name: "Restmüll"), PlannedPickup(date: at(30, 0), name: "Papier"), PlannedPickup(date: december, name: "Biotonne")]
        // 16.11. 21:00: der Wecker für den 17. (Vorabend 20:00) ist vorbei; der 30. ist der letzte Tag in zwei Wochen, der 1.12. liegt dahinter
        XCTAssertEqual(ReminderPlanner.alarms(pickups: pickups, settings: on, now: at(16, 21), calendar: calendar).map(\.dayKey), ["2026-11-30"])
    }

    func testStableIDFromDayKey() {
        XCTAssertEqual(PlannedAlarm.id(dayKey: "2026-01-05"), UUID(uuidString: "7A1A0000-0000-4000-8000-000020260105"))
        XCTAssertNil(PlannedAlarm.id(dayKey: "kaputt"))
        XCTAssertTrue(PlannedAlarm.isPickupAlarm(PlannedAlarm.id(dayKey: "2026-01-05")!))
        XCTAssertFalse(PlannedAlarm.isPickupAlarm(UUID()))
    }
}
