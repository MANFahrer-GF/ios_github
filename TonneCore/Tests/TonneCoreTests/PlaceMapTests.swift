import XCTest
@testable import TonneCore

/// Fester Test ohne Netz: Jede Gemeinde des Verzeichnisses hat einen Eintrag, der sie belegt führt, oder steht mit Grund
/// in der ausdrücklichen Lückenliste – nie beides, nie keins. Anlass: Neuss fehlte, weil je Kreis gezählt wurde.
final class PlaceMapTests: XCTestCase {
    // Prüft deutsche Hinweistexte; ohne Festlegung gilt die Systemsprache (CI: Englisch).
    override func setUp() {
        L10n.forcedLanguage = "de"
    }

    private var places: [String] {
        MunicipalityIndex.all.map { "\($0.district)|\($0.name)" }.filter { !CatalogRegions.unincorporated.contains($0) }
    }

    func testEveryMunicipalityIsMappedOrAnExplicitGap() {
        let all = Set(places)
        XCTAssertGreaterThan(all.count, 10_000)
        let mapped = Set(PlaceMapIndex.entryIDs.keys), gaps = Set(PlaceMapIndex.gaps.keys)
        XCTAssertEqual(all.subtracting(mapped).subtracting(gaps).sorted(), [], "Gemeinden ohne Zuordnung und ohne begründete Lücke")
        XCTAssertEqual(mapped.intersection(gaps).sorted(), [], "Gemeinden mit Zuordnung UND Lücke – Lückenliste veraltet")
        // Gegen das ganze Verzeichnis: „Helmstedt“ ist Stadt und zugleich Name eines gemeindefreien Gebiets.
        let everything = Set(MunicipalityIndex.all.map { "\($0.district)|\($0.name)" })
        XCTAssertEqual(mapped.union(gaps).subtracting(everything).sorted(), [], "Zuordnung oder Lücke für eine Gemeinde, die es nicht gibt")
        XCTAssertFalse(PlaceMapIndex.entryIDs.values.contains { $0.isEmpty }, "Zuordnung ohne Eintrag")
    }

    /// Heißt ein gemeindefreies Gebiet wie eine echte Gemeinde desselben Kreises (Stadt Helmstedt, „Gemeindefreies
    /// Gebiet Helmstedt“), zählt die Gemeinde. Vorher fielen 13 Städte und Gemeinden aus Abdeckung und Test.
    func testTownNamedLikeUnincorporatedAreaStillCounts() throws {
        for pair in ["Landkreis Helmstedt|Helmstedt", "Landkreis Holzminden|Holzminden", "Landkreis Ortenaukreis|Rheinau"] {
            XCTAssertTrue(places.contains(pair), pair)
        }
        XCTAssertTrue(CatalogRegions.unincorporated.contains("Landkreis Helmstedt|Brunsleberfeld"), "echtes gemeindefreies Gebiet bleibt draußen")
        let helmstedt = try XCTUnwrap(ProviderCatalog.coverage.first { $0.district == "Landkreis Helmstedt" })
        XCTAssertEqual(helmstedt.municipalityCount, 23, "23 Gemeinden laut Verzeichnis")
        XCTAssertEqual(Set(places).count, 10_750, "alle Gemeinden des Verzeichnisses ohne gemeindefreie Gebiete")
    }

    func testEveryMappedEntryExistsInTheCatalog() {
        let known = Set(ProviderCatalog.entries.map(\.id))
        XCTAssertEqual(Set(CatalogPlaceMap.entryIDs).subtracting(known).sorted(), [])
    }

    func testGapsCarryAKnownReason() {
        let reasons = Set(["portal_abgeschaltet", "nur_pdf", "nicht_gefuehrt", "kein_eintrag", "nicht_in_liste", "ungeprueft", "mehrdeutig"])
        XCTAssertEqual(Set(PlaceMapIndex.gaps.values.map(\.reason)).subtracting(reasons).sorted(), [])
        // Nachweislich nicht holbar: Portal abgeschaltet (Rhein-Lahn-Kreis nach Sicherheitsvorfall), Termine nur als
        // PDF/Papier oder der zuständige Entsorger führt die Gemeinde in seinem Online-Kalender nicht (Gröde, Helgoland …).
        // Jeder Grund hat einen eigenen Text; offene Gründe gelten nie als nicht holbar.
        let final = ["portal_abgeschaltet", "nur_pdf", "nicht_gefuehrt"]
        let unavailable = PlaceMapIndex.gaps.filter(\.value.isUnavailable)
        XCTAssertTrue(unavailable.allSatisfy { final.contains($0.value.reason) })
        XCTAssertTrue(PlaceMapIndex.gaps.filter { !$0.value.isUnavailable }.allSatisfy { !final.contains($0.value.reason) })
        XCTAssertEqual(unavailable.filter { $0.key.hasPrefix("Landkreis Rhein-Lahn-Kreis|") }.count, 137)
        let notes = ["portal_abgeschaltet", "nur_pdf", "nicht_gefuehrt", "kein_eintrag", "nicht_in_liste", "ungeprueft"].map(PlaceMapIndex.note)
        XCTAssertEqual(Set(notes).count, notes.count)
        XCTAssertTrue(PlaceMapIndex.note("nur_pdf").contains("PDF"))
        XCTAssertTrue(PlaceMapIndex.note("nicht_gefuehrt").contains("führt diese Gemeinde"))
        XCTAssertEqual(PlaceMapIndex.gaps["Kreis Nordfriesland|Gröde"]?.reason, "nicht_gefuehrt")
        XCTAssertEqual(PlaceMapIndex.gaps["Kreis Nordfriesland|Gröde"]?.isUnavailable, true)
        // Seit 11.11.2026 ist jede amtliche Gemeinde belegt oder nachweislich nicht holbar (Grund, Entsorger, Seite und
        // Wortlaut je Zeile in tools/catalog/data/place_map/luecken.json). Eine neue offene Lücke ist ein Fehler.
        XCTAssertEqual(PlaceMapIndex.gaps.count - unavailable.count, 0)
    }

    /// Belege aus dem Abgleich vom 10.11.2026: Ortsliste der dritten Ebene mit Kurzform und Doppelnamen (Abfall+ Wecker,
    /// Kreis Tuttlingen), Landkreis Kaiserslautern (Roth, Mandant KL), EAW Untertaunus, MyMüll im richtigen Kreis.
    func testNewlyMappedPlaces() {
        func entries(_ key: String) -> [String] { PlaceMapIndex.entryIDs[key] ?? [] }
        let wecker = "abfallPlusApp:de.abfallwecker:Abfall+ Wecker (Tuttlingen, Prignitz, Osterode am Harz …)"
        for name in ["Hausen ob Verena", "Neuhausen ob Eck", "Seitingen-Oberflacht", "Fridingen an der Donau"] {
            XCTAssertTrue(entries("Landkreis Tuttlingen|\(name)").contains(wecker), name)
        }
        let kl = "portalsRP:kaiserslautern:Abfallwirtschaft Landkreis Kaiserslautern"
        for name in ["Bruchmühlbach-Miesau", "Ramstein-Miesenbach", "Landstuhl", "Hirschhorn/Pfalz", "Otterbach"] {
            XCTAssertTrue(entries("Landkreis Kaiserslautern|\(name)").contains(kl), name)
        }
        XCTAssertTrue(entries("Landkreis Rheingau-Taunus-Kreis|Idstein").contains("portalsSuedwest:untertaunus:EAW Rheingau-Taunus-Kreis (Untertaunus)"))
        let mymuell = "jumomind:mymuell:MyMüll-App"
        XCTAssertTrue(entries("Landkreis Neu-Ulm|Senden").contains(mymuell))
        XCTAssertTrue(entries("Kreis Rhein-Erft-Kreis|Elsdorf").contains(mymuell))
        // Gegenprobe: der Namensvetter im Kreis Coesfeld bleibt bei seinem Entsorger
        XCTAssertFalse(entries("Kreis Coesfeld|Senden").contains(mymuell))
        // Gemeinde-Einträge, deren Titel vom amtlichen Namen abweicht (Sweep 11.11.2026)
        XCTAssertTrue(entries("Landkreis München|Pullach i.Isartal").contains("awido:pullach:Pullach im Isartal"))
        XCTAssertEqual(entries("Kreis Märkischer Kreis|Lüdenscheid"), ["abfallnavi:stl:STL Lüdenscheid"])
        XCTAssertEqual(entries("Landkreis Wetteraukreis|Rosbach v.d.Höhe"), ["jumomind:ros:Rosbach Vor Der Höhe"])
        XCTAssertEqual(entries("Kreis Kleve|Kranenburg"), ["abfallnavi:kranenburg:Gemeinde Kranenburg"])
        // Gegenprobe: Kranenburg im Kreis Stade bleibt beim Landkreis Stade
        XCTAssertEqual(entries("Landkreis Stade|Kranenburg"), ["awsh:stade:Landkreis Stade"])
        // Einzelportale der letzten sechs Gemeinden (Live-Lauf 11.11.2026, EinzelportaleTests.testLiveEinzelportale)
        for (key, id) in ["Landkreis Neunkirchen|Eppelborn": "portalsNRW:eppelborn:AFZE Eppelborn – Abfuhrkalender",
                          "Landkreis Waldeck-Frankenberg|Waldeck": "portalsNRW:waldeck:Stadt Waldeck – Müllkalender",
                          "Landkreis Neu-Ulm|Elchingen": "portalsNRW:elchingen:Knittel Entsorgung – Elchingen",
                          "Landkreis Neu-Ulm|Nersingen": "portalsNRW:nersingen:Knittel Entsorgung – Nersingen",
                          "Landkreis Marburg-Biedenkopf|Ebsdorfergrund": "portalsNRW:ebsdorfergrund:Gemeinde Ebsdorfergrund – Online-Abfuhrkalender",
                          "Landkreis Main-Kinzig-Kreis|Brachttal": "portalsNRW:brachttal:Gemeinde Brachttal – Müllkalender"] {
            XCTAssertEqual(entries(key), [id], key)
        }
        // Gegenprobe: der Nachbar im selben Kreis bekommt das Gemeindeportal nicht (Neunkirchen hat nur ein PDF)
        XCTAssertEqual(entries("Landkreis Neunkirchen|Neunkirchen"), [])
        XCTAssertEqual(PlaceMapIndex.gaps["Landkreis Neunkirchen|Neunkirchen"]?.reason, "nur_pdf")
        XCTAssertFalse(entries("Landkreis Neu-Ulm|Senden").contains("portalsNRW:elchingen:Knittel Entsorgung – Elchingen"))
        // Feste Kalenderdateien der Gemeinde, je Ortsteil/Bezirk ein Eintrag (Live-Lauf 11.11.2026)
        for (key, count) in ["Landkreis Main-Kinzig-Kreis|Hasselroth": 3, "Landkreis Main-Kinzig-Kreis|Bad Soden-Salmünster": 6,
                             "Landkreis München|Neuried": 2,
                             "Kreis Siegen-Wittgenstein|Erndtebrück": 7, "Landkreis Saarlouis|Lebach": 25] {
            XCTAssertEqual(entries(key).count, count, key)
            XCTAssertTrue(entries(key).allSatisfy { $0.hasPrefix("icsURL:") }, key)
        }
        // Wachtendonk: vier Bezirksdateien plus gemeinsame Wertstoff-Datei (Live-Lauf 11.11.2026)
        XCTAssertEqual(entries("Kreis Kleve|Wachtendonk").count, 5)
        // MZV Rotenburg-Bebra: Kalender je Ortsteil, Kernstädte mit Bezirken der Gelben Tonne (Live-Lauf 11.11.2026)
        for (name, count) in ["Bebra": 15, "Rotenburg a.d.Fulda": 11, "Ronshausen": 1] {
            XCTAssertEqual(entries("Landkreis Hersfeld-Rotenburg|\(name)").filter { $0.contains("mzv-rotenburg-bebra") }.count, count, name)
        }
        // Straßlach-Dingharting: Google-Kalender der Gemeinde und die Abfall+-App des Landkreises
        XCTAssertEqual(entries("Landkreis München|Straßlach-Dingharting").filter { $0.hasPrefix("icsURL:") }.count, 1)
        // Kalender je Straße: Eintrag führt auf die Seite, auf der man den eigenen Link kopiert
        XCTAssertEqual(entries("Kreis Recklinghausen|Gladbeck"), ["icsURL:https://www.zb-gladbeck.de/abfuhrkalender#einfuegen:Gladbeck (ZBG, eigener Kalender-Link)"])
        // ZEW (abfallnavi zew2) führt die Orte im Kreis Düren in seiner Ortsliste (Sweep 11.11.2026)
        for name in ["Düren", "Jülich", "Kreuzau", "Titz"] {
            XCTAssertTrue(entries("Kreis Düren|\(name)").contains("abfallnavi:zew2:ZEW Zweckverband Entsorgungsregion West"), name)
        }
        // Regionalverband Saarbrücken: ZKE-Portal und EZV-Bürgerportal je für ihre Stadt; Ginsheim-Gustavsburg über das
        // Export-Formular der Stadt (Live-Lauf 11.11.2026). Gegenprobe: die übrigen Städte des Verbands bleiben ohne Eintrag.
        XCTAssertEqual(entries("Landkreis Regionalverband Saarbrücken|Saarbrücken"), ["wasteManagementServlet:saarbruecken:ZKE Saarbrücken"])
        XCTAssertEqual(entries("Landkreis Regionalverband Saarbrücken|Völklingen"), ["buergerportal:voelklingen:EZV Völklingen"])
        XCTAssertFalse(entries("Landkreis Regionalverband Saarbrücken|Püttlingen").contains { $0.contains("saarbruecken") || $0.contains("voelklingen") })
        XCTAssertEqual(entries("Landkreis Groß-Gerau|Ginsheim-Gustavsburg").filter { $0.contains("abfallkalender.gigu.de") }.count, 2)
        // AHE (Abfall+ Widgets) und ASTO (Straßen-ICS), Live-Lauf 11.11.2026. Gegenprobe: Nümbrecht (BAV) bekommt ASTO nicht.
        let ahe = "abfallIOGraphQL:0d74f933a2959ed0133cd88eda556714:AHE Ennepe-Ruhr-Kreis"
        for name in ["Ennepetal", "Gevelsberg", "Herdecke", "Schwelm", "Sprockhövel", "Witten"] {
            XCTAssertTrue(entries("Kreis Ennepe-Ruhr-Kreis|\(name)").contains(ahe), name)
        }
        for name in ["Bergneustadt", "Gummersbach", "Marienheide", "Waldbröl", "Wiehl", "Wipperfürth"] {
            XCTAssertTrue(entries("Kreis Oberbergischer Kreis|\(name)").contains { $0.hasPrefix("portalsNRW:asto:") }, name)
        }
        XCTAssertFalse(entries("Kreis Oberbergischer Kreis|Nümbrecht").contains { $0.hasPrefix("portalsNRW:asto:") })
        // Städteservice (Live-Lauf 11.11.2026); Gegenprobe Kelsterbach im selben Kreis
        for name in ["Raunheim", "Rüsselsheim am Main"] {
            XCTAssertTrue(entries("Landkreis Groß-Gerau|\(name)").contains { $0.hasPrefix("portalsSuedwest:staedteservice:") }, name)
        }
        XCTAssertFalse(entries("Landkreis Groß-Gerau|Kelsterbach").contains { $0.hasPrefix("portalsSuedwest:staedteservice:") })
        // iKISS-Abfallmodule je Stadt (Live-Lauf 11.11.2026); Gegenprobe: Nachbarorte bleiben ohne diese Einträge
        for (key, entry) in ["Landkreis Groß-Gerau|Kelsterbach": "sitepark:kelsterbach:Stadt Kelsterbach",
                             "Landkreis Main-Kinzig-Kreis|Bad Orb": "sitepark:bad-orb:Kurstadt Bad Orb",
                             "Landkreis Marburg-Biedenkopf|Stadtallendorf": "sitepark:stadtallendorf:Stadt Stadtallendorf",
                             "Kreis Siegen-Wittgenstein|Netphen": "sitepark:netphen:Stadt Netphen",
                             "Landkreis Marburg-Biedenkopf|Kirchhain": "portalsNRW:kirchhain:Stadt Kirchhain"] {
            XCTAssertTrue(entries(key).contains(entry), key)
        }
        XCTAssertFalse(entries("Landkreis Marburg-Biedenkopf|Amöneburg").contains("portalsNRW:kirchhain:Stadt Kirchhain"))
        XCTAssertFalse(entries("Kreis Siegen-Wittgenstein|Siegen").contains("sitepark:netphen:Stadt Netphen"))
        // sector27-Müllkalender (Live-Lauf 11.11.2026); Gegenprobe: Marl im Kreis Diepholz ist ein Namensvetter
        let sector27 = "portalsNRW:sector27:sector27 Müllkalender (Datteln, Marl, Oer-Erkenschwick, Schermbeck …)"
        for key in ["Kreis Recklinghausen|Datteln", "Kreis Recklinghausen|Marl", "Kreis Recklinghausen|Oer-Erkenschwick",
                    "Kreis Recklinghausen|Dorsten", "Kreis Borken|Raesfeld", "Kreis Wesel|Schermbeck"] {
            XCTAssertTrue(entries(key).contains(sector27), key)
        }
        XCTAssertFalse(entries("Landkreis Diepholz|Marl").contains(sector27))
        // Eigene Stadtportale in NRW (NRWStadtportaleTests.testLiveStadtportale, 11.11.2026); Gegenprobe: Brühl im Rhein-Neckar-Kreis
        let stadtportale = ["Kreis Lippe|Detmold": "portalsNRW:detmold:Stadt Detmold – Abfuhrkalender",
                            "Kreis Recklinghausen|Herten": "portalsNRW:herten:ZBH Herten – Abfallkalender",
                            "Kreis Recklinghausen|Castrop-Rauxel": "portalsNRW:castrop:EUV Stadtbetrieb Castrop-Rauxel – Leerungsabfrage",
                            "Kreis Mettmann|Monheim am Rhein": "portalsNRW:monheim:Stadt Monheim am Rhein – Abfallkalender",
                            "Kreis Rheinisch-Bergischer Kreis|Rösrath": "portalsNRW:roesrath:Stadtwerke Rösrath – Abfuhrkalender",
                            "Kreis Rhein-Erft-Kreis|Brühl": "portalsNRW:bruehl:Stadtservice Brühl – Abfallkalender",
                            "Kreis Siegen-Wittgenstein|Siegen": "portalsNRW:siegen:Stadt Siegen – Abfallkalender",
                            "Kreis Gütersloh|Verl": "portalsNRW:verl:Stadt Verl – Umwelt- und Abfallkalender",
                            "Kreis Mettmann|Velbert": "portalsNRW:velbert:TBV Velbert – Abfallkalender"]
        for (key, entry) in stadtportale { XCTAssertTrue(entries(key).contains(entry), key) }
        XCTAssertFalse(entries("Landkreis Rhein-Neckar-Kreis|Brühl").contains("portalsNRW:bruehl:Stadtservice Brühl – Abfallkalender"))
        // Einzelportale außerhalb NRW (EinzelportaleTests.testLiveEinzelportale, 11.11.2026)
        let einzelportale = ["Landkreis Nordsachsen|Eilenburg": "portalsNRW:eilenburg:Stadt Eilenburg – Abfallkalender",
                             "Landkreis Marburg-Biedenkopf|Weimar (Lahn)": "portalsNRW:weimar_lahn:Gemeinde Weimar (Lahn) – Abfallkalender",
                             "Landkreis München|Ottobrunn": "portalsNRW:ottobrunn:Gemeinde Ottobrunn – Müll App",
                             "Landkreis München|Ismaning": "portalsNRW:ismaning:Gemeinde Ismaning – Abfallkalender",
                             "Stadtkreis Heilbronn|Heilbronn": "portalsNRW:heilbronn:Entsorgungsbetriebe Heilbronn – Abfuhrtermine",
                             "Landkreis Main-Kinzig-Kreis|Erlensee": "portalsNRW:erlensee:Stadt Erlensee – Terminservice",
                             "Landkreis Waldeck-Frankenberg|Frankenberg (Eder)": "portalsNRW:frankenberg:Stadt Frankenberg (Eder) – Abfallkalender",
                             "Landkreis Nordwestmecklenburg|Wismar": "portalsNRW:wismar:EVB Wismar – Abfuhrtermine"]
        for (key, entry) in einzelportale { XCTAssertTrue(entries(key).contains(entry), key) }
        // Gegenprobe: gleichnamige Stadt Weimar (Thüringen) und Landkreis Heilbronn bekommen die Gemeindeportale nicht
        XCTAssertFalse(entries("Kreisfreie Stadt Weimar|Weimar").isEmpty, "Gegenprobe braucht einen vorhandenen Schlüssel")
        XCTAssertFalse(entries("Landkreis Heilbronn|Leingarten").isEmpty, "Gegenprobe braucht einen vorhandenen Schlüssel")
        XCTAssertFalse(entries("Kreisfreie Stadt Weimar|Weimar").contains("portalsNRW:weimar_lahn:Gemeinde Weimar (Lahn) – Abfallkalender"))
        XCTAssertFalse(entries("Landkreis Heilbronn|Leingarten").contains("portalsNRW:heilbronn:Entsorgungsbetriebe Heilbronn – Abfuhrtermine"))
        // Große Städte mit eigenem Entsorger (EinzelportaleTests.testLiveEinzelportale, 11.11.2026)
        let staedte = ["Landkreis Göttingen|Göttingen": "portalsNRW:goettingen:GEB Göttingen – Abfuhrkalender",
                       "Landkreis Gießen|Gießen": "portalsNRW:giessen:Stadtreinigung Gießen – Abfuhrkalender",
                       "Landkreis Lahn-Dill-Kreis|Wetzlar": "portalsNRW:wetzlar:Stadt Wetzlar – Abfuhrtermine",
                       "Kreis Rhein-Erft-Kreis|Hürth": "portalsNRW:huerth:Stadtverkehr Hürth – Müllkalender",
                       // AbfallNavi-Dienst der Stadt (Python-Abruf 11.11.2026: 336 Straßen, Termine bis Ende 2027)
                       "Landkreis Groß-Gerau|Mörfelden-Walldorf": "abfallnavi:moerfelden-walldorf:Stadt Mörfelden-Walldorf"]
        for (key, entry) in staedte { XCTAssertTrue(entries(key).contains(entry), key) }
        // Gegenprobe: Nachbargemeinden im selben Landkreis bekommen das Stadtportal nicht
        for (key, entry) in [("Landkreis Göttingen|Duderstadt", staedte["Landkreis Göttingen|Göttingen"]!),
                             ("Landkreis Gießen|Lich", staedte["Landkreis Gießen|Gießen"]!),
                             ("Landkreis Lahn-Dill-Kreis|Herborn", staedte["Landkreis Lahn-Dill-Kreis|Wetzlar"]!),
                             ("Kreis Rhein-Erft-Kreis|Frechen", staedte["Kreis Rhein-Erft-Kreis|Hürth"]!),
                             ("Landkreis Groß-Gerau|Rüsselsheim am Main", staedte["Landkreis Groß-Gerau|Mörfelden-Walldorf"]!)] {
            XCTAssertFalse(entries(key).isEmpty, "Gegenprobe braucht einen vorhandenen Schlüssel: \(key)")
            XCTAssertFalse(entries(key).contains(entry), key)
        }
        // Abfall+-App Landkreis München: alle 14 Orte liefern Termine (PlaceDatesLiveTests, 11.11.2026)
        let lkm = "abfallPlusApp:de.k4systems.lkmabfallplus:München Landkreis"
        for name in ["Baierbrunn", "Grasbrunn", "Haar", "Grünwald", "Oberhaching", "Oberschleißheim", "Taufkirchen",
                     "Garching b.München", "Kirchheim b.München"] {
            XCTAssertTrue(entries("Landkreis München|\(name)").contains(lkm), name)
        }
        // Gegenprobe: Taufkirchen im Landkreis Mühldorf bekommt die Münchner App nicht
        XCTAssertFalse(entries("Landkreis Mühldorf a.Inn|Taufkirchen").contains(lkm))
        // Burbach: eigener AWIDO-Mandant (9 Orte, Termine live 11.11.2026); Hollnseth über die Ortsteile Abbenseth und Hollen
        XCTAssertEqual(entries("Kreis Siegen-Wittgenstein|Burbach"), ["awido:burbach:Gemeinde Burbach"])
        XCTAssertTrue(entries("Landkreis Cuxhaven|Hollnseth").contains("abfallIOLegacy:49fe8a63a056adbfc43f051f61dd4a44:Landkreis Cuxhaven"))
        // Gegenprobe: Neuried im Ortenaukreis bleibt bei der Kreis-App
        XCTAssertEqual(entries("Landkreis Ortenaukreis|Neuried"), ["abfallPlusApp:de.k4systems.abfallappog:Ortenaukreis"])
        XCTAssertEqual(entries("Landkreis Main-Kinzig-Kreis|Neuberg").count, 1)
        // Wetterau über Mein-Abfallkalender (Startseiten live 11.11.2026)
        for (name, sub) in [("Echzell", "echzell"), ("Florstadt", "florstadt"), ("Hirzenhain", "hirzenhain"), ("Limeshain", "limeshain"),
                            ("Niddatal", "niddatal"), ("Ortenberg", "ortenberg"), ("Rockenberg", "rockenberg"),
                            ("Wölfersheim", "woelfersheim"), ("Wöllstadt", "woellstadt")] {
            XCTAssertEqual(entries("Landkreis Wetteraukreis|\(name)"),
                           ["icsURL:https://\(sub).mein-abfallkalender.online:\(name) (Mein-Abfallkalender)"], name)
        }
        // Gegenprobe: Ortenberg im Ortenaukreis bekommt den hessischen Eintrag nicht
        XCTAssertFalse(entries("Landkreis Ortenaukreis|Ortenberg").contains { $0.contains("mein-abfallkalender") })
        XCTAssertEqual(entries("Kreis Recklinghausen|Waltrop").count, 8, "acht Abfuhrbezirke")
        // Amt Temnitz steht unter der Zeile „Ostprignitz-Ruppin“ des Portals; beide Berschweiler führt der AWB Birkenfeld
        let opr = "sitepark:ostprignitz-ruppin:Landkreis Ostprignitz-Ruppin"
        for name in ["Dabergotz", "Märkisch Linden", "Temnitzquell", "Temnitztal", "Vielitzsee"] {
            XCTAssertTrue(entries("Landkreis Ostprignitz-Ruppin|\(name)").contains(opr), name)
        }
        for name in ["Berschweiler bei Baumholder", "Berschweiler bei Kirn"] {
            XCTAssertEqual(entries("Landkreis Birkenfeld|\(name)"), ["portalsRP:birkenfeld:AWB Landkreis Birkenfeld"], name)
        }
        XCTAssertFalse(entries("Landkreis Greiz|Linda b.Weida").isEmpty)
    }

    func testNeussFindsItsOwnProvider() throws {
        let neuss = try XCTUnwrap(ProviderCatalog.checkPlace("Neuss").first { $0.district == "Kreis Rhein-Kreis Neuss" })
        XCTAssertEqual(neuss.entries.map(\.serviceKey), ["awl_neuss"])
        XCTAssertFalse(neuss.entries.contains { $0.title.contains("Schönmackers") })
        XCTAssertNil(neuss.gapNote)
        let found = ProviderCatalog.search("Neuss")
        XCTAssertTrue(found.contains { $0.serviceKey == "awl_neuss" })
        XCTAssertFalse(found.contains { $0.title.contains("Schönmackers") }, "Schönmackers führt Neuss nicht")
        // Gegenprobe: Kaarst im selben Kreis führt Schönmackers
        let kaarst = try XCTUnwrap(ProviderCatalog.checkPlace("Kaarst").first)
        XCTAssertTrue(kaarst.entries.contains { $0.title.contains("Schönmackers") })
    }

    func testUnavailablePortalIsToldHonestly() throws {
        let diez = try XCTUnwrap(ProviderCatalog.checkPlace("Diez").first { $0.district == "Landkreis Rhein-Lahn-Kreis" })
        XCTAssertFalse(diez.isCovered)
        XCTAssertTrue(diez.isUnavailable)
        XCTAssertNotNil(diez.gapNote)
        let district = try XCTUnwrap(ProviderCatalog.coverage.first { $0.district == "Landkreis Rhein-Lahn-Kreis" })
        XCTAssertFalse(district.isCovered)
    }
}
