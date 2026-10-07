import XCTest
@testable import TonneCore

/// Offline-Tests für die Hilfen der Sachsen-Portale.
final class SachsenPortalsProviderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func testRhythmDatesFollowISOWeekParity() throws {
        let cal = calendar
        let from = try XCTUnwrap(Days.parse("2026-10-01", calendar: cal))
        let to = try XCTUnwrap(Days.parse("2026-10-31", calendar: cal))
        // KW 41 (5.–11.10.) und KW 43 sind ungerade
        let thursdays = SachsenPortalsProvider.rhythmDates("donnerstags ungerade Kalenderwoche", from: from, to: to, calendar: cal)
        XCTAssertEqual(thursdays.map { Days.iso($0, calendar: cal) }, ["2026-10-08", "2026-10-22"])
        let combined = SachsenPortalsProvider.rhythmDates("mittwochs ungerade KW / donnerstags gerade KW", from: from, to: to, calendar: cal)
        XCTAssertEqual(combined.map { Days.iso($0, calendar: cal) }, ["2026-10-01", "2026-10-07", "2026-10-15", "2026-10-21", "2026-10-29"])
        XCTAssertTrue(SachsenPortalsProvider.rhythmDates("Abfuhr erfolgt nach Bedarf - Tel. 0375 4402-26600", from: from, to: to, calendar: cal).isEmpty)
    }

    func testICSWithMovedOccurrence() {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:a@kecl
        SUMMARY:Leichtverpackungen (gelbe Tonne)
        DTSTART;VALUE=DATE:20261104
        RRULE:FREQ=WEEKLY;BYDAY=WE;INTERVAL=2;UNTIL=20261231
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:Leichtverpackungen (gelbe Tonne)
        DTSTART;VALUE=DATE:20261119
        RECURRENCE-ID;TZID=Europe/Berlin:20261118
        UID:a@kecl
        END:VEVENT
        END:VCALENDAR
        """
        let days = SachsenPortalsProvider.parseICS(text, calendar: calendar).map { Days.iso($0.date, calendar: calendar) }
        XCTAssertEqual(days, ["2026-11-04", "2026-11-19", "2026-12-02", "2026-12-16", "2026-12-30"])
    }

    func testFactoryAndLabels() {
        let provider = ProviderFactory.make(kind: .portalsSachsen, serviceKey: "zaoe")
        XCTAssertEqual(provider.displayName, "ZAOE")
        let label = provider.label(for: [SelectionOption(id: "1|7245", title: "Meißen"), SelectionOption(id: "7246", title: "Meißen"),
                                         SelectionOption(id: "7401", title: "Albert-Mücke-Ring"), SelectionOption(id: "1-3-4-6", title: "Haushaltstonnen")])
        XCTAssertEqual(label, "Meißen, Albert-Mücke-Ring")
        let dresden = SachsenPortalsProvider(service: "dresden")
        XCTAssertEqual(dresden.label(for: [SelectionOption(id: "Neum", title: "Neum"), SelectionOption(id: "Neumarkt", title: "Neumarkt"),
                                           SelectionOption(id: "71676", title: "6")]), "Dresden, Neumarkt 6")
    }
}

extension LiveProviderTests {
    func testSachsenDresden() async throws {
        try await checkTyped(SachsenPortalsProvider(service: "dresden"), typed: ["Neumarkt"], prefer: ["Neumarkt", "6"], minCount: 3)
    }

    func testSachsenZAOE() async throws {
        try await check(SachsenPortalsProvider(service: "zaoe"), prefer: ["Meißen", "Meißen", "Albert-Mücke-Ring", "Haushaltstonnen"], minCount: 3)
    }

    func testSachsenKECL() async throws {
        try await check(SachsenPortalsProvider(service: "kecl"), prefer: ["Meerane", "Ahornweg"], minCount: 3)
    }

    func testSachsenLandkreisZwickau() async throws {
        try await check(SachsenPortalsProvider(service: "lkzwickau"), prefer: ["Crimmitschau", "Adlerstraße"], minCount: 3)
    }

    func testSachsenEKM() async throws {
        try await check(SachsenPortalsProvider(service: "ekm"), prefer: ["Döbeln", "Ahornstraße"], minCount: 3)
        try await check(SachsenPortalsProvider(service: "ekm"), prefer: ["Augustusburg"], minCount: 3)
    }
}
