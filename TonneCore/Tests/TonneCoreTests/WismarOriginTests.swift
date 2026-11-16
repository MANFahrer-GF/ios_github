import XCTest
@testable import TonneCore

/// Gemeinde-Prüfung 16.11.2026: Das EVB-Formular antwortet ohne Origin/Referer mit HTTP 400 – die App holte in Wismar keine Termine.
final class WismarOriginTests: XCTestCase {
    func testWismarSendsOriginAndReferer() async throws {
        let provider = NRWPortalsProvider(service: "wismar", client: HTTPClient(session: WismarStub.session()))
        let step = try await provider.nextStep(after: [SelectionOption(id: "Am Markt", title: "Am Markt")])
        XCTAssertNil(step, "ohne Hausnummernregel ist die Auswahl fertig")
        XCTAssertEqual(WismarStub.lastOrigin, "https://www.evb-wismar.de")
    }
}

final class WismarStub: URLProtocol {
    nonisolated(unsafe) static var lastOrigin: String?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WismarStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.evb-wismar.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let origin = request.value(forHTTPHeaderField: "Origin"), referer = request.value(forHTTPHeaderField: "Referer")
        Self.lastOrigin = origin
        let ok = origin != nil && referer?.hasPrefix("https://www.evb-wismar.de/") == true
        let body = ok ? #"<div class="collection-date__result">Restmüll Tonne Freitag, ungerade Woche</div>Navigation überspringen"# : "Bad Request"
        let response = HTTPURLResponse(url: request.url!, statusCode: ok ? 200 : 400, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Gemeinde-Prüfung 16.11.2026: Die Kreis-App Rastatt nennt Bühl selbst zuständig und lieferte dort keine Termine.
/// Die Stadt hat einen eigenen digitalen Abfallkalender (Straße → Abfuhrbezirk → Abfuhrtage).
final class BuehlTests: XCTestCase {
    func testBuehlParsesDaysFromTheCurrentYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let pickups = NRWPortalsProvider.buehlPickups([
            ("2025-12-30", ["Restabfall"]),
            ("2026-11-20", ["Bioabfall (einpacken in Zeitungspapier ist erlaubt)", "Gelbe Tonne (Verpackungsmaterial)"]),
        ], fromYear: 2026, calendar: calendar)
        XCTAssertEqual(pickups.map(\.name).sorted(), ["Bioabfall", "Gelbe Tonne"])
        XCTAssertEqual(pickups.first.map { calendar.component(.day, from: $0.date) }, 20)
    }

    func testBuehlIsServedByTheCityCalendar() throws {
        let buehl = try XCTUnwrap(ProviderCatalog.checkPlace("Bühl").first { $0.district == "Landkreis Rastatt" })
        XCTAssertEqual(buehl.entries.map(\.serviceKey), ["buehl"])
        // Gegenprobe: Bühlertal bleibt bei der Kreis-App
        let buehlertal = try XCTUnwrap(ProviderCatalog.checkPlace("Bühlertal").first)
        XCTAssertTrue(buehlertal.entries.contains { $0.serviceKey == "de.k4systems.awbrastatt" })
    }
}
