import XCTest
@testable import TonneCore

final class CoreTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    func day(_ iso: String) -> Date { Days.parse(iso, calendar: calendar)! }

    func testScheduleBiweekly() {
        let schedule = PickupSchedule(intervalWeeks: 2, anchorDate: day("2026-01-02"))
        let dates = ScheduleEngine.pickupDates(schedule, from: day("2026-01-10"), to: day("2026-02-20"), calendar: calendar)
        XCTAssertEqual(dates.map { Days.iso($0, calendar: calendar) }, ["2026-01-16", "2026-01-30", "2026-02-13"])
    }

    func testScheduleAnchorInFutureAndSkips() {
        var schedule = PickupSchedule(intervalWeeks: 1, anchorDate: day("2026-03-04"), explicitDates: [day("2026-02-20")], skippedDates: [day("2026-03-11")])
        let dates = ScheduleEngine.pickupDates(schedule, from: day("2026-02-01"), to: day("2026-03-20"), calendar: calendar)
        XCTAssertEqual(dates.map { Days.iso($0, calendar: calendar) }, ["2026-02-20", "2026-03-04", "2026-03-18"])
        schedule.intervalWeeks = 0
        XCTAssertEqual(ScheduleEngine.nextPickup(schedule, from: day("2026-01-01"), calendar: calendar), day("2026-02-20"))
    }

    func testScheduleAcrossDST() {
        // Sommerzeitumstellung 29.03.2026 darf den 14-Tage-Rhythmus nicht verschieben.
        let schedule = PickupSchedule(intervalWeeks: 2, anchorDate: day("2026-03-16"))
        let dates = ScheduleEngine.pickupDates(schedule, from: day("2026-03-16"), to: day("2026-04-30"), calendar: calendar)
        XCTAssertEqual(dates.map { Days.iso($0, calendar: calendar) }, ["2026-03-16", "2026-03-30", "2026-04-13", "2026-04-27"])
    }

    func testDiff() {
        let diff = ScheduleEngine.diff(old: [day("2026-10-08"), day("2026-10-22")], new: [day("2026-10-09"), day("2026-10-22")], from: day("2026-10-01"), calendar: calendar)
        XCTAssertEqual(diff.added, [day("2026-10-09")])
        XCTAssertEqual(diff.removed, [day("2026-10-08")])
    }

    func testBirthdayLeapYearAndAge() {
        let lena = AnnualDate(day: 29, month: 2, year: 2000)
        XCTAssertEqual(lena.occurrence(inYear: 2027, calendar: calendar), day("2027-02-28"))
        XCTAssertEqual(lena.occurrence(inYear: 2028, calendar: calendar), day("2028-02-29"))
        XCTAssertEqual(lena.next(from: day("2026-10-07"), calendar: calendar), day("2027-02-28"))
        XCTAssertEqual(lena.years(on: day("2027-02-28"), calendar: calendar), 27)
        let today = AnnualDate(day: 7, month: 10)
        XCTAssertEqual(today.next(from: day("2026-10-07"), calendar: calendar), day("2026-10-07"))
        XCTAssertTrue(AnnualDate.isMilestone(50))
        XCTAssertFalse(AnnualDate.isMilestone(51))
        XCTAssertEqual(AnnualDate(day: 1, month: 1).zodiac, "♑︎ Steinbock")
    }

    func testRecurrence() {
        let monthly = Recurrence.everyMonths(6).occurrences(start: day("2026-01-15"), from: day("2026-06-01"), to: day("2027-02-01"), calendar: calendar)
        XCTAssertEqual(monthly.map { Days.iso($0, calendar: calendar) }, ["2026-07-15", "2027-01-15"])
        XCTAssertEqual(Recurrence.once.occurrences(start: day("2026-05-05"), from: day("2026-01-01"), to: day("2026-12-31"), calendar: calendar).count, 1)
        XCTAssertEqual(Recurrence.yearly.next(start: day("2020-06-20"), from: day("2026-10-07"), calendar: calendar), day("2027-06-20"))
    }

    func testCategoryClassification() {
        XCTAssertEqual(WasteCategory.classify("Grünrückstände"), .green)
        XCTAssertEqual(WasteCategory.classify("Biotonne"), .organic)
        XCTAssertEqual(WasteCategory.classify("Gelbe Tonne"), .packaging)
        XCTAssertEqual(WasteCategory.classify("Restmüll 2-Wo"), .residual)
        XCTAssertEqual(WasteCategory.classify("Papier, Pappe, Kartonagen"), .paper)
        XCTAssertEqual(WasteCategory.classify("Schadstoffmobil"), .hazardous)
        XCTAssertEqual(WasteCategory.classify("Weihnachtsbäume"), .green)
        XCTAssertEqual(WasteCategory.classify("Altkleider"), .textiles)
        XCTAssertEqual(WasteCategory.classify("Irgendwas"), .other)
        XCTAssertTrue(WasteCategory.isIgnorableTitle("Repair Café"))
    }

    func testICSParseAndBuild() {
        let text = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        SUMMARY:Gelber\r
          Sack\r
        DTSTART;TZID=Europe/Berlin;VALUE=DATE:20260323\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Papier\\, Pappe\r
        DTSTART:20260106T230000Z\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Bio\r
        DTSTART;VALUE=DATE:20260105\r
        RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=3\r
        END:VEVENT\r
        END:VCALENDAR
        """
        let events = ICS.parse(text, calendar: calendar)
        XCTAssertEqual(events.map(\.summary), ["Bio", "Papier, Pappe", "Bio", "Bio", "Gelber Sack"])
        XCTAssertEqual(events.map { Days.iso($0.date, calendar: calendar) }, ["2026-01-05", "2026-01-07", "2026-01-19", "2026-02-02", "2026-03-23"])

        let feed = ICS.build(name: "Test", events: [ICS.FeedEvent(uid: "x@y", date: day("2026-10-09"), summary: "Gelber Sack; Gifhorn", alarmMinutes: [-300, 420])], calendar: calendar)
        XCTAssertTrue(feed.contains("DTSTART;VALUE=DATE:20261009"))
        XCTAssertTrue(feed.contains("SUMMARY:Gelber Sack\\; Gifhorn"))
        XCTAssertTrue(feed.contains("TRIGGER:-PT5H"))
        XCTAssertTrue(feed.contains("TRIGGER:PT7H"))
        XCTAssertEqual(ICS.trigger(minutes: -(1440 - 19 * 60)), "-PT5H")
        XCTAssertEqual(ICS.trigger(minutes: 540 - 7 * 1440), "-P6DT15H")
        XCTAssertEqual(ICS.parse(feed, calendar: calendar).first?.summary, "Gelber Sack; Gifhorn")
    }

    func testPlanner() {
        var settings = ReminderSettings()
        settings.morningEnabled = true
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day("2026-10-06"))!
        let pickups = [
            PlannedPickup(date: day("2026-10-07"), name: "Restabfall", locationName: "Kuhlhausen"),
            PlannedPickup(date: day("2026-10-08"), name: "Restmüll", locationName: "Gifhorn"),
            PlannedPickup(date: day("2026-10-08"), name: "Gelber Sack", locationName: "Gifhorn"),
            PlannedPickup(date: day("2026-10-10"), name: "Bio", locationName: "Gifhorn", done: true),
        ]
        let birthdays = [PlannedBirthday(date: day("2026-10-08"), name: "Oma Erika", years: 80, remindDaysBefore: 1)]
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: birthdays, settings: settings, now: now, calendar: calendar)
        let ids = plan.map(\.identifier)
        XCTAssertTrue(ids.contains("waste-evening-2026-10-07"))
        XCTAssertTrue(ids.contains("waste-escalation-2026-10-07"))
        XCTAssertTrue(ids.contains("waste-morning-2026-10-07"))
        XCTAssertTrue(ids.contains("waste-evening-2026-10-08"))
        XCTAssertFalse(ids.contains("waste-evening-2026-10-10"), "Erledigte Abholungen bekommen keine Erinnerung")
        let evening8 = plan.first { $0.identifier == "waste-evening-2026-10-08" }!
        XCTAssertEqual(evening8.title, "Morgen wird abgeholt")
        XCTAssertTrue(evening8.body.contains("Restmüll (Gifhorn) und Gelber Sack (Gifhorn)"))
        XCTAssertEqual(calendar.component(.hour, from: evening8.fireDate), 19)
        XCTAssertEqual(Days.iso(evening8.fireDate, calendar: calendar), "2026-10-07")
        let bday = plan.first { $0.category == .birthday && $0.identifier.hasPrefix("bday-2026") }!
        XCTAssertTrue(bday.body.contains("runder Geburtstag"))
        XCTAssertEqual(plan, plan.sorted { $0.fireDate < $1.fireDate })
    }

    func testCatalogSearch() {
        XCTAssertGreaterThan(ProviderCatalog.count, 150)
        XCTAssertEqual(ProviderCatalog.search("gifhorn").first?.serviceKey, "gifhorn")
        XCTAssertEqual(ProviderCatalog.search("Stendal").first?.kind, .abfallAppNet)
        XCTAssertTrue(ProviderCatalog.search("darmstadt").contains { $0.kind == .jumomind })
        XCTAssertTrue(ProviderCatalog.search("tubingen").contains { $0.serviceKey == "tuebingen" })
        XCTAssertTrue(ProviderCatalog.search("Kreis Unna").contains { $0.kind == .abfallnavi })
    }

    func testSourceConfigurationRoundTrip() {
        let config = SourceConfiguration(providerKind: .awido, serviceKey: "gifhorn", selections: [SelectionOption(id: "1", title: "Gifhorn"), SelectionOption(id: "2", title: "Steinstraße")], label: "Gifhorn, Steinstraße")
        XCTAssertEqual(SourceConfiguration.decode(config.encoded()), config)
        XCTAssertEqual(AwidoProvider(customer: "gifhorn").label(for: config.selections), "Gifhorn, Steinstraße")
    }

    func testHTMLHelpers() {
        let html = #"<select name="f_id_kommune"><option value="0">Bitte...</option><option value="2592" selected>Emsdetten</option></select><input type="hidden" name="tok" value="a&amp;b" />"#
        XCTAssertEqual(HTMLText.options(ofSelect: "f_id_kommune", in: html).map(\.label), ["Bitte...", "Emsdetten"])
        XCTAssertEqual(HTMLText.hiddenInputs(in: html).first?.value, "a&b")
        XCTAssertEqual(HTMLText.decodeEntities("Stra&szlig;e &#246;"), "Straße ö")
    }

    func testWidgetSnapshotRoundTrip() throws {
        let snapshot = WidgetSnapshot(locations: [.init(id: "a", name: "Gifhorn", symbolName: "house.fill", colorHex: "#2F6FED")], pickupDays: [.init(date: day("2026-10-08"), items: [.init(name: "Restmüll", symbolName: "trash.fill", colorHex: "#5B6470", locationID: "a", locationName: "Gifhorn")])])
        let decoded = try WidgetSnapshot.decode(try snapshot.encoded())
        XCTAssertEqual(decoded.pickupDays.first?.items.first?.name, "Restmüll")
        XCTAssertEqual(decoded.filtered(locationID: "b").pickupDays.count, 0)
        XCTAssertEqual(decoded.filtered(locationID: "a").pickupDays.count, 1)
    }

    func testWasteABC() {
        XCTAssertEqual(WasteABC.search("pizza").first?.category, .paper)
        XCTAssertGreaterThan(WasteABC.entries.count, 80)
    }
}
