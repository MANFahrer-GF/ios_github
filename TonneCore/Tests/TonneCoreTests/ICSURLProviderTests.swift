import XCTest
@testable import TonneCore

/// ICS-Links aus dem Katalog: Direktlinks ohne „.ics“, Seiten mit wechselndem Kalenderlink, Sammeltermine.
final class ICSURLProviderTests: XCTestCase {
    func testDirectLinkDetection() {
        XCTAssertTrue(ICSURLProvider(url: "https://www.mzvhegau.de/wp-admin/admin-post.php?action=mzv_ics_download&whole_year=1&slug=Engen").isDirectLink)
        XCTAssertTrue(ICSURLProvider(url: "https://cms.steisslingen.de/tools/icsAbfalltermine/?datasource=steisslingen").isDirectLink)
        XCTAssertTrue(ICSURLProvider(url: "https://www.hille.de/Wirtschaft-Wohnen/Wohnen/Abfallkalender/#link=Bezirk 1 - Ohne Erinnerung").isDirectLink)
        XCTAssertTrue(ICSURLProvider(url: "webcal://example.org/kalender").isDirectLink)
        // Portalseite: hier holt man sich erst den persönlichen Link
        XCTAssertFalse(ICSURLProvider(url: "https://alsfeld.mein-abfallkalender.online").isDirectLink)
        XCTAssertTrue(ICSURLProvider(url: "https://alsfeld.mein-abfallkalender.online/ical.ics?id=1").isDirectLink)
    }

    func testPortalPageAsksForLink() async throws {
        let step = try await ICSURLProvider(url: "https://alsfeld.mein-abfallkalender.online").nextStep(after: [])
        XCTAssertEqual(step?.input, .text)
        let direct = try await ICSURLProvider(url: "https://cms.eigeltingen.de/tools/icsAbfalltermine/?datasource=eigeltingen").nextStep(after: [])
        XCTAssertNil(direct)
    }

    func testNames() {
        XCTAssertEqual(ICSURLProvider.names("Abholung: Biomüll"), ["Biomüll"])
        XCTAssertEqual(ICSURLProvider.names("Abfalltermin (Restmüll)"), ["Restmüll"])
        // Sammeltermine verschiedener Tonnen werden getrennt …
        XCTAssertEqual(ICSURLProvider.names("Abholung: Biomüll\\, Restmüll".replacingOccurrences(of: "\\,", with: ",")), ["Biomüll", "Restmüll"])
        XCTAssertEqual(ICSURLProvider.names("Abfalltermin (Restmüll / Gelbe Tonne)"), ["Restmüll", "Gelbe Tonne"])
        // … gleiche Tonne oder unbekannte Teile nicht
        XCTAssertEqual(ICSURLProvider.names("Abfalltermin (Papier / Pappe)"), ["Papier / Pappe"])
        XCTAssertEqual(ICSURLProvider.names("Gelber Sack / Gelbe Tonne"), ["Gelber Sack / Gelbe Tonne"])
        XCTAssertEqual(ICSURLProvider.names("Restmüll Großbehälter 1,1 m³"), ["Restmüll Großbehälter 1,1 m³"])
        XCTAssertEqual(ICSURLProvider.names("Sperrgut / Kühlgeräte"), ["Sperrgut / Kühlgeräte"])
        XCTAssertEqual(ICSURLProvider.names("  "), ["Abholung"])
        XCTAssertTrue(WasteCategory.isIgnorableTitle("Wertstoffhof geöffnet (WH) – W1"), "Öffnungstage sind keine Abholung")
    }

    /// Ausschnitte der echten Seiten (Oktober 2026).
    func testLinkOnPage() throws {
        let hille = """
        <li><a href="/media/custom/3015_1462_1.ICS?1733829588"><span></span></a></li>
        <li><a href="/media/custom/3015_1711_1.ICS?1765458323" class="csslink_ICS">Bezirk 1 - Ohne Erinnerung</a></li>
        <li><a href="/media/custom/3015_1710_1.ICS?1765458238" class="csslink_ICS">Bezirk 1 - Mit Erinnerung</a></li>
        <li><a href="/media/custom/3015_1712_1.ICS?1765458418" class="csslink_ICS">Bezirk 2 - Ohne Erinnerung</a></li>
        """
        let base = try XCTUnwrap(URL(string: "https://www.hille.de/Wirtschaft-Wohnen/Wohnen/Abfallkalender/"))
        XCTAssertEqual(ICSURLProvider.link(in: hille, base: base, matching: "Bezirk 2 - Ohne Erinnerung")?.absoluteString,
                       "https://www.hille.de/media/custom/3015_1712_1.ICS?1765458418")

        let wehrheim = """
        <a href="/bauen-umwelt/umwelt-abfallwirtschaft/abfallentsorgung/abfallkalender-obernhain-2026.pdf">Abfallkalender Obernhain (.pdf)</a>
        <a href="/bauen-umwelt/umwelt-abfallwirtschaft/abfallentsorgung/abfallkalender-wehrheim-2026-o-full-year.ics?cid=g46&amp;x=1"><span>Abfallkalender
          Obernhain</span> (.ics)</a>
        """
        let wbase = try XCTUnwrap(URL(string: "https://www.wehrheim.de/bauen-umwelt/umwelt-abfallwirtschaft/abfallentsorgung/"))
        XCTAssertEqual(ICSURLProvider.link(in: wehrheim, base: wbase, matching: "Abfallkalender Obernhain")?.absoluteString,
                       "https://www.wehrheim.de/bauen-umwelt/umwelt-abfallwirtschaft/abfallentsorgung/abfallkalender-wehrheim-2026-o-full-year.ics?cid=g46&x=1",
                       "nur ICS-Links zählen, die PDF davor nicht")

        let kriftel = #"<a href="/rathaus-politik/verwaltung/abfall/abfallkalender-2026-1-3.ics?cid=bvq">Teil 1</a><a href="/rathaus-politik/verwaltung/abfall/abfallkalender-2026-2.ics?cid=bvr">Teil 2</a>"#
        let kbase = try XCTUnwrap(URL(string: "https://www.kriftel.de/rathaus-politik/verwaltung/abfall/"))
        XCTAssertEqual(ICSURLProvider.link(in: kriftel, base: kbase, matching: "abfallkalender-2026-2.ics")?.absoluteString,
                       "https://www.kriftel.de/rathaus-politik/verwaltung/abfall/abfallkalender-2026-2.ics?cid=bvr")
        XCTAssertNil(ICSURLProvider.link(in: kriftel, base: kbase, matching: "abfallkalender-2027-2.ics"))
    }

    /// Jeder direkte ICS-Eintrag im Katalog liefert künftige Termine (meldet auch Links, die eine Gemeinde geändert hat).
    func testLiveAllDirectCatalogLinks() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let today = calendar.startOfDay(for: Date())
        var failures: [String] = []
        for entry in ProviderCatalog.entries where entry.kind == .icsURL {
            let provider = ICSURLProvider(url: entry.serviceKey)
            guard provider.isDirectLink else { continue }
            do {
                let pickups = try await provider.pickups(for: [], calendar: calendar)
                let future = pickups.filter { $0.date >= today }
                let known = Set(future.map { WasteCategory.classify($0.name) }).subtracting([.other])
                print("ICS \(entry.title): \(future.count) künftig, \(Set(future.map(\.name)).sorted())")
                if future.count < 3 || known.isEmpty { failures.append("\(entry.title): \(future.count) künftige Termine") }
            } catch {
                failures.append("\(entry.title): \(error.localizedDescription)")
            }
            try await Task.sleep(nanoseconds: 1_100_000_000)
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
