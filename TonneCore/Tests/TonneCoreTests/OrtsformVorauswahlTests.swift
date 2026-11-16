import XCTest
@testable import TonneCore

/// Prüfbefund 1 zu Paket D (16.11.2026): Die Zusatzwort-Sicherung las die Ortsform selbst als Zusatz. „Wasserburg am Inn“
/// verlor in der Remondis-Liste die Vorauswahl „Wasserburg“, weil „am“ Wortanfang von „Amerang“ ist; „Emmerich a. Rhein“
/// verlor „Emmerich am Rhein“ an „Aldenhoven“.
final class OrtsformVorauswahlTests: XCTestCase {
    /// Abfall+-Ortslisten der Apps aus `ap_places.txt`: „== <serviceKey> … n=<Anzahl> ['Ort', …]“.
    private func appLists() throws -> [String: [String]] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../tools/catalog/data/gapres/ap_places.txt")
        var lists: [String: [String]] = [:]
        for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") where line.hasPrefix("== ") {
            let key = String(line.dropFirst(3).prefix { $0 != " " })
            guard let open = line.range(of: "['", options: .backwards) else { continue }
            lists[key] = line[open.lowerBound...].dropFirst(2).dropLast(2).components(separatedBy: "', '")
        }
        return lists
    }

    private func cityStep(_ titles: [String]) -> SelectionStep {
        SelectionStep(title: SelectionStep.cityTitle, options: titles.map { SelectionOption(id: $0, title: $0) })
    }

    /// Echte Kette `servedPlace` → `preselection` über die echten App-Listen.
    func testLongOrShortFormThroughTheRealChainKeepsThePreselection() throws {
        let lists = try appLists()
        let cases: [(key: String, query: String, expected: String)] = [
            ("de.remondis.rheinland", "Wasserburg am Inn", "Wasserburg"),
            ("de.remondis.rheinland", "Rott am Inn", "Rott"),
            ("de.remondis.rheinland", "Flintsbach am Inn", "Flintsbach"),
            ("de.remondis.rheinland", "Nußdorf am Inn", "Nußdorf"),
            ("de.k4systems.muellalarm", "Emmerich a. Rhein", "Emmerich am Rhein"),
            ("de.k4systems.muellalarm", "Emmerich am Rhein", "Emmerich am Rhein"),
        ]
        for item in cases {
            let entry = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == item.key }, item.key)
            let titles = try XCTUnwrap(lists[item.key], item.key)
            let place = try XCTUnwrap(ProviderCatalog.servedPlace(for: entry, query: item.query), item.query)
            XCTAssertEqual(cityStep(titles).preselection(for: place, query: item.query)?.title, item.expected, "„\(item.query)“ (Gemeinde \(place))")
        }
    }

    /// AWIDO lra-mue mit Nachbar „Ampfing“ und Gegenproben: Kurzform gegen Langform, Ortsteil-Sicherung bleibt.
    func testJoinWordIsNoExtraWord() {
        XCTAssertEqual(cityStep(["Mühldorf a.Inn", "Ampfing"]).preselection(for: "Mühldorf a.Inn", query: "Mühldorf am Inn")?.title, "Mühldorf a.Inn")
        XCTAssertEqual(cityStep(["Hamm am Rhein", "Alzey"]).preselection(for: "Hamm am Rhein", query: "Hamm a. Rhein")?.title, "Hamm am Rhein")
        XCTAssertEqual(cityStep(["Bobenheim am Berg", "Bad Dürkheim"]).preselection(for: "Bobenheim am Berg", query: "Bobenheim a. Berg")?.title, "Bobenheim am Berg")
        XCTAssertEqual(cityStep(["Rutsweiler an der Lauter", "Dennweiler-Frohnbach"]).preselection(for: "Rutsweiler an der Lauter", query: "Rutsweiler a.d. Lauter")?.title, "Rutsweiler an der Lauter")
        // Gegenprobe: ein echtes Zusatzwort, das eine andere Option trägt, zeigt weiter die Liste
        XCTAssertNil(cityStep(["Mühldorf a.Inn", "Mühldorf Altmühldorf"]).preselection(for: "Mühldorf a.Inn", query: "Mühldorf am Inn Altmühl"))
    }

    /// Messung „Gemeinde Ortsteil“ (Ortsteil ohne eigene Option, Optionen = Gemeinden des Kreises): 296 von 59.795 Suchen
    /// verloren die Gemeinde, weil ein Zusatzwort nur Wortanfang einer fremden Gemeinde war („Nord“ in „Nordermeldorf“).
    func testLocalityWordIsNoPrefixOfAForeignOption() {
        XCTAssertEqual(cityStep(["Brunsbüttel", "Nordermeldorf"]).preselection(for: "Brunsbüttel", query: "Brunsbüttel Brunsbüttel-Nord")?.title, "Brunsbüttel")
        XCTAssertEqual(cityStep(["Groß Grönau", "Klein Wesenberg"]).preselection(for: "Groß Grönau", query: "Groß Grönau Klein Grönau")?.title, "Groß Grönau")
        XCTAssertEqual(cityStep(["Hemmingstedt", "Hellschen-Heringsand-Unterschaar"]).preselection(for: "Hemmingstedt", query: "Hemmingstedt Op de Hell")?.title, "Hemmingstedt")
        // Gegenproben: Die Suche nennt eine fremde Option ganz, oder den Wortanfang einer Option mit der Gemeinde
        XCTAssertNil(cityStep(["Sankt Annen", "Neufeld"]).preselection(for: "Sankt Annen", query: "Sankt Annen Sankt Annen-Neufeld"))
        XCTAssertNil(cityStep(["Grabow", "Ziegelscheune"]).preselection(for: "Grabow", query: "Grabow Ziegelscheune"))
    }

    /// Näherung über alle Gemeinden mit amtlicher Kurzform (Optionen = Gemeinden des Kreises): Die Langform-Suche wählt die
    /// Gemeinde, ebenso die Kurzform-Suche bei amtlicher Langform. Nie eine andere Option.
    func testEveryLongAndShortFormOfAMunicipalityIsPreselected() {
        let byDistrict = Dictionary(grouping: MunicipalityIndex.all, by: \.district)
        var checked = 0, missed: [String] = [], wrong: [String] = []
        func check(_ item: MunicipalityIndex.Item, query: String) {
            let hits = ProviderCatalog.municipalities(matching: query).filter { $0.district == item.district }
            guard Set(hits.map(\.name)) == [item.name] else { return }
            let step = cityStep(byDistrict[item.district]!.map(\.name))
            // Nur wo die Gemeinde auch ohne Suche vorausgewählt wäre (gleichnamige Gemeinden im Kreis zählen nicht)
            guard step.preselection(for: item.name)?.title == item.name else { return }
            checked += 1
            switch step.preselection(for: item.name, query: query)?.title {
            case item.name?: break
            case nil: missed.append(query)
            case let other?: wrong.append("\(query) → \(other)")
            }
        }
        for item in MunicipalityIndex.all {
            let long = MunicipalityIndex.longForm(item.folded)
            if long != item.folded { check(item, query: long) }
            for (full, short) in [(" am ", " a. "), (" im ", " i. "), (" an der ", " a.d. "), (" in der ", " i.d. "), (" bei ", " b. ")] where item.folded.contains(full) {
                check(item, query: item.folded.replacingOccurrences(of: full, with: short))
            }
        }
        XCTAssertGreaterThan(checked, 400)
        XCTAssertEqual(missed, [], "Langform/Kurzform ohne Vorauswahl")
        XCTAssertEqual(wrong, [], "andere Option gewählt")
    }
}
