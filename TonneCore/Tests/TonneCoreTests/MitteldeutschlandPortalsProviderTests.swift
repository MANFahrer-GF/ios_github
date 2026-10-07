import XCTest
@testable import TonneCore

/// Offline-Tests der Hilfsfunktionen.
final class MitteldeutschlandPortalsProviderTests: XCTestCase {
    func testLatin1Form() {
        let body = String(decoding: MitteldeutschlandPortalsProvider.latin1Form([("Strasse", "Klosterlausnitzer Straße"), ("HSN", "5/1")]), as: UTF8.self)
        XCTAssertEqual(body, "Strasse=Klosterlausnitzer+Stra%DFe&HSN=5%2F1")
    }

    func testAJLParse() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let html = """
        <div id="calenderview"><h2 class="ajl-green uk-h3">Abholtermine 2026 f&uuml;r Burg </h2>
        <div class="cat"><div class="cat-bio"><h3 class="uk-h5">Biom&uuml;ll</h3>
        <div class="dayprint">Mi 14.01.</div><div class="dayprint">Di 27.01.</div></div></div>
        <div class="cat"><div class="cat-rest"><h3 class="uk-h5">Restm&uuml;ll</h3><div class="dayprint">Fr 30.12.</div></div></div>
        """
        let pickups = MitteldeutschlandPortalsProvider.ajlParse(html, fallbackYear: 2025, calendar: calendar)
        XCTAssertEqual(pickups.count, 3)
        XCTAssertEqual(pickups.first?.name, "Biomüll")
        XCTAssertEqual(pickups.first.map { Days.iso($0.date, calendar: calendar) }, "2026-01-14")
        XCTAssertEqual(WasteCategory.classify(pickups.last?.name ?? ""), .residual)
    }

    func testUnknownServiceAndLabel() async {
        let provider = MitteldeutschlandPortalsProvider(service: "gibtsnicht")
        do { _ = try await provider.nextStep(after: []); XCTFail() } catch {}
        let hws = MitteldeutschlandPortalsProvider(service: "hws")
        XCTAssertEqual(hws.label(for: [SelectionOption(id: "Am Kirchtor", title: "Am Kirchtor"), SelectionOption(id: "8", title: "8"), SelectionOption(id: "", title: "Privathaushalt")]), "Halle (Saale), Am Kirchtor 8")
        XCTAssertEqual(hws.displayName, "HWS Halle (Saale)")
    }
}

/// Live-Abfragen je Betreiber (nur mit TONNE_LIVE=1).
extension LiveProviderTests {
    private func mitte(_ key: String) -> MitteldeutschlandPortalsProvider { MitteldeutschlandPortalsProvider(service: key) }

    func testMitteHWSHalle() async throws { try await check(mitte("hws"), prefer: ["Landrain", "129A"], minCount: 3) }
    func testMitteJena() async throws { try await check(mitte("jena"), prefer: ["Altenburger Straße", "15-19"], minCount: 3) }
    func testMitteNordhausen() async throws { try await check(mitte("nordhausen"), prefer: ["Nordhausen", "Grimmelallee"], minCount: 3) }
    func testMitteNordhausenHouseNumber() async throws { try await check(mitte("nordhausen"), prefer: ["Nordhausen", "Kranichstraße", "7"], minCount: 3) }
    func testMitteUHK() async throws { try await check(mitte("uhk"), prefer: ["Mühlhausen Stadttour 3"], minCount: 3) }
    func testMitteAWVGera() async throws { try await check(mitte("awvot"), prefer: ["Gera", "Aga Birkenstraße", "9"], minCount: 3) }
    func testMitteAWVGreiz() async throws { try await check(mitte("awvot"), prefer: ["Kraftsdorf OT Oberndorf", "Klosterlausnitzer Straße", "5/1"], minCount: 3) }
    func testMitteKyffhaeuser() async throws { try await check(mitte("kyffhaeuser"), prefer: ["Sondershausen - Tour 3"], minCount: 3) }
    func testMitteKyffhaeuserRossleben() async throws { try await check(mitte("kyffhaeuser"), prefer: ["Roßleben (Bereich Innenstadt"], minCount: 3) }
    func testMitteSonneberg() async throws { try await check(mitte("sonneberg"), prefer: ["Sonneberg", "Innenstadtbereich", "Coburger Allee"], minCount: 3) }
    func testMitteSonnebergOhneStrasse() async throws { try await check(mitte("sonneberg"), prefer: ["Föritztal", "Schwärzdorf"], minCount: 3) }
    func testMitteAJL() async throws { try await check(mitte("ajl"), prefer: ["Burg", "Fliederweg"], minCount: 3) }
    func testMitteAJLOhneStrasse() async throws { try await check(mitte("ajl"), prefer: ["Biederitz"], minCount: 3) }
}
