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
        // Portalseite mit Kalender je Straße: auch wenn die Adresse „ical“ enthält, wird der eigene Link eingefügt
        XCTAssertFalse(ICSURLProvider(url: "https://example.org/abfall/ical/#einfuegen").isDirectLink)
        XCTAssertTrue(ICSURLProvider(url: "https://alsfeld.mein-abfallkalender.online/ical.ics?id=1").isDirectLink)
    }

    func testPortalPageAsksForLink() async throws {
        let step = try await ICSURLProvider(url: "https://alsfeld.mein-abfallkalender.online").nextStep(after: [])
        XCTAssertEqual(step?.input, .text)
        let direct = try await ICSURLProvider(url: "https://cms.eigeltingen.de/tools/icsAbfalltermine/?datasource=eigeltingen").nextStep(after: [])
        XCTAssertNil(direct)
        let paste = try await ICSURLProvider(url: "https://example.org/abfall/ical/#einfuegen").nextStep(after: [])
        XCTAssertEqual(paste?.input, .text)
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
        XCTAssertEqual(ICSURLProvider.names("Abfuhr Rest+Bio Bezirk 1"), ["Rest", "Bio"])
        XCTAssertEqual(ICSURLProvider.names("Abfuhr Garten Frühjahr Bezirk 8"), ["Garten Frühjahr"])
        XCTAssertEqual(ICSURLProvider.names("Abfuhr Wertstoff Bezirk 3"), ["Wertstoff"])
        // Wachtendonk: gleiche Müllart in der Datei 2026 (Umschrift) und 2027 (Umlaut)
        XCTAssertEqual(ICSURLProvider.names("Bezirk 1 - Restmuell (grau)"), ["Restmüll"])
        XCTAssertEqual(ICSURLProvider.names("Bezirk 1 - Restmüll (grau)"), ["Restmüll"])
        XCTAssertEqual(ICSURLProvider.names("Bezirk 3 - Papier (gruen)"), ["Papier"])
        XCTAssertEqual(ICSURLProvider.names("Bezirk 1 - 4 - Glaskoerbe"), ["Glaskörbe"])
        XCTAssertEqual(ICSURLProvider.names("Bezirk 1 - 4 - Wertstoffe (gelb)"), ["Wertstoffe"])
        // Gegenprobe: ein Titel ohne Bezirksvorsatz bleibt unverändert
        XCTAssertEqual(ICSURLProvider.names("Schadstoffsammlung Wachtendonk"), ["Schadstoffsammlung Wachtendonk"])
        // MZV Rotenburg-Bebra; ein früher gespeicherter Titel führt zur neuen Müllart
        XCTAssertEqual(ICSURLProvider.names("Entsorgung Gelbe Tonne"), ["Gelbe Tonne"])
        XCTAssertTrue(ICSURLProvider.formerTitle("Entsorgung Restabfall", matches: "Restabfall"))
        XCTAssertEqual(ICSURLProvider.names("Entsorgungshof geöffnet"), ["Entsorgungshof geöffnet"])
        XCTAssertEqual(ICSURLProvider.names("Restmüll (Bezirk 2)"), ["Restmüll (Bezirk 2)"], "andere Bezirks-Titel bleiben")
        // Ginsheim-Gustavsburg: „Müllart - Bezirk“; ohne erkannte Müllart vorn bleibt der Titel
        XCTAssertEqual(ICSURLProvider.names("Graue Tonne - Gustavsburg"), ["Graue Tonne"])
        XCTAssertEqual(ICSURLProvider.names("Schadstoffmobil - Alle"), ["Schadstoffmobil"])
        XCTAssertEqual(ICSURLProvider.names("Tag der offenen Tür - Bauhof"), ["Tag der offenen Tür - Bauhof"])
        XCTAssertTrue(WasteCategory.isIgnorableTitle("Wertstoffhof geöffnet (WH) – W1"), "Öffnungstage sind keine Abholung")
    }

    /// Gespeicherte Müllarten aus der Zeit vor der Bereinigung finden ihre Termine wieder (keine doppelten Arten).
    func testFormerTitle() {
        XCTAssertTrue(ICSURLProvider.formerTitle("Abholung: Biomüll", matches: "Biomüll"))
        XCTAssertTrue(ICSURLProvider.formerTitle("Abfalltermin (Restmüll)", matches: "Restmüll"))
        XCTAssertTrue(ICSURLProvider.formerTitle("Abholung: Biomüll, Restmüll", matches: "Biomüll"), "Sammeltermin: erster Teil führt weiter")
        XCTAssertFalse(ICSURLProvider.formerTitle("Abholung: Biomüll, Restmüll", matches: "Restmüll"), "zweiter Teil wird neue Müllart")
        XCTAssertFalse(ICSURLProvider.formerTitle("Biomüll", matches: "Biomüll"), "unverändert – normale Zuordnung")
        XCTAssertFalse(ICSURLProvider.formerTitle("Papier", matches: "Biomüll"))
    }

    /// Abgleich: jede Müllart höchstens einmal, sonst ersetzt ein Titel die Termine des anderen.
    func testTitleMatchingAssignsEachTypeOnce() {
        typealias E = WasteTitleMatching.Existing
        // Früherer Sammeltermin, vom Nutzer in „Restmüll“ umbenannt: „Biomüll“ führt ihn weiter, „Restmüll“ wird neu
        var result = WasteTitleMatching.assign(["Biomüll", "Restmüll"], to: [E(sourceKey: "Abholung: Biomüll, Restmüll", name: "Restmüll")])
        XCTAssertEqual(result, ["Biomüll": 0])
        // Gleicher Quellen-Titel hat Vorrang vor gleichem Namen
        result = WasteTitleMatching.assign(["Papier"], to: [E(sourceKey: nil, name: "Papier"), E(sourceKey: "Papier", name: "Blaue Tonne")])
        XCTAssertEqual(result, ["Papier": 1])
        // Bereinigter Titel findet die alte Müllart, unbekannte Titel bleiben frei
        result = WasteTitleMatching.assign(["Biomüll", "Sperrmüll"], to: [E(sourceKey: "Abholung: Biomüll", name: "Abholung: Biomüll")])
        XCTAssertEqual(result, ["Biomüll": 0])
        // Name ohne Rücksicht auf Groß-/Kleinschreibung
        result = WasteTitleMatching.assign(["gelber sack"], to: [E(sourceKey: nil, name: "Gelber Sack")])
        XCTAssertEqual(result, ["gelber sack": 0])
        // Datei-Import: dieselbe Müllart darf mehrere Titel bekommen (Termine werden beim Übernehmen vereinigt)
        result = WasteTitleMatching.assign(["Biomüll", "Restmüll"], to: [E(sourceKey: "Abholung: Biomüll, Restmüll", name: "Restmüll")], exclusive: false)
        XCTAssertEqual(result, ["Biomüll": 0, "Restmüll": 0])
    }

    /// Steinbach: eine Datei für beide Bezirke – `#ohne=` lässt den anderen Bezirk und Großbehälter weg.
    func testExcludeMarker() async throws {
        ICSStub.body = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261009
        SUMMARY:Restmüll (Bezirk 1)
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261012
        SUMMARY:Restmüll (Bezirk 2)
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261013
        SUMMARY:Restmüll Großbehälter 1\\,1 m³
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261015
        SUMMARY:Biomüll
        END:VEVENT
        END:VCALENDAR
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ICSStub.self]
        let provider = ICSURLProvider(url: "https://www.stadt-steinbach.de/kalender/abfallkalender/event.ics?weekends=false#ohne=(Bezirk 2)|Großbehälter",
                                      client: HTTPClient(session: URLSession(configuration: config)))
        let pickups = try await provider.pickups(for: [], calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(pickups.map(\.name), ["Restmüll (Bezirk 1)", "Biomüll"])
        XCTAssertEqual(ICSStub.lastURL, "https://www.stadt-steinbach.de/kalender/abfallkalender/event.ics?weekends=false", "Filter geht nicht mit zum Server")
    }

    /// Ginsheim-Gustavsburg: Kalender nur als Antwort auf das Export-Formular – `#post=` schickt es per POST, mit Jahr.
    func testPostMarker() async throws {
        ICSStub.body = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260105
        SUMMARY:Grüne Tonne - Ginsheim
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260107
        SUMMARY:Gelbe Tonne - Alle
        END:VEVENT
        END:VCALENDAR
        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ICSStub.self]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let provider = ICSURLProvider(url: "https://abfallkalender.gigu.de/export/ical#post=dateFrom={%Y}-01-01&dateTo={%Y}-12-31&district=2&category=1",
                                      client: HTTPClient(session: URLSession(configuration: config)))
        XCTAssertTrue(provider.isDirectLink)
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Grüne Tonne", "Gelbe Tonne"], "Bezirk im Titel fällt weg")
        XCTAssertEqual(ICSStub.lastURL, "https://abfallkalender.gigu.de/export/ical")
        XCTAssertEqual(ICSStub.lastMethod, "POST")
        // ab November zuletzt das Folgejahr ({%Y} im Formular wie in der Adresse)
        let year = calendar.component(.year, from: Date()) + (calendar.component(.month, from: Date()) >= 11 ? 1 : 0)
        XCTAssertTrue(ICSStub.lastBody.hasPrefix("dateFrom=\(year)-01-01&dateTo=\(year)-12-31"), ICSStub.lastBody)
        XCTAssertTrue(ICSStub.lastBody.hasSuffix("&district=2&category=1"), ICSStub.lastBody)
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

    /// Neuberg (ein ICS-Link ohne Linktext) und Waltrop (acht Bezirke, neue Dateien stehen vor denen des Vorjahrs).
    func testLiveNeubergAndWaltrop() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let today = calendar.startOfDay(for: Date())
        let entries = ProviderCatalog.entries.filter { $0.kind == .icsURL && ($0.serviceKey.contains("neuberg.eu") || $0.serviceKey.contains("vue-waltrop.de")) }
        XCTAssertEqual(entries.count, 9)
        for entry in entries {
            let pickups = try await ICSURLProvider(url: entry.serviceKey).pickups(for: [], calendar: calendar)
            let future = pickups.filter { $0.date >= today }
            let names = Set(future.map(\.name))
            print("ICS \(entry.title): \(future.count) künftig, \(names.sorted())")
            XCTAssertGreaterThanOrEqual(future.count, 3, entry.title)
            XCTAssertFalse(names.contains { $0.contains("Bezirk") || $0.hasPrefix("Abfuhr") }, "\(entry.title): \(names)")
        }
    }

    /// Feste Kalenderdateien der Gemeinden aus dem Abgleich vom 11.11.2026 (je Ortsteil/Bezirk eine Datei).
    func testLiveMunicipalFilesNovember2026() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let today = calendar.startOfDay(for: Date())
        let hosts = ["hasselroth.de": 3, "badsoden-salmuenster.de": 6, "neuried.de": 2, "erndtebrueck.de": 7, "lebach.de": 25, "calendar.google.com": 1,
                     "wachtendonk.de": 5, "mzv-rotenburg-bebra.de": 27, "abfallkalender.gigu.de": 2]
        for (host, count) in hosts {
            let entries = ProviderCatalog.entries.filter { $0.kind == .icsURL && $0.serviceKey.contains(host) }
            XCTAssertEqual(entries.count, count, host)
            for entry in entries {
                let pickups = try await ICSURLProvider(url: entry.serviceKey).pickups(for: [], calendar: calendar)
                let future = pickups.filter { $0.date >= today }
                print("ICS \(entry.title): \(future.count) künftig, \(Set(future.map(\.name)).sorted())")
                XCTAssertGreaterThanOrEqual(future.count, 3, entry.title)
                XCTAssertFalse(future.contains { p in ["Alle", "Ginsheim", "Gustavsburg"].contains { p.name.hasSuffix(" - " + $0) } }, entry.title)
                if let marker = entry.serviceKey.range(of: "#ohne-ort=") {
                    // Ortsfilter: kein Termin aus einem ausgeschlossenen Bezirk, Gelbe Tonne nur aus einem Bezirk
                    let excluded = entry.serviceKey[marker.upperBound...].split(separator: "|").map { $0.lowercased() }
                    XCTAssertFalse(pickups.contains { p in excluded.contains { (p.note ?? "").lowercased().contains($0) } }, entry.title)
                    XCTAssertEqual(Set(pickups.filter { $0.name == "Gelbe Tonne" }.map(\.note)).count, 1, entry.title)
                }
            }
        }
    }

    /// Gladbeck gibt den Kalender je Straße aus; auf der Seite steht der eigene Link unter „Kalender abonnieren“ zum Kopieren.
    func testLiveGladbeckPastedLink() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let entry = try XCTUnwrap(ProviderCatalog.entries.first { $0.kind == .icsURL && $0.serviceKey.contains("zb-gladbeck.de") })
        let provider = ICSURLProvider(url: entry.serviceKey)
        XCTAssertFalse(provider.isDirectLink)
        let link = SelectionOption(id: "https://www.zb-gladbeck.de/abfuhrkalender?format=ical&street=31B56D20&number=1", title: "Adlerstraße 1")
        let names = Set(try await provider.pickups(for: [link], calendar: calendar).map(\.name))
        print("ICS Gladbeck: \(names.sorted())")
        XCTAssertTrue(names.isSuperset(of: ["Graue Tonne", "Braune Tonne", "Blaue Tonne", "Wertstofftonne"]), "\(names)")
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

/// Liefert eine feste ICS-Datei und merkt sich die angefragte Adresse.
final class ICSStub: URLProtocol {
    nonisolated(unsafe) static var body = ""
    nonisolated(unsafe) static var lastURL = ""
    nonisolated(unsafe) static var lastMethod = ""
    nonisolated(unsafe) static var lastBody = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastURL = request.url?.absoluteString ?? ""
        Self.lastMethod = request.httpMethod ?? ""
        // URLSession reicht den Inhalt im URLProtocol als Stream weiter
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(buffer, count: n) }
            stream.close()
        }
        Self.lastBody = String(decoding: body, as: UTF8.self)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/calendar"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
