import XCTest
@testable import TonneCore

/// hausmüll.info: Listen-Parser, Namensbereinigung und Zustand offline; Live-Durchläufe je Betreiber.
final class HausmuellInfoProviderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    func testParseListVariants() {
        // Börde/Wesel: ID und Gebiet in versteckten Spans
        let boerde = "<ul><li id = 'hnr_1194011'onClick='get_value(\"hnr\",1194011,1205137)'><span style = 'display:none;'>1194011</span><span style = 'display:none;'>1205137</span><span>8</span></li></ul>"
        XCTAssertEqual(HausmuellInfoProvider.parseList(boerde, level: .hnr), [SelectionOption(id: "hnr:1194011:1205137", title: "8")])
        // AZV: einfache Anführungszeichen, ohne versteckte Spans
        let azv = "\u{FEFF}<ul class=\"proposalList\"><li id=\"ort_23236\" onclick=\"get_value('ort', 23236, 75254)\"><span>Berka vor dem Hainich</span></li><li>Kein Eintrag gefunden</li></ul>"
        XCTAssertEqual(HausmuellInfoProvider.parseList(azv, level: .ort), [SelectionOption(id: "ort:23236:75254", title: "Berka vor dem Hainich")])
        // Suhl/Erfurt: ohne Gebiet
        let suhl = "<ul><li id = 'ort_1670'onClick='get_value(\"ort\",1670); event.stopPropagation();'><span style = 'display:none;'>1670</span><span>Albrechts</span></li></ul>"
        XCTAssertEqual(HausmuellInfoProvider.parseList(suhl, level: .ort), [SelectionOption(id: "ort:1670:0", title: "Albrechts")])
        // Platzhalter „-“ fällt weg, „-Stadt-“ wird zur Kernstadt
        let sm = "<li onClick='get_value(\"ort\",1502,0)'><span>-</span></li><li onClick='get_value(\"ortsteil\",18896,0)'><span>-Stadt-</span></li>"
        XCTAssertEqual(HausmuellInfoProvider.parseList(sm, level: .ortsteil).map(\.title), ["Kernstadt"])
    }

    func testStateAndLabel() {
        let provider = HausmuellInfoProvider(service: "asc")
        let selections = [SelectionOption(id: "Hübschmann", title: "Hübschmann"),
                          SelectionOption(id: "str:191388:0", title: "Hübschmannstr."),
                          SelectionOption(id: "hnr:22159107:4781518", title: "5")]
        let state = HausmuellInfoProvider.state(from: selections)
        XCTAssertNil(state.query)
        XCTAssertEqual(state.area, "4781518")
        XCTAssertEqual(provider.label(for: selections), "Chemnitz, Hübschmannstr. 5")
        let fields = Dictionary(HausmuellInfoProvider.icsFields(state, year: ""), uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(fields["hidden_id_egebiet"], "4781518")
        XCTAssertEqual(fields["hidden_id_str"], "191388")
        XCTAssertEqual(fields["hidden_send_btn"], "ics")
    }

    func testCleanNameAndDecode() {
        XCTAssertEqual(HausmuellInfoProvider.cleanName("Entsorgung: Pappe, Papier & Kart.").0, "Pappe, Papier & Kart.")
        let shifted = HausmuellInfoProvider.cleanName("Verschobene Abholung: Restmüll ")
        XCTAssertEqual(shifted.0, "Restmüll")
        XCTAssertNotNil(shifted.1)
        XCTAssertEqual(WasteCategory.classify(HausmuellInfoProvider.cleanName("Entsorgung: Leichtstoffverpackungen").0), .packaging)
        // Gemischte Kodierung: eine Zeile UTF-8, eine Latin-1
        var data = Data("SUMMARY:Restmüll\n".utf8)
        data.append(Data([0x53, 0x55, 0x4D, 0x3A, 0x47, 0x72, 0xFC, 0x6E]))
        XCTAssertEqual(HausmuellInfoProvider.decode(data), "SUMMARY:Restmüll\nSUM:Grün")
    }

    func testUnknownOperator() async {
        do {
            _ = try await HausmuellInfoProvider(service: "gibtsnicht").nextStep(after: [])
            XCTFail("Fehler erwartet")
        } catch {}
    }
}

extension LiveProviderTests {
    func testHausmuellInfoErfurt() async throws {
        try await check(HausmuellInfoProvider(service: "erfurt"), prefer: ["Adam-Ries-Straße", "5"], minCount: 3)
    }

    // Hinweis: Das Portal schreibt Umlaute der Adresse Latin-1-kodiert in den Content-Disposition-Header, an dem
    // FoundationNetworking unter Linux scheitert (iOS ist nicht betroffen) – daher Testadressen ohne Umlaute.
    func testHausmuellInfoChemnitz() async throws {
        try await checkTyped(HausmuellInfoProvider(service: "asc"), typed: ["Carl-von-Ossietzky-Straße"], prefer: ["Carl-von-Ossietzky-Str", "94"], minCount: 3)
        // Adresse mit mehreren Objekten: zusätzlicher Schritt „Objektnummer“
        let provider = HausmuellInfoProvider(service: "asc")
        let selections = try await walkTyped(provider, typed: ["Wasserscheide"], prefer: ["Wasserscheide", "5", "89251"])
        XCTAssertEqual(selections.last?.id.hasPrefix("objekt:"), true)
        try await checkTyped(provider, typed: ["Wasserscheide"], prefer: ["Wasserscheide", "5", "89251"], minCount: 3)
    }

    func testHausmuellInfoBoerde() async throws {
        try await check(HausmuellInfoProvider(service: "boerde"), prefer: ["Irxleben", "Bördestraße", "8"], minCount: 3)
    }

    func testHausmuellInfoWartburgkreis() async throws {
        try await check(HausmuellInfoProvider(service: "azv"), prefer: ["Eisenach", "Eisenach", "Abbestraße"], minCount: 3)
        try await check(HausmuellInfoProvider(service: "azv"), prefer: ["Hörselberg-Hainich", "Ettenhausen/Nesse"], minCount: 3)
    }

    func testHausmuellInfoSchmalkaldenMeiningen() async throws {
        try await check(HausmuellInfoProvider(service: "schmalkalden-meiningen"), prefer: ["Zella-Mehlis", "Benshausen", "Albrechtser Straße"], minCount: 3)
        try await check(HausmuellInfoProvider(service: "schmalkalden-meiningen"), prefer: ["Dillstädt"], minCount: 3)
    }

    func testHausmuellInfoEichsfeld() async throws {
        try await check(HausmuellInfoProvider(service: "ew"), prefer: ["Döringsdorf", "Wanfrieder Str."], minCount: 3)
    }

    func testHausmuellInfoSuhl() async throws {
        try await check(HausmuellInfoProvider(service: "ebkds"), prefer: ["Dietzhausen", "Am Rain", "10"], minCount: 3)
    }

    func testHausmuellInfoWesel() async throws {
        try await check(HausmuellInfoProvider(service: "wesel"), prefer: ["Blumenkamp", "Albert-Schweitzer-Weg"], minCount: 3)
        // Mit Umlauten greift unter Linux der Abruf nur über die Gebiets-ID.
        try await check(HausmuellInfoProvider(service: "wesel"), prefer: ["Flüren", "In der Flürener Heide"], minCount: 3)
    }
}
