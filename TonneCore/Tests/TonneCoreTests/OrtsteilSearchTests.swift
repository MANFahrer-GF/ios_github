import XCTest
@testable import TonneCore

/// Suche nach Ortsteilen: „Gemeinde-Ortsteil“, „Ortsteil“ allein und „Gemeinde Ortsteil“ führen zur Gemeinde
/// und damit zu dem Eintrag, der sie führt (Meldung Riedstadt-Erfelden, 14.11.2026).
final class OrtsteilSearchTests: XCTestCase {
    private func gemeinden(_ query: String) -> [String] {
        ProviderCatalog.municipalities(matching: query).map { "\($0.district)|\($0.name)" }
    }

    func testErfeldenFindsKreisGrossGerau() {
        for query in ["Riedstadt-Erfelden", "Erfelden", "Riedstadt Erfelden", "riedstadt - erfelden", "Erfelden (Riedstadt)"] {
            XCTAssertEqual(gemeinden(query), ["Landkreis Groß-Gerau|Riedstadt"], query)
            XCTAssertTrue(ProviderCatalog.search(query).contains { $0.serviceKey == "grossgeraulandkreis-abfallkalender" }, query)
        }
        XCTAssertEqual(ProviderCatalog.municipalityHint(for: "Erfelden"), "Erfelden gehört zu Riedstadt (Landkreis Groß-Gerau).")
    }

    /// Von Hand belegte Ortsteile aus anderen Ländern (nicht aus der erzeugten Tabelle abgeleitet).
    func testOrtsteileInOtherStates() {
        let cases: [(String, String)] = [
            ("Sylt-Westerland", "Sylt"), ("Westerland", "Sylt"),
            ("Bonn-Beuel", "Bonn"), ("Beuel", "Bonn"),
            ("Stuttgart Vaihingen", "Stuttgart"),
            ("Wolfsburg-Fallersleben", "Wolfsburg"), ("Fallersleben", "Wolfsburg"),
            ("Ginsheim-Gustavsburg", "Ginsheim-Gustavsburg"), ("Gustavsburg", "Ginsheim-Gustavsburg"),
            ("Klein-Rohrheim", "Gernsheim"), ("Gernsheim am Rhein", "Gernsheim"), ("Gernsheim-Allmendfeld", "Gernsheim"),
        ]
        for (query, gemeinde) in cases {
            let names = ProviderCatalog.municipalities(matching: query).map(\.name)
            XCTAssertTrue(names.contains(gemeinde), "\(query) → \(names)")
            XCTAssertFalse(ProviderCatalog.search(query).isEmpty, query)
        }
        // Gernsheim: Das Portal schreibt „Gernsheim am Rhein“ (live 14.11.), beide Schreibweisen führen zum Kreis-Eintrag.
        for query in ["Gernsheim", "Gernsheim am Rhein", "Allmendfeld"] {
            XCTAssertTrue(ProviderCatalog.search(query).contains { $0.serviceKey == "grossgeraulandkreis-abfallkalender" }, query)
        }
        // Gleichnamige Ortsteile in mehreren Gemeinden: alle, mit Gemeinde davor eindeutig.
        XCTAssertTrue(gemeinden("Gohlis").contains("Kreisfreie Stadt Leipzig|Leipzig"))
        XCTAssertGreaterThan(gemeinden("Gohlis").count, 1)
        XCTAssertEqual(ProviderCatalog.municipalities(matching: "Leipzig-Gohlis").map(\.name), ["Leipzig"])
    }

    /// Gegenproben: Gemeinden behalten Vorrang, echte Bindestrich-Gemeinden werden nicht zerlegt.
    func testMunicipalitiesKeepPriority() {
        XCTAssertEqual(gemeinden("Bodman-Ludwigshafen"), ["Landkreis Konstanz|Bodman-Ludwigshafen"])
        XCTAssertEqual(gemeinden("Mühlhausen-Ehingen"), ["Landkreis Konstanz|Mühlhausen-Ehingen"])
        XCTAssertEqual(ProviderCatalog.municipalities(matching: "Garmisch-Partenkirchen").map(\.name), ["Garmisch-Partenkirchen"])
        XCTAssertEqual(gemeinden("Bischofsheim").filter { $0.hasPrefix("Landkreis Groß-Gerau") }, ["Landkreis Groß-Gerau|Bischofsheim"])
        XCTAssertTrue(ProviderCatalog.municipalities(matching: "Bergen").allSatisfy { $0.name.hasPrefix("Bergen") })
        XCTAssertTrue(ProviderCatalog.municipalities(matching: "Xyzzyhausen").isEmpty)
        XCTAssertTrue(ProviderCatalog.municipalities(matching: "Riedstadt-Xyzzy").map(\.name) == ["Riedstadt"])
    }

    /// Jeder Ortsteil der Tabelle führt allein und als „Gemeinde-Ortsteil“ zu seiner Gemeinde.
    func testEveryOrtsteilResolves() {
        let all = LocalityIndex.all
        XCTAssertGreaterThan(all.count, 40_000)
        let gemeinden = Set(MunicipalityIndex.all.map { "\($0.district)|\($0.name)" })
        var failures: [String] = []
        for item in all {
            let pair = "\(item.district)|\(item.municipality)"
            if !gemeinden.contains(pair) { failures.append("unbekannte Gemeinde \(pair)"); continue }
            let alone = ProviderCatalog.municipalities(matching: item.name).map { "\($0.district)|\($0.name)" }
            // Allgemeine Namen in mehr als 8 Gemeinden liefern allein bewusst nichts (SuchPruefpunkteTests).
            let places = Set((LocalityIndex.byName[ProviderCatalog.fold(item.name)] ?? []).map { "\($0.district)|\($0.municipality)" })
            // Heißt der Ortsteil wie ein Kreis („Lippe“, „Friesland“), meint die Eingabe allein den Kreis.
            let isDistrict = DistrictIndex.cores[ProviderCatalog.fold(item.name)] != nil
            if !alone.contains(pair) && places.count <= LocalityIndex.maxMunicipalities && !isDistrict {
                failures.append("\(item.name) → \(alone)")
            }
            let query = "\(item.municipality)-\(item.name)"
            let joined = ProviderCatalog.municipalities(matching: query).map { "\($0.district)|\($0.name)" }
            // Ein ganzer Ortsteilname geht vor dem Zerlegen (GeoNames führt „Rothenburg ob der Tauber-Wildbad“ bei Burgbernheim).
            if !joined.contains(pair) && LocalityIndex.byName[ProviderCatalog.fold(query)] == nil { failures.append("\(item.municipality)-\(item.name) → \(joined)") }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) Fehler, z. B. \(failures.prefix(5))")
    }
}
