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

    func testWeekdayAndNumberColumnsAreNoWasteTypes() {
        let text = "Nr;Tag;Datum;Abfallart\n1;Mi;07.10.2026;Restmüll\n2;Do;08.10.2026;Biotonne\n"
        XCTAssertEqual(PickupCSV.parse(text, calendar: calendar).map(\.name), ["Restmüll", "Biotonne"])
        let noHeader = "Mi;07.10.2026;Restmüll\n3;08.10.2026;Papier\n"
        XCTAssertEqual(PickupCSV.parse(noHeader, calendar: calendar).map(\.name), ["Restmüll", "Papier"])
    }

    func testSeveralTypesInOneRowAndWideFormat() {
        let row = PickupCSV.parse("07.10.2026;Restmüll;Biotonne;ab 6 Uhr\n", calendar: calendar)
        XCTAssertEqual(Set(row.map(\.name)), ["Restmüll", "Biotonne"])
        let wide = "Restmüll;Biotonne;Papier\n07.10.2026;08.10.2026;09.10.2026\n21.10.2026;;\n"
        let pickups = PickupCSV.parse(wide, calendar: calendar)
        XCTAssertEqual(pickups.count, 4)
        XCTAssertEqual(pickups.filter { $0.name == "Restmüll" }.count, 2)
    }

    func testMoreDateFormats() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        func day(_ text: String) -> String? {
            PickupCSV.date(from: text, calendar: calendar, today: today).map { Days.iso($0, calendar: calendar) }
        }
        XCTAssertEqual(day("07.10.2026 00:00"), "2026-10-07")
        XCTAssertEqual(day("2026-10-07T00:00:00"), "2026-10-07")
        XCTAssertEqual(day("Mittwoch, 7. Oktober 2026"), "2026-10-07")
        XCTAssertEqual(day("Mi. 07.10.2026"), "2026-10-07")
        XCTAssertEqual(day("Mi 07.10.2026"), "2026-10-07")
        XCTAssertEqual(day("07-10-2026"), "2026-10-07")
        XCTAssertEqual(day("07. Okt"), "2026-10-07")
        XCTAssertEqual(day("05. Jan"), "2027-01-05")      // ohne Jahr: nächstes Vorkommen
        XCTAssertNil(day("2.5"))
        XCTAssertNil(day("1.100"))
        XCTAssertNil(day("Restmüll 120 l"))
    }

    func testUSDatesAreDetected() {
        let text = "Date,Waste type\n10/27/2026,Trash\n11/03/2026,Recycling\n"
        let rows = PickupCSV.parse(text, calendar: calendar)
        XCTAssertEqual(rows.map { Days.iso($0.date, calendar: calendar) }, ["2026-10-27", "2026-11-03"])
    }

    func testCommasInUnquotedNamesStillUseSemicolon() {
        let text = "Datum;Abfallart\n07.10.2026;Papier, Pappe, Kartonage\n08.10.2026;Gelber Sack, Leichtverpackungen\n"
        XCTAssertEqual(PickupCSV.parse(text, calendar: calendar).map(\.name), ["Papier, Pappe, Kartonage", "Gelber Sack, Leichtverpackungen"])
    }

    func testExportEscapesFormulas() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 12, day: 24))!
        XCTAssertTrue(PickupCSV.build([.init(date: day, name: "=HYPERLINK(1)")], calendar: calendar).contains(";'=HYPERLINK(1);"))
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

    func testMunicipalityEntriesDoNotCoverWholeDistrict() {
        let byName = Dictionary(uniqueKeysWithValues: ProviderCatalog.coverage.map { ($0.district, $0) })
        // Fehlt eine Gemeinde, ist der Kreis nur „teilweise“ dabei
        let partial = DistrictCoverage(district: "Landkreis Test", state: "Test", entryIDs: [], localEntryIDs: ["a"],
                                       localPlaces: ["A"], municipalityCount: 2, missingPlaces: ["B"])
        XCTAssertFalse(partial.isCovered)
        XCTAssertTrue(partial.isPartial)
        // Hochtaunus: nur Gemeinde-Kalender (Bad Homburg, Oberursel …) – seit Okt. 2026 für alle 13 Gemeinden
        let hochtaunus = byName["Landkreis Hochtaunuskreis"]
        XCTAssertEqual(hochtaunus?.entryIDs.isEmpty, true, "kein kreisweiter Entsorger")
        XCTAssertEqual(hochtaunus?.isCovered, true)
        XCTAssertTrue(hochtaunus?.localPlaces.contains("Oberursel (Taunus)") == true)
        // Eine kreisfreie Stadt mit eigenem Gemeinde-Kalender gilt als abgedeckt
        XCTAssertEqual(byName["Kreisfreie Stadt Pirmasens"]?.isCovered, true)
    }

    func testSearchShowsOnlyMatchingMunicipalityEntries() {
        // Unterhaching (Landkreis München): kein fremder Gemeinde-Kalender (Aschheim, Planegg …)
        let titles = ProviderCatalog.search("Unterhaching").map(\.title)
        XCTAssertTrue(titles.contains { $0.contains("Unterhaching") })
        XCTAssertFalse(titles.contains { $0.contains("Aschheim") || $0.contains("Planegg") })
        XCTAssertTrue(ProviderCatalog.uncoveredMunicipalities(matching: "Unterhaching").isEmpty)
        // Seit Oktober 2026 angebunden: Soltau (Heidekreis), Öhningen (Landkreis Konstanz, PDF-Jahresdaten)
        XCTAssertTrue(ProviderCatalog.uncoveredMunicipalities(matching: "Soltau").isEmpty)
        XCTAssertTrue(ProviderCatalog.uncoveredMunicipalities(matching: "Öhningen").isEmpty)
        // Konstanz: Müllmann, MZV Hegau, Gemeinde-Kalender und Jahresdaten zusammen – kein kreisweiter Eintrag
        let konstanz = ProviderCatalog.coverage.first { $0.district == "Landkreis Konstanz" }
        XCTAssertEqual(konstanz?.entryIDs.isEmpty, true, "Müllmann zählt nur für seine Gemeinden")
        XCTAssertEqual(konstanz?.isCovered, true)
    }

    /// „Teilweise“ nennt die fehlenden Gemeinden; unbewohnte gemeindefreie Gebiete zählen nicht.
    func testMissingPlaces() {
        let byName = Dictionary(uniqueKeysWithValues: ProviderCatalog.coverage.map { ($0.district, $0) })
        let wmk = byName["Landkreis Werra-Meißner-Kreis"]
        XCTAssertFalse(wmk?.missingPlaces.contains("Gutsbezirk Kaufunger Wald") == true)
        XCTAssertEqual(wmk?.isCovered, true, "der unbewohnte Gutsbezirk hält den Kreis nicht auf „teilweise“")
        XCTAssertEqual(wmk.map { $0.municipalityCount - $0.missingPlaces.count }, wmk?.localPlaces.filter { $0 != "Gutsbezirk Kaufunger Wald" }.count)
        for item in ProviderCatalog.coverage where item.isCovered && item.entryIDs.isEmpty {
            XCTAssertTrue(item.missingPlaces.isEmpty, item.district)
        }
    }

    /// „Geht mein Ort?“: Gemeinde → Entsorger samt Einschränkung.
    func testCheckPlace() throws {
        let soltau = try XCTUnwrap(ProviderCatalog.checkPlace("Soltau").first)
        XCTAssertEqual(soltau.district, "Landkreis Heidekreis")
        XCTAssertTrue(soltau.entries.contains { $0.serviceKey == "heidekreis" })
        XCTAssertNil(ProviderCatalog.restriction(for: try XCTUnwrap(soltau.entries.first { $0.serviceKey == "heidekreis" })))

        // Gemeinde-Einträge nur für ihre Gemeinde: Wehrheims Kalender gehört nicht zu Usingen
        let usingen = try XCTUnwrap(ProviderCatalog.checkPlace("Usingen").first)
        XCTAssertTrue(usingen.isCovered)
        XCTAssertFalse(usingen.entries.contains { $0.title.contains("Wehrheim") })

        let weimar = try XCTUnwrap(ProviderCatalog.checkPlace("Weimar").first { $0.district == "Kreisfreie Stadt Weimar" })
        let weimarEntry = try XCTUnwrap(weimar.entries.first { $0.serviceKey == "weimar" })
        XCTAssertEqual(ProviderCatalog.restriction(for: weimarEntry), "Termine berechnet, ohne Verschiebung an Feiertagen.")

        let amberg = try XCTUnwrap(ProviderCatalog.checkPlace("Ensdorf").first { $0.district == "Landkreis Amberg-Sulzbach" })
        XCTAssertTrue(amberg.entries.contains { ProviderCatalog.restriction(for: $0) == "Nur Restmüll und Altpapier." })
        let sontra = try XCTUnwrap(ProviderCatalog.checkPlace("Sontra").first)
        XCTAssertTrue(sontra.entries.contains { ProviderCatalog.restriction(for: $0)?.contains("Gelbe Tonne nicht enthalten") == true }, "Zusatzhinweis der Jahresdaten bleibt erhalten")

        XCTAssertTrue(ProviderCatalog.checkPlace("Oerbke").isEmpty, "Ortsteil, keine Gemeinde – die Seite fällt auf die Entsorgersuche zurück")
        XCTAssertTrue(ProviderCatalog.checkPlace("So").isEmpty, "zu kurz")
    }

    /// Nur „weitere“ Einträge gelten nicht als angebunden.
    func testOnlyOtherEntriesIsNotCovered() {
        let check = PlaceCheck(name: "X", district: "Landkreis Y", entries: [], otherEntries: [CatalogEntry(kind: .icsURL, serviceKey: "https://x", title: "Amt Z")])
        XCTAssertFalse(check.isCovered)
    }

    /// Einträge für andere Gemeinden des Kreises getrennt; gleichnamige Gemeinden vollständig.
    func testCheckPlaceSeparatesOtherTowns() throws {
        let perleberg = try XCTUnwrap(ProviderCatalog.checkPlace("Perleberg").first)
        XCTAssertTrue(perleberg.entries.contains { $0.title.hasPrefix("Stadt Perleberg") }, "\(perleberg.entries.map(\.title))")
        XCTAssertFalse(perleberg.entries.contains { $0.title.hasPrefix("Gemeinde Gumtow") })
        XCTAssertTrue(perleberg.otherEntries.contains { $0.title.hasPrefix("Gemeinde Gumtow") })
        // Rühstädt: kreisweit über die Abfall+-App (Prignitz) angebunden; das Amt Bad Wilsnack/Weisen zählt seine Gemeinden
        // nicht auf und steht als wahrscheinlichster weiterer Kandidat vorn
        let ruehstaedt = try XCTUnwrap(ProviderCatalog.checkPlace("Rühstädt").first)
        XCTAssertTrue(ruehstaedt.entries.contains { $0.title.hasPrefix("Abfall+ Wecker") })
        XCTAssertTrue(ruehstaedt.otherEntries.first?.title.hasPrefix("Amt ") == true, "\(ruehstaedt.otherEntries.map(\.title))")
        // Kreisweite Einträge bleiben passend
        let feuchtwangen = try XCTUnwrap(ProviderCatalog.checkPlace("Feuchtwangen").first)
        XCTAssertTrue(feuchtwangen.entries.contains { $0.title == "Landkreis Ansbach" })
        let friedrichshafen = try XCTUnwrap(ProviderCatalog.checkPlace("Friedrichshafen").first)
        XCTAssertTrue(friedrichshafen.entries.contains { $0.title.hasPrefix("Bodenseekreis") })
        XCTAssertTrue(friedrichshafen.otherEntries.isEmpty || !friedrichshafen.entries.isEmpty)
        // Zehn Gemeinden heißen Neuenkirchen – alle müssen erscheinen
        XCTAssertEqual(ProviderCatalog.checkPlace("Neuenkirchen").count, ProviderCatalog.municipalities(matching: "Neuenkirchen").count)
        XCTAssertGreaterThan(ProviderCatalog.checkPlace("Neuenkirchen").count, 8)
    }

    func testRestrictedEntries() {
        let keys = Set(ProviderCatalog.restrictedEntries.map(\.serviceKey))
        XCTAssertTrue(keys.isSuperset(of: ["weimar", "landkreis_as", "ansbach", "saaleholzland", "sontra"]), "\(keys.sorted())")
        XCTAssertFalse(keys.contains("heidekreis"))
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

final class GemosNoticeTests: XCTestCase {
    func testNoticeIsNoPickup() {
        XCTAssertTrue(GemosWasteBoxProvider.isNotice("Es sind neue Abfuhrtermine verfügbar! Bitte laden Sie den Kalender neu."))
        XCTAssertFalse(GemosWasteBoxProvider.isNotice("Restabfall 2-wöchentlich"))
    }
}
