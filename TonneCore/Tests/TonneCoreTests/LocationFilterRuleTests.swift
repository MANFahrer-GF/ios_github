import XCTest
@testable import TonneCore

final class LocationFilterRuleTests: XCTestCase {
    let home = UUID(), office = UUID(), deleted = UUID()

    func testFilterOnExistingLocationApplies() {
        XCTAssertEqual(LocationFilterRule.effective(office.uuidString, existing: [home, office]), office)
    }

    /// Gefilterter Standort gelöscht: Filter gilt nicht mehr (vorher: keine einzige Abholung, Menü weg).
    func testFilterOnDeletedLocationIsIgnored() {
        XCTAssertNil(LocationFilterRule.effective(deleted.uuidString, existing: [home, office]))
    }

    /// Nur noch ein Standort (Menü unsichtbar) oder alles gelöscht und neu angelegt: kein Filter.
    func testSingleOrNoLocationNeverFilters() {
        XCTAssertNil(LocationFilterRule.effective(home.uuidString, existing: [home]))
        XCTAssertNil(LocationFilterRule.effective(home.uuidString, existing: []))
        XCTAssertNil(LocationFilterRule.effective("", existing: [home, office]))
    }
}
