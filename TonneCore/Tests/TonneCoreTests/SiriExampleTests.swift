import XCTest
@testable import TonneCore

/// Die Beispielantwort auf der Siri-Seite nannte „Mi., 17. Okt.“ – der 17.10.2026 ist ein Samstag.
final class SiriExampleTests: XCTestCase {
    func testBirthdayExampleUsesTheRealWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 10))!
        let text = SpokenSummary.birthdayExample(now: now, calendar: calendar)
        XCTAssertTrue(text.contains("Oma Erika"), text)
        XCTAssertTrue(text.contains("Paul"), text)
        // Paul: 9 Tage nach dem 8.10.2026 = Samstag, 17. Oktober
        XCTAssertTrue(text.contains("17."), text)
        XCTAssertFalse(text.contains("Mi."), text)
        XCTAssertTrue(text.contains("Sa"), text)
    }
}
