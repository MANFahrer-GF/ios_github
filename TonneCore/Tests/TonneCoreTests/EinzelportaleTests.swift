import XCTest
@testable import TonneCore

final class EinzelportaleTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

    /// Frankenberg: das SUMMARY im Erinnerungsblock („ABFUHRTERMIN“) darf den Termintitel nicht überschreiben.
    func testAlarmSummaryDoesNotReplaceEventTitle() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART:20260105T230000Z
        SUMMARY;LANGUAGE=de:Restmüll blauer Aufkleber am 06.01.2026
        BEGIN:VALARM
        ACTION:DISPLAY
        SUMMARY:ABFUHRTERMIN
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICS.parse(ics, calendar: calendar)
        XCTAssertEqual(events.map(\.summary), ["Restmüll blauer Aufkleber am 06.01.2026"])
        XCTAssertEqual(events.first?.date, day(2026, 1, 6), "23:00 UTC ist der Folgetag in Deutschland")
    }

    /// Eilenburg (Outlook-Export): die Feiertagsverschiebung ist eine Ausnahme ohne SUMMARY und erbt den Serientitel.
    func testRecurrenceOverrideWithoutTitleKeepsSeriesTitle() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260402
        RRULE:FREQ=WEEKLY;COUNT=3;INTERVAL=1
        SUMMARY;LANGUAGE=de:Restabfallentsorgung - EB Berg
        UID:A
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20260410
        RECURRENCE-ID;VALUE=DATE:20260409
        UID:A
        END:VEVENT
        END:VCALENDAR
        """
        let events = SachsenPortalsProvider.parseICS(ics, calendar: calendar)
        XCTAssertEqual(events.map(\.date), [day(2026, 4, 2), day(2026, 4, 10), day(2026, 4, 16)])
        XCTAssertEqual(Set(events.map(\.summary)), ["Restabfallentsorgung - EB Berg"])
    }

    func testEilenburgCalendarsAndNames() {
        let html = #"<a class="link_dokument" data-extension="ICS" href="https://www.eilenburg.de/downloads/datei/abc&amp;x=1" title="t"><span>Restmüll und Papier</span> - EB Berg</a>"#
            + #"<a data-extension="PDF" href="x.pdf">Abfallkalender</a>"#
        XCTAssertEqual(NRWPortalsProvider.eilenburgCalendars(html).map(\.text), ["Restmüll und Papier - EB Berg"])
        XCTAssertEqual(NRWPortalsProvider.eilenburgCalendars(html).first?.url, "https://www.eilenburg.de/downloads/datei/abc&x=1")
        XCTAssertEqual(NRWPortalsProvider.eilenburgName("Restabfallentsorgung - EB Ortsteile/ Dörfer").name, "Restabfallentsorgung")
        XCTAssertEqual(NRWPortalsProvider.eilenburgName("Entsorgung gelber Sack - EB 5").name, "Gelber Sack")
        let mobile = NRWPortalsProvider.eilenburgName("Schadstoffmobil: 08:00 Uhr - 11:30 Uhr")
        XCTAssertEqual(mobile.name, "Schadstoffmobil")
        XCTAssertEqual(mobile.note, "08:00 Uhr - 11:30 Uhr")
    }

    func testWeimarDistrictsFilterTheSharedCalendar() {
        let html = "<p>Allna</p><p>RM 4 P 4 GT 1 Bio 4</p><p>Argenstein RM 3 P 2 GT 3 Bio 3</p>"
        let districts = NRWPortalsProvider.weimarDistricts(html)
        XCTAssertEqual(districts.map(\.title), ["Allna", "Argenstein"])
        XCTAssertEqual(districts.first?.id, "RM 4|P 4|GT 1|Bio 4")
        let events = [ICSEvent(summary: "RM 4", date: day(2026, 11, 12), location: nil), ICSEvent(summary: "RM 3", date: day(2026, 11, 13), location: nil),
                      ICSEvent(summary: "GT 1", date: day(2026, 11, 14), location: nil), ICSEvent(summary: "**Recycling", date: day(2026, 11, 15), location: nil)]
        let pickups = NRWPortalsProvider.weimarPickups(events, codes: ["RM 4", "P 4", "GT 1", "Bio 4"])
        XCTAssertEqual(pickups.map(\.name), ["Restmüll", "Gelbe Tonne"])
    }

    func testMuellappOptionsDistinguishAddressesAndSections() {
        let html = ##"<a href="#areas" class="select-address" data-ic-get-from="https://app.muellapp.com/web-reminder/areas/186669" data-ic-target="#areas" data-value="186669" data-name="Ahornstr.">"##
            + ##"<a href="#addresses-2" data-ic-get-from="https://app.muellapp.com/web-reminder/addresses/9184136/186715" data-value="186715" data-name="Einsteinstr.">"##
        XCTAssertEqual(NRWPortalsProvider.muellappOptions(html).map(\.id), ["a:186669", "p:186715"])
    }

    func testHeilbronnUsesOnlyTheFieldsOfTheAddress() {
        let districts: [String: Any] = ["district": "KH", "city": ["label": "Kirchhausen"], "residual": "KH", "bio": "KH", "yellow": "X", "paper": "X", "green": "KH"]
        let dates: [String: Any] = [
            "KH": ["residual_2": ["1": "2026-11-12"], "residual_4": ["2": "2026-11-13"], "bio_1": ["3": "2026-11-14"], "light-packaging": ["4": "2026-11-15"]],
            "X": ["light-packaging": ["5": "2026-11-16"], "paper": ["6": "2026-11-17"], "residual_2": ["7": "2026-11-18"]],
        ]
        let pickups = NRWPortalsProvider.heilbronnPickups(districts: districts, dates: dates, calendar: calendar).sorted { $0.date < $1.date }
        XCTAssertEqual(pickups.map(\.name), ["Restmüll", "Biotonne", "Gelbe Tonne", "Blaue Tonne"],
                       "residual_4 zeigt die Stadt nicht; Restmüll kommt nur aus dem Restmüll-Bezirk, Gelb nur aus dem Gelb-Bezirk")
    }

    func testErlenseeAndFrankenbergHelpers() {
        XCTAssertEqual(NRWPortalsProvider.erlenseeName("Restmüll (Altenburgstraße)", street: "Altenburgstraße"), "Restmüll")
        XCTAssertEqual(NRWPortalsProvider.erlenseeName("Restmüll (MT)", street: "Altenburgstraße"), "Restmüll (MT)")
        let script = "f.ak_ortsteil.options[0].text = 'Bitte wählen';f.ak_ortsteil.length = 2;f.ak_ortsteil.options[1].value = '1-1'; f.ak_ortsteil.options[1].text = 'FKB-Kernstadt';f.ak_ortsteil.length = 3;f.ak_ortsteil.options[2].value = '2-0'; f.ak_ortsteil.options[2].text = 'Dörnholzhausen';"
        XCTAssertEqual(NRWPortalsProvider.frankenbergOptions(script, field: "ak_ortsteil").map(\.id), ["1-1", "2-0"])
        let streets = "f.ak_strasse.options[1].value = '1'; f.ak_strasse.options[1].text = 'Adalbert-Stifter-Straße';"
        XCTAssertEqual(NRWPortalsProvider.frankenbergOptions(streets, field: "ak_strasse").map(\.title), ["Adalbert-Stifter-Straße"])
    }

    func testWismarSegmentsAndRules() {
        let text = "An der Fischerklause Restmüll Tonne Freitag, ungerade Woche Gelbe Tonne / Gelbe Säcke Donnerstag, gerade Woche Fragen rund um die gelbe Tonne beantwortet Ihnen Veolia Telefon: 03841 71030 Papier-Tonne Montag, gerade Woche Bio-Tonne Mittwoch Von März bis November erfolgt eine wöchentliche Leerung."
        let segments = NRWPortalsProvider.wismarSegments(text)
        XCTAssertEqual(segments, ["Restmüll": "Freitag, ungerade Woche", "Gelbe Tonne": "Donnerstag, gerade Woche", "Papiertonne": "Montag, gerade Woche", "Biotonne": "Mittwoch"])
        XCTAssertFalse(NRWPortalsProvider.wismarNeedsNumber(segments))
        typealias R = NRWPortalsProvider.WismarRule
        XCTAssertEqual(NRWPortalsProvider.wismarRules("Freitag, ungerade Woche", number: nil), [R(weekday: 6, parity: 1)])
        // Lübsche Straße: Bereich und Hausnummer-Parität entscheiden
        let rest = "Montag wöchentlich Nr. 158-218 und 163-221, Dienstag wöchentlich Nr. 87-161 und 106-154, Freitag wöchentlich Nr. 1-85 und 2-104 (gerade Hausnummer - gerade Kalenderwoche, ungerade Hausnummer - ungerade Kalenderwoche)"
        XCTAssertEqual(NRWPortalsProvider.wismarRules(rest, number: 90), [R(weekday: 6, parity: 0)])
        XCTAssertEqual(NRWPortalsProvider.wismarRules(rest, number: 163), [R(weekday: 2, parity: 1)])
        XCTAssertNil(NRWPortalsProvider.wismarRules(rest, number: nil), "ohne Hausnummer nicht entscheidbar")
        let paper = "Mittwoch gerade Woche Nr. 1-85 und 2-104, ungerade Woche Nr. 87-221 und 106-218"
        XCTAssertEqual(NRWPortalsProvider.wismarRules(paper, number: 90), [R(weekday: 4, parity: 0)])
        XCTAssertEqual(NRWPortalsProvider.wismarRules(paper, number: 120), [R(weekday: 4, parity: 1)])
        XCTAssertEqual(NRWPortalsProvider.wismarRules("Nr. 7-9: Dienstag, ungerade Woche alle anderen Hausnummern: Dienstag wöchentlich", number: 8), [R(weekday: 3, parity: 1)])
        XCTAssertEqual(NRWPortalsProvider.wismarRules("Nr. 7-9: Dienstag, ungerade Woche alle anderen Hausnummern: Dienstag wöchentlich", number: 20), [R(weekday: 3, parity: nil)])
        XCTAssertEqual(NRWPortalsProvider.wismarRules("Montag wöchentlich ungerade Hausnummern, Mittwoch wöchentlich gerade Hausnummern", number: 4), [R(weekday: 4, parity: nil)])
        XCTAssertNil(NRWPortalsProvider.wismarRules("Dienstag, wöchentlich Gewerbe", number: nil), "Papier nur für Gewerbe")
    }

    func testWismarDatesAndHolidayShifts() {
        // KW 46/2026: Mo 9.11.–So 15.11. (gerade), KW 49 beginnt am 30.11.
        let fridays = NRWPortalsProvider.wismarDates([.init(weekday: 6, parity: 0)], bio: false, from: day(2026, 11, 9), to: day(2026, 11, 29), calendar: calendar)
        XCTAssertEqual(fridays, [day(2026, 11, 13), day(2026, 11, 27)])
        let bio = NRWPortalsProvider.wismarDates([.init(weekday: 4, parity: nil)], bio: true, from: day(2026, 11, 23), to: day(2026, 12, 13), calendar: calendar)
        XCTAssertEqual(bio, [day(2026, 11, 25), day(2026, 12, 9)], "ab Dezember nur gerade KW: 2.12. liegt in KW 49, 9.12. in KW 50")
        let html = "<tr><td>01.01.2026</td><td style=\"x\">02.01.2026</td><td>02.01.2026</td></tr><tr><td>02.01.2026</td><td> bleibt </td><td>03.01.2026</td></tr>"
        let shifts = NRWPortalsProvider.wismarShifts(html, calendar: calendar)
        XCTAssertEqual(shifts[day(2026, 1, 1)]?.0, day(2026, 1, 2))
        XCTAssertNil(shifts[day(2026, 1, 2)]?.0)
        XCTAssertEqual(shifts[day(2026, 1, 2)]?.1, day(2026, 1, 3))
    }

    func testGoettingenStreetsAndNames() {
        let html = #"<script> const strassen = JSON.parse("{\"146809\":\"Abich-Thiele-Stra\\u00dfe\",\"45741\":\"Albrechtstr.\"}"); const strassenMap = new Map();"#
        XCTAssertEqual(NRWPortalsProvider.goettingenStreets(html).map(\.id).sorted(), ["Abich-Thiele-Straße", "Albrechtstr."])
        XCTAssertEqual(NRWPortalsProvider.goettingenName("[GEB] Abfuhr der Restmülltonne"), "Restmülltonne")
        XCTAssertEqual(NRWPortalsProvider.goettingenName("[GEB] Abfuhr des gelben Sacks"), "Gelber Sack")
    }

    func testWetzlarLocationsAndDurthRoosPage() {
        let html = #"<datalist id="sp_garbagecalendar_location--list"><option value="Abelsgasse (Wetzlar)" >Abelsgasse (Wetzlar)</option><option value="Altenberger Straße ab Nr. 40/65 (Wetzlar)" >x</option></datalist><option value="fremd">"#
        XCTAssertEqual(NRWPortalsProvider.wetzlarLocations(html).map(\.id), ["Abelsgasse (Wetzlar)", "Altenberger Straße ab Nr. 40/65 (Wetzlar)"])
        XCTAssertEqual(NRWPortalsProvider.durthRoosPage("https://stadtreinigung.giessen.de/akal/akal1.php", "Z"), "https://stadtreinigung.giessen.de/akal/akal1.php?von=Z&bis=[")
        XCTAssertEqual(NRWPortalsProvider.hertenPage("A"), "https://abfallkalender.durth-roos.de/herten/index.php?von=A&bis=B")
        let picks = ["Alicen", "Alicenstraße", "20"].map { SelectionOption(id: $0, title: $0) }
        XCTAssertEqual(NRWPortalsProvider(service: "giessen").label(for: picks), "Gießen, Alicenstraße 20")
    }

    func testHuerthOptionsAndSignedLinks() {
        let page = """
        <select aria-label="Ort/Bezirk" data-url="/muellkalender?tx_swhtonnenalarm_pi1%5Baction%5D=streets&amp;type=1311&amp;cHash=0f" class="form-select" id="selectDistrict" name="tx_swhtonnenalarm_pi1[district]">
        <option value="">
        </option><option value="Alt-H&uuml;rth">Alt-H&uuml;rth</option><option value="Efferen">Efferen</option></select>
        <input id="currentCalendarPage" type="hidden" name="" value="/muellkalender?tx_swhtonnenalarm_pi1%5Baction%5D=calendarPage&amp;type=1311&amp;cHash=0b" />
        """
        XCTAssertEqual(NRWPortalsProvider.huerthOptions(page, select: "selectDistrict").map(\.id), ["Alt-Hürth", "Efferen"])
        XCTAssertEqual(NRWPortalsProvider.huerthLink(page, containing: "action%5D=streets"), "/muellkalender?tx_swhtonnenalarm_pi1%5Baction%5D=streets&type=1311&cHash=0f")
        XCTAssertEqual(NRWPortalsProvider.huerthLink(page, containing: "action%5D=calendarPage"), "/muellkalender?tx_swhtonnenalarm_pi1%5Baction%5D=calendarPage&type=1311&cHash=0b")
        XCTAssertNil(NRWPortalsProvider.huerthLink(page, containing: "action%5D=calendarFile"))
        let streets = #"<select class="form-select" id="selectStreet" name="tx_swhtonnenalarm_pi1[street]"><option selected="selected" value="" /><option value="3">Adolf-Dasbach-Weg</option></select>"#
        XCTAssertEqual(NRWPortalsProvider.huerthOptions(streets, select: "selectStreet").map { "\($0.id)|\($0.title)" }, ["3|Adolf-Dasbach-Weg"])
    }

    /// Seitenausschnitte vom 11.11.2026 (afze.de, waldeck-stadt.de, knittel-entsorgung.com, 123abfallkalender.de, brachttal.de).
    func testEppelbornWaldeckKnittelEbsdorfergrundBrachttalParsing() {
        let afze = #"<a href="abfuhrkalender/articles/bubach.html">Bubach</a> <a href="abfuhrkalender/articles/bubach.html">Weiterlesen … Bubach</a> <a href="abfuhrkalender/articles/calm.html"><span>Calmesweiler / Macherbach</span></a>"#
        XCTAssertEqual(NRWPortalsProvider.eppelbornDistricts(afze).map { "\($0.id)|\($0.title)" },
                       ["abfuhrkalender/articles/bubach.html|Bubach", "abfuhrkalender/articles/calm.html|Calmesweiler / Macherbach"])
        XCTAssertEqual(NRWPortalsProvider.eppelbornName("Papier (Rest vom 8. Mai)").name, "Papier")
        XCTAssertEqual(NRWPortalsProvider.eppelbornName("Papier (Rest vom 8. Mai)").note, "Rest vom 8. Mai")
        XCTAssertEqual(NRWPortalsProvider.eppelbornName("Papier (2)").name, "Papier (2)")
        XCTAssertEqual(NRWPortalsProvider.eppelbornName("gelbe Säcke").name, "Gelbe Säcke")
        XCTAssertNil(NRWPortalsProvider.eppelbornName("Ökomobil").note)

        let waldeck = "var cities = [\n {\n 'label': \"Alraft\",\n 'value': \"3\"\n },\n {\n 'label': \"Nieder-Werbe u. Scheid\",\n 'value': \"8\"\n }\n ];\nvar streets = [];"
        XCTAssertEqual(NRWPortalsProvider.waldeckOptions(waldeck, list: "cities").map { "\($0.id)|\($0.title)" }, ["3|Alraft", "8|Nieder-Werbe u. Scheid"])
        XCTAssertEqual(NRWPortalsProvider.waldeckOptions(waldeck, list: "streets").count, 0)

        let knittel = #"et_link_options_data = [{"url":"https:\/\/www.knittel-entsorgung.com\/wp-content\/uploads\/2025\/11\/ELCHINGEN_Thalfingen_2026.ics"},{"url":"https:\/\/www.knittel-entsorgung.com\/wp-content\/uploads\/2025\/11\/NERSINGEN_Nersingen_Leibi_2026.ics"}] <a href="https://www.knittel-entsorgung.com/wp-content/uploads/2025/11/ELCHINGEN_Thalfingen_2026.ics">x</a>"#
        let files = NRWPortalsProvider.knittelFiles(knittel, prefix: "ELCHINGEN_")
        XCTAssertEqual(files.map(\.area), ["Thalfingen"])
        XCTAssertEqual(files.first?.url, "https://www.knittel-entsorgung.com/wp-content/uploads/2025/11/ELCHINGEN_Thalfingen_2026.ics")
        XCTAssertEqual(NRWPortalsProvider.knittelFiles(knittel, prefix: "NERSINGEN_").map(\.area), ["Nersingen_Leibi"])

        let ebs = #"<a href="https://www.123abfallkalender.de/abfallkalender/rpecasvg-ebsdorfergrund/9-molln" class="x"> Mölln </a><a href="https://www.123abfallkalender.de/document/udbubvcl/impressum">Impressum</a>"#
        XCTAssertEqual(NRWPortalsProvider.ebsdorfergrundDistricts(ebs).map { "\($0.id)|\($0.title)" },
                       ["https://www.123abfallkalender.de/abfallkalender/rpecasvg-ebsdorfergrund/9-molln|Mölln"])

        let brachttal = #"&quot;url&quot;:&quot;//www.brachttal.de/rathaus-buergerschaft/gemeindeverwaltung/pdf-dateien-gemeindeverwaltung/muellkalender/muellkalender-hellstein-2026.ics&quot;"#
        let brFiles = NRWPortalsProvider.brachttalFiles(brachttal)
        XCTAssertEqual(brFiles.map { "\($0.area)|\($0.year)" }, ["hellstein|2026"])
        XCTAssertEqual(brFiles.first?.url, "https://www.brachttal.de/rathaus-buergerschaft/gemeindeverwaltung/pdf-dateien-gemeindeverwaltung/muellkalender/muellkalender-hellstein-2026.ics")
        XCTAssertFalse(NRWPortalsProvider.brachttalIsPickup("Fälligkeit Grundbesitzabgaben"))
        XCTAssertFalse(NRWPortalsProvider.brachttalIsPickup("Sperrmüll Anmeldeschluss"))
        XCTAssertTrue(NRWPortalsProvider.brachttalIsPickup("Restmüll"))
    }

    func testLiveEinzelportale() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        L10n.forcedLanguage = "de"
        let cases: [(key: String, inputs: [String])] = [
            ("eilenburg", ["EB Berg", "EB 3"]), ("weimar_lahn", ["Allna"]), ("ottobrunn", ["Ahornstr."]),
            ("ottobrunn", ["Einsteinstr.", "1-16 nördl. Rob.-Koch-Str."]), ("ismaning", ["Adalperostraße"]), ("ismaning", ["Am Hang", "1"]),
            ("heilbronn", ["Aachener Straße"]), ("heilbronn", ["Carl-Zeiss-Straße", "2"]), ("erlensee", ["Altenburgstraße"]),
            ("frankenberg", ["Dörnholzhausen"]), ("frankenberg", ["FKB-Kernstadt", "Adalbert-Stifter-Straße"]),
            ("wismar", ["An der Fischerklause"]), ("wismar", ["Lübsche Straße", "90"]),
            ("goettingen", ["Albrechtstr.", "1"]), ("giessen", ["Alicen", "Alicenstraße", "20"]), ("wetzlar", ["Abelsgasse (Wetzlar)"]),
            ("wetzlar", ["Alte Straße (Steindorf)"]), ("huerth", ["Alt-Hürth", "Adolf-Dasbach-Weg"]), ("huerth", ["Efferen", "Bachstraße"]),
            ("eppelborn", ["Bubach"]), ("eppelborn", ["Wiesbach Süd"]), ("waldeck", ["Waldeck", "Abelauf"]), ("waldeck", ["Alraft", "Am Kirchpfad"]),
            ("elchingen", ["Thalfingen"]), ("nersingen", []), ("ebsdorfergrund", ["Ebsdorf"]), ("ebsdorfergrund", ["Mölln"]),
            ("brachttal", ["Hellstein"]), ("brachttal", ["Udenhain"]),
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
            let extra = try await provider.nextStep(after: selections)
            XCTAssertNil(extra, "\(key): nach \(inputs) kommt noch ein Schritt")
            let pickups = try await provider.pickups(for: selections, calendar: .current).filter { $0.date >= today }
            print("LIVE|\(key)|\(provider.label(for: selections))|termine=\(pickups.count)|\(Set(pickups.map(\.name)).sorted().joined(separator: ","))|erster=\(pickups.first.map { "\($0.date)" } ?? "-")")
            XCTAssertGreaterThan(pickups.count, 3, key)
        }
    }
}

// MARK: - Jahresgrenzen, Altdateien und nicht auswertbare Serien (Prüfrunde 11.11.2026)

extension EinzelportaleTests {
    private static func ics(_ events: [(String, String)]) -> String {
        "BEGIN:VCALENDAR\n" + events.map { "BEGIN:VEVENT\nUID:\($0.0)-\($0.1)\nDTSTART;VALUE=DATE:\($0.0)\nSUMMARY:\($0.1)\nEND:VEVENT\n" }.joined() + "END:VCALENDAR\n"
    }

    private func provider(_ key: String, on date: Date, pages: [String: String]) -> NRWPortalsProvider {
        var provider = NRWPortalsProvider(service: key, client: HTTPClient(session: EinzelStub.session(pages)))
        provider.referenceDate = date
        return provider
    }

    /// Brachttal: Eine Vorjahresdatei, die nicht mehr abrufbar ist, darf den Ortsteil nicht lahmlegen; das laufende Jahr ist Pflicht.
    func testBrachttalSkipsOldYearFiles() async throws {
        let base = "https://www.brachttal.de/m/muellkalender-hellstein-"
        let page = #"&quot;url&quot;:&quot;//www.brachttal.de/m/muellkalender-hellstein-2025.ics&quot; &quot;url&quot;:&quot;//www.brachttal.de/m/muellkalender-hellstein-2026.ics&quot;"#
        let pageURL = "https://www.brachttal.de/rathaus-buergerschaft/gemeindeverwaltung/abfallentsorgung/"
        let selection = [SelectionOption(id: "hellstein", title: "Hellstein")]
        let pickups = try await provider("brachttal", on: day(2026, 11, 11), pages: [pageURL: page, base + "2026.ics": Self.ics([("20261120", "Restmüll")])])
            .pickups(for: selection, calendar: calendar)
        XCTAssertEqual(pickups.map(\.date), [day(2026, 11, 20)])
        XCTAssertFalse(EinzelStub.requested().contains(base + "2025.ics"), "Altjahr wird gar nicht erst geladen")
        // Gegenprobe: Fällt die Datei des laufenden Jahres aus, ist das ein Fehler, kein leerer Kalender
        do {
            _ = try await provider("brachttal", on: day(2026, 11, 11), pages: [pageURL: page]).pickups(for: selection, calendar: calendar)
            XCTFail("Ausfall des laufenden Jahres darf nicht als Erfolg durchgehen")
        } catch {}
        // Im Dezember darf die Datei des Folgejahres noch fehlen
        let december = try await provider("brachttal", on: day(2026, 12, 2), pages: [pageURL: page + #" &quot;url&quot;:&quot;//www.brachttal.de/m/muellkalender-hellstein-2027.ics&quot;"#,
                                                                                      base + "2026.ics": Self.ics([("20261214", "Restmüll")])])
            .pickups(for: selection, calendar: calendar)
        XCTAssertEqual(december.map(\.date), [day(2026, 12, 14)])
    }

    /// Knittel: Verlinkt die Jahresseite auch die Altjahresdatei, gilt die des angefragten Jahres; Folgejahr im Dezember darf fehlen.
    func testKnittelUsesFileOfRequestedYear() async throws {
        let up = "https://www.knittel-entsorgung.com/wp-content/uploads/"
        let page = #"<a href="\#(up)2024/11/ELCHINGEN_Thalfingen_2025.ics">alt</a> <a href="\#(up)2025/11/ELCHINGEN_Thalfingen_2026.ics">neu</a> <a href="\#(up)2025/11/ELCHINGEN_Unterelchingen_2026.ics">x</a>"#
        let pages = ["https://www.knittel-entsorgung.com/abfuhrkalender-2026/": page,
                     up + "2024/11/ELCHINGEN_Thalfingen_2025.ics": Self.ics([("20250110", "Restmüll")]),
                     up + "2025/11/ELCHINGEN_Thalfingen_2026.ics": Self.ics([("20261210", "Restmüll")])]
        let selection = [SelectionOption(id: "Thalfingen", title: "Thalfingen")]
        let pickups = try await provider("elchingen", on: day(2026, 12, 1), pages: pages).pickups(for: selection, calendar: calendar)
        XCTAssertEqual(pickups.map(\.date), [day(2026, 12, 10)])
        let step = try await provider("elchingen", on: day(2026, 11, 1), pages: pages).nextStep(after: [])
        XCTAssertEqual(step?.options.map(\.id), ["Thalfingen", "Unterelchingen"])
    }

    /// Das Abrufjahr folgt der deutschen Uhr, nicht der Zeitzone des Geräts: 31.12. 23:30 UTC ist in Deutschland schon der 1. Januar.
    func testEinzelYearFollowsGermanClock() async throws {
        let saved = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
        defer { NSTimeZone.default = saved }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let newYear = utc.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 30))!
        let up = "https://www.knittel-entsorgung.com/wp-content/uploads/"
        let pages = ["https://www.knittel-entsorgung.com/abfuhrkalender-2027/": #"<a href="\#(up)2026/11/NERSINGEN_Nersingen_2027.ics">x</a>"#,
                     up + "2026/11/NERSINGEN_Nersingen_2027.ics": Self.ics([("20270105", "Restmüll")])]
        let pickups = try await provider("nersingen", on: newYear, pages: pages).pickups(for: [], calendar: calendar)
        XCTAssertEqual(pickups.map(\.date), [day(2027, 1, 5)])
    }

    /// Eppelborn: Eine Serienregel, die der Parser nicht auswerten kann, meldet einen Fehler statt still nur den ersten Termin zu zeigen.
    func testEppelbornRejectsUnsupportedRecurrence() {
        let weekly = "BEGIN:VEVENT\nUID:a\nDTSTART;VALUE=DATE:20260105\nRRULE:FREQ=WEEKLY;INTERVAL=2;UNTIL=20261231;BYDAY=MO\nSUMMARY:Restmüll\nEND:VEVENT\n"
        XCTAssertTrue(NRWPortalsProvider.eppelbornUnsupportedRules(weekly, calendar: calendar, today: day(2026, 11, 11)).isEmpty)
        XCTAssertTrue(NRWPortalsProvider.eppelbornUnsupportedRules("BEGIN:VEVENT\nDTSTART;VALUE=DATE:20260105\nSUMMARY:Papier\nEND:VEVENT\n", calendar: calendar, today: day(2026, 11, 11)).isEmpty)
        for rule in ["FREQ=MONTHLY;BYMONTHDAY=5;UNTIL=20261231", "FREQ=WEEKLY;BYDAY=MO,TH;UNTIL=20261231", "FREQ=WEEKLY;BYDAY=TU;UNTIL=20261231",
                     "FREQ=WEEKLY;BYMONTH=1,2"] {
            let block = "BEGIN:VEVENT\nUID:b\nDTSTART;VALUE=DATE:20260105\nRRULE:\(rule)\nSUMMARY:Bio\nEND:VEVENT\n"
            XCTAssertEqual(NRWPortalsProvider.eppelbornUnsupportedRules(block, calendar: calendar, today: day(2026, 11, 11)), [rule], rule)
        }
        // Serie ohne Ende, die vor über zwei Jahren begann: der Grundparser bricht nach zwei Jahren ab
        let old = "BEGIN:VEVENT\nDTSTART;VALUE=DATE:20230102\nRRULE:FREQ=WEEKLY\nSUMMARY:Bio\nEND:VEVENT\n"
        XCTAssertEqual(NRWPortalsProvider.eppelbornUnsupportedRules(old, calendar: calendar, today: day(2026, 11, 11)), ["FREQ=WEEKLY"])
        let fresh = "BEGIN:VEVENT\nDTSTART;VALUE=DATE:20260102\nRRULE:FREQ=WEEKLY\nSUMMARY:Bio\nEND:VEVENT\n"
        XCTAssertTrue(NRWPortalsProvider.eppelbornUnsupportedRules(fresh, calendar: calendar, today: day(2026, 11, 11)).isEmpty)
    }

    /// Abgesagte Termine (STATUS:CANCELLED) sind keine Abfuhr – auch nicht als abgesagter Einzeltermin einer Serie.
    func testCancelledEventsAreDropped() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:serie
        DTSTART;VALUE=DATE:20260105
        RRULE:FREQ=WEEKLY;COUNT=3
        SUMMARY:Restmüll
        END:VEVENT
        BEGIN:VEVENT
        UID:serie
        RECURRENCE-ID;VALUE=DATE:20260112
        DTSTART;VALUE=DATE:20260112
        STATUS:CANCELLED
        SUMMARY:Restmüll
        END:VEVENT
        BEGIN:VEVENT
        UID:einzeln
        DTSTART;VALUE=DATE:20260107
        STATUS:CANCELLED
        SUMMARY:Papier
        END:VEVENT
        BEGIN:VEVENT
        UID:bestaetigt
        DTSTART;VALUE=DATE:20260108
        STATUS:CONFIRMED
        SUMMARY:Bio
        END:VEVENT
        END:VCALENDAR
        """
        XCTAssertEqual(SachsenPortalsProvider.parseICS(ics, calendar: calendar).map { "\(Days.iso($0.date, calendar: calendar))|\($0.summary)" },
                       ["2026-01-05|Restmüll", "2026-01-08|Bio", "2026-01-19|Restmüll"])
        XCTAssertEqual(ICS.parse(ics, calendar: calendar).filter { $0.summary == "Papier" }.count, 0)
    }
}

/// Liefert feste Seiten je Adresse; alle anderen Adressen scheitern wie bei einem Netzwerkfehler.
final class EinzelStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pages: [String: String] = [:]
    nonisolated(unsafe) private static var seen: [String] = []

    static func session(_ pages: [String: String]) -> URLSession {
        lock.lock(); Self.pages = pages; seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EinzelStub.self]
        return URLSession(configuration: config)
    }

    static func requested() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        Self.lock.lock(); Self.seen.append(url); let body = Self.pages[url]; Self.lock.unlock()
        guard let body else { client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
