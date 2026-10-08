import XCTest
@testable import TonneCore

final class BringInTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testOnlyBinsAreBroughtBackIn() {
        XCTAssertTrue(WasteReturn.isBin(name: "Restmüll"))
        XCTAssertTrue(WasteReturn.isBin(name: "Biotonne"))
        XCTAssertTrue(WasteReturn.isBin(name: "Altpapier"))
        XCTAssertTrue(WasteReturn.isBin(name: "Gelbe Tonne"))
        XCTAssertTrue(WasteReturn.isBin(name: "Restabfallsammlung 2-wöchentlich"))
        XCTAssertFalse(WasteReturn.isBin(name: "Gelber Sack"))
        XCTAssertFalse(WasteReturn.isBin(name: "Leichtverpackungen"))
        XCTAssertFalse(WasteReturn.isBin(name: "Grünschnitt"))
        XCTAssertFalse(WasteReturn.isBin(name: "Sperrmüll"))
        XCTAssertFalse(WasteReturn.isBin(name: "Schadstoffmobil"))
        XCTAssertFalse(WasteReturn.isBin(name: "Weihnachtsbaum"))
        XCTAssertFalse(WasteReturn.isBin(name: "Papiercontainer"))
        XCTAssertFalse(WasteReturn.isBin(name: "Altglascontainer"))
        XCTAssertTrue(WasteReturn.isBin(name: "Restmüllcontainer 1100 l"))
        XCTAssertTrue(WasteReturn.isBin(name: "Restmüll Container 1100 Ltr."))
        XCTAssertTrue(WasteReturn.isBin(name: "Wertstofftonne/Container"))
        XCTAssertFalse(WasteReturn.isBin(name: "Grüngutsammlung", symbol: "tt.bin.bio"))
        XCTAssertTrue(WasteReturn.isBin(name: "Papier/Pappe/Kartonage"))
        XCTAssertTrue(WasteReturn.isBin(name: "Wertstofftonne"))
        XCTAssertFalse(WasteReturn.isBin(name: "Altglas"))
        XCTAssertFalse(WasteReturn.isBin(name: "Problemabfall"))
        // Die eigene Wahl im Symbol gewinnt
        XCTAssertFalse(WasteReturn.isBin(name: "Restmüll", symbol: "tt.sack"))
        XCTAssertTrue(WasteReturn.isBin(name: "Leichtverpackungen", symbol: "tt.bin.yellow"))
    }

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot(pickupDays: [
            .init(date: calendar.startOfDay(for: at(8, 0)), items: [.init(name: "Gelbe Tonne", symbolName: "bag.fill", colorHex: "#F2C230"),
                                                                    .init(name: "Grünschnitt", symbolName: "leaf.fill", colorHex: "#16A34A")], done: true),
            .init(date: calendar.startOfDay(for: at(15, 0)), items: [.init(name: "Restmüll", symbolName: "trash.fill", colorHex: "#5B6470")]),
        ])
    }

    func testDoneDayIsSkippedInTheWidget() {
        // Erledigt markiert → am Abholtag zeigt das Widget schon die nächste Abholung
        XCTAssertEqual(snapshot.nextPickupDay(from: at(8, 7), calendar: calendar)?.items.first?.name, "Restmüll")
        // Am Vorabend steht der erledigte Tag noch da (mit Haken)
        XCTAssertEqual(snapshot.nextPickupDay(from: at(7, 20), calendar: calendar)?.items.first?.name, "Gelbe Tonne")
    }

    func testOpenDayDisappearsAfterFivePM() {
        var open = snapshot
        open.pickupDays[0].done = false
        XCTAssertEqual(open.nextPickupDay(from: at(8, 9), calendar: calendar)?.items.first?.name, "Gelbe Tonne")
        XCTAssertEqual(open.nextPickupDay(from: at(8, 17, 5), calendar: calendar)?.items.first?.name, "Restmüll")
    }

    func testBringInHintFromNoonOnlyForBins() {
        XCTAssertNil(snapshot.bringInDay(at: at(8, 9), calendar: calendar))
        let hint = snapshot.bringInDay(at: at(8, 13), calendar: calendar)
        XCTAssertEqual(hint?.items.map(\.name), ["Gelbe Tonne"])   // Grünschnitt bleibt draußen
        var inside = snapshot
        inside.pickupDays[0].broughtIn = true
        XCTAssertNil(inside.bringInDay(at: at(8, 13), calendar: calendar))
        XCTAssertNil(snapshot.bringInDay(at: at(9, 13), calendar: calendar))
    }

    func testOldSnapshotWithoutBroughtInDecodes() throws {
        let json = #"{"generatedAt":"2026-10-08T06:00:00Z","locations":[],"pickupDays":[{"date":"2026-10-08T00:00:00Z","items":[],"done":true}],"birthdays":[],"missedCountThisYear":0,"doneCountThisYear":1}"#
        let decoded = try WidgetSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(decoded.pickupDays.first?.done, true)
        XCTAssertEqual(decoded.pickupDays.first?.broughtIn, false)
    }

    func testBringInReminderOnPickupDay() {
        var settings = ReminderSettings()
        settings.eveningEnabled = false
        let day = calendar.startOfDay(for: at(8, 0))
        let pickups = [
            PlannedPickup(date: day, name: "Gelbe Tonne", symbolName: "tt.bin.yellow", done: true),
            PlannedPickup(date: day, name: "Grünschnitt", symbolName: "leaf.fill"),
            PlannedPickup(date: calendar.startOfDay(for: at(9, 0)), name: "Gelber Sack", symbolName: "tt.sack"),
        ]
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(8, 7), calendar: calendar)
        let bringIn = plan.filter { $0.category == .wasteBringIn }
        XCTAssertEqual(bringIn.count, 1)
        XCTAssertEqual(bringIn.first?.fireDate, at(8, 17))
        XCTAssertTrue(bringIn.first?.title.contains("Gelbe Tonne") == true)
        // Schon drin → keine Erinnerung
        let inside = pickups.map { pickup -> PlannedPickup in var copy = pickup; copy.broughtIn = true; return copy }
        XCTAssertTrue(ReminderPlanner.plan(pickups: inside, birthdays: [], settings: settings, now: at(8, 7), calendar: calendar)
            .filter { $0.category == .wasteBringIn }.isEmpty)
        // Abgeschaltet → keine Erinnerung
        settings.bringInEnabled = false
        XCTAssertTrue(ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(8, 7), calendar: calendar)
            .filter { $0.category == .wasteBringIn }.isEmpty)
    }

    func testJustMarkedDayStaysForUndo() {
        var snap = snapshot
        // Heute um 7:00 erledigt getippt: bis 7:15 bleibt der Tag (Zurücknehmen, kein Doppeltipp auf morgen)
        snap.pickupDays[0].doneAt = at(8, 7)
        XCTAssertEqual(snap.nextPickupDay(from: at(8, 7, 5), calendar: calendar)?.items.first?.name, "Gelbe Tonne")
        XCTAssertEqual(snap.nextPickupDay(from: at(8, 7, 20), calendar: calendar)?.items.first?.name, "Restmüll")
        // Schon am Vorabend erledigt → am Abholtag sofort weiter
        snap.pickupDays[0].doneAt = at(7, 19)
        XCTAssertEqual(snap.nextPickupDay(from: at(8, 6), calendar: calendar)?.items.first?.name, "Restmüll")
    }

    func testSiriTargetsTodayOrTomorrowOnly() {
        let snap = WidgetSnapshot(pickupDays: [
            .init(date: calendar.startOfDay(for: at(8, 0)), items: [.init(name: "Restmüll", symbolName: "trash.fill", colorHex: "#5B6470")], done: true),
            .init(date: calendar.startOfDay(for: at(15, 0)), items: [.init(name: "Biotonne", symbolName: "leaf.fill", colorHex: "#8B5E34")]),
        ])
        // Heute schon erledigt, morgen nichts → Siri markiert nicht die Abholung in einer Woche
        XCTAssertNil(snap.doneTargetDay(from: at(8, 9), calendar: calendar))
        XCTAssertEqual(snap.undoTargetDay(from: at(8, 9), calendar: calendar)?.items.first?.name, "Restmüll")
        // Am Vorabend: morgen ist dran
        XCTAssertEqual(snap.doneTargetDay(from: at(14, 19), calendar: calendar)?.items.first?.name, "Biotonne")
        // Heute erledigt und morgen wieder Abholung: direkt nach dem Tippen kein Sprung auf morgen, später schon
        var twoDays = snap
        twoDays.pickupDays[1].date = calendar.startOfDay(for: at(9, 0))
        twoDays.pickupDays[0].doneAt = at(8, 9)
        XCTAssertNil(twoDays.doneTargetDay(from: at(8, 9, 5), calendar: calendar))
        XCTAssertEqual(twoDays.doneTargetDay(from: at(8, 15), calendar: calendar)?.items.first?.name, "Biotonne")
        XCTAssertEqual(twoDays.doneTargetDay(from: at(8, 19), calendar: calendar)?.items.first?.name, "Biotonne")
        // „Wann kommt die Müllabfuhr?“ nennt heute bis 17 Uhr, auch wenn erledigt
        XCTAssertEqual(twoDays.nextPickupDay(from: at(8, 10), countDone: true, calendar: calendar)?.items.first?.name, "Restmüll")
        XCTAssertEqual(twoDays.nextPickupDay(from: at(8, 17, 30), countDone: true, calendar: calendar)?.items.first?.name, "Biotonne")
        // Schon geleert und wieder drin → Siri nennt die nächste Abholung
        twoDays.pickupDays[0].broughtIn = true
        XCTAssertEqual(twoDays.nextPickupDay(from: at(8, 14), countDone: true, calendar: calendar)?.items.first?.name, "Biotonne")
    }

    func testBringInHintFollowsSetting() {
        var snap = snapshot
        snap.bringInEnabled = false
        XCTAssertNil(snap.bringInDay(at: at(8, 13), calendar: calendar))
        snap.bringInEnabled = true
        snap.bringInFromMinutes = 15 * 60
        XCTAssertNil(snap.bringInDay(at: at(8, 13), calendar: calendar))
        XCTAssertNotNil(snap.bringInDay(at: at(8, 15, 30), calendar: calendar))
    }

    func testBringInReminderOnlyTwoWeeksAhead() {
        var settings = ReminderSettings()
        settings.eveningEnabled = false
        let pickups = (0..<8).map { week in PlannedPickup(date: Days.add(week * 7, to: calendar.startOfDay(for: at(8, 0)), calendar: calendar), name: "Restmüll") }
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(8, 7), calendar: calendar)
        XCTAssertEqual(plan.filter { $0.category == .wasteBringIn }.count, 3)   // heute, +7, +14
    }
}
