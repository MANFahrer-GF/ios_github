import XCTest
@testable import TonneCore

/// Tonnendienst im Rhythmus (Thomas, 12.11.2026: „jede gerade Woche, jede zweite Woche … sehr starr“).
final class DutyRhythmTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    private func day(_ iso: String) -> Date { Days.parse(iso, calendar: calendar)! }
    private func period(_ start: String, every: Int, _ unit: DutyRhythm.Unit, length: Int = 1) -> DutyPeriod {
        DutyPeriod.rhythm(start: day(start), DutyRhythm(every: every, unit: unit, length: length), calendar: calendar)
    }
    private func onDuty(_ iso: String, _ periods: [DutyPeriod]) -> Bool {
        DutySchedule.isOnDuty(on: day(iso), periods: periods, calendar: calendar)
    }

    /// Zwei Parteien wechseln wöchentlich: dran, frei, dran – auch über Silvester (2026 hat 53 Kalenderwochen).
    func testEverySecondWeekAcrossNewYear() {
        let p = [period("2026-11-16", every: 2, .weeks)]
        XCTAssertEqual(p[0].endKey, "2026-11-22")
        XCTAssertFalse(onDuty("2026-11-15", p), "vor dem ersten Dienst")
        XCTAssertTrue(onDuty("2026-11-16", p))
        XCTAssertTrue(onDuty("2026-11-22", p))
        XCTAssertFalse(onDuty("2026-11-23", p))
        XCTAssertFalse(onDuty("2026-11-29", p))
        XCTAssertTrue(onDuty("2026-11-30", p))
        XCTAssertTrue(onDuty("2026-12-28", p))   // KW 53
        XCTAssertFalse(onDuty("2027-01-04", p))  // KW 1: frei, obwohl ebenfalls ungerade
        XCTAssertTrue(onDuty("2027-01-11", p))
        XCTAssertTrue(onDuty("2030-06-24", p), "läuft ohne Ende weiter")
    }

    /// Vier Parteien, je zwei Wochen am Stück: alle 8 Wochen, 2 Wochen lang.
    func testTwoWeeksEveryEightWeeks() {
        let p = [period("2026-11-16", every: 8, .weeks, length: 2)]
        XCTAssertTrue(onDuty("2026-11-29", p))
        XCTAssertFalse(onDuty("2026-11-30", p))
        XCTAssertFalse(onDuty("2027-01-10", p))
        XCTAssertTrue(onDuty("2027-01-11", p))
        XCTAssertTrue(onDuty("2027-01-24", p))
        XCTAssertFalse(onDuty("2027-01-25", p))
    }

    func testEveryThirdMonth() {
        let p = [period("2026-12-01", every: 3, .months)]
        XCTAssertEqual(p[0].endKey, "2026-12-31")
        XCTAssertTrue(onDuty("2026-12-31", p))
        XCTAssertFalse(onDuty("2027-01-15", p))
        XCTAssertFalse(onDuty("2027-02-28", p))
        XCTAssertTrue(onDuty("2027-03-01", p))
        XCTAssertTrue(onDuty("2027-03-31", p))
        XCTAssertFalse(onDuty("2027-04-01", p))
    }

    /// Monatlich ab dem 31.: Nach dem Februar geht es wieder am 31. weiter, kein Tag bleibt ohne Dienst.
    func testMonthlyFromThe31stLeavesNoGap() {
        let p = [period("2027-01-31", every: 1, .months)]
        var date = day("2027-01-31")
        while date <= day("2027-12-31") {
            XCTAssertTrue(DutySchedule.isOnDuty(on: date, periods: p, calendar: calendar), "Lücke am \(Days.iso(date, calendar: calendar))")
            date = Days.add(1, to: date, calendar: calendar)
        }
    }

    /// Jeden 2. Monat ab dem 31.: Die Dienste beginnen wieder am 31., sobald der Monat einen hat – nicht dauerhaft am 28.
    func testEverySecondMonthFromThe31stComesBackToThe31st() {
        let p = [period("2027-01-31", every: 2, .months)]
        let starts = DutySchedule.upcoming(p, from: day("2027-03-01"), count: 4, calendar: calendar).map { Days.iso($0.start, calendar: calendar) }
        XCTAssertEqual(starts, ["2027-03-31", "2027-05-31", "2027-07-31", "2027-09-30"])
        XCTAssertFalse(onDuty("2027-03-30", p))
        XCTAssertTrue(onDuty("2027-03-31", p))
    }

    /// Vorschau: Ein fester Zeitraum, der einen Rhythmus-Dienst überlappt, ergibt einen durchgehenden Dienst –
    /// egal in welcher Reihenfolge die Einträge gespeichert sind (Prüfung 12.11.2026).
    func testPreviewMergesOverlappingEntries() {
        let rhythm = period("2026-11-16", every: 2, .weeks)
        let fixed = DutyPeriod(startKey: "2026-11-30", endKey: "2026-12-20", yearly: false)
        for periods in [[rhythm, fixed], [fixed, rhythm]] {
            let next = DutySchedule.upcoming(periods, from: day("2026-11-24"), count: 2, calendar: calendar)
                .map { "\(Days.iso($0.start, calendar: calendar))…\(Days.iso($0.end, calendar: calendar))" }
            XCTAssertEqual(next, ["2026-11-30…2026-12-20", "2026-12-28…2027-01-03"])
        }
    }

    /// Ein Abstand von 0 aus fremden Daten darf nicht durch null teilen.
    func testDecodedZeroIntervalIsClamped() throws {
        let json = #"[{"id":"\#(UUID())","startKey":"2026-11-16","endKey":"2026-11-22","rhythm":{"every":0,"unit":"weeks","length":3}}]"#
        let decoded = DutySchedule.decode(json)
        XCTAssertEqual(decoded.first?.rhythm, DutyRhythm(every: 1, unit: .weeks, length: 1))
        XCTAssertTrue(onDuty("2026-12-01", decoded))
    }

    func testStatusNeverEnds() {
        let p = [period("2026-11-16", every: 2, .weeks)]
        XCTAssertEqual(DutySchedule.status(of: p, today: day("2026-11-18"), calendar: calendar), .onDuty(until: day("2026-11-22")))
        XCTAssertEqual(DutySchedule.status(of: p, today: day("2026-11-24"), calendar: calendar), .upcoming(from: day("2026-11-30")))
        XCTAssertEqual(DutySchedule.status(of: p, today: day("2026-11-01"), calendar: calendar), .upcoming(from: day("2026-11-16")))
        XCTAssertEqual(DutySchedule.status(of: p, today: day("2029-02-01"), calendar: calendar).isEnded, false)
    }

    /// Vorschau beim Eintragen: die nächsten drei Dienste, der laufende zuerst.
    func testUpcomingPreview() {
        let p = [period("2026-11-16", every: 2, .weeks)]
        let next = DutySchedule.upcoming(p, from: day("2026-11-18"), count: 3, calendar: calendar).map { Days.iso($0.start, calendar: calendar) }
        XCTAssertEqual(next, ["2026-11-16", "2026-11-30", "2026-12-14"])
        // Gemischt mit einem festen Zeitraum: zeitlich sortiert
        let mixed = p + [DutyPeriod(startKey: "2026-11-24", endKey: "2026-11-25", yearly: false)]
        let both = DutySchedule.upcoming(mixed, from: day("2026-11-23"), count: 3, calendar: calendar).map { Days.iso($0.start, calendar: calendar) }
        XCTAssertEqual(both, ["2026-11-24", "2026-11-30", "2026-12-14"])
    }

    /// Länge nie größer als der Abstand (sonst wäre man immer dran und der Rhythmus sinnlos).
    func testLengthIsCappedByInterval() {
        XCTAssertEqual(DutyRhythm(every: 2, unit: .weeks, length: 5).length, 2)
        XCTAssertEqual(DutyRhythm(every: 0, unit: .weeks).every, 1)
    }

    // MARK: Speichern und ältere App-Versionen

    /// So hat 2.0.9 die Einträge gelesen: `yearly` ist Pflicht.
    private struct OldDutyPeriod: Codable { let id: UUID; let startKey: String; let endKey: String; let yearly: Bool }

    func testRoundTripAndOlderVersionsFallBackToAlwaysReminding() throws {
        let fixed = DutyPeriod(startKey: "2026-03-01", endKey: "2026-04-30", yearly: true)
        let rhythm = period("2026-11-16", every: 2, .weeks)
        let json = DutySchedule.encode([fixed, rhythm])
        XCTAssertEqual(DutySchedule.decode(json), [fixed, rhythm])
        // Alte Version kann die Liste nicht lesen → wie ohne Tonnendienst (jede Erinnerung), nicht „nie mehr erinnern“
        XCTAssertThrowsError(try JSONDecoder().decode([OldDutyPeriod].self, from: Data(json.utf8)))
        // Nur feste Zeiträume: alte Version liest sie wie bisher
        let onlyFixed = DutySchedule.encode([fixed])
        XCTAssertEqual(try JSONDecoder().decode([OldDutyPeriod].self, from: Data(onlyFixed.utf8)).first?.yearly, true)
        // Bestehende Einträge aus 2.0.8/2.0.9 lesen wir weiter
        let legacy = #"[{"id":"\#(fixed.id)","startKey":"2026-03-01","endKey":"2026-04-30","yearly":true}]"#
        XCTAssertEqual(DutySchedule.decode(legacy), [fixed])
    }
}

private extension DutyStatus {
    var isEnded: Bool { self == .ended }
}
