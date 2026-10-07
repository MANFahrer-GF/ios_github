import SwiftUI
import TonneCore

/// Erster Start: Willkommen → Entsorger finden (Assistent) → Mitteilungen erlauben.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var showWizard = false
    @State private var showManual = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#2F6FED"), Color(hex: "#2E9E6B")], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 10) {
                    Text("🗑️🎂").font(.system(size: 72))
                    Text("Tonne & Torte").font(.largeTitle.weight(.bold))
                    Text("Nie wieder den Gelben Sack verpassen.\nNie wieder einen Geburtstag vergessen.")
                        .multilineTextAlignment(.center).font(.title3).opacity(0.9)
                }
                VStack(alignment: .leading, spacing: 14) {
                    feature("antenna.radiowaves.left.and.right", "Termine kommen automatisch vom Entsorger – \(ProviderCatalog.count) Landkreise und Städte.")
                    feature("bell.badge.fill", "Erinnerung am Vorabend mit „Erledigt“-Knopf, Widget und Sperrbildschirm.")
                    feature("icloud.fill", "Alles in deiner iCloud – auf iPhone und iPad gleich.")
                }
                .padding(20)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Spacer()
                VStack(spacing: 12) {
                    Button { showWizard = true } label: {
                        Text("Entsorger finden").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Color(hex: "#2F6FED")).controlSize(.large)
                    Button("Ohne Entsorger starten (Rhythmus von Hand)") { showManual = true }.foregroundStyle(.white.opacity(0.9)).font(.subheadline)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .sheet(isPresented: $showWizard, onDismiss: requestNotifications) { SourceWizardView(location: nil).environmentObject(model) }
        .sheet(isPresented: $showManual, onDismiss: requestNotifications) { NewLocationSheet { _ in }.environmentObject(model) }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 28)
            Text(text).font(.subheadline)
        }
    }

    private func requestNotifications() {
        Task {
            if notifications.authorizationStatus == .notDetermined { await notifications.requestAuthorization() }
            await model.refreshAll()
        }
    }
}
