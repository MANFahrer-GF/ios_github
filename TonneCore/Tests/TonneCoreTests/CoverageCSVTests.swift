import XCTest
@testable import TonneCore

final class PickupCSVTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func testGermanExcelWithHeaderAndBOM() {
        let text = "\u{FEFF}Datum;Abfallart;Hinweis\r\n07.10.2026;Restmüll;\r\n08.10.2026;Gelber Sack;ab 6 Uhr\r\n"
        let rows = PickupCSV.parse(text, calendar: calendar)
        XCTAssertEqual(rows.map(\.name), ["Restmüll", "Gelber Sack"])
        XCTAssertEqual(rows.map { Days.iso($0.date, calendar: calendar) }, ["2026-10-07", "2026-10-08"])
        XCTAssertEqual(rows[1].note, "ab 6 Uhr")
    }

    func testCommaISOAndSwappedColumns() {
        let text = "Abfallart,Datum\nBiotonne,2026-11-02\n\"Papier, blau\",2026-11-03\nkaputt,32.13.2026\n"
        let rows = PickupCSV.parse(text, calendar: calendar)
        XCTAssertEqual(rows.map(\.name), ["Biotonne", "Papier, blau"])
    }

    func testShortYearsWeekdayAndDuplicates() {
        let text = "Mi, 7.10.26\tRestmüll\nMi, 7.10.26\tRestmüll\n31.02.2026\tBio\n"
        let rows = PickupCSV.parse(text, calendar: calendar)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(Days.iso(rows[0].date, calendar: calendar), "2026-10-07")
    }

    func testExportRoundTrip() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 12, day: 24))!
        let csv = PickupCSV.build([.init(date: day, name: "Gelber Sack", note: "Hinweis; mit Semikolon")], calendar: calendar)
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("24.12.2026;Gelber Sack;\"Hinweis; mit Semikolon\""))
        let back = PickupCSV.parse(csv, calendar: calendar)
        XCTAssertEqual(back.first?.name, "Gelber Sack")
        XCTAssertEqual(back.first?.note, "Hinweis; mit Semikolon")
    }

    func testTemplateParses() {
        let rows = PickupCSV.parse(PickupCSV.template(calendar: calendar), calendar: calendar)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(calendar.component(.weekday, from: rows[0].date), 2)   // Montag
    }
}

final class CoverageTests: XCTestCase {
    func testEveryDistrictListedOnce() {
        let all = ProviderCatalog.coverage
        XCTAssertEqual(all.count, Set(all.map(\.district)).count)
        XCTAssertGreaterThanOrEqual(all.count, 400)
        XCTAssertGreaterThan(all.filter(\.isCovered).count, 250)
        XCTAssertTrue(all.allSatisfy { !$0.state.isEmpty && $0.municipalityCount > 0 })
    }

    func testKnownDistricts() {
        let byName = Dictionary(uniqueKeysWithValues: ProviderCatalog.coverage.map { ($0.district, $0) })
        XCTAssertEqual(byName["Landkreis Peine"]?.isCovered, true)
        XCTAssertEqual(byName["Kreisfreie Stadt Brandenburg an der Havel"]?.isCovered, true)
        XCTAssertEqual(byName["Landkreis Potsdam-Mittelmark"]?.isCovered, true)
    }

    func testDisplayNames() {
        XCTAssertEqual(DistrictCoverage.displayName("Landkreis Rems-Murr-Kreis"), "Rems-Murr-Kreis")
        XCTAssertEqual(DistrictCoverage.displayName("Landkreis Peine"), "Landkreis Peine")
        XCTAssertEqual(DistrictCoverage.displayName("Kreis Städteregion Aachen"), "Städteregion Aachen")
    }

    func testSearchPrefersDistrictOfMunicipality() {
        // Bergen (Landkreis Celle): der Celler Entsorger vor „Bergenhusen“ & Co.
        let results = ProviderCatalog.search("Bergen")
        let celle = results.firstIndex { (CatalogRegions.entryDistricts[$0.id] ?? []).contains("Landkreis Celle") }
        let other = results.firstIndex { $0.places.contains("Bergenhusen") }
        XCTAssertNotNil(celle)
        if let celle, let other { XCTAssertLessThan(celle, other) }
        XCTAssertFalse(ProviderCatalog.search("Werder").isEmpty)
        XCTAssertFalse(ProviderCatalog.search("Brandenburg an der Havel").isEmpty)
    }
}
