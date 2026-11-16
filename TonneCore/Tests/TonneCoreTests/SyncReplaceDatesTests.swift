import XCTest
@testable import TonneCore

/// Welche Einzeltermine bleiben nach einem ersetzenden Abgleich stehen? Geprüft wird die Entscheidung, die
/// `SyncService.apply` für die Termine einer Müllart übernimmt (Prüfer-Befund 11: nicht nur die Hilfsfunktion).
final class SyncReplaceDatesTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: day))!
    }

    /// Prüfbefund 9: Eintragswechsel an derselben Adresse ist kein Adresswechsel. Auswahl wie bei der AbfallPlus-App:
    /// Kreis-App mit Ortsschritt und Suchtext, TBR-App ohne Ortsschritt.
    func testAddressChangedComparesTheAddressNotTheSource() {
        func source(_ key: String, _ titles: [String]) -> SourceConfiguration {
            SourceConfiguration(providerKind: .abfallPlusApp, serviceKey: key, selections: titles.enumerated().map { SelectionOption(id: "\(key)-\($0.offset)", title: $0.element) }, label: "")
        }
        let kreis = source("de.k4systems.abfallkreisrt", ["Reutlingen", "Haupt", "Hauptstraße", "12"])
        XCTAssertFalse(SourceConfiguration.addressChanged(from: kreis, to: source("de.abfallplus.tbrapp", ["Hauptstr", "Hauptstr.", "12"])))
        XCTAssertFalse(SourceConfiguration.addressChanged(from: kreis, to: kreis), "gleiche Auswahl")
        // Gegenproben: andere Nummer, Zusatz, anderer Ort, zu wenig zum Vergleichen, keine alte Quelle
        XCTAssertTrue(SourceConfiguration.addressChanged(from: kreis, to: source("de.abfallplus.tbrapp", ["Hauptstraße", "1"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: kreis, to: source("de.abfallplus.tbrapp", ["Hauptstraße", "12a"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: kreis, to: source("de.k4systems.abfallkreisrt", ["Pfullingen", "Hauptstraße", "12"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: kreis, to: source("x", ["Reutlingen"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: nil, to: kreis))
    }

    /// Nachprüfung N2 (16.11.2026): Ein fehlender oder anderer Ortsschritt galt als „gleiche Adresse“. Verglichen wird jetzt
    /// der Ort (gewählte Ortsoption oder der einzige Ort, den der Eintrag führt), Wörter nur noch für Straße und Nummer.
    func testAddressChangedNeedsTheSamePlace() throws {
        func source(_ serviceKey: String, _ titles: [String]) throws -> SourceConfiguration {
            let entry = try XCTUnwrap(ProviderCatalog.entries.first { $0.serviceKey == serviceKey })
            return SourceConfiguration(providerKind: entry.kind, serviceKey: serviceKey, selections: titles.map { SelectionOption(id: "\(serviceKey)-\($0)", title: $0) }, label: "")
        }
        let kreis = "de.k4systems.abfallkreisrt", tbr = "de.abfallplus.tbrapp"
        // Ortsschritt auf der einen, Stadtportal eines anderen Orts auf der anderen Seite
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source(kreis, ["Reutlingen", "Berliner Straße"]), to: try source("elchingen", ["Berliner Straße"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source(kreis, ["Reutlingen", "Am Markt"]), to: try source("nersingen", ["Am Markt"])))
        // Zwei Stadtportale verschiedener Orte, gleiche Straße und Nummer
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source("elchingen", ["Hauptstraße", "12"]), to: try source("nersingen", ["Hauptstraße", "12"])))
        // Gleicher Eintrag, anderer Ort, Ortsname als Wortanfang der Straße
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source(kreis, ["Berg", "Bergstraße", "3"]), to: try source(kreis, ["Tal", "Bergstraße", "3"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source(kreis, ["Pfullingen", "Bergstraße", "3"]), to: try source(kreis, ["Reutlingen", "Bergstraße", "3"])))
        // Ort auf einer Seite nicht bestimmbar (Eintrag führt mehrere Orte, kein Ortsschritt): geändert
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source(kreis, ["Bergstraße", "3"]), to: try source(tbr, ["Bergstraße", "3"])))
        // Orte gleichen Kerns sind verschiedene Orte (Rutsweiler/Glan ≠ Rutsweiler/Lauter, Weisenheim am Berg ≠ am Sand)
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source("kusel", ["Rutsweiler/Glan", "Hauptstraße", "1"]), to: try source("kusel", ["Rutsweiler/Lauter", "Hauptstraße", "1"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source(kreis, ["Weisenheim am Berg", "Hauptstraße", "1"]), to: try source(kreis, ["Weisenheim am Sand", "Hauptstraße", "1"])))
        // Führt der Eintrag genau einen Ort, gilt dieser – auch wenn ein getippter Suchtext wie eine Gemeinde heißt („Berg“)
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source("elchingen", ["Berg", "Bergstraße", "3"]), to: try source("nersingen", ["Berg", "Bergstraße", "3"])))
        XCTAssertFalse(SourceConfiguration.addressChanged(from: try source("elchingen", ["Berg", "Bergstraße", "3"]), to: try source("elchingen", ["Bergstraße", "3"])))
        // Befund 9 bleibt: Kreisportal mit Ort Reutlingen → TBR-App (führt nur Reutlingen), gleiche Straße und Nummer
        XCTAssertFalse(SourceConfiguration.addressChanged(from: try source(kreis, ["Reutlingen", "Berliner Straße", "7"]), to: try source(tbr, ["Berliner Str.", "7"])))
        XCTAssertFalse(SourceConfiguration.addressChanged(from: try source(kreis, ["Reutlingen", "Am Markt"]), to: try source(tbr, ["Am Markt"])))
        XCTAssertTrue(SourceConfiguration.addressChanged(from: try source(kreis, ["Reutlingen", "Am Markt"]), to: try source(tbr, ["Am Markt", "1"])), "Nummer kam dazu")
    }

    /// Alte (falsche) Straße: 5.3. rausgestellt, 12.3. nicht rausgestellt, 19.3. nichts getippt, 2.4. kommend.
    private var old: [Date] { [d(2026, 3, 5), d(2026, 3, 12), d(2026, 3, 19), d(2026, 4, 2)] }
    private var marked: [Date] { [d(2026, 3, 5), d(2026, 3, 12)] }
    private var new: [Date] { [d(2026, 3, 18), d(2026, 4, 1), d(2026, 4, 15)] }
    private var today: Date { d(2026, 3, 25) }

    func testAddressChangeDropsUnmarkedPastDates() {
        let result = ScheduleEngine.datesAfterReplacingSync(old: old, new: new, kept: [], marked: marked, sourceChanged: true,
                                                            today: today, calendar: calendar)
        XCTAssertEqual(result, [d(2026, 3, 5), d(2026, 3, 12), d(2026, 3, 18), d(2026, 4, 1), d(2026, 4, 15)],
                       "der unmarkierte 19.3. der alten Straße darf nicht als „offen“ stehen bleiben, der kommende 2.4. fällt weg")
        // Und so taucht er auch nicht in Statistik/Nachtragen auf
        let input = QuotaInput(scheduled: result, done: [d(2026, 3, 5)], notOut: [d(2026, 3, 12)], included: 12)
        let summary = PickupQuota.summary(input, period: PickupQuota.period(containing: today, anchor: nil, calendar: calendar), today: today, calendar: calendar)
        XCTAssertFalse(summary.entries.contains { $0.date == d(2026, 3, 19) })
        XCTAssertTrue(summary.entries.contains { $0.date == d(2026, 3, 5) && $0.mark == .out })
        XCTAssertTrue(summary.entries.contains { $0.date == d(2026, 3, 12) && $0.mark == .notOut })
    }

    func testSameAddressKeepsAllPastDates() {
        let result = ScheduleEngine.datesAfterReplacingSync(old: old, new: new, kept: [d(2026, 12, 30)], marked: marked, sourceChanged: false,
                                                            today: today, calendar: calendar)
        XCTAssertEqual(result, [d(2026, 3, 5), d(2026, 3, 12), d(2026, 3, 18), d(2026, 3, 19), d(2026, 4, 1), d(2026, 4, 15), d(2026, 12, 30)],
                       "ohne Adresswechsel bleiben alle vergangenen Termine, sonst verschwänden unmarkierte still aus der Statistik")
    }

    func testDeactivatedTypeKeepsFutureAndMarkedOnly() {
        // So bereinigt der Abgleich eine Müllart, die die neue Quelle nicht mehr liefert
        let future = old.filter { $0 >= today }
        let result = ScheduleEngine.datesAfterReplacingSync(old: old, new: future, kept: [], marked: marked, sourceChanged: true,
                                                            today: today, calendar: calendar)
        XCTAssertEqual(result, [d(2026, 3, 5), d(2026, 3, 12), d(2026, 4, 2)])
    }
}
