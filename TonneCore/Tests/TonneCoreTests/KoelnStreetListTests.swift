import XCTest
@testable import TonneCore

/// AWB Köln: Die Adress-Suche verlangt eine Hausnummer. Prüflauf 12.11.2026: Auf eine getippte Straße folgte ein Textfeld
/// für die Hausnummer, die Auswahl über eine Straßenliste (und der Prüflauf) kam nie zustande. Gekürzte echte Antworten.
final class KoelnStreetListTests: XCTestCase {
    private func provider() -> AWBKoelnProvider { AWBKoelnProvider(client: HTTPClient(session: KoelnStub.session())) }
    private let typed = SelectionOption(id: "Haupt", title: "Haupt")

    func testStreetTextLeadsToStreetList() async throws {
        let next = try await provider().nextStep(after: [typed])
        let step = try XCTUnwrap(next)
        XCTAssertEqual(step.input, .list)
        XCTAssertEqual(step.options.map(\.title), ["Hauptstr. Ro", "Hauptstr."])
        XCTAssertEqual(step.options.first?.id, "str:4714")
    }

    func testHouseNumberThenAddress() async throws {
        let street = SelectionOption(id: "str:4714", title: "Hauptstr. Ro")
        let p = provider()
        let numberStep = try await p.nextStep(after: [typed, street])
        XCTAssertEqual(try XCTUnwrap(numberStep).input, .text)
        let addresses = try await p.nextStep(after: [typed, street, SelectionOption(id: "3", title: "3")])
        let step = try XCTUnwrap(addresses)
        XCTAssertEqual(step.options.map(\.id), ["addr:4714:3"], "Nur die gewählte Straße, nicht gleichnamige Anfänge")
        let last = try await p.nextStep(after: [typed, street, SelectionOption(id: "3", title: "3"), step.options[0]])
        XCTAssertNil(last)
    }
}

final class KoelnStub: URLProtocol {
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KoelnStub.self]
        return URLSession(configuration: config)
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.awbkoeln.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = request.url?.query ?? ""
        func row(_ name: String, _ code: String, _ number: String) -> String {
            #"{"street_name":"\#(name)","building_number":"\#(number)","street_code":"\#(code)","district":"Rodenkirchen","zipcode":"50996"}"#
        }
        var rows: [String] = []
        if query.contains("building_number=1&") || query.hasSuffix("building_number=1") { rows = [row("Hauptstr. Ro", "4714", "1")] }
        if query.contains("building_number=2") { rows = [row("Hauptstr.", "13", "2")] }
        if query.contains("building_number=3") { rows = [row("Hauptstr. Ro", "4714", "3"), row("Hauptstr.", "13", "3")] }
        let body = Data(#"{"data":[\#(rows.joined(separator: ","))]}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
