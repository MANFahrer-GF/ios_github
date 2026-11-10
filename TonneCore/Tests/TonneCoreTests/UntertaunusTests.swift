import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// EAW Rheingau-Taunus-Kreis (Untertaunus): Straßenliste als JSON → Gemeinde → Ortsteil → Straße → ICS je Straße.
/// Echte, gekürzte Antworten vom November 2026. Live-Test nur mit TONNE_LIVE=1.
final class UntertaunusTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    // POST /abfallsammlung/abfuhrtermine/autocomplete?type=1660824331 (gekürzt)
    static let streets = #"""
    [{"id":1,"street":"Am Buttegraben","districtId":7,"district":"Daisbach","cityId":1,"city":"Aarbergen"},
     {"id":2,"street":"Am Silberberg","districtId":7,"district":"Daisbach","cityId":1,"city":"Aarbergen"},
     {"id":382,"street":"Hessenstraße","districtId":121,"district":"Görsroth","cityId":5,"city":"Hünstetten"},
     {"id":2150,"street":"Ahornstraße","districtId":101,"district":"Bermbach","cityId":10,"city":"Waldems"},
     {"id":2166,"street":"Hessenstraße","districtId":101,"district":"Bermbach","cityId":10,"city":"Waldems"}]
    """#

    // /abfallsammlung/abfuhrtermine/ics/strasse-2166/feed.ics (gekürzt)
    static let ics = """
    BEGIN:VCALENDAR
    VERSION:2.0
    X-WR-CALNAME:EAW Abfallkalender online für Hessenstraße
    PRODID:-//TYPO3/NONSGML Calendar (calendar) extended V1.0//EN
    METHOD:PUBLISH
    BEGIN:VEVENT
    UID:cc0b683bcc672a32da314925c7161578@eaw-rtk.de
    DTSTART;VALUE=DATE:20261112
    DTEND;VALUE=DATE:20261112
    LOCATION: Hessenstraße – Waldems – Bermbach
    SUMMARY:Biotonne, Gelbe Tonne, Restmülltonne
    END:VEVENT
    BEGIN:VEVENT
    UID:cc0b683bcc672a32da314925c7161579@eaw-rtk.de
    DTSTART;VALUE=DATE:20261126
    DTEND;VALUE=DATE:20261126
    LOCATION: Hessenstraße – Waldems – Bermbach
    SUMMARY:Gelbe Tonne, Altpapiertonne, Tonnentausch
    END:VEVENT
    BEGIN:VEVENT
    UID:cc0b683bcc672a32da314925c7161580@eaw-rtk.de
    DTSTART;VALUE=DATE:20261201
    DTEND;VALUE=DATE:20261201
    LOCATION: Hessenstraße – Waldems – Bermbach
    SUMMARY:Tonnentausch
    END:VEVENT
    END:VCALENDAR

    """

    func testPickupsSplitAndDropBinSwap() {
        let pickups = SuedwestPortalsProvider.untertaunusPickups(Self.ics, calendar: calendar)
        XCTAssertEqual(pickups.map { "\(Days.iso($0.date)) \($0.name)" }.sorted(),
                       ["2026-11-12 Biotonne", "2026-11-12 Gelbe Tonne", "2026-11-12 Restmülltonne",
                        "2026-11-26 Altpapiertonne", "2026-11-26 Gelbe Tonne"],
                       "je Fraktion ein Termin; „Tonnentausch“ ist keine Abfuhr")
        XCTAssertEqual(Set(pickups.map { WasteCategory.classify($0.name) }), [.organic, .packaging, .residual, .paper])
    }

    /// Ganzer Ablauf mit nachgestellten Antworten: gleichnamige Straßen zweier Gemeinden bleiben getrennt.
    func testFlowAgainstStub() async throws {
        let provider = SuedwestPortalsProvider(service: "untertaunus", client: HTTPClient(session: UntertaunusStub.session()))
        let towns = try await provider.nextStep(after: [])
        XCTAssertEqual(towns?.options.map(\.title), ["Aarbergen", "Hünstetten", "Waldems"])
        let town = try XCTUnwrap(towns?.options.first { $0.title == "Waldems" })
        let districts = try await provider.nextStep(after: [town])
        XCTAssertEqual(districts?.options.map(\.title), ["Bermbach"])
        let district = try XCTUnwrap(districts?.options.first)
        let streets = try await provider.nextStep(after: [town, district])
        XCTAssertEqual(streets?.options.map(\.title), ["Ahornstraße", "Hessenstraße"])
        let street = try XCTUnwrap(streets?.options.last)
        XCTAssertEqual(street.id, "2166", "nicht die Hessenstraße in Hünstetten (382)")
        let done = try await provider.nextStep(after: [town, district, street])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [town, district, street], calendar: calendar)
        XCTAssertEqual(pickups.count, 5)
        XCTAssertEqual(provider.label(for: [town, district, street]), "Waldems, Bermbach, Hessenstraße")
        let requests = UntertaunusStub.requests()
        XCTAssertTrue(requests.contains("POST https://www.eaw-rheingau-taunus.de/abfallsammlung/abfuhrtermine/autocomplete?type=1660824331"), "\(requests)")
        XCTAssertTrue(requests.contains("GET https://www.eaw-rheingau-taunus.de/abfallsammlung/abfuhrtermine/ics/strasse-2166/feed.ics"), "\(requests)")
    }

    func testPickupsNeedStreet() async {
        let provider = SuedwestPortalsProvider(service: "untertaunus", client: HTTPClient(session: UntertaunusStub.session()))
        do {
            _ = try await provider.pickups(for: [SelectionOption(id: "c:10", title: "Waldems")], calendar: calendar)
            XCTFail("Fehler erwartet")
        } catch {}
    }

    func testLiveUntertaunus() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = SuedwestPortalsProvider(service: "untertaunus")
        let towns = try await provider.nextStep(after: [])
        XCTAssertEqual(towns?.options.map(\.title), ["Aarbergen", "Bad Schwalbach", "Heidenrod", "Hohenstein", "Hünstetten", "Idstein",
                                                      "Niedernhausen", "Schlangenbad", "Taunusstein", "Waldems"])
        for name in ["Idstein", "Aarbergen"] {
            let town = try XCTUnwrap(towns?.options.first { $0.title == name })
            let districts = try await provider.nextStep(after: [town])
            let district = try XCTUnwrap(districts?.options.first)
            let streets = try await provider.nextStep(after: [town, district])
            let street = try XCTUnwrap(streets?.options.first)
            let pickups = try await provider.pickups(for: [town, district, street], calendar: calendar)
            XCTAssertGreaterThanOrEqual(pickups.count, 3)
            XCTAssertTrue(pickups.allSatisfy { WasteCategory.classify($0.name) != .other }, "\(pickups.map(\.name))")
            print("Untertaunus \(name), \(district.title), \(street.title):", pickups.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })
        }
    }
}

/// Nachgestellte Webseite des EAW für die Tests.
final class UntertaunusStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UntertaunusStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.eaw-rheingau-taunus.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"
        Self.lock.lock()
        Self.seen.append("\(method) \(url)")
        Self.lock.unlock()

        let path = request.url?.path ?? ""
        var body: String?
        if path.hasSuffix("/autocomplete") && method == "POST" { body = UntertaunusTests.streets }
        else if path.hasSuffix("/ics/strasse-2166/feed.ics") { body = UntertaunusTests.ics }
        let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/plain; charset=UTF-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "Not Found").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
