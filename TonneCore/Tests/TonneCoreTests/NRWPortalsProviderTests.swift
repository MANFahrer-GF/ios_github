import XCTest
@testable import TonneCore

/// Offline: Namensaufbereitung der Kreis-Herford-Portale.
final class NRWPortalsProviderTests: XCTestCase {
    // Echte Ausschnitte der Seiten des Stadtbetriebs Frechen (10.11.2026), gekürzt.
    static let frechenOverview = #"""
    <div class="row" id="_a"> <div class="col-md-3"> <ul> <li>
      <a href="/service/abfallkalender/aachener-strasse-1/2026-11"><em>A</em>achener Straße </a> </li> <li>
      <a href="/service/abfallkalender/ahrendgaesschen-8/2026-11">Ahrendg&auml;&szlig;chen </a> </li></ul></div></div>
    <a href="/service/abfallkalender">Abfallkalender</a>
    """#
    static let frechenYear = #"""
    <td class="calendar--day " rel="2026-01-13"> <div class="calendar--day-content"> <div class="calendar--day-number">13</div>
      <div class="calendar--disposaltype disposal--gs" data-toggle="tooltip" data-id="7221" title="Grünschnittabfuhr / Bündel">
        <span class="disposaltype--code"> GS </span> <span class="disposaltype--addon addon--wa"> &#127876; </span> </div> </div> </td>
    <td class="calendar--day " rel="2026-03-10"> <div class="calendar--day-content"> <div class="calendar--day-number">10</div>
      <div class="calendar--disposaltype disposal--gs" data-toggle="tooltip" data-id="7300" title="Grünschnittabfuhr / Bündel"> <span class="disposaltype--code"> GS </span> </div> </div> </td>
    <td class="calendar--day " rel="2026-11-09"> <div class="calendar--day-content"> <div class="calendar--day-number">9</div>
      <div class="calendar--disposaltype disposal--rm" data-toggle="tooltip" data-id="8075" title="Restmüll"> <span class="disposaltype--code"> RM </span> </div>
      <div class="calendar--disposaltype disposal--gt" data-toggle="tooltip" data-id="8077" title="Gelbe Tonne / gelber Sack"> <span class="disposaltype--code"> GT </span> <span class="disposaltype--modifier"> b </span> </div>
      <div class="calendar--disposaltype disposal--gr" data-toggle="tooltip" data-id="8078" title="Großcontainer Restmüll"> <span class="disposaltype--code"> GR </span> <span class="disposaltype--addon addon--gr_14t"> ■ </span> </div> </div> </td>
    <td class="calendar--day calendar--day-today" rel="2026-11-10"> <div class="calendar--day-content"> <div class="calendar--day-number">10</div>
      <div class="calendar--disposaltype disposal--bt" data-toggle="tooltip" data-id="8079" title="Biotonne / Biosäcke"> <span class="disposaltype--code"> BT </span> </div> </div> </td>
    <td class="calendar--day " rel="2026-11-23"> <div class="calendar--day-content"> <div class="calendar--day-number">23</div>
      <div class="calendar--disposaltype disposal--rm" data-toggle="tooltip" data-id="8115" title="Restmüll"> <span class="disposaltype--code"> RM </span> <span class="disposaltype--addon addon--rm_4w"> ● </span> </div> </div> </td>
    <td class="calendar--holiday bg-gray" rel="2026-12-25">25 <span class="holiday-name">1. Weihnachtstag</span></td>
    <td class="calendar--day " rel="2026-12-27"> <div class="calendar--day-content"> <div class="calendar--day-number">27</div> </div> </td>
    <span class="disposaltype--addon addon--rm_4w"> ● </span> <span class="calendar--disposaltype-addon-desc addon--rm_4w"> Abholtag für Restmülltonne </span>
    """#

    /// „Geht mein Ort?“: Frechen ist abgedeckt, die Nachbarstadt im selben Kreis bekommt den Eintrag nicht.
    func testFrechenIsCoveredOnlyInFrechen() throws {
        let frechen = try XCTUnwrap(ProviderCatalog.checkPlace("Frechen").first)
        XCTAssertEqual(frechen.district, "Kreis Rhein-Erft-Kreis")
        let entry = try XCTUnwrap(frechen.entries.first { $0.serviceKey == "frechen" })
        // Der Hinweis zur Leerung erscheint beim Standort, Frechen zählt aber nicht als eingeschränkt
        XCTAssertNil(ProviderCatalog.restriction(for: entry))
        XCTAssertNotNil(NRWPortalsProvider(service: "frechen").notice)
        let huerth = try XCTUnwrap(ProviderCatalog.checkPlace("Hürth").first)
        XCTAssertFalse((huerth.entries + huerth.otherEntries).contains { $0.serviceKey == "frechen" })
    }

    func testFrechenStreets() {
        let streets = NRWPortalsProvider.frechenStreets(Self.frechenOverview)
        XCTAssertEqual(streets.map(\.id), ["aachener-strasse-1", "ahrendgaesschen-8"])
        XCTAssertEqual(streets.map(\.title), ["Aachener Straße", "Ahrendgäßchen"])
    }

    func testFrechenPickups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let pickups = NRWPortalsProvider.frechenPickups(Self.frechenYear, calendar: calendar)
        XCTAssertEqual(pickups.map { "\(Days.iso($0.date, calendar: calendar)) \($0.name)" }, [
            "2026-01-13 Weihnachtsbäume",
            "2026-03-10 Grünschnittabfuhr / Bündel",
            "2026-11-09 Restmüll", "2026-11-09 Gelbe Tonne / gelber Sack",
            "2026-11-09 Großcontainer Restmüll", "2026-11-09 Großcontainer Restmüll 14-täglich",
            "2026-11-10 Biotonne / Biosäcke",
            "2026-11-23 Restmüll", "2026-11-23 Restmüll 4-wöchentlich",
        ])
        // Jede Art landet in der richtigen Gruppe (Symbol, Farbe, „rausstellen“)
        XCTAssertEqual(Set(pickups.map(\.name)).sorted().map(WasteCategory.classify),
                       [.organic, .packaging, .residual, .residual, .green, .residual, .residual, .green])
        XCTAssertEqual(WasteCategory.classify("Blaue Tonne / Papierbündel"), .paper)
        // Eine noch nicht veröffentlichte Jahresseite (Umleitung auf die Übersicht) liefert nichts
        XCTAssertTrue(NRWPortalsProvider.frechenPickups(Self.frechenOverview, calendar: calendar).isEmpty)
    }

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

    func testNRWFrechen() async throws {
        try await check(NRWPortalsProvider(service: "frechen"), prefer: ["Aachener Straße"], minCount: 10)
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
