import XCTest
@testable import TonneCore

/// Bischofsheim (Landkreis Groß-Gerau): Kalender nur als Bild, von Hand abgelesen (tools/pdfkalender/orte/bischofsheim.py).
/// Stichproben aus dem Bild je Bezirk und Müllart, mit den gedruckten Verschiebungen (Ostern, Pfingsten, Kerb, Weihnachten).
final class BischofsheimJahresdatenTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Alle Termine einer Straße als Menge „JJJJ-MM-TT Art“.
    private func termine(_ street: String) async throws -> Set<String> {
        var provider = JahresdatenProvider(key: "bischofsheim")
        provider.referenceDate = Days.parse("2026-01-01", calendar: calendar)
        let firstStep = try await provider.nextStep(after: [])
        let step = try XCTUnwrap(firstStep)
        XCTAssertEqual(step.title, "Straße")
        let option = try XCTUnwrap(step.options.first { $0.id == street }, "\(street) fehlt")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return Set(try await provider.pickups(for: [option], calendar: calendar).map { "\(formatter.string(from: $0.date)) \($0.name)" })
    }

    private func zaehlung(_ termine: Set<String>) -> [String: Int] {
        termine.reduce(into: [:]) { $0[String($1.dropFirst(11)), default: 0] += 1 }
    }

    func testBezirk1Montag() async throws {
        let bez1 = try await termine("alemannenweg")
        for t in ["2026-01-05 Restmüll", "2026-01-05 Biomüll", "2026-03-28 Restmüll", "2026-04-07 Altpapier", "2026-05-26 Biomüll",
                  "2026-09-09 Altpapier", "2026-12-19 Restmüll", "2026-12-28 Altpapier"] {
            XCTAssertTrue(bez1.contains(t), t)
        }
        // Gegenprobe: Termine von Bezirk 2 und der ausgefallene Kerb-Montag gehören nicht dazu
        for t in ["2026-01-06 Restmüll", "2026-03-30 Restmüll", "2026-01-05 Altpapier", "2026-09-07 Altpapier", "2026-12-21 Restmüll"] {
            XCTAssertFalse(bez1.contains(t), t)
        }
        XCTAssertEqual(zaehlung(bez1), ["Biomüll": 52, "Restmüll": 26, "Altpapier": 26, "Gelbe Tonne": 27,
                                         "Schadstoffmobil": 12, "Grünschnitt": 4, "Weihnachtsbäume": 1])
    }

    func testBezirk2Dienstag() async throws {
        let bez2 = try await termine("mainzer_strasse_ungerade_hausnummern")
        for t in ["2026-01-06 Restmüll", "2026-03-30 Restmüll", "2026-04-08 Altpapier", "2026-05-27 Biomüll", "2026-09-10 Altpapier",
                  "2026-12-21 Restmüll", "2026-12-29 Altpapier"] {
            XCTAssertTrue(bez2.contains(t), t)
        }
        for t in ["2026-01-05 Restmüll", "2026-03-28 Restmüll", "2026-03-31 Restmüll", "2026-04-07 Altpapier", "2026-12-19 Restmüll"] {
            XCTAssertFalse(bez2.contains(t), t)
        }
        XCTAssertEqual(zaehlung(bez2)["Restmüll"], 26)
        XCTAssertEqual(zaehlung(bez2)["Altpapier"], 26)
    }

    /// Gelbe Tonne, Grünabfälle, Sondermüll und Christbäume gelten für die ganze Gemeinde; Sperrmüll (auf Abruf) fehlt.
    func testGemeinsameTermineUndStrassen() async throws {
        let gerade = try await termine("mainzer_strasse_gerade_hausnummern")
        let ungerade = try await termine("mainzer_strasse_ungerade_hausnummern")
        XCTAssertNotEqual(gerade, ungerade, "gerade Hausnummern Bezirk 1, ungerade Bezirk 2")
        let alemannenweg = try await termine("alemannenweg")
        let bebelNord = try await termine("august_bebel_strasse_bis_rheinstrasse")
        let bebelSued = try await termine("august_bebel_strasse_von_rheinstrasse_bis_ginsheimer_strasse")
        XCTAssertEqual(gerade, alemannenweg)
        XCTAssertEqual(ungerade, bebelNord)
        XCTAssertEqual(gerade, bebelSued)
        for t in ["2026-01-02 Gelbe Tonne", "2026-06-05 Gelbe Tonne", "2026-12-31 Gelbe Tonne", "2026-04-08 Schadstoffmobil",
                  "2026-10-29 Grünschnitt", "2026-01-09 Weihnachtsbäume"] {
            XCTAssertTrue(gerade.contains(t) && ungerade.contains(t), t)
        }
        XCTAssertFalse(gerade.contains("2026-01-01 Gelbe Tonne"))
        XCTAssertFalse((gerade.union(ungerade)).contains { $0.contains("Sperrmüll") })
        XCTAssertEqual(JahresdatenProvider(key: "bischofsheim").notice?.contains("Sperrmüll nicht enthalten"), true)
    }

    func testCheckPlaceBelegt() throws {
        let hits = ProviderCatalog.checkPlace("Bischofsheim")
        let gg = try XCTUnwrap(hits.first { $0.district == "Landkreis Groß-Gerau" })
        XCTAssertTrue(gg.isCovered)
        XCTAssertNil(gg.gap)
        XCTAssertEqual(gg.entries.map(\.serviceKey), ["bischofsheim"])
        // Gegenprobe: gleichnamige Orte anderer Kreise führen den Eintrag nicht
        for other in hits where other.district != "Landkreis Groß-Gerau" {
            XCTAssertFalse(other.entries.contains { $0.serviceKey == "bischofsheim" }, other.district)
        }
    }
}
