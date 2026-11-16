import XCTest
@testable import TonneCore

/// Kreis Groß-Gerau (C-Trace) fragt Ort → Ortsteil → Straße → Hausnummer. Ohne Ortsteil gab es für Riedstadt und Trebur
/// weder Hausnummern noch einen Plan (Tester Dirk, Riedstadt › Haydnstraße › 16, 15.11.2026).
final class GrossGerauDistrictsTests: XCTestCase {
    private let key = "grossgeraulandkreis-abfallkalender"
    private func provider() -> CTraceProvider { CTraceProvider(service: key, client: HTTPClient(session: GrossGerauStub.session())) }

    func testPlacesWithSeveralDistrictsAreListedAsPlaceSlashDistrict() async throws {
        let step = try await provider().nextStep(after: [])
        XCTAssertEqual(step?.options.map(\.title), ["Nauheim", "Riedstadt / ohne Ortsteil", "Riedstadt / Erfelden", "Riedstadt / Goddelau"])
    }

    func testDistrictIsSentForStreetsHouseNumbersAndCalendar() async throws {
        let p = provider()
        let place = SelectionOption(id: "Riedstadt / Erfelden", title: "Riedstadt / Erfelden")
        let streets = try await p.nextStep(after: [place])
        XCTAssertEqual(streets?.options.map(\.title), ["Haydnstraße"])
        let street = SelectionOption(id: "Haydnstraße", title: "Haydnstraße")
        let numbers = try await p.nextStep(after: [place, street])
        XCTAssertEqual(numbers?.options.map(\.title), ["14", "16"])
        let pickups = try await p.pickups(for: [place, street, SelectionOption(id: "16", title: "16")], calendar: .current)
        XCTAssertFalse(pickups.isEmpty)
        let seen = GrossGerauStub.requests()
        XCTAssertTrue(seen.contains { $0.contains("/Strassen?ort=Riedstadt&ortsteil=Erfelden") })
        XCTAssertTrue(seen.contains { $0.contains("/Hausnummern?ort=Riedstadt&ortsteil=Erfelden&strasse=") })
        let cal = try XCTUnwrap(seen.first { $0.contains("abfallkalender/cal?") })
        XCTAssertTrue(cal.contains("Ortsteil=Erfelden") && cal.contains("Ort=Riedstadt"))
        XCTAssertFalse(cal.contains("Gemeinde="))
    }

    /// Orte mit nur einem Ortsteil und vor 2.1.0 gespeicherte Adressen (drei Werte) laufen wie bisher – ohne `ortsteil`.
    func testSingleDistrictPlaceWorksWithoutDistrict() async throws {
        let p = provider()
        let place = SelectionOption(id: "Nauheim", title: "Nauheim")
        let pickups = try await p.pickups(for: [place, SelectionOption(id: "a", title: "Adam-Opel-Straße"), SelectionOption(id: "1", title: "1")], calendar: .current)
        XCTAssertFalse(pickups.isEmpty)
        let cal = try XCTUnwrap(GrossGerauStub.requests().first { $0.contains("abfallkalender/cal?") })
        XCTAssertFalse(cal.contains("Ortsteil="))
    }

    /// Alte Adresse „Riedstadt“ ohne Ortsteil: Hinweis auf den Ortsteil statt „Nachbar-Hausnummer versuchen“.
    func testOldAddressWithoutDistrictExplainsWhatToDo() async {
        do {
            _ = try await provider().pickups(for: ["Riedstadt", "Haydnstraße", "16"].map { SelectionOption(id: $0, title: $0) }, calendar: .current)
            XCTFail("ohne Ortsteil darf es keinen Plan geben")
        } catch let ProviderError.noData(message) {
            XCTAssertTrue(message.contains("Ortsteil"), message)
            XCTAssertFalse(message.contains("Nachbar"), message)
        } catch { XCTFail("\(error)") }
    }

    /// Die Suche „Erfelden“ (→ Gemeinde Riedstadt) wählt im Ort-Schritt gleich „Riedstadt / Erfelden“.
    func testSearchForDistrictPreselectsPlaceWithDistrict() {
        let step = SelectionStep(title: SelectionStep.cityTitle, options: ["Nauheim", "Riedstadt / ohne Ortsteil", "Riedstadt / Erfelden", "Riedstadt / Goddelau"].map { SelectionOption(id: $0, title: $0) })
        XCTAssertEqual(step.preselection(for: "Riedstadt", query: "Erfelden")?.title, "Riedstadt / Erfelden")
        XCTAssertEqual(step.preselection(for: "Riedstadt", query: "Riedstadt-Erfelden")?.title, "Riedstadt / Erfelden")
        XCTAssertEqual(step.preselection(for: "Riedstadt", query: "erfelden (riedstadt)")?.title, "Riedstadt / Erfelden")
        XCTAssertNil(step.preselection(for: "Riedstadt", query: "Riedstadt"), "ohne Ortsteil die Liste zeigen")
        XCTAssertEqual(step.preselection(for: "Nauheim", query: "Nauheim")?.title, "Nauheim")
    }

    /// Live: Dirks Adresse und je Ort des Kreises die erste Straße mit erster Hausnummer müssen einen Plan liefern.
    func testLiveEveryPlaceOfTheDistrictHasAPlan() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_LIVE"] != nil, "TONNE_LIVE nicht gesetzt")
        let p = CTraceProvider(service: key)
        let erfelden = SelectionOption(id: "Riedstadt / Erfelden", title: "Riedstadt / Erfelden")
        let dirk = try await p.pickups(for: [erfelden, SelectionOption(id: "Haydnstraße", title: "Haydnstraße"), SelectionOption(id: "16", title: "16")], calendar: .current)
        XCTAssertFalse(dirk.isEmpty, "Riedstadt / Erfelden / Haydnstraße 16")
        let placeStep = try await p.nextStep(after: [])
        let places = try XCTUnwrap(placeStep?.options)
        XCTAssertTrue(places.contains { $0.title.hasPrefix("Trebur / ") }, "Trebur ohne Ortsteile")
        var failed: [String] = []
        for place in places where !place.title.hasSuffix("ohne Ortsteil") {
            guard let street = try await p.nextStep(after: [place])?.options.first,
                  let number = try await p.nextStep(after: [place, street])?.options.first else { failed.append("\(place.title): keine Straße/Hausnummer"); continue }
            do { if try await p.pickups(for: [place, street, number], calendar: .current).isEmpty { failed.append("\(place.title): leer") } }
            catch { failed.append("\(place.title) / \(street.title) \(number.title): \(error)") }
        }
        XCTAssertEqual(failed, [])
    }

    /// Wächter: Hat ein C-Trace-Portal im Formular einen Ortsteil-Schritt, muss der Dienst `districts` setzen – und umgekehrt.
    /// So fällt ein neues oder umgebautes Portal auf, bevor ganze Orte still scheitern.
    func testLiveDistrictStepMatchesEveryPortalForm() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_LIVE"] != nil, "TONNE_LIVE nicht gesetzt")
        var mismatches: [String] = []
        for (key, service) in CTraceProvider.services where service.retired == nil {
            let page = try await HTTPClient().string("https://\(service.subdomain).c-trace.de/\(service.name)/Abfallkalender")
            let formHasDistrict = page.contains("id=\"Ortsteil\"")
            if formHasDistrict != service.districts { mismatches.append("\(key): Formular \(formHasDistrict ? "mit" : "ohne") Ortsteil") }
        }
        XCTAssertEqual(mismatches, [])
    }
}

final class GrossGerauStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrossGerauStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix("c-trace.de") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url?.absoluteString.removingPercentEncoding ?? ""
        Self.lock.lock(); Self.seen.append(url); Self.lock.unlock()
        let answers: [(String, String)] = [
            ("/Orte", #"["Nauheim","Riedstadt"]"#),
            ("/Ortsteil?ort=Nauheim", #"["Nauheim"]"#),
            ("/Ortsteil?ort=Riedstadt", #"["ohne Ortsteil","Erfelden","Goddelau"]"#),
            ("/Strassen?ort=Riedstadt&ortsteil=Erfelden", #"["Haydnstraße"]"#),
            ("/Hausnummern?ort=Riedstadt&ortsteil=Erfelden&strasse=Haydnstraße", #"["14","16"]"#),
        ]
        var body = answers.first { url.hasSuffix($0.0) }?.1
        var status = body == nil ? 404 : 200
        if url.contains("abfallkalender/cal?") {
            // Wie das echte Portal: Riedstadt nur mit Ortsteil, sonst 500
            let ok = url.contains("Ort=Nauheim") || url.contains("Ortsteil=Erfelden")
            body = ok ? CTraceListsTests.bremenICS : "<title>Runtime Error</title>"; status = ok ? 200 : 500
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": status == 200 ? "application/json" : "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "<html>404</html>").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
