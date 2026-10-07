import AppIntents

/// Siri auf der Apple Watch. watchOS kennt nur die Befehle, die die Watch-App selbst anmeldet.
/// Die Live-Aktivität gibt es auf der Uhr nicht, deshalb Abholung, Geburtstage und „Erledigt“.
struct TonneWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPickupIntent(),
            phrases: [
                "Wann kommt der Müll in \(.applicationName)",
                "Frag \(.applicationName), wann der Müll kommt",
                "Welche Tonne muss raus in \(.applicationName)",
                "Nächste Abholung in \(.applicationName)",
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
    }
}
