import Foundation
import AppIntents
import TonneCore

/// „Erledigt“ aus Widget, Live-Aktivität oder Mitteilung: markiert den Abholtag als bestätigt.
#if os(iOS)
typealias DoneIntentBase = LiveActivityIntent
#else
typealias DoneIntentBase = AppIntent
#endif

struct MarkPickupDoneIntent: DoneIntentBase {
    static var title: LocalizedStringResource = "Tonne steht draußen"
    static var description = IntentDescription("Markiert die nächste Abholung als erledigt.")
    static var openAppWhenRun = false

    @Parameter(title: "Tag")
    var dayKey: String?

    init() { dayKey = nil }
    init(dayKey: String) { self.dayKey = dayKey }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Ohne Tag (Siri, Kurzbefehl): nur heute oder morgen – nie still eine Abholung in einer Woche
        let snapshot = SnapshotStore.load()
        let target = (dayKey?.isEmpty == false) ? dayKey! : (snapshot?.doneTargetDay().map { Days.iso($0.date) } ?? "")
        guard !target.isEmpty else {
            let todayDone = snapshot?.pickupDays.contains { Days.until($0.date) == 0 && $0.done } ?? false
            return .result(dialog: IntentDialog(stringLiteral: todayDone ? L10n.t("Heute ist schon alles erledigt. 👍", "Everything is already done today. 👍") : L10n.t("Heute und morgen steht keine Abholung an.", "No collection today or tomorrow.")))
        }
        SnapshotStore.markDone(dayKey: target)
        #if os(watchOS)
        WatchSync.sendDone(dayKey: target)
        #endif
        let isToday = Days.parse(target).map { Days.until($0) == 0 } ?? false
        return .result(dialog: IntentDialog(stringLiteral: isToday
            ? L10n.t("Super, alles für heute steht draußen. 👍", "Great, everything for today is out. 👍")
            : L10n.t("Super, alles für morgen steht draußen. 👍", "Great, everything for tomorrow is out. 👍")))
    }
}

/// „Erledigt“ zurücknehmen, falls man versehentlich getippt hat.
struct UndoPickupDoneIntent: DoneIntentBase {
    static var title: LocalizedStringResource = "Erledigt zurücknehmen"
    static var description = IntentDescription("Nimmt die Markierung „steht draußen“ für einen Abholtag zurück.")
    static var openAppWhenRun = false

    @Parameter(title: "Tag")
    var dayKey: String?

    init() { dayKey = nil }
    init(dayKey: String) { self.dayKey = dayKey }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let key = (dayKey?.isEmpty == false) ? dayKey! : (SnapshotStore.load()?.undoTargetDay().map { Days.iso($0.date) } ?? "")
        guard !key.isEmpty else { return .result(dialog: IntentDialog(stringLiteral: L10n.t("Heute und morgen ist nichts als erledigt markiert.", "Nothing is marked as done for today or tomorrow."))) }
        SnapshotStore.markUndone(dayKey: key)
        #if os(watchOS)
        WatchSync.sendUndo(dayKey: key)
        #endif
        return .result(dialog: IntentDialog(stringLiteral: L10n.t("Okay, die Tonne gilt wieder als offen.", "Okay, the bin counts as open again.")))
    }
}

/// „Ist drin“: Tonnen nach der Abfuhr wieder hereingeholt – blendet den Hinweis im Widget aus.
struct MarkBroughtInIntent: DoneIntentBase {
    static var title: LocalizedStringResource = "Tonne ist wieder drin"
    static var description = IntentDescription("Bestätigt, dass die geleerten Tonnen wieder hereingeholt sind.")
    static var openAppWhenRun = false

    @Parameter(title: "Tag")
    var dayKey: String?

    init() { dayKey = nil }
    init(dayKey: String) { self.dayKey = dayKey }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let key = (dayKey?.isEmpty == false) ? dayKey! : Days.iso(Days.today())
        SnapshotStore.markBroughtIn(dayKey: key)
        return .result(dialog: IntentDialog(stringLiteral: L10n.t("Prima, alles ist wieder drin.", "Great, everything is back in.")))
    }
}

/// Siri / Kurzbefehle: „Wann kommt die nächste Müllabfuhr?“
struct NextPickupIntent: AppIntent {
    static var title: LocalizedStringResource = "Nächste Abholung"
    static var description = IntentDescription("Sagt dir, wann die nächste Müllabfuhr kommt.")
    static var openAppWhenRun = false

    @Parameter(title: "Standort")
    var location: LocationEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let snapshot = SnapshotStore.load() else {
            return .result(value: "", dialog: IntentDialog(stringLiteral: L10n.t("Bitte öffne Tonne & Torte einmal, damit ich deine Termine kenne.", "Please open Tonne & Torte once so I know your dates.")))
        }
        let filtered = snapshot.filtered(locationID: location?.id)
        // Heute zählt bis 17 Uhr, auch wenn die Tonne schon draußen steht – das Müllauto kommt ja noch
        guard let next = filtered.nextPickupDay(countDone: true) else {
            return .result(value: "", dialog: IntentDialog(stringLiteral: L10n.t("In den nächsten Wochen steht keine Abholung an.", "No collection in the coming weeks.")))
        }
        let names = next.items.map(\.name)
        let list = ReminderPlanner.joinNames(names)
        let when: String
        switch Days.until(next.date) {
        case 0: when = L10n.t("heute", "today")
        case 1: when = L10n.t("morgen", "tomorrow")
        case 2: when = L10n.t("übermorgen", "the day after tomorrow")
        case let d: when = L10n.t("in \(d) Tagen, am \(DateText.short(next.date))", "in \(d) days, on \(DateText.short(next.date))")
        }
        let text = L10n.t("\(list) \(names.count == 1 ? "kommt" : "kommen") \(when).", "\(list) \(names.count == 1 ? "is" : "are") due \(when).")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// Siri / Kurzbefehle: „Wer hat als Nächstes Geburtstag?“
struct NextBirthdayIntent: AppIntent {
    static var title: LocalizedStringResource = "Nächste Geburtstage"
    static var description = IntentDescription("Sagt dir, wer als Nächstes Geburtstag hat.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let snapshot = SnapshotStore.load() else {
            return .result(value: "", dialog: IntentDialog(stringLiteral: L10n.t("Bitte öffne Tonne & Torte einmal, damit ich die Geburtstage kenne.", "Please open Tonne & Torte once so I know the birthdays.")))
        }
        let text = SpokenSummary.birthdays(snapshot.birthdays)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// Standort als App-Entity für Widget-Konfiguration und Siri – gelesen aus dem Snapshot.
struct LocationEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Standort"
    static var defaultQuery = LocationEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct LocationEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LocationEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [LocationEntity] { all() }
    func defaultResult() async -> LocationEntity? { nil }

    private func all() -> [LocationEntity] {
        (SnapshotStore.load()?.locations ?? []).map { LocationEntity(id: $0.id, name: $0.name) }
    }
}
