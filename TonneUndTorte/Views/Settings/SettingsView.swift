import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var notifications = NotificationManager.shared

    @AppStorage(ReminderSettings.Keys.eveningEnabled) private var eveningEnabled = true
    @AppStorage(ReminderSettings.Keys.eveningMinutes) private var eveningMinutes = 19 * 60
    @AppStorage(ReminderSettings.Keys.morningEnabled) private var morningEnabled = false
    @AppStorage(ReminderSettings.Keys.morningMinutes) private var morningMinutes = 7 * 60
    @AppStorage(ReminderSettings.Keys.birthdayMinutes) private var birthdayMinutes = 9 * 60

    @State private var showResetConfirm = false
    @State private var infoMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: notifications.isAuthorized ? "bell.badge.fill" : "bell.slash.fill")
                            .foregroundStyle(notifications.isAuthorized ? .green : .orange)
                        Text(statusText)
                        Spacer()
                        if notifications.authorizationStatus == .notDetermined {
                            Button("Erlauben") {
                                Task {
                                    await notifications.requestAuthorization()
                                    await notifications.reschedule(using: context)
                                }
                            }
                        } else if notifications.authorizationStatus == .denied {
                            Button("Einstellungen") { notifications.openSystemSettings() }
                        }
                    }
                    LabeledContent("Geplante Erinnerungen", value: "\(notifications.pendingCount)")
                    Button("Testbenachrichtigung senden") {
                        notifications.sendTestNotification()
                        infoMessage = "Die Testbenachrichtigung kommt in 3 Sekunden."
                    }
                    .disabled(!notifications.isAuthorized)
                } header: {
                    Text("Mitteilungen")
                } footer: {
                    Text("iOS erlaubt maximal 64 geplante Mitteilungen. Die App plant deshalb immer die nächsten Termine und aktualisiert bei jedem Öffnen.")
                }

                Section {
                    Toggle("Am Vorabend erinnern", isOn: $eveningEnabled)
                    if eveningEnabled {
                        TimeOfDayPicker(title: "Uhrzeit", minutes: $eveningMinutes)
                    }
                    Toggle("Am Abholtag morgens erinnern", isOn: $morningEnabled)
                    if morningEnabled {
                        TimeOfDayPicker(title: "Uhrzeit", minutes: $morningMinutes)
                    }
                } header: {
                    Text("Müll-Erinnerungen")
                } footer: {
                    Text("Beispiel: „Morgen: Gelber Sack – heute Abend rausstellen.“")
                }

                Section {
                    TimeOfDayPicker(title: "Uhrzeit", minutes: $birthdayMinutes)
                } header: {
                    Text("Geburtstags-Erinnerungen")
                } footer: {
                    Text("Wie viele Tage vorher erinnert wird, legst du bei jeder Person einzeln fest.")
                }

                Section("Daten") {
                    Button("Beispiel-Geburtstage laden") {
                        SeedData.insertDemoBirthdays(context: context)
                        reschedule()
                        infoMessage = "Beispiel-Geburtstage wurden angelegt."
                    }
                    Button("Standard-Standorte wiederherstellen") {
                        SeedData.insertDefaultLocations(context: context)
                        reschedule()
                        infoMessage = "Gifhorn und Kuhlhausen wurden angelegt."
                    }
                    Button("Alle Daten löschen", role: .destructive) {
                        showResetConfirm = true
                    }
                }

                Section("Über") {
                    LabeledContent("App", value: "Tonne & Torte")
                    LabeledContent("Version", value: appVersion)
                    Text("Müll- und Geburtstagskalender mit Erinnerungen. Abfuhrtermine kommen aus dem AWIDO-Portal (Landkreis Gifhorn) und der Abfall-App Landkreis Stendal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .onChange(of: eveningEnabled) { _, _ in reschedule() }
            .onChange(of: eveningMinutes) { _, _ in reschedule() }
            .onChange(of: morningEnabled) { _, _ in reschedule() }
            .onChange(of: morningMinutes) { _, _ in reschedule() }
            .onChange(of: birthdayMinutes) { _, _ in reschedule() }
            .confirmationDialog("Wirklich alle Standorte, Müllarten und Geburtstage löschen?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Alles löschen", role: .destructive) {
                    SeedData.deleteEverything(context: context)
                    reschedule()
                }
            }
            .alert("Hinweis", isPresented: Binding(get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
            }
            .task { await notifications.refreshStatus() }
        }
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func reschedule() {
        Task { await notifications.reschedule(using: context) }
    }
}
