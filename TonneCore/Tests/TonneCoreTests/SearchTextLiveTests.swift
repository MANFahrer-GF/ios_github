import XCTest
@testable import TonneCore

/// Echte Portale (nur mit TONNE_LIVE=1): Assistent mit Suchtext durchspielen und den Standortnamen prüfen.
/// Gegenstück zu `SearchTextLabelTests`, das die Auswahlen nur nachbaut.
final class SearchTextLiveTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    /// `inputs`: je Schritt der getippte Text (Textschritt) bzw. der gewünschte Listeneintrag (Teilstring).
    private func run(_ provider: WasteProvider, _ inputs: [String], search: String, street: String) async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1", "TONNE_LIVE nicht gesetzt")
        var selections: [SelectionOption] = []
        var index = 0
        while let step = try await provider.nextStep(after: selections) {
            let wanted = index < inputs.count ? inputs[index] : ""
            if step.input == .text {
                selections.append(SelectionOption(id: wanted, title: wanted))
            } else {
                let pick = step.options.first { $0.title.localizedCaseInsensitiveContains(wanted) && !wanted.isEmpty } ?? step.options[0]
                selections.append(pick)
            }
            index += 1
            if index > 8 { XCTFail("Zu viele Schritte"); break }
        }
        let label = provider.label(for: selections)
        let pickups = try await provider.pickups(for: selections)
        print("LIVE \(provider.kind.rawValue)/\(provider.serviceKey): „\(label)“ – \(pickups.count) Termine – Auswahl: \(selections.map(\.title))")
        XCTAssertFalse(label.components(separatedBy: ", ").contains(search), "Suchtext im Namen: \(label)")
        XCTAssertTrue(label.contains(street), "Straße fehlt im Namen: \(label)")
        XCTAssertGreaterThan(pickups.count, 0)
    }

    func testLeipzig() async throws {
        try await run(LeipzigProvider(), ["Hamburger Str.", "Hamburger Straße", "10"], search: "Hamburger Str.", street: "Hamburger Straße")
    }
    func testKoeln() async throws {
        try await run(AWBKoelnProvider(), ["Aachener Str.", "50"], search: "Aachener Str.", street: "Aachener Str")
    }
    func testAhaHannover() async throws {
        try await run(AhaHannoverProvider(), ["Hannover", "Podbi", "Podbielskistr", "10"], search: "Podbi", street: "Podbielski")
    }
    /// Bochum: Das Portal findet genau eine Straße und zeigt gleich die Hausnummern – der getippte Text ist die Straßenangabe.
    func testMuellmaxBochumDirectToNumbers() async throws {
        try await run(MuellmaxProvider(service: "Usb"), ["Kortum", "2"], search: "Kortum", street: "Kortumstr")
    }
    func testMuellmaxMainz() async throws {
        try await run(MuellmaxProvider(service: "Ebm"), ["Haupt", "1"], search: "Haupt", street: "Hauptstraße")
    }
    func testSector27Dorsten() async throws {
        try await run(NRWPortalsProvider(service: "sector27"), ["Dorsten", "Haupt", "Hauptstraße"], search: "Haupt", street: "Hauptstraße")
    }
}
