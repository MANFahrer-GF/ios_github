import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// Müllmann-App (Landkreis Konstanz, Karlsruhe), ZVA Werra-Meißner, Kelkheim und Flörsheim.
/// Parser-Tests und ganze Abläufe mit echten, gekürzten Antworten der Portale (Oktober 2026);
/// Live-Tests nur mit TONNE_LIVE=1.
final class SuedwestNeueBetreiberTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func names(_ pickups: [Pickup]) -> [String] { pickups.map { "\(Days.iso($0.date)) \($0.name)" } }

    // MARK: Müllmann

    static let mmRegions = #"""
    [{"key":"aach","name":"Aach","years":[2026],"infoUrl":"https://www.aach.de/de/Aktuelles/Abfallkalender"},
     {"key":"konstanz","name":"Konstanz","years":[2026],"streets":true,"holidays":true,"state":"BW"},
     {"key":"karlsruhe","name":"Karlsruhe","years":[2026],"streets":true,"numbers":true,"holidays":true,"state":"bw"}]
    """#
    static let mmStreets = #"""
    [{"key":"abendbergweg","name":"Abendbergweg"},{"key":"alter_wall","name":"Alter Wall","hasRanges":2},{"key":"adenauerstr","name":"Adenauerstr."}]
    """#
    static let mmAbendbergweg = #"""
    {"key":"abendbergweg","name":"Abendbergweg","ranges":[{"selector":"*","districts":["bio_1_2026","rest_5_2026","gelb_3_2026","papier_15_2026","christ_22_2026","pollutant_2026"],"plz":"78465"}],"year":2026}
    """#
    static let mmAlterWall = #"""
    {"key":"alter_wall","name":"Alter Wall","ranges":[{"selector":"1_9und2_8","name":"1–9 und 2–8","info":"von Theodor-Heuss-Str. bis Mainaustr.","districts":["bio_4_2026"],"plz":"78467"},{"selector":"11_21und10_20","name":"11–21 und 10–20","info":"von Eisenbahnstr. bis Theodor-Heuss-Str.","districts":["bio_2_2026"],"plz":"78467"}],"year":2026}
    """#
    static let mmTypes = #"""
    [{"key":"bio","name":"Biomüll","useInfo":true,"color":"009242","icon":"bin","class":"regular","aliases":[]},
     {"key":"rest","name":"Restmüll","useInfo":true,"color":"993365","icon":"bin","class":"regular","aliases":[]},
     {"key":"gelb","name":"Gelber Sack","color":"FBDA0B","icon":"bag","class":"regular","aliases":[]},
     {"key":"papier","name":"Papier","color":"001DFF","icon":"bin","class":"regular","aliases":[]},
     {"key":"pollutant_dorfweiher","name":"Problemstoffe Dorfweiher","useLocation":true,"location":"Litzelstetter Str. 150, Dorfweiher","icon":"tank","class":"regular","aliases":[]}]
    """#
    static let mmEvents = #"""
    [{"type":"bio","date":"12.10.2026","info":"jeden Montag"},{"type":"gelb","date":"14.10.2026"},
     {"type":"rest","date":"19.10.2026","info":"alle 2 Wochen montags"},{"type":"papier","date":"23.10.2026"},
     {"type":"pollutant_dorfweiher","date":"10.11.2026","info":"Wertstoffhof Dorfweiher, Litzelstetter Str. 150 (9:45 bis 11:45)","start":"9:45","end":"11:45"},
     {"type":"unbekannt","date":"11.11.2026"},{"type":"bio","date":"kaputt"}]
    """#

    func testMuellmannPickups() {
        let pickups = SuedwestPortalsProvider.muellmannPickups(events: Data(Self.mmEvents.utf8), types: Data(Self.mmTypes.utf8), calendar: calendar)
        XCTAssertEqual(names(pickups), ["2026-10-12 Biomüll", "2026-10-14 Gelber Sack", "2026-10-19 Restmüll", "2026-10-23 Papier", "2026-11-10 Problemstoffe Dorfweiher"],
                       "unbekannte Abfallart und kaputtes Datum fallen weg")
        XCTAssertEqual(pickups.map { WasteCategory.classify($0.name) }, [.organic, .packaging, .residual, .paper, .hazardous])
    }

    func testMuellmannFlowWithStreetRanges() async throws {
        let provider = SuedwestPortalsProvider(service: "muellmann", client: HTTPClient(session: PortalStub.session(Self.muellmannRoute)))
        let regions = try await provider.nextStep(after: [])
        XCTAssertEqual(regions?.options.map(\.title), ["Aach", "Karlsruhe", "Konstanz"])
        let konstanz = try XCTUnwrap(regions?.options.first { $0.id == "konstanz" })
        let streets = try await provider.nextStep(after: [konstanz])
        let wall = try XCTUnwrap(streets?.options.first { $0.title == "Alter Wall" })
        let ranges = try await provider.nextStep(after: [konstanz, wall])
        XCTAssertEqual(ranges?.options.map(\.title), ["1–9 und 2–8", "11–21 und 10–20"])
        XCTAssertEqual(ranges?.options.first?.subtitle, "von Theodor-Heuss-Str. bis Mainaustr.")
        let range = try XCTUnwrap(ranges?.options.first)
        let done = try await provider.nextStep(after: [konstanz, wall, range])
        XCTAssertNil(done)
        let pickups = try await provider.pickups(for: [konstanz, wall, range], calendar: calendar)
        XCTAssertEqual(pickups.count, 5)
        XCTAssertEqual(provider.label(for: [konstanz, wall, range]), "Konstanz, Alter Wall 1–9 und 2–8")

        let requests = PortalStub.requests()
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-API-Key"] == "fz2LM67Xurs1sXjmHEIAlhssIS1mBlf8" })
        XCTAssertTrue(requests.contains { $0.url == "https://muellmann.gering.dev/konstanz/events/alter_wall/1_9und2_8" }, "\(requests.map(\.url))")
        XCTAssertTrue(requests.contains { $0.url == "https://muellmann.gering.dev/konstanz/types" })
    }

    func testMuellmannStreetWithoutRanges() async throws {
        let provider = SuedwestPortalsProvider(service: "muellmann", client: HTTPClient(session: PortalStub.session(Self.muellmannRoute)))
        let konstanz = SelectionOption(id: "konstanz", title: "Konstanz")
        let street = SelectionOption(id: "abendbergweg", title: "Abendbergweg")
        let next = try await provider.nextStep(after: [konstanz, street])
        XCTAssertNil(next, "nur ein Abschnitt – keine weitere Auswahl")
        _ = try await provider.pickups(for: [konstanz, street], calendar: calendar)
        XCTAssertTrue(PortalStub.requests().contains { $0.url == "https://muellmann.gering.dev/konstanz/events/abendbergweg/*" }, "\(PortalStub.requests().map(\.url))")
    }

    func testMuellmannTownWithoutStreets() async throws {
        let provider = SuedwestPortalsProvider(service: "muellmann", client: HTTPClient(session: PortalStub.session(Self.muellmannRoute)))
        let aach = SelectionOption(id: "aach", title: "Aach")
        let next = try await provider.nextStep(after: [aach])
        XCTAssertNil(next)
        let pickups = try await provider.pickups(for: [aach], calendar: calendar)
        XCTAssertFalse(pickups.isEmpty)
        XCTAssertTrue(PortalStub.requests().contains { $0.url == "https://muellmann.gering.dev/aach/events" })
        XCTAssertEqual(provider.label(for: [aach]), "Aach")
    }

    static func muellmannRoute(_ request: PortalStub.Seen) -> String? {
        guard request.url.hasPrefix("https://muellmann.gering.dev") else { return nil }
        let path = String(request.url.dropFirst("https://muellmann.gering.dev".count))
        switch path {
        case "/": return mmRegions
        case "/aach/streets": return "[]"
        case "/konstanz/streets": return mmStreets
        case "/konstanz/streets/abendbergweg": return mmAbendbergweg
        case "/konstanz/streets/alter_wall": return mmAlterWall
        default: break
        }
        if path.hasSuffix("/types") { return mmTypes }
        if path.contains("/events") { return mmEvents }
        return nil
    }

    // MARK: ZVA Werra-Meißner

    static let zvaCities = #"""
    <form action="https://www.zva-wmk.de/termine/persönlicher-terminkalender-2026" method="get">
    <select name="city" id="calcity" onchange="jsgoto('termine/persönlicher-terminkalender-2026?city='+this.form.city[this.form.city.selectedIndex].value);" class="formfield">
    <option value="">-- Ort auswählen --</option>
    <option value="BAD+SOODEN-ALLENDORF_AHRENBERG" label="Bad Sooden-Allendorf - Ahrenberg">Bad Sooden-Allendorf - Ahrenberg</option>
    <option value="WEHRETAL_REICHENSACHSEN" label="Wehretal - Reichensachsen" selected>Wehretal - Reichensachsen</option>
    <option value="WEI%C3%9FENBORN_RAMBACH" label="Weißenborn - Rambach">Weißenborn - Rambach</option>
    <option value="WEI%C3%9FENBORN_WEI%C3%9FENBORN" label="Weißenborn - Weißenborn">Weißenborn - Weißenborn</option>
    </select>
    <select name="street" id="calstreet" class="formfield">
    <option value="">-- Straße auswählen --</option>
    <option value="AM+BAHNHOF" label="AM BAHNHOF">AM BAHNHOF</option>
    <option value="AM+LEIMBACH" label="AM LEIMBACH">AM LEIMBACH</option>
    <option value="AM+STADTWEG" label="AM STADTWEG">AM STADTWEG</option>
    </select>
    """#
    static let zvaICS = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//ZVA-WMK//NONSGML v1//EN
    METHOD:PUBLISH
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261012
    UID:zvawmk219734
    SUMMARY:Biomüll
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261019
    UID:zvawmk219736
    SUMMARY:Restmüll
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261024
    UID:zvawmk219738
    SUMMARY:Baum- Und Strauchschnitt
    END:VEVENT
    END:VCALENDAR
    """

    func testZvaFlow() async throws {
        let year = 2026
        let page = "https://www.zva-wmk.de/termine/pers%C3%B6nlicher-terminkalender-"
        var provider = SuedwestPortalsProvider(service: "zvawmk", client: HTTPClient(session: PortalStub.session { request in
            guard request.url.hasPrefix(page) else { return nil }
            if request.url.contains("link=ical") {
                // Die Seite des Folgejahres gibt es noch nicht.
                return request.url.hasPrefix("\(page)\(year)?") ? Self.zvaICS : nil
            }
            return Self.zvaCities
        }))
        provider.referenceDate = Days.parse("2026-10-09", calendar: calendar)
        let cities = try await provider.nextStep(after: [])
        XCTAssertEqual(cities?.options.count, 4)
        let city = try XCTUnwrap(cities?.options.first { $0.title == "Wehretal - Reichensachsen" })
        XCTAssertEqual(city.id, "WEHRETAL_REICHENSACHSEN")
        let streets = try await provider.nextStep(after: [city])
        let street = try XCTUnwrap(streets?.options.first)
        XCTAssertEqual(street.title, "Am Bahnhof")
        XCTAssertEqual(street.id, "AM+BAHNHOF")
        let done = try await provider.nextStep(after: [city, street])
        XCTAssertNil(done)

        let pickups = try await provider.pickups(for: [city, street], calendar: calendar)
        XCTAssertEqual(names(pickups), ["2026-10-12 Biomüll", "2026-10-19 Restmüll", "2026-10-24 Baum- und Strauchschnitt"])
        XCTAssertEqual(WasteCategory.classify(pickups[2].name), .green)
        XCTAssertEqual(provider.label(for: [city, street]), "Wehretal – Reichensachsen, Am Bahnhof")
        let weissenborn = SelectionOption(id: "WEI%C3%9FENBORN_WEI%C3%9FENBORN", title: "Weißenborn - Weißenborn")
        XCTAssertEqual(provider.label(for: [weissenborn, street]), "Weißenborn, Am Bahnhof")

        let urls = PortalStub.requests().map(\.url)
        XCTAssertTrue(urls.contains("\(page)\(year)?city=WEHRETAL_REICHENSACHSEN"), "\(urls)")
        XCTAssertTrue(urls.contains("\(page)\(year)?city=WEHRETAL_REICHENSACHSEN&street=AM+BAHNHOF&type=all&link=ical&fullday=1"), "\(urls)")
        XCTAssertTrue(urls.contains("\(page)\(year + 1)?city=WEHRETAL_REICHENSACHSEN&street=AM+BAHNHOF&type=all&link=ical&fullday=1"), "Folgejahr wird versucht")
    }

    // MARK: Kelkheim

    static let kelkheimForm = #"""
    <script>$(function() {
    var availableTags = [
    "Adalbert-Stifter-Straße",
    "Altkönigstraße ",
    "Frankfurter Straße",
    "Zum Gimbacher Hof",
    ];
    $( "#street" ).autocomplete({
    source: availableTags
    });
    });</script>
    """#
    static let kelkheimCalendar = #"""
    <a class="noprint" href="webcal://kelkheim.de/mod_abfallkalender/index.php?action=ical&area=B-5%2C+S-5+Di&amp;datetype=Restmuell%2CBlaue+Tonne%2CBio-Tonne%2CGelber+Sack%2CSondermuell%2CSperrmuell%2CGruenabfuhr%2CRestmuell-Container%2CGruenschnittannahmestelle%2CWertstoffhof%2CSonstige&amp;street=Frankfurter+Stra%DFe&amp;number=10">abonnieren</a> (<a style="cursor: pointer;" title="in Zwischenablage kopieren" onclick="copyToClipboard('https://kelkheim.de/mod_abfallkalender/index.php?action=ical&area=B-5%2C+S-5+Di&amp;datetype=Restmuell%2CBlaue+Tonne%2CBio-Tonne%2CGelber+Sack%2CSondermuell%2CSperrmuell%2CGruenabfuhr%2CRestmuell-Container%2CGruenschnittannahmestelle%2CWertstoffhof%2CSonstige&amp;street=Frankfurter+Stra%DFe&amp;number=10')">
    """#
    static let kelkheimICS = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//ConPresso GmbH//NONSGML v0.1//EN
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261014
    UID:f677148babd8586c7f0ceaa733e52c5e@kelkheim.de
    SUMMARY:Bio-Tonne Bezirk B-5, S-5 Di
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261016
    UID:f57a1c4ddf6179cae9dbbc069dd588b4@kelkheim.de
    SUMMARY:Gelber Sack Bezirk B-5, S-5 Di
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261020
    UID:a1@kelkheim.de
    SUMMARY:Restmuell Bezirk B-5, S-5 Di
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261110
    UID:a2@kelkheim.de
    SUMMARY:Sperrmuell Bezirk B-5, S-5 Di
    END:VEVENT
    END:VCALENDAR
    """

    func testKelkheimParsing() {
        let streets = SuedwestPortalsProvider.kelkheimStreets(Self.kelkheimForm)
        XCTAssertEqual(streets.map(\.title), ["Adalbert-Stifter-Straße", "Altkönigstraße", "Frankfurter Straße", "Zum Gimbacher Hof"])
        XCTAssertEqual(streets[1].id, "Altkönigstraße ", "Schreibweise des Portals bleibt für das Formular erhalten")
        XCTAssertEqual(SuedwestPortalsProvider.kelkheimName("Restmuell Bezirk B-5, S-5 Di"), "Restmüll")
        XCTAssertEqual(SuedwestPortalsProvider.kelkheimName("Blaue Tonne Bezirk B-1, S-1 Di"), "Blaue Tonne")
        XCTAssertEqual(SuedwestPortalsProvider.kelkheimName("Gruenabfuhr Bezirk B-1, S-1 Di"), "Grünabfuhr")
        XCTAssertEqual(WasteCategory.classify("Blaue Tonne"), .paper)
        XCTAssertEqual(WasteCategory.classify("Grünabfuhr"), .organic)
        XCTAssertEqual(WasteCategory.classify("Sondermüll"), .hazardous)
    }

    func testKelkheimFlow() async throws {
        let provider = SuedwestPortalsProvider(service: "kelkheim", client: HTTPClient(session: PortalStub.session { request in
            guard request.url.hasPrefix("https://kelkheim.de/mod_abfallkalender/") else { return nil }
            if request.url.contains("action=ical") { return Self.kelkheimICS }
            return request.method == "POST" ? Self.kelkheimCalendar : Self.kelkheimForm
        }))
        let streets = try await provider.nextStep(after: [])
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Frankfurter Straße" })
        let numberStep = try await provider.nextStep(after: [street])
        XCTAssertEqual(numberStep?.input, .text)
        let number = SelectionOption(id: "10", title: "10 ")
        let done = try await provider.nextStep(after: [street, number])
        XCTAssertNil(done)
        let pickups = try await provider.pickups(for: [street, number], calendar: calendar)
        XCTAssertEqual(names(pickups), ["2026-10-14 Bio-Tonne", "2026-10-16 Gelber Sack", "2026-10-20 Restmüll", "2026-11-10 Sperrmüll"])
        XCTAssertEqual(provider.label(for: [street, number]), "Kelkheim (Taunus), Frankfurter Straße 10")

        let requests = PortalStub.requests()
        let post = try XCTUnwrap(requests.first { $0.method == "POST" })
        XCTAssertEqual(post.url, "https://kelkheim.de/mod_abfallkalender/")
        XCTAssertTrue(post.body.hasPrefix("action=areas_search&street=Frankfurter+Stra%C3%9Fe&number=10&datetype%5B%5D=Restmuell&"), post.body)
        XCTAssertFalse(post.body.contains("Restmuell-Container"))
        XCTAssertTrue(requests.contains { $0.url == "https://kelkheim.de/mod_abfallkalender/index.php?action=ical&area=B-5%2C+S-5+Di&datetype=Restmuell%2CBlaue+Tonne%2CBio-Tonne%2CGelber+Sack%2CSondermuell%2CSperrmuell%2CGruenabfuhr%2CRestmuell-Container%2CGruenschnittannahmestelle%2CWertstoffhof%2CSonstige&street=Frankfurter+Stra%DFe&number=10" },
                      "\(requests.map(\.url))")
    }

    func testKelkheimUnknownAddress() async {
        // Ohne passenden Bezirk zeigt das Portal wieder das leere Formular.
        let provider = SuedwestPortalsProvider(service: "kelkheim", client: HTTPClient(session: PortalStub.session { _ in Self.kelkheimForm }))
        do {
            _ = try await provider.pickups(for: [SelectionOption(id: "Frankfurter Straße", title: "Frankfurter Straße"), SelectionOption(id: "", title: "")], calendar: calendar)
            XCTFail("Fehler erwartet")
        } catch {}
    }

    // MARK: Flörsheim

    static let floersheimStreets = """

                    <div class="searchcontd">
                    <table class="suggestLayer" cellspacing="1" cellpadding="3" border="0" width="100%">
            <tbody>
            <tr class="listsearchoff_begin" id="trstr0"><td><span id="astr0" onkeydown="selecttosearcheenterstr(event,'Hauptlehrer-Urson-Straße','1')" onmouseover="mouseoversearchstr('0','2')" onclick="selecttosearchemousestr(event,'Hauptlehrer-Urson-Straße','1')">Hauptlehrer-Urson-Straße</span></td></tr><tr class="listsearchoff_begin" id="trstr1"><td><span id="astr1" onkeydown="selecttosearcheenterstr(event,'Hauptstraße','1')" onmouseover="mouseoversearchstr('1','2')" onclick="selecttosearchemousestr(event,'Hauptstraße','1')">Hauptstraße</span></td></tr>        </tbody>
    \t\t</table>
            </div>

    """
    static let floersheimICS = #"""
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:Floersheim-Umweltkalender.de 2026
    CALSCALE:GREGORIAN
    METHOD:PUBLISH
    X-WR-CALNAME:Abfuhrtermine fuer das Jahr 2026
    X-WR-TIMEZONE:Europe/Berlin
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261005
    LOCATION:Deutschland\,Flörsheim am Main\,Hauptstraße
    SUMMARY:Bio-Tonne
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261012
    LOCATION:Deutschland\,Flörsheim am Main\,Hauptstraße
    SUMMARY:Gelber Sack
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261017
    LOCATION:Deutschland\,Flörsheim am Main\,Hauptstraße
    SUMMARY:Sonderabfälle\, Flörsheim\, Sportanlagen Hauptstraße 8.00-10.00 Uhr
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261023
    LOCATION:Deutschland\,Flörsheim am Main\,Hauptstraße
    SUMMARY:Restmüll\, Deponie Wicker\, Zusatztermine\, 7.30 - 12.00 Uhr und 13:00 - 16:00 Uhr
    END:VEVENT
    BEGIN:VEVENT
    DTSTART;VALUE=DATE:20261019
    LOCATION:Deutschland\,Flörsheim am Main\,Hauptstraße
    SUMMARY:Altpapier
    END:VEVENT
    END:VCALENDAR
    """#

    func testFloersheimParsing() {
        XCTAssertEqual(SuedwestPortalsProvider.floersheimStreets(Self.floersheimStreets).map(\.title), ["Hauptlehrer-Urson-Straße", "Hauptstraße"])
        XCTAssertEqual(SuedwestPortalsProvider.floersheimNames("Sonderabfälle, Wicker, Friedhof Taunusstraße, 16.00 - 17.30 Uhr"), ["Schadstoffmobil"])
        XCTAssertEqual(SuedwestPortalsProvider.floersheimNames("Restmüll, Deponie Wicker, Zusatztermine, 7.30 - 12.00 Uhr"), [])
        XCTAssertEqual(SuedwestPortalsProvider.floersheimNames("Gartenabfall"), ["Gartenabfall"])
        XCTAssertEqual(WasteCategory.classify("Schadstoffmobil"), .hazardous)
        XCTAssertEqual(WasteCategory.classify("Gartenabfall"), .green)
    }

    private func floersheimProvider(numbers: String = "0", district: String = "1|||1|||22|||") -> SuedwestPortalsProvider {
        SuedwestPortalsProvider(service: "floersheim", client: HTTPClient(session: PortalStub.session { request in
            guard request.url.hasPrefix("https://www.floersheim-umweltkalender.de/") else { return nil }
            if request.url.hasSuffix("ajaxseachstr.html") { return Self.floersheimStreets }
            if request.url.hasSuffix("searchnachnr.html") { return numbers }
            if request.url.hasSuffix("searchnachnrundstr.html") { return district }
            if request.url.contains("icalkalender.html") { return Self.floersheimICS }
            return nil
        }))
    }

    func testFloersheimFlow() async throws {
        let provider = floersheimProvider()
        let first = try await provider.nextStep(after: [])
        XCTAssertEqual(first?.input, .text)
        let search = SelectionOption(id: "Haupt", title: "Haupt")
        let streets = try await provider.nextStep(after: [search])
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Hauptstraße" })
        let done = try await provider.nextStep(after: [search, street])
        XCTAssertNil(done, "Straße liegt ganz in einem Bezirk")
        let pickups = try await provider.pickups(for: [search, street], calendar: calendar)
        XCTAssertEqual(names(pickups), ["2026-10-05 Bio-Tonne", "2026-10-12 Gelber Sack", "2026-10-17 Schadstoffmobil", "2026-10-19 Altpapier"])
        XCTAssertEqual(provider.label(for: [search, street]), "Flörsheim am Main, Hauptstraße")

        let requests = PortalStub.requests()
        XCTAssertEqual(requests.first { $0.url.hasSuffix("ajaxseachstr.html") }?.body, "searchstr=Haupt")
        XCTAssertEqual(requests.first { $0.url.hasSuffix("searchnachnrundstr.html") }?.body, "strnamesearch=Hauptstra%C3%9Fe&checkedarts=1_3_7_4_8_6")
        XCTAssertTrue(requests.contains { $0.url == "https://www.floersheim-umweltkalender.de/icalkalender.html?jahr=1&selectedmonat=&selectedwoche=&bezirk=1&hausnr=&strasse=Hauptstra%C3%9Fe&checkedarts=1_3_7_4_8_6" },
                      "\(requests.map(\.url))")
    }

    func testFloersheimHouseNumber() async throws {
        let provider = floersheimProvider(numbers: "3", district: "0|||||||||Die Hausnummer wurde nicht gefunden. Bitte überprüfen Sie Ihre Eingabe.")
        let search = SelectionOption(id: "Haupt", title: "Haupt")
        let street = SelectionOption(id: "Hauptstraße", title: "Hauptstraße")
        let numberStep = try await provider.nextStep(after: [search, street])
        XCTAssertEqual(numberStep?.input, .text)
        do {
            _ = try await provider.pickups(for: [search, street, SelectionOption(id: "999", title: "999")], calendar: calendar)
            XCTFail("Fehler erwartet")
        } catch {}
        XCTAssertEqual(PortalStub.requests().last?.body, "strnamesearch=Hauptstra%C3%9Fe&checkedarts=1_3_7_4_8_6&hsnrsearch=999")
    }

    // MARK: Live

    private func requireLive() throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
    }

    /// Termine ab heute; gibt sie zum Nachlesen aus.
    private func checkUpcoming(_ pickups: [Pickup], _ label: String, min: Int = 3) {
        let today = calendar.startOfDay(for: Date())
        let upcoming = pickups.filter { $0.date >= today }
        XCTAssertGreaterThanOrEqual(upcoming.count, min, label)
        print("\(label):", upcoming.prefix(8).map { "\(Days.iso($0.date)) \($0.name)" })
    }

    func testLiveMuellmann() async throws {
        try requireLive()
        let provider = SuedwestPortalsProvider(service: "muellmann")
        let regions = try await provider.nextStep(after: [])
        let konstanz = try XCTUnwrap(regions?.options.first { $0.id == "konstanz" })
        let streets = try await provider.nextStep(after: [konstanz])
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Abendbergweg" })
        let none = try await provider.nextStep(after: [konstanz, street])
        XCTAssertNil(none)
        let pickups = try await provider.pickups(for: [konstanz, street], calendar: calendar)
        checkUpcoming(pickups, "Konstanz Abendbergweg")
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-12" && $0.name == "Biomüll" })
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-14" && $0.name == "Gelber Sack" })

        let aach = try XCTUnwrap(regions?.options.first { $0.id == "aach" })
        let aachNext = try await provider.nextStep(after: [aach])
        XCTAssertNil(aachNext)
        let aachPickups = try await provider.pickups(for: [aach], calendar: calendar)
        checkUpcoming(aachPickups, "Aach")
        XCTAssertTrue(aachPickups.contains { Days.iso($0.date) == "2026-10-12" && $0.name == "Biomüll" })

        let karlsruhe = try XCTUnwrap(regions?.options.first { $0.id == "karlsruhe" })
        let ksStreets = try await provider.nextStep(after: [karlsruhe])
        let adler = try XCTUnwrap(ksStreets?.options.first { $0.title == "Adlerstraße" })
        let ranges = try await provider.nextStep(after: [karlsruhe, adler])
        let range = try XCTUnwrap(ranges?.options.first { $0.title == "3–9" })
        checkUpcoming(try await provider.pickups(for: [karlsruhe, adler, range], calendar: calendar), "Karlsruhe Adlerstraße 3–9")
    }

    func testLiveZvaWerraMeissner() async throws {
        try requireLive()
        let provider = SuedwestPortalsProvider(service: "zvawmk")
        let cities = try await provider.nextStep(after: [])
        XCTAssertGreaterThan(cities?.options.count ?? 0, 100)
        let city = try XCTUnwrap(cities?.options.first { $0.id == "WEHRETAL_REICHENSACHSEN" })
        let streets = try await provider.nextStep(after: [city])
        let street = try XCTUnwrap(streets?.options.first { $0.id == "AM+BAHNHOF" })
        let pickups = try await provider.pickups(for: [city, street], calendar: calendar)
        checkUpcoming(pickups, "Wehretal-Reichensachsen Am Bahnhof")
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-12" && $0.name == "Biomüll" })
    }

    func testLiveKelkheim() async throws {
        try requireLive()
        let provider = SuedwestPortalsProvider(service: "kelkheim")
        let streets = try await provider.nextStep(after: [])
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Frankfurter Straße" })
        let number = SelectionOption(id: "10", title: "10")
        let pickups = try await provider.pickups(for: [street, number], calendar: calendar)
        checkUpcoming(pickups, "Kelkheim Frankfurter Straße 10")
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-14" && $0.name == "Bio-Tonne" })
        XCTAssertTrue(pickups.contains { Days.iso($0.date) == "2026-10-16" && $0.name == "Gelber Sack" })
    }

    func testLiveFloersheim() async throws {
        try requireLive()
        let provider = SuedwestPortalsProvider(service: "floersheim")
        let search = SelectionOption(id: "Haupt", title: "Haupt")
        let streets = try await provider.nextStep(after: [search])
        let street = try XCTUnwrap(streets?.options.first { $0.title == "Hauptstraße" })
        let none = try await provider.nextStep(after: [search, street])
        XCTAssertNil(none)
        let pickups = try await provider.pickups(for: [search, street], calendar: calendar)
        checkUpcoming(pickups, "Flörsheim Hauptstraße")
        XCTAssertFalse(pickups.contains { $0.name.contains("Container") || $0.name.contains("Deponie") })
    }
}

/// Nachgestellte Portale: `route` liefert je Anfrage die Antwort, `nil` heißt HTTP 404.
final class PortalStub: URLProtocol {
    struct Seen { let url: String; let method: String; let headers: [String: String]; let body: String }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []
    nonisolated(unsafe) private static var route: (Seen) -> String? = { _ in nil }

    static func session(_ route: @escaping (Seen) -> String?) -> URLSession {
        lock.lock(); seen = []; Self.route = route; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PortalStub.self]
        return URLSession(configuration: config)
    }

    static func requests() -> [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            body = data
        }
        let entry = Seen(url: request.url?.absoluteString ?? "", method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:],
                         body: body.map { String(decoding: $0, as: UTF8.self) } ?? "")
        Self.lock.lock()
        Self.seen.append(entry)
        let route = Self.route
        Self.lock.unlock()

        let answer = route(entry)
        let response = HTTPURLResponse(url: request.url!, statusCode: answer == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((answer ?? "nicht gefunden").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
