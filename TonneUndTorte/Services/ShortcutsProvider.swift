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
            shortTitle: "Abholung erledigt",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: StartPickupLiveActivityIntent(),
            phrases: [
                "Abhol-Erinnerung starten in \(.applicationName)",
                "Tonnen-Erinnerung starten in \(.applicationName)",
                "Zeig die Tonnen auf dem Sperrbildschirm mit \(.applicationName)",
            ],
            shortTitle: "Abhol-Erinnerung starten",
            systemImageName: "bell.badge.fill"
        )
    }
}
