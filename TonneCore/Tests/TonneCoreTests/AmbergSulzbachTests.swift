import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// Landkreis Amberg-Sulzbach (landkreis-as.de/abfallwirtschaft): Gemeinde → ggf. Ortsteil oder Straße,
/// dann Kalender-Formular absenden, erst danach existiert die ICS-Datei. Die Antworten unten sind echte,
/// gekürzte Antworten des Portals vom 09.10.2026. Live-Test nur mit TONNE_LIVE=1.
final class AmbergSulzbachTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    // Startseite: Gemeinde-Auswahl (Optionen ohne schließendes Tag), gekürzt.
    static let start = #"""
    <form action="abfuhrtermine.php?jahr=2026" method="POST">
    <label for="abhol_gde">Gemeinde auswählen</label>
    <select id="abhol_gde" name="abhol_gde" class="custom-select form-control" size="1" onchange="this.form.submit()">
    <option value="x">Gemeinde ausw&auml;hlen</option>
    <option value="x">-------------------------</option>
    <option value="21">Ammerthal<option value="5">Auerbach<option value="1">Ensdorf<option value="26">Kümmersbruck<option value="8">K&ouml;nigstein<option value="27">Sulzbach-Rosenberg<option value="25">Vilseck</select>
    <input type="hidden" name="submit_gde" value=""></form>
    """#

    // Gemeinde ohne Unterauswahl (Ensdorf): gleich das Kalender-Formular. `{Y}` = Jahr der Anfrage.
    static let ensdorf = #"""
    <form action="abfuhrtermine.php?abhol_gde=1&jahr={Y}" method="POST">
    <p>&nbsp;</p><div id="links_hover" class="box-mb"><ul class="unstyled-list"><li class="datensatz"><a href="abfuhrtermine.php?jahr={Y}" class="csslink_intern">eine andere Gemeinde ausw&auml;hlen</a></li></ul></div></form>
    <form action="abfuhrtermine_kalender.php?jahr={Y}" method="POST">
    <input type="hidden" name="muell_gde" value="1">
    <input type="hidden" name="muell_ot" value="">
    <input type="hidden" name="muell_ot_id" value="">
    <input type="hidden" name="muell_str" value="">
    <input type="hidden" name="muell_str_id" value="">
    <input type="hidden" name="muell_tag" value="Montag">
    <input type="hidden" name="muell_rest" value="#ffff00">
    <input type="hidden" name="muell_papier" value="#33cc00">
    <input class="btn btn-success" type="Submit" name="submit_kalender" value="Kalender&uuml;bersicht anzeigen">
    </form>
    """#

    // Vilseck: erst Ortsteil (gekürzt).
    static let vilseck = #"""
    <form action="abfuhrtermine.php?abhol_gde=25&jahr={Y}" method="POST">
    <h4>Ortsteil/Stadtgebiet</h4><label for="abhol_gde_ot">Ortsteil/Stadtgebiet auswählen</label><select name="abhol_gde_ot" class="custom-select form-control" size="1"><option value="">Ortsteil/Stadtgebiet ausw&auml;hlen</option><option value="">-------------------------</option><option value="36">Altmannsberg<option value="37">Axtheid<option value="58">Axtheid-Berg<option value="35">Vilseck (Stadtgebiet)<option value="47">Ödgodlricht</select><input type="hidden" name="abhol_gde" value="25"><input class="btn btn-success" type="Submit" name="submit_ot" value="anzeigen"></form>
    """#

    static let vilseckCalendar = #"""
    <form action="abfuhrtermine_kalender.php?jahr={Y}" method="POST">
    <input type="hidden" name="muell_gde" value="25">
    <input type="hidden" name="muell_ot" value="Axtheid-Berg">
    <input type="hidden" name="muell_ot_id" value="58">
    <input type="hidden" name="muell_str" value="">
    <input type="hidden" name="muell_str_id" value="">
    <input type="hidden" name="muell_tag" value="Mittwoch">
    <input type="hidden" name="muell_rest" value="#ff9900">
    <input type="hidden" name="muell_papier" value="#ff94a7">
    <input class="btn btn-success" type="Submit" name="submit_kalender" value="Kalender&uuml;bersicht anzeigen">
    </form>
    """#

    // Sulzbach-Rosenberg: Straßenfeld mit Autovervollständigung.
    static let sulzbach = #"""
    <form action="abfuhrtermine.php?abhol_gde=27&jahr={Y}" method="POST">
    <h4>Stra&szlig;e</h4><input class="form-control auto" type="Text" name="abhol_gde_str_suro_bez"  placeholder="Bitte geben Sie hier die Straße ein ..."><input type="hidden" name="abhol_gde" value="27"><input class="btn btn-success" type="Submit" name="submit_str" value="anzeigen"></form>
    """#

    static let sulzbachCalendar = #"""
    <form action="abfuhrtermine_kalender.php?jahr={Y}" method="POST">
    <input type="hidden" name="muell_gde" value="27">
    <input type="hidden" name="muell_ot" value="">
    <input type="hidden" name="muell_ot_id" value="">
    <input type="hidden" name="muell_str" value="Adam-Stegerwald-Straße">
    <input type="hidden" name="muell_str_id" value="2">
    <input type="hidden" name="muell_tag" value="Freitag">
    <input type="hidden" name="muell_rest" value="#ffff00">
    <input type="hidden" name="muell_papier" value="#33cc00">
    <input class="btn btn-success" type="Submit" name="submit_kalender" value="Kalender&uuml;bersicht anzeigen">
    </form>
    """#

    static let autocomplete = #"["Adam-Stegerwald-Straße"]"#

    // Kalenderseite: Link auf die gerade erzeugte ICS-Datei.
    static let calendarPage = #"""
    <a href="abfuhrtermine_kalender_pdf.php?jahr={Y}&gde=1"><i class="fas fa-print fa-fw"></i>drucken/speichern</a> &nbsp; &nbsp; <a href="abfuhrtermine_kalender_{Y}_{NAME}.ics"><i class="fas fa-download fa-fw" aria-hidden="true"></i>exportieren</a></div>
    <b>Link:</b> <a href="abfuhrtermine_kalender_{Y}_{NAME}.ics">https://www.amberg-sulzbach.de/abfallwirtschaft/abfuhrtermine_kalender_{Y}_{NAME}.ics</a>
    """#

    // ICS von Ensdorf, gekürzt (Zeiten mit TZID und zugleich „Z“, Titel mit Zusätzen).
    static let ics = """
    BEGIN:VCALENDAR\r
    PRODID:Landkreis Amberg-Sulzbach; https://www.amberg-sulzbach.de\r
    VERSION:2.0\r
    METHOD:Publish\r
    X-WR-CALNAME:Abfuhrtermine_Ensdorf2026\r
    BEGIN:VTIMEZONE\r
    TZID:W. Europe Standard Time\r
    BEGIN:STANDARD\r
    DTSTART:16011028T030000\r
    RRULE:FREQ=YEARLY;BYDAY=-1SU;BYMONTH=10\r
    TZOFFSETFROM:+0200\r
    TZOFFSETTO:+0000\r
    END:STANDARD\r
    END:VTIMEZONE\r
    BEGIN:VEVENT\r
    UID:2201202541@amberg-sulzbach.de\r
    DESCRIPTION:Abfuhrkalender für die Gemeinde Ensdorf. Alle Angaben ohne Gewähr (Stand: 24.11.2025).\r
    DTSTART;TZID="W. Europe Standard Time":20261012T060000Z\r
    DTEND;TZID="W. Europe Standard Time":20261012T070000Z\r
    BEGIN:VALARM\r
    TRIGGER:-PT18H\r
    ACTION:DISPLAY\r
    END:VALARM\r
    LOCATION:Ensdorf\r
    SUMMARY:Restmüll | Abfuhrkalender - Landkreis Amberg-Sulzbach\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:2201202542@amberg-sulzbach.de\r
    DTSTART;TZID="W. Europe Standard Time":20261026T060000Z\r
    SUMMARY:Restmüll | Abfuhrkalender - Landkreis Amberg-Sulzbach\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:2201202611@amberg-sulzbach.de\r
    DTSTART;TZID="W. Europe Standard Time":20261102T060000\r
    SUMMARY:Altpapier| Abfuhrkalender - Landkreis Amberg-Sulzbach\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:2201202545@amberg-sulzbach.de\r
    DTSTART;TZID="W. Europe Standard Time":20261219T060000Z\r
    SUMMARY:Restmüll  ! vorgefahren ! | Abfuhrkalender - Landkreis Amberg-Sulzbach\r
    END:VEVENT\r
    END:VCALENDAR\r

    """

    // So antwortet das Portal für 2027, solange es den Plan noch nicht gibt.
    static let emptyICS = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Abfuhrtermine_Ensdorf2027\r\nEND:VCALENDAR\r\n"

    /// Abruftag der Fixtures; so hängen die Stub-Tests nicht vom heutigen Datum ab.
    static let fixtureDay = Days.parse("2026-10-09", calendar: Calendar(identifier: .gregorian))!

    static func stubProvider() -> BayernPortalsProvider {
        var provider = BayernPortalsProvider(service: "landkreis_as", client: HTTPClient(session: LandkreisASStub.session()))
        provider.referenceDate = fixtureDay
        return provider
    }

    func testTownOptions() {
        let options = BayernPortalsProvider.asOptions("abhol_gde", in: Self.start)
        XCTAssertEqual(options.map(\.title), ["Ammerthal", "Auerbach", "Ensdorf", "Kümmersbruck", "Königstein", "Sulzbach-Rosenberg", "Vilseck"])
        XCTAssertEqual(options.first { $0.title == "Vilseck" }?.id, "25")
        XCTAssertTrue(BayernPortalsProvider.asOptions("abhol_gde_ot", in: Self.start).isEmpty, "Gemeinde-Seite hat keine Ortsteile")
    }

    func testDistrictOptions() {
        let options = BayernPortalsProvider.asOptions("abhol_gde_ot", in: Self.vilseck)
        XCTAssertEqual(options.map(\.id), ["36", "37", "58", "35", "47"], "Platzhalter ohne Wert entfallen")
        XCTAssertEqual(options[2].title, "Axtheid-Berg")
    }

    func testCalendarForm() throws {
        XCTAssertNil(BayernPortalsProvider.asCalendarForm(Self.vilseck), "Ortsteil fehlt noch")
        XCTAssertNil(BayernPortalsProvider.asCalendarForm(Self.sulzbach), "Straße fehlt noch")
        let form = try XCTUnwrap(BayernPortalsProvider.asCalendarForm(Self.sulzbachCalendar.replacingOccurrences(of: "{Y}", with: "2026")))
        XCTAssertEqual(form.action, "abfuhrtermine_kalender.php?jahr=2026")
        XCTAssertEqual(form.fields.first { $0.0 == "muell_str" }?.1, "Adam-Stegerwald-Straße")
        XCTAssertEqual(form.fields.first { $0.0 == "muell_str_id" }?.1, "2")
        XCTAssertEqual(form.fields.last?.0, "submit_kalender")
    }

    func testICSLink() {
        let page = Self.calendarPage.replacingOccurrences(of: "{Y}", with: "2026").replacingOccurrences(of: "{NAME}", with: "vilseck58")
        XCTAssertEqual(BayernPortalsProvider.asICSLink(page), "abfuhrtermine_kalender_2026_vilseck58.ics")
    }

    func testSplit() {
        XCTAssertEqual(BayernPortalsProvider.asSplit("Altpapier| Abfuhrkalender - Landkreis Amberg-Sulzbach").first?.name, "Altpapier")
        let moved = BayernPortalsProvider.asSplit("Restmüll  ! nachgefahren ! | Abfuhrkalender - Landkreis Amberg-Sulzbach")
        XCTAssertEqual(moved.first?.name, "Restmüll")
        XCTAssertEqual(moved.first?.note, "nachgefahren")
    }

    func testLabel() {
        let provider = BayernPortalsProvider(service: "landkreis_as")
        XCTAssertEqual(provider.displayName, "Abfallwirtschaft Landkreis Amberg-Sulzbach")
        let street = [SelectionOption(id: "27", title: "Sulzbach-Rosenberg"), SelectionOption(id: "Adam", title: "Adam"),
                      SelectionOption(id: "Adam-Stegerwald-Straße", title: "Adam-Stegerwald-Straße")]
        XCTAssertEqual(provider.label(for: street), "Sulzbach-Rosenberg, Adam-Stegerwald-Straße")
        let district = [SelectionOption(id: "25", title: "Vilseck"), SelectionOption(id: "58", title: "Axtheid-Berg")]
        XCTAssertEqual(provider.label(for: district), "Vilseck, Axtheid-Berg")
    }

    /// (a) Gemeinde ohne Unterauswahl: Gemeinde-POST, Kalender-POST, ICS; Folgejahr leer.
    func testFlowTownOnly() async throws {
        let provider = Self.stubProvider()
        let towns = try await provider.nextStep(after: [])
        let town = try XCTUnwrap(towns?.options.first { $0.title == "Ensdorf" })
        let done = try await provider.nextStep(after: [town])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [town], calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Restmüll", "Restmüll", "Altpapier", "Restmüll"])
        XCTAssertEqual(pickups.map { Days.iso($0.date) }, ["2026-10-12", "2026-10-26", "2026-11-02", "2026-12-19"])
        XCTAssertEqual(pickups.last?.note, "vorgefahren")
        XCTAssertEqual(WasteCategory.classify(pickups[0].name), .residual)
        XCTAssertEqual(WasteCategory.classify(pickups[2].name), .paper)

        let year = 2026
        let requests = LandkreisASStub.requests()
        let townPost = try XCTUnwrap(requests.first { $0.method == "POST" && $0.url.hasSuffix("abfuhrtermine.php?jahr=\(year)") })
        XCTAssertEqual(townPost.body, "abhol_gde=1&submit_gde=")
        XCTAssertEqual(townPost.headers["Content-Type"], "application/x-www-form-urlencoded; charset=utf-8")
        let calendarPost = try XCTUnwrap(requests.first { $0.url.hasSuffix("abfuhrtermine_kalender.php?jahr=\(year)") })
        XCTAssertEqual(calendarPost.method, "POST")
        XCTAssertTrue(calendarPost.body.hasPrefix("muell_gde=1&muell_ot=&muell_ot_id=&muell_str=&muell_str_id=&muell_tag=Montag&muell_rest=%23ffff00"), calendarPost.body)
        XCTAssertTrue(calendarPost.body.hasSuffix("&submit_kalender=Kalender%C3%BCbersicht+anzeigen"), calendarPost.body)
        XCTAssertTrue(requests.contains { $0.method == "GET" && $0.url.hasSuffix("abfuhrtermine_kalender_\(year)_ensdorf.ics") })
        XCTAssertTrue(requests.contains { $0.url.hasSuffix("abfuhrtermine_kalender.php?jahr=\(year + 1)") }, "Folgejahr wird versucht")
    }

    /// (b) Gemeinde mit Ortsteil.
    func testFlowDistrict() async throws {
        let provider = Self.stubProvider()
        let town = SelectionOption(id: "25", title: "Vilseck")
        let districts = try await provider.nextStep(after: [town])
        XCTAssertEqual(districts?.title, SelectionStep.districtTitle)
        let district = try XCTUnwrap(districts?.options.first { $0.title == "Axtheid-Berg" })
        let done = try await provider.nextStep(after: [town, district])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [town, district], calendar: calendar)
        XCTAssertEqual(pickups.count, 4)

        let year = 2026
        let requests = LandkreisASStub.requests()
        let districtPost = try XCTUnwrap(requests.first { $0.url.hasSuffix("abfuhrtermine.php?abhol_gde=25&jahr=\(year)") })
        XCTAssertEqual(districtPost.body, "abhol_gde_ot=58&abhol_gde=25&submit_ot=anzeigen")
        let calendarPost = try XCTUnwrap(requests.first { $0.url.hasSuffix("abfuhrtermine_kalender.php?jahr=\(year)") })
        XCTAssertTrue(calendarPost.body.contains("muell_ot=Axtheid-Berg&muell_ot_id=58"), calendarPost.body)
        XCTAssertTrue(requests.contains { $0.url.hasSuffix("abfuhrtermine_kalender_\(year)_vilseck58.ics") })
    }

    /// (c) Sulzbach-Rosenberg: Straßensuche über die Autovervollständigung.
    func testFlowStreet() async throws {
        let provider = Self.stubProvider()
        let town = SelectionOption(id: "27", title: "Sulzbach-Rosenberg")
        let input = try await provider.nextStep(after: [town])
        XCTAssertEqual(input?.input, .text)
        // Bindestrich bricht die Portalsuche: gesucht wird mit „Stegerwald“, „Adam“ selbst geprüft.
        let search = SelectionOption(id: "Adam-Stegerwald", title: "Adam-Stegerwald")
        let streets = try await provider.nextStep(after: [town, search])
        let street = try XCTUnwrap(streets?.options.first)
        XCTAssertEqual(street.title, "Adam-Stegerwald-Straße")
        let done = try await provider.nextStep(after: [town, search, street])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [town, search, street], calendar: calendar)
        XCTAssertEqual(pickups.count, 4)

        let year = 2026
        let requests = LandkreisASStub.requests()
        XCTAssertTrue(requests.contains { $0.method == "GET" && $0.url.hasSuffix("abfuhrtermine_ort_autocomplete.php?term=Stegerwald") })
        let streetPost = try XCTUnwrap(requests.first { $0.url.hasSuffix("abfuhrtermine.php?abhol_gde=27&jahr=\(year)") })
        XCTAssertEqual(streetPost.body, "abhol_gde_str_suro_bez=Adam-Stegerwald-Stra%C3%9Fe&abhol_gde=27&submit_str=anzeigen")
        XCTAssertTrue(requests.contains { $0.url.hasSuffix("abfuhrtermine_kalender_\(year)_sulzbach-rosenberg2.ics") })
    }

    func testStreetMissingIsRejected() async {
        let provider = Self.stubProvider()
        do {
            _ = try await provider.pickups(for: [SelectionOption(id: "27", title: "Sulzbach-Rosenberg")], calendar: calendar)
            XCTFail("Fehler erwartet")
        } catch {}
    }

    // MARK: Live (je Schrittart einmal)

    private func live(_ selections: [String], search: String? = nil) async throws -> [Pickup] {
        let provider = BayernPortalsProvider(service: "landkreis_as")
        var chosen: [SelectionOption] = []
        for title in selections {
            if let search, chosen.count == 1 { chosen.append(SelectionOption(id: search, title: search)) }
            let step = try await provider.nextStep(after: chosen)
            chosen.append(try XCTUnwrap(step?.options.first { $0.title == title }, "\(title) fehlt"))
        }
        let done = try await provider.nextStep(after: chosen)
        XCTAssertNil(done)
        let pickups = try await provider.pickups(for: chosen, calendar: calendar)
        print("Amberg-Sulzbach \(provider.label(for: chosen)):", pickups.filter { $0.date >= Days.today(calendar: calendar) }.prefix(6).map { "\(Days.iso($0.date)) \($0.name)" })
        return pickups
    }

    /// Ohne feste Daten: mindestens drei künftige Termine, alle als Restmüll bzw. Papier erkannt.
    private func checkFuture(_ pickups: [Pickup]) {
        let future = pickups.filter { $0.date >= Days.today(calendar: calendar) }
        XCTAssertGreaterThanOrEqual(future.count, 3)
        let kinds = Set(future.map { WasteCategory.classify($0.name) })
        XCTAssertTrue(kinds.isSubset(of: [.residual, .paper]), "\(kinds)")
        XCTAssertTrue(kinds.contains(.residual), "Restmüll fehlt")
    }

    func testLiveTownOnly() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let pickups = try await live(["Ensdorf"])
        checkFuture(pickups)
    }

    func testLiveDistrict() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let pickups = try await live(["Vilseck", "Axtheid-Berg"])
        checkFuture(pickups)
    }

    func testLiveStreet() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let pickups = try await live(["Sulzbach-Rosenberg", "Adam-Stegerwald-Straße"], search: "Adam-Steg")
        checkFuture(pickups)
    }
}

/// Nachgestelltes Portal landkreis-as.de für die Tests.
final class LandkreisASStub: URLProtocol {
    struct Seen { let url: String; let method: String; let headers: [String: String]; let body: String }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LandkreisASStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "landkreis-as.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(buffer, count: count)
            }
            stream.close()
            data = collected
        }
        let body = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        Self.lock.lock()
        Self.seen.append(Seen(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:], body: body))
        Self.lock.unlock()

        let year = url.range(of: #"jahr=(\d{4})"#, options: .regularExpression).map { String(url[$0].suffix(4)) } ?? ""
        let fill = { (text: String) in text.replacingOccurrences(of: "{Y}", with: year) }
        let tests = AmbergSulzbachTests.self
        var text = ""
        if url.hasSuffix("abfuhrtermine.php") {
            text = tests.start
        } else if url.contains("abfuhrtermine_ort_autocomplete.php") {
            text = tests.autocomplete
        } else if url.contains("abfuhrtermine_kalender.php") {
            let name = body.contains("muell_gde=25") ? "vilseck58" : body.contains("muell_gde=27") ? "sulzbach-rosenberg2" : "ensdorf"
            text = fill(tests.calendarPage).replacingOccurrences(of: "{NAME}", with: name)
        } else if url.hasSuffix(".ics") {
            text = url.contains("_2026_") ? tests.ics : tests.emptyICS
        } else if url.contains("abfuhrtermine.php") {
            if body.contains("submit_ot=") { text = tests.vilseckCalendar }
            else if body.contains("submit_str=") { text = tests.sulzbachCalendar }
            else if body.contains("abhol_gde=25") { text = tests.vilseck }
            else if body.contains("abhol_gde=27") { text = tests.sulzbach }
            else if body.contains("abhol_gde=1&") { text = tests.ensdorf }
            text = fill(text)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
