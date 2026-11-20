import XCTest
@testable import TonneCore

/// Gemeinde-Prüfung Punkt 6 (16.11.2026): Ostprignitz-Ruppin und Potsdam-Mittelmark führen im Ort-Schritt Ortsteile statt
/// Gemeinden. Die Suche „Damelack“ fand die Gemeinde Breddin, der Assistent zeigte dann aber die ganze Liste mit 49 Orten.
final class OrtsteilVorauswahlTests: XCTestCase {
    // Erwartet deutsche Texte – unabhängig von der Sprache des Rechners (CI läuft englisch) und von anderen Testklassen
    override func setUp() { L10n.forcedLanguage = "de" }
    override func tearDown() { L10n.forcedLanguage = nil }

    // Berechnet, nicht beim Anlegen der Testinstanz: der Schritttitel hängt von der Sprache ab (setUp)
    private var step: SelectionStep { SelectionStep(title: SelectionStep.cityTitle, options: ["Dorf Zechlin", "Damelack", "Kränzlin", "Ostprignitz-Ruppin"]
        .map { SelectionOption(id: $0, title: $0) }) }

    func testSearchedLocalityOfThePlaceIsPreselected() {
        XCTAssertEqual(step.preselection(for: "Breddin", query: "Damelack")?.title, "Damelack")
        XCTAssertEqual(step.preselection(for: "Breddin", query: " damelack ")?.title, "Damelack")
        XCTAssertEqual(step.preselection(for: "Märkisch Linden", query: "Kränzlin")?.title, "Kränzlin")
    }

    func testOtherEntriesStayAList() {
        // Gemeinde selbst gesucht: kein Ortsteil, keine Vorauswahl
        XCTAssertNil(step.preselection(for: "Breddin", query: "Breddin"))
        // Eintrag gleichen Namens, der kein Ortsteil der gesuchten Gemeinde ist
        XCTAssertNil(step.preselection(for: "Breddin", query: "Kränzlin"))
        // Außerhalb des Ort-Schritts nie
        let street = SelectionStep(title: SelectionStep.streetTitle, options: step.options)
        XCTAssertNil(street.preselection(for: "Breddin", query: "Damelack"))
    }

    /// Gemos „Gemeinde / Ortsteil“ (Prüfbefund 1, 16.11.2026): Gemeinde und Ortsteil stehen in derselben Liste. Die Suche
    /// „Kummer“ fand die Gemeinde Ludwigslust und wählte „Ludwigslust“, obwohl „Kummer“ eigene Option ist.
    func testOwnOptionOfTheSearchedLocalityBeatsTheMunicipality() {
        let gemos = SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: ["Ludwigslust", "Kummer", "Alt Krenzlin", "Klein Krams + Ausbau"]
            .map { SelectionOption(id: $0, title: $0) })
        XCTAssertEqual(gemos.preselection(for: "Ludwigslust", query: "Kummer")?.title, "Kummer")
        XCTAssertEqual(gemos.preselection(for: "Ludwigslust", query: "Ludwigslust Kummer")?.title, "Kummer")
        XCTAssertEqual(gemos.preselection(for: "Ludwigslust", query: "Kummer (Ludwigslust)")?.title, "Kummer")
        // „Klein Krams + Ausbau“ ist nicht genau der gesuchte Ortsteil: Liste statt Gemeinde
        XCTAssertNil(gemos.preselection(for: "Alt Krenzlin", query: "Klein Krams"))
        // Die Gemeinde selbst gesucht: weiter die Gemeinde
        XCTAssertEqual(gemos.preselection(for: "Ludwigslust", query: "Ludwigslust")?.title, "Ludwigslust")
    }

    /// Prüfbefund 2: „Zahrensdorf“ gehört zu Neu Gülze, „Zahrensdorf (Kloster Tempzin)“ zu Kloster Tempzin.
    func testLocalityWithTheMunicipalityInBracketsIsChosen() {
        let gemos = SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: ["Kloster Tempzin", "Zahrensdorf", "Zahrensdorf (Kloster Tempzin)"]
            .map { SelectionOption(id: $0, title: $0) })
        XCTAssertEqual(gemos.preselection(for: "Kloster Tempzin", query: "Zahrensdorf")?.title, "Zahrensdorf (Kloster Tempzin)")
        // Kein passender Zusatz unter mehreren gleichnamigen: Liste
        let twins = SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: ["Kloster Tempzin", "Zahrensdorf", "Zahrensdorf (Neu Gülze)"]
            .map { SelectionOption(id: $0, title: $0) })
        XCTAssertNil(twins.preselection(for: "Kloster Tempzin", query: "Zahrensdorf"))
    }

    /// Nachprüfung N1 (16.11.2026): Ortsteil mit eigener Option, aber anders geschrieben – Bindestrich statt Leerzeichen
    /// oder umgekehrt. Bisher fiel die Suche still auf die Gemeinde zurück.
    func testOtherSpellingOfTheLocalityNeverChoosesTheMunicipality() {
        func gemos(_ titles: [String]) -> SelectionStep {
            SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: titles.map { SelectionOption(id: $0, title: $0) })
        }
        XCTAssertEqual(gemos(["Dabel", "Dabel-Woland"]).preselection(for: "Dabel", query: "Dabel Woland")?.title, "Dabel-Woland")
        XCTAssertEqual(gemos(["Hagenow (einschließlich Hagenow Land)", "Hagenow Heide"]).preselection(for: "Hagenow", query: "Hagenow-Heide")?.title, "Hagenow Heide")
        XCTAssertEqual(gemos(["Grabow", "Grabow Ziegelscheune"]).preselection(for: "Grabow", query: "Grabow-Ziegelscheune")?.title, "Grabow Ziegelscheune")
        XCTAssertEqual(gemos(["Beelitz (Stadt)", "Beelitz-Heilstätten"]).preselection(for: "Beelitz", query: "Beelitz Heilstätten")?.title, "Beelitz-Heilstätten")
        // Sicherung: Die Suche nennt einen Ortsteil, den eine andere Option trägt, aber nicht eindeutig – Liste statt Gemeinde
        XCTAssertNil(gemos(["Grabow", "Grabow Ziegelscheune", "Grabow Ziegelscheune Ausbau"]).preselection(for: "Grabow", query: "Grabow Ziegel"))
        XCTAssertNil(gemos(["Grabow", "Grabow/Ziegelscheune"]).preselection(for: "Grabow", query: "Ziegelscheune Grabow"))
        // Gegenproben: Ortsteil ohne eigene Option oder bloßer Gemeindename wählen weiter die Gemeinde
        XCTAssertEqual(gemos(["Dabel", "Dabel-Woland"]).preselection(for: "Dabel", query: "Dabel")?.title, "Dabel")
        XCTAssertEqual(gemos(["Hagenow (einschließlich Hagenow Land)", "Hagenow Heide"]).preselection(for: "Hagenow", query: "Hagenow Land")?.title, "Hagenow (einschließlich Hagenow Land)")
        XCTAssertEqual(gemos(["Stuttgart", "Esslingen"]).preselection(for: "Stuttgart", query: "Stuttgart Vaihingen")?.title, "Stuttgart")
    }

    /// Echte Kette über die ganze LWL-Liste: Wer einen Ortsteil sucht, der eigene Option ist, bekommt nie die Gemeinde.
    func testNoLwlLocalityIsAnsweredWithItsMunicipality() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../tools/catalog/data/gemos/lwl_places.txt")
        let titles = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lwl = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == "lwl" })
        let step = SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: titles.map { SelectionOption(id: $0, title: $0) })
        var checked = 0, variants = 0
        for title in titles {
            // Auch in anderer Schreibweise gesucht (Nachprüfung N1): „Dabel Woland“ für „Dabel-Woland“, „Hagenow-Heide“ für „Hagenow Heide“
            var queries = [title, title.replacingOccurrences(of: "-", with: " ")]
            if !title.contains(where: { "(+/".contains($0) }) { queries.append(title.replacingOccurrences(of: " ", with: "-")) }
            for query in Set(queries) {
                guard let place = ProviderCatalog.servedPlace(for: lwl, query: query),
                      SelectionStep.placeCore(place) != SelectionStep.placeCore(title) else { continue }
                checked += 1
                if query != title { variants += 1 }
                if let chosen = step.preselection(for: place, query: query) {
                    XCTAssertEqual(SelectionStep.placeCore(chosen.title), SelectionStep.placeCore(title), "Suche „\(query)“ (Gemeinde \(place)) wählte „\(chosen.title)“")
                }
            }
        }
        XCTAssertGreaterThan(checked, 100)
        XCTAssertGreaterThan(variants, 5)
    }

    /// Prüfbefund 3 über `servedPlace` selbst (Nachprüfung N3 ersetzt eine Schleife, die nur den Filter nachrechnete):
    /// Bloße Namen, die in der LWL-Liste zu mehreren geführten Gemeinden gehören, liefern keine Gemeinde; ein eindeutiger
    /// Ortsteil liefert seine.
    func testLwlTwinNamesServeNoPlace() throws {
        let lwl = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == "lwl" })
        for bare in ["Zahrensdorf", "Holzendorf", "Beckendorf", "Bandekow", "Barkow", "Goldenbow"] {
            XCTAssertNil(ProviderCatalog.servedPlace(for: lwl, query: bare), "„\(bare)“ gehört zu mehreren geführten Gemeinden")
        }
        XCTAssertEqual(ProviderCatalog.servedPlace(for: lwl, query: "Kummer"), "Ludwigslust")
        XCTAssertEqual(ProviderCatalog.servedPlace(for: lwl, query: "Dabel-Woland"), "Dabel")
    }
}
