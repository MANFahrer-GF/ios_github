import XCTest
@testable import TonneCore

/// Portal liefert nur Vergangenes (Feucht bei Heimat-Info, Portal-Prüfung 12.11.2026): klare Meldung statt still 0 Termine.
final class UpcomingDatesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func day(_ iso: String) -> Date { Days.parse(iso, calendar: calendar)! }

    func testOnlyPastDatesThrowWithLastDate() {
        L10n.forcedLanguage = "de"
        defer { L10n.forcedLanguage = nil }
        let past = [Pickup(date: day("2025-12-29"), name: "Restmüll"), Pickup(date: day("2025-06-02"), name: "Papier")]
        XCTAssertThrowsError(try ProviderError.requireUpcoming(past, today: day("2026-11-12"), calendar: calendar)) { error in
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("2025"), text)
            XCTAssertTrue(text.contains("Entsorger oder Adresse ändern"), text)
        }
        XCTAssertThrowsError(try ProviderError.requireUpcoming(past, today: day("2026-11-12"), setup: true, calendar: calendar)) { error in
            XCTAssertTrue(error.localizedDescription.contains("anderen Entsorger"), error.localizedDescription)
        }
    }

    func testUpcomingOrTodayOrEmptyPass() throws {
        let mixed = [Pickup(date: day("2025-12-29"), name: "Restmüll"), Pickup(date: day("2026-11-12"), name: "Papier")]
        XCTAssertNoThrow(try ProviderError.requireUpcoming(mixed, today: day("2026-11-12"), calendar: calendar))
        // Leere Liste meldet jeder Anbieter selbst – hier keine zweite Meldung
        XCTAssertNoThrow(try ProviderError.requireUpcoming([], today: day("2026-11-12"), calendar: calendar))
    }

    /// Veraltete Heimat-Info-Quelle steht nicht mehr im Katalog; Feucht findet die Suche über Nürnberger Land.
    func testFeuchtComesFromNuernbergerLand() {
        XCTAssertFalse(ProviderCatalog.entries.contains { $0.kind == .heimatInfo && $0.serviceKey == "feucht" })
        XCTAssertTrue(ProviderCatalog.entries.contains { $0.kind == .portalsBayern && $0.serviceKey == "nuernberger_land" && $0.places.contains("Feucht") })
    }
}
