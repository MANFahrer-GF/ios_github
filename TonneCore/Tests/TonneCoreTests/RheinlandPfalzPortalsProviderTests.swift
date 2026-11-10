import XCTest
@testable import TonneCore

/// Live-Tests für die Portale in Rheinland-Pfalz (nur mit TONNE_LIVE=1).
extension LiveProviderTests {
    private func rp(_ key: String) -> RheinlandPfalzPortalsProvider { RheinlandPfalzPortalsProvider(service: key) }

    func testRPArtTrier() async throws { try await check(rp("art"), prefer: ["Stadt Trier", "Trier", "Universitätsring"], minCount: 3) }
    func testRPArtDorf() async throws { try await check(rp("art"), prefer: ["Kelberg", "Drees"], minCount: 3) }
    func testRPRheinLahn() async throws { try await check(rp("rheinlahn"), prefer: ["Bad Ems", "Adolf-Bach-Promenade"]) }
    func testRPKAW() async throws { try await check(rp("kaw"), prefer: ["Stadt Bingen", "Bingen-Stadt"], minCount: 5) }
    /// Zwei Gemeinden unter einer Kennung: je Verbandsgemeinde eine Zeile mit dem amtlichen Namen und nur ihren Straßen.
    func testBirkenfeldSplitsBerschweiler() {
        func row(_ g: String, _ gid: String, _ vg: String, _ s: String, _ sid: String) -> [String: String] {
            ["Gemeinde": g, "GemeindeId": gid, "Verbandsgemeinde": vg, "Strasse": s, "StrassenId": sid]
        }
        let streets = [row("Berschweiler", "129", "Baumholder", "Hauptstraße", "1"), row("Berschweiler", "129", "Baumholder", "Kanzel", "2"),
                       row("Berschweiler", "129", "Herrstein-Rhaunen", "Hauptstraße", "3"), row("Abentheuer", "5", "Birkenfeld", "Dorfstraße", "4")]
        let places = RheinlandPfalzPortalsProvider.birkenfeldPlaces(streets)
        XCTAssertEqual(places.map(\.title), ["Abentheuer", "Berschweiler bei Baumholder", "Berschweiler bei Kirn"])
        XCTAssertEqual(places.map(\.id), ["5", "129|Baumholder", "129|Herrstein-Rhaunen"])
        XCTAssertEqual(RheinlandPfalzPortalsProvider.birkenfeldStreets(streets, place: "129|Herrstein-Rhaunen").map(\.id), ["3"])
        XCTAssertEqual(RheinlandPfalzPortalsProvider.birkenfeldStreets(streets, place: "129|Baumholder").map(\.id), ["1", "2"])
        XCTAssertEqual(RheinlandPfalzPortalsProvider.birkenfeldStreets(streets, place: "129").count, 3, "früher gespeicherte Kennung")
        XCTAssertEqual(RheinlandPfalzPortalsProvider.birkenfeldStreets(streets, place: "5").map(\.title), ["Dorfstraße"])
    }

    func testRPBirkenfeld() async throws { try await check(rp("birkenfeld"), prefer: ["Reichenbach", "Auf dem Schoß"], minCount: 3) }
    func testRPKusel() async throws { try await check(rp("kusel"), prefer: ["Adenbach"], minCount: 5) }
    func testRPKreuznach() async throws { try await check(rp("kreuznach"), prefer: ["Bad Kreuznach", "Adalbert-Stifter-Straße", "3"]) }
    func testRPKreuznachDorf() async throws { try await check(rp("kreuznach"), prefer: ["Hargesheim"]) }
    func testRPGermersheim() async throws { try await check(rp("germersheim"), prefer: ["Bellheim", "Albert-Schweitzer-Str."]) }
    func testRPSpeyer() async throws { try await check(rp("speyer"), prefer: ["Adenauerpark"]) }
    func testRPWorms() async throws { try await check(rp("worms"), prefer: ["Adam-Riese-Straße"]) }
    func testRPKoblenz() async throws { try await check(rp("koblenz"), prefer: ["Wallersheim"], minCount: 3) }
}

/// Offline: Bezeichnungen der Adressen.
final class RheinlandPfalzPortalsLabelTests: XCTestCase {
    func testLabels() {
        let art = RheinlandPfalzPortalsProvider(service: "art")
        XCTAssertEqual(art.label(for: [SelectionOption(id: "Stadt Trier", title: "Stadt Trier"), SelectionOption(id: "Trier", title: "Trier"),
                                      SelectionOption(id: "k", title: "Universitätsring")]), "Trier, Universitätsring")
        let kh = RheinlandPfalzPortalsProvider(service: "kreuznach")
        XCTAssertEqual(kh.label(for: [SelectionOption(id: "c:1", title: "Bad Kreuznach"), SelectionOption(id: "s:2", title: "Ringstraße"),
                                     SelectionOption(id: "h:3", title: "5")]), "Bad Kreuznach, Ringstraße 5")
        XCTAssertEqual(RheinlandPfalzPortalsProvider(service: "worms").label(for: [SelectionOption(id: "x", title: "Adam-Riese-Straße")]),
                       "Worms, Adam-Riese-Straße")
    }
}
