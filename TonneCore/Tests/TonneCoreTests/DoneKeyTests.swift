import XCTest
@testable import TonneCore

/// „Erledigt“ je Standort (Thomas 20.11.2026): zwei Standorte mit Abholung am selben Tag.
final class DoneKeyTests: XCTestCase {
    let home = "11111111-1111-1111-1111-111111111111", flat = "22222222-2222-2222-2222-222222222222"

    func testKeyRoundTrip() {
        XCTAssertEqual(DoneKey.make(day: "2026-11-21", locationID: nil), "2026-11-21")
        XCTAssertEqual(DoneKey.make(day: "2026-11-21", locationID: home), "2026-11-21@\(home)")
        XCTAssertEqual(DoneKey.split("2026-11-21@\(home)").day, "2026-11-21")
        XCTAssertEqual(DoneKey.split("2026-11-21@\(home)").locationID, home)
        // Alte Schlüssel (vor 2.1.1) gelten weiter für den ganzen Tag
        XCTAssertNil(DoneKey.split("2026-11-21").locationID)
    }

    private func day() -> WidgetSnapshot.PickupDay {
        WidgetSnapshot.PickupDay(date: Days.today(), items: [
            WidgetSnapshot.PickupItem(name: "Restmüll", symbolName: "trash.fill", colorHex: "#5B6470", locationID: home),
            WidgetSnapshot.PickupItem(name: "Papier", symbolName: "doc.fill", colorHex: "#2F6FED", locationID: flat),
        ])
    }

    /// Erledigt nur für „Zuhause“: Der Tag bleibt offen, die Ferienwohnung auch – gefiltert ist Zuhause erledigt.
    func testDoneForOneLocationKeepsOtherOpen() {
        var d = day()
        d.setDone(true, locationID: home)
        XCTAssertFalse(d.done, "anderer Standort wurde mit erledigt")
        var snapshot = WidgetSnapshot(); snapshot.pickupDays = [d]
        XCTAssertEqual(snapshot.filtered(locationID: home).pickupDays.first?.done, true)
        XCTAssertEqual(snapshot.filtered(locationID: flat).pickupDays.first?.done, false)
        // Dann auch die Ferienwohnung: ganzer Tag erledigt
        d.setDone(true, locationID: flat)
        XCTAssertTrue(d.done)
        // Zurücknehmen nur für Zuhause
        d.setDone(false, locationID: home)
        XCTAssertFalse(d.done)
        XCTAssertEqual(d.items.map(\.done), [false, true])
    }

    /// Ohne Standort wie bisher: alles erledigt. Ältere Schnappschüsse ohne `done` je Müllart folgen dem Tag.
    func testWholeDayAndOldSnapshots() {
        var d = day()
        d.setDone(true, locationID: nil)
        XCTAssertTrue(d.done)
        var old = day(); old.done = true
        var snapshot = WidgetSnapshot(); snapshot.pickupDays = [old]
        XCTAssertEqual(snapshot.filtered(locationID: home).pickupDays.first?.done, true)
    }

    // MARK: - Ausstehende Markierungen widerspruchsfrei (Prüfbefund 3)

    private var dA: String { "2026-11-21@\(home)" }
    private var dB: String { "2026-11-21@\(flat)" }

    /// A erledigt, dann ganzer Tag, dann ganzer Tag zurück: Nichts darf A beim Übernehmen wieder erledigen.
    func testWholeUndoClearsLocationDone() {
        var r = DoneKey.reconcile(done: [], undo: [], .done(dA), locations: [home, flat])
        r = DoneKey.reconcile(done: r.done, undo: r.undo, .done("2026-11-21"), locations: [home, flat])
        r = DoneKey.reconcile(done: r.done, undo: r.undo, .undo("2026-11-21"), locations: [home, flat])
        XCTAssertEqual(r.done, [])
        XCTAssertEqual(r.undo, ["2026-11-21"])
    }

    /// Ganzer Tag erledigt (noch nicht übernommen), dann im Standort-Widget A zurück: B bleibt erledigt, A offen.
    func testLocationUndoSplitsPendingWholeDone() {
        var r = DoneKey.reconcile(done: [], undo: [], .done("2026-11-21"), locations: [home, flat])
        r = DoneKey.reconcile(done: r.done, undo: r.undo, .undo(dA), locations: [home, flat])
        XCTAssertEqual(r.done, [dB])
        XCTAssertEqual(r.undo, [dA])
    }

    /// A zurückgenommen, dann wieder erledigt: kein Rücknahme-Schlüssel mehr für A; anderer Tag bleibt unberührt.
    func testRedoRemovesUndo() {
        var r = DoneKey.reconcile(done: ["2026-11-28"], undo: [], .undo(dA), locations: [home, flat])
        r = DoneKey.reconcile(done: r.done, undo: r.undo, .done(dA), locations: [home, flat])
        XCTAssertEqual(r.done, ["2026-11-28", dA])
        XCTAssertEqual(r.undo, [])
    }

    /// Heute nur „Zuhause“ erledigt: Das Standort-Widget hält den Tag 15 Minuten zum Zurücknehmen (Prüfbefund 1).
    func testLocationDoneTodayKeepsUndoWindow() {
        let now = Days.at(minutes: 8 * 60, on: Days.today())!
        var d = day()
        d.setDone(true, locationID: home)
        d.doneAt = now
        var snapshot = WidgetSnapshot(); snapshot.pickupDays = [d]
        let filtered = snapshot.filtered(locationID: home)
        XCTAssertEqual(filtered.nextPickupDay(from: now.addingTimeInterval(60))?.date, Days.today(), "Rückgängig sofort weg")
        // Gegenprobe ohne Zeitstempel: gilt sofort als vorbei
        var noStamp = d; noStamp.doneAt = nil
        snapshot.pickupDays = [noStamp]
        XCTAssertNil(snapshot.filtered(locationID: home).nextPickupDay(from: now.addingTimeInterval(60)))
    }

    /// A und B heute erledigt, nur A zurück: B behält Zeitstempel und Rückgängig-Fenster; erst ohne Erledigtes fällt er weg.
    func testUndoOneLocationKeepsOthersStamp() {
        let now = Days.at(minutes: 8 * 60, on: Days.today())!
        var d = day()
        d.setDone(true, locationID: nil); d.doneAt = now
        d.setDone(false, locationID: home)
        XCTAssertEqual(d.doneAt, now)
        var snapshot = WidgetSnapshot(); snapshot.pickupDays = [d]
        XCTAssertEqual(snapshot.filtered(locationID: flat).nextPickupDay(from: now.addingTimeInterval(60))?.date, Days.today())
        d.setDone(false, locationID: flat)
        XCTAssertNil(d.doneAt)
    }
}

