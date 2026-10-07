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
                Text("Apple verlangt, dass in Siri-Befehlen einer App der App-Name vorkommt – sonst weiß Siri nicht, welche App gemeint ist, und antwortet selbst. Sag dafür einfach „Tonne und Torte“.")
            }

            Section("Müllabfuhr") {
                phrase("Hey Siri, wann kommt der Müll in Tonne und Torte?")
                phrase("Hey Siri, frag Tonne und Torte, welche Tonne raus muss")
                phrase("Hey Siri, Tonne und Torte Müll")
            }
            Section("Geburtstage") {
                phrase("Hey Siri, wer hat als Nächstes Geburtstag in Tonne und Torte?")
                phrase("Hey Siri, hat heute jemand Geburtstag in Tonne und Torte?")
                phrase("Hey Siri, Tonne und Torte Geburtstage")
            }
            Section("Erledigt & Sperrbildschirm") {
                phrase("Hey Siri, Tonne steht draußen in Tonne und Torte")
                phrase("Hey Siri, Tonnen-Erinnerung starten in Tonne und Torte")
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
                Text("Nach der Installation die App einmal öffnen – erst dann kennt Siri die Befehle. Antwortet Siri trotzdem selbst (z. B. mit ChatGPT), hat sie den App-Namen nicht verstanden: langsam „Tonne und Torte“ sagen oder einen eigenen Kurzbefehl anlegen.")
            } header: {
                Text("Wenn Siri nicht reagiert")
            }
        }
        .navigationTitle("Siri & Kurzbefehle")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func phrase(_ text: LocalizedStringKey) -> some View {
        Label { Text(text) } icon: { Image(systemName: "waveform").foregroundStyle(.tint) }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(.tint))
            Text(text)
        }
    }
}
