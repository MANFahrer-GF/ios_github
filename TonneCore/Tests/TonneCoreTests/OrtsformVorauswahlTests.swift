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

    /// Prüfbefund A zu Paket E: Ein halb genannter Ortsteil wählte die Gemeinde. Echte Kette über die LWL-Liste: „Dömitz
    /// Schmölen“ meint „Groß Schmölen“ oder „Klein Schmölen“, „Sternberg Raden“ meint „Groß Raden“ – Liste statt Gemeinde.
    func testHalfNamedLocalityShowsTheList() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../tools/catalog/data/gemos/lwl_places.txt")
        let titles = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let lwl = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == "lwl" })
        let step = SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: titles.map { SelectionOption(id: $0, title: $0) })
        for (query, municipality) in [("Dömitz Schmölen", "Dömitz"), ("Sternberg Raden", "Sternberg"), ("Techentin Hagen", "Techentin"),
                                      ("Neu Poserin OT Groß Poserin", "Neu Poserin")] {
            let place = try XCTUnwrap(ProviderCatalog.servedPlace(for: lwl, query: query), query)
            XCTAssertEqual(place, municipality, query)
            XCTAssertNil(step.preselection(for: place, query: query), "„\(query)“ wählte die Gemeinde")
        }
        // Gegenprobe: die Gemeinde allein und ein Ortsteil ohne eigene Option wählen weiter die Gemeinde
        XCTAssertEqual(step.preselection(for: "Dömitz", query: "Dömitz")?.title, "Dömitz")
        XCTAssertEqual(step.preselection(for: "Sternberg", query: "Sternberg Vaihingen")?.title, "Sternberg")
    }

    /// Gegenprobe zu Prüfbefund A über die echten Gemeinden des Kreises: Halb genannt reicht nur bei einem Ortsteil der
    /// gesuchten Gemeinde. „Wester-Ohrstedt Ohrstedt“ meint nicht die Gemeinde „Oster-Ohrstedt“. Und „Hüsby“ wählt „Hüsby“,
    /// nicht das gleich gefaltete „Husby“ (in allen früheren Ständen falsch).
    func testHalfNamedMunicipalityOfTheDistrictKeepsThePlace() throws {
        func district(of name: String) throws -> SelectionStep {
            let item = try XCTUnwrap(MunicipalityIndex.all.first { $0.name == name }, name)
            return cityStep(MunicipalityIndex.all.filter { $0.district == item.district }.map(\.name))
        }
        let nordfriesland = try district(of: "Wester-Ohrstedt")
        XCTAssertTrue(nordfriesland.options.contains { $0.title == "Oster-Ohrstedt" })
        XCTAssertEqual(nordfriesland.preselection(for: "Wester-Ohrstedt", query: "Wester-Ohrstedt Ohrstedt")?.title, "Wester-Ohrstedt")
        let schleswig = try district(of: "Hüsby")
        XCTAssertTrue(schleswig.options.contains { $0.title == "Husby" })
        XCTAssertEqual(schleswig.preselection(for: "Hüsby", query: "Hüsby Kroy")?.title, "Hüsby")
        XCTAssertEqual(schleswig.preselection(for: "Husby")?.title, "Husby")
    }

    /// Prüfbefund A, zweite Spielart: Die Wörter der Gemeinde zählen in der Suche nur einmal. „Dessau-Roßlau Roßlau (Elbe)“
    /// nennt den Ortsteil „Roßlau (Elbe)“ ganz (Ortsteile laut Ortsteil-Liste als eigene Optionen).
    func testMunicipalityWordsCountOnceInTheSearch() throws {
        for (municipality, locality) in [("Dessau-Roßlau", "Roßlau (Elbe)"), ("Weimar (Lahn)", "Roth (Lahn)")] {
            XCTAssertTrue((LocalityIndex.byName[ProviderCatalog.fold(locality)] ?? []).contains { $0.municipality == municipality }, locality)
            let step = cityStep([municipality, locality])
            XCTAssertNil(step.preselection(for: municipality, query: "\(municipality) \(locality)"), locality)
            XCTAssertEqual(step.preselection(for: municipality, query: municipality)?.title, municipality, "Gegenprobe")
        }
    }

    /// In allen früheren Ständen falsch: Ein Ortsteil, der den Gemeindenamen trägt, wählte die Gemeinde
    /// („Amt Wachsenburg Wachsenburg“, „Storbeck-Frankendorf Frankendorf (Storbeck-Frankendorf)“). Dieselbe Gemeinde in
    /// anderer Schreibung als Ortsteil („Alt Mölln“) wählt weiter die Gemeinde.
    func testLocalityCarryingTheMunicipalityNameShowsTheList() {
        for (municipality, locality, query) in [("Amt Wachsenburg", "Wachsenburg", "Amt Wachsenburg Wachsenburg"),
                                                ("Amt Creuzburg", "Creuzburg", "Amt Creuzburg Creuzburg"),
                                                ("Storbeck-Frankendorf", "Frankendorf (Storbeck-Frankendorf)", "Storbeck-Frankendorf Frankendorf (Storbeck-Frankendorf)")] {
            XCTAssertTrue((LocalityIndex.byName[ProviderCatalog.fold(locality)] ?? []).contains { $0.municipality == municipality }, locality)
            XCTAssertNil(cityStep([municipality, locality]).preselection(for: municipality, query: query), query)
            XCTAssertEqual(cityStep([municipality, locality]).preselection(for: municipality, query: municipality)?.title, municipality, "Gegenprobe")
        }
        XCTAssertTrue((LocalityIndex.byName[ProviderCatalog.fold("Alt Mölln")] ?? []).contains { $0.municipality == "Alt-Mölln" })
        XCTAssertEqual(cityStep(["Alt-Mölln", "Alt Mölln"]).preselection(for: "Alt-Mölln", query: "Alt-Mölln Alt Mölln")?.title, "Alt-Mölln")
    }

    /// Prüfbefund C zu Paket E: Ein einzelner Buchstabe ohne Punkt („Rieden a“) wählte die Gemeinde, obwohl der Eintrag auch
    /// „Rieden am Forggensee“ führt. Echte Kette über die belegten Orte der Einträge; mit Punkt kam schon die Liste.
    func testSingleLetterWithoutDotIsNoExtraWord() throws {
        for (query, names) in [("Rieden a", ["Rieden", "Rieden am Forggensee"])] {
            func served(_ entry: CatalogEntry) -> [String] {
                Array(Set((EntryPlacesIndex.pairs[entry.id] ?? []).map { String($0.split(separator: "|", maxSplits: 1).last ?? "") })).sorted()
            }
            let entry = try XCTUnwrap(ProviderCatalog.entries.first { entry in names.allSatisfy(served(entry).contains) }, query)
            let place = try XCTUnwrap(ProviderCatalog.servedPlace(for: entry, query: query), query)
            let step = cityStep(served(entry))
            XCTAssertNil(step.preselection(for: place, query: query), "„\(query)“ (Gemeinde \(place))")
            XCTAssertNil(step.preselection(for: place, query: query + "."), "mit Punkt")
            XCTAssertEqual(step.preselection(for: names[1], query: names[1])?.title, names[1], "Gegenprobe Langform")
        }
        // Bundesweit gleicher Kern: alle Gemeinden „Simbach …“ bzw. „Neukirch …“ als Optionen
        for (query, core) in [("Simbach i", "simbach"), ("Neukirch a", "neukirch")] {
            let names = Array(Set(MunicipalityIndex.all.map(\.name).filter { SelectionStep.placeCore($0) == core })).sorted()
            let place = try XCTUnwrap(names.first { SelectionStep.spelling($0) == core }, core)
            XCTAssertGreaterThan(names.count, 1, core)
            XCTAssertNil(cityStep(names).preselection(for: place, query: query), query)
            XCTAssertEqual(cityStep(names).preselection(for: place, query: place)?.title, place, "Gegenprobe \(place)")
        }
    }

    /// Prüfbefund D zu Paket E: Zusatz nur aus Bindewort oder Abkürzung ist kein Zusatz der Gemeinde (Kusel).
    func testJoinWordOrAbbreviationAloneKeepsTheList() {
        let kusel = SelectionStep(title: L10n.t("Ortsgemeinde", "Municipality"), options: ["Kusel", "Rutsweiler/Glan", "Rutsweiler/Lauter"]
            .map { SelectionOption(id: $0, title: $0) })
        XCTAssertNil(kusel.preselection(for: "Rutsweiler am Glan", query: "Rutsweiler a."))
        XCTAssertNil(kusel.preselection(for: "Rutsweiler am Glan", query: "Rutsweiler an der"))
        XCTAssertEqual(kusel.preselection(for: "Rutsweiler am Glan", query: "Rutsweiler a. Glan")?.title, "Rutsweiler/Glan")
    }
}
