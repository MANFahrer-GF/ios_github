import XCTest

/// Klickt die App im Simulator durch: alle Tabs, Fenster öffnen und mit „Abbrechen“ schließen, anlegen, bearbeiten, löschen,
/// Anrufen nur mit Nachfrage. Läuft mit leerer Datenbank im Speicher plus Testdaten (Startschalter -uiTesting -uiTestingSeed).
final class TonneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // App-Store-Bilder: nur auf Wunsch (TEST_RUNNER_TONNE_MARKETING=1), mit Beispieldaten statt Testdaten
        if name.contains("Marketing") {
            guard ProcessInfo.processInfo.environment["TONNE_MARKETING"] == "1" else { throw XCTSkip("nur für App-Store-Bilder") }
            app.launchArguments = ["-uiTesting", "-demoData", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
            app.launchEnvironment["TONNE_UITESTING"] = "1"
            app.terminate(); app.launch()
            if !app.staticTexts["Oma Erika"].firstMatch.waitForExistence(timeout: 8) { app.terminate(); app.launch() }
            XCTAssertTrue(app.staticTexts["Oma Erika"].firstMatch.waitForExistence(timeout: 10), "App läuft nicht mit den Beispieldaten")
            return
        }
        // Assistent: echte Portale und der gespeicherte Datenbestand des Simulators, nur auf Wunsch (TEST_RUNNER_TONNE_WIZARD=1)
        if name.contains("Wizard") {
            guard ProcessInfo.processInfo.environment["TONNE_WIZARD"] == "1" else { throw XCTSkip("nur von Hand: ruft echte Portale ab") }
            app.launchArguments = ["-app.onboardingDone", "YES", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
            app.terminate(); app.launch()
            return
        }
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

    /// Bilder für App Store Connect: Übersicht und Geburtstage, ohne Wischen/Öffnen – genau so, wie die App startet.
    func testMarketingScreenshots() {
        tab("Übersicht"); sleep(2); snap("marketing-overview")
        tab("Termine"); app.buttons["Geburtstage"].firstMatch.tap(); sleep(2); snap("marketing-birthdays")
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
        // Auf dem iPad ist das Sheet kleiner: die Zeile liegt erst nach dem Scrollen im Bild
        for _ in 0..<4 where !app.switches["Uhrzeit"].exists { app.swipeUp() }
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

    /// Tonnendienst: Zeitraum anlegen, der erst nächsten Monat beginnt – die nächsten Abfuhren heißen dann „Du bist nicht dran“.
    func testDutyPeriods() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-demoData", "-app.onboardingDone", "YES", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Oma Erika"].firstMatch.waitForExistence(timeout: 10))
        sleep(1); snap("01-uebersicht-vorher")

        tab("Müll")
        XCTAssertTrue(text("Gifhorn").waitForExistence(timeout: 5))
        text("Gifhorn").tap()
        let add = app.buttons["Zeitraum hinzufügen"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        sleep(1); snap("02-standort-ohne-zeitraum")

        add.tap()
        XCTAssertTrue(app.navigationBars["Neuer Zeitraum"].waitForExistence(timeout: 5))
        sleep(1); snap("03-neuer-zeitraum")

        // „Von“ auf den 15. des nächsten Monats: Die nächsten Abfuhren liegen dann außerhalb
        app.datePickers.firstMatch.buttons.firstMatch.tap()
        let next = app.buttons["Nächster Monat"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap(); sleep(1)
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' 15. '")).firstMatch.tap(); sleep(1)
        // Datumswähler schließen: auf die Titelzeile, denn neben dem Fenster würde das iPad das ganze Fenster schließen
        app.navigationBars["Neuer Zeitraum"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1)
        snap("04-zeitraum-gewaehlt")
        app.buttons["Sichern"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Neuer Zeitraum"].waitForNonExistence(timeout: 5))
        let status = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nächster Dienst ab'")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), "Statuszeile fehlt")
        sleep(1); snap("05-standort-mit-zeitraum")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        tab("Übersicht")
        XCTAssertTrue(text("Du bist nicht dran").waitForExistence(timeout: 5), "Übersicht zeigt den Tonnendienst nicht")
        XCTAssertFalse(app.buttons["Bleibt drin"].exists, "„Bleibt drin“ ergibt ohne Dienst keinen Sinn")
        sleep(1); snap("06-uebersicht-nicht-dran")

        tab("Kalender"); sleep(1); snap("07-kalender")
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

    // MARK: - Absturzbericht

    private func openCrashReports() {
        tab("Mehr")
        app.buttons["Einstellungen"].tap()
        for _ in 0..<12 where !app.staticTexts["ABSTURZBERICHTE"].isHittable && !app.staticTexts["Absturzberichte"].isHittable {
            app.swipeUp()
        }
    }

    func testNoCrashReportMeansNoPromptAndAnEmptyList() {
        XCTAssertFalse(app.buttons["Ansehen und senden"].waitForExistence(timeout: 2), "Hinweis ohne Absturzbericht")
        openCrashReports()
        XCTAssertTrue(text("Keine Absturzberichte vorhanden").exists)
    }

    func testSwipedAwayOfferStaysGoneAfterRestart() {
        app.terminate()
        app.launchArguments.append("-simulateCrashReport")
        app.launch()
        XCTAssertTrue(app.buttons["Ansehen und senden"].waitForExistence(timeout: 10), "Hinweis auf den Absturz fehlt")
        let bar = app.navigationBars["Tonne & Torte ist abgestürzt"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bar.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertTrue(app.buttons["Ansehen und senden"].waitForNonExistence(timeout: 5), "Hinweis ließ sich nicht wegwischen")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-simulateCrashReport" }
        app.launchArguments.append("-keepCrashReports")
        app.launch()
        XCTAssertTrue(app.staticTexts["Lena Sommer"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Ansehen und senden"].waitForExistence(timeout: 3), "Hinweis kam nach dem Neustart wieder")
        openCrashReports()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bericht senden")).firstMatch.exists,
                      "Bericht ging beim Neustart verloren")
    }

    func testCrashReportIsOfferedOnceAndCanBeSentAndDeleted() {
        app.terminate()
        app.launchArguments.append("-simulateCrashReport")
        app.launch()

        XCTAssertTrue(app.buttons["Ansehen und senden"].waitForExistence(timeout: 10), "Hinweis auf den Absturz fehlt")
        app.buttons["Ansehen und senden"].tap()

        // Simulator hat keine Mail-App: es bleibt das Teilen
        XCTAssertTrue(app.buttons["Bericht teilen"].waitForExistence(timeout: 5), "Teilen fehlt ohne Mail-App")
        app.buttons["Schließen"].tap()
        XCTAssertTrue(app.buttons["Bericht teilen"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Ansehen und senden"].waitForExistence(timeout: 2), "Hinweis kam ein zweites Mal")

        openCrashReports()
        let send = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bericht senden")).firstMatch
        XCTAssertTrue(send.exists, "Bericht fehlt in den Einstellungen")
        send.tap()
        XCTAssertTrue(app.buttons["Bericht teilen"].waitForExistence(timeout: 5))
        app.buttons["Schließen"].tap()
        XCTAssertTrue(app.buttons["Berichte löschen"].waitForExistence(timeout: 5))
        app.buttons["Berichte löschen"].tap()
        XCTAssertTrue(text("Keine Absturzberichte vorhanden").waitForExistence(timeout: 5), "Bericht wurde nicht gelöscht")
    }

    // MARK: - Einrichtungs-Assistent (echte Portale, Reihenfolge durch die Nummer im Namen)

    private func dump(_ place: String) {
        print("WIZ[\(place)] switches:", app.switches.allElementsBoundByIndex.map { "\($0.label)=\($0.value as? String ?? "?")" })
        print("WIZ[\(place)] buttons:", app.buttons.allElementsBoundByIndex.map(\.label).prefix(40))
        print("WIZ[\(place)] texts:", app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(40))
        snap(place)
    }

    private func element(_ query: XCUIElementQuery, prefix: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Eine Auswahl im Assistenten: Suchtext eingeben, Treffer antippen.
    private func choose(_ prefix: String, search: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "Suchfeld für „\(search)“ fehlt")
        field.tap()
        // Gleich nach dem Schrittwechsel kommt der erste Tipp manchmal ohne Tastaturfokus an
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
        field.typeText(search)
        let hit = element(app.buttons, prefix: prefix)
        if !hit.waitForExistence(timeout: 20) { dump("kein-treffer-\(search)") }
        XCTAssertTrue(hit.exists, "Treffer „\(prefix)“ fehlt")
        hit.tap()
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    /// Schalter einer Müllart im letzten Schritt („Restmüll, 26 Termine“).
    private func binSwitch(_ name: String) -> XCUIElement { element(app.switches, prefix: name + ", ") }

    private func setBin(_ name: String, on: Bool) {
        let row = binSwitch(name)
        scrollTo(row)
        XCTAssertTrue(row.exists, "Schalter „\(name)“ fehlt")
        guard (row.value as? String == "1") != on else { return }
        let inner = row.switches.firstMatch
        (inner.exists ? inner : row).tap()
        XCTAssertEqual(row.value as? String, on ? "1" : "0", "Schalter „\(name)“ hat nicht umgeschaltet")
    }

    private func finishWizard() {
        let create = app.buttons["Standort anlegen"]
        scrollTo(create)
        create.tap()
        XCTAssertTrue(app.buttons["Los geht’s"].waitForExistence(timeout: 20), "Assistent wird nicht fertig")
        app.buttons["Los geht’s"].tap()
    }

    private func newWizard() {
        tab("Müll")
        let bar = app.navigationBars["Müll"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.buttons.element(boundBy: bar.buttons.count - 1).tap()
        XCTAssertTrue(app.buttons["Standort mit Entsorger anlegen"].waitForExistence(timeout: 5))
        app.buttons["Standort mit Entsorger anlegen"].tap()
    }

    /// Vorhandenen Standort über „Entsorger oder Adresse ändern“ neu einrichten.
    private func editWizard(_ location: String) {
        tab("Müll")
        let row = element(app.buttons, prefix: location)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Standort „\(location)“ fehlt")
        row.tap()
        let change = app.buttons["Entsorger oder Adresse ändern"]
        scrollTo(change)
        change.tap()
    }

    /// Zustand unter „Müll“: deaktivierte Müllarten tragen „Deaktiviert“ in ihrer Zeile.
    private func assertDisabled(_ name: String, _ disabled: Bool, file: StaticString = #filePath, line: UInt = #line) {
        tab("Müll")
        let row = element(app.buttons, prefix: name + ",")
        scrollTo(row)
        XCTAssertTrue(row.exists, "Müllart „\(name)“ fehlt unter „Müll“", file: file, line: line)
        XCTAssertEqual(row.label.contains("Deaktiviert"), disabled, "„\(name)“: \(row.label)", file: file, line: line)
    }

    /// Neu anlegen: alle neun Arten vorab an; drei Restmüll-Arten abwählen, nur „Restmüll“ bleibt.
    func testWizard1Frechen() {
        newWizard()
        choose("Stadtbetrieb Frechen", search: "Frechen")
        choose("Aachener", search: "Aachener")
        XCTAssertTrue(binSwitch("Restmüll").waitForExistence(timeout: 30), "Müllarten kommen nicht")
        XCTAssertEqual(app.switches.allElementsBoundByIndex.filter { !$0.label.isEmpty }.map { $0.value as? String }, Array(repeating: "1", count: 9))
        for name in ["Großcontainer Restmüll", "Großcontainer Restmüll 14-täglich", "Restmüll 4-wöchentlich"] { setBin(name, on: false) }
        dump("1-frechen-schalter")
        finishWizard()
        dump("1-frechen-muell")
        for name in ["Großcontainer Restmüll", "Großcontainer Restmüll 14-täglich", "Restmüll 4-wöchentlich"] { assertDisabled(name, true) }
        for name in ["Restmüll", "Grünschnittabfuhr / Bündel", "Weihnachtsbäume", "Biotonne / Biosäcke"] { assertDisabled(name, false) }
    }

    /// Gleiche Adresse neu einrichten: Schalter zeigen den gespeicherten Zustand, Einschalten wirkt.
    func testWizard2SameAddress() {
        editWizard("Frechen")
        choose("Stadtbetrieb Frechen", search: "Frechen")
        choose("Aachener", search: "Aachener")
        XCTAssertTrue(binSwitch("Restmüll").waitForExistence(timeout: 30), "Müllarten kommen nicht")
        XCTAssertEqual(binSwitch("Restmüll 4-wöchentlich").value as? String, "0")
        XCTAssertEqual(binSwitch("Restmüll").value as? String, "1")
        setBin("Restmüll 4-wöchentlich", on: true)
        dump("2-gleich-schalter")
        finishWizard()
        assertDisabled("Restmüll 4-wöchentlich", false)
        assertDisabled("Großcontainer Restmüll", true)
        assertDisabled("Restmüll", false)
    }

    /// Vorbereitung je Fall per sqlite (siehe Übergabe): eine eingeschaltete Müllart „Altart“ mit Quellentitel, den der
    /// Abruf nicht liefert (umbenannte „Weihnachtsbäume“). Andere Adresse: Die Art der alten, die die neue nicht liefert, ist aus.
    func testWizard3OtherAddress() throws {
        tab("Müll")
        guard element(app.buttons, prefix: "Altart,").waitForExistence(timeout: 5) else { throw XCTSkip("Altart nicht vorbereitet") }
        assertDisabled("Altart", false)
        editWizard("Frechen")
        choose("Stadtbetrieb Frechen", search: "Frechen")
        choose("Hauptstraße", search: "Hauptstr")
        XCTAssertTrue(binSwitch("Restmüll").waitForExistence(timeout: 30), "Müllarten kommen nicht")
        dump("3-andere-schalter")
        finishWizard()
        assertDisabled("Altart", true)
        assertDisabled("Restmüll 4-wöchentlich", false)
    }

    /// Gleiche Adresse (Hauptstraße aus Fall 3), „Altart“ wieder eingeschaltet: Sie bleibt an, denn Portale, die nur
    /// Kommendes liefern, nennen Saisonarten zeitweise gar nicht.
    func testWizard4SeasonalStays() throws {
        tab("Müll")
        guard element(app.buttons, prefix: "Altart,").waitForExistence(timeout: 5) else { throw XCTSkip("Altart nicht vorbereitet") }
        assertDisabled("Altart", false)
        editWizard("Frechen")
        choose("Stadtbetrieb Frechen", search: "Frechen")
        choose("Hauptstraße", search: "Hauptstr")
        XCTAssertTrue(binSwitch("Restmüll").waitForExistence(timeout: 30), "Müllarten kommen nicht")
        finishWizard()
        dump("4-saison-muell")
        assertDisabled("Altart", false)
        assertDisabled("Weihnachtsbäume", false)
    }

    /// Jülich (ZEW, Anlass: Grünschnitt fehlte): Grünschnitt ist im Assistenten dabei und vorab an.
    func testWizard5Juelich() {
        newWizard()
        choose("ZEW", search: "ZEW")
        choose("Jülich", search: "Jülich")
        choose("Aachener Landstr", search: "Aachener Land")
        let green = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Grün")).firstMatch
        if !green.waitForExistence(timeout: 30) { dump("5-juelich-ohne-gruen") }
        XCTAssertTrue(green.exists, "Grünschnitt fehlt im Assistenten")
        XCTAssertEqual(green.value as? String, "1", "Grünschnitt nicht vorab an")
        XCTAssertTrue(app.switches.allElementsBoundByIndex.filter { !$0.label.isEmpty }.allSatisfy { $0.value as? String == "1" }, "nicht alle Arten vorab an")
        dump("5-juelich-schalter")
        let greenName = green.label.components(separatedBy: ",").first ?? "Grün"
        finishWizard()
        assertDisabled(greenName, false)
    }

    // MARK: - Mitteilungen

    /// Absturz 2.0.8 (9): Nach dem Tippen auf eine Mitteilung rief die App UIKits Completion-Handler auf einem
    /// Concurrency-Thread auf, UIKit brach mit einer NSException ab. Laut drei Berichten (zwei Geräte) nach „Erledigt“ in der
    /// Mitteilung (AppModel.markDone im Absturz). Hier: Testmitteilung, App in den Hintergrund, lange drücken, „Erledigt“ –
    /// die App darf dabei nicht beendet werden.
    func testTappingNotificationKeepsAppRunning() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        tab("Mehr")
        app.buttons["Einstellungen"].tap()
        let allow = app.buttons["Erlauben"]
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
            let systemAllow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN {'Erlauben', 'Allow'}")).firstMatch
            if systemAllow.waitForExistence(timeout: 5) { systemAllow.tap() }
        }
        let send = app.buttons["Testmitteilung senden"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "„Testmitteilung senden“ fehlt")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: send)
        waitForExpectations(timeout: 5)
        send.tap()
        XCUIDevice.shared.press(.home)

        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Gelber Sack'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "Testmitteilung kam nicht an")
        banner.press(forDuration: 1.5)
        let done = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Erledigt'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Aktion „Erledigt“ fehlt in der Mitteilung")
        done.tap()

        sleep(4) // der Abbruch kam erst nach dem Abarbeiten der Aktion (Speichern, dann Rückmeldung an iOS)
        XCTAssertNotEqual(app.state, .notRunning, "App ist nach „Erledigt“ in der Mitteilung abgestürzt")
        app.activate()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "App zeigt nach „Erledigt“ keine Oberfläche mehr")
    }
}
