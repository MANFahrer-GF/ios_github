import XCTest
@testable import TonneCore

/// Prüfpunkte zur Ortsteil-Suche und Müllmann-Anzeige (Advisor, 14.11.2026).
final class SuchPruefpunkteTests: XCTestCase {
    private func entry(_ serviceKey: String) throws -> CatalogEntry {
        try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == serviceKey })
    }

    /// Die Müllmann-App hieß „Müllmann-App (Landkreis Konstanz, Karlsruhe)“ und traf „Landkreis Konstanz“ über den Titel.
    /// Seit sie nur noch „Müllmann-App“ heißt, findet der Kreisname sie über die belegte Zuordnung.
    func testKreisnameFindetMuellmann() throws {
        let muellmann = try entry("muellmann")
        for query in ["Landkreis Konstanz", "Kreis Konstanz", "landkreis konstanz"] {
            XCTAssertTrue(ProviderCatalog.search(query).contains(muellmann), query)
        }
        XCTAssertEqual(ProviderCatalog.districts(matching: ProviderCatalog.fold("Kreis Konstanz")), ["Landkreis Konstanz"])
        // Ein bloßer Ortsname ist kein Kreisname
        XCTAssertTrue(ProviderCatalog.districts(matching: "konstanz").isEmpty)
        // Stadtkreis über seinen Kreisnamen
        XCTAssertTrue(ProviderCatalog.search("Stadtkreis Karlsruhe").contains(muellmann))
    }

    /// „Führt X nicht“ nur, wenn der Eintrag die Gemeinde nicht selbst unter seinen Orten im selben Kreis nennt
    /// (Messung 14.11.: 2 Widersprüche bei 9.794 Gemeinden – TBR-App „Reutlingen“, EVS „Saarbrücken“).
    func testKeinNichtGegenEigeneOrtsangabe() throws {
        XCTAssertNil(ProviderCatalog.placeNote(for: try entry("de.abfallplus.tbrapp"), query: "Reutlingen"))
        XCTAssertNil(ProviderCatalog.placeNote(for: try entry("Evs"), query: "Saarbrücken"))
        // Der Kreis-Eintrag nennt die Stadt nur im Titel – dort bleibt die Aussage (Thomas' Fall Karlsruhe).
        XCTAssertEqual(ProviderCatalog.placeNote(for: try entry("de.k4systems.abfallappka"), query: "Karlsruhe"), "Führt Karlsruhe nicht")
        // Namensvetter in einem anderen Kreis: der Ludwigslust-Parchimer Ortsteil „Heide“ ist nicht Heide in Dithmarschen
        XCTAssertEqual(ProviderCatalog.placeNote(for: try entry("lwl"), query: "Heide"), "Führt Heide nicht")
    }

    /// Allgemeine Ortsteilnamen („Thal“ in 36 Gemeinden, „Altstadt“ in 30) liefern allein keine Gemeinden.
    func testAllgemeinerOrtsteilnameLiefertKeineBeliebigenGemeinden() {
        for name in ["Thal", "Altstadt", "Bergham"] {
            XCTAssertTrue(ProviderCatalog.municipalities(matching: name).isEmpty, name)
            XCTAssertEqual(ProviderCatalog.municipalityHint(for: name)?.contains("bitte mit Gemeinde suchen"), true, name)
        }
        // Kein Ortsteilname liefert mehr als die Grenze
        for (name, _) in LocalityIndex.byName {
            XCTAssertLessThanOrEqual(ProviderCatalog.municipalities(matching: name).count, max(LocalityIndex.maxMunicipalities,
                ProviderCatalog.municipalityHits(name).count), name)
        }
        // Mit Gemeinde davor eindeutig
        XCTAssertEqual(ProviderCatalog.municipalities(matching: "Leipzig Gohlis").map(\.name), ["Leipzig"])
    }

    /// Die Gemeindesuche über die sortierte Liste liefert für jeden Gemeindenamen und jeden Wortanfang dasselbe wie die
    /// frühere lineare Suche über alle Gemeinden.
    func testSortierteGemeindesucheGleichLinear() {
        let all = MunicipalityIndex.all
        func linear(_ needle: String) -> [String] {
            let candidates = all.filter { $0.folded.hasPrefix(needle) }
            let exact = candidates.filter { $0.folded == needle }
            let hits = exact.isEmpty ? candidates.filter { !$0.folded[$0.folded.index($0.folded.startIndex, offsetBy: needle.count)].isLetter } : exact
            return (exact.isEmpty ? Array(hits.prefix(8)) : hits).map { "\($0.district)|\($0.name)" }
        }
        var needles = Set<String>()
        for item in all {
            needles.insert(item.folded)
            for index in item.folded.indices where !item.folded[index].isLetter {
                let start = String(item.folded[..<index])
                if start.count >= 3 { needles.insert(start) }
            }
        }
        var mismatches: [String] = []
        for needle in needles.sorted() {
            let sorted = ProviderCatalog.municipalityHits(needle).map { "\($0.district)|\($0.name)" }
            if sorted != linear(needle) { mismatches.append(needle) }
        }
        XCTAssertGreaterThan(needles.count, 10_000)
        XCTAssertEqual(mismatches, [], "\(mismatches.prefix(20))")
    }

    /// Vorauswahl nur im Gemeinde-Schritt: Ein Straßen- oder Bezirksschritt mit gleichnamigem Eintrag wird nicht übersprungen.
    func testVorauswahlNurImOrtSchritt() {
        let options = [SelectionOption(id: "1", title: "Karlsruhe"), SelectionOption(id: "2", title: "Konstanz")]
        XCTAssertEqual(SelectionStep(title: SelectionStep.cityTitle, options: options).preselection(for: "Karlsruhe")?.id, "1")
        XCTAssertEqual(SelectionStep(title: L10n.t("Gemeinde", "Municipality"), options: options).preselection(for: "karlsruhe")?.id, "1")
        XCTAssertNil(SelectionStep(title: SelectionStep.streetTitle, options: options).preselection(for: "Karlsruhe"))
        XCTAssertNil(SelectionStep(title: L10n.t("Abfuhrbezirk", "Collection district"), options: options).preselection(for: "Karlsruhe"))
        XCTAssertNil(SelectionStep(title: SelectionStep.cityTitle, options: options).preselection(for: "Singen (Hohentwiel)"))
    }
}
