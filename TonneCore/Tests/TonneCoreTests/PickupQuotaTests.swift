import XCTest
@testable import TonneCore

/// Leerungs-Statistik mit Freileerungen (Konzept 16.11.2026, Abschnitt 5).
final class PickupQuotaTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func d(_ year: Int, _ month: Int, _ day: Int) -> Date { Days.make(year: year, month: month, day: day, calendar: calendar)! }
    private func year(_ y: Int) -> QuotaPeriod { PickupQuota.period(containing: d(y, 6, 1), calendar: calendar) }

    override func setUp() { L10n.forcedLanguage = "de" }
    override func tearDown() { L10n.forcedLanguage = nil }

    /// Restmüll alle zwei Wochen 2026 ab 8. Januar.
    private var biweekly2026: [Date] { (0..<26).map { Days.add($0 * 14, to: d(2026, 1, 8), calendar: calendar) } }

    // MARK: - Zeitraum, Jahreswechsel, Stichtag

    func testCalendarYearAndYearChange() {
        let period = year(2026)
        XCTAssertEqual(period.start, d(2026, 1, 1))
        XCTAssertEqual(period.end, d(2027, 1, 1))
        XCTAssertEqual(period.label(calendar: calendar), "2026")
        // Jahreswechsel: Zähler startet neu, das Vorjahr bleibt einsehbar
        let input = QuotaInput(done: [d(2025, 12, 18), d(2025, 12, 30), d(2026, 1, 8)], included: 12)
        let now = PickupQuota.summary(input, period: year(2026), today: d(2026, 1, 9), calendar: calendar)
        XCTAssertEqual(now.used, 1)
        XCTAssertEqual(now.free, 11)
        let previous = PickupQuota.previous(year(2026), calendar: calendar)
        XCTAssertEqual(previous, year(2025))
        XCTAssertEqual(PickupQuota.summary(input, period: previous, today: d(2026, 1, 9), calendar: calendar).used, 2)
    }

    func testCutoffDateStartsFeeYear() {
        let anchor = d(2020, 4, 1)
        let before = PickupQuota.period(containing: d(2026, 3, 31), anchor: anchor, calendar: calendar)
        XCTAssertEqual(before, QuotaPeriod(start: d(2025, 4, 1), end: d(2026, 4, 1)))
        XCTAssertEqual(before.label(calendar: calendar), "2025/26")
        let on = PickupQuota.period(containing: d(2026, 4, 1), anchor: anchor, calendar: calendar)
        XCTAssertEqual(on, QuotaPeriod(start: d(2026, 4, 1), end: d(2027, 4, 1)))
        // Marke am 31.3. gehört zum alten, am 1.4. zum neuen Gebührenjahr
        let input = QuotaInput(done: [d(2026, 3, 31), d(2026, 4, 1)], included: 12)
        XCTAssertEqual(PickupQuota.summary(input, period: before, today: d(2026, 4, 2), calendar: calendar).used, 1)
        XCTAssertEqual(PickupQuota.summary(input, period: on, today: d(2026, 4, 2), calendar: calendar).used, 1)
        // 29. Februar als Stichtag: im Nicht-Schaltjahr der 28.
        let leap = PickupQuota.period(containing: d(2027, 3, 1), anchor: d(2024, 2, 29), calendar: calendar)
        XCTAssertEqual(leap.start, d(2027, 2, 28))
        XCTAssertEqual(leap.end, d(2028, 2, 29))
    }

    // MARK: - Kontingent erreicht und überschritten, Kosten

    func testQuotaReached() {
        let dates = Array(biweekly2026.prefix(3))
        let summary = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: dates, included: 3), period: year(2026), today: d(2026, 2, 10), calendar: calendar)
        XCTAssertEqual(summary.used, 3)
        XCTAssertEqual(summary.free, 0)
        XCTAssertTrue(summary.isExhausted)
        XCTAssertEqual(summary.overBy, 0)
        XCTAssertEqual(summary.prognosis, .exhausted)
        XCTAssertEqual(PickupQuota.freeLine(summary), "alle 3 genutzt")
        XCTAssertEqual(PickupQuota.headline(summary), "3 von 3")
    }

    func testQuotaExceededWithCost() {
        let dates = Array(biweekly2026.prefix(5))
        let summary = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: dates, included: 3, pricePerExtra: 4.2),
                                          period: year(2026), today: d(2026, 3, 10), calendar: calendar)
        XCTAssertEqual(summary.used, 5)
        XCTAssertEqual(summary.overBy, 2)
        XCTAssertEqual(summary.free, 0)
        XCTAssertEqual(summary.extraCost ?? 0, 8.4, accuracy: 0.0001)
        XCTAssertEqual(PickupQuota.freeLine(summary), "2 über dem Kontingent von 3")
    }

    func testOpenAndRemainingAndPrognosis() {
        // 12 frei, 5 vergangene Termine: 2 raus, 1 nicht raus, 2 offen; heute (5.3.) ist ein Termin ohne Markierung
        let past = Array(biweekly2026.prefix(5))
        let input = QuotaInput(scheduled: biweekly2026, done: [past[0], past[2]], notOut: [past[1]], included: 12)
        let today = biweekly2026[5]
        let summary = PickupQuota.summary(input, period: year(2026), today: today, calendar: calendar)
        XCTAssertEqual(summary.used, 2)
        XCTAssertEqual(summary.open, 2, "offen zählt nie als genutzt")
        XCTAssertEqual(summary.decided, 3)
        XCTAssertEqual(summary.free, 10)
        XCTAssertEqual(summary.remaining, 21, "heute ohne Markierung kommt noch")
        XCTAssertEqual(summary.pastCount, 5)
        XCTAssertEqual(PickupQuota.freeLine(summary), "noch 10 von 12 frei")
        // Tempo 2 von 3 → 10 freie reichen für 15 Termine, also bis zum 15. kommenden Termin
        XCTAssertEqual(summary.prognosis, .runsOut(biweekly2026[5 + 14]))
        // Halbes Tempo: reicht bis Jahresende
        let slow = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: [past[0]], notOut: Array(past[1...4]), included: 12),
                                       period: year(2026), today: today, calendar: calendar)
        XCTAssertEqual(slow.prognosis, .lastsUntilEnd)
        // Ohne Kontingent: nur die Zählung
        let plain = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: [past[0], past[2]], notOut: [past[1]]), period: year(2026), today: today, calendar: calendar)
        XCTAssertNil(plain.included)
        XCTAssertNil(PickupQuota.freeLine(plain))
        XCTAssertEqual(plain.prognosis, .none)
        XCTAssertEqual(PickupQuota.headline(plain), "2 von 5 Terminen rausgestellt")
    }

    // MARK: - Tag mit zwei Müllarten

    func testDayWithTwoTypesNeedsChoice() {
        XCTAssertFalse(PickupQuota.needsChoice(counted: [true]), "nur eine Müllart: wie heute")
        XCTAssertFalse(PickupQuota.needsChoice(counted: [false, false]), "keine gezählte: wie heute")
        XCTAssertTrue(PickupQuota.needsChoice(counted: [true, false]))
        XCTAssertFalse(PickupQuota.needsChoice(counted: []))
    }

    func testBlanketFromWidgetMarksAllButFlagsCountedType() {
        let types = [(id: "rest", counted: true), (id: "papier", counted: false)]
        let widget = PickupQuota.resolve(.blanket, types: types)
        XCTAssertEqual(widget.out, ["rest", "papier"], "„Erledigt“ markiert wie heute alle")
        XCTAssertEqual(widget.bulk, ["rest"], "der gezählte Tag gilt als pauschal bestätigt")
        XCTAssertTrue(widget.notOut.isEmpty)
        // Nur eine Müllart: kein Nachfragen
        XCTAssertTrue(PickupQuota.resolve(.blanket, types: [(id: "rest", counted: true)]).bulk.isEmpty)
    }

    func testSheetAndNotificationActions() {
        let types = [(id: "rest", counted: true), (id: "papier", counted: false)]
        // „Alles raus“ / Blatt mit allen Häkchen: ausdrücklich, nichts nachzufragen
        let all = PickupQuota.resolve(.chosen(left: []), types: types)
        XCTAssertEqual(all.out, ["rest", "papier"])
        XCTAssertTrue(all.bulk.isEmpty)
        // „Ohne Restmüll“ / Häkchen weg: Restmüll ist „nicht raus“, nicht „offen“
        let without = PickupQuota.resolve(.chosen(left: ["rest"]), types: types)
        XCTAssertEqual(without.out, ["papier"])
        XCTAssertEqual(without.notOut, ["rest"])
        XCTAssertTrue(without.bulk.isEmpty)
    }

    func testBulkConfirmedCountsButIsAskedAgain() {
        let day = biweekly2026[2]
        let input = QuotaInput(scheduled: biweekly2026, done: [day], bulkConfirmed: [day], included: 12)
        let summary = PickupQuota.summary(input, period: year(2026), today: Days.add(3, to: day, calendar: calendar), calendar: calendar)
        XCTAssertEqual(summary.used, 1)
        XCTAssertEqual(summary.bulk, 1)
        let catchUp = PickupQuota.catchUp(input, today: Days.add(3, to: day, calendar: calendar), calendar: calendar)
        XCTAssertTrue(catchUp.contains { $0.date == day && $0.bulkConfirmed })
    }

    // MARK: - Abgleich ersetzt Termine

    func testSyncReplacingDatesKeepsMarks() {
        // Termin 12.3. wurde markiert, dann verschiebt der Abgleich ihn auf den 13.3.
        let moved = biweekly2026.map { $0 == d(2026, 3, 12) ? d(2026, 3, 13) : $0 }
        let input = QuotaInput(scheduled: moved, done: [d(2026, 3, 12)], included: 12)
        let summary = PickupQuota.summary(input, period: year(2026), today: d(2026, 3, 20), calendar: calendar)
        XCTAssertEqual(summary.used, 1, "die Markierung hängt am Datum")
        XCTAssertTrue(summary.entries.contains { $0.date == d(2026, 3, 12) && $0.mark == .out })
        // Vergangene Termine bleiben beim Ersetzen stehen
        let kept = PickupQuota.pastDatesKeptOnSync(old: [d(2026, 3, 1), d(2026, 3, 19), d(2026, 3, 20), d(2026, 4, 2)], today: d(2026, 3, 20), calendar: calendar)
        XCTAssertEqual(kept, [d(2026, 3, 1), d(2026, 3, 19)])
    }

    // MARK: - Zusatzleerung und Startwert

    func testExtraPickupAndBaseline() {
        // Kontingent mitten im Jahr eingeschaltet: „bis 20.11. laut Angabe: 6“
        let baselineDay = d(2026, 11, 20)
        let earlier = biweekly2026.filter { $0 <= baselineDay }
        let input = QuotaInput(scheduled: biweekly2026, done: [earlier[0], earlier[1]], extra: [d(2026, 11, 24)],
                               included: 12, baseline: 6, baselineDate: baselineDay)
        let summary = PickupQuota.summary(input, period: year(2026), today: d(2026, 11, 25), calendar: calendar)
        XCTAssertEqual(summary.used, 7, "6 laut Angabe + 1 Zusatzleerung; frühere Markierungen stecken im Startwert")
        XCTAssertEqual(summary.open, 0, "vor dem Startwert ist nichts offen")
        XCTAssertTrue(summary.entries.contains { $0.date == d(2026, 11, 24) && $0.isExtra && $0.mark == .out })
        XCTAssertEqual(summary.free, 5)
        // Startwert gilt nur in seinem Zeitraum
        XCTAssertEqual(PickupQuota.summary(input, period: year(2027), today: d(2027, 1, 2), calendar: calendar).used, 0)
    }

    // MARK: - Tonnendienst

    func testOffDutyHiddenUnlessCounted() {
        let past = Array(biweekly2026.prefix(4))
        let offDuty: Set<Date> = [past[1], past[3]]
        let today = d(2026, 3, 1)
        let hidden = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: [past[0], past[2]], offDuty: offDuty, included: 12),
                                         period: year(2026), today: today, calendar: calendar)
        XCTAssertEqual(hidden.open, 0, "fremde Tage ausgeblendet")
        XCTAssertFalse(hidden.entries.contains { $0.date == past[1] })
        XCTAssertEqual(hidden.used, 2)
        let counted = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: [past[0], past[2]], offDuty: offDuty, countOffDuty: true, included: 12),
                                          period: year(2026), today: today, calendar: calendar)
        XCTAssertEqual(counted.open, 2, "geteilte Tonne: fremde Tage stehen offen zum Nachtragen")
        XCTAssertTrue(counted.entries.contains { $0.date == past[1] && $0.offDuty && $0.mark == .open })
        // Hat jemand an einem fremden Tag doch markiert, zählt es trotzdem
        let marked = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: [past[1]], offDuty: offDuty, included: 12),
                                         period: year(2026), today: today, calendar: calendar)
        XCTAssertEqual(marked.used, 1)
    }

    // MARK: - Kontingentänderung mitten im Jahr

    func testQuotaChangeMidYear() {
        var changes = PickupQuota.recording(12, at: d(2025, 3, 1), into: [], calendar: calendar)
        changes = PickupQuota.recording(26, at: d(2026, 7, 1), into: changes, calendar: calendar)
        // Am selben Tag ersetzt eine neue Angabe die vorige
        changes = PickupQuota.recording(20, at: d(2026, 7, 1), into: changes, calendar: calendar)
        XCTAssertEqual(changes.count, 2)
        let done = Array(biweekly2026.prefix(10))
        let input = QuotaInput(scheduled: biweekly2026, done: done, included: 20, changes: changes)
        let now = PickupQuota.summary(input, period: year(2026), today: d(2026, 7, 2), calendar: calendar)
        XCTAssertEqual(now.included, 20, "gilt ab Änderung")
        XCTAssertEqual(now.used, 10, "der bisherige Stand bleibt")
        XCTAssertEqual(now.free, 10)
        XCTAssertEqual(PickupQuota.included(in: year(2025), current: 20, changes: changes), 12, "Vorjahr behält sein Kontingent")
        XCTAssertNil(PickupQuota.included(in: year(2024), current: 20, changes: changes), "vor der Einrichtung kein Kontingent")
        XCTAssertEqual(PickupQuota.included(in: year(2026), current: 7, changes: []), 7, "ohne Verlauf gilt das aktuelle")
        // Abgeschaltet
        let off = PickupQuota.recording(nil, at: d(2026, 8, 1), into: changes, calendar: calendar)
        XCTAssertNil(PickupQuota.included(in: year(2026), current: nil, changes: off))
    }

    // MARK: - Nachtragen

    func testCatchUpLastThirtyDaysOnlyWithQuota() {
        let today = d(2026, 4, 20)
        let input = QuotaInput(scheduled: biweekly2026, done: [d(2026, 4, 2)], included: 12)
        let entries = PickupQuota.catchUp(input, today: today, calendar: calendar)
        // 19.3. liegt außerhalb von 30 Tagen, 2.4. ist markiert, 16.4. offen, 30.4. kommt noch
        XCTAssertEqual(entries.map(\.date), [d(2026, 4, 16)])
        var plain = input
        plain.included = nil
        XCTAssertTrue(PickupQuota.catchUp(plain, today: today, calendar: calendar).isEmpty, "ohne Kontingent keine Karte")
    }

    // MARK: - CSV

    func testCSVExport() {
        let rows = [PickupQuota.CSVRow(date: d(2026, 3, 12), location: "Haus; Garten", wasteType: "Restmüll", mark: .out),
                    PickupQuota.CSVRow(date: d(2026, 2, 26), location: "Haus", wasteType: "Papier", mark: .open),
                    PickupQuota.CSVRow(date: d(2026, 3, 1), location: "Haus", wasteType: "Restmüll", mark: .notOut, isExtra: true)]
        XCTAssertEqual(PickupQuota.csv(rows, calendar: calendar), """
        Datum;Standort;Abfallart;Zustand;Zusatzleerung
        2026-02-26;Haus;Papier;offen;
        2026-03-01;Haus;Restmüll;nicht raus;ja
        2026-03-12;"Haus; Garten";Restmüll;raus;

        """)
    }

    func testDoneTheEveningBeforeCountsRightAway() {
        // „Erledigt“ am Vorabend für morgen zählt sofort; offen morgen kommt noch
        let tomorrow = biweekly2026[3]
        let today = Days.add(-1, to: tomorrow, calendar: calendar)
        let marked = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, done: [tomorrow], included: 12), period: year(2026), today: today, calendar: calendar)
        XCTAssertEqual(marked.used, 1)
        let open = PickupQuota.summary(QuotaInput(scheduled: biweekly2026, included: 12), period: year(2026), today: today, calendar: calendar)
        XCTAssertEqual(open.used, 0)
        XCTAssertEqual(open.open, 3, "nur die drei vergangenen Termine sind offen")
    }

    // MARK: - Vorabend-Mitteilung

    private func planEvening(_ pickups: [PlannedPickup]) -> PlannedNotification? {
        var settings = ReminderSettings()
        settings.escalationEnabled = false
        settings.bringInEnabled = false
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 8))!
        return ReminderPlanner.plan(pickups: pickups, birthdays: [], settings: settings, now: now, calendar: calendar)
            .first { $0.category == .wasteEvening }
    }

    func testEveningNotificationShowsFreeLineAndChoice() {
        let day = d(2026, 3, 5)
        let rest = PlannedPickup(date: day, name: "Restmüll", quotaTypeID: "rest-id", quotaLine: "noch 5 von 12 frei")
        let paper = PlannedPickup(date: day, name: "Papier")
        let both = planEvening([rest, paper])
        XCTAssertEqual(both?.body.components(separatedBy: "\n").last, "Restmüll · noch 5 von 12 frei")
        XCTAssertEqual(both?.choiceTypeID, "rest-id")
        XCTAssertEqual(both?.choiceName, "Restmüll")
        // Nur die gezählte Müllart: Zeile ja, Wahl nein (ein Tipp wie heute)
        let single = planEvening([rest])
        XCTAssertTrue(single?.body.hasSuffix("Restmüll · noch 5 von 12 frei") ?? false)
        XCTAssertNil(single?.choiceTypeID)
        // Ohne Kontingent: Text und Aktionen wie bisher
        let plain = planEvening([PlannedPickup(date: day, name: "Restmüll"), paper])
        XCTAssertFalse(plain?.body.contains("frei") ?? true)
        XCTAssertFalse(plain?.body.contains("\n") ?? true)
        XCTAssertNil(plain?.choiceTypeID)
    }

    func testKeepDaysCoversPreviousYear() {
        // Vorjahr ganz einsehbar: Der älteste Tag des Vorjahres liegt höchstens 731 Tage zurück
        XCTAssertGreaterThanOrEqual(PickupQuota.keepDays, 731)
    }
}
