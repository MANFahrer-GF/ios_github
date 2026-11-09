import XCTest
@testable import TonneCore

/// Funde aus der Prüfung aller Orte auf fehlende oder falsche Straßenlisten (November 2026),
/// jeweils mit echten, gekürzten Portalantworten.
final class StreetAuditTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    // MARK: - Suche in Auswahllisten

    private func titles(_ options: [SelectionOption], _ query: String) -> [String] {
        OptionSearch(options).filter(query: query).map(\.title)
    }

    func testOptionSearchVereinheitlichtSchreibweisen() {
        let options = ["Aachener Straße", "Karl-Marx-Str.", "Mühlenweg", "Bäringer\u{AD}straße", "Hauptstr.", "Goethe Platz"].map { SelectionOption(id: $0, title: $0) }
        XCTAssertEqual(titles(options, "aachener str."), ["Aachener Straße"])
        XCTAssertEqual(titles(options, "Karl Marx Straße"), ["Karl-Marx-Str."])
        XCTAssertEqual(titles(options, "karlmarxstrasse"), ["Karl-Marx-Str."])
        XCTAssertEqual(titles(options, "Muehlen"), ["Mühlenweg"])
        XCTAssertEqual(titles(options, "Muhlen"), ["Mühlenweg"])
        XCTAssertEqual(titles(options, "Bäringerstr"), ["Bäringer\u{AD}straße"])
        XCTAssertEqual(titles(options, "Platz Goethe"), ["Goethe Platz"], "Reihenfolge der Wörter ist egal")
        XCTAssertEqual(titles(options, "Goethe Weg"), [], "alle Wörter müssen passen")
    }

    func testOptionSearchTrefferBleibenBeimTippenStehen() {
        let options = [SelectionOption(id: "1", title: "Hauptstr."), SelectionOption(id: "2", title: "Hauptstraße")]
        for typed in ["Hau", "Haupts", "Hauptst", "Hauptstr", "Hauptstra", "Hauptstraß", "Hauptstraße", "Hauptstrasse"] {
            XCTAssertEqual(titles(options, typed).count, 2, typed)
        }
    }

    func testOptionSearchDurchsuchtDenUntertitel() {
        let options = [SelectionOption(id: "1", title: "Kirchweg", subtitle: "Oberdorf"), SelectionOption(id: "2", title: "Kirchweg", subtitle: "Unterdorf")]
        XCTAssertEqual(OptionSearch(options).filter(query: "kirchweg unterdorf").map(\.id), ["2"])
    }

    func testOptionSearchOhneEingabeZeigtAlles() {
        let options = (0..<1200).map { SelectionOption(id: "\($0)", title: "Straße \($0)") }
        XCTAssertEqual(OptionSearch(options).filter(query: "  - ").count, 1200)
    }

    func testOptionSearchGrosseListeDauer() {
        let options = (0..<6000).map { SelectionOption(id: "\($0)", title: "Münchner-Beispiel Straße \($0)", subtitle: "Ortsteil") }
        let index = OptionSearch(options)
        XCTAssertEqual(index.filter(query: "Straße 5999").count, 1)
    }

    // MARK: - Hamburg

    private func hamburgStep(streets: Int) async throws -> SelectionStep? {
        let rows = (0..<streets).map { "{\"asId\":\($0),\"name\":\"Schulstraße \($0)\",\"hnIds\":[]}" }.joined(separator: ",")
        StreetAuditStub.handler = { _ in (200, "[\(rows)]") }
        let provider = NordPortalsProvider(service: "hamburg", client: HTTPClient(session: StreetAuditStub.session()))
        return try await provider.nextStep(after: [SelectionOption(id: "Sch", title: "Sch")])
    }

    func testHamburgSagtBeiFuenfzigTreffernDassMehrBuchstabenNoetigSind() async throws {
        let step = try await hamburgStep(streets: 50)
        XCTAssertEqual(step?.options.count, 50)
        XCTAssertEqual(step?.hint?.contains("mehr Buchstaben"), true)
    }

    func testHamburgOhneHinweisUnterDerGrenze() async throws {
        let step = try await hamburgStep(streets: 49)
        XCTAssertEqual(step?.options.count, 49)
        XCTAssertNil(step?.hint)
    }

    // MARK: - A.R.T. Trier

    private func artStep(_ rows: [String]) async throws -> SelectionStep? {
        StreetAuditStub.handler = { _ in (200, "{\"data\":[\(rows.joined(separator: ","))]}") }
        let provider = RheinlandPfalzPortalsProvider(service: "art", client: HTTPClient(session: StreetAuditStub.session()))
        return try await provider.nextStep(after: [SelectionOption(id: "Trier-Land", title: "Trier-Land"), SelectionOption(id: "Aach", title: "Aach")])
    }

    private func artRow(_ strasse: String?, _ ortsteil: String?, key: String) -> String {
        let quote = { (value: String?) in value.map { "\"\($0)\"" } ?? "null" }
        return "{\"plz\":\"54298\",\"ort\":\"Aach\",\"strasse\":\(quote(strasse)),\"ortsteil\":\(quote(ortsteil)),\"verbandsgemeinde\":\"Trier-Land\",\"key\":\"\(key)\"}"
    }

    func testARTUebrigeStrassenStehenObenMitHinweis() async throws {
        let step = try await artStep([artRow("Aacher Straße", nil, key: "a"), artRow(nil, nil, key: "rest"), artRow("Zum Wehrborn", nil, key: "z")])
        XCTAssertEqual(step?.options.map(\.id), ["rest", "a", "z"])
        XCTAssertEqual(step?.options.first?.title, "Übrige Straßen")
        XCTAssertNotNil(step?.options.first?.subtitle)
        XCTAssertEqual(step?.noMatchHint?.contains("Übrige Straßen"), true)
    }

    func testARTOhneSammeleintragOhneHinweis() async throws {
        let step = try await artStep([artRow("Aacher Straße", nil, key: "a"), artRow("Zum Wehrborn", nil, key: "z")])
        XCTAssertEqual(step?.options.map(\.id), ["a", "z"])
        XCTAssertNil(step?.noMatchHint)
    }

    // MARK: - Gleichnamige Einträge

    func testAbfallnaviZeigtOrtsteilNurBeiGleichenNamen() async throws {
        StreetAuditStub.handler = { _ in (200, #"[{"id":1,"name":"Ackerstraße","ortsteilName":"Gallinchen"},{"id":2,"name":"Ackerstraße","ortsteilName":"Mitte"},{"id":3,"name":"Birkenweg","ortsteilName":"Sielow"}]"#) }
        let provider = AbfallnaviProvider(service: "cottbus", client: HTTPClient(session: StreetAuditStub.session()))
        let step = try await provider.nextStep(after: [SelectionOption(id: "city:7", title: "Cottbus")])
        XCTAssertEqual(step?.options.map(\.subtitle), ["Gallinchen", "Mitte", nil])
    }

    func testMuenchenFasstGleicheAdressenZusammen() {
        let html = #"<span class="aostrasse">Maria-Nindl-Pl.</span><span class="aostrasse">Maria-Nindl-Platz</span><span class="aostrasse">Bellinzonastr.</span>"#
        XCTAssertEqual(AWMMuenchenProvider.streets(in: html).map(\.title), ["Bellinzonastraße", "Maria-Nindl-Platz"])
    }

    func testBuergerportalBlendetAltdatensatzOhnePLZAus() async throws {
        StreetAuditStub.handler = { _ in (200, #"{"d":[{"StrassenId":365,"Name":"Kirchstraße","Plz":"56818"},{"StrassenId":2130,"Name":"Kirchstraße","Plz":null},{"StrassenId":9,"Name":"Moselweg","Plz":null}]}"#) }
        let provider = BuergerportalProvider(operator: "cochem_zell", client: HTTPClient(session: StreetAuditStub.session()))
        let step = try await provider.nextStep(after: [SelectionOption(id: "14|Klotten", title: "Klotten")])
        XCTAssertEqual(step?.options.map(\.id), ["365", "9"])
    }

    func testJenaFuehrtDoppelteStrasseZusammenUndFragtDieRichtigeAb() async throws {
        let select = { (name: String, values: [String]) in "<select name=\"\(name)\">" + values.map { "<option value=\"\($0)\">\($0)</option>" }.joined() + "</select>" }
        nonisolated(unsafe) var calendarURL = ""
        StreetAuditStub.handler = { url in
            if url.contains("makeICSAll") { calendarURL = url; return (200, "BEGIN:VCALENDAR\nEND:VCALENDAR") }
            if url.contains("street=Lange%20Gasse%20") || url.contains("street=Lange+Gasse+") { return (200, select("hnummer", ["Hausnummer", "55", "60"])) }
            if url.contains("street=Lange") { return (200, select("hnummer", ["Hausnummer", "37", "60"])) }
            return (200, select("comboboxStreet", ["Lange Gasse", "Lange Gasse ", "Weg"]))
        }
        let provider = MitteldeutschlandPortalsProvider(service: "jena", client: HTTPClient(session: StreetAuditStub.session()))
        let streets = try await provider.nextStep(after: [])
        XCTAssertEqual(streets?.options.map(\.title), ["Lange Gasse", "Weg"])
        let street = try XCTUnwrap(streets?.options.first)
        let numbers = try await provider.nextStep(after: [street])
        XCTAssertEqual(numbers?.options.map(\.title).sorted(), ["37", "55", "60"])
        let number = try XCTUnwrap(numbers?.options.first { $0.title == "55" })
        _ = try? await provider.pickups(for: [street, number], calendar: .current)
        XCTAssertTrue(calendarURL.contains("hnummer=55"), calendarURL)
        XCTAssertTrue(calendarURL.contains("Gasse%20&") || calendarURL.contains("Gasse+&"), calendarURL)
    }

    func testKyffhaeuserFasstOrteZusammenUndUeberspringtVeralteteKennung() async throws {
        let page = #"x "tribe_venues[]","options":[{"text":"Ebeleben","id":"105","value":"105"},{"text":"Ebeleben","id":"1433","value":"1433"},{"text":"Holzthaleben","id":"7","value":"7"}] y"#
        let events = #"{"events":[{"title":"Papier","start_date":"2030-01-02 00:00:00"}],"total_pages":1}"#
        StreetAuditStub.handler = { url in
            if url.contains("/kalender/") { return (200, page) }
            return url.contains("venue=105") ? (400, "{}") : (200, events)
        }
        let provider = MitteldeutschlandPortalsProvider(service: "kyffhaeuser", client: HTTPClient(session: StreetAuditStub.session()))
        let step = try await provider.nextStep(after: [])
        XCTAssertEqual(step?.options.map(\.title), ["Ebeleben", "Holzthaleben"])
        let ebeleben = try XCTUnwrap(step?.options.first)
        let pickups = try await provider.pickups(for: [ebeleben], calendar: .current)
        XCTAssertEqual(Set(pickups.map(\.name)).count, 1)
    }

    func testNaechsteTermineJeAbfallart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = { (m: Int, d: Int) in calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }
        let pickups = [Pickup(date: day(12, 3), name: "Papier"), Pickup(date: day(11, 12), name: "Restabfall"), Pickup(date: day(11, 26), name: "Restabfall")]
        XCTAssertEqual(AbfallIOGraphQLProvider.nextDates(pickups, calendar: calendar), "Papier 03.12. · Restabfall 12.11.")
    }

    // MARK: - Landkreis Cham

    func testChamCompletesLiestJSONForm() {
        // Antwort von loadCompletes.php seit dem Umbau des Portals, November 2026
        let html = #"<script>complete = [{"label":"93473 Arnschwang","value":"1"},{"label":"93444 Bad Kötzting","value":"3"},{"label":"Arnschwanger Str.","value":""}];</script>"#
        let items = BayernPortalsProvider.chamCompletes(html)
        XCTAssertEqual(items.map(\.label), ["93473 Arnschwang", "93444 Bad Kötzting", "Arnschwanger Str."])
        XCTAssertEqual(items.map(\.value), ["1", "3", ""])
    }

    func testChamCompletesLiestAlteForm() {
        let html = #"complete = [{ label: '93474 Arrach', value: '2' }, { label: 'Zum \'Anger\'', value: '' }];"#
        let items = BayernPortalsProvider.chamCompletes(html)
        XCTAssertEqual(items.map(\.label), ["93474 Arrach", "Zum 'Anger'"])
        XCTAssertEqual(items.map(\.value), ["2", ""])
    }

    // MARK: - AZV Wartburgkreis

    func testWartburgkreisFragtDieSuchskripteUndNichtDenProxy() async throws {
        StreetAuditStub.handler = { url in
            if url.contains("proxy.php") { return (404, "File not found.\n") }
            if url.contains("search/search_orte.php") {
                return (200, "\u{FEFF}<ul class=\"proposalList\"><li id=\"ort_23190\" onclick=\"get_value('ort', 23190, 0)\"><span>Amt Creuzburg</span></li></ul>")
            }
            return (500, "")
        }
        let provider = HausmuellInfoProvider(service: "azv", client: HTTPClient(session: StreetAuditStub.session()))
        let step = try await provider.nextStep(after: [])
        XCTAssertEqual(step?.options.map(\.title), ["Amt Creuzburg"])
    }

    // MARK: - Landkreis Nordhausen

    private func nordhausen() -> MitteldeutschlandPortalsProvider {
        StreetAuditStub.handler = { url in
            if url.hasSuffix("/addresses") {
                return (200, #"[{"id":7,"location":"Appenrode","street":"","houseNumbers":""},{"id":8,"location":"Bleicherode","street":"Hauptstraße","houseNumbers":""},{"id":9,"location":"Bleicherode","street":"Ringstraße","houseNumbers":""}]"#)
            }
            if url.contains("/calendar/ics?addressid=7") {
                return (200, "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20270105\r\nSUMMARY:Restabfall wird abgeholt\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
            }
            return (500, "")
        }
        return MitteldeutschlandPortalsProvider(service: "nordhausen", client: HTTPClient(session: StreetAuditStub.session()))
    }

    func testNordhausenOrtOhneStrasseFuehrtDirektZuDenTerminen() async throws {
        let provider = nordhausen()
        let places = try await provider.nextStep(after: [])
        let appenrode = try XCTUnwrap(places?.options.first { $0.title == "Appenrode" })
        XCTAssertEqual(appenrode.id, "7")
        let next = try await provider.nextStep(after: [appenrode])
        XCTAssertNil(next, "ohne Straße folgt keine weitere Auswahl")
        let pickups = try await provider.pickups(for: [appenrode], calendar: .current)
        XCTAssertEqual(pickups.map(\.name), ["Restabfall"])
    }

    func testNordhausenOrtMitStrassenFragtWeiterDieStrasseAb() async throws {
        let provider = nordhausen()
        let places = try await provider.nextStep(after: [])
        let bleicherode = try XCTUnwrap(places?.options.first { $0.title == "Bleicherode" })
        XCTAssertEqual(bleicherode.id, "Bleicherode")
        let streets = try await provider.nextStep(after: [bleicherode])
        XCTAssertEqual(streets?.options.map(\.title), ["Hauptstraße", "Ringstraße"])
    }

    // MARK: - Auswahllisten im HTML

    func testAuswahllisteEndetAuchOhneSchliessendesSelect() {
        let html = #"<select name="ort"><option value="1">Bad Saarow</option><option value="2">Beeskow</option><select name="strasse"><option value="leer">Alte Eichen</option></select>"#
        XCTAssertEqual(HTMLText.options(ofSelect: "ort", in: html).map(\.label), ["Bad Saarow", "Beeskow"])
        XCTAssertEqual(HTMLText.options(ofSelect: "strasse", in: html).map(\.label), ["Alte Eichen"])
    }

    func testAuswahllisteMitSchliessendemSelectUnveraendert() {
        let html = #"<select name="ort"><option value="1">Bad Saarow</option></select><option value="9">außerhalb</option>"#
        XCTAssertEqual(HTMLText.options(ofSelect: "ort", in: html).map(\.value), ["1"])
    }

    // MARK: - AbfallPlus: Abfallarten

    private let abfallartenHTML = #"""
    <input type="hidden" name="f_id_abfallart[]" id="f_id_abfallart_1141" value="0" class="awk-standort-auswahl-value" />
    <input type="hidden" name="f_id_abfallart[]" id="f_id_abfallart_1142" value="1142" class="awk-standort-auswahl-value" />
    <input type="hidden" name="f_id_abfallart[]" id="f_id_abfallart_66" value="66" class="awk-standort-auswahl-value" />
    """#

    func testAbfallartenStandardmaessigAlleSchalter() {
        XCTAssertEqual(AbfallPlusAppProvider.typeIDs(in: abfallartenHTML, onlyPreselected: false).sorted(), ["1141", "1142", "66"])
    }

    func testAbfallartenNachAblehnungNurDieEingeschalteten() {
        XCTAssertEqual(AbfallPlusAppProvider.typeIDs(in: abfallartenHTML, onlyPreselected: true).sorted(), ["1142", "66"])
    }

    // MARK: - Kreiszuordnung im Katalog

    private func districts(of entryPrefix: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let hits = CatalogRegions.entryDistricts.filter { $0.key.hasPrefix(entryPrefix + ":") }
        XCTAssertEqual(hits.count, 1, "Eintrag \(entryPrefix)", file: file, line: line)
        return hits.first?.value ?? []
    }

    func testEintraegeBleibenInEinemBundesland() {
        // Wirklich länderübergreifende Dienste; alles andere wäre eine Zuordnung über einen gleichnamigen Ort.
        let multiState = ["abfallPlusApp:de.abfallwecker:", "abfallPlusApp:de.albagroup.app:", "abfallPlusApp:de.remondis.rheinland:", "jumomind:mymuell:", "lobbe:lobbe:"]
        XCTAssertGreaterThan(CatalogRegions.entryDistricts.count, 300)
        for (id, districts) in CatalogRegions.entryDistricts where !multiState.contains(where: id.hasPrefix) {
            let states = Set(districts.map { CatalogRegions.districtStates[$0] ?? "unbekannt: \($0)" })
            XCTAssertEqual(states.count, 1, "\(id): \(states.sorted())")
        }
    }

    func testKreiszuordnungHaengtNichtAmGleichnamigenOrt() {
        let wrong: [(String, String)] = [
            ("portalsRP:art", "Kreisfreie Stadt Hamm"), ("portalsRP:art", "Landkreis Esslingen"), ("portalsRP:art", "Landkreis Neunkirchen"),
            ("portalsRP:kreuznach", "Landkreis Roth"), ("portalsRP:rheinlahn", "Landkreis Roth"),
            ("hausmuellInfo:wesel", "Landkreis Wittenberg"), ("portalsBayern:eva", "Kreisfreie Stadt Oberhausen"),
            ("portalsMitte:ajl", "Kreisfreie Stadt Hagen"), ("wasteManagementServlet:hameln", "Kreisfreie Stadt Hagen"),
            ("portalsNord:bremerhaven", "Landkreis Cuxhaven"),
        ]
        for (entry, district) in wrong {
            XCTAssertFalse(districts(of: entry).contains(district), "\(entry) → \(district)")
        }
        XCTAssertTrue(districts(of: "portalsRP:art").contains("Kreisfreie Stadt Trier"), "der echte Bereich bleibt")
        XCTAssertTrue(districts(of: "portalsRP:kreuznach").contains("Landkreis Bad Kreuznach"))
    }

    func testNichtBedienteKreiseBleibenDraussen() {
        let notServed: [(String, String)] = [
            ("awmMuenchen:muenchen", "Landkreis München"), ("leipzig:leipzig", "Landkreis Leipzig"), ("portalsMV:rostock", "Landkreis Rostock"),
            ("portalsNord:osnabrueck", "Landkreis Osnabrück"), ("portalsBayern:coburg", "Landkreis Coburg"), ("muellmax:Ask", "Landkreis Kaiserslautern"),
            ("abfallPlusApp:de.k4systems.abfallappla", "Landkreis Landshut"), ("abfallPlusApp:de.k4systems.awa", "Landkreis Augsburg"), ("abfallPlusApp:de.k4systems.wuerzburg", "Landkreis Würzburg"),
            ("awido:lra-regensburg", "Kreisfreie Stadt Regensburg"), ("abfallPlusApp:abfallH.ucom.de", "Stadtkreis Heilbronn"), ("abfallPlusApp:de.remondis.rheinland", "Landkreis Traunstein"),
            ("jumomind:mymuell", "Landkreis Biberach"), ("jumomind:mymuell", "Landkreis Main-Kinzig-Kreis"), ("jumomind:mymuell", "Landkreis Aschaffenburg"),
        ]
        for (entry, district) in notServed {
            XCTAssertFalse(districts(of: entry).contains(district), "\(entry) → \(district)")
        }
        // Gegenprobe: echte Bereiche und Mehrkreis-Dienste bleiben erhalten.
        XCTAssertTrue(districts(of: "awido:lra-regensburg").contains("Landkreis Regensburg"))
        XCTAssertTrue(districts(of: "abfallPlusApp:abfallH.ucom.de").contains("Landkreis Heilbronn"))
        XCTAssertTrue(districts(of: "abfallPlusApp:de.k4systems.zawdw").contains("Landkreis Passau"))
    }

    /// A.R.T. bedient die Gemeinde Hamm im Eifelkreis, aber nicht die Stadt Hamm in Westfalen.
    func testSucheHammFindetStadtUndEifelgemeinde() throws {
        let hits = ProviderCatalog.search("Hamm")
        XCTAssertTrue(hits.contains { $0.title == "Stadt Hamm" })
        let art = try XCTUnwrap(hits.first { $0.serviceKey == "art" })
        XCTAssertTrue(art.places.contains("Hamm"))
        XCTAssertFalse(CatalogRegions.entryDistricts[art.id]?.contains("Kreisfreie Stadt Hamm") ?? true)
    }

    func testBurgenlandIstOesterreichUndNichtDerBurgenlandkreis() throws {
        let app = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == "de.k4systems.udb" })
        XCTAssertEqual(app.title, "Burgenland (Österreich)")
        XCTAssertFalse(ProviderCatalog.search("Naumburg").contains { $0.serviceKey == "de.k4systems.udb" })
        XCTAssertNil(CatalogRegions.entryDistricts[app.id])
        XCTAssertFalse(ProviderCatalog.search("Burgenlandkreis").contains { $0.serviceKey == "de.k4systems.udb" })
    }

    func testKreiszuordnungVerweistNurAufVorhandeneEintraege() {
        let known = Set(ProviderCatalog.entries.map(\.id))
        XCTAssertEqual(Set(CatalogRegions.entryDistricts.keys).subtracting(known).sorted(), [])
    }
}

/// Nachgestelltes Portal: Antwort je aufgerufener Adresse.
final class StreetAuditStub: URLProtocol {
    nonisolated(unsafe) static var handler: (String) -> (Int, String) = { _ in (500, "") }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreetAuditStub.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, body) = Self.handler(url.absoluteString)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
