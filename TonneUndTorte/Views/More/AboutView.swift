import SwiftUI
import TonneCore

/// „Über diese App“: wer sie gebaut hat, was sie kann, woher die Daten kommen.
struct AboutView: View {
    @Environment(\.colorScheme) private var scheme

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                madeBy
                card(title: "Die Geschichte", symbol: "book.fill") {
                    Text("Tonne & Torte ist ein Hobbyprojekt aus Gifhorn. Entstanden, weil der Gelbe Sack einmal zu oft stehen geblieben ist und Geburtstage nicht im Kalender standen. Die App ist für mich und meine Familie gedacht und wird nebenbei weiterentwickelt.")
                }
                card(title: "Was die App kann", symbol: "sparkles") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Abfuhrtermine direkt vom Entsorger, wöchentlich automatisch abgeglichen")
                        bullet("Erinnerung am Vorabend mit „Erledigt“ und „Später nochmal“")
                        bullet("Widgets, Sperrbildschirm, Live-Aktivität, Apple Watch und Siri")
                        bullet("Geburtstage mit Alter, runden Jubiläen und Geschenkideen")
                        bullet("Eigene wiederkehrende Termine wie TÜV oder Rauchmelder")
                        bullet("Kalender-App: iCloud, Google oder Outlook, automatisch aktuell")
                        bullet("Export als ICS, CSV und PDF")
                    }
                }
                card(title: "Woher die Daten kommen", symbol: "antenna.radiowaves.left.and.right") {
                    Text("Termine kommen direkt von den Portalen der Entsorger: AWIDO, AbfallPlus, Jumomind, Abfallnavi, Abfall-App, C-Trace, Müllmax, Gemos, AWSH, Lobbe, Nerdbridge, Mein-Abfallkalender sowie BSR Berlin, Köln, Leipzig und Region Hannover. Der Katalog kennt \(ProviderCatalog.count) Entsorger. Alle Angaben ohne Gewähr, im Zweifel gilt der Abfuhrkalender deines Entsorgers.")
                }
                card(title: "Clean. Ohne Mist.", symbol: "checkmark.seal.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Keine Werbung – nirgends, nie")
                        bullet("Kein Tracking, keine Analyse-Tools, keine Werbe-ID")
                        bullet("Kein Konto, kein Abo, keine In-App-Käufe")
                        bullet("Kein eigener Server: Deine Daten bleiben auf deinen Geräten und in deiner eigenen iCloud")
                        bullet("Nach draußen geht nur deine Adresse an den Entsorger, den du auswählst – damit er dir die Abfuhrtermine schickt")
                    }
                }
                card(title: "Danke", symbol: "heart.fill") {
                    Text("Die Liste der Entsorger beruht auf dem Open-Source-Projekt hacs_waste_collection_schedule (MIT-Lizenz). Symbole: SF Symbols von Apple, Tonnen und Sack selbst gezeichnet.")
                }
                VStack(spacing: 4) {
                    Text("Mit ❤️ gebaut in Gifhorn")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text("Version \(version)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Über Tonne & Torte")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Das App-Symbol aus dem Bundle (Xcode legt die Dateinamen in CFBundleIcons ab).
    private static var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }

    /// Die Visitenkarte des Machers.
    private var madeBy: some View {
        VStack(spacing: 10) {
            Text("❤️").font(.system(size: 40))
            Text("Gebaut von Thomas Kant")
                .font(.system(size: 22, weight: .black, design: .rounded))
            Text("Mit Herz aus Gifhorn – damit keine Tonne mehr stehen bleibt\nund keine Torte vergessen wird.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(colors: [Color(hex: "#FF5FA2").opacity(0.16), Color(hex: "#F2C230").opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(uiImage: Self.appIcon ?? UIImage())
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
            Text("Tonne & Torte").font(.title.weight(.black)).tracking(-0.5)
            Text("Nie wieder den Gelben Sack verpassen.\nNie wieder einen Geburtstag vergessen.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func card<Content: View>(title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content().font(.subheadline).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
            Text(text)
        }
    }
}
