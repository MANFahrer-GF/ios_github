import XCTest
@testable import TonneCore

/// Bad Laasphe (Kreis Siegen-Wittgenstein): Farbkalender 2027 (tools/pdfkalender/orte/badlaasphe.py, Wunsch Roman Schössler
/// 21.11.2026). Stichproben gegen die gerenderte PDF: Bezirk A (Feudingen), gemischt (Banfe: Rest/Bio B, Papier A) und Kernstadt D.
final class BadLaaspheJahresdatenTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func termine(_ selections: [String]) async throws -> Set<String> {
        var provider = JahresdatenProvider(key: "badlaasphe")
        provider.referenceDate = Days.parse("2027-01-01", calendar: calendar)
        var chosen: [SelectionOption] = []
        for id in selections {
            let step = try await provider.nextStep(after: chosen)
            let option = try XCTUnwrap(try XCTUnwrap(step).options.first { $0.id == id }, "\(id) fehlt")
            chosen.append(option)
        }
        let done = try await provider.nextStep(after: chosen)
        XCTAssertNil(done)
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        return Set(try await provider.pickups(for: chosen, calendar: calendar).map { "\(formatter.string(from: $0.date)) \($0.name)" })
    }

    func testFeudingenBezirkA() async throws {
        let t = try await termine(["gruppe:Ortsteile", "feudingen"])
        for s in ["2027-01-05 Biomüll", "2027-01-11 Restmüll", "2027-01-25 Altpapier", "2027-01-25 Gelbe Tonne", "2027-02-06 Schadstoffsammlung",
                  "2027-02-22 Altpapier"] {
            XCTAssertTrue(t.contains(s), s)
        }
        XCTAssertFalse(t.contains("2027-01-06 Biomüll"), "Bezirk B gehört nicht zu Feudingen")
    }

    /// Banfe: Rest/Bio Bezirk B, Papier Bezirk A („Nur Papiermüll: Banfe …“), Gelbe Tonne 6.
    func testBanfeGemischt() async throws {
        let t = try await termine(["gruppe:Ortsteile", "banfe"])
        for s in ["2027-01-06 Biomüll", "2027-01-12 Restmüll", "2027-01-25 Altpapier", "2027-01-02 Gelbe Tonne", "2027-01-29 Gelbe Tonne"] {
            XCTAssertTrue(t.contains(s), s)
        }
        XCTAssertFalse(t.contains("2027-01-26 Altpapier"), "Papier Bezirk B gehört nicht zu Banfe")
        XCTAssertFalse(t.contains("2027-01-05 Biomüll"), "Bio Bezirk A gehört nicht zu Banfe")
    }

    /// Kernstadt erst als Gruppe, dann Straße: Bahnhofstraße = Bezirk D, Gelbe Tonne 7.
    func testKernstadtStrasse() async throws {
        let t = try await termine(["gruppe:Kernstadt", "kernstadt_bahnhofstrasse"])
        for s in ["2027-01-08 Restmüll", "2027-01-21 Altpapier", "2027-01-27 Gelbe Tonne", "2027-01-28 Biomüll"] {
            XCTAssertTrue(t.contains(s), s)
        }
    }

    func testCheckPlaceBelegt() throws {
        let hit = try XCTUnwrap(ProviderCatalog.checkPlace("Bad Laasphe").first { $0.district == "Kreis Siegen-Wittgenstein" })
        XCTAssertTrue(hit.isCovered)
        XCTAssertNil(hit.gap)
        XCTAssertEqual(hit.entries.map(\.serviceKey), ["badlaasphe"])
    }

    /// Nur im Teil Gelbe Tonne genannt (Prüfbefund 21.11.2026): wählbar, mit Gelber Tonne und Schadstoff, ohne Rest/Bio/Papier.
    func testNurGelbeTonne() async throws {
        let w = try await termine(["gruppe:Ortsteile", "welschengeheu"])
        XCTAssertTrue(w.contains("2027-01-22 Gelbe Tonne"))
        XCTAssertTrue(w.contains("2027-02-06 Schadstoffsammlung"))
        XCTAssertFalse(w.contains { $0.hasSuffix("Restmüll") || $0.hasSuffix("Biomüll") || $0.hasSuffix("Altpapier") })
        let g = try await termine(["gruppe:Kernstadt", "kernstadt_im_gruendchen"])
        XCTAssertEqual(g.filter { $0.hasSuffix("Gelbe Tonne") }.count, 13)
    }
}

