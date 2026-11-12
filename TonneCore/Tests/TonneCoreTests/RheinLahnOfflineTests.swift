import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// Rhein-Lahn-Kreis: Das Portal ist seit einem Sicherheitsvorfall abgeschaltet (Startseite, 12.11.2026); jede Unterseite
/// antwortet 404. Statt „HTTP 404“ bekommt der Nutzer gesagt, was los ist und wo die Termine stehen.
final class RheinLahnOfflineTests: XCTestCase {
    func testShutDownPortalIsExplained() async throws {
        L10n.forcedLanguage = "de"
        defer { L10n.forcedLanguage = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RheinLahnStub.self]
        let provider = RheinlandPfalzPortalsProvider(service: "rheinlahn", client: HTTPClient(session: URLSession(configuration: config)))
        do {
            _ = try await provider.nextStep(after: [])
            XCTFail("abgeschaltetes Portal muss einen Hinweis werfen")
        } catch let error as ProviderError {
            let text = error.errorDescription ?? ""
            XCTAssertTrue(text.contains("Sicherheitsvorfall"), text)
            XCTAssertTrue(text.contains("rhein-lahn-kreis.de"), text)
        }
    }
}

/// Wie das echte Portal seit der Abschaltung: Hinweisseite, Unterseiten 404.
final class RheinLahnStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix("rhein-lahn-kreis-abfallwirtschaft.de") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("<title>Rhein-Lahn-Kreis Abfallwirtschaft – Hinweis</title>".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
