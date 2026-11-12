import XCTest
@testable import TonneCore

/// Meldung für Orte ohne abrufbaren Online-Kalender: Klartext je Grund mit Entsorger, Webseite und Prüftag, geprüft je
/// Gemeinde (nicht je Kreis). Anlass: In Kreisen mit irgendeinem Entsorger warnte der Assistent nie, und nur
/// „Portal abgeschaltet“ zeigte überhaupt seinen Grund.
final class PlaceGapTests: XCTestCase {
    override func setUp() { L10n.forcedLanguage = "de" }
    override func tearDown() { L10n.forcedLanguage = nil }

    private func check(_ name: String, in district: String) throws -> PlaceCheck {
        try XCTUnwrap(ProviderCatalog.checkPlace(name).first { $0.district == district }, "\(name) im \(district)")
    }

    /// Jede nachweisliche Lücke trägt Entsorger, https-Webseite und lesbaren Prüftag – sonst fiele die Karte auf den
    /// allgemeinen Satz zurück.
    func testEveryGapCarriesProviderWebsiteAndDate() {
        XCTAssertFalse(PlaceMapIndex.gaps.isEmpty)
        for (key, gap) in PlaceMapIndex.gaps where gap.isUnavailable {
            XCTAssertFalse(gap.provider?.isEmpty ?? true, key)
            XCTAssertEqual(gap.website?.scheme, "https", key)
            XCTAssertNotNil(gap.checkedOnText, key)
        }
    }

    func testPdfOnlyNamesProviderDateAndPdf() throws {
        let langeoog = try check("Langeoog", in: "Landkreis Wittmund")
        XCTAssertFalse(langeoog.isCovered)
        XCTAssertTrue(langeoog.isUnavailable)
        let gap = try XCTUnwrap(langeoog.gap)
        XCTAssertEqual(gap.reason, "nur_pdf")
        XCTAssertEqual(gap.website?.host, "www.landkreis-wittmund.de")
        let text = try XCTUnwrap(langeoog.gapNote)
        XCTAssertTrue(text.contains("Landkreis Wittmund (Abfuhr Fa. Augustin)"), text)
        XCTAssertTrue(text.contains("am 11.11.2026"), text)
        XCTAssertTrue(text.contains("PDF"), text)
        XCTAssertFalse(text.contains("gibt es keinen"), "nur sagen, was wir bei der Prüfung gesehen haben")
    }

    func testNotListedNamesThePlaceAndProvider() throws {
        let groede = try check("Gröde", in: "Kreis Nordfriesland")
        let text = try XCTUnwrap(groede.gapNote)
        XCTAssertEqual(groede.gap?.reason, "nicht_gefuehrt")
        XCTAssertTrue(text.contains("am 11.11.2026 stand Gröde nicht im Online-Kalender von Kreis Nordfriesland (Abfall+-App)"), text)
        XCTAssertFalse(text.contains("k4systems"), "keine App-Paketkennung im Text")
    }

    /// Rhein-Lahn: Portal nach Sicherheitsvorfall abgeschaltet; seit 2.0.10 Termine aus den PDFs der Verbandsgemeinden.
    func testRheinLahnComesFromPDFData() throws {
        let diez = try check("Diez", in: "Landkreis Rhein-Lahn-Kreis")
        XCTAssertNil(diez.gapNote)
        XCTAssertTrue(diez.entries.contains { $0.kind == .jahresdaten && $0.serviceKey == "rlk_diez_diez" })
    }

    func testEnglishTextAndDate() throws {
        L10n.forcedLanguage = "en"
        let langeoog = try check("Langeoog", in: "Landkreis Wittmund")
        XCTAssertEqual(langeoog.gap?.checkedOnText, "11 Nov 2026")
        XCTAssertTrue(langeoog.gapNote?.hasPrefix("When we checked on 11 Nov 2026") == true, langeoog.gapNote ?? "")
        XCTAssertEqual(langeoog.gap?.headline, "No online calendar to fetch")
    }

    /// Gegenprobe: Ein belegter Ort hat keine Lücke und keine Karte.
    func testCoveredPlaceHasNoGap() throws {
        let neuss = try check("Neuss", in: "Kreis Rhein-Kreis Neuss")
        XCTAssertTrue(neuss.isCovered)
        XCTAssertNil(neuss.gap)
        XCTAssertNil(neuss.gapNote)
        XCTAssertFalse(neuss.isUnavailable)
        XCTAssertTrue(ProviderCatalog.uncoveredPlaces(matching: "Neuss").isEmpty)
    }

    /// Je Gemeinde geprüft: Langeoog liegt in einem Kreis mit Entsorgern im Katalog – die alte Prüfung je Kreis hätte
    /// nicht gewarnt.
    func testUncoveredIsCheckedPerMunicipalityNotPerDistrict() throws {
        let wittmund = try XCTUnwrap(ProviderCatalog.coverage.first { $0.district == "Landkreis Wittmund" })
        XCTAssertFalse(wittmund.allEntryIDs.isEmpty, "Voraussetzung: Der Kreis hat Entsorger im Katalog")
        let missing = ProviderCatalog.uncoveredPlaces(matching: "Langeoog")
        XCTAssertEqual(missing.map(\.id), ["Landkreis Wittmund|Langeoog"])
        // Gegenprobe im selben Kreis: Wittmund selbst ist belegt
        XCTAssertTrue(ProviderCatalog.uncoveredPlaces(matching: "Wittmund").isEmpty)
    }

    /// Gleichnamige Orte: Jede Karte trägt ihren eigenen Namen und Kreis; belegte Namensvettern erscheinen nicht.
    /// (Früher: erster Name mit den Kreisen aller Treffer kombiniert, und nur, wenn kein Treffer belegt war.)
    func testSameNamePlacesKeepTheirOwnDistrict() throws {
        let all = ProviderCatalog.checkPlace("Neunkirchen")
        XCTAssertGreaterThan(all.count, 1, "Voraussetzung: mehrere Gemeinden heißen Neunkirchen")
        XCTAssertTrue(all.contains(where: \.isCovered), "Voraussetzung: mindestens ein Neunkirchen ist belegt")
        let missing = ProviderCatalog.uncoveredPlaces(matching: "Neunkirchen")
        XCTAssertEqual(missing.map(\.id), ["Landkreis Neunkirchen|Neunkirchen"])
        XCTAssertEqual(missing.first?.gap?.reason, "nur_pdf")
    }

    /// Die Suche bietet für einen nachweislich nicht holbaren Ort keine Kreis-Entsorger an, die ihn nicht führen
    /// (Auswahl endete sonst bei „Nichts gefunden“). Gegenprobe: Für Wittmund selbst bleiben sie.
    func testSearchOffersNoDistrictCandidatesForUnavailablePlace() {
        let wittmundIDs = Set(CatalogRegions.entryDistricts.filter { $0.value.contains("Landkreis Wittmund") }.map(\.key))
        XCTAssertFalse(wittmundIDs.isEmpty, "Voraussetzung: kreisweite Entsorger im Landkreis Wittmund")
        let langeoog = Set(ProviderCatalog.search("Langeoog").map(\.id))
        XCTAssertTrue(langeoog.isDisjoint(with: wittmundIDs), "\(langeoog.intersection(wittmundIDs))")
        XCTAssertFalse(Set(ProviderCatalog.search("Wittmund").map(\.id)).isDisjoint(with: wittmundIDs))
    }

    /// Auch ein Titel-Treffer fällt weg, wenn er an den Kreis eines nicht holbaren Orts gebunden ist
    /// („Garmisch-Partenkirchen“ nur als PDF → nicht „Kreis Garmisch-Partenkirchen“). Gegenprobe: Murnau im selben
    /// Kreis wird vom Kreis-Eintrag geführt und behält ihn.
    func testSearchDropsTitleHitBoundToUnavailablePlace() throws {
        let gap = try check("Garmisch-Partenkirchen", in: "Landkreis Garmisch-Partenkirchen")
        XCTAssertTrue(gap.isUnavailable, "Voraussetzung: Garmisch-Partenkirchen ist nur als PDF belegt")
        let kreis = try XCTUnwrap(CatalogRegions.entryDistricts.first {
            $0.value.contains("Landkreis Garmisch-Partenkirchen")
        }?.key)
        XCTAssertFalse(ProviderCatalog.search("Garmisch-Partenkirchen").map(\.id).contains(kreis))
        XCTAssertTrue(ProviderCatalog.search("Murnau a.Staffelsee").map(\.id).contains(kreis))
    }

    /// „Ort melden“: Gemeinde, Kreis und Grund vorbefüllt, keine Adresse oder Koordinaten.
    func testReportMailIsPrefilledWithoutAddress() throws {
        let langeoog = try check("Langeoog", in: "Landkreis Wittmund")
        let url = try XCTUnwrap(langeoog.reportMailURL)
        XCTAssertEqual(url.scheme, "mailto")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let subject = try XCTUnwrap(items.first { $0.name == "subject" }?.value)
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertEqual(subject, "Ort fehlt: Langeoog")
        XCTAssertTrue(body.contains("Gemeinde: Langeoog"))
        XCTAssertTrue(body.contains("Kreis: Landkreis Wittmund"))
        XCTAssertTrue(body.contains("PDF"), "Grund steht in der Mail")
        XCTAssertFalse(body.lowercased().contains("straße") || body.lowercased().contains("koordinate"))
    }

    /// „Ort melden“ ohne gefundene Gemeinde: kein Suchtext in der Mail (er könnte eine Adresse sein), Felder leer.
    func testBlankReportMailCarriesNoInput() throws {
        let url = try XCTUnwrap(PlaceCheck.blankReportMailURL)
        XCTAssertEqual(url.scheme, "mailto")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "subject" }?.value, "Ort fehlt")
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.hasPrefix("Gemeinde:\nKreis:\n"), body)
    }

    /// Prüftag nur als echter Kalendertag: 2026-02-30 wird nicht still zum 02.03., der 29.02. eines Schaltjahrs gilt.
    func testCheckedOnRejectsImpossibleDates() {
        func text(_ date: String) -> String? {
            PlaceGap(reason: "nur_pdf", isUnavailable: true, provider: "A", checkedOn: date).checkedOnText
        }
        XCTAssertNil(text("2026-02-30"))
        XCTAssertNil(text("2027-02-29"))
        XCTAssertNil(text("2026-11-31"))
        XCTAssertEqual(text("2028-02-29"), "29.02.2028")
        XCTAssertEqual(text("2026-11-10"), "10.11.2026")
    }

    /// Ohne Quelle (nicht belegt) bleibt der allgemeine Satz, ohne erfundenen Entsorger.
    func testGapWithoutSourceFallsBackToNote() {
        let gap = PlaceGap(reason: "nur_pdf", isUnavailable: true)
        XCTAssertEqual(gap.explanation(for: "X"), PlaceMapIndex.note("nur_pdf"))
        XCTAssertNil(gap.checkedOnText)
        XCTAssertNil(PlaceGap(reason: "", isUnavailable: false, provider: "A", checkedOn: "2026-13-01").checkedOnText)
    }
}
