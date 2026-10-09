import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// AHK Heidekreis: Die API blockt Rechenzentren außerhalb Deutschlands. Deshalb prüfen diese Tests
/// den ganzen Ablauf gegen nachgestellte Antworten (echte, gekürzte Antworten der API vom Oktober 2026).
/// Live-Test nur mit TONNE_LIVE=1 von einem Rechner in Deutschland.
final class HeidekreisTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    // Echte Antworten der API (Oktober 2026), gekürzt; Icon-Bilder weggelassen.
    static let streets = #"""
    [{"arStrasse":84106,"strassenname":"Wagnerstr.","hausNr":null,"hausNrZ":null,"hausNrHausNrZ":"","arObjekt":null,"plz":"29633","ort":"Munster","ortsteil":"","ortOrtsteil":"Munster"},
     {"arStrasse":6240,"strassenname":"Wagnerstr.","hausNr":null,"hausNrZ":null,"hausNrHausNrZ":"","arObjekt":null,"plz":"29683","ort":"Bad Fallingbostel","ortsteil":"Fallingbostel","ortOrtsteil":"Bad Fallingbostel/Fallingbostel"},
     {"arStrasse":85051,"strassenname":"Wagnerstr.","hausNr":null,"hausNrZ":null,"hausNrHausNrZ":"","arObjekt":null,"plz":"29643","ort":"Neuenkirchen","ortsteil":"","ortOrtsteil":"Neuenkirchen"},
     {"arStrasse":84106,"strassenname":"Wagnerstr.","hausNr":null,"hausNrZ":null,"hausNrHausNrZ":"","arObjekt":null,"plz":"29633","ort":"Munster","ortsteil":"","ortOrtsteil":"Munster"}]
    """#
    static let houseNumbers = #"""
    [{"arStrasse":84106,"strassenname":"Wagnerstr.","hausNr":10,"hausNrZ":"-18","hausNrHausNrZ":"10-18","arObjekt":13636,"plz":"29633","ort":"Munster","ortsteil":"","ortOrtsteil":"Munster"},
     {"arStrasse":84106,"strassenname":"Wagnerstr.","hausNr":2,"hausNrZ":"","hausNrHausNrZ":"2","arObjekt":13621,"plz":"29633","ort":"Munster","ortsteil":"","ortOrtsteil":"Munster"},
     {"arStrasse":84106,"strassenname":"Wagnerstr.","hausNr":4,"hausNrZ":"a","hausNrHausNrZ":"4a","arObjekt":13623,"plz":"29633","ort":"Munster","ortsteil":"","ortOrtsteil":"Munster"}]
    """#
    // Wohnhaus (Bispingen) und Gewerbe-Container (Munster) zusammen.
    static let icons = #"""
    [{"description":"Bioenergietonne 60 L","id":5},{"description":"Gelbe Tonne 240 L ","id":254},{"description":"Papier 240 L","id":8},
     {"description":"Restabfalltonne 240 L","id":3},{"description":"Strauchschnitt","id":272},{"description":"AHS RM 1100 L","id":106}]
    """#
    static let types = #"""
    [{"id":2.0,"name":"Restabfall"},{"id":3.0,"name":"Gelbe Tonne"},{"id":4.0,"name":"Bio- und Gartenabfall"},{"id":6.0,"name":"Altpapier"}]
    """#
    static let days = #"""
    [{"date":"2026-10-05T00:00:00","idDisposalType":2,"moved":false,"idIcon":3,"color":"Black"},
     {"date":"2026-10-08T00:00:00","idDisposalType":3,"moved":false,"idIcon":254,"color":"#FDC100"},
     {"date":"2026-10-14T00:00:00","idDisposalType":4,"moved":false,"idIcon":5,"color":"Brown"},
     {"date":"2026-10-19T00:00:00","idDisposalType":6,"moved":false,"idIcon":8,"color":"Blue"},
     {"date":"2026-10-26T00:00:00","idDisposalType":2,"moved":false,"idIcon":106,"color":"Black"},
     {"date":"2026-11-06T00:00:00","idDisposalType":13.0,"moved":false,"idIcon":272,"color":"Blue"},
     {"date":"kaputt","idDisposalType":2,"moved":false,"idIcon":3,"color":"Black"},
     {"date":"2026-11-09T00:00:00","idDisposalType":99,"moved":false,"idIcon":999,"color":"Black"}]
    """#

    func testStreetsParsing() {
        let options = NordPortalsProvider.ahkStreets(Data(Self.streets.utf8))
        XCTAssertEqual(options.count, 3, "doppelte Straße wird zusammengefasst")
        XCTAssertEqual(options.map(\.id), ["84106", "85051", "6240"])
        XCTAssertEqual(options[2].subtitle, "29683 Bad Fallingbostel/Fallingbostel")
        XCTAssertEqual(options[0].subtitle, "29633 Munster")
    }

    func testHouseNumbersParsing() {
        let options = NordPortalsProvider.ahkHouseNumbers(Data(Self.houseNumbers.utf8))
        XCTAssertEqual(options.map(\.title), ["2", "4a", "10-18"])
        XCTAssertEqual(options.last?.id, "13636")
    }

    func testPickupsParsing() {
        let pickups = NordPortalsProvider.ahkPickups(days: Data(Self.days.utf8), icons: Data(Self.icons.utf8),
                                                     types: Data(Self.types.utf8), calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Restabfalltonne", "Gelbe Tonne", "Bioenergietonne", "Papier", "Restabfall", "Strauchschnitt"],
                       "Gewerbe-Kürzel „AHS RM“ wird durch die Abfallart ersetzt, Strauchschnitt behält seinen Namen")
        XCTAssertEqual(pickups.first?.date, Days.parse("2026-10-05", calendar: calendar))
        XCTAssertEqual(WasteCategory.classify(pickups[0].name), .residual)
        XCTAssertEqual(WasteCategory.classify(pickups[1].name), .packaging)
        XCTAssertEqual(WasteCategory.classify(pickups[2].name), .organic)
        XCTAssertEqual(WasteCategory.classify(pickups[3].name), .paper)
        XCTAssertEqual(WasteCategory.classify(pickups[4].name), .residual)
    }

    func testPickupsWithoutNameLists() {
        // Fallen die Namenslisten aus, bleiben nur Tage ohne Namen übrig – die werden verworfen statt „Typ 2“ zu zeigen.
        XCTAssertTrue(NordPortalsProvider.ahkPickups(days: Data(Self.days.utf8), icons: Data(), types: Data(), calendar: calendar).isEmpty)
    }

    func testPickupsTypesOnly() {
        // Fällt nur die Icon-Liste aus, tragen die Abfallarten (IDs dort als Kommazahl „2.0“).
        let pickups = NordPortalsProvider.ahkPickups(days: Data(Self.days.utf8), icons: Data(), types: Data(Self.types.utf8), calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Restabfall", "Gelbe Tonne", "Bio- und Gartenabfall", "Altpapier", "Restabfall"])
    }

    func testLabel() {
        let provider = NordPortalsProvider(service: "heidekreis")
        let s = [SelectionOption(id: "Wagner", title: "Wagner"),
                 SelectionOption(id: "4711", title: "Wagnerstr.", subtitle: "29633 Munster"),
                 SelectionOption(id: "90001", title: "10-18")]
        XCTAssertEqual(provider.label(for: s), "Munster, Wagnerstr. 10-18")
        XCTAssertEqual(provider.displayName, "Abfallwirtschaft Heidekreis")
    }

    /// Ganzer Ablauf mit nachgestellten Antworten: prüft URLs, Kopfzeilen und den POST-Körper.
    func testFlowAgainstStub() async throws {
        let client = HTTPClient(session: AHKStub.session())
        let provider = NordPortalsProvider(service: "heidekreis", client: client)

        let first = try await provider.nextStep(after: [])
        XCTAssertEqual(first?.input, .text)

        let search = SelectionOption(id: "Wagner", title: "Wagner")
        let streets = try await provider.nextStep(after: [search])
        XCTAssertEqual(streets?.options.first?.title, "Wagnerstr.")

        let street = try XCTUnwrap(streets?.options.first { $0.subtitle == "29633 Munster" })
        let numbers = try await provider.nextStep(after: [search, street])
        let number = try XCTUnwrap(numbers?.options.first { $0.title == "10-18" })
        let done = try await provider.nextStep(after: [search, street, number])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [search, street, number], calendar: calendar)
        XCTAssertEqual(pickups.count, 6)

        let requests = AHKStub.requests()
        let search1 = try XCTUnwrap(requests.first { $0.url.contains("QStreetByPartialName") })
        XCTAssertTrue(search1.url.hasSuffix("PartialName=Wagner"))
        XCTAssertEqual(search1.headers["Referer"], "https://ahkweb.heidekreis.de/")
        XCTAssertEqual(search1.headers["Origin"], "https://ahkweb.heidekreis.de")
        let house = try XCTUnwrap(requests.first { $0.url.contains("QHouseNrEkal") })
        XCTAssertEqual(house.method, "POST")
        XCTAssertEqual(house.body, "[84106]")
        XCTAssertEqual(house.headers["Content-Type"], "application/json")
        let daysRequest = try XCTUnwrap(requests.first { $0.url.contains("QDisposaldays") })
        XCTAssertTrue(daysRequest.url.contains("idObject=13636&from="), daysRequest.url)
        XCTAssertNotNil(daysRequest.url.range(of: #"from=\d{2}%2F\d{2}%2F\d{4}&to=\d{2}%2F\d{2}%2F\d{4}$"#, options: .regularExpression), daysRequest.url)
    }

    func testShortSearchRejected() async {
        let provider = NordPortalsProvider(service: "heidekreis", client: HTTPClient(session: AHKStub.session()))
        do {
            _ = try await provider.nextStep(after: [SelectionOption(id: "Wa", title: "Wa")])
            XCTFail("Fehler erwartet")
        } catch {}
    }

    func testLiveHeidekreis() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = NordPortalsProvider(service: "heidekreis")
        let search = SelectionOption(id: "Wagnerstr", title: "Wagnerstr")
        let streets = try await provider.nextStep(after: [search])
        let street = try XCTUnwrap(streets?.options.first { $0.subtitle?.contains("Munster") == true })
        let numbers = try await provider.nextStep(after: [search, street])
        let number = try XCTUnwrap(numbers?.options.first { $0.title == "10-18" } ?? numbers?.options.first)
        let pickups = try await provider.pickups(for: [search, street, number], calendar: calendar)
        XCTAssertGreaterThanOrEqual(pickups.count, 3)
        print("Heidekreis:", pickups.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })
    }
}

/// Nachgestellte AHK-API für die Tests.
final class AHKStub: URLProtocol {
    struct Seen { let url: String; let method: String; let headers: [String: String]; let body: String }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AHKStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "ahkwebapi.heidekreis.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        }
        Self.lock.lock()
        Self.seen.append(Seen(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:],
                              body: body.map { String(decoding: $0, as: UTF8.self) } ?? ""))
        Self.lock.unlock()

        let json: String
        if url.contains("QStreetByPartialName") { json = HeidekreisTests.streets }
        else if url.contains("QHouseNrEkal") { json = HeidekreisTests.houseNumbers }
        else if url.contains("QDisposalDayIcons") { json = HeidekreisTests.icons }
        else if url.contains("QDisposalTypes") { json = HeidekreisTests.types }
        else if url.contains("QDisposaldays") { json = HeidekreisTests.days }
        else { json = "[]" }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
