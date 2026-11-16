import XCTest
@testable import TonneCore

/// AW Germersheim: Der ICS-Download (POST) wird seit Herbst 2026 nur mit `Sec-Fetch-Site: same-origin` angenommen,
/// sonst HTTP 400 – damals scheiterten alle 31 Gemeinden des Kreises.
final class GermersheimTests: XCTestCase {
    func testICSDownloadSendsSameOriginHeader() async throws {
        let client = HTTPClient(session: GermersheimStub.session())
        let provider = RheinlandPfalzPortalsProvider(service: "germersheim", client: client)
        let selections = [SelectionOption(id: "Bellheim", title: "Bellheim"), SelectionOption(id: "Adenauerring", title: "Adenauerring")]
        let pickups = try await provider.pickups(for: selections, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(pickups.count, 1)
        XCTAssertEqual(pickups.first?.name, "Restmüll")
    }

    /// Das Schadstoffmobil trägt Uhrzeit und Standort im Namen – das darf keine eigene Müllart je Standort ergeben.
    func testProblemmuellKeepsTimeAndPlaceAsNote() {
        let day = Date(timeIntervalSince1970: 0)
        let split = RheinlandPfalzPortalsProvider.germersheimSplitNote(
            Pickup(date: day, name: "Problemmüll 11:00 - 13:00 Uhr, Kandel, Stadionvorplatz (Bienwaldstadion Jahnstraße)"))
        XCTAssertEqual(split.name, "Problemmüll")
        XCTAssertEqual(split.note, "11:00 - 13:00 Uhr, Kandel, Stadionvorplatz (Bienwaldstadion Jahnstraße)")
        XCTAssertEqual(RheinlandPfalzPortalsProvider.germersheimSplitNote(Pickup(date: day, name: "Gelber Sack")).name, "Gelber Sack")
    }
}

final class GermersheimStub: URLProtocol {
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GermersheimStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.abfallwirtschaft-germersheim.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static let form = """
    <input type="checkbox" id="id_form_icsabfallart_0" name="icsabfallart[]"
           value="Restmüll"  onchange="this.form.submit()">
    """
    static let download = """
    <form method="POST">
        <input type="hidden" name="ICS_DOWNLOAD" value="9dcb88e0137649590b755372b040afad">
        <input type="hidden" name="REQUEST_TOKEN" value="abc.def">
    </form>
    """
    static let ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20261120\r\nSUMMARY:Restmüll\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        var status = 200, text = ""
        if request.httpMethod == "POST" {
            // Wie das echte Portal: ohne die Browser-Kopfzeile „400 Bad Request“
            if request.value(forHTTPHeaderField: "Sec-Fetch-Site") == "same-origin" { text = Self.ics } else { status = 400 }
        } else {
            text = url.contains("icsabfallart") ? Self.download : Self.form
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
