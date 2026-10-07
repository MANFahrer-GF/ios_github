import AppIntents
import TonneCore

/// Startet die Live-Aktivität „Tonne rausstellen“, ohne die App zu öffnen.
/// iOS erlaubt das Starten im Hintergrund nur über eine LiveActivityIntent – z. B. aus einer
/// Kurzbefehle-Automation („Jeden Tag um 18 Uhr“), per Siri oder über die Aktionstaste.
struct StartPickupLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Tonnen-Erinnerung starten"
    static var description = IntentDescription("Zeigt am Vorabend der Abholung die Live-Aktivität auf dem Sperrbildschirm – ohne die App zu öffnen.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore.load() else {
            return .result(dialog: "Öffne Tonne & Torte einmal, damit die Termine bekannt sind.")
        }
        await LiveActivityManager.refresh(with: snapshot)
        guard let next = snapshot.nextPickupDay(), Days.until(next.date) <= 1 else {
            return .result(dialog: "Morgen wird nichts abgeholt.")
        }
        return .result(dialog: "Erinnerung für \(ReminderPlanner.joinNames(next.items.map(\.name))) ist auf dem Sperrbildschirm.")
    }
}
