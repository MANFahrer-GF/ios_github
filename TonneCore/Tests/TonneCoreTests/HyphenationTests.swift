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
}
