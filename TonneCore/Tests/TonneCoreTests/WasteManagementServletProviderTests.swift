import XCTest
@testable import TonneCore

/// Offline: Namensbereinigung und Kennungstabelle.
final class WasteManagementServletProviderTests: XCTestCase {
    func testCleanName() {
        XCTAssertEqual(WasteManagementServletProvider.cleanName("Restmuell 7-taeglich"), "Restmüll 7-täglich")
        XCTAssertEqual(WasteManagementServletProvider.cleanName("Grossmuellbehaelter 1100 L "), "Restmüll-Großbehälter 1100 L")
        XCTAssertEqual(WasteManagementServletProvider.cleanName("Bioabfallbehaelter , letzte Leerung Saison-Biotonne"), "Bioabfallbehälter, letzte Leerung Saison-Biotonne")
        XCTAssertNil(WasteManagementServletProvider.cleanName("Die neue ICal-Kalenderdatei steht zur Verfuegung."))
        XCTAssertEqual(WasteCategory.classify(WasteManagementServletProvider.cleanName("Grossmuellbehaelter 1100 L")!), .residual)
        XCTAssertEqual(WasteCategory.classify(WasteManagementServletProvider.cleanName("Papierbehaelter")!), .paper)
    }

    func testPortalTable() {
        for key in ["pforzheim", "zweibruecken", "bielefeld", "bamberg", "hameln", "alzeyworms", "suedwestsachsen", "vogtland", "suedbrandenburg", "pfaffenhofen"] {
            let provider = ProviderFactory.make(kind: .wasteManagementServlet, serviceKey: key)
            XCTAssertNotNil(WasteManagementServletProvider.portals[key], key)
            XCTAssertNotEqual(provider.displayName, "WasteManagement-Portal", key)
        }
        let pforzheim = WasteManagementServletProvider(service: "pforzheim")
        XCTAssertEqual(pforzheim.label(for: [SelectionOption(id: "A", title: "A"), SelectionOption(id: "Abnobastraße", title: "Abnobastraße"), SelectionOption(id: "3", title: "3")]), "Pforzheim, Abnobastraße 3")
        let vogtland = WasteManagementServletProvider(service: "vogtland")
        XCTAssertEqual(vogtland.label(for: [SelectionOption(id: "Plauen", title: "Plauen"), SelectionOption(id: "Am\u{00A0}Bahnhof", title: "Am Bahnhof"), SelectionOption(id: "1", title: "1")]), "Plauen, Am Bahnhof 1")
    }
}

/// Live je Betreiber (TONNE_LIVE=1).
extension LiveProviderTests {
    private func servlet(_ key: String) -> WasteManagementServletProvider { WasteManagementServletProvider(service: key) }

    /// Bamberg und SBAZV sind aus manchen Netzen nicht erreichbar (Verbindung wird zurückgesetzt) – dann überspringen.
    private func checkReachable(_ key: String, prefer: [String], typed: [String] = [], minCount: Int = 3) async throws {
        do {
            if typed.isEmpty {
                try await check(servlet(key), prefer: prefer, minCount: minCount)
            } else {
                try await checkTyped(servlet(key), typed: typed, prefer: prefer, minCount: minCount)
            }
        } catch HTTPError.transport(let message) {
            throw XCTSkip("\(key) nicht erreichbar: \(message)")
        }
    }

    func testServletPforzheim() async throws { try await checkTyped(servlet("pforzheim"), typed: ["3"], prefer: ["A", "Abnobastraße"], minCount: 3) }
    func testServletZweibruecken() async throws { try await check(servlet("zweibruecken"), prefer: ["V", "Vogesenstraße", "75"], minCount: 3) }
    func testServletBielefeld() async throws { try await checkTyped(servlet("bielefeld"), typed: ["57"], prefer: ["E", "Eckendorfer Straße"], minCount: 3) }
    func testServletBamberg() async throws { try await checkReachable("bamberg", prefer: ["G", "Gartenstraße"], typed: ["2"]) }
    func testServletHameln() async throws { try await check(servlet("hameln"), prefer: ["Hameln", "Deisterstr.", "10"], minCount: 3) }
    func testServletAlzeyWorms() async throws { try await check(servlet("alzeyworms"), prefer: ["Alzey", "Am Dorfbrunnen", "3"], minCount: 3) }
    func testServletSuedwestsachsen() async throws { try await check(servlet("suedwestsachsen"), prefer: ["Annaberg-Buchholz", "Adam-Ries-Straße", "1"], minCount: 3) }
    func testServletVogtland() async throws { try await check(servlet("vogtland"), prefer: ["Plauen", "Albert-Schweitzer-Straße", "1"], minCount: 10) }
    func testServletSuedbrandenburg() async throws { try await checkReachable("suedbrandenburg", prefer: ["Rangsdorf", "", ""]) }
    func testServletPfaffenhofen() async throws { try await checkTyped(servlet("pfaffenhofen"), typed: ["3"], prefer: ["Geisenfeld", "Altmühlstr."], minCount: 3) }

    /// Unbekannte Hausnummer: Hinweis des Portals statt leerer Liste.
    func testServletPfaffenhofenWrongNumber() async throws {
        try XCTSkipUnless(live, "TONNE_LIVE nicht gesetzt")
        let selections = [SelectionOption(id: "Geisenfeld", title: "Geisenfeld"), SelectionOption(id: "Altmühlstr.", title: "Altmühlstr."), SelectionOption(id: "999", title: "999")]
        do {
            _ = try await servlet("pfaffenhofen").pickups(for: selections)
            XCTFail("Fehler erwartet")
        } catch ProviderError.invalidSelection(let message) {
            print("Pfaffenhofen 999: \(message)")
            XCTAssertTrue(message.contains("Hausnummer"))
        }
    }
}
