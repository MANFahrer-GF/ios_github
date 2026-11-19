import XCTest
@testable import TonneCore

/// Zeile „Nächster Wecker“ in den Einstellungen (Codex-Befunde zum Feinschliff 19.11.2026).
final class NextAlarmTests: XCTestCase {
    func testPicksEarliestScheduledFixedAlarm() {
        let (a, b, c, d) = (UUID(), UUID(), UUID(), UUID())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            NextAlarm.Item(id: a, date: now.addingTimeInterval(7 * 86_400), isScheduled: true),
            NextAlarm.Item(id: b, date: now.addingTimeInterval(86_400), isScheduled: true),
            NextAlarm.Item(id: c, date: now.addingTimeInterval(3_600), isScheduled: false),   // klingelt gerade / vorbei
            NextAlarm.Item(id: d, date: nil, isScheduled: true),                               // kein fester Zeitpunkt
        ]
        XCTAssertEqual(NextAlarm.pick(items)?.id, b)
        XCTAssertNil(NextAlarm.pick([NextAlarm.Item(id: c, date: now, isScheduled: false)]), "Nichts geplant = keiner")
        XCTAssertNil(NextAlarm.pick([]))
    }

    func testTextNamesDayAndMonth() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        // Fr., 27.11.2026, 20:00 in Berlin
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: berlin, year: 2026, month: 11, day: 27, hour: 20).date!
        let de = NextAlarm.text(date: date, title: "Restmüll rausstellen", locale: Locale(identifier: "de_DE"), timeZone: berlin)
        XCTAssertTrue(de.contains("Fr"), de)
        XCTAssertTrue(de.contains("27"), de)
        XCTAssertTrue(de.contains("Nov"), de)
        XCTAssertTrue(de.contains("20:00"), de)
        XCTAssertTrue(de.hasSuffix(" · Restmüll rausstellen"), de)
        XCTAssertFalse(NextAlarm.text(date: date, title: nil, locale: Locale(identifier: "de_DE"), timeZone: berlin).contains("·"))
    }
}
