import XCTest
@testable import TonneCore

/// Cochem-Zell (Gemeinde-Prüfung 16.11.2026): Das Portal führt fast jeden Ort doppelt – „Beuren“ ohne Ortsteil mit ein paar
/// Alt-Straßen ohne Plan und „Beuren – Beuren“ mit den echten Straßen. Wer „Beuren“ wählte, bekam keine Termine
/// (Kaisersesch, Zell, Bullay … 50 Gemeinden). Der gleichnamige Ortsteil gehört zum Hauptort: ein Eintrag „Beuren“ mit allen Straßen.
final class BuergerportalSameNameDistrictTests: XCTestCase {
    private func provider() -> BuergerportalProvider {
        BuergerportalProvider(operator: "cochem_zell", client: HTTPClient(session: BuergerportalStub.session()))
    }

    func testSameNamedDistrictIsMergedIntoThePlace() async throws {
        let step = try await provider().nextStep(after: [])
        XCTAssertEqual(step?.options.map(\.title), ["Altlay", "Beuren", "Cochem", "Cochem – Cochem-Sehl"])
    }

    func testPlaceListsStreetsOfTheSameNamedDistrict() async throws {
        let p = provider()
        let first = try await p.nextStep(after: [])
        let beuren = try XCTUnwrap(first?.options.first { $0.title == "Beuren" })
        _ = try await p.nextStep(after: [beuren])
        let filter = try XCTUnwrap(BuergerportalStub.requests().first { $0.contains("/Strassen?") })
        XCTAssertTrue(filter.contains("Ort/OrteId eq 79 and (OrtsteilName eq null or OrtsteilName eq '' or OrtsteilName eq 'Beuren')"), filter)
    }

    /// Vor 2.1.0 gespeicherte Adressen tragen „79|Beuren“ – die Termine hängen nur an Ort und Straße und kommen weiter.
    func testSavedAddressWithOldDistrictIdStillGetsPickups() async throws {
        let p = provider()
        let pickups = try await p.pickups(for: [SelectionOption(id: "79|Beuren", title: "Beuren – Beuren"),
                                               SelectionOption(id: "500", title: "Hofstraße"), SelectionOption(id: "1", title: "1")], calendar: .current)
        XCTAssertEqual(pickups.count, 1)
        let request = try XCTUnwrap(BuergerportalStub.requests().first { $0.contains("/AbfuhrtermineAbJahr?") })
        XCTAssertTrue(request.contains("orteId=79&strassenId=500"), request)
    }

    /// Altpfad im Straßenschritt: „79|Beuren“ fragt nur den Ortsteil ab und findet seine Straßen weiter.
    func testSavedAddressWithOldDistrictIdStillListsStreets() async throws {
        let step = try await provider().nextStep(after: [SelectionOption(id: "79|Beuren", title: "Beuren – Beuren")])
        XCTAssertEqual(step?.options.map(\.title), ["Hofstraße"])
        let filter = try XCTUnwrap(BuergerportalStub.requests().first { $0.contains("/Strassen?") })
        XCTAssertTrue(filter.contains("Ort/OrteId eq 79 and OrtsteilName eq 'Beuren'"), filter)
    }
}

final class BuergerportalStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BuergerportalStub.self]
        return URLSession(configuration: config)
    }

    private static let streetFilters: Set<String> = [
        "Ort/OrteId eq 79 and (OrtsteilName eq null or OrtsteilName eq '' or OrtsteilName eq 'Beuren')",
        "Ort/OrteId eq 79 and OrtsteilName eq 'Beuren'",
    ]

    static func requests() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.contains("buerger-portal-cochemzell") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url?.absoluteString.removingPercentEncoding ?? ""
        Self.lock.lock(); Self.seen.append(url); Self.lock.unlock()
        // Dekodierte Parameter: Der OData-Filter kommt kodiert an, ein Vergleich am Rohtext träfe nie
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
        var body = #"{"d":[]}"#
        if url.contains("/OrteMitOrtsteilen") {
            body = #"{"d":[{"OrteId":79,"Ortsname":"Beuren","Ortsteilname":null},{"OrteId":79,"Ortsname":"Beuren","Ortsteilname":"Beuren"},"#
                + #"{"OrteId":37,"Ortsname":"Altlay","Ortsteilname":"Altlay"},{"OrteId":2,"Ortsname":"Cochem","Ortsteilname":null},"#
                + #"{"OrteId":2,"Ortsname":"Cochem","Ortsteilname":"Cochem-Sehl"}]}"#
        } else if url.contains("/Strassen?"), Self.streetFilters.contains(query["$filter"] ?? "") {
            // Nur die beiden Anfragen, die Beurens echte Straßen finden: Hauptort samt gleichnamigem Ortsteil oder Altpfad Ortsteil
            body = #"{"d":[{"StrassenId":500,"Name":"Hofstraße","Plz":"56825"}]}"#
        } else if url.contains("/AbfuhrtermineAbJahr?"), query["orteId"] == "79", query["strassenId"] == "500" {
            body = #"{"d":[{"Termin":"/Date(1798761600000)/","Abfuhrplan":{"GefaesstarifArt":{"Abfallart":{"Name":"Restmüll"}}}}]}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
