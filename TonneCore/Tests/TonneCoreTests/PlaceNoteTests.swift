import XCTest
@testable import TonneCore

/// Trefferliste nennt den gesuchten Ort zuerst (Thomas 14.11.2026: „Karlsruhe > Konstanz“ bei der Müllmann-App –
/// wer Karlsruhe suchte, sah nur „Aach, Allensbach, Bodman-Ludwigshafen …“).
final class PlaceNoteTests: XCTestCase {
    private func entry(_ serviceKey: String) throws -> CatalogEntry {
        try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == serviceKey })
    }

    func testMuellmannNamesKarlsruheFirst() throws {
        let muellmann = try entry("muellmann")
        XCTAssertEqual(ProviderCatalog.placeNote(for: muellmann, query: "Karlsruhe"), "Führt Karlsruhe · auch 14 Orte im Landkreis Konstanz")
        XCTAssertEqual(ProviderCatalog.servedPlace(for: muellmann, query: "Karlsruhe"), "Karlsruhe")
        // Andere Richtung: Konstanz, die übrigen Orte liegen in zwei Kreisen
        XCTAssertEqual(ProviderCatalog.placeNote(for: muellmann, query: "Konstanz"), "Führt Konstanz · auch 14 weitere Orte")
        XCTAssertEqual(ProviderCatalog.servedPlace(for: muellmann, query: "Singen"), "Singen (Hohentwiel)")
    }

    func testCountyEntryDoesNotClaimCity() throws {
        // Die Stadt Karlsruhe führt laut belegter Zuordnung nur die Müllmann-App, nicht die AbfallPlus-App des Landkreises.
        let kreis = try entry("de.k4systems.abfallappka")
        XCTAssertEqual(ProviderCatalog.placeNote(for: kreis, query: "Karlsruhe"), "Führt Karlsruhe nicht")
        XCTAssertNil(ProviderCatalog.servedPlace(for: kreis, query: "Karlsruhe"))
    }

    func testNoNoteWithoutPlace() throws {
        let muellmann = try entry("muellmann")
        XCTAssertNil(ProviderCatalog.placeNote(for: muellmann, query: "Müllmann"))
        XCTAssertNil(ProviderCatalog.placeNote(for: muellmann, query: "Xyzzyhausen"))
        XCTAssertNil(ProviderCatalog.servedPlace(for: muellmann, query: "Müllmann"))
    }
}
