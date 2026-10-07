import XCTest
@testable import TonneCore

/// Portale Brandenburg: offline nur Grundsätzliches, live je Betreiber eine echte Adresse.
final class BrandenburgPortalsProviderTests: XCTestCase {
    func testFactoryAndLabels() {
        let potsdam = ProviderFactory.make(kind: .portalsBrandenburg, serviceKey: "potsdam")
        XCTAssertEqual(potsdam.serviceKey, "potsdam")
        let selections = [
            SelectionOption(id: "Golm", title: "Golm"), SelectionOption(id: "Akazienweg", title: "Akazienweg"),
            SelectionOption(id: "4", title: "4-wöchentlich"), SelectionOption(id: "3", title: "14-tägig"), SelectionOption(id: "2", title: "wöchentlich"),
        ]
        XCTAssertEqual(potsdam.label(for: selections), "Potsdam, Golm, Akazienweg")
        let kwu = BrandenburgPortalsProvider(service: "kwu")
        XCTAssertEqual(kwu.label(for: [SelectionOption(id: "a", title: "Erkner"), SelectionOption(id: "b", title: "Heinrich-Heine-Straße"), SelectionOption(id: "c", title: "11")]),
                       "Erkner, Heinrich-Heine-Straße 11")
    }

    func testUnknownServiceThrows() async {
        do {
            _ = try await BrandenburgPortalsProvider(service: "gibtsnicht").nextStep(after: [])
            XCTFail("Fehler erwartet")
        } catch {}
    }

    func testKAEVTownListIsStatic() async throws {
        let step = try await BrandenburgPortalsProvider(service: "kaev").nextStep(after: [])
        XCTAssertEqual(step?.options.count, 35)
        XCTAssertTrue(step?.options.contains { $0.title == "Luckau" } ?? false)
    }
}

extension LiveProviderTests {
    func testBrandenburgPotsdam() async throws {
        // Golm, Akazienweg: Restabfall 4-wöchentlich, Bio 14-tägig, Papier wöchentlich
        try await check(BrandenburgPortalsProvider(service: "potsdam"), prefer: ["Golm", "Akazienweg", "4-wöchentlich", "14-tägig", "wöchentlich"], minCount: 3)
    }

    func testBrandenburgKWU() async throws {
        try await check(BrandenburgPortalsProvider(service: "kwu"), prefer: ["Erkner", "Heinrich-Heine-Straße", "11"], minCount: 3)
    }

    func testBrandenburgSpreeNeisse() async throws {
        try await check(BrandenburgPortalsProvider(service: "spn"), prefer: ["Forst (Lausitz)", "Rosenweg"], minCount: 3)
    }

    func testBrandenburgKAEV() async throws {
        try await check(BrandenburgPortalsProvider(service: "kaev"), prefer: ["Lübben (Spreewald)", "Adlerweg"], minCount: 3)
    }

    func testBrandenburgFrankfurtOder() async throws {
        try await check(BrandenburgPortalsProvider(service: "ffo"), prefer: ["Stadtgebiet", "Karl-Marx-Str", ""], minCount: 3)
    }
}
