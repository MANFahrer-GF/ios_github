import XCTest
@testable import TonneCore

/// Portale mit mitlaufendem Fenster (SBAZV: rund 6 Wochen voraus) bringen neue Termine nach und nach. Bei wöchentlichem
/// Abgleich kamen sie bis zu 7 Tage spät an (Weihnachtsbäume im Januar). Kurzer Vorlauf → alle 2 Tage (Thomas 16.11.2026).
final class SyncRhythmTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400) }

    func testNeverSyncedIsDue() {
        XCTAssertTrue(SyncRhythm.isDue(lastSync: nil, lastKnownPickup: days(200), now: now))
    }

    func testShortLeadSyncsEveryTwoDays() {
        // letzter bekannter Termin in 6 Wochen
        XCTAssertFalse(SyncRhythm.isDue(lastSync: days(-1.5), lastKnownPickup: days(42), now: now))
        XCTAssertTrue(SyncRhythm.isDue(lastSync: days(-2.1), lastKnownPickup: days(42), now: now))
    }

    func testLongLeadSyncsWeekly() {
        // Jahresplan bis Ende nächsten Jahres
        XCTAssertFalse(SyncRhythm.isDue(lastSync: days(-3), lastKnownPickup: days(300), now: now))
        XCTAssertFalse(SyncRhythm.isDue(lastSync: days(-6.9), lastKnownPickup: days(300), now: now))
        XCTAssertTrue(SyncRhythm.isDue(lastSync: days(-7.1), lastKnownPickup: days(300), now: now))
    }

    func testBoundaryAtEightWeeks() {
        XCTAssertTrue(SyncRhythm.isDue(lastSync: days(-3), lastKnownPickup: days(55), now: now), "unter 8 Wochen: kurz")
        XCTAssertFalse(SyncRhythm.isDue(lastSync: days(-3), lastKnownPickup: days(57), now: now), "über 8 Wochen: wöchentlich")
    }

    func testNoKnownPickupsSyncsEveryTwoDays() {
        XCTAssertFalse(SyncRhythm.isDue(lastSync: days(-1), lastKnownPickup: nil, now: now))
        XCTAssertTrue(SyncRhythm.isDue(lastSync: days(-2.5), lastKnownPickup: nil, now: now))
        XCTAssertTrue(SyncRhythm.isDue(lastSync: days(-2.5), lastKnownPickup: days(-10), now: now), "nur vergangene Termine")
    }
}
