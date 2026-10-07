import AppIntents

/// Siri-Sätze für Tonne & Torte. Apple verlangt in jedem Satz den App-Namen (gesprochen „Tonne und Torte“,
/// siehe INAlternativeAppNames). Ohne App-Namen geht es über einen eigenen Kurzbefehl – erklärt in SiriView.
struct TonneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPickupIntent(),
            phrases: [
                "Wann kommt der Müll in \(.applicationName)",
                "Frag \(.applicationName), wann der Müll kommt",
                "Welche Tonne muss raus in \(.applicationName)",
                "Frag \(.applicationName), welche Tonne raus muss",
                "Nächste Abholung in \(.applicationName)",
                "Müllabfuhr in \(.applicationName)",
                "\(.applicationName) Müll",
            ],
            shortTitle: "Nächste Abholung",
            systemImageName: "trash.fill"
        )
        AppShortcut(
            intent: NextBirthdayIntent(),
            phrases: [
                "Wer hat als Nächstes Geburtstag in \(.applicationName)",
                "Frag \(.applicationName), wer Geburtstag hat",
                "Hat heute jemand Geburtstag in \(.applicationName)",
                "Nächster Geburtstag in \(.applicationName)",
                "Geburtstage in \(.applicationName)",
                "\(.applicationName) Geburtstage",
            ],
            shortTitle: "Nächste Geburtstage",
            systemImageName: "birthday.cake.fill"
        )
        AppShortcut(
            intent: MarkPickupDoneIntent(),
            phrases: [
                "Tonne steht draußen in \(.applicationName)",
                "Müll ist erledigt in \(.applicationName)",
                "\(.applicationName) erledigt",
            ],
            shortTitle: "Tonne steht draußen",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: StartPickupLiveActivityIntent(),
            phrases: [
                "Tonnen-Erinnerung starten in \(.applicationName)",
                "Zeig die Tonnen auf dem Sperrbildschirm mit \(.applicationName)",
            ],
            shortTitle: "Tonnen-Erinnerung starten",
            systemImageName: "bell.badge.fill"
        )
    }
}
