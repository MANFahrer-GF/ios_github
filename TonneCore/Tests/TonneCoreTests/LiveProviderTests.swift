import XCTest
@testable import TonneCore

/// Echte Abfragen gegen die Portale – nur mit TONNE_LIVE=1, damit normale Tests offline laufen.
final class LiveProviderTests: XCTestCase {
    var live: Bool { ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" }

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

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

extension LiveProviderTests {
    /// Assistent mit Texteingaben: `typed` liefert für Text-Schritte die Eingabe.
    func walkTyped(_ provider: WasteProvider, typed: [String], prefer: [String]) async throws -> [SelectionOption] {
        var selections: [SelectionOption] = []
        var typedIndex = 0, listIndex = 0
        while let step = try await provider.nextStep(after: selections) {
            if step.input == .text {
                let value = typedIndex < typed.count ? typed[typedIndex] : ""
                typedIndex += 1
                selections.append(SelectionOption(id: value, title: value))
            } else {
                guard !step.options.isEmpty else { XCTFail("\(provider.kind) \(step.title): keine Optionen"); break }
                let wanted = (listIndex < prefer.count ? prefer[listIndex] : "").lowercased()
                listIndex += 1
                let pick = step.options.first { $0.title.lowercased() == wanted } ?? step.options.first { $0.title.lowercased().contains(wanted) } ?? step.options[0]
                selections.append(pick)
            }
            if selections.count > 8 { XCTFail("Zu viele Schritte"); break }
        }
        return selections
    }

    func checkTyped(_ provider: WasteProvider, typed: [String], prefer: [String], minCount: Int = 10) async throws {
        try XCTSkipUnless(live, "TONNE_LIVE nicht gesetzt")
        let selections = try await walkTyped(provider, typed: typed, prefer: prefer)
        let pickups = try await provider.pickups(for: selections)
        print("\(provider.kind.rawValue)/\(provider.serviceKey): \(provider.label(for: selections)) → \(pickups.count) Termine, \(Set(pickups.map(\.name)).sorted())")
        XCTAssertGreaterThanOrEqual(pickups.count, minCount)
    }

    func testCTraceBremen() async throws { try await checkTyped(CTraceProvider(service: "bremenabfallkalender"), typed: ["Abbentorstraße", "5"], prefer: []) }
    func testCTraceAugsburg() async throws { try await checkTyped(CTraceProvider(service: "augsburglandkreis"), typed: ["Königsbrunn", "Marktplatz", "7"], prefer: []) }
    func testKoeln() async throws { try await checkTyped(AWBKoelnProvider(), typed: ["Aachener Str.", "50"], prefer: ["Aachener Str. 50"]) }
    func testLeipzig() async throws { try await checkTyped(LeipzigProvider(), typed: ["Bahnhofsallee"], prefer: ["Bahnhofsallee", "7"]) }
    func testHannover() async throws { try await checkTyped(AhaHannoverProvider(), typed: ["Voltastr", "25"], prefer: ["Hannover", "Voltastr. / Vahrenwald"]) }
    func testMuellmaxMuenster() async throws { try await checkTyped(MuellmaxProvider(service: "Awm"), typed: ["Achatiusweg"], prefer: ["Achatiusweg"]) }
}


extension LiveProviderTests {
    func testAbfallPlusAppAlbaBraunschweig() async throws {
        try await checkTyped(AbfallPlusAppProvider(appID: "de.albagroup.app"), typed: ["Hauptstr"], prefer: ["Braunschweig", "Hauptstraße", "7A"], minCount: 3)
    }

    func testAbfallPlusAppLueneburg() async throws {
        try await checkTyped(AbfallPlusAppProvider(appID: "de.abfallplus.gfaabfallinfo"), typed: ["Am Sande"], prefer: ["Lüneburg", "Am Sande", "1"], minCount: 5)
    }

    func testBSRBerlinMitte() async throws {
        try await checkTyped(BSRProvider(), typed: ["Alexanderstr", "5"], prefer: ["Alexanderstr.", "Alexanderstr. 5"], minCount: 10)
    }

    func testGemosNostorf() async throws {
        try await check(GemosWasteBoxProvider(customer: "lwl"), prefer: ["Nostorf (19258)"], minCount: 5)
    }

    func testAWSHLauenburg() async throws {
        try await check(AWSHProvider(), prefer: ["Lauenburg", "", "Restabfall 40L-240L · 2-wöchentlich", "", ""], minCount: 5)
    }

    func testLobbeIserlohn() async throws {
        try await check(LobbeProvider(), prefer: ["Nordrhein-Westfalen", "Iserlohn", ""], minCount: 5)
    }

    func testNerdbridgeEinbeck() async throws {
        try await check(NerdbridgeProvider(), prefer: ["Einbeck (Bezirk 2)"], minCount: 5)
    }
}

/// Prüft für jeden Katalogeintrag, ob der erste Auswahlschritt Daten liefert.
/// Läuft nur mit `TONNE_SWEEP=1`, weil es einige Minuten dauert.
final class CatalogSweepTests: XCTestCase {
    func testEveryCatalogEntryAnswers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_SWEEP"] != nil, "TONNE_SWEEP nicht gesetzt")
        let filter = ProcessInfo.processInfo.environment["TONNE_SWEEP_KINDS"].map { Set($0.split(separator: ",").map(String.init)) }
        let entries = ProviderCatalog.entries.filter { filter == nil || filter!.contains($0.kind.rawValue) }
        var failures: [String] = []
        try await withThrowingTaskGroup(of: String?.self) { group in
            var iterator = entries.makeIterator()
            func addNext() {
                guard let entry = iterator.next() else { return }
                group.addTask {
                    let provider = ProviderFactory.make(kind: entry.kind, serviceKey: entry.serviceKey)
                    do {
                        guard let step = try await provider.nextStep(after: []) else {
                            return entry.kind == .icsURL ? nil : "\(entry.kind.rawValue) | \(entry.title) | kein erster Schritt"
                        }
                        if step.input == .list && step.options.isEmpty { return "\(entry.kind.rawValue) | \(entry.title) | leere Liste" }
                        return nil
                    } catch {
                        return "\(entry.kind.rawValue) | \(entry.title) | \(error.localizedDescription)"
                    }
                }
            }
            let parallel = Int(ProcessInfo.processInfo.environment["TONNE_SWEEP_PARALLEL"] ?? "") ?? 12
            for _ in 0..<parallel { addNext() }
            while let result = try await group.next() {
                if let result { failures.append(result) }
                addNext()
            }
        }
        print("SWEEP: \(entries.count) Einträge, \(failures.count) Fehler")
        for failure in failures.sorted() { print("SWEEP-FEHLER: \(failure)") }
        XCTAssertTrue(failures.isEmpty)
    }
}
