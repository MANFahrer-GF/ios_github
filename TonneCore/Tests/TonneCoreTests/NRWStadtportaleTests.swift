import XCTest
@testable import TonneCore

final class NRWStadtportaleTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    func testDetmoldStreetsFromScript() {
        let html = #"strasse[1] = {"id":"1","name":"55er Str.","tag":"3"};strasse[2] = {"id":"2","name":"Aachener Str.","tag":"4"};"#
        XCTAssertEqual(NRWPortalsProvider.detmoldStreets(html).map(\.title), ["55er Str.", "Aachener Str."])
    }

    func testHertenDuplicateStreetsGetSections() {
        let html = "<option selected value=1>Achtenbecksweg</option><option value=7>Albert-Einstein-Allee    </option><option value=8>Albert-Einstein-Allee</option>"
        let options = NRWPortalsProvider.hertenStreets(html, letter: "A")
        XCTAssertEqual(options.map(\.id), ["A|1", "A|7", "A|8"])
        XCTAssertEqual(options.map(\.title), ["Achtenbecksweg", "Albert-Einstein-Allee (Abschnitt 1)", "Albert-Einstein-Allee (Abschnitt 2)"])
        XCTAssertTrue(NRWPortalsProvider.hertenPage("Z").hasSuffix("von=Z&bis=["))
    }

    func testBruehlSplitsCombinedSummary() {
        XCTAssertEqual(NRWPortalsProvider.bruehlNames("Gelber Sack (gelb), Altpapier (blau) - Kölnstraße 1 (Bezirk: 5K) - Stadt Brühl | Abteilung Stadtservice"),
                       ["Gelber Sack", "Altpapier"])
        XCTAssertEqual(NRWPortalsProvider.bruehlNames("Hausmüll (grau), Straßenlaub - Kölnstraße 1 (Bezirk: 5K) - Stadt Brühl"), ["Hausmüll", "Straßenlaub"])
    }

    func testMonheimFiltersDistrictsAndSkipsRecyclingCentre() {
        let entries = [("2026-12-08", "1", "7"), ("2026-12-09", "", "1"), ("2026-12-10", "5,6", "5"), ("2026-12-11", "", "2"), ("2026-12-12", "3", "6")]
        let pickups = NRWPortalsProvider.monheimPickups(entries, streetDistricts: "10,6", calendar: calendar)
        XCTAssertEqual(pickups.map(\.name), ["Gelber Sack", "Schadstoffmobil"])
        XCTAssertEqual(pickups.first?.date, day(2026, 12, 10))
    }

    func testVelbertCalendar() {
        let html = """
        <td class="abfkalkopf1" colspan="3">Abfallkalender 2026 - Juli bis Dezember</td>
        <table class="abfkalmonrahm"><thead><tr><th class="abfkalmonkopf" colspan="2">Juli</th></tr></thead><tbody>
        <tr> <td class="abfkaltaglinks abfkalwochtag">07&nbsp;&nbsp;Di&nbsp;&nbsp;</td> <td class="abfkaltagrechts abfkalwochtag"> </td> </tr>
        <tr> <td class="abfkaltaglinks abfkalwochtag">08&nbsp;&nbsp;Mi&nbsp;&nbsp;</td> <td class="abfkaltagrechts abfkalwochtag"> <img src="/_assets/x/Icons/abfall_braun.png?1" class="abfkalsymb" /> <img src="/_assets/x/Icons/abfall_grau.png?1" class="abfkalsymb" /></td> </tr>
        </tbody></table>
        <table class="abfkallegendcont "> <tr><td class="abfkaltonne"><br><img src="/_assets/x/Icons/abfall_grau.png?1" class="abfkalsymbleg" /></td><td class="tonnetext"><br>Restmülltonne</td></tr>
        <tr><td class="abfkaltonne"><img src="/_assets/x/Icons/abfall_braun.png?1" class="abfkalsymbleg" /></td><td class="tonnetext">Biotonne</td></tr></table>
        """
        let pickups = NRWPortalsProvider.velbertCalendar(html, calendar: calendar)
        XCTAssertEqual(pickups, [Pickup(date: day(2026, 7, 8), name: "Biotonne"), Pickup(date: day(2026, 7, 8), name: "Restmülltonne")])
    }

    /// Live (11.11.2026): je Dienst eine echte Adresse bis zu den Terminen; `TONNE_LIVE=1`.
    func testLiveStadtportale() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        L10n.forcedLanguage = "de"
        // Eingaben je Schritt: Listenwahl über den Titel, freie Eingabe als Text.
        let cases: [(key: String, inputs: [String])] = [
            ("detmold", ["Aachener Str."]), ("herten", ["Acker", "Ackerstraße"]), ("castrop", ["Ackerstr.", "1"]),
            ("monheim", ["Ackerweg"]), ("roesrath", ["Akazienweg (nur Haus Nr. 5)"]), ("bruehl", ["Kölnstraße", "1"]),
            ("siegen", ["ADALBERT-STIFTER-WEG", "1"]), ("verl", ["Abfuhrbezirk 1"]), ("velbert", ["Friedrichstraße 1"]),
        ]
        let today = Calendar.current.startOfDay(for: Date())
        for (key, inputs) in cases {
            let provider = NRWPortalsProvider(service: key)
            var selections: [SelectionOption] = []
            for input in inputs {
                guard let step = try await provider.nextStep(after: selections) else { XCTFail("\(key): Schritt fehlt"); break }
                if step.input == .text {
                    selections.append(SelectionOption(id: input, title: input))
                } else {
                    guard let option = step.options.first(where: { $0.title == input }) else { XCTFail("\(key): „\(input)“ fehlt"); break }
                    selections.append(option)
                }
            }
            let pickups = try await provider.pickups(for: selections, calendar: .current).filter { $0.date >= today }
            print("LIVE|\(key)|\(provider.label(for: selections))|termine=\(pickups.count)|\(Set(pickups.map(\.name)).sorted().joined(separator: ","))")
            XCTAssertGreaterThan(pickups.count, 3, key)
        }
    }
}
