import XCTest
@testable import TonneCore

/// Getippter Suchtext gehört nicht in den Standortnamen (Thomas, Leipzig 11.11.2026:
/// „Hamburger Str., Hamburger Straße, 10“). Ein Fall je Anbieter bzw. Schlüssel, dessen Assistent
/// erst einen Suchtext abfragt und danach eine Trefferliste zeigt. Der Suchtext ist ein Kunstwort,
/// das in keinem Listentitel steckt; geprüft wird, dass er fehlt und die gewählte Straße da ist.
final class SearchTextLabelTests: XCTestCase {
    static let search = "Qxsuch"
    private static func typed(_ text: String = search) -> SelectionOption { SelectionOption(id: text, title: text) }
    private static func option(_ id: String, _ title: String, _ subtitle: String? = nil) -> SelectionOption {
        SelectionOption(id: id, title: title, subtitle: subtitle)
    }

    struct Case {
        let kind: ProviderKind
        let key: String
        let selections: [SelectionOption]
        let street: String
    }

    static let cases: [Case] = [
        Case(kind: .abfallPlusApp, key: "de.abfallplus.app", selections: [option("k=5;l=1", "Musterstadt"), typed(), option("k=5;s=9", "Hauptstraße")], street: "Hauptstraße"),
        Case(kind: .portalsBayern, key: "fuerth", selections: [typed(), option("71", "Mühltalstraße"), typed("3")], street: "Mühltalstraße"),
        Case(kind: .portalsBayern, key: "landkreis_as", selections: [option("12", "Hirschau"), typed(), option("44", "Adam-Stegerwald-Straße")], street: "Adam-Stegerwald-Straße"),
        Case(kind: .awbKoeln, key: "koeln", selections: [typed(), typed("50"), option("addr:1234:50", "Aachener Straße 50", "50672 Neustadt-Nord")], street: "Aachener Straße 50"),
        Case(kind: .leipzig, key: "leipzig", selections: [typed(), option("street:Hamburger Straße", "Hamburger Straße"), option("house:4711:10", "10")], street: "Hamburger Straße"),
        Case(kind: .ahaHannover, key: "hannover", selections: [option("city:Hannover", "Hannover"), typed(), option("street:00123", "Hauptstraße"), typed("10")], street: "Hauptstraße"),
        Case(kind: .portalsNRW, key: "giessen", selections: [typed(), option("1|2", "Alicenstraße"), typed("12")], street: "Alicenstraße"),
        Case(kind: .hausmuellInfo, key: "erfurt", selections: [typed(), option("str:55:1", "Hübschmannstraße"), option("hnr:7:1", "3")], street: "Hübschmannstraße"),
        Case(kind: .insertIT, key: "offenbach", selections: [typed(), option("812", "Kaiserstraße"), option("9", "3")], street: "Kaiserstraße"),
        Case(kind: .portalsMV, key: "rostock", selections: [typed(), option("4711", "Bahnhofstraße"), typed("1")], street: "Bahnhofstraße"),
        Case(kind: .muellmax, key: "muellmax-test", selections: [option("ort:3", "Musterstadt"), typed(), option("str:88", "Hauptstraße"), option("hnr:5", "10")], street: "Hauptstraße"),
        Case(kind: .portalsNRW, key: "awista", selections: [typed(), option("a1|Merkurstraße", "Merkurstraße"), typed("45"), option("6f1d2b54-1c55-4a8e-9e0f-1a2b3c4d5e6f", "Merkurstraße 45")], street: "Merkurstraße 45"),
        Case(kind: .portalsNRW, key: "awg", selections: [typed(), option("Friedrich-Engels-Allee", "Friedrich-Engels-Allee")], street: "Friedrich-Engels-Allee"),
        Case(kind: .portalsNRW, key: "sector27", selections: [option("1", "Datteln"), typed(), option("s:77", "Ahornweg")], street: "Ahornweg"),
        Case(kind: .portalsNRW, key: "herten", selections: [typed(), option("9|1", "Ackerstraße")], street: "Ackerstraße"),
        Case(kind: .portalsNord, key: "hamburg", selections: [typed(), option("Hauptstraße", "Hauptstraße"), option("12", "12")], street: "Hauptstraße"),
        Case(kind: .portalsNord, key: "bremerhaven", selections: [typed(), option("Hafenstraße, Bremerhaven", "Hafenstraße, Bremerhaven"), option("2", "2")], street: "Hafenstraße"),
        Case(kind: .portalsNord, key: "kiel", selections: [typed(), option("Holtenauer Straße", "Holtenauer Straße"), option("5", "5")], street: "Holtenauer Straße"),
        Case(kind: .portalsNord, key: "heidekreis", selections: [typed(), option("h:1", "Poststraße", "29633 Munster"), option("1", "1")], street: "Poststraße"),
        Case(kind: .bsr, key: "bsr", selections: [typed(), option("Alexanderstr.", "Alexanderstr."), typed("1"), option("x1", "Alexanderstr. 1, 10178 Berlin")], street: "Alexanderstr."),
        Case(kind: .portalsSachsen, key: "dresden", selections: [typed(), option("n1", "Neumarkt"), option("1", "1")], street: "Neumarkt"),
        Case(kind: .portalsSuedwest, key: "frankfurt", selections: [typed(), option("s:4711", "Zeil"), typed("7")], street: "Zeil"),
        Case(kind: .portalsSuedwest, key: "stuttgart", selections: [typed(), option("Königstr.", "Königstr."), typed("7")], street: "Königstr."),
        Case(kind: .portalsSuedwest, key: "wiesbaden", selections: [typed(), option("Rheinstraße, Wiesbaden", "Rheinstraße", "Wiesbaden"), typed("7")], street: "Rheinstraße"),
        Case(kind: .portalsSuedwest, key: "heidenheim", selections: [option("Giengen", "Giengen"), option("Burgberg", "Burgberg"), typed(), option("Hauptstraße", "Hauptstraße")], street: "Hauptstraße"),
        Case(kind: .portalsSuedwest, key: "floersheim", selections: [typed(), option("Hauptstraße", "Hauptstraße"), typed("7")], street: "Hauptstraße"),
    ]

    func testSearchTextNeverInLabel() {
        var leaking: [String] = []
        for c in Self.cases {
            let label = ProviderFactory.make(kind: c.kind, serviceKey: c.key).label(for: c.selections)
            if label.contains(Self.search) || !label.contains(c.street) {
                leaking.append("\(c.kind.rawValue)/\(c.key): „\(label)“")
            }
        }
        XCTAssertEqual(leaking, [], "Suchtext im Namen oder Straße fehlt (\(leaking.count) von \(Self.cases.count))")
    }

    /// Thomas' Fall wörtlich: Leipzig, „Hamburger Str.“ getippt, eine Straße, Hausnummer 10.
    func testLeipzigLabelOfThomasCase() {
        let selections = [Self.typed("Hamburger Str."), Self.option("street:Hamburger Straße", "Hamburger Straße"), Self.option("house:4711:10", "10")]
        XCTAssertEqual(LeipzigProvider().label(for: selections), "Leipzig, Hamburger Straße 10")
    }

    /// Schon gespeicherte Standorte: alter automatischer Name wird ersetzt, ein selbst vergebener bleibt.
    func testStoredLegacyLabelIsRepaired() {
        let selections = [Self.typed("Hamburger Str."), Self.option("street:Hamburger Straße", "Hamburger Straße"), Self.option("house:4711:10", "10")]
        let legacy = SourceConfiguration(providerKind: .leipzig, serviceKey: "leipzig", selections: selections, label: "Hamburger Str., Hamburger Straße, 10")
        XCTAssertEqual(legacy.repairedSearchTextLabel(), "Leipzig, Hamburger Straße 10")
        var own = legacy
        own.label = "Oma"
        XCTAssertNil(own.repairedSearchTextLabel())
        var fixed = legacy
        fixed.label = "Leipzig, Hamburger Straße 10"
        XCTAssertNil(fixed.repairedSearchTextLabel())
        let sector = SourceConfiguration(providerKind: .portalsNRW, serviceKey: "sector27",
                                         selections: [Self.option("1", "Datteln"), Self.typed("Ahorn"), Self.option("s:77", "Ahornweg")], label: "Datteln, Ahorn, Ahornweg")
        XCTAssertEqual(sector.repairedSearchTextLabel(), "Datteln, Ahornweg")
        // Müllmax-Direktsprung aus Build 12 (2.0.9): Name nur „2“ → getippter Text kommt zurück (die echte Straße kennt die alte
        // Auswahl nicht); mit gewählter Straße oder selbst vergebenem Namen bleibt alles, wie es ist
        let jump = SourceConfiguration(providerKind: .muellmax, serviceKey: "Usb", selections: [Self.typed("Kortum"), Self.option("hnr:5", "2")], label: "2")
        XCTAssertEqual(jump.repairedSearchTextLabel(), "Kortum, 2")
        let withStreet = SourceConfiguration(providerKind: .muellmax, serviceKey: "Usb",
                                             selections: [Self.typed("Kortum"), Self.option("str:5", "Kortumstraße"), Self.option("hnr:2", "2")], label: "Kortumstraße, 2")
        XCTAssertNil(withStreet.repairedSearchTextLabel())
        var ownJump = jump
        ownJump.label = "Büro"
        XCTAssertNil(ownJump.repairedSearchTextLabel())
        // Andere Anbieter fasst die Reparatur nicht an
        let other = SourceConfiguration(providerKind: .portalsSachsen, serviceKey: "dresden", selections: selections, label: "Hamburger Str., Hamburger Straße, 10")
        XCTAssertNil(other.repairedSearchTextLabel())
    }

    /// Müllmax Bochum (live 12.11.): Findet das Portal genau eine Straße, folgen gleich die Hausnummern – der getippte Text
    /// ist dann die einzige Straßenangabe und muss im Namen bleiben (sonst hieße der Standort nur „2“).
    func testMuellmaxKeepsTypedStreetWithoutStreetList() {
        let provider = MuellmaxProvider(service: "Usb")
        XCTAssertEqual(provider.label(for: [Self.typed("Kortum"), Self.option("hnr:2|straße:Kortumstraße", "2")]), "Kortumstraße, 2")
        // Ohne Adresskopf bleibt der getippte Text die einzige Straßenangabe
        XCTAssertEqual(provider.label(for: [Self.typed("Kortum"), Self.option("hnr:2", "2")]), "Kortum, 2")
        // Adresskopf der echten Seite (EB Mainz, Suche „Haupt“, 12.11.2026)
        let head = "<div class=\"m_symadr\">\n\t\t\t\t\t<strong>Abfuhrtermine</strong><br />Hauptstraße<br />Mainz\n\t\t\t\t</div>"
        XCTAssertEqual(MuellmaxProvider.chosenStreet(in: head), "Hauptstraße")
        XCTAssertEqual(provider.label(for: [Self.typed("Kortum"), Self.option("str:5", "Kortumstraße"), Self.option("hnr:2", "2")]), "Kortumstraße, 2")
    }

    /// Wächter: Jeder Texteingabe-Schritt (`.text(title:`) in den Anbietern ist hier gezählt. Kommt einer dazu oder fällt einer weg,
    /// wird der Test rot. Dann prüfen: Folgt auf die Eingabe eine Trefferliste? Dann gehört ein Fall in `cases` (sonst landet der
    /// Suchtext im Standortnamen, Leipzig 11.11.2026). Endet der Assistent mit der Eingabe (Hausnummer, ICS-Link), ist sie Teil der
    /// Adresse und braucht keinen Fall. Danach die Zahl hier anpassen.
    static let textSteps: [String: Int] = [
        "AWMMuenchenProvider.swift": 1,          // Hausnummer am Ende
        "AbfallPlusAppProvider.swift": 3,        // Fall abfallPlusApp (ein geteilter Schritt, zwei Verwendungen)
        "BayernPortalsProvider.swift": 2,        // Fälle fuerth, landkreis_as
        "BuergerportalProvider.swift": 1,        // Hausnummer am Ende
        "CTraceProvider.swift": 3,               // Ort, Straße, Hausnummer getippt, keine Trefferliste danach
        "CityProviders.swift": 5,                // Fälle koeln (2), leipzig, hannover (2)
        "Einzelportale.swift": 4,                // Fall giessen, sonst Hausnummer am Ende
        "HausmuellInfoProvider.swift": 1,        // Fall erfurt
        "ICSURLProvider.swift": 1,               // ICS-Link
        "InsertITProvider.swift": 1,             // Fall offenbach
        "MagdeburgProvider.swift": 1,            // Hausnummer am Ende
        "MecklenburgPortalsProvider.swift": 2,   // Fall rostock
        "MuellmaxProvider.swift": 1,             // Fall muellmax
        "NRWPortalsProvider.swift": 7,           // Fälle awista, awg, sector27
        "NRWStadtportale.swift": 4,              // Fall herten, sonst Hausnummer bzw. ganze Adresse am Ende
        "NordPortalsProvider.swift": 6,          // Fälle hamburg, bremerhaven, kiel, heidekreis (geteilter Schritt, vier Verwendungen)
        "RegionalProviders.swift": 2,            // Fall bsr
        "SachsenPortalsProvider.swift": 1,       // Fall dresden
        "SuedwestPortalsProvider.swift": 9,      // Fälle frankfurt, stuttgart, wiesbaden, heidenheim, floersheim
        "WasteManagementServletProvider.swift": 1, // Hausnummer am Ende
    ]

    /// „    static var streetSearchStep: SelectionStep {“ → „streetSearchStep“
    static func sharedStepName(_ line: String) -> String? {
        guard let match = line.range(of: #"var \w+: SelectionStep \{"#, options: .regularExpression) else { return nil }
        return String(line[match].dropFirst(4).prefix { $0 != ":" })
    }

    func testEveryTextStepIsReviewed() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TonneCore/Providers")
        var found: [String: Int] = [:]
        for file in try FileManager.default.contentsOfDirectory(atPath: dir.path) where file.hasSuffix(".swift") {
            let source = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            let lines = source.components(separatedBy: "\n")
            var count = lines.filter { $0.contains(".text(title") && !$0.contains("static func") }.count
            // Geteilte Schritte („var streetSearchStep: SelectionStep { .text(title: …) }“): jede Verwendung zählt als eigener Schritt,
            // sonst bliebe ein weiterer Dienst, der denselben Schritt nutzt, unbemerkt (Prüfung 12.11.2026)
            for (index, line) in lines.enumerated() {
                guard let name = Self.sharedStepName(line), lines[index...].prefix(3).contains(where: { $0.contains(".text(title") }) else { continue }
                count += lines.filter { $0.range(of: "\\b\(name)\\b", options: .regularExpression) != nil }.count - 1
            }
            if count > 0 { found[file] = count }
        }
        XCTAssertFalse(found.isEmpty, "Quelltext nicht gefunden: \(dir.path)")
        XCTAssertEqual(found, Self.textSteps, "Texteingabe-Schritte geändert: Fall in `cases` ergänzen oder begründen, dann `textSteps` anpassen")
    }

    /// Ganzer Weg ohne Netz: Müllmax springt nach „Kortum“ gleich zu den Hausnummern. Die Straße aus dem Adresskopf muss in der
    /// Kennung der Hausnummer landen (nicht im Untertitel, der die Suche verfälscht), und die Abfrage schickt nur die Nummer.
    func testMuellmaxDirectJumpCarriesStreetOffline() async throws {
        let provider = MuellmaxProvider(service: "Usb", client: HTTPClient(session: MuellmaxStub.session()))
        let typed = Self.typed("Kortum")
        let step = try await provider.nextStep(after: [typed])
        let numbers = try XCTUnwrap(step?.options)
        XCTAssertEqual(numbers.map(\.title), ["2", "2a", "12"])
        XCTAssertTrue(numbers.allSatisfy { $0.subtitle == nil }, "Straße gehört nicht in den Untertitel")
        XCTAssertEqual(provider.label(for: [typed, numbers[1]]), "Kortumstraße, 2a")
        _ = try await provider.nextStep(after: [typed, numbers[1]])
        XCTAssertTrue(MuellmaxStub.bodies().contains { $0.contains("mm_frm_hnr_sel=7") && !$0.contains("Kortum%C3%9F") && !$0.contains("stra") },
                      "Hausnummer-Abfrage muss nur die Nummer schicken: \(MuellmaxStub.bodies())")
    }

    func testKoelnLabelUsesTheFoundAddress() {
        let selections = [Self.typed("Aachener Str."), Self.typed("50"), Self.option("addr:1234:50", "Aachener Straße 50")]
        XCTAssertEqual(AWBKoelnProvider().label(for: selections), "Köln, Aachener Straße 50")
    }
}

/// Müllmax-Seite nach der Straßensuche „Kortum“: genau eine Straße, deshalb gleich die Hausnummern.
final class MuellmaxStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []

    static func session() -> URLSession {
        lock.lock(); seen = []; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MuellmaxStub.self]
        return URLSession(configuration: config)
    }

    static func bodies() -> [String] { lock.lock(); defer { lock.unlock() }; return seen }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.muellmax.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        Self.lock.lock(); Self.seen.append(String(decoding: body, as: UTF8.self)); Self.lock.unlock()
        let html = """
        <form><input type="hidden" name="mm_ses" value="abc">
        <div class="m_symadr">
            <strong>Abfuhrtermine</strong><br />Kortumstraße<br />Bochum
        </div>
        <select name="mm_frm_hnr_sel"><option value="">bitte wählen</option><option value="5">2</option><option value="7">2a</option><option value="9">12</option></select>
        </form>
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
