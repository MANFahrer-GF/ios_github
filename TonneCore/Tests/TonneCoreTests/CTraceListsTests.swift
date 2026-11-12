import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// C-Trace: Straße und Hausnummer kommen als Liste aus dem Portal, auch bei festem Ort. Vorher war die Straße ein Textfeld,
/// das nur den vollen Portalnamen fand („Haupt“ fand in Bremen nichts), und die Hausnummer frei getippt – eine Nummer, die
/// das Portal nicht kennt, gab HTTP 500 (Bremen „Aachener Straße 1“, Aurich „Kirchlohne 1“) oder nur Sammeltermine
/// (Arnsberg „Ackerstraße 1“: 9 Termine ohne Tonnen, „Ackerstraße 2“: 84). Antworten echt und gekürzt, 12.11.2026.
final class CTraceListsTests: XCTestCase {
    // web.c-trace.de/bremenabfallkalender/Data/Strassen?ort=Bremen (gekürzt; der leere Eintrag steht so im Portal)
    static let bremenStreets = #"["","10 Olbersstraße","Aachener Straße","Aarhuser Straße"]"#
    // …/Data/Hausnummern?ort=Bremen&strasse=Aachener Straße (gekürzt)
    static let bremenHouses = #"["0","2","2-10","3"]"#
    // web.c-trace.de/arnsberg-abfallkalender/Hausnummern?ort=Arnsberg&strasse=Ackerstraße
    static let arnsbergHouses = #"["2","4","6","8"]"#
    static let arnsbergStreets = #"["Achter der Borg","Ackerstraße","Adam-Stegerwald-Weg"]"#
    // web.c-trace.de/dietzenbach/OData.svc/AktuelleStrassen?$format=json&strasse='' (gekürzt)
    static let dietzenbachStreets = #"{"d":[{"__metadata":{"uri":"https://web.c-trace.de/dietzenbach/OData.svc/Strassen(2)","type":"DataServiceProviderDietzenbach.Strasse"},"StrassenId":2,"Name":"Adolph-Kolping-Str.","OrtsteilName":null},{"StrassenId":5,"Name":"Ahornweg","OrtsteilName":null}]}"#
    // apps.c-trace.de/web.landau/OData.svc/Strassen?$format=json&$orderby=Name (gekürzt)
    static let landauStreets = #"{"d":[{"__metadata":{"uri":"https://apps.c-trace.de/web.landau/OData.svc/Strassen(46)","type":"DataServiceProviderLandau.Strasse"},"StrassenId":46,"Name":"Adlerstr.","OrtsteilName":null},{"StrassenId":92,"Name":"Adolf-Kessler-Str.","OrtsteilName":null}]}"#
    // apps.c-trace.de/web.aurich-abfallkalender/OData.svc/AktuelleObjekte?gemeinde='Brookmerland'&ort='Wirdum'&strasse='Kirchlohne' (gekürzt)
    static let aurichObjects = #"{"d":[{"__metadata":{"uri":"https://apps.c-trace.de/web.aurich-abfallkalender/OData.svc/Objekte(3112)","type":"DataServiceProviderAurich.Objekt"},"ObjekteId":3112,"HausNr":"1","HausNrZus":"A"},{"ObjekteId":75857,"HausNr":"2","HausNrZus":null},{"ObjekteId":59326,"HausNr":"3","HausNrZus":null}]}"#

    // web.c-trace.de/bremenabfallkalender/abfallkalender/cal?…Aachener Straße, Hausnr 2 (zwei Termine, Beschreibung gekürzt)
    static let bremenICS = "BEGIN:VCALENDAR\r\nMETHOD:PUBLISH\r\nPRODID:-//www.die-bremer-stadtreinigung.de//NONSGML c-ware 1.0//\r\nVERSION:2.0\r\n"
        + "BEGIN:VEVENT\r\nUID:164483\r\nDTSTART;VALUE=DATE-TIME:20261116T060000\r\nDTEND;VALUE=DATE-TIME:20261116T063000\r\nLOCATION:Bremen\\,Aachener Straße 2\r\nSUMMARY:Abfuhr: Bioabfall\r\nEND:VEVENT\r\n"
        + "BEGIN:VEVENT\r\nUID:163573\r\nDTSTART;VALUE=DATE-TIME:20261116T060000\r\nDTEND;VALUE=DATE-TIME:20261116T063000\r\nLOCATION:Bremen\\,Aachener Straße 2\r\nSUMMARY:Abfuhr: Restmüll\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

    private func provider(_ key: String) -> CTraceProvider {
        CTraceProvider(service: key, client: HTTPClient(session: CTraceStub.session()))
    }

    func testBremenStreetAndHouseNumberAreListsFromDataCalls() async throws {
        let bremen = provider("bremenabfallkalender")
        let streets = try await bremen.nextStep(after: [])
        XCTAssertEqual(streets?.input, .list)
        XCTAssertEqual(streets?.title, SelectionStep.streetTitle)
        XCTAssertEqual(streets?.options.map(\.title), ["10 Olbersstraße", "Aachener Straße", "Aarhuser Straße"])
        // Teilsuche in der App findet „Aachener Straße“ schon mit „aach“
        XCTAssertEqual(OptionSearch(streets?.options ?? []).filter(query: "aach").first?.title, "Aachener Straße")
        let street = SelectionOption(id: "Aachener Straße", title: "Aachener Straße")
        let houses = try await bremen.nextStep(after: [street])
        XCTAssertEqual(houses?.input, .list)
        XCTAssertEqual(houses?.title, SelectionStep.houseNumberTitle)
        XCTAssertEqual(houses?.options.map(\.title), ["0", "2", "2-10", "3"])
        let urls = CTraceStub.requests()
        XCTAssertEqual(urls, ["https://web.c-trace.de/bremenabfallkalender/Data/Strassen?ort=Bremen",
                              "https://web.c-trace.de/bremenabfallkalender/Data/Hausnummern?ort=Bremen&strasse=Aachener%20Stra%C3%9Fe"])
    }

    func testArnsbergUsesPlainListsForFixedCity() async throws {
        let arnsberg = provider("arnsberg-abfallkalender")
        let streets = try await arnsberg.nextStep(after: [])
        XCTAssertEqual(streets?.options.map(\.title), ["Achter der Borg", "Ackerstraße", "Adam-Stegerwald-Weg"])
        let houses = try await arnsberg.nextStep(after: [SelectionOption(id: "Ackerstraße", title: "Ackerstraße")])
        XCTAssertEqual(houses?.options.map(\.title), ["2", "4", "6", "8"])
        XCTAssertEqual(CTraceStub.requests(), ["https://web.c-trace.de/arnsberg-abfallkalender/Strassen?ort=Arnsberg",
                                               "https://web.c-trace.de/arnsberg-abfallkalender/Hausnummern?ort=Arnsberg&strasse=Ackerstra%C3%9Fe"])
    }

    func testDietzenbachUsesCurrentStreetsAndObjects() async throws {
        let dietzenbach = provider("dietzenbach")
        let streets = try await dietzenbach.nextStep(after: [])
        XCTAssertEqual(streets?.options.map(\.title), ["Adolph-Kolping-Str.", "Ahornweg"])
        _ = try await dietzenbach.nextStep(after: [SelectionOption(id: "Ahornweg", title: "Ahornweg")])
        XCTAssertEqual(CTraceStub.requests(), ["https://web.c-trace.de/dietzenbach/OData.svc/AktuelleStrassen?$format=json&strasse=''",
                                               "https://web.c-trace.de/dietzenbach/OData.svc/AktuelleObjekte?$format=json&strasse='Ahornweg'"])
    }

    func testLandauUsesAllStreetsWithoutCityFilter() async throws {
        let landau = provider("landau")
        let streets = try await landau.nextStep(after: [])
        XCTAssertEqual(streets?.options.map(\.title), ["Adlerstr.", "Adolf-Kessler-Str."])
        XCTAssertEqual(CTraceStub.requests(), ["https://apps.c-trace.de/web.landau/OData.svc/Strassen?$format=json&$orderby=Name"])
    }

    func testAurichHouseNumbersComeFromObjectsOfAreaAndPlace() async throws {
        let aurich = provider("aurich-abfallkalender")
        let place = SelectionOption(id: "Brookmerland / Wirdum", title: "Brookmerland / Wirdum")
        let houses = try await aurich.nextStep(after: [place, SelectionOption(id: "Kirchlohne", title: "Kirchlohne")])
        XCTAssertEqual(houses?.input, .list)
        XCTAssertEqual(houses?.options.map(\.title), ["1A", "2", "3"])
        XCTAssertEqual(CTraceStub.requests().last,
                       "https://apps.c-trace.de/web.aurich-abfallkalender/OData.svc/AktuelleObjekte?$format=json&gemeinde='Brookmerland'&ort='Wirdum'&strasse='Kirchlohne'")
    }

    /// Kennt das Portal die Straße nicht oder antwortet es nicht, bleibt die Texteingabe.
    func testHouseNumberFallsBackToTextWhenPortalHasNoList() async throws {
        let bremen = provider("bremenabfallkalender")
        let step = try await bremen.nextStep(after: [SelectionOption(id: "Unbekannt", title: "Unbekannt")])
        XCTAssertEqual(step?.input, .text)
        XCTAssertEqual(step?.title, SelectionStep.houseNumberTitle)
    }

    func testParseHouseNumbers() throws {
        XCTAssertEqual(try CTraceProvider.parseHouseNumbers(Data(Self.aurichObjects.utf8)), ["1A", "2", "3"])
        XCTAssertEqual(try CTraceProvider.parseHouseNumbers(Data(#"["2"," 2","","4"]"#.utf8)), ["2", "4"])
        XCTAssertThrowsError(try CTraceProvider.parseHouseNumbers(Data("<html>500</html>".utf8)))
    }

    /// Kein Plan zur Adresse: C-Trace antwortet 500 (Bremen „Irisweg 17“, auch die Portalseite zeigt nichts) – verständlich melden.
    func testMissingPlanIsExplainedInsteadOfHTTP500() async throws {
        let bremen = provider("bremenabfallkalender")
        let found = try await bremen.pickups(for: [SelectionOption(id: "Aachener Straße", title: "Aachener Straße"), SelectionOption(id: "2", title: "2")],
                                             calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(found.map(\.name).sorted(), ["Bioabfall", "Restmüll"])
        do {
            _ = try await bremen.pickups(for: [SelectionOption(id: "Irisweg", title: "Irisweg"), SelectionOption(id: "17", title: "17")],
                                         calendar: Calendar(identifier: .gregorian))
            XCTFail("Irisweg 17 hat keinen Plan")
        } catch let error as ProviderError {
            XCTAssertFalse(error.errorDescription?.contains("HTTP") ?? true)
        }
    }

    /// Roth (letzter Termin 03.01.2024) und Rheingau (31.12.2025): sofort sagen, was zu tun ist, ohne Abfrage ins Leere.
    func testRetiredPortalsExplainWithoutAsking() async throws {
        for key in ["roth", "rheingauleerungen"] {
            let retired = provider(key)
            do {
                _ = try await retired.nextStep(after: [])
                XCTFail("\(key) muss einen Hinweis werfen")
            } catch let error as ProviderError {
                XCTAssertTrue(error.errorDescription?.contains("C-Trace-Portal") == true || error.errorDescription?.contains("C-Trace portal") == true, key)
            }
            XCTAssertTrue(CTraceStub.requests().isEmpty, key)
        }
    }
}

/// Nachgestellte C-Trace-Portale; Unbekanntes antwortet 404 wie das echte Portal.
final class CTraceStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CTraceStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix("c-trace.de") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.lock.lock(); Self.seen.append(url); Self.lock.unlock()
        let answers: [(String, String)] = [
            ("bremenabfallkalender/Data/Strassen?ort=Bremen", CTraceListsTests.bremenStreets),
            ("bremenabfallkalender/Data/Hausnummern?ort=Bremen&strasse=Aachener", CTraceListsTests.bremenHouses),
            ("arnsberg-abfallkalender/Strassen?ort=Arnsberg", CTraceListsTests.arnsbergStreets),
            ("arnsberg-abfallkalender/Hausnummern?ort=Arnsberg&strasse=Ackerstra", CTraceListsTests.arnsbergHouses),
            ("dietzenbach/OData.svc/AktuelleStrassen", CTraceListsTests.dietzenbachStreets),
            ("web.landau/OData.svc/Strassen", CTraceListsTests.landauStreets),
            ("web.aurich-abfallkalender/OData.svc/AktuelleObjekte", CTraceListsTests.aurichObjects),
        ]
        var body = answers.first { url.contains($0.0) }?.1
        var status = body == nil ? 404 : 200
        if url.contains("abfallkalender/cal?") {
            // Termine: Aachener Straße 2 hat einen Plan, Irisweg 17 nicht (echtes Portal: „Runtime Error“ mit 500)
            if url.contains("Strasse=Aachener") { body = CTraceListsTests.bremenICS; status = 200 } else { body = "<title>Runtime Error</title>"; status = 500 }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": status == 200 ? "application/json" : "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "<html>404</html>").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
