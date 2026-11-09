import XCTest
@testable import TonneCore

/// Funde aus der Prüfung aller Orte auf fehlende oder falsche Straßenlisten (November 2026),
/// jeweils mit echten, gekürzten Portalantworten.
final class StreetAuditTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    // MARK: - Landkreis Cham

    func testChamCompletesLiestJSONForm() {
        // Antwort von loadCompletes.php seit dem Umbau des Portals, November 2026
        let html = #"<script>complete = [{"label":"93473 Arnschwang","value":"1"},{"label":"93444 Bad Kötzting","value":"3"},{"label":"Arnschwanger Str.","value":""}];</script>"#
        let items = BayernPortalsProvider.chamCompletes(html)
        XCTAssertEqual(items.map(\.label), ["93473 Arnschwang", "93444 Bad Kötzting", "Arnschwanger Str."])
        XCTAssertEqual(items.map(\.value), ["1", "3", ""])
    }

    func testChamCompletesLiestAlteForm() {
        let html = #"complete = [{ label: '93474 Arrach', value: '2' }, { label: 'Zum \'Anger\'', value: '' }];"#
        let items = BayernPortalsProvider.chamCompletes(html)
        XCTAssertEqual(items.map(\.label), ["93474 Arrach", "Zum 'Anger'"])
        XCTAssertEqual(items.map(\.value), ["2", ""])
    }

    // MARK: - AZV Wartburgkreis

    func testWartburgkreisFragtDieSuchskripteUndNichtDenProxy() async throws {
        StreetAuditStub.handler = { url in
            if url.contains("proxy.php") { return (404, "File not found.\n") }
            if url.contains("search/search_orte.php") {
                return (200, "\u{FEFF}<ul class=\"proposalList\"><li id=\"ort_23190\" onclick=\"get_value('ort', 23190, 0)\"><span>Amt Creuzburg</span></li></ul>")
            }
            return (500, "")
        }
        let provider = HausmuellInfoProvider(service: "azv", client: HTTPClient(session: StreetAuditStub.session()))
        let step = try await provider.nextStep(after: [])
        XCTAssertEqual(step?.options.map(\.title), ["Amt Creuzburg"])
    }
}

/// Nachgestelltes Portal: Antwort je aufgerufener Adresse.
final class StreetAuditStub: URLProtocol {
    nonisolated(unsafe) static var handler: (String) -> (Int, String) = { _ in (500, "") }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreetAuditStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, body) = Self.handler(url.absoluteString)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
