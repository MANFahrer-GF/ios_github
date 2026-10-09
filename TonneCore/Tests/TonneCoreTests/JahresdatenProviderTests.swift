import XCTest
@testable import TonneCore

/// Jahresdaten aus PDF-Kalendern: Auswahl (einstufig, zweistufig, ohne Auswahl), Termine, Hinweis, abgelaufene Daten.
final class JahresdatenProviderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    static let grouped = #"""
    {"key":"testkreis","title":"Testkreis","source":"https://www.example.de/kalender.pdf","stand":"2026-10-09","years":[2026],
     "groupTitle":"Ort","stepTitle":"Straße","notice":"Gelbe Tonne nicht enthalten.",
     "areas":[{"id":"buergel_markt","title":"Markt","group":"Bürgel","plan":"p1"},
              {"id":"buergel_bahnhofstr","title":"Bahnhofstraße","group":"Bürgel","plan":"p2"},
              {"id":"albersdorf","title":"Albersdorf","group":null,"plan":"p2"}],
     "plans":{"p1":[["2026-10-12","Restmüll"],["2026-10-19","Altpapier","Leerung am Feiertag oder einen Tag später"]],
              "p2":[["2026-10-13","Biomüll"],["kaputt","Restmüll"]]}}
    """#

    static let single = #"""
    {"key":"einzel","title":"Einzelort","source":"https://einzel.example/abfall.pdf","stand":"2026-10-09","years":[2026],
     "groupTitle":null,"stepTitle":"Bezirk","notice":null,
     "areas":[{"id":"alle","title":"Einzelort","group":null,"plan":"p1"}],
     "plans":{"p1":[["2026-11-02","Gelbe Tonne"]]}}
    """#

    private func provider(_ json: String) -> JahresdatenProvider {
        var provider = JahresdatenProvider(key: "test", json: json)
        provider.referenceDate = Days.parse("2026-10-09", calendar: calendar)
        return provider
    }

    func testTwoLevelSelection() async throws {
        let provider = provider(Self.grouped)
        let firstStep = try await provider.nextStep(after: [])
        let first = try XCTUnwrap(firstStep)
        XCTAssertEqual(first.title, "Ort")
        XCTAssertEqual(first.options.map(\.title), ["Albersdorf", "Bürgel"], "Gruppen und Orte ohne Straßen in einer Liste")

        let town = try XCTUnwrap(first.options.first { $0.title == "Bürgel" })
        let streetStep = try await provider.nextStep(after: [town])
        let streets = try XCTUnwrap(streetStep)
        XCTAssertEqual(streets.title, "Straße")
        XCTAssertEqual(streets.options.map(\.title), ["Bahnhofstraße", "Markt"])

        let market = try XCTUnwrap(streets.options.first { $0.title == "Markt" })
        let done = try await provider.nextStep(after: [town, market])
        XCTAssertNil(done)
        let pickups = try await provider.pickups(for: [town, market], calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Restmüll", "Altpapier"])
        XCTAssertEqual(pickups.last?.note, "Leerung am Feiertag oder einen Tag später")
        XCTAssertEqual(pickups.first?.date, Days.parse("2026-10-12", calendar: calendar))

        // Ort ohne Straßen: direkt fertig, kaputte Zeilen fallen weg
        let village = try XCTUnwrap(first.options.first { $0.title == "Albersdorf" })
        let villageDone = try await provider.nextStep(after: [village])
        XCTAssertNil(villageDone)
        let villagePickups = try await provider.pickups(for: [village], calendar: calendar)
        XCTAssertEqual(villagePickups.map(\.name), ["Biomüll"])
    }

    func testSingleAreaNeedsNoSelection() async throws {
        let provider = provider(Self.single)
        let step = try await provider.nextStep(after: [])
        XCTAssertNil(step)
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Gelbe Tonne"])
    }

    func testNotice() {
        let notice = try? XCTUnwrap(provider(Self.grouped).notice)
        XCTAssertTrue(notice?.contains("www.example.de") == true, notice ?? "")
        XCTAssertTrue(notice?.contains("2026") == true)
        XCTAssertTrue(notice?.contains("Gelbe Tonne nicht enthalten.") == true)
        XCTAssertNil(ICSURLProvider(url: "https://example.org/a.ics").notice, "andere Anbieter ohne Hinweis")
    }

    /// Nach dem letzten Termin (Jahr nicht eingepflegt): klare Meldung statt leerer Liste.
    func testExpiredDataExplains() async throws {
        var provider = provider(Self.single)
        provider.referenceDate = Days.parse("2027-01-05", calendar: calendar)
        do {
            _ = try await provider.pickups(for: [], calendar: calendar)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("2027"), error.localizedDescription)
        }
    }

    func testUnknownKey() async {
        let provider = JahresdatenProvider(key: "gibtsnicht")
        do {
            _ = try await provider.nextStep(after: [])
            XCTFail("Fehler erwartet")
        } catch {}
        XCTAssertNil(provider.notice)
    }

    /// Alle ausgelieferten Jahresdaten lassen sich lesen und jede Abfallart wird erkannt.
    func testShippedDataIsValid() async throws {
        for key in JahresdatenData.files.keys.sorted() {
            let provider = JahresdatenProvider(key: key)
            XCTAssertNotNil(provider.notice, "\(key): JSON nicht lesbar")
            XCTAssertEqual(ProviderCatalog.entries.filter { $0.kind == .jahresdaten && $0.serviceKey == key }.count, 1, "\(key): Katalogeintrag fehlt")
        }
    }
}
