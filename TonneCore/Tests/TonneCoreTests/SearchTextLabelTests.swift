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
        // Andere Anbieter fasst die Reparatur nicht an
        let other = SourceConfiguration(providerKind: .portalsSachsen, serviceKey: "dresden", selections: selections, label: "Hamburger Str., Hamburger Straße, 10")
        XCTAssertNil(other.repairedSearchTextLabel())
    }

    /// Müllmax Bochum (live 12.11.): Findet das Portal genau eine Straße, folgen gleich die Hausnummern – der getippte Text
    /// ist dann die einzige Straßenangabe und muss im Namen bleiben (sonst hieße der Standort nur „2“).
    func testMuellmaxKeepsTypedStreetWithoutStreetList() {
        let provider = MuellmaxProvider(service: "Usb")
        XCTAssertEqual(provider.label(for: [Self.typed("Kortum"), Self.option("hnr:2", "2", "Kortumstraße")]), "Kortumstraße, 2")
        // Ohne Adresskopf bleibt der getippte Text die einzige Straßenangabe
        XCTAssertEqual(provider.label(for: [Self.typed("Kortum"), Self.option("hnr:2", "2")]), "Kortum, 2")
        // Adresskopf der echten Seite (EB Mainz, Suche „Haupt“, 12.11.2026)
        let head = "<div class=\"m_symadr\">\n\t\t\t\t\t<strong>Abfuhrtermine</strong><br />Hauptstraße<br />Mainz\n\t\t\t\t</div>"
        XCTAssertEqual(MuellmaxProvider.chosenStreet(in: head), "Hauptstraße")
        XCTAssertEqual(provider.label(for: [Self.typed("Kortum"), Self.option("str:5", "Kortumstraße"), Self.option("hnr:2", "2")]), "Kortumstraße, 2")
    }

    func testKoelnLabelUsesTheFoundAddress() {
        let selections = [Self.typed("Aachener Str."), Self.typed("50"), Self.option("addr:1234:50", "Aachener Straße 50")]
        XCTAssertEqual(AWBKoelnProvider().label(for: selections), "Köln, Aachener Straße 50")
    }
}
