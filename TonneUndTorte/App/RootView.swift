import SwiftUI
import SwiftData
import TonneCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Query private var locations: [Location]

    var body: some View {
        Group {
            if TonneUndTorteApp.storeUnavailable {
                // Datenbank gerade nicht lesbar – nichts Leeres zum Bearbeiten anbieten, sondern erklären und neu versuchen
                ContentUnavailableView {
                    Label(L10n.t("Daten werden geöffnet …", "Opening your data …"), systemImage: "lock.circle")
                } description: {
                    Text(L10n.t("Deine Termine sind gerade nicht lesbar – meist direkt nach einem Neustart, bevor das iPhone entsperrt wurde.",
                                "Your data can't be read right now – usually right after a restart, before the iPhone was unlocked."))
                } actions: {
                    Button(L10n.t("Erneut versuchen", "Try again")) { NotificationCenter.default.post(name: TonneUndTorteApp.retryStoreNotification, object: nil) }
                        .buttonStyle(.borderedProminent)
                }
            } else if model.onboardingDone || !locations.isEmpty {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert(L10n.t("Nicht gespeichert", "Not saved"), isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.lastError ?? "") }
        .background { CrashReportPrompt() }
    }
}

/// Während die Datenbank nach dem Start öffnet (meist Sekundenbruchteile): leer wie der Startbildschirm, erst nach einer
/// halben Sekunde ein Hinweis – so flackert der normale Start nicht. Bewusst ohne Bedienung: Eingaben gingen sonst in ein
/// Modell ohne Datenbank und wären nach dem Öffnen weg.
struct StoreOpeningView: View {
    @State private var showHint = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if showHint {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.t("Termine werden geladen …", "Loading your dates …")).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            showHint = true
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            OverviewView().tabItem { Label("Übersicht", systemImage: "house.fill") }.tag(AppTab.overview)
            MonthCalendarView().tabItem { Label("Kalender", systemImage: "calendar") }.tag(AppTab.calendar)
            WasteListView().tabItem { Label("Müll", systemImage: "trash.fill") }.tag(AppTab.waste)
            BirthdayListView().tabItem { Label(L10n.t("Termine", "Events"), systemImage: "birthday.cake.fill") }.tag(AppTab.birthdays)
            MoreView().tabItem { Label("Mehr", systemImage: "ellipsis.circle.fill") }.tag(AppTab.more)
        }
    }
}
