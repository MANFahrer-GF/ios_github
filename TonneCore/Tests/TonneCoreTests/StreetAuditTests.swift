import XCTest
@testable import TonneCore

/// Funde aus der Prüfung aller Orte auf fehlende oder falsche Straßenlisten (November 2026),
/// jeweils mit echten, gekürzten Portalantworten.
final class StreetAuditTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    // MARK: - Suche in Auswahllisten

    private func titles(_ options: [SelectionOption], _ query: String) -> [String] {
        OptionSearch(options).filter(query: query).map(\.title)
    }

    func testOptionSearchVereinheitlichtSchreibweisen() {
        let options = ["Aachener Straße", "Karl-Marx-Str.", "Mühlenweg", "Bäringer\u{AD}straße", "Hauptstr.", "Goethe Platz"].map { SelectionOption(id: $0, title: $0) }
        XCTAssertEqual(titles(options, "aachener str."), ["Aachener Straße"])
        XCTAssertEqual(titles(options, "Karl Marx Straße"), ["Karl-Marx-Str."])
        XCTAssertEqual(titles(options, "karlmarxstrasse"), ["Karl-Marx-Str."])
        XCTAssertEqual(titles(options, "Muehlen"), ["Mühlenweg"])
        XCTAssertEqual(titles(options, "Muhlen"), ["Mühlenweg"])
        XCTAssertEqual(titles(options, "Bäringerstr"), ["Bäringer\u{AD}straße"])
        XCTAssertEqual(titles(options, "Platz Goethe"), ["Goethe Platz"], "Reihenfolge der Wörter ist egal")
        XCTAssertEqual(titles(options, "Goethe Weg"), [], "alle Wörter müssen passen")
    }

    func testOptionSearchTrefferBleibenBeimTippenStehen() {
        let options = [SelectionOption(id: "1", title: "Hauptstr."), SelectionOption(id: "2", title: "Hauptstraße")]
        for typed in ["Hau", "Haupts", "Hauptst", "Hauptstr", "Hauptstra", "Hauptstraß", "Hauptstraße", "Hauptstrasse"] {
            XCTAssertEqual(titles(options, typed).count, 2, typed)
        }
    }

    func testOptionSearchDurchsuchtDenUntertitel() {
        let options = [SelectionOption(id: "1", title: "Kirchweg", subtitle: "Oberdorf"), SelectionOption(id: "2", title: "Kirchweg", subtitle: "Unterdorf")]
        XCTAssertEqual(OptionSearch(options).filter(query: "kirchweg unterdorf").map(\.id), ["2"])
    }

    func testOptionSearchOhneEingabeZeigtAlles() {
        let options = (0..<1200).map { SelectionOption(id: "\($0)", title: "Straße \($0)") }
        XCTAssertEqual(OptionSearch(options).filter(query: "  - ").count, 1200)
    }

    func testOptionSearchGrosseListeDauer() {
        let options = (0..<6000).map { SelectionOption(id: "\($0)", title: "Münchner-Beispiel Straße \($0)", subtitle: "Ortsteil") }
        let index = OptionSearch(options)
        XCTAssertEqual(index.filter(query: "Straße 5999").count, 1)
    }

    // MARK: - Hamburg

    private func hamburgStep(streets: Int) async throws -> SelectionStep? {
        let rows = (0..<streets).map { "{\"asId\":\($0),\"name\":\"Schulstraße \($0)\",\"hnIds\":[]}" }.joined(separator: ",")
        StreetAuditStub.handler = { _ in (200, "[\(rows)]") }
        let provider = NordPortalsProvider(service: "hamburg", client: HTTPClient(session: StreetAuditStub.session()))
        return try await provider.nextStep(after: [SelectionOption(id: "Sch", title: "Sch")])
    }

    func testHamburgSagtBeiFuenfzigTreffernDassMehrBuchstabenNoetigSind() async throws {
        let step = try await hamburgStep(streets: 50)
        XCTAssertEqual(step?.options.count, 50)
        XCTAssertEqual(step?.hint?.contains("mehr Buchstaben"), true)
    }

    func testHamburgOhneHinweisUnterDerGrenze() async throws {
        let step = try await hamburgStep(streets: 49)
        XCTAssertEqual(step?.options.count, 49)
        XCTAssertNil(step?.hint)
    }

    // MARK: - A.R.T. Trier

    private func artStep(_ rows: [String]) async throws -> SelectionStep? {
        StreetAuditStub.handler = { _ in (200, "{\"data\":[\(rows.joined(separator: ","))]}") }
        let provider = RheinlandPfalzPortalsProvider(service: "art", client: HTTPClient(session: StreetAuditStub.session()))
        return try await provider.nextStep(after: [SelectionOption(id: "Trier-Land", title: "Trier-Land"), SelectionOption(id: "Aach", title: "Aach")])
    }

    private func artRow(_ strasse: String?, _ ortsteil: String?, key: String) -> String {
        let quote = { (value: String?) in value.map { "\"\($0)\"" } ?? "null" }
        return "{\"plz\":\"54298\",\"ort\":\"Aach\",\"strasse\":\(quote(strasse)),\"ortsteil\":\(quote(ortsteil)),\"verbandsgemeinde\":\"Trier-Land\",\"key\":\"\(key)\"}"
    }

    func testARTUebrigeStrassenStehenObenMitHinweis() async throws {
        let step = try await artStep([artRow("Aacher Straße", nil, key: "a"), artRow(nil, nil, key: "rest"), artRow("Zum Wehrborn", nil, key: "z")])
        XCTAssertEqual(step?.options.map(\.id), ["rest", "a", "z"])
        XCTAssertEqual(step?.options.first?.title, "Übrige Straßen")
        XCTAssertNotNil(step?.options.first?.subtitle)
        XCTAssertEqual(step?.noMatchHint?.contains("Übrige Straßen"), true)
    }

    func testARTOhneSammeleintragOhneHinweis() async throws {
        let step = try await artStep([artRow("Aacher Straße", nil, key: "a"), artRow("Zum Wehrborn", nil, key: "z")])
        XCTAssertEqual(step?.options.map(\.id), ["a", "z"])
        XCTAssertNil(step?.noMatchHint)
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
