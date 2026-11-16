import XCTest
@testable import TonneCore

final class HyphenationTests: XCTestCase {
    private let shy = "\u{00AD}"

    func testLongGermanWordGetsSoftHyphensAtSyllables() {
        let out = Hyphenation.soft("TÜV / Hauptuntersuchung", english: false)
        // Ohne die Striche ist der Text unverändert – nichts anderes wird angefasst.
        XCTAssertEqual(out.replacingOccurrences(of: shy, with: ""), "TÜV / Hauptuntersuchung")
        XCTAssertTrue(out.contains(shy), out)
        // Nie die falsche Stelle, an der SwiftUI ohne Trennung bricht.
        XCTAssertFalse(out.contains("untersuc\(shy)hung"), out)
        // Die Wortfuge „Haupt|untersuchung“ ist eine Trennstelle.
        XCTAssertTrue(out.contains("Haupt\(shy)"), out)
    }

    func testShortWordsAndEdgesStayUntouched() {
        XCTAssertEqual(Hyphenation.soft("Gelber Sack", english: false), "Gelber Sack")
        XCTAssertEqual(Hyphenation.soft("", english: false), "")
        let out = Hyphenation.soft("Geburtstagsfeier", english: false)
        XCTAssertFalse(out.hasPrefix("G\(shy)") || out.hasSuffix("\(shy)r"), out)
    }

    /// Sichtprüfung 16.11.: „Gabriele Grundhö-“ / „fer-Kantorowicz“ bei normaler Schrift. Teile eines Bindestrich-Worts
    /// bleiben ganz, die Zeile bricht am Bindestrich; ein langes Wort daneben wird weiter getrennt.
    func testHyphenatedCompoundKeepsItsParts() {
        XCTAssertTrue(Hyphenation.soft("Gabriele Grundhöfer-Kantorowicz", english: false).hasSuffix(" Grundhöfer-Kantorowicz"))
        let mixed = Hyphenation.soft("Grundhöfer-Kantorowicz Geburtstagsfeier", english: false)
        XCTAssertTrue(mixed.hasPrefix("Grundhöfer-Kantorowicz "), mixed)
        XCTAssertTrue(mixed.contains(shy), "freistehendes langes Wort wird getrennt: \(mixed)")
        // Prüfbefund: lange Teile behalten ihre Trennstellen, sonst bricht SwiftUI wieder „Hauptuntersuc|hung“
        for text in ["TÜV-Hauptuntersuchung", "Elektro-Kleingerätesammlung"] {
            XCTAssertTrue(Hyphenation.soft(text, english: false).contains(shy), text)
        }
    }
}
