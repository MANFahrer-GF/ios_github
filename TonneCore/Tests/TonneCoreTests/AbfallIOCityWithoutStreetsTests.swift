import XCTest
@testable import TonneCore

/// Gemeinde-Prüfung 16.11.2026: Das Kreisportal Reutlingen führt Reutlingen, Metzingen und Pfullingen in der Ortsliste, aber
/// ohne Straßen. Wer so einen Ort wählte, bekam „Bitte eine Hausnummer wählen.“ – ohne Auswahl, die es gab.
final class AbfallIOCityWithoutStreetsTests: XCTestCase {
    func testCityWithoutStreetsSaysAnotherProviderIsResponsible() async throws {
        let provider = AbfallIOGraphQLProvider(key: "test", client: HTTPClient(session: AbfallIOStub.session()))
        do {
            _ = try await provider.nextStep(after: [SelectionOption(id: "city:1", title: "Pfullingen")])
            XCTFail("Ort ohne Straßen muss gemeldet werden")
        } catch let error as ProviderError {
            XCTAssertTrue(error.errorDescription?.contains("anderer Entsorger") == true, error.errorDescription ?? "")
        }
        // Gegenprobe: Ort mit Straßen führt zur Straßenauswahl
        let step = try await provider.nextStep(after: [SelectionOption(id: "city:2", title: "Eningen unter Achalm")])
        XCTAssertEqual(step?.options.map(\.title), ["Achalmstraße"])
    }
}

final class AbfallIOStub: URLProtocol {
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AbfallIOStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.contains("abfall.io") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = #"{"apiKey":"k"}"#
        if request.url?.host == "widgets.abfall.io" {
            let sent = Self.body(of: request)
            body = sent.contains(#""id":"1""#)
                ? #"{"data":{"city":{"streets":[],"districts":[]}}}"#
                : #"{"data":{"city":{"streets":[{"id":"9","name":"Achalmstraße"}],"districts":[]}}}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
        return String(decoding: data, as: UTF8.self)
    }
}
