import XCTest
@testable import TonneCore

/// AWM München: Straßenliste, Formular-Parser und ICS-Auflösung (BYDAY/EXDATE) offline; Live-Durchläufe.
final class AWMMuenchenProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return cal
    }

    func testStreets() {
        let html = #"<div id="strassenliste"><span class="aostrasse">Marienpl.</span> <span class="aostrasse">Dall&#039;Armistr.</span><span class="aostrasse">Geretsrieder Str.</span><span class="aostrasse">Marienpl.</span></div>"#
        let streets = AWMMuenchenProvider.streets(in: html)
        XCTAssertEqual(streets.map(\.id), ["Dall'Armistr.", "Geretsrieder Str.", "Marienpl."])
        XCTAssertEqual(streets.map(\.title), ["Dall'Armistraße", "Geretsrieder Straße", "Marienplatz"])
        XCTAssertEqual(AWMMuenchenProvider.expandStreet("Fritz-Erler-Str."), "Fritz-Erler-Straße")
        XCTAssertEqual(AWMMuenchenProvider.expandStreet("St.-Martin-Str."), "St.-Martin-Straße")
    }

    func testFormWithCycleChoice() {
        let html = """
        <form method="post" name="abfuhrkalender" id="abfuhrkalender" action="/abfall-entsorgen/muelltonnen/abfuhrkalender?a=1&amp;cHash=abc">
        <input type="hidden" name="tx_awmabfuhrkalender_abfuhrkalender[__trustedProperties]" value="{&quot;section&quot;:1}0f" />
        <label for="leerungszyklus" class="long">Leerungszyklus für <strong>Restmülltonne</strong> wählen</label>
        <select name="tx_awmabfuhrkalender_abfuhrkalender[leerungszyklus][R]" class="form-control mb-1" id="leerungszyklus" size="3">
        <option value="001;U">1x pro Woche</option><option value="003;U">3x pro Woche</option></select>
        <input id="leerungszyklus_B" type="hidden" name="tx_awmabfuhrkalender_abfuhrkalender[leerungszyklus][B]" value="1/2;G" />
        <input class="btn submitButton" id="submitAbfuhrkalender" type="submit" value="Weiter" name="tx_awmabfuhrkalender_abfuhrkalender[submitAbfuhrkalender]" />
        </form>
        """
        guard let form = AWMMuenchenProvider.form(in: html) else { return XCTFail("Formular nicht erkannt") }
        XCTAssertEqual(form.action, "https://www.awm-muenchen.de/abfall-entsorgen/muelltonnen/abfuhrkalender?a=1&cHash=abc")
        let fields = Dictionary(form.fields, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(fields["tx_awmabfuhrkalender_abfuhrkalender[__trustedProperties]"], "{\"section\":1}0f")
        XCTAssertEqual(fields["tx_awmabfuhrkalender_abfuhrkalender[leerungszyklus][B]"], "1/2;G")
        XCTAssertEqual(fields["tx_awmabfuhrkalender_abfuhrkalender[submitAbfuhrkalender]"], "Weiter")
        XCTAssertEqual(form.selects.count, 1)
        let step = AWMMuenchenProvider.step(for: form.selects[0])
        XCTAssertEqual(step.title, "Leerungszyklus Restmülltonne")
        XCTAssertEqual(step.options.map(\.id), ["[leerungszyklus][R]|001;U", "[leerungszyklus][R]|003;U"])
        XCTAssertEqual(step.options.map(\.title), ["1x pro Woche", "3x pro Woche"])
    }

    func testLinksAndErrors() {
        let page = #"<div class="icsButtons"><a href="/abfall-entsorgen/muelltonnen/abfuhrkalender?x%5By%5D=1&cHash=9" class="downloadics"><i></i></a></div>"#
        XCTAssertEqual(AWMMuenchenProvider.icsLinks(in: page), ["https://www.awm-muenchen.de/abfall-entsorgen/muelltonnen/abfuhrkalender?x%5By%5D=1&cHash=9"])
        let error = #"<div class="message messageError">Die Adresse konnte nicht gefunden werden.<br /></div>"#
        XCTAssertEqual(AWMMuenchenProvider.errorMessage(in: error), "Die Adresse konnte nicht gefunden werden.")
        XCTAssertNil(AWMMuenchenProvider.errorMessage(in: page))
    }

    func testParseICSWithByDayAndExdate() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        SUMMARY:Restmülltonne, Marienpl. 1
        DTSTART;TZID=Europe/Berlin;VALUE=DATE:20261123
        RRULE:FREQ=WEEKLY;UNTIL=20261231;BYDAY=MO,WE;WKST=MO
        EXDATE;VALUE=DATE:20261221T000000
        EXDATE;VALUE=DATE:20261223T000000
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY: Achtung: Restmülltonne, Marienpl. 1
        DTSTART;TZID=Europe/Berlin;VALUE=DATE:20261221
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:Biotonne, Marienpl. 1
        DTSTART;TZID=Europe/Berlin;VALUE=DATE:20261113
        RRULE:FREQ=WEEKLY;INTERVAL=2;UNTIL=20261231;BYDAY=FR;WKST=MO
        EXDATE;VALUE=DATE:20261225T000000
        END:VEVENT
        END:VCALENDAR
        """
        let cal = calendar
        let pickups = AWMMuenchenProvider.parseICS(ics, calendar: cal)
        let rest = pickups.filter { $0.name == "Restmülltonne" }.map { Days.iso($0.date, calendar: cal) }
        // Mo/Mi ab 23.11., ohne 21./23.12., dafür der Achtung-Termin am 21.12.
        XCTAssertEqual(rest.first, "2026-11-23")
        XCTAssertEqual(rest[1], "2026-11-25")
        XCTAssertFalse(rest.contains("2026-12-23"))
        XCTAssertEqual(rest.filter { $0 == "2026-12-21" }.count, 1)
        XCTAssertTrue(rest.contains("2026-12-30"))
        XCTAssertEqual(rest.count, 11)
        XCTAssertNotNil(pickups.first { $0.name == "Restmülltonne" && Days.iso($0.date, calendar: cal) == "2026-12-21" }?.note)
        let bio = pickups.filter { $0.name == "Biotonne" }.map { Days.iso($0.date, calendar: cal) }
        XCTAssertEqual(bio, ["2026-11-13", "2026-11-27", "2026-12-11"])
        XCTAssertEqual(WasteCategory.classify("Restmülltonne"), .residual)
        XCTAssertEqual(WasteCategory.classify("Papiertonne"), .paper)
        XCTAssertEqual(WasteCategory.classify("Biotonne"), .organic)
    }

    func testLabel() {
        let provider = AWMMuenchenProvider()
        let selections = [SelectionOption(id: "Marienpl.", title: "Marienplatz"), SelectionOption(id: "1", title: "1"),
                          SelectionOption(id: "[leerungszyklus][R]|001;U", title: "1x pro Woche")]
        XCTAssertEqual(provider.label(for: selections), "München, Marienplatz 1")
        XCTAssertEqual(provider.serviceKey, "muenchen")
    }
}

extension LiveProviderTests {
    /// Marienplatz 1: Leerungszyklus für Restmüll und Papier als eigene Listenschritte.
    func testAWMMuenchenMarienplatz() async throws {
        try XCTSkipUnless(live, "TONNE_LIVE nicht gesetzt")
        let provider = AWMMuenchenProvider()
        let selections = try await walkTyped(provider, typed: ["1"], prefer: ["Marienplatz", "1x pro Woche", "2x pro Woche"])
        XCTAssertEqual(selections.count, 4)
        XCTAssertTrue(selections[2].id.hasPrefix("[leerungszyklus]"))
        let pickups = try await provider.pickups(for: selections)
        let names = Set(pickups.map(\.name))
        print("awmMuenchen: \(provider.label(for: selections)) → \(pickups.count) Termine, \(names.sorted())")
        XCTAssertGreaterThanOrEqual(pickups.count, 20)
        XCTAssertTrue(names.contains { WasteCategory.classify($0) == .residual })
        XCTAssertTrue(names.contains { WasteCategory.classify($0) == .paper })
    }

    /// Bellinzonastr. 19 und Waltenbergerstr. 1: ein Stellplatz, Kalender direkt nach der Adresse.
    func testAWMMuenchenBellinzonastrasse() async throws {
        try await checkTyped(AWMMuenchenProvider(), typed: ["19"], prefer: ["Bellinzonastraße"], minCount: 10)
    }

    func testAWMMuenchenWaltenbergerstrasse() async throws {
        try await checkTyped(AWMMuenchenProvider(), typed: ["1"], prefer: ["Waltenbergerstraße"], minCount: 10)
    }

    func testAWMMuenchenUnknownAddress() async throws {
        try XCTSkipUnless(live, "TONNE_LIVE nicht gesetzt")
        let selections = [SelectionOption(id: "Bellinzonastr.", title: "Bellinzonastraße"), SelectionOption(id: "999", title: "999")]
        do {
            _ = try await AWMMuenchenProvider().nextStep(after: selections)
            XCTFail("Fehler erwartet")
        } catch ProviderError.invalidSelection(let message) {
            XCTAssertTrue(message.contains("nicht gefunden"))
        }
    }
}
