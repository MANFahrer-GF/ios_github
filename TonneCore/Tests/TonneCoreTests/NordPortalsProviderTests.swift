import XCTest
@testable import TonneCore

/// Offline-Tests der Hilfsfunktionen und Live-Tests je Betreiber (nur mit TONNE_LIVE=1).
final class NordPortalsProviderTests: XCTestCase {
    func testSplitCombined() {
        XCTAssertEqual(NordPortalsProvider.splitCombined("Restmüll- und Altpapiertonne"), ["Restmülltonne", "Altpapiertonne"])
        XCTAssertEqual(NordPortalsProvider.splitCombined("Gelbe Tonne und Biotonne"), ["Gelbe Tonne", "Biotonne"])
        XCTAssertEqual(NordPortalsProvider.splitCombined("Altpapier und Altglas"), ["Altpapier", "Altglas"])
        XCTAssertEqual(NordPortalsProvider.splitCombined("Restabfall"), ["Restabfall"])
    }

    func testAreaSplit() {
        XCTAssertEqual(NordPortalsProvider.areaSplit("Altpapier 2").type, "Altpapier")
        XCTAssertEqual(NordPortalsProvider.areaSplit("Gelber Sack 1").area, "1")
        XCTAssertNil(NordPortalsProvider.areaSplit("Schadstoffmobil").area)
    }

    func testGermanDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = NordPortalsProvider.germanDate("in 4 Tagen, Mo. 12.10.2026", calendar: calendar)
        XCTAssertEqual(date, Days.parse("2026-10-12", calendar: calendar))
    }

    func testUnknownOperator() async {
        do {
            _ = try await NordPortalsProvider(service: "gibtsnicht").nextStep(after: [])
            XCTFail("Fehler erwartet")
        } catch {}
    }

    func testLabels() {
        let hh = NordPortalsProvider(service: "hamburg")
        let s = [SelectionOption(id: "Zabel", title: "Zabel"), SelectionOption(id: "2586", title: "Zabelweg"), SelectionOption(id: "53814", title: "1B")]
        XCTAssertEqual(hh.label(for: s), "Hamburg, Zabelweg 1B")
        let beg = NordPortalsProvider(service: "bremerhaven")
        let b = [SelectionOption(id: "Hafen", title: "Hafen"), SelectionOption(id: "Hafenstraße, Bremerhaven", title: "Hafenstraße, Bremerhaven"), SelectionOption(id: "2", title: "2")]
        XCTAssertEqual(beg.label(for: b), "Bremerhaven, Hafenstraße 2")
        let ammer = NordPortalsProvider(service: "ammerland")
        XCTAssertEqual(ammer.label(for: [SelectionOption(id: "3", title: "Edewecht"), SelectionOption(id: "9", title: "Schepser Damm"), SelectionOption(id: "vier:0", title: "14-täglich")]),
                       "Edewecht, Schepser Damm")
    }
}

extension LiveProviderTests {
    private func nord(_ key: String) -> NordPortalsProvider { NordPortalsProvider(service: key) }

    func testNordHamburg() async throws { try await checkTyped(nord("hamburg"), typed: ["Zabelweg"], prefer: ["Zabelweg", "1B"]) }
    func testNordBremerhaven() async throws { try await checkTyped(nord("bremerhaven"), typed: ["Hafenstr", "2"], prefer: ["Hafenstraße, Bremerhaven"], minCount: 3) }
    func testNordKiel() async throws { try await checkTyped(nord("kiel"), typed: ["Auguste-Viktoria"], prefer: ["Auguste-Viktoria-Straße", "14"]) }
    func testNordZVO() async throws { try await check(nord("zvo"), prefer: ["Bad Schwartau", "Lindenstraße"]) }
    func testNordZVOOhneStrasse() async throws { try await check(nord("zvo"), prefer: ["Curau"]) }
    func testNordWolfsburg() async throws { try await check(nord("wolfsburg"), prefer: ["Bahnhofspassage", "1"]) }
    func testNordAwigo() async throws { try await check(nord("awigo"), prefer: ["Bippen", "Am Bad", "4"], minCount: 3) }
    func testNordOsnabrueck() async throws { try await check(nord("osnabrueck"), prefer: ["Albertstraße"], minCount: 3) }
    func testNordHarburg() async throws { try await check(nord("harburg"), prefer: ["Hanstedt", "Evendorf", "Hausmüll 14-täglich"]) }
    func testNordHarburgDreiEbenen() async throws {
        try await check(nord("harburg"), prefer: ["Buchholz", "Buchholz mit Steinbeck (ohne Reindorf)", "Seppenser Mühlenweg Haus-Nr. 1 / 2"])
    }
    func testNordAmmerland() async throws { try await check(nord("ammerland"), prefer: ["Edewecht", "Schepser Damm", "14-täglich"]) }
    func testNordHelmstedt() async throws { try await check(nord("helmstedt"), prefer: ["Lehre", "Gebiet 1", "Gebiet 2"]) }
    func testNordHildesheim() async throws { try await check(nord("hildesheim"), prefer: ["Hildesheim", "Achtum", "Achtumer Feld", "4-wöchentlich"], minCount: 3) }
    func testNordEmden() async throws { try await check(nord("emden"), prefer: ["Larrelt"], minCount: 3) }
    func testNordDelmenhorst() async throws { try await check(nord("delmenhorst"), prefer: ["Abfuhrbezirk 1", "Altpapiertour A"]) }
}
