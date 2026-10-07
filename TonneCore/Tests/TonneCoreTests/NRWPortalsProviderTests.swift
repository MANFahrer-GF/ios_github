import XCTest
@testable import TonneCore

/// Offline: Namensaufbereitung der Kreis-Herford-Portale.
final class NRWPortalsProviderTests: XCTestCase {
    func testHerfordNames() {
        XCTAssertEqual(NRWPortalsProvider.herfordNames("HF Gelbe Tonne, Blaue Tonne, Altkleider, 4 wöchentlich: Herford", place: "Herford"),
                       ["Gelbe Tonne", "Blaue Tonne", "Altkleider"])
        XCTAssertEqual(NRWPortalsProvider.herfordNames("HF Restabfall (Graue Tonne) 2 wöchentlich: Herford", place: "Herford"),
                       ["Restabfall (Graue Tonne) 2 wöchentlich"])
        XCTAssertEqual(NRWPortalsProvider.herfordNames("Vl-RM-4-w: Vlotho", place: "Vlotho"), ["Restmüll 4-wöchentlich"])
        XCTAssertEqual(NRWPortalsProvider.herfordNames("Vl-E-Schrott: Vlotho", place: "Vlotho"), ["Elektroschrott"])
        XCTAssertEqual(NRWPortalsProvider.herfordNames("Hi Restmüll_4_Wochen: Hiddenhausen", place: "Hiddenhausen"), ["Restmüll 4 Wochen"])
        XCTAssertEqual(NRWPortalsProvider.herfordNames("EN Grüne Tonne: Enger", place: "Enger"), ["Grüne Tonne (Verpackungen)"])
        XCTAssertEqual(NRWPortalsProvider.herfordNames("RH Restmüll 1.100 l, 2 Wö: Rödinghausen", place: "Rödinghausen"), ["Restmüll 1.100 l, 2 Wö"])
        // doppelt kodiertes UTF-8 aus Kirchlengern
        let kirchlengern = NRWPortalsProvider.herfordNames("_KI RestmÃŒll blauer Deckel (4-wÃ¶chentlich): Kirchlengern", place: "Kirchlengern")
        XCTAssertEqual(kirchlengern, ["Restmüll bl. Deckel (4-wöchentlich)"])
        XCTAssertEqual(WasteCategory.classify(kirchlengern[0]), .residual)
        XCTAssertEqual(WasteCategory.classify(NRWPortalsProvider.herfordNames("BÜ Rest 4 Wö (gelber Deckel): Bünde", place: "Bünde")[0]), .residual)
        XCTAssertEqual(WasteCategory.classify(NRWPortalsProvider.herfordNames("BÜ Leichtstoff: Bünde", place: "Bünde")[0]), .packaging)
    }

    func testStripAlarms() {
        let ics = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Restmüll/Bio\nDTSTART;VALUE=DATE:20260106\nBEGIN:VALARM\nSUMMARY:Dran denken\nEND:VALARM\nEND:VEVENT\nEND:VCALENDAR\n"
        XCTAssertEqual(ICS.parse(NRWPortalsProvider.stripAlarms(ics)).first?.summary, "Restmüll/Bio")
    }
}

/// Live-Abfragen je Betreiber (nur mit TONNE_LIVE=1).
extension LiveProviderTests {
    func testNRWAwista() async throws {
        try await checkTyped(NRWPortalsProvider(service: "awista"), typed: ["Merkurstr", "45"], prefer: ["Merkurstraße", "Merkurstraße 45"], minCount: 3)
    }

    func testNRWMags() async throws {
        try await checkTyped(NRWPortalsProvider(service: "mags"), typed: ["43"], prefer: ["Schlossacker", "2-wöchentlich"], minCount: 3)
    }

    func testNRWAwg() async throws {
        try await checkTyped(NRWPortalsProvider(service: "awg"), typed: ["Hauptstr"], prefer: ["Hauptstraße"], minCount: 3)
    }

    func testNRWRsag() async throws {
        try await check(NRWPortalsProvider(service: "rsag"), prefer: ["Königswinter", "Winzerstraße"], minCount: 3)
    }

    func testNRWGelsendienste() async throws {
        try await checkTyped(NRWPortalsProvider(service: "gelsendienste"), typed: ["10"], prefer: ["Bismarckstr."], minCount: 3)
    }

    func testNRWBest() async throws {
        try await checkTyped(NRWPortalsProvider(service: "best"), typed: ["10"], prefer: ["Hochstraße"], minCount: 3)
    }

    func testNRWEnni() async throws {
        try await check(NRWPortalsProvider(service: "enni"), prefer: ["Abteistraße"], minCount: 3)
    }

    /// Alle neun Kommunen im Kreis Herford (je eigener Host).
    func testNRWHerford() async throws {
        try XCTSkipUnless(live, "TONNE_LIVE nicht gesetzt")
        let places = NRWPortalsProvider.herfordPlaces.map(\.name)
        var failed: [String] = []
        for place in places {
            do { try await check(NRWPortalsProvider(service: "herford"), prefer: [place, "a"], minCount: 3) } catch { failed.append("\(place): \(error)") }
        }
        XCTAssertTrue(failed.isEmpty, failed.joined(separator: "\n"))
    }
}
