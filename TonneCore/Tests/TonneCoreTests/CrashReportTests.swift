import XCTest
@testable import TonneCore

final class CrashReportTests: XCTestCase {
    private var url: URL!
    private var store: CrashReportStore!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("crash-\(UUID().uuidString)/reports.json")
        store = CrashReportStore(url: url)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func report(day: Int = 1, stack: String = "{\"a\":1}", reason: String? = "Namespace SIGNAL", signal: Int = 5) -> CrashReport {
        CrashReport(reportDate: Date(timeIntervalSince1970: TimeInterval(day) * 86_400), appVersion: "2.0.7 (8)",
                    osVersion: "iPhone OS 27.2", deviceType: "iPad16,6", exceptionType: 6, exceptionCode: 0, signal: signal,
                    terminationReason: reason, objectiveCException: nil, callStackJSON: stack)
    }

    func testSameCrashDeliveredTwiceCountsOnce() {
        store.add([report()])
        store.add([report()])
        XCTAssertEqual(store.load().count, 1)
    }

    func testDifferentCrashesAreKeptNewestFirst() {
        store.add([report(day: 1), report(day: 3), report(day: 2)])
        XCTAssertEqual(store.load().map(\.reportDate.timeIntervalSince1970), [3, 2, 1].map { $0 * 86_400 })
    }

    func testKeepsOnlyTheNewestReports() {
        store.add((1...(CrashReportStore.maxReports + 2)).map { report(day: $0) })
        let days = store.load().map { Int($0.reportDate.timeIntervalSince1970 / 86_400) }
        XCTAssertEqual(days, [7, 6, 5, 4, 3])
    }

    func testSurvivesARestart() {
        store.add([report()])
        XCTAssertEqual(CrashReportStore(url: url).load(), [report()])
    }

    func testPromptIsRememberedAndOtherReportsStayUntouched() {
        let first = report(day: 1), second = report(day: 2)
        store.add([first, second])
        store.markPrompted(id: first.id)
        let loaded = store.load()
        XCTAssertEqual(loaded.first { $0.id == first.id }?.prompted, true)
        XCTAssertEqual(loaded.first { $0.id == second.id }?.prompted, false)
    }

    func testPromptFlagIsKeptWhenTheSameCrashArrivesAgain() {
        let first = report()
        store.add([first])
        store.markPrompted(id: first.id)
        store.add([report()])
        XCTAssertEqual(store.load().first?.prompted, true)
    }

    func testRemoveAll() {
        store.add([report(day: 1), report(day: 2)])
        store.removeAll()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testDeletedReportDoesNotComeBackWhenIOSDeliversItAgain() {
        store.add([report()])
        store.removeAll()
        store.add([report()])
        XCTAssertTrue(store.load().isEmpty, "gelöschter Bericht kam zurück")
    }

    func testEvictedReportDoesNotComeBackWhenIOSDeliversItAgain() {
        store.add((1...(CrashReportStore.maxReports + 1)).map { report(day: $0) })
        store.add([report(day: 1)])
        XCTAssertFalse(store.load().contains { $0.id == report(day: 1).id }, "verdrängter Bericht kam zurück")
    }

    func testNewCrashStillArrivesAfterDeleting() {
        store.add([report(day: 1)])
        store.removeAll()
        store.add([report(day: 2)])
        XCTAssertEqual(store.load().map(\.id), [report(day: 2).id])
    }

    func testSameStackWithDifferentReasonIsADifferentCrash() {
        store.add([report(reason: "SIGABRT"), report(reason: "Watchdog")])
        XCTAssertEqual(store.load().count, 2)
    }

    func testSameStackWithDifferentSignalIsADifferentCrash() {
        store.add([report(signal: 5), report(signal: 6)])
        XCTAssertEqual(store.load().count, 2)
    }

    /// Nicht lesbare Datei (statt fehlender): nichts anfassen. Ein Fehler würde sie beim atomaren Schreiben ersetzen.
    func testUnreadableFileIsLeftAlone() throws {
        store.add([report(day: 1)])
        let original = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        store.add([report(day: 2)])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(try Data(contentsOf: url), original, "die nicht lesbare Datei wurde überschrieben")
    }

    func testBrokenFileIsSetAsideAndNewReportsStillArrive() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kaputt".utf8).write(to: url)
        store.add([report()])
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("kaputt")), Data("kaputt".utf8), "kaputte Datei ging verloren")
    }

    func testFileTextCarriesDeviceVersionsReasonAndStack() {
        let text = report(stack: "{\"callStacks\":[]}", reason: "scene-update watchdog").fileText
        for part in ["2.0.7 (8)", "iPhone OS 27.2", "iPad16,6", "scene-update watchdog", "Signal: 5", "{\"callStacks\":[]}"] {
            XCTAssertTrue(text.contains(part), "„\(part)“ fehlt im Bericht")
        }
    }

    func testEmptyOptionalFieldsDoNotAppear() {
        let plain = CrashReport(reportDate: Date(), appVersion: "1", osVersion: "2", deviceType: "3", exceptionType: nil,
                                exceptionCode: nil, signal: nil, terminationReason: nil, objectiveCException: nil, callStackJSON: "{}")
        XCTAssertFalse(plain.summary.contains("Grund"))
        XCTAssertFalse(plain.summary.contains("Signal"))
        XCTAssertFalse(plain.summary.contains("Objective-C"))
    }
}
