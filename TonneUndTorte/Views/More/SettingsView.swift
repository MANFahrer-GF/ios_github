import SwiftUI
import SwiftData
import TonneCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @ObservedObject private var notifications = NotificationManager.shared

    @AppStorage(SettingsKeys.eveningEnabled) private var eveningEnabled = true
    @AppStorage(SettingsKeys.eveningMinutes) private var eveningMinutes = 19 * 60
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = true
    @AppStorage(SettingsKeys.escalationMinutes) private var escalationMinutes = 21 * 60
    @AppStorage(SettingsKeys.morningEnabled) private var morningEnabled = false
    @AppStorage(SettingsKeys.morningMinutes) private var morningMinutes = 7 * 60
    @AppStorage(SettingsKeys.birthdayMinutes) private var birthdayMinutes = 9 * 60
    @AppStorage(SettingsKeys.customMinutes) private var customMinutes = 9 * 60
    @AppStorage(SettingsKeys.liveActivities) private var liveActivities = true
    @State private var showResetConfirm = false
    @State private var info: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: notifications.isAuthorized ? "bell.badge.fill" : "bell.slash.fill").foregroundStyle(notifications.isAuthorized ? .green : .orange)
                    Text(statusText)
                    Spacer()
                    if notifications.authorizationStatus == .notDetermined {
                        Button("Erlauben") { Task { await notifications.requestAuthorization(); await model.refreshAll() } }
                    } else if notifications.authorizationStatus == .denied {
                        Button("Einstellungen") { notifications.openSystemSettings() }
                    }
                }
                LabeledContent("Geplante Erinnerungen", value: "\(notifications.pendingCount)")
                Button("Testmitteilung senden") { notifications.sendTest(); info = "Kommt in 3 Sekunden – mit Knöpfen „Erledigt“ und „In 1 Stunde“." }.disabled(!notifications.isAuthorized)
            } header: { Text("Mitteilungen") }

            Section {
                Toggle("Am Vorabend erinnern", isOn: $eveningEnabled)
                if eveningEnabled {
                    TimeOfDayPicker(title: "Uhrzeit", minutes: $eveningMinutes)
                    Toggle("Nochmal erinnern, falls nicht „Erledigt“", isOn: $escalationEnabled)
                    if escalationEnabled { TimeOfDayPicker(title: "Zweite Erinnerung", minutes: $escalationMinutes) }
                }
                Toggle("Am Abholtag morgens erinnern", isOn: $morningEnabled)
                if morningEnabled { TimeOfDayPicker(title: "Uhrzeit morgens", minutes: $morningMinutes) }
                Toggle("Live-Aktivität am Vorabend", isOn: $liveActivities)
            } header: { Text("Müll-Erinnerungen") } footer: {
                Text("Die Live-Aktivität zeigt „Tonne rausstellen“ auf dem Sperrbildschirm und in der Dynamic Island, sobald du die App am Vorabend öffnest.")
            }

            Section("Geburtstage & eigene Termine") {
                TimeOfDayPicker(title: "Geburtstage", minutes: $birthdayMinutes)
                TimeOfDayPicker(title: "Eigene Termine", minutes: $customMinutes)
            }

            Section {
                LabeledContent("iCloud", value: "Daten werden über deinen iCloud-Account synchronisiert")
                Button("Alle Daten löschen", role: .destructive) { showResetConfirm = true }
            } header: { Text("Daten") }

            Section("Über") {
                LabeledContent("Version", value: appVersion)
                Text("Termine kommen direkt von den Portalen der Entsorger (AWIDO, AbfallPlus, Jumomind, Abfallnavi, Abfall-App). Angaben ohne Gewähr. Katalog mit \(ProviderCatalog.count) Entsorgern.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Einstellungen")
        .onChange(of: eveningEnabled) { _, _ in refresh() }
        .onChange(of: eveningMinutes) { _, _ in refresh() }
        .onChange(of: escalationEnabled) { _, _ in refresh() }
        .onChange(of: escalationMinutes) { _, _ in refresh() }
        .onChange(of: morningEnabled) { _, _ in refresh() }
        .onChange(of: morningMinutes) { _, _ in refresh() }
        .onChange(of: birthdayMinutes) { _, _ in refresh() }
        .onChange(of: customMinutes) { _, _ in refresh() }
        .onChange(of: liveActivities) { _, _ in refresh() }
        .confirmationDialog("Wirklich alle Standorte, Müllarten, Geburtstage und Termine löschen?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                try? context.delete(model: WasteType.self); try? context.delete(model: Location.self)
                try? context.delete(model: Person.self); try? context.delete(model: CustomEvent.self)
                try? context.save()
                model.onboardingDone = false
                refresh()
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) { Button("OK", role: .cancel) {} } message: { Text(info ?? "") }
        .task { await notifications.refreshStatus() }
    }

    private var statusText: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Mitteilungen erlaubt"
        case .denied: return "Mitteilungen abgelehnt"
        case .notDetermined: return "Noch nicht erlaubt"
        @unknown default: return "Unbekannt"
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func refresh() { Task { await model.refreshAll() } }
}
