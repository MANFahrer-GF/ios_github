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

    /// Prüfbefund 4 (16.11.): Viele Straßen teilen einen Abfuhrbezirk; die Kennung muss je Straße eindeutig sein
    /// (SwiftUI-Liste), der Abruf läuft weiter über den Bezirk.
    func testBuehlStreetOptionsHaveUniqueIDsAndFetchByDistrict() async throws {
        let api = NRWPortalsProvider.buehlAPI
        let streets = #"{"records":[{"_id":1,"name":"Hauptstraße","district":{"_id":7,"code":"B2"}},{"_id":2,"name":"Schwanenstraße","district":{"_id":7,"code":"B2"}}]}"#
        let days = #"{"collectionDays":[{"date":"2026-11-20","garbageTypes":[{"description":"Restabfall"}]}]}"#
        let pages = [api + "/main.Street?relations[]=district&limit=1000": streets,
                     api + "/main.Street?relations%5B%5D=district&limit=1000": streets,
                     api + "/main.District/7?relations[]=collectionDays.garbageTypes": days,
                     api + "/main.District/7?relations%5B%5D=collectionDays.garbageTypes": days]
        let provider = NRWPortalsProvider(service: "buehl", client: HTTPClient(session: EinzelStub.session(pages)))
        let next = try await provider.nextStep(after: [])
        let step = try XCTUnwrap(next)
        XCTAssertEqual(step.options.count, 2)
        XCTAssertEqual(Set(step.options.map(\.id)).count, step.options.count, "doppelte Kennungen")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let option = try XCTUnwrap(step.options.first { $0.title == "Schwanenstraße" })
        let pickups = try await provider.pickups(for: [option], calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Restabfall"])
        XCTAssertTrue(EinzelStub.requested().contains { $0.contains("/main.District/7?") }, "Abruf über den Bezirk")
    }

    func testBuehlIsServedByTheCityCalendar() throws {
        let buehl = try XCTUnwrap(ProviderCatalog.checkPlace("Bühl").first { $0.district == "Landkreis Rastatt" })
        XCTAssertEqual(buehl.entries.map(\.serviceKey), ["buehl"])
        // Gegenprobe: Bühlertal bleibt bei der Kreis-App
        let buehlertal = try XCTUnwrap(ProviderCatalog.checkPlace("Bühlertal").first)
        XCTAssertTrue(buehlertal.entries.contains { $0.serviceKey == "de.k4systems.awbrastatt" })
    }
}
