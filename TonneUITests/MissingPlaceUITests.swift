import XCTest

/// Meldung für Orte ohne abrufbaren Online-Kalender: gleiche Karte in „Geht mein Ort?“ und im Assistenten, Grund mit
/// Entsorger und Prüftag, Knöpfe statt Hilfetext. Ohne Netz (Testdaten, Prüfung aus der erzeugten Zuordnung).
final class MissingPlaceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingSeed", "-app.onboardingDone", "YES", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["TONNE_UITESTING"] = "1"
        app.terminate()
        app.launch()
        if !app.staticTexts["Lena Sommer"].firstMatch.waitForExistence(timeout: 8) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.staticTexts["Lena Sommer"].firstMatch.waitForExistence(timeout: 10), "App läuft nicht mit den Testdaten")
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tab(_ name: String) {
        let bar = app.tabBars.buttons[name]
        if bar.waitForExistence(timeout: 3) { bar.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Suchfeld fehlt")
        field.tap()
        // Fokus am Suchfeld selbst prüfen – die Tastatur kann noch einem anderen Feld gehören (Linkfeld im Assistenten)
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 3) != .completed { field.tap() }
        if let old = field.value as? String, !old.isEmpty, old != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(text)
    }

    private func reasonText() -> String {
        let reason = element("placeGapReason")
        XCTAssertTrue(reason.waitForExistence(timeout: 10), "Karte mit Grund fehlt")
        return reason.label
    }

    func testCoverageShowsReasonPerPlace() {
        tab("Mehr")
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Geht mein Ort?")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        // Ohne Eingabe: keine lange Liste „Es fehlen noch: …“ mehr
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Es fehlen noch")).firstMatch.exists)

        // Nur PDF: Entsorger, Prüftag und Webseite
        search("Langeoog")
        var text = reasonText()
        XCTAssertTrue(text.contains("Landkreis Wittmund (Abfuhr Fa. Augustin)"), text)
        XCTAssertTrue(text.contains("11.11.2026"), text)
        XCTAssertTrue(text.contains("PDF"), text)
        XCTAssertTrue(element("placeGapWebsite").exists, "Webseite des Entsorgers fehlt")
        XCTAssertTrue(element("placeGapReport").exists, "„Ort melden“ fehlt")
        XCTAssertFalse(element("placeGapPasteLink").exists, "außerhalb des Assistenten gibt es kein Linkfeld")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "nächsten Updates")).firstMatch.exists)
        snap("ort-langeoog-nur-pdf")

        // Nicht geführt: Gemeinde und Entsorger im Satz
        search("Gröde")
        text = reasonText()
        XCTAssertTrue(text.contains("stand Gröde nicht im Online-Kalender"), text)
        snap("ort-groede-nicht-gefuehrt")
        element("placeGapMore").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Feste Abfuhr")).firstMatch.waitForExistence(timeout: 5),
                      "„Weitere Möglichkeiten“ klappt nicht auf")
        snap("ort-groede-weitere-moeglichkeiten")

        // Gegenprobe: belegter Ort ohne Karte
        search("Neuss")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Neuss ·")).firstMatch.waitForExistence(timeout: 10)
                      || app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Neuss ·")).firstMatch.exists,
                      "Neuss wird nicht gefunden")
        XCTAssertFalse(element("placeGapReason").exists, "belegter Ort zeigt eine Lücke")
        snap("ort-neuss-belegt")
    }

    func testWizardShowsSameCardAndJumpsToLinkField() {
        tab("Müll")
        let bar = app.navigationBars["Müll"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.buttons.element(boundBy: bar.buttons.count - 1).tap()
        XCTAssertTrue(app.buttons["Standort mit Entsorger anlegen"].waitForExistence(timeout: 5))
        app.buttons["Standort mit Entsorger anlegen"].tap()

        search("Langeoog")
        let text = reasonText()
        XCTAssertTrue(text.contains("Landkreis Wittmund (Abfuhr Fa. Augustin)"), text)
        XCTAssertTrue(element("placeGapImportFile").exists, "„Termine aus Datei laden“ fehlt")
        // Kein Kreis-Entsorger als Kandidat, der Langeoog nicht führt
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Landkreis Wittmund")).firstMatch.exists,
                       "Kreis-Entsorger wird für Langeoog angeboten")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kein Entsorger gefunden")).firstMatch.exists,
                       "leere Trefferliste widerspricht der Karte")
        snap("assistent-langeoog")

        // Gegenprobe im selben Kreis: Wittmund ist belegt, keine Karte, Kreis-Entsorger wählbar
        search("Wittmund")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Landkreis Wittmund")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(element("placeGapReason").exists, "belegter Ort zeigt eine Lücke")

        // Zurück zu Langeoog: Knopf springt ins Linkfeld
        search("Langeoog")
        XCTAssertTrue(element("placeGapReason").waitForExistence(timeout: 10))

        let paste = element("placeGapPasteLink")
        XCTAssertTrue(paste.exists, "„Kalender-Link einfügen“ fehlt")
        paste.tap()
        let field = element("icsLinkField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        snap("assistent-linkfeld")

    }

    private func openWizard() {
        tab("Müll")
        let bar = app.navigationBars["Müll"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.buttons.element(boundBy: bar.buttons.count - 1).tap()
        XCTAssertTrue(app.buttons["Standort mit Entsorger anlegen"].waitForExistence(timeout: 5))
        app.buttons["Standort mit Entsorger anlegen"].tap()
    }

    /// Gleichnamige Orte: Neben der Karte für Neunkirchen (Saar, nur PDF) sagt der Kopf, dass die übrigen Treffer
    /// nicht für diesen Ort gelten.
    func testWizardMarksResultsOfOtherSameNamePlaces() {
        openWizard()
        search("Neunkirchen")
        XCTAssertTrue(element("placeGapReason").waitForExistence(timeout: 10), "Karte für Neunkirchen fehlt")
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Andere Treffer")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Kopf „Andere Treffer“ fehlt")
        XCTAssertTrue(header.label.localizedCaseInsensitiveContains("gelten nicht für Neunkirchen"), header.label)
        app.searchFields.firstMatch.typeText("\n")
        for _ in 0..<4 where !header.isHittable { app.swipeUp() }
        snap("assistent-neunkirchen-andere-treffer")
        // Gegenprobe: belegter Ort ohne Karte behält den einfachen Kopf
        search("Wittmund")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Treffer")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Andere Treffer")).firstMatch.exists)
    }
}
