import XCTest
@testable import TonneCore

/// Echte Abfragen gegen die Portale – nur mit TONNE_LIVE=1, damit normale Tests offline laufen.
final class LiveProviderTests: XCTestCase {
    var live: Bool { ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" }

    /// Läuft den Assistenten automatisch durch: nimmt jeweils die Option, die `prefer` am besten trifft.
    func walk(_ provider: WasteProvider, prefer: [String]) async throws -> [SelectionOption] {
        var selections: [SelectionOption] = []
        var index = 0
        while let step = try await provider.nextStep(after: selections) {
            guard !step.options.isEmpty else { XCTFail("\(provider.kind) \(step.title): keine Optionen"); break }
            let wanted = (index < prefer.count ? prefer[index] : "").lowercased()
            let pick = step.options.first { $0.title.lowercased() == wanted }
                ?? step.options.first { $0.title.lowercased().contains(wanted) }
                ?? step.options[0]
            selections.append(pick)
            index += 1
            if index > 6 { XCTFail("Zu viele Schritte"); break }
        }
        return selections
    }

    func check(_ provider: WasteProvider, prefer: [String], minCount: Int = 10) async throws {
        try XCTSkipUnless(live, "TONNE_LIVE nicht gesetzt")
        let selections = try await walk(provider, prefer: prefer)
        let pickups = try await provider.pickups(for: selections)
        let names = Set(pickups.map(\.name))
        print("\(provider.kind.rawValue)/\(provider.serviceKey): \(provider.label(for: selections)) → \(pickups.count) Termine, \(names.sorted())")
        XCTAssertGreaterThanOrEqual(pickups.count, minCount)
        XCTAssertTrue(names.contains { WasteCategory.classify($0) != .other })
    }

    func testAwidoGifhorn() async throws { try await check(AwidoProvider(customer: "gifhorn"), prefer: ["Gifhorn", "Steinstraße"]) }
    func testAbfallIOGraphQL() async throws { try await check(AbfallIOGraphQLProvider(key: "efb75cbd1f08fae1d4e47ae72a85c655"), prefer: ["Altlandsberg", "Altlandsberg", "Ahornweg", ""]) }
    func testAbfallIOLegacy() async throws { try await check(AbfallIOLegacyProvider(key: "e21758b9c711463552fb9c70ac7d4273"), prefer: ["Emsdetten", "Ackerstraße", ""]) }
    func testJumomindZAW() async throws { try await check(JumomindProvider(service: "zaw"), prefer: ["Alsbach", "Hähnleiner"]) }
    func testJumomindMyMuell() async throws { try await check(JumomindProvider(service: "mymuell"), prefer: ["Darmstadt", "Achatweg"]) }
    func testAbfallnaviAachen() async throws { try await check(AbfallnaviProvider(service: "aachen"), prefer: ["Aachen", "Abteiplatz", "7"]) }
    func testAbfallAppNetStendal() async throws { try await check(AbfallAppNetProvider(tenant: "landkreis-stendal"), prefer: ["Kuhlhausen"]) }
    func testAbfallAppNetStendalStreet() async throws { try await check(AbfallAppNetProvider(tenant: "landkreis-stendal"), prefer: ["Stendal", "Stendal", "Ahornweg"]) }
    func testICSURL() async throws {
        try await check(ICSURLProvider(url: "https://landkreis-stendal.abfall-app.net/download?system=ical&period=2&district=1465&categories=&view=month"), prefer: [])
    }
}
