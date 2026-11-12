import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// Wetteraukreis: Glauburg, Niddatal, Wöllstadt und Ortenberg führen auf mein-abfallkalender.online nur „gefährliche
/// Abfälle“ (Messung 12.11.2026). Die regulären Termine stehen als ICS auf den Gemeindeseiten; angebunden über den
/// vorhandenen ICS-Weg (Direktlink bzw. `#link=`). Gekürzte echte Antworten vom 12.11.2026.
final class WetterauQuellenTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func event(_ date: String, _ summary: String, extra: String = "") -> String {
        "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:\(date)\r\n\(extra)SUMMARY:\(summary)\r\nEND:VEVENT\r\n"
    }

    private func ics(_ events: String) -> String { "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(events)END:VCALENDAR\r\n" }

    /// Niddatal: je Stadtteil eine Jahresdatei mit wechselndem Upload-Pfad; der Link wird auf der Seite gesucht.
    func testNiddatalYearFileFromPage() async throws {
        let year = calendar.component(.year, from: Date())
        QuellenStub.routes = [
            ("abfallkalender_assenheim\(year).ics", ics(event("\(year)1215", "Restmüll") + event("\(year)1217", "Bioabfall"))),
            ("niddatal.de/leben-in-niddatal", """
            <a href="/wp-content/uploads/go-x/u/f8bd8ff4/abfallkalender_assenheim\(year).ics">Assenheim \(year).ics</a>
            <a href="/wp-content/uploads/go-x/u/1f26f53b/abfallkalender_boenstadt\(year).ics">Bönstadt \(year).ics</a>
            """),
        ]
        let provider = ICSURLProvider(url: "https://niddatal.de/leben-in-niddatal/abfallentsorgung/#link=abfallkalender_assenheim{%Y}.ics", client: QuellenStub.client())
        XCTAssertTrue(provider.isDirectLink)
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Restmüll", "Bioabfall"])
        XCTAssertTrue(QuellenStub.urls().contains { $0.contains("/go-x/u/f8bd8ff4/abfallkalender_assenheim\(year).ics") }, "Datei des gewählten Stadtteils")
    }

    /// Wöllstadt: Die iCal-Datei liefert nur mit der Sitzungskennung `sid` der Terminseite Termine.
    func testWoellstadtIcalWithSessionFromPage() async throws {
        QuellenStub.routes = [
            ("ical.php", "SID"),
            ("modules=events", """
            <a href="ical.php?websiteid=normal&amp;modus=5&amp;tag=12&amp;monat=11&amp;jahr=2026&amp;field1=16~d843cea749c116ae9e06f0f7c4dd2e0e&amp;field2=-1&amp;unid=-1&amp;sid=c56c678388f003d2952c20f306faa07a&amp;dummy=" title="iCal-Datei">iCal-Datei</a>
            """),
        ]
        QuellenStub.icsWithSession = ics(event("20261124", "Hausmüll") + event("20261126", "Gelbe Tonne") + event("20261201", "Bioabfall"))
        let provider = ICSURLProvider(url: "https://www.woellstadt.de/index.html?eventtyp=6&field2=-1&field1=16~d843cea749c116ae9e06f0f7c4dd2e0e&modules=events&ansicht=3#link=ical.php", client: QuellenStub.client())
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Hausmüll", "Gelbe Tonne", "Bioabfall"])
        XCTAssertTrue(QuellenStub.urls().contains { $0.contains("ical.php") && $0.contains("sid=c56c678388f003d2952c20f306faa07a") && !$0.contains("&amp;") })
    }

    /// Ortenberg/Glauburg: öffentliche Google-Kalender je Ortsteil; alte Serien (RRULE mit COUNT/UNTIL) laufen nicht in die Zukunft.
    func testOrtenbergGoogleCalendarOldSeriesStayInPast() async throws {
        let old = event("20150105", "Restmüll", extra: "RRULE:FREQ=WEEKLY;COUNT=2;INTERVAL=4;BYDAY=FR\r\n")
            + event("20250106", "Biomüll", extra: "RRULE:FREQ=WEEKLY;WKST=MO;UNTIL=20251231;INTERVAL=3;BYDAY=MO\r\n")
        QuellenStub.routes = [("calendar/ical", ics(old + event("20261104", "Sondermüll Recyclinghof/Biomüll") + event("20261109", "Restmüll")
                                                    + event("20261111", "Papiermüll") + event("20261119", "Gelbe Tonne")))]
        let provider = ICSURLProvider(url: "webcal://www.google.com/calendar/ical/bv9129oo9fogiatn5o39ppkgpg%40group.calendar.google.com/public/basic.ics", client: QuellenStub.client())
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        let fromNovember = pickups.filter { Days.iso($0.date, calendar: calendar) >= "2026-11-01" }
        XCTAssertEqual(fromNovember.map { Days.iso($0.date, calendar: calendar) + " " + $0.name },
                       ["2026-11-04 Biomüll", "2026-11-04 Sondermüll Recyclinghof", "2026-11-09 Restmüll", "2026-11-11 Papiermüll", "2026-11-19 Gelbe Tonne"])
        XCTAssertFalse(pickups.contains { Days.iso($0.date, calendar: calendar) > "2025-12-31" && Days.iso($0.date, calendar: calendar) < "2026-11-01" }, "Serien enden mit COUNT/UNTIL")
    }

    /// Wölfersheim/Limeshain: Die Gemeinde-App (feed.gemeindeapp.de) liefert je Ortsteil einen ICS-Feed; die Zeile
    /// `DTSTART;VALUE=DATE;VALUE=DATE:` trägt den Parameter doppelt. Gekürzte echte Antwort vom 12.11.2026.
    func testGemeindeAppFeedWithDoubledDateParameter() async throws {
        let feed = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:icalendar-ruby\r\nX-WR-CALNAME;VALUE=TEXT:Wölfersheim\r\n"
            + ["20261124 Restmüll", "20261124 Gelbe Tonne", "20261125 Biomüll", "20261130 Papier"].map { entry -> String in
                let parts = entry.split(separator: " ", maxSplits: 1).map(String.init)
                return "BEGIN:VEVENT\r\nUID:x\(parts[0])\(parts[1].count)\r\nDTSTART;VALUE=DATE;VALUE=DATE:\(parts[0])\r\nLOCATION:Södel\\, Wölfersheim\r\nSUMMARY:\(parts[1])\r\nEND:VEVENT\r\n"
            }.joined() + "END:VCALENDAR\r\n"
        QuellenStub.routes = [("garbage_disposals.ics?district_id=9", feed)]
        let provider = ICSURLProvider(url: "webcal://feed.gemeindeapp.de/v1/communities/2/garbage_disposals.ics?district_id=9", client: QuellenStub.client())
        XCTAssertTrue(provider.isDirectLink)
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        XCTAssertEqual(pickups.map { Days.iso($0.date, calendar: calendar) + " " + $0.name },
                       ["2026-11-24 Gelbe Tonne", "2026-11-24 Restmüll", "2026-11-25 Biomüll", "2026-11-30 Papier"])
    }

    /// Pirmasens: Kalender je Straße (`waste.ical`), alle Straßen eines der zehn Abfuhrbezirke M1–M10 haben denselben Kalender.
    /// Das Jahr kommt als `{%Y}`; die Datei fürs Folgejahr gibt es ab November erst später (404) und bleibt still weg.
    func testPirmasensWasteCalendarPerDistrictStreet() async throws {
        let year = calendar.component(.year, from: Date())
        let event = { (d: String, name: String) in "BEGIN:VEVENT\r\nDTSTAMP:20261112T103931\r\nUID:waste-\(name)-\(d)\r\nDTSTART;VALUE=DATE:\(d)\r\nDURATION:P1D\r\nSUMMARY:\(name)\r\nCLASS:PUBLIC\r\nEND:VEVENT\r\n" }
        QuellenStub.routes = [("waste.ical?street=Adolf-Ludwig-Ring&year=\(year)&parent=132751",
                               ics(event("\(year)1214", "Restmüll") + event("\(year)1215", "Gelber Sack / Gelbe Tonne") + event("\(year)1216", "Papier") + event("\(year)1218", "Biomüll")))]
        let provider = ICSURLProvider(url: "https://www.pirmasens.de/:c_c_a_wasteCalendar/waste.ical?street=Adolf-Ludwig-Ring&year={%Y}&parent=132751", client: QuellenStub.client())
        XCTAssertTrue(provider.isDirectLink)
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        XCTAssertEqual(Set(pickups.map(\.name)), ["Restmüll", "Gelber Sack / Gelbe Tonne", "Papier", "Biomüll"])
        XCTAssertEqual(pickups.count, 4)
    }

    /// Gladbeck (ZBG): Straße aus der Liste der Seite, Hausnummer als Text, Kalender von `?format=ical&street=…&number=…`.
    func testGladbeckStreetAndHouseNumber() async throws {
        QuellenStub.routes = [
            ("format=ical&street=31B56D20&number=12", ics(event("20261118", "Graue Tonne") + event("20261117", "Wertstofftonne") + event("20261125", "Braune Tonne") + event("20261118", "Blaue Tonne"))),
            ("zb-gladbeck.de/abfuhrkalender", """
            <select class="form-control" name="street" style="display: none;" required>
            <option selected="selected" disabled="disabled" value=""> Gib deine Straße an </option>
            <option value="31B56D20" > Adlerstraße </option>
            <option value="B7FECCC7" > Agathastraße </option>
            </select>
            """),
        ]
        let provider = ICSURLProvider(url: "https://www.zb-gladbeck.de/abfuhrkalender#adresse-zbg", client: QuellenStub.client())
        XCTAssertFalse(provider.isDirectLink)
        let streets = try await provider.nextStep(after: [])
        XCTAssertEqual(streets?.options.map(\.title), ["Adlerstraße", "Agathastraße"])
        let street = try XCTUnwrap(streets?.options.first)
        let number = try await provider.nextStep(after: [street])
        XCTAssertEqual(number?.input, .text)
        let done = try await provider.nextStep(after: [street, SelectionOption(id: "12", title: "12")])
        XCTAssertNil(done)
        let pickups = try await provider.pickups(for: [street, SelectionOption(id: "12", title: "12")], calendar: calendar)
        XCTAssertEqual(Set(pickups.map(\.name)), ["Graue Tonne", "Wertstofftonne", "Braune Tonne", "Blaue Tonne"])
        XCTAssertTrue(QuellenStub.urls().contains { $0.contains("format=ical&street=31B56D20&number=12") })
        XCTAssertEqual(provider.label(for: [street, SelectionOption(id: "12", title: "12")]), "Adlerstraße, 12")
    }

    /// Live: TONNE_LIVE=1 – druckt kommende Termine und Müllarten je Quelle.
    func testLive() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        for key in Self.liveKeys {
            let pickups = try await ICSURLProvider(url: key).pickups(for: [], calendar: .current)
            let future = pickups.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
            let last = pickups.map(\.date).max().map { Days.iso($0, calendar: .current) } ?? "-"
            print("LIVE \(future.count) kommend bis \(last): \(Set(future.map(\.name)).sorted().joined(separator: ", ")) – \(key.prefix(90))")
            XCTAssertGreaterThan(future.count, 3, key)
        }
    }

    static let liveKeys = [
        "https://calendar.google.com/calendar/ical/59b4a0a670fd813f5ac895880e3b8c7fe9a2d4e8a3d7e3ad2de30f7e7276f526%40group.calendar.google.com/public/basic.ics",
        "https://calendar.google.com/calendar/ical/46c2118aa324d7eca670e08455132ecfff13511238a0cb6fb97182e627439d1b%40group.calendar.google.com/public/basic.ics",
        "https://niddatal.de/leben-in-niddatal/abfallentsorgung/#link=abfallkalender_assenheim{%Y}.ics",
        "https://niddatal.de/leben-in-niddatal/abfallentsorgung/#link=abfallkalender_boenstadt{%Y}.ics",
        "https://niddatal.de/leben-in-niddatal/abfallentsorgung/#link=abfallkalender_ilbenstadt{%Y}.ics",
        "https://niddatal.de/leben-in-niddatal/abfallentsorgung/#link=abfallkalender_kaichen{%Y}.ics",
        "https://www.woellstadt.de/index.html?eventtyp=6&field2=-1&field1=16~d843cea749c116ae9e06f0f7c4dd2e0e&modules=events&ansicht=3#link=ical.php",
        "https://www.woellstadt.de/index.html?eventtyp=6&field2=-1&field1=14~a1aa578fba0cc281e91efb660ef44f2a&modules=events&ansicht=3#link=ical.php",
    ] + ["u2sn3fvlm5hqjjp1amh389kc50", "ee7kq0m7jln0auphop8sn9ukeo", "3ap04dhsqjc0nun1qv6i9g8smo", "90d2re9e503bflo2fpj2d5n0f8", "63vhrpn9rv6pgmi1k76afcnddo",
         "0lrere4fs4prg929jui6l3mrtk", "bv9129oo9fogiatn5o39ppkgpg", "4gqnolu03kqdj7ssoigeie5h2k", "5gbpuc92iqvn4s549hhgvrn0rk", "37uj3rpv42budis1q6d6nb810g"]
        .map { "webcal://www.google.com/calendar/ical/\($0)%40group.calendar.google.com/public/basic.ics" }
        + [9, 11, 12, 13, 14].map { "webcal://feed.gemeindeapp.de/v1/communities/2/garbage_disposals.ics?district_id=\($0)" }
        + [20, 21, 22, 23].map { "webcal://feed.gemeindeapp.de/v1/communities/6/garbage_disposals.ics?district_id=\($0)" }
        + ["Adolf-Ludwig-Ring", "Albert-Schweitzer-Straße", "Bergstraße", "Akazienweg", "Albert-Bastian-Weg", "Adalbert-Stifter-Straße",
           "Adlerstraße", "Denkmalstraße", "Castellstraße", "Bismarckstraße"]
            .map { "https://www.pirmasens.de/:c_c_a_wasteCalendar/waste.ical?street=\(HTTPClient.query($0))&year={%Y}&parent=132751" }

    /// Live Gladbeck: Straße aus der Seitenliste, Hausnummer 12.
    func testLiveGladbeck() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = ICSURLProvider(url: "https://www.zb-gladbeck.de/abfuhrkalender#adresse-zbg")
        let firstStep = try await provider.nextStep(after: [])
        let streets = try XCTUnwrap(firstStep)
        let street = try XCTUnwrap(streets.options.first { $0.title == "Adlerstraße" })
        let pickups = try await provider.pickups(for: [street, SelectionOption(id: "12", title: "12")], calendar: .current)
        let future = pickups.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
        print("LIVE Gladbeck \(streets.options.count) Straßen; \(future.count) kommend: \(Set(future.map(\.name)).sorted().joined(separator: ", "))")
        XCTAssertGreaterThan(future.count, 3)
    }
}

/// Antwortet je nach Adress-Teil (erster Treffer in `routes`). „SID“: ICS nur, wenn die Anfrage eine `sid` trägt.
final class QuellenStub: URLProtocol {
    nonisolated(unsafe) static var routes: [(String, String)] = []
    nonisolated(unsafe) static var icsWithSession = ""
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func client() -> HTTPClient {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QuellenStub.self]
        return HTTPClient(session: URLSession(configuration: config))
    }

    static func urls() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.lock.lock(); Self.seen.append(url); Self.lock.unlock()
        var body = Self.routes.first { url.contains($0.0) }?.1
        if body == "SID" {
            body = url.range(of: #"sid=[0-9a-f]+"#, options: .regularExpression) != nil ? Self.icsWithSession : "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "nicht gefunden").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
