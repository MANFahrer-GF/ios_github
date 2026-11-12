import XCTest
@testable import TonneCore

/// Kreis Verden (Abfall+ App): Das Portal führt Ortsteile ganz ohne Straßen (Langwedel-Holtebüttel, Kirchlinteln-Lehringen,
/// Prüflauf 12.11.2026). Wer so einen Ortsteil wählt, bekam eine Straßensuche, die nie etwas fand. Jetzt wird die Ortsteil-Liste
/// ohne die leeren noch einmal angeboten. Gekürzte echte Antworten.
final class AbfallPlusEmptyDistrictTests: XCTestCase {
    private func provider() -> AbfallPlusAppProvider {
        var provider = AbfallPlusAppProvider(appID: "de.abfallplus.abfallappver")
        provider.urlProtocols = [APLStub.self]
        return provider
    }

    func testDistrictWithoutStreetsOffersOtherDistrictsAgain() async throws {
        let p = provider()
        let first = try await p.nextStep(after: [])
        let kom = try XCTUnwrap(first).options.first { $0.title == "Langwedel" }!
        let districtsStep = try await p.nextStep(after: [kom])
        let districts = try XCTUnwrap(districtsStep)
        XCTAssertEqual(districts.title, SelectionStep.districtTitle)
        let holte = try XCTUnwrap(districts.options.first { $0.title == "Holtebüttel" })
        let again = try await p.nextStep(after: [kom, holte])
        let step = try XCTUnwrap(again)
        XCTAssertEqual(step.input, .list)
        XCTAssertEqual(step.options.map(\.title), ["Kernstadt"], "Der leere Ortsteil wird nicht noch einmal angeboten")
        let streets = try await p.nextStep(after: [kom, holte, step.options[0]])
        XCTAssertEqual(try XCTUnwrap(streets).options.map(\.title), ["Hauptstraße"])
    }
}

final class APLStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "app.abfallplus.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(buffer, count: n) }
            stream.close()
        }
        let form = String(decoding: body, as: UTF8.self).removingPercentEncoding ?? ""
        let path = (request.url?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        func item(_ id: String, _ name: String, _ type: String, _ next: String) -> String {
            #"<li><a href="javascript:void(0)" data-rel="back" onclick="awk_standort_auswahl_step_fertig('\#(id)','\#(name)','\#(type)','\#(next)','',{'step_follow':0,'step_follow_data':{},'set_id_kommune':87263470581})">\#(name)</a></li>"#
        }
        var text = ""
        switch path {
        case "login":
            text = #"<input name="f_id_bundesland" value="0"><input name="f_id_landkreis" value="0"><input name="f_id_kommune" value="0"> #awk_assistent_step_standort_kommune #awk_assistent_step_standort_bezirk #awk_assistent_step_standort_strasse"#
        case "assistent/kommune":
            text = "<ul>" + item("87263470581|0|Langwedel", "Langwedel", "kommune", "bezirk") + "</ul>"
        case "assistent/bezirk":
            text = "<ul>" + item("63|0|Holtebüttel", "Holtebüttel", "bezirk", "strasse") + item("6|0|Kernstadt", "Kernstadt", "bezirk", "strasse") + "</ul>"
        case "assistent/strasse":
            text = form.contains("id_bezirk=6|0|Kernstadt") ? "<ul>" + item("301|301|Hauptstraße", "Hauptstraße", "strasse", "hnr") + "</ul>" : "<ul> </ul>"
        default: text = ""
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
