import XCTest
@testable import TonneCore

/// Gemeinde-Prüfung 16.11.2026: Ortslisten mit Einträgen, die nur Feiertage oder gar keine Termine liefern, aber unter dem Namen
/// der gesuchten Gemeinde stehen. Die Suche wählte sie vor und führte in eine Adresse ohne Termine.
final class PlatzhalterOrteTests: XCTestCase {
    func testAwidoHidesPlaceholderPlaces() async throws {
        let gotha = AwidoProvider(customer: "gotha", client: HTTPClient(session: PlatzhalterStub.session()))
        let first = try await gotha.nextStep(after: [])
        let step = try XCTUnwrap(first)
        XCTAssertEqual(step.options.map(\.title), ["Friedrichroda", "Nessetal OT Hochheim"])
        XCTAssertNil(step.preselection(for: "Nessetal"), "keine Vorauswahl des Platzhalters, der Nutzer wählt seinen Ortsteil")
        // Neustadt a.d. Waldnaab: „Landkreis“ führt nur Feiertage
        XCTAssertTrue(AwidoProvider.isPlaceholder(customer: "neustadt", place: "Landkreis"))
        // Gegenprobe: in anderen Kreisen bleibt ein gleichnamiger Ort
        XCTAssertFalse(AwidoProvider.isPlaceholder(customer: "gifhorn", place: "Nessetal"))
    }

    func testSpreeNeisseOffersTheTownOfPeitzNotTheAmt() async throws {
        let provider = BrandenburgPortalsProvider(service: "spn", client: HTTPClient(session: PlatzhalterStub.session()))
        let first = try await provider.nextStep(after: [])
        let step = try XCTUnwrap(first)
        XCTAssertEqual(step.options.map(\.title), ["Drachhausen", "Gemeinden des Amtes Peitz", "Peitz/Picnjo"])
        XCTAssertEqual(step.preselection(for: "Peitz")?.id, "592")
    }

    func testKWUStreetWithOnlyEmptyObjectIsReported() async throws {
        let provider = BrandenburgPortalsProvider(service: "kwu", client: HTTPClient(session: PlatzhalterStub.session()))
        let ort = SelectionOption(id: "10222001", title: "Vogelsang")
        do {
            _ = try await provider.nextStep(after: [ort, SelectionOption(id: "Waldessaum", title: "Waldessaum")])
            XCTFail("Straße ohne Abfuhr muss gemeldet werden")
        } catch let error as ProviderError {
            XCTAssertTrue(error.errorDescription?.contains("keine Abfuhr") == true, error.errorDescription ?? "")
        }
        // Gegenprobe: Straße mit Hausnummern
        let step = try await provider.nextStep(after: [ort, SelectionOption(id: "Am Anger", title: "Am Anger")])
        XCTAssertEqual(step?.options.map(\.title), ["2", "4"])
    }
}

final class PlatzhalterStub: URLProtocol {
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PlatzhalterStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        var body = ""
        if url.contains("getPlaces") {
            body = #"[{"key":"a","value":"Friedrichroda"},{"key":"b","value":"Nessetal"},{"key":"c","value":"Nessetal OT Hochheim"}]"#
        } else if url.hasSuffix("/termine/abfuhrtermine.html") {
            body = #"<select name="group"><option value="/termine/abfuhrtermine/2026/576.html">Drachhausen</option><option value="/termine/abfuhrtermine/2026/8.html">Peitz</option><option value="/termine/abfuhrtermine/2026/592.html">Peitz/Picnjo</option></select>"#
        } else if url.contains("kal_str2ort.php") {
            body = url.contains("Waldessaum") ? #"<option value="+++1">leer</option>"# : #"<option value="+++2">2</option><option value="+++4">4</option>"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
