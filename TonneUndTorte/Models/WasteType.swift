import Foundation
import SwiftData
import TonneCore

/// Eine Müllart (Restmüll, Gelber Sack …) mit Rhythmus und/oder Einzelterminen.
@Model
final class WasteType {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#5B6470"
    /// Immer ein SF-Symbolname, damit auch ältere App-Versionen ein Symbol zeigen.
    var symbolName: String = "trash.fill"
    /// Ausdrücklich gewähltes eigenes Piktogramm („tt.sack“ …), unabhängig vom Namen.
    var glyphName: String?
    var categoryRaw: String = WasteCategory.other.rawValue
    var sortOrder: Int = 0
    var isActive: Bool = true
    var remindersEnabled: Bool = true
    var intervalWeeks: Int = 0
    var anchorDate: Date?
    var explicitDates: [Date] = []
    var skippedDates: [Date] = []
    /// Tage, an denen „Erledigt“ bestätigt wurde.
    var doneDates: [Date] = []
    /// Tage, an denen diese Müllart „diesmal nicht rausgestellt“ wird – die Abfuhr kommt, aber ohne Erinnerung (ab 2.0.7).
    var notPutOutDates: [Date] = []
    /// Schlüssel in der Online-Quelle (Titel der Fraktion), damit ein Abgleich die Termine ersetzt.
    var sourceKey: String?
    var createdAt: Date = Date()
    /// Hinweise des Entsorgers je Termin („2026-10-22“ → „Am Grauen Stein 6 (08:00 - 12:00)“), als JSON (ab 2.0.5).
    /// Nur für Müllarten zum Hinbringen (Schadstoffmobil) gespeichert – bei Tonnen steht dort meist nur die Straße.
    var dayNotesJSON: String = ""

    // MARK: Leerungs-Statistik (ab 2.1) – alles leer = wie bisher, nur additive Felder mit Standardwert (leichte Migration)
    /// Inklusive Leerungen je Zeitraum (nil = ohne Kontingent).
    var includedPerYear: Int?
    /// Stichtag des Gebührenjahres (nur Tag und Monat zählen); nil = Kalenderjahr.
    var quotaStart: Date?
    /// Startwert „bis quotaBaselineDate laut Angabe: quotaBaseline“.
    var quotaBaseline: Int?
    var quotaBaselineDate: Date?
    /// Preis je Leerung über dem Kontingent.
    var pricePerExtra: Double?
    /// Tonnendienst: Leerungen zählen auch, wenn jemand anderes dran ist (geteilte Tonne).
    var countOffDuty: Bool = false
    /// Zusatzleerungen, die nicht im Kalender stehen.
    var extraPickupDates: [Date] = []
    /// „Erledigt“ aus Widget/Watch für einen Tag mit mehreren Müllarten – wird einmal nachgefragt.
    var bulkConfirmedDates: [Date] = []
    /// Änderungen des Kontingents als JSON (`[QuotaChange]`), damit eine Änderung erst ab dann gilt.
    var quotaChangesJSON: String = ""

    var location: Location?

    init(name: String, category: WasteCategory, colorHex: String? = nil, symbolName: String? = nil, sortOrder: Int = 0, sourceKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.colorHex = colorHex ?? category.colorHex
        self.symbolName = symbolName ?? category.symbolName
        self.sortOrder = sortOrder
        self.sourceKey = sourceKey
        self.createdAt = Date()
    }

    /// Angezeigtes Symbol, einmal aufgelöst: das gewählte Piktogramm, sonst das aus SF-Name und Name abgeleitete,
    /// sonst der SF-Name. Ein gewähltes Piktogramm gilt nur, solange `symbolName` noch dazu passt – ändert eine
    /// ältere App-Version (iCloud) nur `symbolName`, gewinnt diese neuere Wahl.
    var displaySymbol: String {
        get {
            if let glyphName, !hasStaleGlyph { return glyphName }
            return WasteGlyph.assetName(for: symbolName, name: name) ?? symbolName
        }
        set {
            if WasteGlyph.all.contains(newValue) {
                glyphName = newValue
                symbolName = WasteGlyph.sfFallback(for: newValue)
            } else {
                glyphName = nil
                symbolName = newValue
            }
        }
    }

    /// Das gewählte Piktogramm passt nicht mehr zum SF-Namen (eine ältere App-Version hat das Symbol geändert).
    /// Nur beim Lesen ausgewertet – nichts wird automatisch gelöscht, auch keine Piktogramme neuerer Versionen.
    private var hasStaleGlyph: Bool {
        guard let glyphName else { return false }
        return WasteGlyph.sfFallback(for: glyphName) != symbolName
    }

    /// Wie mit dieser Müllart umgegangen wird (Tonne / bereitstellen / hinbringen).
    var handling: WasteHandling { WasteHandling.of(name: name, symbol: displaySymbol, category: category) }

    var dayNotes: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: Data(dayNotesJSON.utf8))) ?? [:] }
        set { dayNotesJSON = newValue.isEmpty ? "" : (String(data: (try? JSONEncoder().encode(newValue)) ?? Data(), encoding: .utf8) ?? "") }
    }

    /// Zeit/Ort zu einem Termin, nur beim Hinbringen.
    func note(on day: Date) -> String? {
        guard handling == .bringTo, !dayNotesJSON.isEmpty else { return nil }
        return dayNotes[Days.iso(day)]
    }

    var category: WasteCategory {
        get { WasteCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var schedule: PickupSchedule {
        PickupSchedule(intervalWeeks: intervalWeeks, anchorDate: anchorDate, explicitDates: explicitDates, skippedDates: skippedDates)
    }

    var hasSchedule: Bool { schedule.hasAnyDates }

    func pickupDates(from: Date, to: Date) -> [Date] {
        ScheduleEngine.pickupDates(schedule, from: from, to: to)
    }

    var nextPickup: Date? { ScheduleEngine.nextPickup(schedule) }

    // MARK: - Termine bearbeiten

    func addExplicitDate(_ date: Date) {
        let day = Days.start(of: date)
        if !explicitDates.contains(day) { explicitDates.append(day); explicitDates.sort() }
        skippedDates.removeAll { Days.start(of: $0) == day }
    }

    func skip(_ date: Date) {
        let day = Days.start(of: date)
        if !skippedDates.contains(day) { skippedDates.append(day); skippedDates.sort() }
    }

    func unskip(_ date: Date) {
        let day = Days.start(of: date)
        skippedDates.removeAll { Days.start(of: $0) == day }
    }

    func move(_ date: Date, to newDate: Date) {
        skip(date)
        addExplicitDate(newDate)
    }

    func isDone(on date: Date) -> Bool {
        let day = Days.start(of: date)
        return doneDates.contains { Days.start(of: $0) == day }
    }

    func markDone(on date: Date) {
        let day = Days.start(of: date)
        if !isDone(on: day) { doneDates.append(day) }
    }

    func unmarkDone(on date: Date) {
        let day = Days.start(of: date)
        doneDates.removeAll { Days.start(of: $0) == day }
    }

    /// Tonnendienst des Standorts: Außerhalb der eingetragenen Zeiträume ist jemand anderes dran.
    var dutyPeriods: [DutyPeriod] { location?.dutyPeriods ?? [] }

    func isOnDuty(on date: Date) -> Bool { DutySchedule.isOnDuty(on: date, periods: dutyPeriods) }

    /// Tage, die der Nutzer markiert hat (rausgestellt oder nicht) – ein Adresswechsel lässt sie stehen.
    var markedDates: [Date] { doneDates + notPutOutDates + bulkConfirmedDates }

    func isNotPutOut(on date: Date) -> Bool {
        let day = Days.start(of: date)
        return notPutOutDates.contains { Days.start(of: $0) == day }
    }

    /// „Diesmal nicht rausstellen“ setzen oder zurücknehmen. Hebt ein „Erledigt“ für den Tag auf – beides zugleich gibt es nicht.
    func setNotPutOut(_ notOut: Bool, on date: Date) {
        let day = Days.start(of: date)
        notPutOutDates.removeAll { Days.start(of: $0) == day }
        if notOut { notPutOutDates.append(day); unmarkDone(on: day); clearBulk(on: day) }
    }

    /// Entfernt Einzeltermine und Markierungen, die älter sind, als die Vorjahres-Statistik braucht (800 Tage).
    func prune() {
        let cutoff = Days.add(-PickupQuota.keepDays, to: Days.today())
        explicitDates.removeAll { $0 < cutoff }
        skippedDates.removeAll { $0 < cutoff }
        doneDates.removeAll { $0 < cutoff }
        notPutOutDates.removeAll { $0 < cutoff }
        extraPickupDates.removeAll { $0 < cutoff }
        bulkConfirmedDates.removeAll { $0 < cutoff }
    }

    // MARK: - Leerungs-Statistik

    /// Gezählte Müllart: Ein Kontingent ist eingetragen.
    var isCounted: Bool { includedPerYear != nil }

    var quotaChanges: [QuotaChange] {
        get { (try? JSONDecoder().decode([QuotaChange].self, from: Data(quotaChangesJSON.utf8))) ?? [] }
        set { quotaChangesJSON = newValue.isEmpty ? "" : (String(data: (try? JSONEncoder().encode(newValue)) ?? Data(), encoding: .utf8) ?? "") }
    }

    /// Kontingent setzen; eine Änderung gilt ab heute, der bisherige Stand bleibt.
    func setIncluded(_ value: Int?) {
        guard value != includedPerYear else { return }
        includedPerYear = value
        quotaChanges = PickupQuota.recording(value, at: Days.today(), into: quotaChanges)
    }

    func quotaPeriod(containing day: Date) -> QuotaPeriod { PickupQuota.period(containing: day, anchor: quotaStart) }

    /// Alles für die Rechnung in einem Zeitraum (Plan, Markierungen, Tonnendienst).
    func quotaInput(period: QuotaPeriod) -> QuotaInput {
        let scheduled = pickupDates(from: period.start, to: Days.add(-1, to: period.end))
        let duty = dutyPeriods
        let offDuty = duty.isEmpty ? [] : Set(scheduled.filter { !DutySchedule.isOnDuty(on: $0, periods: duty) })
        return QuotaInput(scheduled: scheduled, done: doneDates, notOut: notPutOutDates, extra: extraPickupDates, bulkConfirmed: bulkConfirmedDates,
                          offDuty: offDuty, countOffDuty: countOffDuty, included: includedPerYear, changes: quotaChanges,
                          baseline: quotaBaseline, baselineDate: quotaBaselineDate, pricePerExtra: pricePerExtra)
    }

    func quotaSummary(period: QuotaPeriod, today: Date = Days.today()) -> QuotaSummary {
        PickupQuota.summary(quotaInput(period: period), period: period, today: today)
    }

    /// Offene und pauschal bestätigte Termine der letzten 30 Tage (nur mit Kontingent).
    func catchUpEntries(today: Date = Days.today()) -> [QuotaEntry] {
        guard isCounted else { return [] }
        let window = QuotaPeriod(start: Days.add(-PickupQuota.catchUpDays, to: today), end: Days.add(1, to: today))
        return PickupQuota.catchUp(quotaInput(period: window), today: today)
    }

    func isBulkConfirmed(on date: Date) -> Bool {
        let day = Days.start(of: date)
        return bulkConfirmedDates.contains { Days.start(of: $0) == day }
    }

    func markBulk(on date: Date) {
        let day = Days.start(of: date)
        if !isBulkConfirmed(on: day) { bulkConfirmedDates.append(day) }
    }

    func clearBulk(on date: Date) {
        let day = Days.start(of: date)
        bulkConfirmedDates.removeAll { Days.start(of: $0) == day }
    }

    /// Zustand eines Termins ausdrücklich setzen (Statistik, Nachtragen): raus, nicht raus oder offen.
    func setPickupMark(_ mark: PickupMark, on date: Date) {
        let day = Days.start(of: date)
        clearBulk(on: day)
        // Eine Zusatzleerung, die doch nicht stattfand, entfällt
        if mark != .out { removeExtraPickup(day) }
        switch mark {
        case .out:
            notPutOutDates.removeAll { Days.start(of: $0) == day }
            markDone(on: day)
        case .notOut:
            setNotPutOut(true, on: day)
        case .open:
            unmarkDone(on: day)
            notPutOutDates.removeAll { Days.start(of: $0) == day }
        }
    }

    func addExtraPickup(_ date: Date) {
        let day = Days.start(of: date)
        if !extraPickupDates.contains(where: { Days.start(of: $0) == day }) { extraPickupDates.append(day); extraPickupDates.sort() }
    }

    func removeExtraPickup(_ date: Date) {
        let day = Days.start(of: date)
        extraPickupDates.removeAll { Days.start(of: $0) == day }
    }
}
