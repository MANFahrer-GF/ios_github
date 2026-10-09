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
        if !SettingsKeys.liveActivitiesEnabled() {
            return .result(dialog: "Live-Aktivitäten sind für Tonne & Torte in den Einstellungen ausgeschaltet.")
        }
        // Termine stammen aus dem zuletzt gespeicherten Stand der App (reicht 60 Tage voraus);
        // ist der fast aufgebraucht, lieber nichts behaupten.
        guard let snapshot = SnapshotStore.load(), snapshot.generatedAt > Date().addingTimeInterval(-50 * 86_400) else {
            return .result(dialog: "Öffne Tonne & Torte einmal, damit die Termine aktuell sind.")
        }
        let evening = SettingsKeys.reminderSettings().eveningMinutes
        switch await LiveActivityManager.refresh(with: snapshot, eveningMinutes: evening, showTomorrowNow: true).outcome {
        case .shown(let names):
            return .result(dialog: "Erinnerung für \(ReminderPlanner.joinNames(names)) ist auf dem Sperrbildschirm.")
        case .nothingDue:
            return .result(dialog: "Morgen wird nichts abgeholt.")
        case .alreadyDone:
            return .result(dialog: "Ist schon erledigt – alles steht draußen.")
        case .disabled:
            return .result(dialog: "Live-Aktivitäten sind für Tonne & Torte in den Einstellungen ausgeschaltet.")
        case .failed:
            return .result(dialog: "Die Erinnerung konnte gerade nicht gestartet werden.")
        }
    }
}
