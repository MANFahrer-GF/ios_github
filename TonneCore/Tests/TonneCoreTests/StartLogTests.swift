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
        let id = UUID()
        store.begin(id: id, appVersion: "2.0.11 (15)", at: Date(timeIntervalSince1970: 0))
        store.step("Umzug", milliseconds: 3, atMilliseconds: 40, start: id)
        store.step("Cloud", milliseconds: 29_000, atMilliseconds: 29_040, start: id)
        // Kein finish(): iOS hat den Start beendet. Ein neuer Prozess liest die Datei neu.
        let records = StartLogStore(url: url).load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].steps.map(\.name), ["Umzug", "Cloud"])
        XCTAssertFalse(records[0].finished)
        XCTAssertEqual(StartLogStore.text(records),
                       "Start 1970-01-01T00:00:00Z (2.0.11 (15)): Umzug 3 ms (bei 40 ms) · Cloud 29000 ms (bei 29040 ms) – NICHT abgeschlossen")
    }

    func testFinishMarksOnlyTheCurrentStart() {
        let b = UUID()
        store.begin(id: UUID(), appVersion: "a", at: Date(timeIntervalSince1970: 0))
        store.begin(id: b, appVersion: "b", at: Date(timeIntervalSince1970: 60))
        store.step("Modell", milliseconds: 5, atMilliseconds: 9, start: b)
        store.finish(start: b)
        XCTAssertEqual(store.load().map(\.finished), [false, true])
        XCTAssertEqual(store.load()[0].steps, [])
    }

    func testKeepsOnlyTheNewestStarts() {
        for i in 0..<(StartLogStore.maxRecords + 3) { store.begin(id: UUID(), appVersion: "\(i)", at: Date(timeIntervalSince1970: Double(i))) }
        XCTAssertEqual(store.load().map(\.appVersion), (3..<(StartLogStore.maxRecords + 3)).map(String.init))
    }

    func testBrokenFileCountsAsEmpty() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kaputt".utf8).write(to: url)
        XCTAssertEqual(store.load(), [])
        store.begin(id: UUID(), appVersion: "x", at: Date())
        XCTAssertEqual(store.load().count, 1)
    }

    /// Prüfung 19.11.: Datei da, aber nicht lesbar (vor dem ersten Entsperren) – nichts überschreiben, alte Starts bleiben.
    func testUnreadableFileKeepsTheOldStarts() throws {
        store.begin(id: UUID(), appVersion: "alt", at: Date(timeIntervalSince1970: 0))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        store.begin(id: UUID(), appVersion: "neu", at: Date(timeIntervalSince1970: 60))
        XCTAssertEqual(store.load(), [], "nicht lesbar zählt beim Lesen als leer")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(store.load().map(\.appVersion), ["alt"])
    }

    /// Scheitert `begin`, landen die Schritte dieses Starts nicht im Eintrag eines früheren (womöglich abgestürzten) Starts.
    func testStepAfterFailedBeginLeavesOtherStartsAlone() throws {
        let old = UUID()
        store.begin(id: old, appVersion: "alt", at: Date(timeIntervalSince1970: 0))
        store.step("Cloud", milliseconds: 29_000, atMilliseconds: 29_040, start: old)
        let before = store.load()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let current = UUID()
        store.begin(id: current, appVersion: "neu", at: Date(timeIntervalSince1970: 60))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        store.step("Modell", milliseconds: 5, atMilliseconds: 9, start: current)
        store.finish(start: current)
        XCTAssertEqual(store.load(), before)
    }

    func testFilesWithoutStartIdStillLoad() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"[{"started":0,"appVersion":"2.0.11 (15)","steps":[],"finished":false}]"#.utf8).write(to: url)
        XCTAssertEqual(store.load().map(\.appVersion), ["2.0.11 (15)"])
        XCTAssertNil(store.load()[0].id)
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
