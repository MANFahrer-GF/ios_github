import XCTest
@testable import TonneCore

final class CTracePlacesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    // Echte Antwort von /Orte (WZV Segeberg, 10.11.2026), gekürzt; Rheingau liefert zusätzlich einen leeren Eintrag.
    func testPlainListKeepsOrderDropsEmptyAndDuplicates() throws {
        let json = #"["","Bad Bramstedt","Bad Segeberg","Bark OT Bockhorn","Bad Segeberg"]"#
        XCTAssertEqual(try CTraceProvider.parseNames(Data(json.utf8)), ["Bad Bramstedt", "Bad Segeberg", "Bark OT Bockhorn"])
    }

    // Echte Antwort von OData.svc/Strassen (Landkreis Augsburg), gekürzt: derselbe Name je Ortsteil.
    func testODataStreetsAreDeduplicated() throws {
        let json = #"{"d":[{"__metadata":{"uri":"x"},"StrassenId":2442,"Name":"Adalbert-Stifter-Straße","OrtsteilName":"Königsbrunn"},{"StrassenId":9,"Name":"Adalbert-Stifter-Straße","OrtsteilName":"Ort B"},{"StrassenId":3,"Name":"Am Bach"}]}"#
        XCTAssertEqual(try CTraceProvider.parseNames(Data(json.utf8)), ["Adalbert-Stifter-Straße", "Am Bach"])
    }

    // Echte Antwort von OData.svc/Orte?$expand=Gebiet (Landkreis Aurich), gekürzt.
    func testAurichPlacesCarryAreaAndSkipTestAreas() throws {
        let json = #"{"d":[{"Name":"Westerende-Kirchloog","Gebiet":{"Name":"Ihlow"}},{"Name":"Aurich","Gebiet":{"Name":"Aurich"}},{"Name":"Test","Gebiet":{"Name":"Musterstadt"}},{"Name":"Lütetsburg","Gebiet":{"Name":"Hage"}}]}"#
        XCTAssertEqual(try CTraceProvider.parseNames(Data(json.utf8)), ["Ihlow / Westerende-Kirchloog", "Aurich", "Hage / Lütetsburg"])
    }

    func testBrokenAnswerThrows() {
        XCTAssertThrowsError(try CTraceProvider.parseNames(Data("<html>404</html>".utf8)))
    }

    /// Liefert das Portal keine Straßenliste, bleibt die Texteingabe (Bayreuth ist im Stub nicht hinterlegt → 404).
    func testFixedCityFallsBackToStreetTextWhenListFails() async throws {
        let provider = CTraceProvider(service: "bayreuthstadt-abfallkalender", client: HTTPClient(session: CTraceStub.session()))
        let step = try await provider.nextStep(after: [])
        XCTAssertEqual(step?.input, .text)
        XCTAssertEqual(step?.title, SelectionStep.streetTitle)
        let house = try await provider.nextStep(after: [SelectionOption(id: "a", title: "Am Wall")])
        XCTAssertEqual(house?.title, SelectionStep.houseNumberTitle)
    }

    func testLiveSegeberg() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_LIVE"] != nil, "TONNE_LIVE nicht gesetzt")
        let provider = CTraceProvider(service: "segebergwzv-abfallkalender")
        let placeStep = try await provider.nextStep(after: [])
        XCTAssertEqual(placeStep?.input, .list)
        let place = try XCTUnwrap(placeStep?.options.first { $0.title == "Bad Segeberg" })
        let streetStep = try await provider.nextStep(after: [place])
        XCTAssertEqual(streetStep?.input, .list)
        let street = try XCTUnwrap(streetStep?.options.first)
        // Hausnummer als Liste aus dem Portal
        let houseStep = try await provider.nextStep(after: [place, street])
        XCTAssertEqual(houseStep?.input, .list)
        let houseOption = try XCTUnwrap(houseStep?.options.first)
        let none = try await provider.nextStep(after: [place, street, houseOption])
        XCTAssertNil(none)
        let pickups = try await provider.pickups(for: [place, street, houseOption], calendar: calendar)
        XCTAssertGreaterThan(pickups.count, 10)
    }

    /// Alle Dienste mit Ortsliste: Ortsliste und Straßenliste kommen; optional als JSON ablegen (TONNE_ORTE_JSON=Pfad).
    func testLiveAllServicesListPlaces() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_LIVE"] != nil, "TONNE_LIVE nicht gesetzt")
        // Roth und Rheingau führen keine aktuellen Termine mehr (CTraceListsTests.testRetiredPortalsExplainWithoutAsking).
        let keys = ["augsburglandkreis", "segebergwzv-abfallkalender", "maintauberkreis-abfallkalender",
                    "grossgeraulandkreis-abfallkalender", "aurich-abfallkalender"]
        var all: [String: [String]] = [:]
        for key in keys {
            let provider = CTraceProvider(service: key)
            let step = try await provider.nextStep(after: [])
            XCTAssertEqual(step?.input, .list, key)
            let places = step?.options ?? []
            all[key] = places.map(\.title)
            XCTAssertFalse(places.isEmpty, key)
            let streets = try await provider.nextStep(after: [try XCTUnwrap(places.first)])
            XCTAssertEqual(streets?.input, .list, key)
            XCTAssertFalse(streets?.options.isEmpty ?? true, key)
        }
        if let path = ProcessInfo.processInfo.environment["TONNE_ORTE_JSON"] {
            let data = try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: URL(fileURLWithPath: path))
        }
        print("CTRACE-ORTE", all.mapValues(\.count))
    }
}
