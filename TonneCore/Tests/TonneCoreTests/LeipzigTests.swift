import XCTest
@testable import TonneCore

/// Stadtreinigung Leipzig nach dem Umbau der Straßensuche (November 2026).
final class LeipzigTests: XCTestCase {
    // Echte Antwort von rest/odata/Streets?search=Bahnhofsallee (10.11.2026), gekürzt; zweite Straße zum Test ergänzt.
    static let streets = #"""
    {"results":[{"name":"Bahnhofsallee","postalcode":"04288","district":"Liebertwolkwitz","numbers":[
      {"number":"11","position_nos":["70045","70848"]},{"number":"1","position_nos":["69189"]},
      {"number":"13","position_nos":["57291","69198","70901"]},{"number":"4","position_nos":["69191"]}]},
     {"name":"Bahnhofsallee","postalcode":"04205","district":"Miltitz","numbers":[{"number":"2 A","position_nos":["1"]}]},
     {"name":"Bahnhofstraße","postalcode":"04158","district":"Wiederitzsch","numbers":[]}],
     "total":{"count":3,"errors":[],"offline":false,"maintenanceProtocol":false}}
    """#

    private func decoded() throws -> [LeipzigProvider.Streets.Street] {
        try JSONDecoder().decode(LeipzigProvider.Streets.self, from: Data(Self.streets.utf8)).results
    }

    func testStreetsOfNewFormat() throws {
        let options = LeipzigProvider.streetOptions(try decoded())
        XCTAssertEqual(options.map(\.title), ["Bahnhofsallee", "Bahnhofsallee", "Bahnhofstraße"])
        // Nur gleichnamige Straßen bekommen Postleitzahl und Ortsteil dazu
        XCTAssertEqual(options.map(\.subtitle), ["04205 Miltitz", "04288 Liebertwolkwitz", nil])
        // Jede Zeile hat eine eigene Kennung; eine eindeutige Straße behält die bisherige Form
        XCTAssertEqual(options.map(\.id), ["street:Bahnhofsallee|04205 Miltitz", "street:Bahnhofsallee|04288 Liebertwolkwitz", "street:Bahnhofstraße"])
        XCTAssertEqual(LeipzigProvider.streetParts(options[0].id).name, "Bahnhofsallee")
        XCTAssertEqual(LeipzigProvider.streetParts("street:Bahnhofstraße").name, "Bahnhofstraße")
    }

    func testHouseNumbersCarryEveryPosition() throws {
        let street = SelectionOption(id: "street:Bahnhofsallee|04288 Liebertwolkwitz", title: "Bahnhofsallee")
        let options = try XCTUnwrap(LeipzigProvider.houseOptions(try decoded(), for: street))
        XCTAssertEqual(options.map(\.title), ["1", "4", "11", "13"])
        XCTAssertEqual(options.map(\.id), ["house:69189:1", "house:69191:4", "house:70045,70848:11", "house:57291,69198,70901:13"])
        // Der Kalender-Abruf zerlegt die Kennung an „:“ in genau drei Teile
        XCTAssertTrue(options.allSatisfy { $0.id.split(separator: ":").count == 3 })
    }

    func testHouseNumbersOfTheChosenDistrict() throws {
        let miltitz = SelectionOption(id: "street:Bahnhofsallee|04205 Miltitz", title: "Bahnhofsallee")
        XCTAssertEqual(LeipzigProvider.houseOptions(try decoded(), for: miltitz)?.map(\.id), ["house:1:2 A"])
        // Ohne Ortsteil (eindeutige Straße): die Straße dieses Namens
        let plain = SelectionOption(id: "street:Bahnhofstraße", title: "Bahnhofstraße")
        XCTAssertEqual(LeipzigProvider.houseOptions(try decoded(), for: plain)?.count, 0)
        XCTAssertNil(LeipzigProvider.houseOptions(try decoded(), for: SelectionOption(id: "street:Gibtsnicht", title: "Gibtsnicht")))
    }

    /// Der Titel trägt „(Abholzeit)“. Ob eine gespeicherte Müllart den Titel mit oder ohne Zusatz kennt:
    /// Sie führt die Termine weiter, es entsteht keine zweite.
    func testPickupTimeSuffixIsNoWasteType() {
        XCTAssertEqual(LeipzigProvider.cleanName("Biotonne (Abholzeit)"), "Biotonne")
        XCTAssertEqual(LeipzigProvider.cleanName("Restabfalltonne, "), "Restabfalltonne")
        XCTAssertEqual(LeipzigProvider.cleanName("Biotonne (Abholzeit), "), "Biotonne")
        XCTAssertEqual(LeipzigProvider.cleanName("Biotonne, (Abholzeit)"), "Biotonne")
        let titles = ["Biotonne", "Gelbe Tonne"]
        XCTAssertEqual(WasteTitleMatching.assign(titles, to: [.init(sourceKey: "Gelbe Tonne (Abholzeit)", name: "Gelb"), .init(sourceKey: "Biotonne", name: "Bio")]),
                       ["Biotonne": 1, "Gelbe Tonne": 0])
        XCTAssertTrue(ICSURLProvider.formerTitle("Gelbe Tonne (Abholzeit)", matches: "Gelbe Tonne"))
    }
}
