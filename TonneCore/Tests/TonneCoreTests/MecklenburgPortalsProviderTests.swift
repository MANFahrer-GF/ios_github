import XCTest
@testable import TonneCore

/// Offline-Prüfungen für die MV-Portale.
final class MecklenburgPortalsProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    func testFactoryAndNames() {
        let provider = ProviderFactory.make(kind: .portalsMV, serviceKey: "nwm")
        XCTAssertEqual(provider.kind, .portalsMV)
        XCTAssertEqual(provider.displayName, "Landkreis Nordwestmecklenburg")
        XCTAssertEqual(MecklenburgPortalsProvider(service: "vevg").displayName, "VEVG Vorpommern-Greifswald")
    }

    func testLabels() {
        let rostock = MecklenburgPortalsProvider(service: "rostock")
        let selections = [SelectionOption(id: "Bahnhofs", title: "Bahnhofs"), SelectionOption(id: "Bahnhofstr.|18055", title: "Bahnhofstr."), SelectionOption(id: "1", title: "1")]
        XCTAssertEqual(rostock.label(for: selections), "Rostock, Bahnhofstr. 1")
        // Rhythmus-Schritte gehören nicht ins Label.
        let lro = MecklenburgPortalsProvider(service: "lro")
        XCTAssertEqual(lro.label(for: [SelectionOption(id: "B_B_O_A", title: "Alt Kätwin"), SelectionOption(id: "rhythm:2w", title: "Alle 2 Wochen")]), "Alt Kätwin")
    }

    func testUnknownServiceThrows() async {
        do {
            _ = try await MecklenburgPortalsProvider(service: "gibtsnicht").nextStep(after: [])
            XCTFail("Fehler erwartet")
        } catch {}
    }
}

/// Live-Abfragen (nur mit TONNE_LIVE=1).
extension LiveProviderTests {
    func testMVLandkreisRostock() async throws {
        try await check(MecklenburgPortalsProvider(service: "lro"), prefer: ["Alt Kätwin", "Alle 2 Wochen", "Alle 4 Wochen"], minCount: 3)
    }

    func testMVLandkreisRostockGuestrow() async throws {
        try await check(MecklenburgPortalsProvider(service: "lro"), prefer: ["Güstrow", "Werlestraße", "Alle 2 Wochen", "Alle 2 Wochen"], minCount: 3)
    }

    func testMVStadtRostock() async throws {
        try await checkTyped(MecklenburgPortalsProvider(service: "rostock"), typed: ["Bahnhofstr", "1"], prefer: ["Bahnhofstr."], minCount: 3)
    }

    func testMVNordwestmecklenburg() async throws {
        try await check(MecklenburgPortalsProvider(service: "nwm"), prefer: ["Gadebusch"], minCount: 3)
    }

    func testMVVEVGOrt() async throws {
        try await check(MecklenburgPortalsProvider(service: "vevg"), prefer: ["Wusterhusen"], minCount: 3)
    }

    func testMVVEVGAnklamStrasse() async throws {
        try await check(MecklenburgPortalsProvider(service: "vevg"), prefer: ["Anklam", "Adolf-Damaschke", "14-täglich"], minCount: 3)
    }

    func testMVVEVGGreifswald() async throws {
        try await check(MecklenburgPortalsProvider(service: "vevg"), prefer: ["Greifswald", "Anklamer Straße", "Anklamer Straße 1 "], minCount: 3)
    }

    /// Schwerin (SDS) über Gemos WasteBox mit Kategorie im ICS-Link.
    func testMVSchwerin() async throws {
        try await check(MecklenburgPortalsProvider(service: "schwerin"), prefer: ["Mozartstraße", "1", "14-täglich"], minCount: 3)
        try await check(MecklenburgPortalsProvider(service: "schwerin"), prefer: ["Am Wald", "1"], minCount: 3)
    }
}
