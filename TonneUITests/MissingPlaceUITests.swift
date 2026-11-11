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

    func testWizardShowsSameCardAndOpensLinkSheet() {
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
        tapFree(paste)
        checkLinkSheet("assistent-linkfeld")
        // „Verwenden“ lädt den Link: Blatt zu, Fehler als Hinweis sichtbar
        tapFree(paste)
        useFailingLink()
    }

    /// Knopf in der Suchliste antippen, ohne die schwebende Suchleiste zu treffen: Sie steht über der Tastatur und kann
    /// den Knopf verdecken (im Gesamtlauf gemessen: Knopf 497–549 pt, Suchfeld 500–528 pt), der Tipp landete dann im Suchfeld.
    private func tapFree(_ button: XCUIElement) {
        // Kein Enter ins Suchfeld: Das nahm im Gesamtlauf den Fokus weg (iPhone) bzw. klappte die Suche ein (iPad).
        // Stattdessen die Liste ein Stück schieben, bis weder Suchleiste noch Tastatur den Knopf verdecken.
        let field = app.searchFields.firstMatch
        let keyboard = app.keyboards.firstMatch
        func covered() -> Bool {
            let f = button.frame
            if field.exists, f.maxY > field.frame.minY - 4, f.minY < field.frame.maxY + 4 { return true }
            if keyboard.exists, f.maxY > keyboard.frame.minY { return true }
            return false
        }
        for _ in 0..<4 where covered() {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)))
        }
        XCTAssertFalse(covered(), "\(button.label) ist verdeckt")
        button.tap()
    }

    /// „Verwenden“ mit einem Link, der sofort scheitert: Blatt schließt, „Geht mein Ort?“ ist verlassen, der Hinweis erscheint.
    private func useFailingLink() {
        let field = element("icsLinkSheetField")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Blatt „Kalender-Link einfügen“ fehlt")
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        // Das Feld behält einen früher eingegebenen Link; ersetzen statt anhängen
        if let old = field.value as? String, !old.isEmpty, old != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText("https://beispiel.invalid/a.ics")
        app.buttons["Verwenden"].tap()
        let alert = app.alerts["Hinweis"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "Hinweis nach „Verwenden“ erscheint nicht")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "example.org")).count == 0, "alter Link wurde geladen")
        snap("assistent-link-verwenden-hinweis")
        XCTAssertFalse(field.exists, "Blatt bleibt nach „Verwenden“ offen")
        XCTAssertFalse(app.navigationBars["Geht mein Ort?"].exists, "„Geht mein Ort?“ bleibt nach „Verwenden“ stehen")
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "Suche fehlt nach dem Hinweis")
    }

    /// Blatt „Kalender-Link einfügen“: Feld fokussiert und sichtbar über der Tastatur, „Verwenden“ erst mit gültigem Link.
    private func checkLinkSheet(_ name: String) {
        let field = element("icsLinkSheetField")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Blatt „Kalender-Link einfügen“ fehlt")
        expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY, "Linkfeld liegt hinter der Tastatur")
        let use = app.buttons["Verwenden"]
        XCTAssertFalse(use.isEnabled, "„Verwenden“ ohne Link")
        field.typeText("https://example.org/abfall.ics")
        XCTAssertTrue(use.isEnabled, "„Verwenden“ bleibt mit gültigem Link aus")
        snap(name)
        app.navigationBars["Kalender-Link einfügen"].buttons["Abbrechen"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2) && field.exists, "Blatt schließt nicht")
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
        // Auf dem iPad ist das Blatt kleiner: Der Kopf liegt unter der Karte außerhalb des Bilds und wird erst beim Scrollen
        // geladen. Kein Enter ins Suchfeld (nahm im Gesamtlauf den Fokus weg), nur schieben.
        for _ in 0..<8 where !header.waitForExistence(timeout: 1) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)))
        }
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Kopf „Andere Treffer“ fehlt")
        XCTAssertTrue(header.label.localizedCaseInsensitiveContains("gelten nicht für Neunkirchen"), header.label)
        snap("assistent-neunkirchen-andere-treffer")
        // Gegenprobe: belegter Ort ohne Karte behält den einfachen Kopf
        search("Wittmund")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Treffer")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Andere Treffer")).firstMatch.exists)
    }

    private func openCoverageInWizard(searching place: String) {
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Geht mein Ort?")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        search(place)
        XCTAssertTrue(element("placeGapReason").waitForExistence(timeout: 10), "Karte fehlt in „Geht mein Ort?“")
    }

    /// Aus „Geht mein Ort?“ im Assistenten ohne geschätzte Wartezeit: Link einfügen öffnet das Blatt mit fokussiertem,
    /// sichtbarem Feld, „Termine aus Datei laden“ öffnet die Dateiauswahl.
    func testWizardCoverageActionsReachTheirTarget() {
        openWizard()
        openCoverageInWizard(searching: "Langeoog")
        let paste = element("placeGapPasteLink")
        XCTAssertTrue(paste.exists, "„Kalender-Link einfügen“ fehlt in „Geht mein Ort?“")
        tapFree(paste)
        checkLinkSheet("assistent-ort-linkfeld")

        // „Verwenden“ aus „Geht mein Ort?“: Blatt zu, Seite verlassen, Hinweis sichtbar
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        tapFree(paste)
        useFailingLink()

        // Datei laden direkt von „Geht mein Ort?“
        openCoverageInWizard(searching: "Langeoog")
        let importFile = element("placeGapImportFile")
        XCTAssertTrue(importFile.waitForExistence(timeout: 5))
        tapFree(importFile)
        // Die Dateiauswahl läuft in einem eigenen Prozess und ist in der App-Hierarchie leer. Sie deckt die Seite ab
        // (iPhone: Blatt über die volle Breite, iPad: mittiges Blatt mit Abdunklung), der Knopf ist dann nicht mehr treffbar.
        let covered = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: importFile)], timeout: 10)
        if covered != .completed {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "hierarchie-dateiauswahl"
            tree.lifetime = .keepAlways
            add(tree)
        }
        XCTAssertEqual(covered, .completed, "Dateiauswahl erscheint nicht")
        XCTAssertTrue(app.navigationBars["Geht mein Ort?"].exists, "„Geht mein Ort?“ wurde dafür verlassen")
        sleep(2)
        snap("assistent-ort-dateiauswahl")
    }
}
