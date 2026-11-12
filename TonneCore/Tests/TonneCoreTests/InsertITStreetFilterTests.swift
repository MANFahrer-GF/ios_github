import XCTest
@testable import TonneCore

/// Insert IT (Lübeck, Offenbach …): Die Straßensuche liefert auch Plätze und Bahnhöfe ohne Hausnummern. Prüflauf 12.11.2026:
/// „Haupt“ ergab in Lübeck „Hauptbahnhof, Hauptstraße“ und in Offenbach „Hauptbahnhof, Haupteingangstraße“, beide ohne
/// Hausnummern – die Auswahl endete in einer Sackgasse. Gekürzte echte Antworten.
final class InsertITStreetFilterTests: XCTestCase {
    private func provider() -> InsertITProvider {
        InsertITProvider(city: "Offenbach", client: HTTPClient(session: InsertITStub.session()))
    }

    private let typed = SelectionOption(id: "Haupt", title: "Haupt")

    func testStreetsWithoutHouseNumbersAreLeftOut() async throws {
        let step = try await provider().nextStep(after: [typed])
        XCTAssertEqual(try XCTUnwrap(step).options.map(\.title), ["Hauptstraße"])
    }

    func testOnlyStreetsWithoutHouseNumbersIsAnErrorSoSearchCanTryAnotherWord() async throws {
        InsertITStub.streets = #"[{"ID":801,"Name":"Hauptbahnhof"},{"ID":802,"Name":"Haupteingangstraße"}]"#
        defer { InsertITStub.streets = InsertITStub.defaultStreets }
        do {
            _ = try await provider().nextStep(after: [typed])
            XCTFail("Liste nur mit Straßen ohne Hausnummern darf keine Auswahl sein")
        } catch let error as ProviderError {
            guard case .invalidSelection = error else { return XCTFail("falscher Fehler \(error)") }
        }
    }

    func testFailedLookupKeepsListUnchanged() async throws {
        InsertITStub.failLocations = true
        defer { InsertITStub.failLocations = false }
        let step = try await provider().nextStep(after: [typed])
        XCTAssertEqual(try XCTUnwrap(step).options.count, 2, "Bei gescheiterter Nachfrage nichts ausblenden")
    }
}

final class InsertITStub: URLProtocol {
    static let defaultStreets = #"[{"ID":801,"Name":"Hauptbahnhof"},{"ID":203,"Name":"Hauptstraße"}]"#
    nonisolated(unsafe) static var streets = defaultStreets
    nonisolated(unsafe) static var failLocations = false

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InsertITStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.insert-it.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!.absoluteString
        var status = 200
        var body = "[]"
        if url.contains("GetStreets") { body = Self.streets }
        else if url.contains("GetLocations") {
            if Self.failLocations { status = 500 }
            else if url.contains("streetId=203") {
                body = #"[{"ID":1020,"AssessedValue":1,"StreetId":203,"HouseNumberStart":8,"HouseNumberStartExtra":null,"HouseNumberEnd":null,"HouseNumberEndExtra":null,"Text":"8"}]"#
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
