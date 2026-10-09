import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// Kreis Minden-Lübbecke: Espelkamp (iKISS wie Kreis Herford) und PreZero Bad Oeynhausen.
/// Echte, gekürzte Antworten der Portale vom Oktober 2026; Live-Test nur mit TONNE_LIVE=1.
final class MindenLuebbeckeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    // Espelkamp liefert die Straßenliste in ISO-8859-1.
    static let espelkampStreets = """
    <select name="strasse" class="form_ft" style="width:400px" size="1" id="InputStr" onchange="document.SFm.call.value='sfm';document.SFm.submit();">
    <option value="">-Bitte w&auml;hlen-</option>
    <option value="2862.456.1">Adolf-Kolping-Straße</option>
    <option value="2862.115.1">Fabbenstedter Straße</option>
    <option value="2862.466.1">Fabbenstedter Straße 1-32</option>
    <option value="2862.468.1">Fabbenstedter Straße ab 34</option>
    <option value="2862.476.1">Riesebach</option>
    <option value="2862.477.1">Riesebach (gerade Hsnr)</option>
    </select>
    """

    static let espelkampICS = """
    BEGIN:VCALENDAR
    METHOD:PUBLISH
    X-WR-TIMEZONE:Europe/Berlin
    PRODID:http://www.espelkamp.de
    VERSION:2.0
    BEGIN:VEVENT
    LOCATION: Espelkamp - Adolf-Kolping-Straße
    SUMMARY:Restabfall (vierwöchentlich): Espelkamp
    DTSTART;VALUE=DATE:20261009
    END:VEVENT
    BEGIN:VEVENT
    SUMMARY:Bioabfall (14-täglich): Espelkamp
    DTSTART;VALUE=DATE:20261016
    END:VEVENT
    BEGIN:VEVENT
    SUMMARY:Altpapier (vierwöchentlich): Espelkamp
    DTSTART;VALUE=DATE:20261020
    END:VEVENT
    BEGIN:VEVENT
    SUMMARY:Leichtstoffe (vierwöchentlich): Espelkamp
    DTSTART;VALUE=DATE:20261021
    END:VEVENT
    END:VCALENDAR
    """

    static let prezeroStreets = """
    <select id="street" name="street" class="selectpicker" data-width="100%" data-live-search="true" data-none-results-text="Adresse nicht gefunden: {0}" required>
        <option selected disabled value="" data-postalcode="" data-city="">Bitte wählen Sie einen Straßennamen</option>
        <option value="Aalstraße" data-postalcode="32549" data-city="Bad Oeynhausen - NULL" >Aalstraße</option>
        <option value="Ackerstraße" data-postalcode="32549" data-city="Bad Oeynhausen - NULL" >Ackerstraße</option>
        <option value="Adam-Opel-Straße" data-postalcode="32547" data-city="Bad Oeynhausen - NULL" >Adam-Opel-Straße</option>
    </select>
    """

    static let prezeroCalendarPage = """
    <form action="/bad-oeynhausen/download/ical/787/1/2026"
          method="post" class="ical">
        <input class="form-check-input" type="checkbox" name="material[]" value="1" id="checkbox-1" checked required>
    </form>
    """

    static let prezeroICS = """
    BEGIN:VCALENDAR\r
    PRODID:-//eluceo/ical//2.0/EN\r
    VERSION:2.0\r
    BEGIN:VEVENT\r
    SUMMARY:Papiertonne\r
    DTSTART;VALUE=DATE:20261015\r
    LOCATION:Aalstraße 1\\, 32549 Bad Oeynhausen\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    SUMMARY:Restmülltonne\r
    DTSTART;VALUE=DATE:20261015\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    SUMMARY:Biotonne\r
    DTSTART;VALUE=DATE:20261022\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    SUMMARY:Gelbe Tonne\r
    DTSTART;VALUE=DATE:20261022\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    SUMMARY:Schadstoffsammlung\r
    DTSTART;VALUE=DATE:20261024\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    SUMMARY:Biotonne-Reinigung\r
    DTSTART;VALUE=DATE:20261027\r
    END:VEVENT\r
    END:VCALENDAR\r
    """

    // MARK: - Espelkamp

    func testEspelkampNames() {
        let names = ["Restabfall (vierwöchentlich): Espelkamp", "Bioabfall (14-täglich): Espelkamp",
                     "Altpapier (vierwöchentlich): Espelkamp", "Leichtstoffe (vierwöchentlich): Espelkamp"]
            .map { NRWPortalsProvider.herfordNames($0, place: "Espelkamp")[0] }
        XCTAssertEqual(names, ["Restabfall (vierwöchentlich)", "Bioabfall (14-täglich)", "Altpapier (vierwöchentlich)", "Leichtstoffverpackungen (vierwöchentlich)"])
        XCTAssertEqual(names.map(WasteCategory.classify), [.residual, .organic, .paper, .packaging])
    }

    func testEspelkampSplitStreetsDropped() {
        let options = HTMLText.options(ofSelect: "strasse", in: Self.espelkampStreets).filter { !$0.value.isEmpty }
            .map { SelectionOption(id: $0.value, title: $0.label) }
        XCTAssertEqual(NRWPortalsProvider.withoutSplitStreets(options).map(\.id),
                       ["2862.456.1", "2862.466.1", "2862.468.1", "2862.477.1"],
                       "Gesamteinträge aufgeteilter Straßen (Fabbenstedter Straße, Riesebach) fallen weg")
    }

    func testEspelkampFlowAgainstStub() async throws {
        let provider = NRWPortalsProvider(service: "espelkamp", client: HTTPClient(session: MindenStub.session()))
        XCTAssertEqual(provider.displayName, "Stadt Espelkamp")
        let streets = try await provider.nextStep(after: [])
        XCTAssertEqual(streets?.title, SelectionStep.streetTitle, "nur eine Kommune – keine Ortswahl")
        XCTAssertEqual(streets?.options.map(\.title), ["Adolf-Kolping-Straße", "Fabbenstedter Straße 1-32", "Fabbenstedter Straße ab 34", "Riesebach (gerade Hsnr)"])
        let street = try XCTUnwrap(streets?.options.first)
        let done = try await provider.nextStep(after: [street])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [street], calendar: calendar)
        XCTAssertEqual(pickups.count, 4)
        XCTAssertEqual(pickups.first?.date, Days.parse("2026-10-09", calendar: calendar))
        XCTAssertEqual(pickups.first?.name, "Restabfall (vierwöchentlich)")
        XCTAssertEqual(provider.label(for: [street]), "Espelkamp, Adolf-Kolping-Straße")

        let requests = MindenStub.requests()
        XCTAssertEqual(requests.first?.url, "https://www.espelkamp.de/index.php?La=1&ffmod=abf&ort=322.4&call=sfm")
        let export = try XCTUnwrap(requests.first { $0.url.contains("abfall_export.php") })
        XCTAssertTrue(export.url.hasPrefix("https://www.espelkamp.de/output/abfall_export.php?csv_export=1&mode=vcal&ort=322.4&strasse=2862.456.1&vtyp=2&vMo=01&vJ="), export.url)
        XCTAssertEqual(export.headers["Referer"], "https://www.espelkamp.de/")
    }

    func testHerfordStillAsksForPlace() async throws {
        let provider = NRWPortalsProvider(service: "herford", client: HTTPClient(session: MindenStub.session()))
        let first = try await provider.nextStep(after: [])
        XCTAssertEqual(first?.title, SelectionStep.cityTitle)
        XCTAssertEqual(first?.options.count, 9)
        XCTAssertFalse(first?.options.contains { $0.title == "Espelkamp" } ?? true)
    }

    // MARK: - PreZero Bad Oeynhausen

    func testPrezeroParsing() {
        XCTAssertEqual(NRWPortalsProvider.prezeroDownloadPath(Self.prezeroCalendarPage), "/bad-oeynhausen/download/ical/787/1")
        XCTAssertNil(NRWPortalsProvider.prezeroDownloadPath("<form method=\"post\"></form>"))
        let pickups = NRWPortalsProvider.prezeroPickups(Self.prezeroICS, calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Papiertonne", "Restmülltonne", "Biotonne", "Gelbe Tonne", "Schadstoffsammlung"],
                       "Tonnenreinigung ist keine Abfuhr")
        XCTAssertEqual(pickups.map { WasteCategory.classify($0.name) }, [.paper, .residual, .organic, .packaging, .hazardous])
    }

    func testPrezeroFlowAgainstStub() async throws {
        let provider = NRWPortalsProvider(service: "prezero", client: HTTPClient(session: MindenStub.session()))
        XCTAssertEqual(provider.displayName, "PreZero Bad Oeynhausen")
        let streets = try await provider.nextStep(after: [])
        XCTAssertEqual(streets?.options.map(\.title), ["Aalstraße", "Ackerstraße", "Adam-Opel-Straße"])
        let street = try XCTUnwrap(streets?.options.first)
        let number = try await provider.nextStep(after: [street])
        XCTAssertEqual(number?.input, .text)
        let house = SelectionOption(id: "1", title: " 1 ")
        let done = try await provider.nextStep(after: [street, house])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [street, house], calendar: calendar)
        XCTAssertEqual(pickups.count, 5)
        XCTAssertEqual(pickups.first?.date, Days.parse("2026-10-15", calendar: calendar))
        XCTAssertEqual(provider.label(for: [street, SelectionOption(id: "1", title: "1")]), "Bad Oeynhausen, Aalstraße 1")

        let requests = MindenStub.requests()
        let form = try XCTUnwrap(requests.first { $0.method == "POST" && $0.url.hasSuffix("/bad-oeynhausen") })
        XCTAssertEqual(form.body, "street=Aalstra%C3%9Fe&houseNo=1")
        XCTAssertEqual(form.headers["Content-Type"], "application/x-www-form-urlencoded; charset=utf-8")
        let downloads = requests.filter { $0.url.contains("/download/ical/") }
        let year = calendar.component(.year, from: Date())
        XCTAssertEqual(downloads.map(\.url), ["https://abfallkalender.prezero.network/bad-oeynhausen/download/ical/787/1/\(year)",
                                             "https://abfallkalender.prezero.network/bad-oeynhausen/download/ical/787/1/\(year + 1)"])
        XCTAssertEqual(downloads.first?.method, "POST")
    }

    // MARK: - Live

    func testLiveEspelkamp() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = NRWPortalsProvider(service: "espelkamp")
        let streets = try await provider.nextStep(after: [])
        XCTAssertGreaterThan(streets?.options.count ?? 0, 400)
        XCTAssertFalse(streets?.options.contains { $0.title == "Fabbenstedter Straße" } ?? true)
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Adolf-Kolping-Straße" })
        let pickups = try await provider.pickups(for: [street], calendar: calendar)
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-09" && WasteCategory.classify($0.name) == .residual })
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-16" && WasteCategory.classify($0.name) == .organic })
        XCTAssertEqual(Set(pickups.map { WasteCategory.classify($0.name) }), [.residual, .organic, .paper, .packaging])
        let split = try XCTUnwrap(streets?.options.first { $0.title == "Fabbenstedter Straße 1-32" })
        let splitPickups = try await provider.pickups(for: [split], calendar: calendar)
        XCTAssertGreaterThanOrEqual(splitPickups.count, 3)
        print("Espelkamp:", pickups.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })
    }

    func testLivePrezeroBadOeynhausen() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = NRWPortalsProvider(service: "prezero")
        let streets = try await provider.nextStep(after: [])
        XCTAssertGreaterThan(streets?.options.count ?? 0, 1000)
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Aalstraße" })
        let selections = [street, SelectionOption(id: "1", title: "1")]
        let pickups = try await provider.pickups(for: selections, calendar: calendar)
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-15" })
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-22" })
        XCTAssertTrue(Set(pickups.map { WasteCategory.classify($0.name) }).isSuperset(of: [.residual, .organic, .paper, .packaging]))
        print("Bad Oeynhausen:", pickups.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })
    }
}

/// Nachgestellte Portale Espelkamp und PreZero für die Tests.
final class MindenStub: URLProtocol {
    struct Seen { let url: String; let method: String; let headers: [String: String]; let body: String }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MindenStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool {
        ["www.espelkamp.de", "abfallkalender.prezero.network"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        }
        Self.lock.lock()
        Self.seen.append(Seen(url: url, method: method, headers: request.allHTTPHeaderFields ?? [:],
                              body: body.map { String(decoding: $0, as: UTF8.self) } ?? ""))
        Self.lock.unlock()

        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let data: Data
        if url.contains("ffmod=abf") { data = MindenLuebbeckeTests.espelkampStreets.data(using: .isoLatin1)! }
        else if url.contains("abfall_export.php") {
            // Wie live: Für das Folgejahr gibt es noch keine Termine.
            data = Data((url.contains("vJ=\(year)&") ? MindenLuebbeckeTests.espelkampICS : "BEGIN:VCALENDAR\nEND:VCALENDAR\n").utf8)
        } else if url.contains("/download/ical/") {
            data = Data((url.hasSuffix("/\(year)") ? MindenLuebbeckeTests.prezeroICS : "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n").utf8)
        } else if method == "POST" { data = Data(MindenLuebbeckeTests.prezeroCalendarPage.utf8) }
        else { data = Data(MindenLuebbeckeTests.prezeroStreets.utf8) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
