import AppIntents

/// Siri-Sätze für Tonne & Torte („Hey Siri, wann kommt der Müll?“).
struct TonneShortcuts: AppShortcutsProvider {
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
