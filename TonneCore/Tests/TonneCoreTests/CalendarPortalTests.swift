import XCTest
@testable import TonneCore

final class CalendarPortalTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // Echte Antwort von calendar/townarea-streets (AWL Neuss, 10.11.2026), gekürzt.
    func testStreetsKeepSplitRangesAsOwnRows() throws {
        let json = #"[{"strasseNummer":141,"strasseBezeichnung":"Adolfstrasse 1-19, 0-12","blockedHomeNumbers":[]},{"strasseNummer":100,"strasseBezeichnung":"Abteiweg","blockedHomeNumbers":[]},{"strasseNummer":140,"strasseBezeichnung":"Adolfstrasse 21-/ 14-999","blockedHomeNumbers":[]}]"#
        let streets = try JSONDecoder().decode([CalendarPortalProvider.Street].self, from: Data(json.utf8))
        let options = CalendarPortalProvider.streetOptions(streets)
        XCTAssertEqual(options.map(\.title), ["Abteiweg", "Adolfstrasse 1-19, 0-12", "Adolfstrasse 21-/ 14-999"])
        XCTAssertEqual(options.map(\.id), ["street:100", "street:141", "street:140"])
    }

    // Echte Antwort von calendar?isYear=true (Abteiweg, 2026), gekürzt: Der Monat zählt ab 0.
    func testMonthsCountFromZero() throws {
        let json = #"{"0-2026":{"3":["pink","gelb","grau"],"8":["blau"]},"11-2026":{"30":["braun"]}}"#
        let year = try JSONDecoder().decode(CalendarPortalProvider.Year.self, from: Data(json.utf8))
        let pickups = CalendarPortalProvider.pickups(year, calendar: calendar)
        XCTAssertEqual(pickups.count, 5)
        XCTAssertEqual(Set(pickups.filter { $0.date == day(2026, 1, 3) }.map(\.name)),
                       ["Restmülltonne (pink)", "Gelbe Tonne", "Restmülltonne (grau)"])
        XCTAssertEqual(pickups.filter { $0.date == day(2026, 1, 8) }.map(\.name), ["Papiertonne"])
        // Gegenprobe zur Zählung ab 0: „11“ ist Dezember, im November darf nichts stehen
        XCTAssertEqual(pickups.filter { $0.date == day(2026, 12, 30) }.map(\.name), ["Biotonne"])
        XCTAssertTrue(pickups.filter { calendar.component(.month, from: $0.date) == 11 }.isEmpty)
    }

    func testUnknownColourStaysVisibleAndImpossibleDaysAreDropped() throws {
        let json = #"{"1-2026":{"31":["grau"],"10":["tuerkis","grau","grau"]},"kaputt":{"1":["grau"]}}"#
        let year = try JSONDecoder().decode(CalendarPortalProvider.Year.self, from: Data(json.utf8))
        let pickups = CalendarPortalProvider.pickups(year, calendar: calendar)
        // Der 31. Februar fällt weg (kein stiller Sprung in den März), die doppelte Farbe zählt einmal
        XCTAssertEqual(pickups.map(\.date), [day(2026, 2, 10), day(2026, 2, 10)])
        XCTAssertEqual(pickups.map(\.name), ["Restmülltonne (grau)", "tuerkis"])
    }

    func testCatalogFindsNeuss() {
        let entry = ProviderCatalog.entries.first { $0.kind == .calendarPortal && $0.serviceKey == "awl_neuss" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(CatalogRegions.localEntries[entry?.id ?? ""], ["Kreis Rhein-Kreis Neuss|Neuss"])
        XCTAssertNotNil(CalendarPortalProvider.operators["awl_neuss"])
    }

    func testLiveNeuss() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_LIVE"] != nil, "TONNE_LIVE nicht gesetzt")
        let provider = CalendarPortalProvider(operator: "awl_neuss")
        let step = try await provider.nextStep(after: [])
        let streets = try XCTUnwrap(step?.options)
        XCTAssertGreaterThan(streets.count, 1000)
        let street = try XCTUnwrap(streets.first { $0.title == "Abteiweg" })
        let next = try await provider.nextStep(after: [street])
        XCTAssertNil(next)
        let pickups = try await provider.pickups(for: [street], calendar: calendar)
        XCTAssertGreaterThan(pickups.count, 100)
        let thisYear = calendar.component(.year, from: Date())
        XCTAssertTrue(pickups.contains { calendar.component(.year, from: $0.date) == thisYear })
        XCTAssertEqual(Set(pickups.map(\.name)).subtracting(CalendarPortalProvider.names.values), [])
    }
}
