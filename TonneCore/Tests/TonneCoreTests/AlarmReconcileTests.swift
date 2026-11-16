import XCTest
@testable import TonneCore

/// Abgleich vorhandener Wecker mit dem Plan: was storniert wird, was liegen bleibt, wann neu geplant wird.
final class AlarmReconcileTests: XCTestCase {
    private let tue = PlannedAlarm.id(dayKey: "2026-11-17")!
    private let wed = PlannedAlarm.id(dayKey: "2026-11-18")!
    private let thu = PlannedAlarm.id(dayKey: "2026-11-19")!
    private func planned(_ id: UUID) -> PlannedAlarm { PlannedAlarm(id: id, dayKey: "", fireDate: Date(), title: "Rausstellen: Restmüll") }

    /// Befund 7: Ein Refresh kurz nach 20:00 (Hintergrund-Aufgabe, Watch) darf den gerade klingelnden Wecker nicht beenden.
    func testRingingAlarmSurvivesReplan() {
        let existing: [(id: UUID, state: AlarmRunState)] = [(tue, .alerting), (wed, .scheduled), (thu, .scheduled)]
        XCTAssertEqual(AlarmReconcile.toCancel(existing: existing, plan: [planned(wed)]), [thu])
    }

    func testRingingAlarmSurvivesEmptyPlanButScheduledOnesGo() {
        let existing: [(id: UUID, state: AlarmRunState)] = [(tue, .alerting), (wed, .countdown), (thu, .scheduled)]
        XCTAssertEqual(AlarmReconcile.toCancel(existing: existing, plan: []), [thu])
    }

    /// Befund 13: Titel-Schlüssel nicht mehr geplanter Tage verschwinden, geplante und klingelnde bleiben, fremde Schlüssel bleiben unberührt.
    func testStaleTitleKeysArePruned() {
        let stored = [AlarmReconcile.titleKey(tue), AlarmReconcile.titleKey(wed), AlarmReconcile.titleKey(thu), "alarmEnabled", "alarmMinutes"]
        XCTAssertEqual(AlarmReconcile.staleTitleKeys(stored: stored, keeping: [wed]), [AlarmReconcile.titleKey(thu), AlarmReconcile.titleKey(tue)].sorted())
        XCTAssertEqual(AlarmReconcile.staleTitleKeys(stored: stored, keeping: [tue, wed, thu]), [])
    }

    /// Befund 8: „Erledigt“ oder „Diesmal nicht“ von einem anderen Gerät muss die Neuplanung auslösen.
    func testFingerprintChangesWithDoneAndNotPutOut() {
        let day = Date(timeIntervalSince1970: 1_795_000_000)
        let open = [PlannedPickup(date: day, name: "Restmüll")]
        let done = [PlannedPickup(date: day, name: "Restmüll", done: true)]
        let notPutOut = [PlannedPickup(date: day, name: "Restmüll", skipped: true)]
        let base = ReminderPlanner.replanFingerprint(pickups: open)
        XCTAssertNotEqual(base, ReminderPlanner.replanFingerprint(pickups: done))
        XCTAssertNotEqual(base, ReminderPlanner.replanFingerprint(pickups: notPutOut))
        XCTAssertEqual(base, ReminderPlanner.replanFingerprint(pickups: open), "gleicher Stand → keine Neuplanung")
    }
}
