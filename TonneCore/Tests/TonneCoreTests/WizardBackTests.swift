import XCTest
@testable import TonneCore

final class WizardBackTests: XCTestCase {
    /// Ort gewählt, Straße automatisch (einzige Option), jetzt Hausnummern: „Zurück“ führt zur Ortsliste.
    func testBackSkipsAutoSelectedStep() {
        XCTAssertEqual(WizardBack.remainingCount(selectionCount: 2, auto: [1]), 0)
    }

    /// Ohne automatische Schritte: wie bisher eine Auswahl zurück.
    func testBackWithoutAutoRemovesOne() {
        XCTAssertEqual(WizardBack.remainingCount(selectionCount: 3, auto: []), 2)
    }

    /// Automatischer Schritt in der Mitte bleibt, wenn danach selbst gewählt wurde.
    func testAutoInTheMiddleStays() {
        XCTAssertEqual(WizardBack.remainingCount(selectionCount: 3, auto: [1]), 2)
        XCTAssertEqual(WizardBack.remainingCount(selectionCount: 0, auto: []), 0)
    }
}
