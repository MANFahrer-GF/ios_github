import XCTest
@testable import TonneCore

/// Landkreis Rostock: Mit „Saison“ bei der schwarzen Tonne liefert das Portal auch Gelbe und Blaue Tonne nur in der Saison
/// (ical.php, Küsserow-Hof 2026: Schwarz bis 28.10., Gelb bis 19.10., Blau bis 05.10., Grün weiter bis 31.12.; `gsaison` kürzt nur
/// die grüne Tonne). Die Auswahl sagt das jetzt dazu.
final class LROSeasonTests: XCTestCase {
    func testBlackSeasonOptionsSayYellowAndBlueFollow() async throws {
        L10n.forcedLanguage = "de"
        defer { L10n.forcedLanguage = nil }
        let lro = MecklenburgPortalsProvider(service: "lro")
        let place = SelectionOption(id: "C_C_Kz_Fz", title: "Küsserow-Hof")
        let blackStep = try await lro.nextStep(after: [place])
        let black = try XCTUnwrap(blackStep)
        XCTAssertEqual(black.options.map(\.title), ["Alle 2 Wochen", "Alle 4 Wochen", "Alle 2 Wochen, nur Saison", "Alle 4 Wochen, nur Saison", "Keine Tonne"])
        let notes = black.options.map(\.subtitle)
        XCTAssertNil(notes[0]); XCTAssertNil(notes[1]); XCTAssertNil(notes[4])
        XCTAssertEqual(notes[2], "Dann auch Gelbe und Blaue Tonne nur in der Saison (April bis Oktober)")
        XCTAssertEqual(notes[3], notes[2])
        // Die IDs bleiben, gespeicherte Auswahlen gelten weiter.
        XCTAssertEqual(black.options.map(\.id), ["rhythm:2w", "rhythm:4w", "rhythm:2w|s", "rhythm:4w|s", "rhythm:none"])

        let greenStep = try await lro.nextStep(after: [place, black.options[0]])
        let green = try XCTUnwrap(greenStep)
        XCTAssertTrue(green.options.allSatisfy { $0.subtitle == nil }, "Bio-Saison betrifft nur die grüne Tonne")
    }
}
