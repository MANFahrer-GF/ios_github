import XCTest
@testable import TonneCore

/// Prüfpunkte zur Ortsteil-Suche und Müllmann-Anzeige (Advisor, 14.11.2026).
final class SuchPruefpunkteTests: XCTestCase {
    private func entry(_ serviceKey: String) throws -> CatalogEntry {
        try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == serviceKey })
    }

    /// Die Müllmann-App hieß „Müllmann-App (Landkreis Konstanz, Karlsruhe)“ und traf „Landkreis Konstanz“ über den Titel.
    /// Seit sie nur noch „Müllmann-App“ heißt, findet der Kreisname sie über die belegte Zuordnung.
    func testKreisnameFindetMuellmann() throws {
        let muellmann = try entry("muellmann")
        for query in ["Landkreis Konstanz", "Kreis Konstanz", "landkreis konstanz"] {
            XCTAssertTrue(ProviderCatalog.search(query).contains(muellmann), query)
        }
        XCTAssertEqual(ProviderCatalog.districts(matching: ProviderCatalog.fold("Kreis Konstanz")), ["Landkreis Konstanz"])
        // Ein bloßer Ortsname ist kein Kreisname
        XCTAssertTrue(ProviderCatalog.districts(matching: "konstanz").isEmpty)
        // Stadtkreis über seinen Kreisnamen
        XCTAssertTrue(ProviderCatalog.search("Stadtkreis Karlsruhe").contains(muellmann))
    }

    /// „Führt X nicht“ nur, wenn der Eintrag die Gemeinde nicht selbst unter seinen Orten im selben Kreis nennt
    /// (Messung 14.11.: 2 Widersprüche bei 9.794 Gemeinden – TBR-App „Reutlingen“, EVS „Saarbrücken“).
    func testKeinNichtGegenEigeneOrtsangabe() throws {
        // Seit 16.11. belegt die Zuordnung die TBR-App für Reutlingen (das Kreisportal führt die Stadt ohne Straßen)
        XCTAssertEqual(ProviderCatalog.placeNote(for: try entry("de.abfallplus.tbrapp"), query: "Reutlingen"), "Führt Reutlingen")
        XCTAssertNil(ProviderCatalog.placeNote(for: try entry("Evs"), query: "Saarbrücken"))
        // Der Kreis-Eintrag nennt die Stadt nur im Titel – dort bleibt die Aussage (Thomas' Fall Karlsruhe).
        XCTAssertEqual(ProviderCatalog.placeNote(for: try entry("de.k4systems.abfallappka"), query: "Karlsruhe"), "Führt Karlsruhe nicht")
        // Namensvetter in einem anderen Kreis: der Ludwigslust-Parchimer Ortsteil „Heide“ ist nicht Heide in Dithmarschen
        XCTAssertEqual(ProviderCatalog.placeNote(for: try entry("lwl"), query: "Heide"), "Führt Heide nicht")
    }

    /// Allgemeine Ortsteilnamen („Thal“ in 36 Gemeinden, „Altstadt“ in 30) liefern allein keine Gemeinden.
    func testAllgemeinerOrtsteilnameLiefertKeineBeliebigenGemeinden() {
        for name in ["Thal", "Altstadt", "Bergham"] {
            XCTAssertTrue(ProviderCatalog.municipalities(matching: name).isEmpty, name)
            XCTAssertEqual(ProviderCatalog.municipalityHint(for: name)?.contains("bitte mit Gemeinde suchen"), true, name)
        }
        // Kein Ortsteilname liefert mehr als die Grenze
        for (name, _) in LocalityIndex.byName {
            XCTAssertLessThanOrEqual(ProviderCatalog.municipalities(matching: name).count, max(LocalityIndex.maxMunicipalities,
                ProviderCatalog.municipalityHits(name).count), name)
        }
        // Mit Gemeinde davor eindeutig
        XCTAssertEqual(ProviderCatalog.municipalities(matching: "Leipzig Gohlis").map(\.name), ["Leipzig"])
    }

    /// Die Gemeindesuche über die sortierte Liste liefert für jeden Gemeindenamen und jeden Wortanfang dasselbe wie die
    /// frühere lineare Suche über alle Gemeinden.
    func testSortierteGemeindesucheGleichLinear() {
        let all = MunicipalityIndex.all
        func linear(_ needle: String) -> [String] {
            let candidates = all.filter { $0.folded.hasPrefix(needle) }
            let exact = candidates.filter { $0.folded == needle }
            let hits = exact.isEmpty ? candidates.filter { !$0.folded[$0.folded.index($0.folded.startIndex, offsetBy: needle.count)].isLetter } : exact
            return (exact.isEmpty ? Array(hits.prefix(8)) : hits).map { "\($0.district)|\($0.name)" }
        }
        var needles = Set<String>()
        for item in all {
            needles.insert(item.folded)
            for index in item.folded.indices where !item.folded[index].isLetter {
                let start = String(item.folded[..<index])
                if start.count >= 3 { needles.insert(start) }
            }
        }
        var mismatches: [String] = []
        for needle in needles.sorted() {
            let sorted = ProviderCatalog.municipalityHits(needle).map { "\($0.district)|\($0.name)" }
            if sorted != linear(needle) { mismatches.append(needle) }
        }
        XCTAssertGreaterThan(needles.count, 10_000)
        XCTAssertEqual(mismatches, [], "\(mismatches.prefix(20))")
    }

    /// Vorauswahl nur im Gemeinde-Schritt: Ein Straßen- oder Bezirksschritt mit gleichnamigem Eintrag wird nicht übersprungen.
    func testVorauswahlNurImOrtSchritt() {
        let options = [SelectionOption(id: "1", title: "Karlsruhe"), SelectionOption(id: "2", title: "Konstanz")]
        XCTAssertEqual(SelectionStep(title: SelectionStep.cityTitle, options: options).preselection(for: "Karlsruhe")?.id, "1")
        XCTAssertEqual(SelectionStep(title: L10n.t("Gemeinde", "Municipality"), options: options).preselection(for: "karlsruhe")?.id, "1")
        XCTAssertNil(SelectionStep(title: SelectionStep.streetTitle, options: options).preselection(for: "Karlsruhe"))
        XCTAssertNil(SelectionStep(title: L10n.t("Abfuhrbezirk", "Collection district"), options: options).preselection(for: "Karlsruhe"))
        XCTAssertNil(SelectionStep(title: SelectionStep.cityTitle, options: options).preselection(for: "Singen (Hohentwiel)"))
    }

    /// Gemeinde-Prüfung 16.11.2026: Portale schreiben den Ort mit Vorsilbe oder ohne amtlichen Zusatz. Die Suche wählte
    /// „Saal a.d.Donau“ in Kelheims Liste („Gemeinde Saal“) nicht vor, der Nutzer musste selbst suchen.
    func testVorauswahlKenntVorsilbenUndZusaetze() {
        let kelheim = SelectionStep(title: SelectionStep.cityTitle, options: ["Gemeinde Saal", "Stadt Neustadt", "Markt Bad Abbach", "Stadt Kelheim"]
            .enumerated().map { SelectionOption(id: "\($0.offset)", title: $0.element) })
        XCTAssertEqual(kelheim.preselection(for: "Saal a.d.Donau")?.title, "Gemeinde Saal")
        XCTAssertEqual(kelheim.preselection(for: "Neustadt a.d.Donau")?.title, "Stadt Neustadt")
        XCTAssertEqual(kelheim.preselection(for: "Bad Abbach")?.title, "Markt Bad Abbach")
        let landshut = SelectionStep(title: SelectionStep.cityTitle, options: ["Neufahrn i. Ndb.", "Bayerbach b. Erg.", "Ergoldsbach"]
            .enumerated().map { SelectionOption(id: "\($0.offset)", title: $0.element) })
        XCTAssertEqual(landshut.preselection(for: "Neufahrn i.NB")?.title, "Neufahrn i. Ndb.")
        XCTAssertEqual(landshut.preselection(for: "Bayerbach b.Ergoldsbach")?.title, "Bayerbach b. Erg.")
        let hildburghausen = SelectionStep(title: SelectionStep.cityTitle, options: [SelectionOption(id: "1", title: "Brünn"), SelectionOption(id: "2", title: "Eisfeld")])
        XCTAssertEqual(hildburghausen.preselection(for: "Brünn/Thür.")?.title, "Brünn")
        // Potsdam-Mittelmark: Schritt „Gemeinde / Ortsteil“ ist ein Ortsschritt
        let apm = SelectionStep(title: L10n.t("Gemeinde / Ortsteil", "Town / district"), options: [SelectionOption(id: "1", title: "Beelitz (Stadt)"), SelectionOption(id: "2", title: "Beelitz-Heilstätten")])
        XCTAssertEqual(apm.preselection(for: "Beelitz")?.title, "Beelitz (Stadt)")
        // Punkt 6: „St.“ für „Sankt“ (KAW Mainz-Bingen), Zusatz mit „mit“/„ohne“ (AWB Bad Dürkheim)
        let kaw = SelectionStep(title: SelectionStep.cityTitle, options: ["Sprendlingen", "St.Johann", "Welgesheim"]
            .enumerated().map { SelectionOption(id: "\($0.offset)", title: $0.element) })
        XCTAssertEqual(kaw.preselection(for: "Sankt Johann")?.title, "St.Johann")
        let lambrecht = SelectionStep(title: SelectionStep.cityTitle, options: ["Altleiningen mit Neuleiningen Tal", "Frankeneck mit Iptestal Erfenstein und Sattelmühle",
                                                                                 "Lambrecht ohne Iptestal und Dörrental", "Lindenberg mit Lambrecht-Dörrental", "Neuleiningen"]
            .enumerated().map { SelectionOption(id: "\($0.offset)", title: $0.element) })
        XCTAssertEqual(lambrecht.preselection(for: "Altleiningen")?.title, "Altleiningen mit Neuleiningen Tal")
        XCTAssertEqual(lambrecht.preselection(for: "Frankeneck")?.title, "Frankeneck mit Iptestal Erfenstein und Sattelmühle")
        // „ohne“ schließt Teile der Gemeinde aus (Dörrental liegt bei „Lindenberg mit Lambrecht-Dörrental“): Liste (Prüfbefund 14)
        XCTAssertNil(lambrecht.preselection(for: "Lambrecht (Pfalz)"))
        XCTAssertEqual(lambrecht.preselection(for: "Lambrecht ohne Iptestal und Dörrental")?.title, "Lambrecht ohne Iptestal und Dörrental")
        XCTAssertEqual(lambrecht.preselection(for: "Neuleiningen")?.title, "Neuleiningen")
        // Gleicher Kern, Zusatz nach „/“ entscheidet (Kusel)
        let rutsweiler = SelectionStep(title: L10n.t("Ortsgemeinde", "Municipality"), options: ["Rutsweiler/Glan", "Rutsweiler/Lauter", "Kusel"]
            .enumerated().map { SelectionOption(id: "\($0.offset)", title: $0.element) })
        XCTAssertEqual(rutsweiler.preselection(for: "Rutsweiler am Glan")?.title, "Rutsweiler/Glan")
        XCTAssertEqual(rutsweiler.preselection(for: "Rutsweiler an der Lauter")?.title, "Rutsweiler/Lauter")
        var found = false
        XCTAssertEqual(PortalHealthLiveTests.pick(rutsweiler.options, wanted: "Rutsweiler an der Lauter", found: &found).title, "Rutsweiler/Lauter")
        // Gegenproben: mehrdeutiger Kern und Ortsteil mit Bindestrich wählen nichts vor
        let kusel = SelectionStep(title: SelectionStep.cityTitle, options: [SelectionOption(id: "1", title: "Stadt Breitenbach"), SelectionOption(id: "2", title: "Gemeinde Breitenbach")])
        XCTAssertNil(kusel.preselection(for: "Breitenbach a.Herzberg"))
        let glan = SelectionStep(title: SelectionStep.cityTitle, options: [SelectionOption(id: "1", title: "Altenglan - Mühlbach")])
        XCTAssertNil(glan.preselection(for: "Altenglan"))
    }

    /// Prüfer 14.11.: „Führt X nicht“ stand unter dem Eintrag, der die Stadt führt – bei Namensvettern mit Zusatz und bei
    /// Einträgen, die den getippten Ort selbst nennen.
    func testKeinNichtBeiNamensvetternOderEigenemOrt() throws {
        let cases: [(String, String)] = [
            ("frankenthal", "Frankenthal"), ("https://ruedesheim.mein-abfallkalender.online", "Rüdesheim"),
            ("Efb", "Friedberg"), ("de.k4systems.abfallhr", "Borken"),
            ("de.idcontor.abfalllu", "Ludwigshafen"), ("rlk_nastaetten_lautert", "Münchenroth"),
        ]
        for (key, query) in cases {
            XCTAssertNil(ProviderCatalog.placeNote(for: try entry(key), query: query), query)
        }
    }

    /// Prüfer 14.11.: „Halle Saale“, „Winsen Luhe“ … landeten beim gleichnamigen Ort ohne Zusatz (Rückschritt zu 2.0.10).
    func testZusatzWaehltDenRichtigenNamensvetter() {
        func names(_ query: String) -> [String] { ProviderCatalog.municipalities(matching: query).map(\.name) }
        XCTAssertEqual(names("Halle Saale"), ["Halle (Saale)"])
        XCTAssertEqual(names("Winsen Luhe"), ["Winsen (Luhe)"])
        XCTAssertEqual(names("Frankenthal Pfalz"), ["Frankenthal (Pfalz)"])
        XCTAssertEqual(names("Halle Westfalen"), ["Halle (Westf.)"])
        // Rechts eine eigene Gemeinde oder ein Kreiswort: keine Gemeinde, die Volltextsuche übernimmt
        XCTAssertEqual(names("Weimar Lahn"), ["Weimar (Lahn)"])
        XCTAssertEqual(names("Langenfeld Rheinland"), ["Langenfeld (Rhld.)"])
        for query in ["Darmstadt-Dieburg", "Lüchow-Dannenberg", "München Landkreis"] {
            XCTAssertEqual(names(query), [], query)
        }
        XCTAssertEqual(ProviderCatalog.search("Lüchow-Dannenberg").first?.title, "Landkreis Lüchow-Dannenberg")
        XCTAssertEqual(ProviderCatalog.search("Weimar Lahn").first?.title, "Gemeinde Weimar (Lahn) – Abfallkalender")
        XCTAssertEqual(ProviderCatalog.search("Halle Saale").first?.title, "Halle (Saale) – HWS Entsorgungskalender")
    }

    /// Prüfer 14.11.: Voller Kreisname trifft nur diesen Kreis.
    func testVollerKreisnameNurDieserKreis() throws {
        XCTAssertEqual(ProviderCatalog.districts(matching: "stadtkreis karlsruhe"), ["Stadtkreis Karlsruhe"])
        XCTAssertFalse(ProviderCatalog.search("Stadtkreis Karlsruhe").contains(try entry("de.k4systems.abfallappka")))
        XCTAssertEqual(ProviderCatalog.districts(matching: "kreis karlsruhe"), ["Landkreis Karlsruhe", "Stadtkreis Karlsruhe"])
    }

    /// Prüfer 14.11.: Gemeinden in Langform („Altenstadt an der Waldnaab“) sind keine Ortsteile von Nachbargemeinden.
    func testLangformFindetDieGemeinde() {
        XCTAssertEqual(ProviderCatalog.municipalities(matching: "Altenstadt an der Waldnaab").map(\.name), ["Altenstadt a.d.Waldnaab"])
        XCTAssertEqual(ProviderCatalog.municipalities(matching: "Garching bei München").map(\.name), ["Garching b.München"])
        XCTAssertFalse(ProviderCatalog.municipalityHint(for: "Altenstadt an der Waldnaab")?.contains("Störnstein") ?? false)
        XCTAssertNil(LocalityIndex.byName["altenstadt an der waldnaab"])
    }

    /// Nachprüfung 14.11.: Ortsteile, die wie eine andere Gemeinde heißen, führen weiter zur Gemeinde links; Namensvetter nur
    /// bei ganz passendem Zusatz, nicht beim Anfangsbuchstaben.
    func testGemeindeOrtsteilUndGanzerZusatz() {
        func names(_ query: String) -> [String] { ProviderCatalog.municipalities(matching: query).map(\.name) }
        for (query, city) in [("Berlin-Lichtenberg", "Berlin"), ("Hamburg-Eppendorf", "Hamburg"), ("Hamburg Eppendorf", "Hamburg"),
                              ("Duisburg-Rheinhausen", "Duisburg"), ("Hannover-Linden", "Hannover"), ("Dortmund Brackel", "Dortmund"),
                              ("Aachen-Brand", "Aachen"), ("Hamm Schmehausen", "Hamm"), ("Hamm S", "Hamm"), ("Borken H", "Borken")] {
            let found = names(query)
            XCTAssertTrue(!found.isEmpty && found.allSatisfy { $0 == city }, "\(query) → \(found)")
            XCTAssertFalse(ProviderCatalog.search(query).isEmpty, query)
        }
        XCTAssertEqual(names("Neustadt Weinstraße"), ["Neustadt an der Weinstraße"])
        XCTAssertEqual(names("Neustadt Holstein"), ["Neustadt in Holstein"])
        XCTAssertEqual(names("Neustadt Donau"), ["Neustadt a.d.Donau"])
        XCTAssertEqual(names("Landau Isar"), ["Landau a.d.Isar"])
        XCTAssertEqual(names("Aschau Inn"), ["Aschau a.Inn"])
        XCTAssertEqual(names("Königstein Taunus"), ["Königstein im Taunus"])
        XCTAssertFalse(names("Frankfurt Osthafen").contains("Frankfurt (Oder)"))
        XCTAssertEqual(names("Borken Singlis"), ["Borken (Hessen)"])
        XCTAssertEqual(names("Kirchheim Teck"), ["Kirchheim unter Teck"])
        XCTAssertEqual(names("Haag OB"), ["Haag i.OB"])
        XCTAssertEqual(names("Rothenburg Tauber"), ["Rothenburg ob der Tauber"])
    }

    /// Nachprüfung 14.11.: Trifft die Eingabe genau einen Namensvetter mit Zusatz, bleibt „Führt X nicht“ möglich.
    func testNichtBeiEindeutigemZusatz() {
        let hits = ProviderCatalog.municipalities(matching: "Lingen")
        XCTAssertEqual(hits.map(\.name), ["Lingen (Ems)"])
        let notes = ProviderCatalog.entries.compactMap { ProviderCatalog.placeNote(for: $0, query: "Lingen") }
        XCTAssertTrue(notes.contains("Führt Lingen (Ems) nicht"), "\(Set(notes))")
    }

    /// Vergleich mit 2.0.10 (14.11.): Kreisnamen ohne Vorsilbe und ganze Titelwörter behalten ihren Eintrag oben.
    func testKreisnameOhneVorsilbeUndGanzeTitelwoerter() {
        XCTAssertEqual(ProviderCatalog.districts(matching: "friesland"), ["Landkreis Friesland"])
        XCTAssertTrue(ProviderCatalog.districts(matching: "konstanz").isEmpty)
        XCTAssertNil(ProviderCatalog.municipalityHint(for: "Friesland"))
        XCTAssertEqual(ProviderCatalog.search("Friesland").first?.title, "MyMüll-App")
        XCTAssertEqual(ProviderCatalog.search("Ammerland").first?.title, "AWB Ammerland")
        XCTAssertEqual(ProviderCatalog.search("Bergstraße").first?.title, "Kreis Bergstraße")
        XCTAssertEqual(ProviderCatalog.search("Bebra Solz").first?.title, "Bebra: Solz (MZV)")
        XCTAssertEqual(ProviderCatalog.search("Darmstadt-Dieburg").first?.title, "Darmstadt-Dieburg (ZAW)")
        // Bloßer Gemeindename wie in 2.0.10: Kreis-Einträge nicht vor die belegten
        XCTAssertEqual(ProviderCatalog.search("Karlsruhe").first?.title, "Müllmann-App")
    }

    /// Prüfbefund 3: echte Kette `servedPlace` → `preselection`. Die bloße Suche „Rutsweiler“ passt auf zwei Gemeinden;
    /// `servedPlace` liefert eine davon, die Vorauswahl darf sie nicht still wählen.
    func testAmbiguousSearchThroughTheRealChainShowsTheList() throws {
        let kusel = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == "kusel" })
        let step = SelectionStep(title: L10n.t("Ortsgemeinde", "Municipality"), options: ["Kusel", "Rutsweiler/Glan", "Rutsweiler/Lauter"]
            .enumerated().map { SelectionOption(id: "\($0.offset)", title: $0.element) })
        func chain(_ query: String) -> String? {
            ProviderCatalog.servedPlace(for: kusel, query: query).flatMap { step.preselection(for: $0, query: query)?.title }
        }
        XCTAssertEqual(ProviderCatalog.servedPlace(for: kusel, query: "Rutsweiler am Glan"), "Rutsweiler am Glan")
        XCTAssertEqual(ProviderCatalog.servedPlace(for: kusel, query: "Rutsweiler an der Lauter"), "Rutsweiler an der Lauter")
        XCTAssertNil(ProviderCatalog.servedPlace(for: kusel, query: "Rutsweiler"), "zwei geführte Gemeinden: keine still wählen")
        // Auch wenn eine Gemeinde ankommt, wählt die Kurzform bei zwei Optionen gleichen Kerns nichts vor
        XCTAssertNil(step.preselection(for: "Rutsweiler am Glan", query: "Rutsweiler"))
        XCTAssertNil(chain("Rutsweiler"))
        XCTAssertEqual(chain("Rutsweiler am Glan"), "Rutsweiler/Glan")
        XCTAssertEqual(chain("Rutsweiler an der Lauter"), "Rutsweiler/Lauter")
        XCTAssertEqual(chain("Kusel"), "Kusel")
        // Bad Dürkheim: „Weisenheim“ = am Berg oder am Sand
        let duew = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == "awb-duerkheim" })
        let weisenheim = SelectionStep(title: SelectionStep.cityTitle, options: ["Weisenheim am Berg", "Weisenheim am Sand", "Bad Dürkheim"]
            .enumerated().map { SelectionOption(id: "\($0.offset)", title: $0.element) })
        XCTAssertNil(ProviderCatalog.servedPlace(for: duew, query: "Weisenheim"))
        XCTAssertEqual(ProviderCatalog.servedPlace(for: duew, query: "Weisenheim am Berg"), "Weisenheim am Berg")
        XCTAssertNil(weisenheim.preselection(for: "Weisenheim am Berg", query: "Weisenheim"))
        XCTAssertEqual(weisenheim.preselection(for: "Weisenheim am Sand", query: "Weisenheim am Sand")?.title, "Weisenheim am Sand")
    }
}
