import XCTest
@testable import TonneCore

/// Prüfbefund 4 zu Teil 13: Ein zweiter Durchlauf las die ausstehenden Tage einmal und übernahm später einen Tag, den der
/// erste inzwischen erledigt hatte – dessen Erledigt-Zeit wurde dabei mit „jetzt“ überschrieben.
@MainActor
final class PendingMarkersTests: XCTestCase {
    func testSecondRunSkipsDaysTheFirstRunFinished() async {
        var pending: Set<String> = ["2026-11-20", "2026-11-21"]
        let old = Date(timeIntervalSince1970: 1_000)
        var doneAt: [String: Date] = ["2026-11-20": old, "2026-11-21": old]
        func markDone(_ key: String) {
            // wie `AppModel.markDone`: nicht mehr ausstehend → neue Zeit, sonst die gemerkte behalten
            if !pending.contains(key) { doneAt[key] = Date() }
            pending.remove(key)
        }
        var nested = false
        // Durchlauf B arbeitet den ersten Tag ab; währenddessen läuft Durchlauf A ganz durch
        await PendingMarkers.apply({ pending }) { key in
            if !nested {
                nested = true
                await PendingMarkers.apply({ pending }) { markDone($0) }
            }
            markDone(key)
        }
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(doneAt["2026-11-21"], old, "Erledigt-Zeit des zweiten Tages überschrieben")
    }
}
