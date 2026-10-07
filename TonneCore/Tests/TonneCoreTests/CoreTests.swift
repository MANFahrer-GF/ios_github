import XCTest
@testable import TonneCore

final class CoreTests: XCTestCase {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = "de"
    }

    func day(_ iso: String) -> Date { Days.parse(iso, calendar: calendar)! }

    func testUpcomingBirthdays() {
        let today = Days.today()
        let item = { (offset: Int, name: String) in WidgetSnapshot.BirthdayItem(date: Days.add(offset, to: today), name: name, years: nil, colorHex: "#000000", initials: "X") }
        let snapshot = WidgetSnapshot(birthdays: [item(3, "C"), item(0, "A"), item(0, "B"), item(1, "D")])
        let tomorrow = snapshot.upcomingBirthdays(from: Days.add(1, to: today))
        XCTAssertEqual(tomorrow.birthdays.map(\.name), ["D", "C"])
        XCTAssertEqual(snapshot.upcomingBirthdays(from: today).birthdays.map(\.name).prefix(2).sorted(), ["A", "B"])
    }

    func testPickupItemKeepsSFName() {
        let item = WidgetSnapshot.PickupItem(name: "Gelber Sack", symbolName: "tt.sack", colorHex: "#F2C230")
        XCTAssertEqual(item.symbolName, "bag.fill")
        XCTAssertEqual(item.displaySymbol, "tt.sack")
        // Ältere Schnappschüsse ohne glyphName lassen sich weiter lesen
        let old = ##"{"name":"Restmüll","symbolName":"trash.fill","colorHex":"#5B6470"}"##
        let decoded = try? JSONDecoder().decode(WidgetSnapshot.PickupItem.self, from: Data(old.utf8))
        XCTAssertEqual(decoded?.displaySymbol, "trash.fill")
    }

    func testShortNames() {
        XCTAssertEqual(ReminderPlanner.shortNames(["A"], max: 2), "A")
        XCTAssertEqual(ReminderPlanner.shortNames(["A", "B", "C"], max: 3), "A, B, C")
        XCTAssertEqual(ReminderPlanner.shortNames(["A", "B", "C"], max: 4), "A, B, C")
        XCTAssertEqual(ReminderPlanner.shortNames(["A", "B", "C", "D"], max: 2), "A, B +2")
        XCTAssertEqual(ReminderPlanner.shortNames(["A", "B"], max: 0), "A +1")
    }

    func testWasteGlyph() {
        XCTAssertEqual(WasteGlyph.assetName(for: "bag.fill", name: "Gelber Sack"), "tt.sack")
        XCTAssertEqual(WasteGlyph.assetName(for: "bag.fill", name: "Gelbe Tonne"), "tt.bin.yellow")
        XCTAssertEqual(WasteGlyph.assetName(for: "bag.fill", name: "Wertstofftonne"), "tt.bin.yellow")
        XCTAssertEqual(WasteGlyph.assetName(for: "trash.fill"), "tt.bin")
        XCTAssertEqual(WasteGlyph.assetName(for: "leaf.fill", name: "Biotonne"), "tt.bin.bio")
        XCTAssertNil(WasteGlyph.assetName(for: "leaf.fill", name: "Laubsammlung"))
        XCTAssertNil(WasteGlyph.assetName(for: "tree.fill", name: "Weihnachtsbäume"))
        XCTAssertNil(WasteGlyph.assetName(for: "sofa.fill"))
        XCTAssertEqual(WasteGlyph.assetName(for: "bag.fill", name: "Yellow bin"), "tt.bin.yellow")
        XCTAssertNil(WasteGlyph.assetName(for: "leaf.fill", name: "Leaf collection"))
        XCTAssertNil(WasteGlyph.assetName(for: "tree.fill", name: "Christmas trees"))
        XCTAssertNil(WasteGlyph.assetName(for: "checkmark.circle"))
        XCTAssertEqual(WasteGlyph.assetName(for: "bag.fill", name: "Kombinierte Wertstoffsammlung"), "tt.sack")
        // Direkt gewählt: gilt unabhängig vom Namen
        XCTAssertEqual(WasteGlyph.assetName(for: "tt.bin.yellow", name: "Gelber Sack"), "tt.bin.yellow")
        XCTAssertEqual(WasteGlyph.pickerSymbols.prefix(7), ["tt.bin", "tt.bin.bio", "tt.bin.paper", "tt.bin.yellow", "tt.sack", "tt.glass", "tt.green"])
        XCTAssertFalse(WasteGlyph.pickerSymbols.contains("bag.fill"))
        XCTAssertTrue(WasteGlyph.pickerSymbols.contains("sofa.fill"))
        XCTAssertTrue(WasteGlyph.matches("tt.sack", current: "bag.fill", name: "Gelber Sack"))
        XCTAssertTrue(WasteGlyph.matches("tt.bin.yellow", current: "bag.fill", name: "Gelbe Tonne"))
        XCTAssertFalse(WasteGlyph.matches("tt.sack", current: "bag.fill", name: "Gelbe Tonne"))
        XCTAssertTrue(WasteGlyph.pickerSymbols.contains("leaf"))
        XCTAssertTrue(WasteGlyph.pickerSymbols.contains("tree"))
        XCTAssertTrue(WasteGlyph.matches("leaf", current: "leaf.fill", name: "Laubsammlung"))
        XCTAssertTrue(WasteGlyph.matches("tt.bin.bio", current: "leaf.fill", name: "Biotonne"))
        XCTAssertFalse(WasteGlyph.matches("leaf", current: "leaf.fill", name: "Biotonne"))
        XCTAssertNil(WasteGlyph.assetName(for: "leaf"))
        XCTAssertNil(WasteGlyph.assetName(for: "tree.fill", name: "Christbaumabholung"))
        XCTAssertNil(WasteGlyph.assetName(for: "tree.fill", name: "Tannenbäume"))
        XCTAssertNil(WasteGlyph.assetName(for: "leaf.fill", name: "Laubsäcke"))
        XCTAssertEqual(WasteGlyph.assetName(for: "leaf.fill", name: "Biotonne Urlaubsvertretung"), "tt.bin.bio")
        XCTAssertEqual(WasteGlyph.assetName(for: "bag.fill", name: "Wertstofftonne"), "tt.bin.yellow")
        XCTAssertEqual(WasteGlyph.sfFallback(for: "tt.sack"), "bag.fill")
        XCTAssertEqual(WasteGlyph.sfFallback(for: "tt.bin.yellow"), "bag.fill")
        XCTAssertEqual(WasteGlyph.sfFallback(for: "sofa.fill"), "sofa.fill")
        for asset in WasteGlyph.all {
            XCTAssertNotEqual(WasteGlyph.accessibilityName(for: asset), asset)
            XCTAssertNotNil(WasteGlyph.sfFallback(for: asset).firstIndex(of: "."))
            XCTAssertFalse(WasteGlyph.sfFallback(for: asset).hasPrefix("tt."))
        }
        // Jedes Symbol der Auswahl ist genau einmal drin
        XCTAssertEqual(Set(WasteGlyph.pickerSymbols).count, WasteGlyph.pickerSymbols.count)
        for category in WasteCategory.allCases {
            if let asset = WasteGlyph.assetName(for: category.symbolName, name: category.name) {
                XCTAssertTrue(WasteGlyph.all.contains(asset))
            }
        }
    }

    func testL10n() {
        L10n.forcedLanguage = "en-US"
        XCTAssertEqual(WasteCategory.packaging.name, "Packaging")
        XCTAssertEqual(Recurrence.everyWeeks(2).label, "Every 2 weeks")
        XCTAssertEqual(ReminderPlanner.joinNames(["A", "B", "C"]), "A, B and C")
        L10n.forcedLanguage = "de"
        XCTAssertEqual(WasteCategory.packaging.name, "Gelber Sack")
        XCTAssertEqual(ReminderPlanner.joinNames(["A", "B", "C"]), "A, B und C")
    }

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

    func testProviderLabels() {
        let awsh = AWSHProvider()
        let picks = [SelectionOption(id: "83", title: "Lauenburg"), SelectionOption(id: "1", title: "Hauptstraße"),
                     SelectionOption(id: "type:R02", title: "Restabfall 40L-240L · 2-wöchentlich"), SelectionOption(id: "type:none:P", title: "Habe ich nicht")]
        XCTAssertEqual(awsh.label(for: picks), "Lauenburg, Hauptstraße")
        let existential: WasteProvider = awsh
        XCTAssertEqual(existential.label(for: picks), "Lauenburg, Hauptstraße")
        let bsr: WasteProvider = BSRProvider()
        XCTAssertEqual(bsr.label(for: [SelectionOption(id: "Alex", title: "Alex"), SelectionOption(id: "Alexanderstr.", title: "Alexanderstr."), SelectionOption(id: "5", title: "5"), SelectionOption(id: "k", title: "Alexanderstr. 5, 10178 Berlin (Mitte)")]), "Alexanderstr. 5, 10178 Berlin (Mitte)")
    }

    func testRecurrenceKeepsEndOfMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let end = cal.date(from: DateComponents(year: 2026, month: 5, day: 31))!
        let days = Recurrence.everyMonths(1).occurrences(start: start, from: start, to: end, calendar: cal).map { cal.component(.day, from: $0) }
        XCTAssertEqual(days, [31, 28, 31, 30, 31])

        let leap = cal.date(from: DateComponents(year: 2024, month: 2, day: 29))!
        let until = cal.date(from: DateComponents(year: 2028, month: 3, day: 1))!
        let leapDays = Recurrence.yearly.occurrences(start: leap, from: leap, to: until, calendar: cal).map { cal.component(.day, from: $0) }
        XCTAssertEqual(leapDays, [29, 28, 28, 28, 29])
    }

    func testCatalogSearch() {
        XCTAssertGreaterThan(ProviderCatalog.count, 300)
        XCTAssertEqual(ProviderCatalog.search("Köln").first?.kind, .awbKoeln)
        XCTAssertTrue(ProviderCatalog.search("Hannover").contains { $0.kind == .ahaHannover })
        XCTAssertTrue(ProviderCatalog.search("Bremen").contains { $0.kind == .cTrace })
        XCTAssertEqual(ProviderCatalog.search("gifhorn").first?.serviceKey, "gifhorn")
        XCTAssertEqual(ProviderCatalog.search("Stendal").first?.kind, .abfallAppNet)
        XCTAssertTrue(ProviderCatalog.search("darmstadt").contains { $0.kind == .jumomind })
        XCTAssertTrue(ProviderCatalog.search("tubingen").contains { $0.serviceKey == "tuebingen" })
        // Stichproben aus Norddeutschland: Ort → Landkreis → Entsorger
        XCTAssertTrue(ProviderCatalog.search("Boizenburg").contains { $0.kind == .gemosWasteBox }, "Boizenburg")
        XCTAssertTrue(ProviderCatalog.search("Nostorf").contains { $0.kind == .gemosWasteBox }, "Nostorf")
        XCTAssertEqual(ProviderCatalog.search("Rensdorf").first?.kind, .gemosWasteBox, "Rensdorf")
        XCTAssertTrue(ProviderCatalog.search("Lauenburg").contains { $0.kind == .awsh }, "Lauenburg")
        XCTAssertTrue(ProviderCatalog.search("Lüneburg").contains { $0.kind == .abfallPlusApp }, "Lüneburg")
        XCTAssertTrue(ProviderCatalog.search("Adendorf").contains { $0.serviceKey == "de.abfallplus.gfaabfallinfo" }, "Adendorf")
        XCTAssertEqual(ProviderCatalog.search("Berlin").first?.kind, .bsr, "Berlin")
        XCTAssertTrue(ProviderCatalog.search("Pankow").contains { $0.kind == .bsr }, "Pankow")
        XCTAssertTrue(ProviderCatalog.search("Einbeck").contains { $0.kind == .nerdbridge }, "Einbeck")
        XCTAssertTrue(ProviderCatalog.search("Iserlohn").contains { $0.kind == .lobbe }, "Iserlohn")
        XCTAssertTrue(ProviderCatalog.search("Eppstein").contains { $0.kind == .icsURL }, "Eppstein")
        XCTAssertEqual(ProviderCatalog.municipalities(matching: "Nostorf").first?.district, "Landkreis Ludwigslust-Parchim")
        XCTAssertNotNil(ProviderCatalog.municipalityHint(for: "Boizenburg"))
        XCTAssertTrue(AbfallPlusAppProvider.isPlaceholder("Leni (39)"))
        XCTAssertFalse(AbfallPlusAppProvider.isPlaceholder("Graue Tonne"))
        XCTAssertFalse(AbfallPlusAppProvider.isPlaceholder("Restmüll (240 l)"))
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

    func testBirthdayExportCSV() {
        let rows = [
            BirthdayExport.Row(name: "Oma Erika", annual: AnnualDate(day: 8, month: 10, year: 1948), notes: "Mag Blumen; keine Pralinen", giftIdeas: ["Schal", "Buch"]),
            BirthdayExport.Row(name: "Lena", annual: AnnualDate(day: 29, month: 2), remindersEnabled: false, remindDaysBefore: 7),
        ]
        let csv = BirthdayExport.csv(rows, from: day("2026-10-07"), calendar: calendar)
        let lines = csv.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Name;Geburtstag;Geburtsjahr;Alter"))
        XCTAssertTrue(lines[1].hasPrefix("Oma Erika;08.10.1948;1948;77;2026-10-08;1;78;"))
        XCTAssertTrue(lines[1].contains("\"Mag Blumen; keine Pralinen\""))
        XCTAssertTrue(lines[2].hasPrefix("Lena;29.02.;;;2027-02-28;144;;"))
        XCTAssertEqual(BirthdayExport.currentAge(AnnualDate(day: 8, month: 10, year: 1948), from: day("2026-10-08"), calendar: calendar), 78)
    }

    func testWasteABC() {
        XCTAssertEqual(WasteABC.search("pizza").first?.category, .paper)
        XCTAssertGreaterThan(WasteABC.entries.count, 80)
    }
}
