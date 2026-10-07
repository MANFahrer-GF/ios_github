import SwiftUI
import AppIntents

/// Erklärt die Siri-Befehle und wie man eigene Sätze ohne App-Namen anlegt.
struct SiriView: View {
    var body: some View {
        List {
            Section {
                SiriTipView(intent: NextPickupIntent())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Apple verlangt, dass in Siri-Befehlen einer App der App-Name vorkommt – sonst weiß Siri nicht, welche App gemeint ist, und antwortet selbst. Sag dafür einfach „Tonne und Torte“. Ohne App-Namen geht es mit einem eigenen Kurzbefehl (ganz unten).")
            }

            Section {
                tip("1", "Sag „Hey Siri“ und warte kurz, bis Siri zuhört.")
                tip("2", "Sprich den App-Namen als „Tonne und Torte“ – deutlich und ohne Pause dazwischen.")
                tip("3", "Sag den Satz genau so wie unten. Andere Formulierungen kennt Siri meist nicht.")
                tip("4", "Antwortet Siri selbst oder mit ChatGPT, hat sie den App-Namen nicht erkannt – dann noch einmal langsamer sagen oder unten einen eigenen Satz anlegen.")
            } header: {
                Text("So sprichst du richtig")
            }

            Section {
                phrase("Wann kommt der Müll in Tonne und Torte?")
                phrase("Frag Tonne und Torte, wann der Müll kommt")
                phrase("Welche Tonne muss raus in Tonne und Torte?")
                phrase("Frag Tonne und Torte, welche Tonne raus muss")
                phrase("Nächste Abholung in Tonne und Torte")
                phrase("Müllabfuhr in Tonne und Torte")
                phrase("Tonne und Torte Müll")
            } header: {
                Label("Müllabfuhr", systemImage: "trash.fill")
            } footer: {
                Text("Siri sagt z. B.: „Gelber Sack und Restmüll kommen morgen.“")
            }

            Section {
                phrase("Wer hat als Nächstes Geburtstag in Tonne und Torte?")
                phrase("Frag Tonne und Torte, wer Geburtstag hat")
                phrase("Hat heute jemand Geburtstag in Tonne und Torte?")
                phrase("Nächster Geburtstag in Tonne und Torte")
                phrase("Geburtstage in Tonne und Torte")
                phrase("Tonne und Torte Geburtstage")
            } header: {
                Label("Geburtstage", systemImage: "birthday.cake.fill")
            } footer: {
                Text("Siri sagt z. B.: „Oma Erika wird morgen 80. Danach: Paul in 9 Tagen.“")
            }

            Section {
                phrase("Tonne steht draußen in Tonne und Torte")
                phrase("Müll ist erledigt in Tonne und Torte")
                phrase("Tonne und Torte erledigt")
            } header: {
                Label("Erledigt", systemImage: "checkmark.circle.fill")
            } footer: {
                Text("Hakt die nächste Abholung ab – wie der Knopf „Erledigt“.")
            }

            Section {
                phrase("Tonnen-Erinnerung starten in Tonne und Torte")
                phrase("Zeig die Tonnen auf dem Sperrbildschirm mit Tonne und Torte")
            } header: {
                Label("Sperrbildschirm (nur iPhone)", systemImage: "bell.badge.fill")
            } footer: {
                Text("Zeigt die Live-Aktivität sofort. Ab iOS 26 kommt sie am Vorabend ohnehin von selbst.")
            }

            Section {
                Text("Auf der Uhr funktionieren die Sätze für Müllabfuhr, Geburtstage und „Erledigt“. Öffne die Watch-App dafür einmal, und die iPhone-App sollte die Termine schon geschickt haben.")
            } header: {
                Label("Apple Watch", systemImage: "applewatch")
            }

            Section {
                step(1, "Tippe unten auf „Kurzbefehle öffnen“.")
                step(2, "Tippe in der Kurzbefehle-App auf „+“ für einen neuen Kurzbefehl, dann auf „Aktion hinzufügen“ und suche „Tonne & Torte“.")
                step(3, "Wähle z. B. „Nächste Abholung“ oder „Nächste Geburtstage“.")
                step(4, "Tippe oben auf den Namen des Kurzbefehls und nenne ihn so, wie du fragen willst – z. B. „Welche Tonne“ oder „Geburtstage“.")
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
            } header: {
                Text("Eigener Satz ohne App-Namen")
            } footer: {
                Text("Danach reicht „Hey Siri, Welche Tonne“ – Siri startet den Kurzbefehl direkt. Funktioniert auch auf der Apple Watch.")
            }

            Section {
                Text("Nach der Installation die App einmal öffnen – erst dann kennt Siri die Befehle. Das kann ein, zwei Minuten dauern.")
            } header: {
                Text("Wenn Siri nicht reagiert")
            }
        }
        .navigationTitle("Siri & Kurzbefehle")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func phrase(_ text: LocalizedStringKey) -> some View {
        Label { Text("„") + Text(text) + Text("“") } icon: { Image(systemName: "waveform").foregroundStyle(.tint) }
    }

    private func tip(_ number: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(.orange))
            Text(text)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(.tint))
            Text(text)
        }
    }
}
