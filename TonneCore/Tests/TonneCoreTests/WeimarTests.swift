import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// KS Weimar: Der Entsorgungsplan ist eine HTML-Tabelle mit Wochentag + gerade/ungerade Kalenderwoche je Straße;
/// die Termine rechnet die App selbst. Live-Test nur mit TONNE_LIVE=1.
final class WeimarTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func day(_ iso: String) -> Date { Days.parse(iso, calendar: calendar)! }

    // Echte Tabelle der Seite (Oktober 2026), auf einige Zeilen gekürzt – samt Tippfehlern und leeren Zellen.
    static let page = #"""
    <html><body><div class="table-responsive"><table class="filterable contenttable table w-100  "><tr><th  ><div>Nr.</div></th><th  ><div>Straße</div></th><th  ><div>Entsorgungstag Zweirad<br>
        60l -240l Restmülltonnen<br>Biotonnen 80l -240l<br>
    sowie
    Papiertonnen 120l und 1100l
    </div></th><th  class='header'><div>Entsorgungstag Vierrad<br>
          1100l Restmülltonnen / wöchentlich</div></th></tr><tr><td>1</td><td>Abraham-Lincoln-Straße</td><td>Donnerstag ungerade Kalenderwoche</td><td>Montag gerade und ungerade Kalenderwoche</td></tr><tr><td>2</td><td>Ackerwand</td><td>Mittwoch ungerade Kalenderwoche</td><td>&nbsp;</td></tr><tr><td>3</td><td>Ahornallee</td><td>Dienstag gerade Kalenderwoche</td><td>&nbsp;</td></tr><tr><td>18</td><td>Am Berge</td><td></td><td>&nbsp;</td></tr><tr><td>138</td><td>Brucknerstraße</td><td>Donnerstag ungerade Kalenderwoche</td><td>Montag</td></tr><tr><td>249</td><td>Hämeenlinnaer Straße</td><td>Fr uKw</td><td>&nbsp;</td></tr><tr><td>615</td><td>Wolfsgasse</td><td>Mikl gKw</td><td>&nbsp;</td></tr></table></div></body></html>
    """#

    func testPlanParsing() {
        let plan = MitteldeutschlandPortalsProvider.weimarPlan(Self.page)
        XCTAssertEqual(plan.map(\.name), ["Abraham-Lincoln-Straße", "Ackerwand", "Ahornallee", "Am Berge", "Brucknerstraße",
                                          "Hämeenlinnaer Straße", "Wolfsgasse"], "Kopfzeile (th) ist keine Straße")
        XCTAssertEqual(plan[0].regular, "Donnerstag ungerade Kalenderwoche")
        XCTAssertEqual(plan[0].large, "Montag gerade und ungerade Kalenderwoche")
        XCTAssertEqual(plan[1].large, "", "&nbsp; zählt als leer")
    }

    func testRules() {
        typealias P = MitteldeutschlandPortalsProvider
        XCTAssertTrue(P.weimarRule("Mittwoch ungerade Kalenderwoche")! == (4, 1))
        XCTAssertTrue(P.weimarRule("Dienstag gerade Kalenderwoche")! == (3, 0))
        XCTAssertTrue(P.weimarRule("Fr uKw")! == (6, 1))
        XCTAssertTrue(P.weimarRule("Mikl gKw")! == (4, 0), "Wolfsgasse: im Kalender 2014 „Mi gKw“")
        XCTAssertTrue(P.weimarRule("Montag gerade und ungerade Kalenderwoche")! == (2, nil))
        XCTAssertNil(P.weimarRule(""))
        XCTAssertNil(P.weimarRule("Montag"), "ohne Woche ist der Zweirad-Rhythmus unklar")
        XCTAssertTrue(P.weimarRule("Montag", weekly: true)! == (2, nil), "1100-l-Spalte ist laut Kopf wöchentlich")
        XCTAssertNil(P.weimarRule("", weekly: true))
    }

    func testPickupsRegular() throws {
        let plan = MitteldeutschlandPortalsProvider.weimarPlan(Self.page)
        let street = try XCTUnwrap(plan.first { $0.name == "Ackerwand" })
        let start = day("2026-10-09")
        let pickups = MitteldeutschlandPortalsProvider.weimarPickups(street, large: false, from: start, calendar: calendar)
        let dates = Array(Set(pickups.map(\.date))).sorted()
        // 07.10. (KW 41) liegt vor dem Start, 14.10. ist KW 42 (gerade) → erster Termin 21.10. (KW 43).
        XCTAssertEqual(dates.prefix(3).map { Days.iso($0) }, ["2026-10-21", "2026-11-04", "2026-11-18"])
        XCTAssertEqual(Set(pickups.filter { $0.date == dates[0] }.map(\.name)), ["Restmüll", "Biotonne", "Papier", "Gelbe Tonne"])
        XCTAssertEqual(Set(pickups.map { WasteCategory.classify($0.name) }), [.residual, .organic, .paper, .packaging])
        XCTAssertEqual(pickups.first?.note, L10n.t("Mittwoch in ungeraden Kalenderwochen", "Wednesday in odd calendar weeks"))
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        for date in dates {
            XCTAssertEqual(calendar.component(.weekday, from: date), 4)
            XCTAssertEqual(iso.component(.weekOfYear, from: date) % 2, 1, Days.iso(date))
        }
        XCTAssertTrue((25...27).contains(dates.count), "etwa ein Jahr im 14-täglichen Rhythmus: \(dates.count)")

        let friday = try XCTUnwrap(plan.first { $0.name == "Hämeenlinnaer Straße" })
        let fridays = MitteldeutschlandPortalsProvider.weimarPickups(friday, large: false, from: start, calendar: calendar)
        XCTAssertEqual(fridays.map(\.date).min().map { Days.iso($0) }, "2026-10-09", "Starttag zählt mit")
        let even = try XCTUnwrap(plan.first { $0.name == "Ahornallee" })
        XCTAssertEqual(MitteldeutschlandPortalsProvider.weimarPickups(even, large: false, from: start, calendar: calendar)
            .map(\.date).min().map { Days.iso($0) }, "2026-10-13")
    }

    func testPickupsLargeContainer() throws {
        let street = try XCTUnwrap(MitteldeutschlandPortalsProvider.weimarPlan(Self.page).first { $0.name == "Abraham-Lincoln-Straße" })
        let pickups = MitteldeutschlandPortalsProvider.weimarPickups(street, large: true, from: day("2026-10-09"), calendar: calendar)
        let residual = pickups.filter { $0.name == "Restmüll" }.map(\.date).sorted()
        XCTAssertEqual(residual.prefix(3).map { Days.iso($0) }, ["2026-10-12", "2026-10-19", "2026-10-26"], "1100 l: jeden Montag")
        XCTAssertEqual(residual.first.flatMap { d in pickups.first { $0.date == d }?.note }, L10n.t("Jeden Montag", "Every Monday"))
        let bio = pickups.filter { $0.name == "Biotonne" }.map(\.date).sorted()
        XCTAssertEqual(bio.prefix(2).map { Days.iso($0) }, ["2026-10-22", "2026-11-05"], "übrige Tonnen bleiben am Donnerstag ungerade KW")
        XCTAssertFalse(pickups.contains { $0.name == "Restmüll" && calendar.component(.weekday, from: $0.date) == 5 })
    }

    func testLabel() {
        let provider = MitteldeutschlandPortalsProvider(service: "weimar")
        XCTAssertEqual(provider.label(for: [SelectionOption(id: "Ackerwand", title: "Ackerwand")]), "Weimar, Ackerwand")
        XCTAssertEqual(provider.label(for: [SelectionOption(id: "Abraham-Lincoln-Straße", title: "Abraham-Lincoln-Straße"),
                                            SelectionOption(id: "1100", title: "1100-l-Behälter, wöchentliche Leerung")]),
                       "Weimar, Abraham-Lincoln-Straße")
        XCTAssertEqual(provider.displayName, "Kommunalservice Weimar")
    }

    /// Ganzer Ablauf gegen die nachgestellte Seite: Straßenliste, Behälterwahl nur bei 1100-l-Spalte, Termine.
    func testFlowAgainstStub() async throws {
        let provider = MitteldeutschlandPortalsProvider(service: "weimar", client: HTTPClient(session: WeimarStub.session()))

        let streets = try await provider.nextStep(after: [])
        XCTAssertEqual(streets?.title, SelectionStep.streetTitle)
        XCTAssertEqual(streets?.options.map(\.title), ["Abraham-Lincoln-Straße", "Ackerwand", "Ahornallee", "Brucknerstraße",
                                                       "Hämeenlinnaer Straße", "Wolfsgasse"], "Straße ohne Termin fällt weg")

        let ackerwand = try XCTUnwrap(streets?.options.first { $0.title == "Ackerwand" })
        let none = try await provider.nextStep(after: [ackerwand])
        XCTAssertNil(none, "ohne 1100-l-Spalte keine Behälterwahl")
        let pickups = try await provider.pickups(for: [ackerwand], calendar: calendar)
        XCTAssertFalse(pickups.isEmpty)
        XCTAssertTrue(pickups.allSatisfy { calendar.component(.weekday, from: $0.date) == 4 })

        let lincoln = try XCTUnwrap(streets?.options.first { $0.title == "Abraham-Lincoln-Straße" })
        let bins = try await provider.nextStep(after: [lincoln])
        XCTAssertEqual(bins?.options.map(\.id), ["zweirad", "1100"])
        let large = try XCTUnwrap(bins?.options.last)
        let done = try await provider.nextStep(after: [lincoln, large])
        XCTAssertNil(done)
        let weekly = try await provider.pickups(for: [lincoln, large], calendar: calendar)
        XCTAssertTrue(weekly.filter { $0.name == "Restmüll" }.allSatisfy { calendar.component(.weekday, from: $0.date) == 2 })

        do {
            _ = try await provider.pickups(for: [SelectionOption(id: "Gibtsnicht", title: "Gibtsnicht")], calendar: calendar)
            XCTFail("Fehler erwartet")
        } catch {}

        let requests = WeimarStub.requests()
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { $0 == "GET " + MitteldeutschlandPortalsProvider.weimarURL }, "\(requests)")
    }

    func testLiveWeimar() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = MitteldeutschlandPortalsProvider(service: "weimar")
        let streets = try await provider.nextStep(after: [])
        XCTAssertGreaterThan(streets?.options.count ?? 0, 600)
        let ackerwand = try XCTUnwrap(streets?.options.first { $0.title == "Ackerwand" })
        let pickups = try await provider.pickups(for: [ackerwand], calendar: calendar)
        XCTAssertEqual(Set(pickups.map(\.name)), ["Restmüll", "Biotonne", "Papier", "Gelbe Tonne"])
        XCTAssertGreaterThanOrEqual(pickups.first.map(\.date) ?? .distantPast, Days.today(calendar: calendar))
        print("Weimar Ackerwand:", pickups.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })

        let lincoln = try XCTUnwrap(streets?.options.first { $0.title == "Abraham-Lincoln-Straße" })
        let bins = try await provider.nextStep(after: [lincoln])
        let large = try XCTUnwrap(bins?.options.first { $0.id == "1100" })
        let weekly = try await provider.pickups(for: [lincoln, large], calendar: calendar)
        print("Weimar Abraham-Lincoln-Straße 1100 l:", weekly.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })
        XCTAssertTrue(weekly.contains { $0.name == "Restmüll" })
    }
}

/// Nachgestellte Seite des KS Weimar.
final class WeimarStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeimarStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "ks-weimar.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seen.append("\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(WeimarTests.page.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
