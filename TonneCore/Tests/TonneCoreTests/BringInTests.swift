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

    // MARK: - Tonne, bereitstellen oder hinbringen (Rückmeldung: „bei Schadstoffmobil gibt es keine Tonne“)

    func testHandlingOfUsersExamples() {
        XCTAssertEqual(WasteHandling.of(name: "Schadstoffmobil"), .bringTo)
        XCTAssertEqual(WasteHandling.of(name: "Problemabfall"), .bringTo)
        XCTAssertEqual(WasteHandling.of(name: "Sperrmüll"), .setOut)
        XCTAssertEqual(WasteHandling.of(name: "Weihnachtsbäume"), .setOut)
        XCTAssertEqual(WasteHandling.of(name: "Grünschnitt"), .setOut)
        XCTAssertEqual(WasteHandling.of(name: "Gelber Sack"), .setOut)
        XCTAssertEqual(WasteHandling.of(name: "Gelbe Tonne"), .bin)
        XCTAssertEqual(WasteHandling.of(name: "Restmüll"), .bin)
        XCTAssertEqual(WasteHandling.of(name: "Biotonne"), .bin)
        XCTAssertEqual(WasteHandling.of(name: "Papier"), .bin)
    }

    private func day(_ iso: String) -> Date { Days.parse(iso, calendar: calendar)! }

    private func plan(_ pickups: [PlannedPickup]) -> [PlannedNotification] {
        var settings = ReminderSettings()
        settings.morningEnabled = true
        settings.bringInEnabled = false
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day("2026-10-20"))!
        return ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: now, calendar: calendar)
    }

    private func texts(_ plan: [PlannedNotification]) -> String { plan.map { $0.title + " " + $0.body }.joined(separator: " | ") }

    func testDropOffDayNeverTalksAboutBinsOrPuttingOut() {
        let result = plan([PlannedPickup(date: day("2026-10-22"), name: "Schadstoffmobil", note: "Aßlar, Am Grauen Stein 6 (08:00 - 12:00)")])
        XCTAssertFalse(result.contains { $0.category == .wasteEscalation }, "kein „Steht … draußen?“ beim Schadstoffmobil")
        let all = texts(result)
        for word in ["Tonne", "draußen", "rausstell", "bin", "put out"] { XCTAssertFalse(all.contains(word), "„\(word)“ in: \(all)") }
        let evening = result.first { $0.category == .wasteEvening }!
        XCTAssertEqual(evening.title, "Morgen: Schadstoffmobil")
        XCTAssertTrue(evening.body.contains("hinbringen: Aßlar, Am Grauen Stein 6 (08:00 - 12:00)"), evening.body)
        XCTAssertTrue(evening.bringOnly)
        XCTAssertTrue(result.first { $0.category == .wasteMorning }!.body.contains("08:00 - 12:00"))
    }

    func testBagAndBulkySayPutOutButNeverBin() {
        for name in ["Gelber Sack", "Sperrmüll", "Weihnachtsbäume"] {
            let all = texts(plan([PlannedPickup(date: day("2026-10-22"), name: name)]))
            XCTAssertFalse(all.contains("Tonne"), "\(name): \(all)")
            XCTAssertTrue(all.contains("bereitgestellt") || all.contains("bereitstellen") || all.contains("rausgestellt"), "\(name): \(all)")
        }
        XCTAssertTrue(texts(plan([PlannedPickup(date: day("2026-10-22"), name: "Restmüll")])).contains("Steht die Tonne schon draußen?"))
    }

    func testMixedDayKeepsEscalationButNotForDropOff() {
        let result = plan([PlannedPickup(date: day("2026-10-22"), name: "Biotonne"),
                           PlannedPickup(date: day("2026-10-22"), name: "Schadstoffmobil", note: "Rathaus, 9–11 Uhr")])
        let escalation = result.first { $0.category == .wasteEscalation }!
        XCTAssertFalse(escalation.body.contains("Schadstoffmobil"), escalation.body)
        let evening = result.first { $0.category == .wasteEvening }!
        XCTAssertEqual(evening.body, "Biotonne heute Abend rausstellen, Schadstoffmobil (Rathaus, 9–11 Uhr) morgen hinbringen.")
        XCTAssertTrue(evening.bringOnly, "gemischt: Knopf nur „Erledigt“, nicht „steht draußen“")
        XCTAssertFalse(escalation.bringOnly, "Nachhaken betrifft nur die Tonne")
    }

    func testWidgetHintOnMixedDayMentionsDropOff() {
        let mixed = PickupWording([.init(name: "Biotonne", handling: .bin), .init(name: "Schadstoffmobil", handling: .bringTo)])
        XCTAssertEqual(mixed.hint(daysUntil: 1, done: false), "rausstellen und hinbringen")
        XCTAssertEqual(mixed.hint(daysUntil: 0, done: false), "Abfuhr und hinbringen")
        XCTAssertEqual(mixed.hint(daysUntil: 1, done: true), "erledigt 👍")
        let bins = PickupWording([.init(name: "Biotonne", handling: .bin), .init(name: "Gelber Sack", handling: .setOut)])
        XCTAssertEqual(bins.hint(daysUntil: 1, done: false), "abends rausstellen")
        XCTAssertEqual(bins.hint(daysUntil: 1, done: true), "steht draußen 👍")
    }

    func testNoteIsIgnoredForBins() {
        // AWIDO schickt bei Tonnen nur die Straße – das soll nicht in der Erinnerung stehen
        let all = texts(plan([PlannedPickup(date: day("2026-10-22"), name: "Restmüll", note: "Weiden, Ackerstraße")]))
        XCTAssertFalse(all.contains("Ackerstraße"), all)
    }

    func testNoLiveActivityForDropOffOnlyDays() {
        let today = Days.today()
        let item = WidgetSnapshot.PickupItem(name: "Schadstoffmobil", symbolName: "exclamationmark.triangle.fill", colorHex: "#DC2626")
        let days = [WidgetSnapshot.PickupDay(date: Days.add(1, to: today), items: [item])]
        XCTAssertTrue(LiveActivityPlanner.plan(pickupDays: days, now: Date(), eveningMinutes: 19 * 60, canSchedule: true).isEmpty)
        XCTAssertEqual(PickupWording(names: ["Schadstoffmobil"], symbols: []).hint(daysUntil: 1, done: false), "morgen hinbringen")
        XCTAssertEqual(PickupWording(names: ["Restmüll"], symbols: []).hint(daysUntil: 1, done: false), "abends rausstellen")
    }

    func testStoredCategoryAndAnnahmeAreDropOff() {
        XCTAssertEqual(WasteHandling.of(name: "Sondertermin", category: .hazardous), .bringTo, "umbenanntes Schadstoffmobil")
        XCTAssertEqual(WasteHandling.of(name: "Elektroschrott-Annahme"), .bringTo)
        XCTAssertEqual(WasteHandling.of(name: "Grünschnitt-Tonne"), .bin)
        XCTAssertEqual(WasteHandling.of(name: "Wertstofftonne"), .bin)
    }

    func testMixedDayDoneInTheEveningKeepsMorningDropOffReminder() {
        let result = plan([PlannedPickup(date: day("2026-10-22"), name: "Biotonne", done: true),
                           PlannedPickup(date: day("2026-10-22"), name: "Schadstoffmobil", done: true, note: "Rathaus, 9–11 Uhr")])
        XCTAssertFalse(result.contains { $0.category == .wasteEvening || $0.category == .wasteEscalation }, "Tonne ist erledigt")
        let morning = result.first { $0.category == .wasteMorning }
        XCTAssertEqual(morning?.title, "Heute: Schadstoffmobil")
        XCTAssertEqual(morning?.body, "Heute hinbringen: Rathaus, 9–11 Uhr")
        XCTAssertEqual(morning?.bringOnly, true)
    }

    func testSnapshotDropOffFlagWinsAndOldSnapshotsDecode() throws {
        let flagged = WidgetSnapshot.PickupItem(name: "Sondertermin", symbolName: "trash.fill", colorHex: "#DC2626", dropOff: true)
        XCTAssertTrue(PickupWording(day: WidgetSnapshot.PickupDay(date: Days.today(), items: [flagged])).onlyBringTo)
        let old = ##"{"name":"Schadstoffmobil","symbolName":"trash.fill","colorHex":"#DC2626"}"##
        let decoded = try JSONDecoder().decode(WidgetSnapshot.PickupItem.self, from: Data(old.utf8))
        XCTAssertNil(decoded.dropOff)
        XCTAssertTrue(PickupWording(day: WidgetSnapshot.PickupDay(date: Days.today(), items: [decoded])).onlyBringTo)
    }

    func testAnnahmeOnlyAsAcceptancePoint() {
        XCTAssertEqual(WasteHandling.of(name: "Annahme"), .bringTo)
        XCTAssertEqual(WasteHandling.of(name: "Grünschnittannahme"), .bringTo)
        XCTAssertEqual(WasteHandling.of(name: "Grüngut Annahmestelle"), .bringTo)
        XCTAssertNotEqual(WasteHandling.of(name: "Annahmeschluss Sperrmüll"), .bringTo)
        XCTAssertNotEqual(WasteHandling.of(name: "Sperrmüll nach Annahme"), .bringTo)
        XCTAssertEqual(WasteHandling.of(name: "Annahmetonne"), .bin)
    }

    func testDropOffMarkedDoneOnTheDayItselfGetsNoMorningReminder() {
        let pickupDay = day("2026-10-22")
        func morning(doneAt: Date?) -> PlannedNotification? {
            plan([PlannedPickup(date: pickupDay, name: "Biotonne", done: true, doneAt: doneAt),
                  PlannedPickup(date: pickupDay, name: "Schadstoffmobil", done: true, note: "Rathaus", doneAt: doneAt)])
                .first { $0.category == .wasteMorning }
        }
        let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day("2026-10-21"))!
        let sameMorning = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: pickupDay)!
        XCTAssertEqual(morning(doneAt: evening)?.title, "Heute: Schadstoffmobil", "am Vorabend abgehakt: trotzdem hinbringen")
        XCTAssertNil(morning(doneAt: sameMorning), "am Abholtag abgehakt: schon hingebracht")
    }

    func testDropOffIsNeverBroughtBackIn() {
        var settings = ReminderSettings()
        settings.eveningEnabled = false
        let today = calendar.startOfDay(for: at(8, 0))
        // umbenannt, mit Tonnen-Symbol, aber als Schadstoff gespeichert
        let pickups = [PlannedPickup(date: today, name: "Restmüll Sondertermin", symbolName: "trash.fill", done: true, handling: .bringTo)]
        XCTAssertFalse(pickups[0].isBin)
        XCTAssertTrue(ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: at(8, 7), calendar: calendar)
            .filter { $0.category == .wasteBringIn }.isEmpty)
        let item = WidgetSnapshot.PickupItem(name: "Restmüll Sondertermin", symbolName: "trash.fill", colorHex: "#5B6470", dropOff: true)
        let snap = WidgetSnapshot(pickupDays: [.init(date: today, items: [item], done: true)])
        XCTAssertNil(snap.bringInDay(at: at(8, 14), calendar: calendar))
    }
}
