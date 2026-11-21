import XCTest
@testable import TonneCore

/// Beschlüsse der Gemeinde-Prüfung vom 16.11.2026, die bis 21.11. nicht in CatalogRegions.swift angekommen waren (die Datei war
/// nicht neu erzeugt worden). Zusätzlich prüft tools/check_generated.sh in der CI, dass alle erzeugten Dateien aktuell sind.
final class CatalogRegionsBeschluesseTests: XCTestCase {
    private func districts(_ id: String) -> [String] { CatalogRegions.entryDistricts[id] ?? [] }

    /// ALBA lieferte an allen 15 Gemeinden im Kreis Tübingen keine Termine (der Kreis läuft über AWIDO).
    func testAlbaOhneTuebingen() {
        let alba = districts("abfallPlusApp:de.albagroup.app:ALBA (Berlin, Braunschweig, Havelland …)")
        XCTAssertFalse(alba.isEmpty)
        XCTAssertFalse(alba.contains { $0.contains("Tübingen") }, "ALBA darf Tübingen nicht mehr führen")
        XCTAssertTrue(alba.contains("Kreisfreie Stadt Berlin"))
    }

    /// Aschaffenburg über die Stadtwerke (nur die Stadt – der Landkreis hat seinen eigenen Eintrag), Bühl über den digitalen
    /// Kalender der Stadt.
    func testAschaffenburgUndBuehlZugeordnet() {
        XCTAssertEqual(districts("awido:stwab:Stadtwerke Aschaffenburg"), ["Kreisfreie Stadt Aschaffenburg"])
        XCTAssertEqual(districts("awido:lra-ab:Landkreis Aschaffenburg"), ["Landkreis Aschaffenburg"])
        // Bühl bedient nur die eigene Stadt: steht darum unter localEntries („Landkreis|Gemeinde“), nicht unter entryDistricts.
        XCTAssertEqual(CatalogRegions.localEntries["portalsNRW:buehl:Stadt Bühl – Digitaler Abfallkalender"], ["Landkreis Rastatt|Bühl"])
    }
}
