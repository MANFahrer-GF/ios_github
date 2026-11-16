import XCTest
@testable import TonneCore

/// Gemeinde-Prüfung Punkt 6 (16.11.2026): Ostprignitz-Ruppin und Potsdam-Mittelmark führen im Ort-Schritt Ortsteile statt
/// Gemeinden. Die Suche „Damelack“ fand die Gemeinde Breddin, der Assistent zeigte dann aber die ganze Liste mit 49 Orten.
final class OrtsteilVorauswahlTests: XCTestCase {
    private let step = SelectionStep(title: SelectionStep.cityTitle, options: ["Dorf Zechlin", "Damelack", "Kränzlin", "Ostprignitz-Ruppin"]
        .map { SelectionOption(id: $0, title: $0) })

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

    /// Echte Kette über die ganze LWL-Liste: Wer einen Ortsteil sucht, der eigene Option ist, bekommt nie die Gemeinde.
    func testNoLwlLocalityIsAnsweredWithItsMunicipality() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../tools/catalog/data/gemos/lwl_places.txt")
        let titles = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lwl = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == "lwl" })
        let step = SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: titles.map { SelectionOption(id: $0, title: $0) })
        var checked = 0
        for title in titles {
            guard let place = ProviderCatalog.servedPlace(for: lwl, query: title),
                  SelectionStep.placeCore(place) != SelectionStep.placeCore(title) else { continue }
            checked += 1
            if let chosen = step.preselection(for: place, query: title) {
                XCTAssertEqual(SelectionStep.placeCore(chosen.title), SelectionStep.placeCore(title), "Suche „\(title)“ (Gemeinde \(place)) wählte „\(chosen.title)“")
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }
}
