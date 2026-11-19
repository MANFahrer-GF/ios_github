import XCTest
@testable import TonneCore

final class StartLogTests: XCTestCase {
    private var url: URL!
    private var store: StartLogStore!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("startlog-\(UUID().uuidString)/start.json")
        store = StartLogStore(url: url)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testAbortedStartKeepsItsStepsAndIsMarkedUnfinished() {
        store.begin(appVersion: "2.0.11 (15)", at: Date(timeIntervalSince1970: 0))
        store.step("Umzug", milliseconds: 3, atMilliseconds: 40)
        store.step("Cloud", milliseconds: 29_000, atMilliseconds: 29_040)
        // Kein finish(): iOS hat den Start beendet. Ein neuer Prozess liest die Datei neu.
        let records = StartLogStore(url: url).load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].steps.map(\.name), ["Umzug", "Cloud"])
        XCTAssertFalse(records[0].finished)
        XCTAssertEqual(StartLogStore.text(records),
                       "Start 1970-01-01T00:00:00Z (2.0.11 (15)): Umzug 3 ms (bei 40 ms) · Cloud 29000 ms (bei 29040 ms) – NICHT abgeschlossen")
    }

    func testFinishMarksOnlyTheCurrentStart() {
        store.begin(appVersion: "a", at: Date(timeIntervalSince1970: 0))
        store.begin(appVersion: "b", at: Date(timeIntervalSince1970: 60))
        store.step("Modell", milliseconds: 5, atMilliseconds: 9)
        store.finish()
        XCTAssertEqual(store.load().map(\.finished), [false, true])
        XCTAssertEqual(store.load()[0].steps, [])
    }

    func testKeepsOnlyTheNewestStarts() {
        for i in 0..<(StartLogStore.maxRecords + 3) { store.begin(appVersion: "\(i)", at: Date(timeIntervalSince1970: Double(i))) }
        XCTAssertEqual(store.load().map(\.appVersion), ["3", "4", "5", "6", "7"])
    }

    func testBrokenFileCountsAsEmpty() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kaputt".utf8).write(to: url)
        XCTAssertEqual(store.load(), [])
        store.begin(appVersion: "x", at: Date())
        XCTAssertEqual(store.load().count, 1)
    }

    func testStartLogIsInTheFileButNotInTheIdentity() {
        func report(_ log: String?) -> CrashReport {
            CrashReport(reportDate: Date(timeIntervalSince1970: 0), appVersion: "2.0.11 (15)", osVersion: "iPhone OS 27.2", deviceType: "iPhone18,1",
                        exceptionType: 10, exceptionCode: 0, signal: 9, terminationReason: "0x8BADF00D", objectiveCException: nil,
                        callStackJSON: "{}", startLog: log)
        }
        let with = report("Start …")
        XCTAssertEqual(with.id, report(nil).id)
        XCTAssertTrue(with.fileText.contains("Letzte Starts:\nStart …\n\n{}"))
        XCTAssertFalse(report(nil).fileText.contains("Letzte Starts"))
    }

    func testReportsSavedBeforeTheFieldExistedStillLoad() throws {
        let old = #"[{"id":"x","reportDate":0,"appVersion":"2.0.7 (8)","osVersion":"o","deviceType":"d","callStackJSON":"{}","prompted":false}]"#
        let reports = try JSONDecoder().decode([CrashReport].self, from: Data(old.utf8))
        XCTAssertNil(reports[0].startLog)
    }
}
