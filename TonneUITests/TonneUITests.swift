import XCTest

/// Klickt die App im Simulator durch: alle Tabs, Fenster öffnen und mit „Abbrechen“ schließen, anlegen, bearbeiten, löschen,
/// Anrufen nur mit Nachfrage. Läuft mit leerer Datenbank im Speicher plus Testdaten (Startschalter -uiTesting -uiTestingSeed).
final class TonneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingSeed", "-app.onboardingDone", "YES", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["TONNE_UITESTING"] = "1"
        app.terminate()
        app.launch()
        // Beim ersten Start eines Laufs kommen die Startschalter manchmal nicht an – dann einmal neu starten.
        // Sicherheitsnetz: ohne Testdaten (echte Daten im Simulator) bricht der Test ab, statt daran zu arbeiten.
        if !app.staticTexts["Lena Sommer"].firstMatch.waitForExistence(timeout: 8) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.staticTexts["Lena Sommer"].firstMatch.waitForExistence(timeout: 10), "App läuft nicht mit den Testdaten")
    }

    // MARK: - Hilfen

    private func tab(_ name: String) {
        let bar = app.tabBars.buttons[name]
        if bar.waitForExistence(timeout: 3) { bar.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    private func text(_ label: String) -> XCUIElement { app.staticTexts[label].firstMatch }

    /// Schalter wie ein Mensch umlegen: auf den Schalter selbst tippen, nicht auf die Zeilenmitte (schaltet unter iOS 26 nicht).
    private func flip(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.switches[label].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Schalter „\(label)“ fehlt", file: file, line: line)
        let before = row.value as? String
        let inner = row.switches.firstMatch
        (inner.exists ? inner : row).tap()
        XCTAssertNotEqual(row.value as? String, before, "Schalter „\(label)“ hat nicht umgeschaltet", file: file, line: line)
    }

    /// Ein Fenster mit diesem Titel ist offen und geht mit „Abbrechen“ wieder zu.
    private func assertOpenThenCancel(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Fenster „\(title)“ geht nicht auf", file: file, line: line)
        app.buttons["Abbrechen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[title].waitForNonExistence(timeout: 5), "„Abbrechen“ schließt „\(title)“ nicht", file: file, line: line)
    }

    /// „Anrufen“ fragt nach – und „Abbrechen“ in der Nachfrage ruft nicht an.
    private func assertCallAsksFirst(name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["\(name) anrufen?"].waitForExistence(timeout: 5), "keine Nachfrage vor dem Anruf", file: file, line: line)
        // iOS 26 zeigt die Nachfrage als kleines Menü: ohne eigenen Abbrechen-Knopf, schließen durch Tippen daneben
        let dismiss = app.descendants(matching: .any)["Einblendmenü schließen"].firstMatch
        if app.buttons["Abbrechen"].exists { app.buttons["Abbrechen"].firstMatch.tap() }
        else if dismiss.exists { dismiss.tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap() }
        XCTAssertTrue(app.staticTexts["\(name) anrufen?"].waitForNonExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, "App hat die Telefon-App geöffnet", file: file, line: line)
    }

    /// Screenshot für die Sichtprüfung (bleibt im Testergebnis).
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Jede Seite einmal fotografieren – zum Prüfen, ob auf dem iPhone etwas abgeschnitten ist.
    func testScreenshotsAllPages() {
        tab("Übersicht"); sleep(1); snap("01-uebersicht-oben")
        app.swipeUp(); sleep(1); snap("02-uebersicht-unten")
        tab("Kalender"); sleep(1); snap("03-kalender")
        app.swipeUp(); sleep(1); snap("04-kalender-tag")
        tab("Müll"); sleep(1); snap("05-muell")
        tab("Termine"); app.buttons["Geburtstage"].firstMatch.tap(); sleep(1); snap("06-geburtstage")
        app.swipeUp(); sleep(1); snap("07-geburtstage-unten")
        app.swipeDown(); app.swipeDown()
        text("Test Person").firstMatch.tap(); sleep(1); snap("08-geburtstag-bearbeiten")
        app.swipeUp(); sleep(1); snap("09-geburtstag-bearbeiten-unten")
        app.navigationBars["Geburtstag"].buttons["Abbrechen"].tap()
        app.buttons["Eigene Termine"].firstMatch.tap(); sleep(1); snap("10-eigene-termine")
        text("Testtermin").tap(); sleep(1); snap("11-termin-bearbeiten")
        app.swipeUp(); sleep(1); snap("12-termin-bearbeiten-unten")
        app.navigationBars["Termin"].buttons["Abbrechen"].tap()
        tab("Mehr"); sleep(1); snap("13-mehr")
        app.buttons["Einstellungen"].tap(); sleep(1); snap("14-einstellungen")
        app.swipeUp(); sleep(1); snap("15-einstellungen-2")
        app.swipeUp(); sleep(1); snap("16-einstellungen-3")
        app.swipeUp(); sleep(1); snap("17-einstellungen-4")
    }

    // MARK: - Übersicht

    func testOverviewOpensEverything() {
        tab("Übersicht")
        XCTAssertTrue(text("Test Person").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Jg. 1960").exists, "Jahrgang fehlt in der Übersicht")
        XCTAssertTrue(text("🎂 wird 66").exists, "Alter fehlt in der Übersicht")

        text("Test Person").tap()
        assertOpenThenCancel("Geburtstag")

        text("Testtermin").tap()
        assertOpenThenCancel("Termin")

        let paper = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Papier'")).firstMatch
        for _ in 0..<4 where !(paper.exists && paper.isHittable) { app.swipeUp() }
        paper.tap()
        XCTAssertTrue(app.buttons["Fertig"].waitForExistence(timeout: 5), "Müllart öffnet sich nicht")
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.buttons["Fertig"].waitForNonExistence(timeout: 5))

        for _ in 0..<4 { app.swipeDown() }
        // Anrufen/Nachricht nur am Geburtstag selbst: Lena (heute) hat sie, Test Person (in 3 Tagen) nicht
        XCTAssertTrue(text("Lena Sommer").exists)
        XCTAssertEqual(app.buttons.matching(identifier: "Anrufen").count, 1, "Anrufen soll nur beim heutigen Geburtstag stehen")
        XCTAssertEqual(app.buttons.matching(identifier: "Nachricht").count, 1)
        app.buttons["Anrufen"].firstMatch.tap()
        assertCallAsksFirst(name: "Lena Sommer")
    }

    // MARK: - Termine › Geburtstage

    func testBirthdays() {
        tab("Termine")
        app.buttons["Geburtstage"].firstMatch.tap()
        XCTAssertTrue(text("Test Person").waitForExistence(timeout: 5))

        // Öffnen, Jahr ausschalten zeigt Tag/Monat statt Datum, unten Glückwunsch und Anrufen (mit Nachfrage), Abbrechen
        text("Test Person").tap()
        XCTAssertTrue(app.navigationBars["Geburtstag"].waitForExistence(timeout: 5))
        flip("Geburtsjahr bekannt")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tag'")).firstMatch.waitForExistence(timeout: 3) || text("Tag").exists, "ohne Jahr fehlt die Tag-Auswahl")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Monat'")).firstMatch.exists || text("Monat").exists, "ohne Jahr fehlt die Monats-Auswahl")
        XCTAssertFalse(app.datePickers.firstMatch.exists, "ohne Jahr steht noch eine Datumsauswahl mit Jahr da")
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertTrue(app.buttons["Glückwunsch per Nachricht senden"].exists || app.links["Glückwunsch per Nachricht senden"].exists, "Glückwunsch fehlt")
        app.buttons["Anrufen"].firstMatch.tap()
        assertCallAsksFirst(name: "Test Person")
        app.buttons["Abbrechen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Geburtstag"].waitForNonExistence(timeout: 5))

        // Wischen: Gratulieren und Anrufen (mit Nachfrage)
        let row = app.cells.containing(.staticText, identifier: "Test Person").firstMatch
        if row.exists {
            row.swipeRight()
            XCTAssertTrue(app.buttons["Gratulieren"].waitForExistence(timeout: 3))
            app.buttons["Anrufen"].firstMatch.tap()
            assertCallAsksFirst(name: "Test Person")
        }

        // Neu anlegen ohne Jahr, sichern, wieder löschen
        app.navigationBars["Termine"].buttons.element(boundBy: app.navigationBars["Termine"].buttons.count - 1).tap()
        XCTAssertTrue(app.buttons["Als CSV exportieren (Excel)"].waitForExistence(timeout: 3), "CSV-Export fehlt bei Geburtstagen")
        XCTAssertTrue(app.buttons["Als PDF exportieren"].exists, "PDF-Export fehlt bei Geburtstagen")
        app.buttons["Neuer Geburtstag"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Geburtstag"].waitForExistence(timeout: 5))
        let name = app.textFields["Name"].firstMatch
        name.tap(); name.typeText("Neu Person")
        flip("Geburtsjahr bekannt")
        app.navigationBars["Geburtstag"].buttons["Sichern"].tap()
        // Ohne gewähltes Datum landet er am 1. Januar – also weiter unten in der Liste
        for _ in 0..<8 where !(text("Neu Person").exists && text("Neu Person").isHittable) { app.swipeUp() }
        XCTAssertTrue(text("Neu Person").waitForExistence(timeout: 5), "neuer Geburtstag fehlt in der Liste")
        text("Neu Person").tap()
        XCTAssertTrue(app.navigationBars["Geburtstag"].waitForExistence(timeout: 5))
        app.swipeUp(); app.swipeUp()
        app.buttons["Geburtstag löschen"].firstMatch.tap()
        app.buttons["Löschen"].firstMatch.tap()
        XCTAssertTrue(text("Neu Person").waitForNonExistence(timeout: 5), "Geburtstag wurde nicht gelöscht")
    }

    // MARK: - Termine › Eigene Termine

    func testCustomEvents() {
        tab("Termine")
        app.buttons["Eigene Termine"].firstMatch.tap()
        XCTAssertTrue(text("Testtermin").waitForExistence(timeout: 5))

        text("Testtermin").tap()
        assertOpenThenCancel("Termin")

        // Neu: Vorlage, Uhrzeit, Symbol wählen, sichern
        app.navigationBars["Termine"].buttons.element(boundBy: app.navigationBars["Termine"].buttons.count - 1).tap()
        XCTAssertTrue(app.buttons["Als CSV exportieren (Excel)"].waitForExistence(timeout: 3), "CSV-Export fehlt bei eigenen Terminen")
        XCTAssertTrue(app.buttons["Als PDF exportieren"].exists, "PDF-Export fehlt bei eigenen Terminen")
        app.buttons["Neuer Termin"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Neuer Termin"].waitForExistence(timeout: 5), "„+“ öffnet keinen neuen Termin")
        app.buttons["Rauchmelder testen"].firstMatch.tap()
        flip("Uhrzeit")
        app.swipeUp()
        app.buttons["Symbol"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Symbol"].waitForExistence(timeout: 5), "Symbol-Seite geht nicht auf")
        app.navigationBars["Symbol"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Neuer Termin"].buttons["Sichern"].tap()
        XCTAssertTrue(text("Rauchmelder testen").waitForExistence(timeout: 5), "neuer Termin fehlt in der Liste")

        // Erledigt per Wischen, dann löschen
        let row = app.cells.containing(.staticText, identifier: "Rauchmelder testen").firstMatch
        if row.exists {
            row.swipeRight()
            if app.buttons["Erledigt"].waitForExistence(timeout: 3) { app.buttons["Erledigt"].tap() }
        }
        text("Rauchmelder testen").tap()
        XCTAssertTrue(app.navigationBars["Termin"].waitForExistence(timeout: 5))
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        app.buttons["Termin löschen"].firstMatch.tap()
        XCTAssertTrue(text("Rauchmelder testen").waitForNonExistence(timeout: 5), "Termin wurde nicht gelöscht")
    }

    // MARK: - Kalender

    func testCalendarOpensEntries() {
        tab("Kalender")
        app.buttons["Heute"].firstMatch.tap()
        XCTAssertTrue(text("Testtermin").waitForExistence(timeout: 5), "heutiger Termin fehlt im Kalender")
        text("Testtermin").tap()
        assertOpenThenCancel("Termin")
    }

    // MARK: - Müll

    func testWasteTab() {
        tab("Müll")
        XCTAssertTrue(text("Papier").waitForExistence(timeout: 5))
        text("Papier").tap()
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(text("Papier").waitForExistence(timeout: 5))
    }

    // MARK: - Mehr und Einstellungen

    func testMoreAndSettings() {
        tab("Mehr")
        for link in ["Abfall-ABC", "Geht mein Ort?", "Kalender-Abgleich", "Siri & Kurzbefehle", "Einstellungen"] {
            let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", link)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "„\(link)“ fehlt unter Mehr")
            button.tap()
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5), "„\(link)“ öffnet keine Seite")
            back.tap()
            XCTAssertTrue(app.buttons["Einstellungen"].waitForExistence(timeout: 5), "von „\(link)“ kein Weg zurück")
        }
        XCTAssertFalse(app.buttons["Eigene Termine"].exists, "Eigene Termine stehen noch unter Mehr")

        // Einstellungen: jeden Schalter zweimal umlegen (an/aus), dabei durch die Seite scrollen
        app.buttons["Einstellungen"].tap()
        var flipped = Set<String>()
        for _ in 0..<8 {
            for toggle in app.switches.allElementsBoundByIndex where toggle.isHittable && !toggle.label.isEmpty && !flipped.contains(toggle.label) {
                flipped.insert(toggle.label)
                flip(toggle.label); flip(toggle.label)
            }
            app.swipeUp()
        }
        XCTAssertGreaterThanOrEqual(flipped.count, 10, "zu wenige Schalter gefunden: \(flipped)")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
