import XCTest
@testable import TonneCore

/// „Diesmal nicht rausstellen“: Die Abfuhr kommt, aber eine Müllart bleibt diesmal drin.
final class SkipPickupTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private var settings: ReminderSettings {
        var settings = ReminderSettings()
        settings.morningEnabled = true
        return settings
    }

    /// Gelber Sack ausgelassen, Restmüll geht raus: alle Erinnerungen nennen nur noch den Restmüll.
    func testSkippedSackLeavesOnlyTheBin() {
        let day = calendar.startOfDay(for: at(5, 0))
        let pickups = [
            PlannedPickup(date: day, name: "Gelber Sack", symbolName: "tt.sack", skipped: true),
            PlannedPickup(date: day, name: "Restmüll", symbolName: "trash.fill"),
        ]
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(4, 12), calendar: calendar)
        let waste = plan.filter { $0.threadIdentifier == "waste" }
        XCTAssertEqual(Set(waste.map(\.category)), [.wasteEvening, .wasteEscalation, .wasteMorning, .wasteBringIn])
        for note in waste {
            XCTAssertFalse((note.title + note.body).contains("Gelber Sack"), "\(note.category): \(note.title) – \(note.body)")
            XCTAssertTrue((note.title + note.body).contains("Restmüll"), "\(note.category): \(note.title) – \(note.body)")
        }
    }

    /// Alles ausgelassen: gar keine Müll-Mitteilung für den Tag – auch kein „wieder reinholen“ für die Tonne.
    func testEverythingSkippedMeansNoReminders() {
        let day = calendar.startOfDay(for: at(5, 0))
        let pickups = [
            PlannedPickup(date: day, name: "Gelber Sack", symbolName: "tt.sack", skipped: true),
            PlannedPickup(date: day, name: "Restmüll", symbolName: "trash.fill", skipped: true),
        ]
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(4, 12), calendar: calendar)
        XCTAssertTrue(plan.filter { $0.threadIdentifier == "waste" }.isEmpty, plan.map(\.identifier).description)
    }

    /// Gegenprobe: ohne Auslassen kommen beide in die Erinnerung (der Test oben misst also wirklich etwas).
    func testWithoutSkipBothAreNamed() {
        let day = calendar.startOfDay(for: at(5, 0))
        let pickups = [
            PlannedPickup(date: day, name: "Gelber Sack", symbolName: "tt.sack"),
            PlannedPickup(date: day, name: "Restmüll", symbolName: "trash.fill"),
        ]
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(4, 12), calendar: calendar)
        let evening = plan.first { $0.category == .wasteEvening }
        XCTAssertTrue(evening.map { ($0.title + $0.body).contains("Gelber Sack") && ($0.title + $0.body).contains("Restmüll") } == true)
    }

    /// Nur dieser eine Termin entfällt – der nächste Gelbe Sack wird wieder normal erinnert.
    func testSkipOnlyAffectsThatDay() {
        let pickups = [
            PlannedPickup(date: calendar.startOfDay(for: at(5, 0)), name: "Gelber Sack", symbolName: "tt.sack", skipped: true),
            PlannedPickup(date: calendar.startOfDay(for: at(19, 0)), name: "Gelber Sack", symbolName: "tt.sack"),
        ]
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(4, 12), calendar: calendar)
        XCTAssertEqual(plan.filter { $0.category == .wasteEvening }.map(\.dayKey), ["2026-11-19"])
    }
}
