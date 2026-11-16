import XCTest
@testable import TonneCore

/// Gemeinde-Prüfung (16.11.2026): Bei A.R.T. Trier, AWB Altenkirchen und AWB Bad Dürkheim steht zuerst die Verbandsgemeinde,
/// die Ortsgemeinde erst darunter. Die Prüfung nahm die mittlere VG und meldete 230 Gemeinden als „nicht in der Auswahl“,
/// obwohl 203 davon unter ihrer VG stehen (Altrich → Wittlich-Land). Sperren und HTTP 429 standen als feste „fehler“ in der Datei.
final class PortalHealthWalkTests: XCTestCase {
    /// Ort (VG) → Gemeinde → fertig.
    private struct VGStub: WasteProvider {
        let kind = ProviderKind.awido
        let serviceKey = "stub"
        let displayName = "Stub"
        let tree = ["VG Altenkirchen - Flammersfeld": ["Almersbach", "Kircheib"], "VG Hamm/Sieg": ["Fürthen", "Pracht"],
                    "Wittlich-Land": ["Altrich", "Graach"]]

        func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
            switch selections.count {
            case 0: return SelectionStep(title: SelectionStep.cityTitle, options: tree.keys.sorted().map { SelectionOption(id: $0, title: $0) })
            case 1: return SelectionStep(title: "Ortsteil", options: (tree[selections[0].title] ?? []).map { SelectionOption(id: $0, title: $0) })
            default: return nil
            }
        }

        func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] { [] }
    }

    private func titles(_ options: [SelectionOption]) -> [String] { options.map(\.title) }

    func testOrtsgemeindeIsFoundUnderItsVerbandsgemeinde() async throws {
        let step = try await VGStub().nextStep(after: [])!
        let parent = try await PortalHealthLiveTests.parentOption(of: "Almersbach", in: step.options, after: [], provider: VGStub())
        XCTAssertEqual(parent?.title, "VG Altenkirchen - Flammersfeld")
        let none = try await PortalHealthLiveTests.parentOption(of: "Nirgendwo", in: step.options, after: [], provider: VGStub())
        XCTAssertNil(none)
    }

    /// Burgenlandkreis: Unter der VerbG stehen Ortsteile statt Gemeinden; Gleina gibt es als Ortsteil in zwei Verbänden.
    private struct VerbGStub: WasteProvider {
        let kind = ProviderKind.muellabfuhrDeutschland
        let serviceKey = "stub"
        let displayName = "Stub"
        let tree = ["Gemeinde Elsteraue": ["Gleina", "Profen"], "VerbG An der Finne": ["Borgau", "Kahlwinkel", "Saubach"],
                    "VerbG Unstruttal": ["Baumersroda", "Ebersroda", "Gleina"]]
        func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
            switch selections.count {
            case 0: return SelectionStep(title: SelectionStep.cityTitle, options: tree.keys.sorted().map { SelectionOption(id: $0, title: $0) })
            case 1: return SelectionStep(title: "Ortsteil oder Straße", options: (tree[selections[0].title] ?? []).map { SelectionOption(id: $0, title: $0) })
            default: return nil
            }
        }
        func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] { [] }
    }

    func testMunicipalityIsFoundUnderTheAssociationThatListsItsLocalities() async throws {
        let options = try await VerbGStub().nextStep(after: [])!.options
        let finneland = try await PortalHealthLiveTests.parentOption(of: "Finneland", in: options, after: [], provider: VerbGStub(),
                                                                     localities: ["Borgau", "Kahlwinkel", "Marienroda", "Saubach"])
        XCTAssertEqual(finneland?.title, "VerbG An der Finne")
        // Name in zwei Verbänden: der mit den meisten Ortsteilen
        let gleina = try await PortalHealthLiveTests.parentOption(of: "Gleina", in: options, after: [], provider: VerbGStub(),
                                                                  localities: ["Baumersroda", "Ebersroda", "Müncheroda"])
        XCTAssertEqual(gleina?.title, "VerbG Unstruttal")
        // Ohne Ortsteile bleibt ein doppelter Name unentschieden, ein unbekannter ohnehin
        let ambiguous = try await PortalHealthLiveTests.parentOption(of: "Gleina", in: options, after: [], provider: VerbGStub())
        XCTAssertNil(ambiguous)
        let unknown = try await PortalHealthLiveTests.parentOption(of: "Nirgendwo", in: options, after: [], provider: VerbGStub(), localities: ["Irgendwo"])
        XCTAssertNil(unknown)
    }

    func testWalkPicksTheLocalityUnderTheAssociation() async throws {
        let job = PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: .muellabfuhrDeutschland, serviceKey: "stub", title: "Stub"),
                                            district: "Landkreis Burgenlandkreis", place: "Finneland")
        let (selections, placeFound, _) = try await PortalHealthLiveTests.walk(job, calendar: .current, provider: VerbGStub())
        XCTAssertEqual(selections.first?.title, "VerbG An der Finne")
        XCTAssertTrue(["Borgau", "Kahlwinkel", "Saubach"].contains(selections.last?.title ?? ""))
        XCTAssertEqual(placeFound, true)
    }

    func testOfficialNameWithSuffixMatchesShortPortalName() {
        XCTAssertTrue(PortalHealthLiveTests.matches(SelectionOption(id: "g", title: "Graach"), "Graach an der Mosel"))
        XCTAssertTrue(PortalHealthLiveTests.matches(SelectionOption(id: "a", title: "Ahaus, Stadt"), "Ahaus"))
        XCTAssertFalse(PortalHealthLiveTests.matches(SelectionOption(id: "n", title: "Neumagen"), "Neumagen-Dhron"))
        XCTAssertFalse(PortalHealthLiveTests.matches(SelectionOption(id: "b", title: "Bad"), "Badenweiler"))
    }

    /// Gemeinde-Prüfung 16.11.2026: MyMüll führt „Mühlheim“ (ohne Straßen) vor „Mühlheim am Main“; AWIDO Neustadt
    /// a.d. Waldnaab führt „Neustadt am Kulm“ und „Neustadt/WN“ mit demselben Kernnamen.
    func testExactNameBeatsPrefixAndAmbiguousCoresAreNotPicked() {
        var found = false
        let mymuell = ["Mühlheim", "Mühlheim am Main", "Mülheim an der Ruhr"].map { SelectionOption(id: $0, title: $0) }
        XCTAssertEqual(PortalHealthLiveTests.pick(mymuell, wanted: "Mühlheim am Main", found: &found).title, "Mühlheim am Main")
        XCTAssertTrue(found)
        found = false
        let awido = ["Mantel", "Neustadt am Kulm", "Neustadt/WN", "Parkstein"].map { SelectionOption(id: $0, title: $0) }
        let picked = PortalHealthLiveTests.pick(awido, wanted: "Neustadt a.d.Waldnaab", found: &found)
        XCTAssertFalse(found && picked.title == "Neustadt am Kulm", "mehrdeutiger Kern darf nicht als Fund gelten")
    }

    /// Prüfbefunde 3 und 14 ändern nur die Vorauswahl der App, nicht „Ort gefunden“ des Prüfwerkzeugs (Punkt-6-Auswertung).
    func testPickStaysWhenTheAppNoLongerPreselects() {
        var found = false
        let duew = ["Lambrecht ohne Iptestal und Dörrental", "Lindenberg mit Lambrecht-Dörrental", "Weisenheim am Berg", "Weisenheim am Sand"]
            .map { SelectionOption(id: $0, title: $0) }
        XCTAssertEqual(PortalHealthLiveTests.pick(duew, wanted: "Lambrecht (Pfalz)", found: &found).title, "Lambrecht ohne Iptestal und Dörrental")
        XCTAssertTrue(found)
        found = false
        XCTAssertEqual(PortalHealthLiveTests.pick(duew, wanted: "Weisenheim am Sand", found: &found).title, "Weisenheim am Sand")
        XCTAssertTrue(found)
        found = false
        let kusel = ["Kusel", "Rutsweiler/Glan", "Rutsweiler/Lauter"].map { SelectionOption(id: $0, title: $0) }
        XCTAssertEqual(PortalHealthLiveTests.pick(kusel, wanted: "Rutsweiler am Glan", found: &found).title, "Rutsweiler/Glan")
        XCTAssertTrue(found)
    }

    func testLaterAttemptsTryADistrictOfThePlace() {
        let options = ["Zell (Mosel)", "Zell (Mosel) – Zell-Barl", "Zell (Mosel) – Zell-Stadt", "Zellertal"].map { SelectionOption(id: $0, title: $0) }
        var found = false
        XCTAssertEqual(PortalHealthLiveTests.pick(options, wanted: "Zell", variant: 0, found: &found).title, "Zell (Mosel)")
        XCTAssertEqual(PortalHealthLiveTests.pick(options, wanted: "Zell", variant: 1, found: &found).title, "Zell (Mosel) – Zell-Barl")
        XCTAssertEqual(PortalHealthLiveTests.pick(options, wanted: "Zell", variant: 2, found: &found).title, "Zell (Mosel) – Zell-Stadt")
        let aurich = ["Aurich", "Aurich / Aurich-Stadt", "Aurichhof"].map { SelectionOption(id: $0, title: $0) }
        XCTAssertEqual(PortalHealthLiveTests.pick(aurich, wanted: "Aurich", variant: 1, found: &found).title, "Aurich / Aurich-Stadt")
        let kaev = ["Groß Wasserburg", "Krausnick", "Lübbenau/Spreewald"].map { SelectionOption(id: $0, title: $0) }
        found = false
        XCTAssertEqual(PortalHealthLiveTests.pick(kaev, wanted: "Krausnick-Groß Wasserburg", found: &found).title, "Krausnick")
        XCTAssertTrue(found)
    }

    func testRateLimitsAndServerErrorsAreNotStored() {
        func result(_ status: String, _ error: String?, _ reasons: [String] = []) -> PortalHealthLiveTests.Result {
            var r = PortalHealthLiveTests.Result(key: "k", mode: "gemeinden", title: "t", kind: "muellmax", serviceKey: "s")
            r.status = status; r.error = error; r.reasons = reasons
            return r
        }
        XCTAssertTrue(PortalHealthLiveTests.isTransient(result("fehler", "Müllmax hat die Abfrage für 24 Stunden gesperrt (Abfragelimit).")))
        XCTAssertTrue(PortalHealthLiveTests.isTransient(result("fehler", "www.rsag.de antwortete mit HTTP 429.")))
        XCTAssertTrue(PortalHealthLiveTests.isTransient(result("fehler", "x antwortete mit HTTP 502.")))
        XCTAssertTrue(PortalHealthLiveTests.isTransient(result("fehler", nil, ["Portal antwortet nicht (über 120 s)"])))
        XCTAssertTrue(PortalHealthLiveTests.isTransient(result("fehler", "leere erste Auswahl bei „Bundesland“ (Abfragegrenze)")))
        XCTAssertTrue(PortalHealthLiveTests.isTransient(result("fehler", "Verbindung fehlgeschlagen: Es besteht anscheinend keine Verbindung zum Internet.")))
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("fehler", "Verbindung fehlgeschlagen: Es wurde kein Server mit dem angegebenen Hostnamen gefunden.")))
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("fehler", "leere Auswahl bei „Straße“")))
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("fehler", "Jumomind hat keine Termine für diese Adresse geliefert.")))
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("fehler", "x antwortete mit HTTP 404.")))
        XCTAssertTrue(PortalHealthLiveTests.isTransient(result("fehler", "www.muellmax.de antwortete mit HTTP 403.")))
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("warnung", "HTTP 429")))
    }

    // MARK: Gemeinde-Prüfung 16.11.2026, Teil 9: Hausnummer und Suchwort

    /// München AWM: Straße → freie Hausnummer; das Portal prüft die Nummer im nächsten Schritt und kennt nur 10.
    private struct NumberStub: WasteProvider {
        let kind = ProviderKind.awmMuenchen
        let serviceKey = "stub"
        let displayName = "Stub"
        func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
            switch selections.count {
            case 0: return SelectionStep(title: SelectionStep.streetTitle, options: [SelectionOption(id: "k", title: "Kronwinkler Str.")])
            case 1: return .text(title: SelectionStep.houseNumberTitle)
            default:
                guard selections[1].id == "10" else { throw ProviderError.invalidSelection("Die Adresse konnte nicht gefunden werden.") }
                return nil
            }
        }
        func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] { [] }
    }

    /// Müllmax: Straßen-Suchfeld; bei genau einem Treffer („Garten“) ist das Portal sofort fertig, sonst keine Liste.
    private struct SearchStub: WasteProvider {
        let kind = ProviderKind.muellmax
        let serviceKey = "stub"
        let displayName = "Stub"
        func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
            guard let last = selections.last else { return .text(title: SelectionStep.streetTitle) }
            if last.id == "Garten" { return nil }
            throw ProviderError.noData("Keine Straße gefunden.")
        }
        func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] { [] }
    }

    /// Ostprignitz-Ruppin: eine lange Ortsliste (49 Orte) mit Ortsteilen statt Gemeinden – Breddin steht dort als „Damelack“,
    /// weitere Orte stehen unter dem Sammelort „Ostprignitz-Ruppin“.
    private struct LocalityStub: WasteProvider {
        let kind = ProviderKind.sitepark
        let serviceKey = "stub"
        let displayName = "Stub"
        func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
            switch selections.first?.title {
            case nil:
                let names = (1...44).map { "Ort \($0)" } + ["Damelack", "Ostprignitz-Ruppin"]
                return SelectionStep(title: SelectionStep.cityTitle, options: names.sorted().map { SelectionOption(id: $0, title: $0) })
            case "Ostprignitz-Ruppin" where selections.count == 1:
                // Sammelort: weitere Orte des Kreises als Einträge
                return SelectionStep(title: SelectionStep.streetTitle, options: ["Dabergotz", "Dreetz", "Seebeck", "Stüdenitz", "Vielitz"].map { SelectionOption(id: $0, title: $0) })
            default: return nil
            }
        }
        func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] { [] }
    }

    private func job(_ kind: ProviderKind) -> PortalHealthLiveTests.Job {
        PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: kind, serviceKey: "stub", title: "Stub"), district: nil, place: nil)
    }

    func testHouseNumberRejectedByTheNextStepTriesTheFollowingNumbers() async throws {
        let (selections, _, typedNumber) = try await PortalHealthLiveTests.walk(job(.awmMuenchen), calendar: .current, provider: NumberStub())
        XCTAssertEqual(titles(selections), ["Kronwinkler Str.", "10"])
        XCTAssertTrue(typedNumber)
        // `check` macht ab der gefundenen Nummer weiter, nicht wieder bei 1
        XCTAssertEqual(Array(PortalHealthLiveTests.houseNumbers.drop(while: { $0 != selections.last?.id })), ["10", "20"])
    }

    func testSearchWordAfterWhichThePortalIsFinishedIsTaken() async throws {
        let (selections, _, _) = try await PortalHealthLiveTests.walk(job(.muellmax), calendar: .current, provider: SearchStub())
        XCTAssertEqual(titles(selections), ["Garten"])
    }

    /// Gemeinde-Prüfung Punkt 6 (16.11.2026): Der Schlüssel „Landkreis|Gemeinde“ wurde mit dem optionalen Landkreis gebaut
    /// („Optional(…)|Breddin“) und traf nie – alle 12 Gemeinden in Ostprignitz-Ruppin bekamen den mittleren Ort.
    func testLocalityOfThePlaceIsPickedFromALongList() async throws {
        let job = PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: .sitepark, serviceKey: "stub", title: "Stub"),
                                            district: "Landkreis Ostprignitz-Ruppin", place: "Breddin")
        let (selections, placeFound, _) = try await PortalHealthLiveTests.walk(job, calendar: .current, provider: LocalityStub())
        XCTAssertEqual(titles(selections), ["Damelack"])
        XCTAssertEqual(placeFound, true)
    }

    func testPlaceUnderTheCollectiveEntryOfTheDistrictIsFound() async throws {
        for (place, expected) in [("Dreetz", "Dreetz"), ("Vielitzsee", "Seebeck"), ("Stüdenitz-Schönermark", "Stüdenitz")] {
            let job = PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: .sitepark, serviceKey: "stub", title: "Stub"),
                                                district: "Landkreis Ostprignitz-Ruppin", place: place)
            let (selections, placeFound, _) = try await PortalHealthLiveTests.walk(job, calendar: .current, provider: LocalityStub())
            XCTAssertEqual(selections.first?.title, "Ostprignitz-Ruppin", place)
            XCTAssertEqual(placeFound, true, place)
            if place != "Vielitzsee" { XCTAssertEqual(selections.last?.title, expected, place) }
            else { XCTAssertTrue(["Seebeck", "Vielitz"].contains(selections.last?.title ?? ""), place) }
        }
        // Ortsteil in der Liste geht vor dem Sammelort
        let breddin = PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: .sitepark, serviceKey: "stub", title: "Stub"),
                                                district: "Landkreis Ostprignitz-Ruppin", place: "Breddin")
        let (selections, _, _) = try await PortalHealthLiveTests.walk(breddin, calendar: .current, provider: LocalityStub())
        XCTAssertEqual(titles(selections), ["Damelack"])
    }

    /// Abfall+ Wecker: Bundesland → Landkreis (mit leerem Altkreis) → Gemeinde → Ortsteil.
    private struct RegionStub: WasteProvider {
        let kind = ProviderKind.abfallPlusApp
        let serviceKey = "stub"
        let displayName = "Stub"
        func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
            func list(_ title: String, _ names: [String]) -> SelectionStep { SelectionStep(title: title, options: names.map { SelectionOption(id: $0, title: $0) }) }
            switch selections.map(\.title) {
            case []: return list("Bundesland", ["Bayern", "Niedersachsen", "Rheinland-Pfalz"])
            case ["Niedersachsen"]: return list("Landkreis", ["Kreis Cuxhaven", "Kreis Göttingen", "Kreis Osterode am Harz"])
            // Altkreis: leere Straßensuche
            case ["Niedersachsen", "Kreis Osterode am Harz"]: return .text(title: SelectionStep.streetTitle)
            case ["Niedersachsen", "Kreis Göttingen"]: return list(SelectionStep.cityTitle, ["Gleichen", "Göttingen", "Osterode am Harz"])
            case ["Niedersachsen", "Kreis Göttingen", "Osterode am Harz"]: return list("Ortsteil", ["Lerbach", "Osterode am Harz"])
            default: return nil
            }
        }
        func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] { [] }
    }

    func testStateAndDistrictAreChosenBeforeThePlace() async throws {
        for (place, path) in [("Osterode am Harz", ["Niedersachsen", "Kreis Göttingen", "Osterode am Harz", "Osterode am Harz"]),
                              ("Gleichen", ["Niedersachsen", "Kreis Göttingen", "Gleichen"])] {
            let job = PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: .abfallPlusApp, serviceKey: "stub", title: "Stub"),
                                                district: "Landkreis Göttingen", place: place)
            let (selections, placeFound, _) = try await PortalHealthLiveTests.walk(job, calendar: .current, provider: RegionStub())
            XCTAssertEqual(titles(selections), path)
            XCTAssertEqual(placeFound, true, place)
        }
    }

    /// A.R.T. Trier: VGs aus vier Kreisen, „Esch“ gibt es in Wittlich-Land und Gerolstein.
    private struct ARTStub: WasteProvider {
        let kind = ProviderKind.portalsRP
        let serviceKey = "stub"
        let displayName = "Stub"
        let tree = ["Daun": ["Brück", "Daun", "Dreis"], "Gerolstein": ["Esch", "Gerolstein"], "Saarburg-Kell": ["Mannebach"],
                    "Wittlich-Land": ["Dreis", "Esch", "Manderscheid"]]
        func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
            switch selections.count {
            case 0: return SelectionStep(title: SelectionStep.cityTitle, options: tree.keys.sorted().map { SelectionOption(id: $0, title: $0) })
            case 1: return SelectionStep(title: "Ortsgemeinde", options: (tree[selections[0].title] ?? []).map { SelectionOption(id: $0, title: $0) })
            default: return nil
            }
        }
        func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] { [] }
    }

    func testAmbiguousMunicipalityIsFoundUnderItsOwnVerband() async throws {
        XCTAssertEqual(PortalHealthLiveTests.verbands["Landkreis Vulkaneifel|Esch"], "Gerolstein")
        XCTAssertEqual(PortalHealthLiveTests.verbands["Landkreis Helmstedt|Bahrdorf"], "Velpke")
        for (district, path) in [("Landkreis Vulkaneifel", ["Gerolstein", "Esch"]), ("Landkreis Bernkastel-Wittlich", ["Wittlich-Land", "Esch"])] {
            let job = PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: .portalsRP, serviceKey: "stub", title: "Stub"), district: district, place: "Esch")
            let (selections, placeFound, _) = try await PortalHealthLiveTests.walk(job, calendar: .current, provider: ARTStub())
            XCTAssertEqual(titles(selections), path, district)
            XCTAssertEqual(placeFound, true, district)
        }
        // Unter der VG Daun steht auch der Ort „Daun“: nicht noch einmal den Verband wählen, sondern den Doppelnamen-Teil
        let dreisBrueck = PortalHealthLiveTests.Job(key: "t", entry: CatalogEntry(kind: .portalsRP, serviceKey: "stub", title: "Stub"),
                                                    district: "Landkreis Vulkaneifel", place: "Dreis-Brück")
        let (daun, found, _) = try await PortalHealthLiveTests.walk(dreisBrueck, calendar: .current, provider: ARTStub())
        XCTAssertEqual(titles(daun), ["Daun", "Dreis"])
        XCTAssertEqual(found, true)
        let helmstedt = [SelectionOption(id: "1", title: "Grasleben und Velpke"), SelectionOption(id: "2", title: "Lehre"),
                         SelectionOption(id: "3", title: "Nord-Elm und Königslutter Ortsteile")]
        XCTAssertEqual(PortalHealthLiveTests.verbandOption(in: helmstedt, verband: "Velpke")?.title, "Grasleben und Velpke")
        XCTAssertEqual(PortalHealthLiveTests.verbandOption(in: helmstedt, verband: "Nord-Elm")?.title, "Nord-Elm und Königslutter Ortsteile")
        XCTAssertNil(PortalHealthLiveTests.verbandOption(in: helmstedt, verband: "Heeseberg"))
    }
}
