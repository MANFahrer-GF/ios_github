import XCTest
@testable import TonneCore

@MainActor
final class OpenOnceTests: XCTestCase {
    func testConcurrentCallersShareOneAttempt() async {
        var attempts = 0
        let once = OpenOnce {
            attempts += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
            return true
        }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { await once.run() } }
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(once.succeeded)
        await once.run()
        XCTAssertEqual(attempts, 1, "nach einem Erfolg kein weiterer Versuch")
    }

    func testFailedAttemptAllowsANewOneButWaitersDoNotRetry() async {
        var results = [false, true]
        var attempts = 0
        let once = OpenOnce {
            attempts += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
            return results.removeFirst()
        }
        // Drei warten gemeinsam auf den gescheiterten ersten Versuch – keiner startet danach selbst einen zweiten
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 { group.addTask { await once.run() } }
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(once.succeeded)
        await once.run()
        XCTAssertEqual(attempts, 2, "nach einem Fehlschlag ist ein neuer Versuch erlaubt")
        XCTAssertTrue(once.succeeded)
        await once.run()
        XCTAssertEqual(attempts, 2)
    }
}
