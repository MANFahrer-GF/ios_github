import XCTest
@testable import TonneCore

/// Fester Test ohne Netz: Jede Gemeinde des Verzeichnisses hat einen Eintrag, der sie belegt führt, oder steht mit Grund
/// in der ausdrücklichen Lückenliste – nie beides, nie keins. Anlass: Neuss fehlte, weil je Kreis gezählt wurde.
final class PlaceMapTests: XCTestCase {
    private var places: [String] {
        MunicipalityIndex.all.map { "\($0.district)|\($0.name)" }.filter { !CatalogRegions.unincorporated.contains($0) }
    }

    func testEveryMunicipalityIsMappedOrAnExplicitGap() {
        let all = Set(places)
        XCTAssertGreaterThan(all.count, 10_000)
        let mapped = Set(PlaceMapIndex.entryIDs.keys), gaps = Set(PlaceMapIndex.gaps.keys)
        XCTAssertEqual(all.subtracting(mapped).subtracting(gaps).sorted(), [], "Gemeinden ohne Zuordnung und ohne begründete Lücke")
        XCTAssertEqual(mapped.intersection(gaps).sorted(), [], "Gemeinden mit Zuordnung UND Lücke – Lückenliste veraltet")
        // Gegen das ganze Verzeichnis: „Helmstedt“ ist Stadt und zugleich Name eines gemeindefreien Gebiets.
        let everything = Set(MunicipalityIndex.all.map { "\($0.district)|\($0.name)" })
        XCTAssertEqual(mapped.union(gaps).subtracting(everything).sorted(), [], "Zuordnung oder Lücke für eine Gemeinde, die es nicht gibt")
        XCTAssertFalse(PlaceMapIndex.entryIDs.values.contains { $0.isEmpty }, "Zuordnung ohne Eintrag")
    }

    func testEveryMappedEntryExistsInTheCatalog() {
        let known = Set(ProviderCatalog.entries.map(\.id))
        XCTAssertEqual(Set(CatalogPlaceMap.entryIDs).subtracting(known).sorted(), [])
    }

    func testGapsCarryAKnownReason() {
        let reasons = Set(["portal_abgeschaltet", "kein_eintrag", "nicht_in_liste", "ungeprueft", "mehrdeutig"])
        XCTAssertEqual(Set(PlaceMapIndex.gaps.values.map(\.reason)).subtracting(reasons).sorted(), [])
        // Nachweislich nicht holbar ist derzeit nur der Rhein-Lahn-Kreis (Portal nach Sicherheitsvorfall abgeschaltet).
        let unavailable = PlaceMapIndex.gaps.filter(\.value.unavailable)
        XCTAssertTrue(unavailable.allSatisfy { $0.key.hasPrefix("Landkreis Rhein-Lahn-Kreis|") && $0.value.reason == "portal_abgeschaltet" })
        // Noch nicht belegte Gemeinden: Die Zahl darf nur sinken. Ziel ist 0; jede Zeile steht mit Grund in
        // tools/catalog/data/place_map/luecken.json.
        XCTAssertLessThanOrEqual(PlaceMapIndex.gaps.count - unavailable.count, 352)
    }

    func testNeussFindsItsOwnProvider() throws {
        let neuss = try XCTUnwrap(ProviderCatalog.checkPlace("Neuss").first { $0.district == "Kreis Rhein-Kreis Neuss" })
        XCTAssertEqual(neuss.entries.map(\.serviceKey), ["awl_neuss"])
        XCTAssertFalse(neuss.entries.contains { $0.title.contains("Schönmackers") })
        XCTAssertNil(neuss.gapNote)
        let found = ProviderCatalog.search("Neuss")
        XCTAssertTrue(found.contains { $0.serviceKey == "awl_neuss" })
        XCTAssertFalse(found.contains { $0.title.contains("Schönmackers") }, "Schönmackers führt Neuss nicht")
        // Gegenprobe: Kaarst im selben Kreis führt Schönmackers
        let kaarst = try XCTUnwrap(ProviderCatalog.checkPlace("Kaarst").first)
        XCTAssertTrue(kaarst.entries.contains { $0.title.contains("Schönmackers") })
    }

    func testUnavailablePortalIsToldHonestly() throws {
        let diez = try XCTUnwrap(ProviderCatalog.checkPlace("Diez").first { $0.district == "Landkreis Rhein-Lahn-Kreis" })
        XCTAssertFalse(diez.isCovered)
        XCTAssertTrue(diez.isUnavailable)
        XCTAssertNotNil(diez.gapNote)
        let district = try XCTUnwrap(ProviderCatalog.coverage.first { $0.district == "Landkreis Rhein-Lahn-Kreis" })
        XCTAssertFalse(district.isCovered)
    }
}
