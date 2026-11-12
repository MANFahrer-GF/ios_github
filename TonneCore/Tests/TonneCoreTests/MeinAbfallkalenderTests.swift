import XCTest
@testable import TonneCore

/// mein-abfallkalender.online: Straße in der App wählen statt iCal-Link besorgen (Portal-Prüfung 12.11.2026: 78 Orte nur mit
/// Kopierlink nutzbar, den das Portal nur per E-Mail mit Rechenaufgabe verschickt). Gekürzte echte Antworten (Eppstein).
final class MeinAbfallkalenderTests: XCTestCase {
    static let start = """
    <form id="search_form" action="/" method="post">
    <select id="street_id" name="street_id">
                          <option value="19745">Adolf-Guckers-Weg, Eppstein</option>
                          <option value="19746">Albert-Schweitzer-Stra&szlig;e, Bremthal</option>
    </select>
    <select id="filter_period" name="filter_period"><option value="next_10">Die nächsten 10 Termine</option><option value="all.2026">Übersicht 2026</option><option value="all.2027">Übersicht 2027</option><option value="01.2026">Januar 2026</option></select>
    """

    static func result(_ year: Int) -> String {
        """
        <table id="dates_table" cellspacing="0"><caption id="results_headline">Übersicht \(year)</caption>
        <tr class="month"><th colspan="5"><h3>Januar \(year)</h3></th></tr>
        <tr bgcolor="#FFFFFF" class="dates"> <td class="waste_type"><div class="DSD"></div></td> <td class="nowrap">Gelber Sack</td> <td>Samstag</td> <td>03.01.\(year)</td> <td class="no_print"> </td> </tr>
        <tr bgcolor="#F6F6F8" class="dates"> <td class="waste_type"><div class="WeSt"></div></td> <td class="nowrap"><a href="abfallarten#WeSt">Wertstoffhof</a></td> <td>Samstag</td> <td>03.01.\(year)</td> <td class="no_print"> </td> </tr>
        <tr bgcolor="#F6F6F8" class="dates"> <td colspan="5"><p class="small"><em><strong>Info:</strong> 09:00 - 14:00 Uhr</em></p></td> </tr>
        <tr bgcolor="#FFFFFF" class="dates"> <td class="waste_type"><div class="RM"></div></td> <td class="nowrap">Restm&uuml;ll</td> <td>Mittwoch</td> <td>07.12.\(year)</td> <td class="no_print"> </td> </tr>
        </table>
        """
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func testStreetListInsteadOfPasteField() async throws {
        let provider = ICSURLProvider(url: "https://eppstein.mein-abfallkalender.online", client: HTTPClient(session: MAKStub.session()))
        let next = try await provider.nextStep(after: [])
        let step = try XCTUnwrap(next)
        XCTAssertEqual(step.input, .list, "Straßenliste statt Feld zum Einfügen eines Links")
        XCTAssertEqual(step.options.map(\.title), ["Adolf-Guckers-Weg, Eppstein", "Albert-Schweitzer-Straße, Bremthal"])
        XCTAssertEqual(step.options.first?.id, "mak:19745")
        XCTAssertTrue(MAKStub.requests().allSatisfy { $0.agent.contains("Macintosh") }, "Desktop-Kennung, sonst leitet das Portal auf die Handy-Ansicht um")
    }

    func testPickupsFromYearOverviewsWithoutRecyclingCentre() async throws {
        let provider = ICSURLProvider(url: "https://eppstein.mein-abfallkalender.online", client: HTTPClient(session: MAKStub.session()))
        let pickups = try await provider.pickups(for: [SelectionOption(id: "mak:19746", title: "Albert-Schweitzer-Straße, Bremthal")], calendar: calendar)
        let year = calendar.component(.year, from: Date())
        XCTAssertFalse(pickups.contains { $0.name.contains("Wertstoffhof") }, "Öffnungszeiten sind keine Abfuhr")
        XCTAssertTrue(pickups.contains { $0.name == "Restmüll" && Days.iso($0.date, calendar: calendar) == "\(year)-12-07" })
        // Nur Jahresübersichten ab dem laufenden Jahr, je Straße
        let bodies = MAKStub.requests().filter { $0.method == "POST" }.map(\.body)
        XCTAssertTrue(bodies.allSatisfy { $0.contains("street_id=19746") })
        XCTAssertTrue(bodies.contains { $0.contains("filter_period=all.\(year)") })
    }

    /// Früher eingefügte iCal-Links laufen weiter über den ICS-Weg.
    func testPastedLinkStillUsesICS() {
        XCTAssertFalse(ICSURLProvider(url: "https://eppstein.mein-abfallkalender.online").isDirectLink)
        XCTAssertTrue(ICSURLProvider(url: "https://eppstein.mein-abfallkalender.online").isMeinAbfallkalender)
        XCTAssertFalse(ICSURLProvider(url: "https://example.org/kalender.ics").isMeinAbfallkalender)
    }
}

final class MAKStub: URLProtocol {
    struct Seen { let method: String; let agent: String; let body: String }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MAKStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix("mein-abfallkalender.online") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let text = String(decoding: body, as: UTF8.self)
        Self.lock.lock()
        Self.seen.append(Seen(method: request.httpMethod ?? "GET", agent: request.value(forHTTPHeaderField: "User-Agent") ?? "", body: text))
        Self.lock.unlock()
        let year = Calendar.current.component(.year, from: Date())
        let html: String
        if request.httpMethod == "POST" {
            html = MeinAbfallkalenderTests.result(text.contains("all.\(year + 1)") ? year + 1 : year)
        } else {
            html = MeinAbfallkalenderTests.start.replacingOccurrences(of: "2026", with: String(year)).replacingOccurrences(of: "2027", with: String(year + 1))
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
