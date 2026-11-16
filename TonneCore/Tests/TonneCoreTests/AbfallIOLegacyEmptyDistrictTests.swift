import XCTest
@testable import TonneCore

/// Gemeinde-Prüfung 16.11.2026: Unterallgäu, Babenhausen, Ortsteil Klosterbeuren (Bezirk 10691). Das Portal führt den
/// Bezirk, liefert danach aber weder Straßen noch Abfallarten, und `export_ics` antwortet mit HTTP 404. Die App zeigte
/// den 404; jetzt meldet sie, dass das Portal für diese Auswahl keine Daten führt.
final class AbfallIOLegacyEmptyDistrictTests: XCTestCase {
    private let provider = AbfallIOLegacyProvider(key: "test", client: HTTPClient(session: LegacyEmptyDistrictStub.session()))

    func testDistrictWithoutWasteTypesSaysThePortalHasNoData() async throws {
        L10n.forcedLanguage = "de"
        defer { L10n.forcedLanguage = nil }
        do {
            _ = try await provider.nextStep(after: [SelectionOption(id: "f_id_bezirk:1", title: "Klosterbeuren")])
            XCTFail("Bezirk ohne Abfallarten muss gemeldet werden")
        } catch let error as ProviderError {
            XCTAssertTrue(error.errorDescription?.contains("keine Abfuhrdaten") == true, error.errorDescription ?? "")
        }
        do {
            _ = try await provider.pickups(for: [SelectionOption(id: "f_id_bezirk:1", title: "Klosterbeuren")], calendar: .current)
            XCTFail("Export ohne Abfallarten darf nicht versucht werden")
        } catch let error as ProviderError {
            XCTAssertTrue(error.errorDescription?.contains("keine Abfuhrdaten") == true, error.errorDescription ?? "")
        }
        XCTAssertFalse(LegacyEmptyDistrictStub.exportCalled, "export_ics hätte HTTP 404 geliefert")
    }

    /// Prüfbefund 12: Die Meldung folgt der Sprache der Oberfläche.
    func testNoDataMessageIsEnglishInEnglishUI() async throws {
        L10n.forcedLanguage = "en"
        defer { L10n.forcedLanguage = nil }
        do {
            _ = try await provider.nextStep(after: [SelectionOption(id: "f_id_bezirk:1", title: "Klosterbeuren")])
            XCTFail("Bezirk ohne Abfallarten muss gemeldet werden")
        } catch let error as ProviderError {
            XCTAssertTrue(error.errorDescription?.contains("no collection data") == true, error.errorDescription ?? "")
        }
    }

    func testDistrictWithWasteTypesIsFinishedAndFirstStepStillOffersDistricts() async throws {
        let first = try await provider.nextStep(after: [])
        XCTAssertEqual(first?.options.map(\.title), ["Klosterbeuren", "Babenhausen"])
        let done = try await provider.nextStep(after: [SelectionOption(id: "f_id_bezirk:2", title: "Babenhausen")])
        XCTAssertNil(done)
    }
}

final class LegacyEmptyDistrictStub: URLProtocol {
    nonisolated(unsafe) static var exportCalled = false

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LegacyEmptyDistrictStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.abfall.io" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let query = request.url?.query ?? ""
        let sent = Self.body(of: request)
        var status = 200
        var body = #"<input type="hidden" name="f_id_kommune" value="5"><select name="f_id_bezirk"><option value="0">Bitte wählen</option><option value="1">Klosterbeuren</option><option value="2">Babenhausen</option></select>"#
        if query.contains("waction=auswahl_bezirk_set") {
            body = sent.contains("f_id_bezirk=1")
                ? #"<input type="hidden" name="f_id_kommune" value="5"><input type="hidden" name="f_id_bezirk" value="1">"#
                : #"<input type="hidden" name="f_id_bezirk" value="2"><input type="checkbox" name="f_id_abfalltyp_0" value="31">"#
        } else if query.contains("waction=export_ics") {
            Self.exportCalled = true
            status = 404
            body = ""
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
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
