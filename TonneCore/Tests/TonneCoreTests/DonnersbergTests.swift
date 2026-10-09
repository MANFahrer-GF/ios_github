import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// Abfall-App Donnersbergkreis (Softwareentwicklung Roth): Ort → ggf. Straße → ICS je Jahr.
/// Echte, gekürzte Antworten vom Oktober 2026. Live-Test nur mit TONNE_LIVE=1.
final class DonnersbergTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    // /web/KIB/de/kalender (gekürzt)
    static let places = #"""
    <li class="nav-item"><a class="nav-link  active" aria-current="page" href="/web/KIB/de/kalender">Müllabfuhrplan</a></li>
    <ul class="orte-liste" id="orte-liste">
                                <li><a href="/web/KIB/de/kalender/Albisheim/muellarten">Albisheim</a></li>
                                            <li><a href="/web/KIB/de/kalender/Auf_der_Fuellenweide/muellarten">Auf der Füllenweide</a></li>
                                            <li><a href="/web/KIB/de/kalender/orte/Eisenberg/strassen">Eisenberg</a></li>
                                            <li><a href="/web/KIB/de/kalender/orte/Kirchheimbolanden/strassen">Kirchheimbolanden</a></li>
                                            <li><a href="/web/KIB/de/kalender/Reichsthal-Seelen/muellarten">Reichsthal-Seelen</a></li>
                                            <li><a href="/web/KIB/de/kalender/Seltenbach/muellarten">Seltenbach </a></li>
    </ul>
    """#

    // /web/KIB/de/kalender/orte/Kirchheimbolanden/strassen (gekürzt)
    static let streets = #"""
    <li id="nav-item-herausloesen" hidden class="nav-item"><a class="nav-link" href="/web/KIB/de/kalender/orte/Kirchheimbolanden/strassen" target="blank">In eigenem Fenster öffnen</a></li>
    <ul class="strassen-liste" id="strassen-liste">
                   <li><a href="/web/KIB/de/kalender/Kirchheimbolanden/Albrecht-Duerer-Strasse/muellarten">Albrecht-Dürer-Straße</a></li>
                   <li><a href="/web/KIB/de/kalender/Kirchheimbolanden/Am_Schlossgarten/muellarten">Am Schloßgarten</a></li>
                   <li><a href="/web/KIB/de/kalender/Kirchheimbolanden/Amtsstrasse/muellarten">Amtsstraße</a></li>
    </ul>
    """#

    // /web/KIB/de/kalender/Albisheim/muellarten (gekürzt)
    static let types = #"""
    <form class="abfallarten-liste" id="abfallarten-liste" action="/web/KIB/de/kalender/Albisheim" method="GET">
        <fieldset>
            <div class="form-check">
            <input class="form-check-input" type="checkbox" name="abfallart_Restabfall" id="Restabfall" checked>
            <label class="form-check-label restabfall" for="Restabfall">Restabfall</label>
            </div>
            <div class="form-check">
            <input class="form-check-input" type="checkbox" name="abfallart_Bioabfall" id="Bioabfall" checked>
            <label class="form-check-label bioabfall" for="Bioabfall">Bioabfall</label>
            </div>
            <div class="form-check">
            <input class="form-check-input" type="checkbox" name="abfallart_Papier" id="Papier" checked>
            <label class="form-check-label papier" for="Papier">Papierabfall</label>
            </div>
            <div class="form-check">
            <input class="form-check-input" type="checkbox" name="abfallart_GelberSack" id="GelberSack" checked>
            <label class="form-check-label gelbersack" for="GelberSack">Gelber Sack</label>
            </div>
            <button id="btnZumAbfurplan" class="btn btn-primary" type="submit">Zum Müllabfuhrplan</button>
        </fieldset>
    </form>
    """#

    // /2026/KIB/Albisheim/ics/de?… (gekürzt)
    static let ics = """
    BEGIN:VCALENDAR\r
    VERSION:2.0\r
    PRODID:-//Softwareentwicklung-Roth//abfallkalender_online_1_0//DE\r
    BEGIN:VEVENT\r
    UID:20261008-2257460783674384-58499370582850@abfallkalender_online.sof\r
     twareentwicklung-roth.de\r
    DTSTAMP:20261009T085124Z\r
    DTSTART;VALUE=DATE:20261008\r
    DTEND;VALUE=DATE:20261009\r
    LOCATION:Albisheim\r
    SUMMARY:Restabfall\r
    TRANSP:TRANSPARENT\r
    CLASS:PUBLIC\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:20261008-2383354359-58499370582850@abfallkalender_online.softwaree\r
     ntwicklung-roth.de\r
    DTSTAMP:20261009T085124Z\r
    DTSTART;VALUE=DATE:20261008\r
    DTEND;VALUE=DATE:20261009\r
    LOCATION:Albisheim\r
    SUMMARY:Papierabfall\r
    TRANSP:TRANSPARENT\r
    CLASS:PUBLIC\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:20261014-59281016529412-58499370582850@abfallkalender_online.softw\r
     areentwicklung-roth.de\r
    DTSTAMP:20261009T085124Z\r
    DTSTART;VALUE=DATE:20261014\r
    DTEND;VALUE=DATE:20261015\r
    LOCATION:Albisheim\r
    SUMMARY:Bioabfall\r
    TRANSP:TRANSPARENT\r
    CLASS:PUBLIC\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:20261014-1966416505268599-58499370582850@abfallkalender_online.sof\r
     twareentwicklung-roth.de\r
    DTSTAMP:20261009T085124Z\r
    DTSTART;VALUE=DATE:20261014\r
    DTEND;VALUE=DATE:20261015\r
    LOCATION:Albisheim\r
    SUMMARY:Gelber Sack\r
    TRANSP:TRANSPARENT\r
    CLASS:PUBLIC\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:20261222-1966416505268599-58499370582850@abfallkalender_online.sof\r
     twareentwicklung-roth.de\r
    DTSTAMP:20261009T085124Z\r
    DTSTART;VALUE=DATE:20261222\r
    DTEND;VALUE=DATE:20261223\r
    LOCATION:Albisheim\r
    SUMMARY:Gelber Sack\\nVerlegt wg. Weihnachten\r
    TRANSP:TRANSPARENT\r
    CLASS:PUBLIC\r
    END:VEVENT\r
    END:VCALENDAR\r

    """

    func testPlacesParsing() {
        let options = RheinlandPfalzPortalsProvider.donnersbergPlaces(Self.places)
        XCTAssertEqual(options.map(\.title), ["Albisheim", "Auf der Füllenweide", "Eisenberg", "Kirchheimbolanden", "Reichsthal-Seelen", "Seltenbach"],
                       "Navigationslink ohne Ort fällt weg, Leerzeichen am Namensende auch")
        XCTAssertEqual(options.first?.id, "Albisheim")
        XCTAssertEqual(options[2].id, "orte/Eisenberg", "Orte mit Straßenliste behalten das Präfix")
    }

    func testStreetsParsing() {
        let options = RheinlandPfalzPortalsProvider.donnersbergStreets(Self.streets)
        XCTAssertEqual(options.map(\.title), ["Albrecht-Dürer-Straße", "Am Schloßgarten", "Amtsstraße"],
                       "„In eigenem Fenster öffnen“ verweist auf die Straßenliste selbst und fällt weg")
        XCTAssertEqual(options.last?.id, "Kirchheimbolanden/Amtsstrasse")
    }

    func testTypesParsing() {
        XCTAssertEqual(RheinlandPfalzPortalsProvider.donnersbergTypes(Self.types),
                       ["abfallart_Restabfall", "abfallart_Bioabfall", "abfallart_Papier", "abfallart_GelberSack"])
    }

    func testPickupsParsing() {
        let pickups = RheinlandPfalzPortalsProvider.donnersbergPickups(Self.ics, calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Papierabfall", "Restabfall", "Bioabfall", "Gelber Sack", "Gelber Sack"],
                       "Hinweis „Verlegt wg. Weihnachten“ wird abgeschnitten")
        XCTAssertEqual(pickups.first?.date, Days.parse("2026-10-08", calendar: calendar))
        XCTAssertEqual(pickups.last?.date, Days.parse("2026-12-22", calendar: calendar))
        XCTAssertEqual(pickups.map { WasteCategory.classify($0.name) }, [.paper, .residual, .organic, .packaging, .packaging])
    }

    func testLabel() {
        let provider = RheinlandPfalzPortalsProvider(service: "donnersberg")
        XCTAssertEqual(provider.label(for: [SelectionOption(id: "orte/Kirchheimbolanden", title: "Kirchheimbolanden"),
                                            SelectionOption(id: "Kirchheimbolanden/Amtsstrasse", title: "Amtsstraße")]),
                       "Kirchheimbolanden, Amtsstraße")
        XCTAssertEqual(provider.displayName, "Donnersbergkreis")
    }

    /// Ganzer Ablauf mit nachgestellten Antworten: prüft URLs und den Accept-Kopf (ohne `text/html` liefert die Web-App 404).
    func testFlowAgainstStub() async throws {
        let provider = RheinlandPfalzPortalsProvider(service: "donnersberg", client: HTTPClient(session: DonnersbergStub.session()))

        let places = try await provider.nextStep(after: [])
        let town = try XCTUnwrap(places?.options.first { $0.title == "Kirchheimbolanden" })
        let streets = try await provider.nextStep(after: [town])
        XCTAssertEqual(streets?.title, SelectionStep.streetTitle)
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Amtsstraße" })
        let done = try await provider.nextStep(after: [town, street])
        XCTAssertNil(done)

        // Ort ohne Straßenliste: nach der Ortswahl fertig.
        let village = try XCTUnwrap(places?.options.first { $0.title == "Albisheim" })
        let villageDone = try await provider.nextStep(after: [village])
        XCTAssertNil(villageDone)

        let pickups = try await provider.pickups(for: [town, street], calendar: calendar)
        XCTAssertEqual(pickups.count, 5, "Folgejahr fehlt (404) – aktuelles Jahr reicht")

        let requests = DonnersbergStub.requests()
        let base = "https://abfallapp.softwareentwicklung-roth.de"
        XCTAssertTrue(requests.contains { $0.url == "\(base)/web/KIB/de/kalender" })
        XCTAssertTrue(requests.contains { $0.url == "\(base)/web/KIB/de/kalender/orte/Kirchheimbolanden/strassen" })
        XCTAssertTrue(requests.contains { $0.url == "\(base)/web/KIB/de/kalender/Kirchheimbolanden/Amtsstrasse/muellarten" })
        for request in requests where request.url.contains("/web/") {
            XCTAssertTrue(request.accept.contains("text/html"), request.url)
        }
        let year = calendar.component(.year, from: Date())
        let query = "abfallart_Restabfall=on&abfallart_Bioabfall=on&abfallart_Papier=on&abfallart_GelberSack=on"
        XCTAssertTrue(requests.contains { $0.url == "\(base)/\(year)/KIB/Kirchheimbolanden/Amtsstrasse/ics/de?\(query)" })
        XCTAssertTrue(requests.contains { $0.url == "\(base)/\(year + 1)/KIB/Kirchheimbolanden/Amtsstrasse/ics/de?\(query)" })
    }

    func testTownWithStreetsNeedsStreet() async {
        let provider = RheinlandPfalzPortalsProvider(service: "donnersberg", client: HTTPClient(session: DonnersbergStub.session()))
        do {
            _ = try await provider.pickups(for: [SelectionOption(id: "orte/Eisenberg", title: "Eisenberg")], calendar: calendar)
            XCTFail("Fehler erwartet")
        } catch {}
    }

    func testLiveDonnersberg() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = RheinlandPfalzPortalsProvider(service: "donnersberg")
        let places = try await provider.nextStep(after: [])
        XCTAssertGreaterThan(places?.options.count ?? 0, 150)

        let village = try XCTUnwrap(places?.options.first { $0.title == "Albisheim" })
        let villageNext = try await provider.nextStep(after: [village])
        XCTAssertNil(villageNext)
        let villagePickups = try await provider.pickups(for: [village], calendar: calendar)
        XCTAssertGreaterThanOrEqual(villagePickups.count, 5)
        XCTAssertTrue(villagePickups.allSatisfy { WasteCategory.classify($0.name) != .other }, "\(villagePickups.map(\.name))")
        print("Donnersberg Albisheim:", villagePickups.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })

        let town = try XCTUnwrap(places?.options.first { $0.title == "Kirchheimbolanden" })
        let streets = try await provider.nextStep(after: [town])
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Amtsstraße" })
        let pickups = try await provider.pickups(for: [town, street], calendar: calendar)
        XCTAssertGreaterThanOrEqual(pickups.count, 5)
        print("Donnersberg Kirchheimbolanden, Amtsstraße:", pickups.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })
    }
}

/// Nachgestellte Web-App für die Tests; antwortet wie das Original ohne `Accept: text/html` mit 404.
final class DonnersbergStub: URLProtocol {
    struct Seen { let url: String; let accept: String }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DonnersbergStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "abfallapp.softwareentwicklung-roth.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let accept = request.value(forHTTPHeaderField: "Accept") ?? ""
        Self.lock.lock()
        Self.seen.append(Seen(url: url, accept: accept))
        Self.lock.unlock()

        let path = request.url?.path ?? ""
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        var body: String?
        if path.hasPrefix("/web/") && !accept.contains("text/html") { body = nil }
        else if path == "/web/KIB/de/kalender" { body = DonnersbergTests.places }
        else if path.hasSuffix("/strassen") { body = DonnersbergTests.streets }
        else if path.hasSuffix("/muellarten") { body = DonnersbergTests.types }
        else if path.hasPrefix("/\(thisYear)/KIB/") && path.hasSuffix("/ics/de") { body = DonnersbergTests.ics }
        let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/html; charset=UTF-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "Not Found").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
