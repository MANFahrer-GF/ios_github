import AppIntents

/// Siri auf der Apple Watch („Hey Siri, wann kommt der Müll in Tonne & Torte?“).
/// watchOS kennt nur die Befehle, die die Watch-App selbst anmeldet – die iPhone-App-Liste gilt dort nicht.
/// Die Live-Aktivität gibt es auf der Uhr nicht, deshalb nur Abfrage und „Erledigt“.
struct TonneWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPickupIntent(),
            phrases: [
                "Wann kommt der Müll in \(.applicationName)",
                "Nächste Abholung in \(.applicationName)",
                "Wann ist die nächste Müllabfuhr in \(.applicationName)",
                "Welche Tonne muss raus in \(.applicationName)",
            ],
            shortTitle: "Nächste Abholung",
            systemImageName: "trash.fill"
        )
        AppShortcut(
            intent: MarkPickupDoneIntent(),
            phrases: [
                "Tonne steht draußen in \(.applicationName)",
                "Müll ist erledigt in \(.applicationName)",
            ],
            shortTitle: "Tonne steht draußen",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
