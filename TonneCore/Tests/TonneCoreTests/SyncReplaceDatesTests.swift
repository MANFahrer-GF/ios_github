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
