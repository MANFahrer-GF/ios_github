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
                card(title: "Gebaut von Thomas Kant", symbol: "person.fill") {
                    Text("Tonne & Torte ist ein Hobbyprojekt aus Gifhorn. Entstanden, weil der Gelbe Sack einmal zu oft stehen geblieben ist und Geburtstage nicht im Kalender standen. Die App ist für mich und meine Familie gedacht und wird nebenbei weiterentwickelt.")
                }
                card(title: "Was die App kann", symbol: "sparkles") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Abfuhrtermine direkt vom Entsorger, wöchentlich automatisch abgeglichen")
                        bullet("Erinnerung am Vorabend mit „Erledigt“ und „Später nochmal“")
                        bullet("Widgets, Sperrbildschirm, Live-Aktivität, Apple Watch und Siri")
                        bullet("Geburtstage mit Alter, runden Jubiläen und Geschenkideen")
                        bullet("Eigene wiederkehrende Termine wie TÜV oder Rauchmelder")
                        bullet("Apple-Kalender, ICS, CSV und PDF als Export")
                    }
                }
                card(title: "Woher die Daten kommen", symbol: "antenna.radiowaves.left.and.right") {
                    Text("Termine kommen direkt von den Portalen der Entsorger: AWIDO, AbfallPlus, Jumomind, Abfallnavi, Abfall-App, C-Trace, Müllmax sowie Köln, Leipzig und Region Hannover. Der Katalog kennt \(ProviderCatalog.count) Entsorger. Alle Angaben ohne Gewähr, im Zweifel gilt der Abfuhrkalender deines Entsorgers.")
                }
                card(title: "Deine Daten", symbol: "lock.shield.fill") {
                    Text("Es gibt kein Konto und keinen eigenen Server. Standorte, Müllarten und Geburtstage bleiben auf deinem Gerät und werden nur über deine eigene iCloud zwischen iPhone, iPad und Watch abgeglichen. Die App verschickt nichts an Dritte.")
                }
                card(title: "Danke", symbol: "heart.fill") {
                    Text("Die Liste der Entsorger beruht auf dem Open-Source-Projekt hacs_waste_collection_schedule (MIT-Lizenz). Symbole: SF Symbols von Apple.")
                }
                Text("Version \(version)")
                    .font(.footnote).foregroundStyle(.secondary)
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

    private func card<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content().font(.subheadline).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
            Text(text)
        }
    }
}
