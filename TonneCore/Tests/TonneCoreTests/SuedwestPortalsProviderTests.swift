import XCTest
@testable import TonneCore

/// Offline: Heidelberger Rhythmus-Rechnung und Stuttgarter Tabellen-Parser.
final class SuedwestPortalsParsingTests: XCTestCase {
    func testHeidelbergWeekParity() {
        // 2026: Mi 07.01. = KW 2 (gerade), Mi 14.01. = KW 3 (ungerade)
        let even = SuedwestPortalsProvider.heidelbergDates(weekday: "Mi", rhythm: "G", from: "2026-01-01", to: "2026-01-31")
        let odd = SuedwestPortalsProvider.heidelbergDates(weekday: "Mi", rhythm: "U", from: "2026-01-01", to: "2026-01-31")
        let all = SuedwestPortalsProvider.heidelbergDates(weekday: "Mi", rhythm: "A", from: "2026-01-01", to: "2026-01-31")
        XCTAssertEqual(even, ["2026-01-07", "2026-01-21"])
        XCTAssertEqual(odd, ["2026-01-14", "2026-01-28"])
        XCTAssertEqual(all.count, 4)
        XCTAssertTrue(SuedwestPortalsProvider.heidelbergDates(weekday: "xx", rhythm: "A", from: "2026-01-01", to: "2026-01-31").isEmpty)
    }

    func testStuttgartTable() {
        let html = """
        <table id="awstable" class="table"><tbody>
        <tr class="thead-light"><th colspan="3"><span class="text-dark">Restabfall</span></th></tr>
        <tr><td>Montag</td><td>12.10.2026</td><td>01-wöchentl.</td></tr>
        <tr><td>Montag</td><td>19.10.2026</td><td>02-wöchentl.</td></tr>
        <tr class="thead-light"><th colspan="3"><span class="text-dark">Gelber Sack</span></th></tr>
        <tr><td>Dienstag</td><td>13.10.2026</td><td>03-wöchentl.</td></tr>
        </tbody></table>
        """
        L10n.forcedLanguage = "de"
        let pickups = SuedwestPortalsProvider.parseStuttgart(html, calendar: .current)
        XCTAssertEqual(Set(pickups.map(\.name)), ["Restabfall (wöchentlich)", "Restabfall (2-wöchentlich)", "Gelber Sack"])
        XCTAssertEqual(pickups.count, 3)
    }

    func testUnknownService() async {
        do {
            _ = try await SuedwestPortalsProvider(service: "gibtsnicht").nextStep(after: [])
            XCTFail("Fehler erwartet")
        } catch {}
    }
}

/// Live gegen die Portale – nur mit TONNE_LIVE=1.
extension LiveProviderTests {
    func testSuedwestFrankfurt() async throws {
        try await checkTyped(SuedwestPortalsProvider(service: "frankfurt"), typed: ["Zeil"], prefer: ["Zeil", "10"])
    }

    func testSuedwestStuttgart() async throws {
        try await checkTyped(SuedwestPortalsProvider(service: "stuttgart"), typed: ["Im Steinengarten", "7"], prefer: ["Im Steinengarten"])
    }

    func testSuedwestWiesbaden() async throws {
        try await checkTyped(SuedwestPortalsProvider(service: "wiesbaden"), typed: ["Wilhelm-Dietz"], prefer: ["Wilhelm-Dietz-Straße", "5"])
    }

    func testSuedwestHeidelberg() async throws {
        try await check(SuedwestPortalsProvider(service: "heidelberg"), prefer: ["Alte Bergheimer Straße", "14-täglich (gerade"])
    }

    func testSuedwestHeidenheim() async throws {
        try await checkTyped(SuedwestPortalsProvider(service: "heidenheim"), typed: ["Hauptstr"], prefer: ["Heidenheim", "Heidenheim", "Hauptstraße"], minCount: 3)
        try await check(SuedwestPortalsProvider(service: "heidenheim"), prefer: ["Dischingen", "Hofen"], minCount: 3)
    }

    func testSuedwestBadenBaden() async throws {
        try await check(SuedwestPortalsProvider(service: "badenbaden"), prefer: ["Neuweier"], minCount: 3)
        try await check(SuedwestPortalsProvider(service: "badenbaden"), prefer: ["Baden-Baden", "Adlerstraße"], minCount: 3)
    }

    func testSuedwestKreisKassel() async throws {
        try await check(SuedwestPortalsProvider(service: "kreiskassel"), prefer: ["Fuldatal", "Ihringshausen"], minCount: 3)
        try await check(SuedwestPortalsProvider(service: "kreiskassel"), prefer: ["Nieste"], minCount: 3)
    }

    func testSuedwestRESO() async throws {
        try await check(SuedwestPortalsProvider(service: "reso"), prefer: ["Michelstadt", "Kernstadt"])
    }
}
