import XCTest
@testable import TonneCore

/// Update-Prüfung vor dem Senden eines Absturzberichts (Thomas, 19.11.2026: zu viele Berichte alter Versionen).
final class UpdateCheckTests: XCTestCase {
    func testVersionOrder() {
        XCTAssertTrue(UpdateCheck.isOlder("2.0.11 (15)", than: "2.1.0"))
        XCTAssertTrue(UpdateCheck.isOlder("2.0.9", than: "2.0.11"))   // numerisch, nicht als Text
        XCTAssertFalse(UpdateCheck.isOlder("2.1", than: "2.1.0"))
        XCTAssertFalse(UpdateCheck.isOlder("2.1.0 (17)", than: "2.1.0"))
        XCTAssertFalse(UpdateCheck.isOlder("2.1.1", than: "2.1.0"))
        XCTAssertFalse(UpdateCheck.isOlder("?", than: "2.1.0"), "Unlesbar zählt nie als alt")
    }

    func testVerdict() {
        XCTAssertEqual(UpdateCheck.verdict(report: "2.0.11 (15)", installed: "2.0.11 (15)", store: "2.1.0"), .updateAvailable(store: "2.1.0"))
        XCTAssertEqual(UpdateCheck.verdict(report: "2.0.11 (15)", installed: "2.1.0 (17)", store: "2.1.0"), .reportFromOlderVersion(report: "2.0.11", installed: "2.1.0"))
        XCTAssertEqual(UpdateCheck.verdict(report: "2.0.11", installed: "2.1.0 (17)", store: nil), .reportFromOlderVersion(report: "2.0.11", installed: "2.1.0"), "Auch ohne Netz")
        XCTAssertEqual(UpdateCheck.verdict(report: "2.1.0 (17)", installed: "2.1.0 (17)", store: "2.1.0"), .current)
        XCTAssertEqual(UpdateCheck.verdict(report: "2.1.0 (17)", installed: "2.1.0 (17)", store: nil), .current, "Ohne Netz senden wie bisher")
        // Apple meldet die neue Version manchmal erst Stunden später: Store älter als installiert ist kein Update
        XCTAssertEqual(UpdateCheck.verdict(report: "2.1.1", installed: "2.1.1", store: "2.1.0"), .current)
    }

    func testLookupResponse() throws {
        let json = #"{"resultCount":1,"results":[{"version":"2.1.0","trackViewUrl":"https://apps.apple.com/de/app/id123?uo=4","bundleId":"x"}]}"#
        let found = try XCTUnwrap(UpdateCheck.storeVersion(fromLookup: Data(json.utf8)))
        XCTAssertEqual(found.version, "2.1.0")
        XCTAssertEqual(found.url?.host, "apps.apple.com")
        // Codex-Befund 1: ohne trackViewUrl die Seite aus der App-Nummer
        let bare = try XCTUnwrap(UpdateCheck.storeVersion(fromLookup: Data(#"{"results":[{"version":"2.1.0","trackId":6123456789}]}"#.utf8)))
        XCTAssertEqual(bare.url?.absoluteString, "https://apps.apple.com/app/id6123456789")
        XCTAssertNil(UpdateCheck.storeVersion(fromLookup: Data(#"{"resultCount":0,"results":[]}"#.utf8)))
        XCTAssertNil(UpdateCheck.storeVersion(fromLookup: Data("kaputt".utf8)))
    }

    /// „Trotzdem senden“: Vermerk steht oben in Datei und Mail-Text, ohne Vermerk bleibt alles wie bisher (Codex-Befund 2).
    func testNoteIsOnTopOfFileAndMail() {
        let report = CrashReport(reportDate: Date(timeIntervalSince1970: 0), appVersion: "2.0.11 (15)", osVersion: "iOS 27", deviceType: "iPhone",
                                 exceptionType: nil, exceptionCode: nil, signal: 6, terminationReason: nil, objectiveCException: nil, callStackJSON: "{}")
        let note = "Gesendet trotz verfügbarem Update: installiert 2.0.11 (15), im App Store 2.1.0"
        XCTAssertTrue(report.fileText(note: note).hasPrefix(note + "\n\n" + "App: 2.0.11 (15)"))
        XCTAssertTrue(report.summary(note: note).hasPrefix(note + "\nApp: 2.0.11 (15)"))
        XCTAssertEqual(report.fileText(note: nil), report.fileText)
        XCTAssertEqual(report.summary(note: nil), report.summary)
    }
}
