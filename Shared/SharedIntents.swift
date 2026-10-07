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
        let key = (dayKey?.isEmpty == false) ? dayKey! : (SnapshotStore.load()?.nextPickupDay().map { Days.iso($0.date) } ?? "")
        guard !key.isEmpty else { return .result(dialog: "Es steht keine Abholung an.") }
        SnapshotStore.markDone(dayKey: key)
        #if os(watchOS)
        WatchSync.sendDone(dayKey: key)
        #endif
        return .result(dialog: "Super, alles steht draußen. 👍")
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
            return .result(value: "", dialog: "Bitte öffne Tonne & Torte einmal, damit ich deine Termine kenne.")
        }
        let filtered = snapshot.filtered(locationID: location?.id)
        guard let next = filtered.nextPickupDay() else {
            return .result(value: "", dialog: "In den nächsten Wochen steht keine Abholung an.")
        }
        let names = next.items.map(\.name)
        let list = ReminderPlanner.joinNames(names)
        let when: String
        switch Days.until(next.date) {
        case 0: when = "heute"
        case 1: when = "morgen"
        case 2: when = "übermorgen"
        case let d: when = "in \(d) Tagen, am \(DateText.short(next.date))"
        }
        let text = "\(list) \(names.count == 1 ? "kommt" : "kommen") \(when)."
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
