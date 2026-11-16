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
}
