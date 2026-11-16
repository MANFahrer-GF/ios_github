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
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("fehler", "Jumomind hat keine Termine für diese Adresse geliefert.")))
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("fehler", "x antwortete mit HTTP 404.")))
        XCTAssertFalse(PortalHealthLiveTests.isTransient(result("warnung", "HTTP 429")))
    }
}
