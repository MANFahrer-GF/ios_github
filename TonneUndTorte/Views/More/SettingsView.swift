import SwiftUI
import UIKit
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
    @State private var activityStatus: LiveActivityManager.Status = .none
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
                if liveActivities {
                    // Die Live-Aktivität startet zur Abendzeit – auch wenn die Abend-Mitteilung aus ist.
                    if !eveningEnabled { TimeOfDayPicker(title: L10n.t("Uhrzeit Live-Aktivität", "Live Activity time"), minutes: $eveningMinutes) }
                    if LiveActivityManager.canSchedule, LiveActivityManager.systemAllows { activityStatusRow }
                }
            } header: { Text("Müll-Erinnerungen") } footer: {
                liveActivityFooter
            }

            Section("Geburtstage & eigene Termine") {
                TimeOfDayPicker(title: "Geburtstage", minutes: $birthdayMinutes)
                TimeOfDayPicker(title: "Eigene Termine", minutes: $customMinutes)
            }

            Section {
                LabeledContent("iCloud", value: "Daten werden über deinen iCloud-Account synchronisiert")
                Button("Alle Daten löschen", role: .destructive) { showResetConfirm = true }
            } header: { Text("Daten") }

            Section {
                NavigationLink { AboutView() } label: {
                    Label("Über Tonne & Torte", systemImage: "info.circle.fill")
                }
                LabeledContent("Version", value: appVersion)
            } header: {
                Text("Über")
            } footer: {
                Text("Mit ❤️ aus Gifhorn – gebaut von Thomas Kant.")
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
        .task {
            await notifications.refreshStatus()
            activityStatus = LiveActivityManager.status()
        }
    }

    // MARK: Live-Aktivität

    private var eveningTimeText: String { String(format: "%02d:%02d", eveningMinutes / 60, eveningMinutes % 60) }

    @ViewBuilder
    private var activityStatusRow: some View {
        switch activityStatus {
        case .running(let names):
            LabeledContent("Live-Aktivität", value: L10n.t("läuft gerade · ", "running · ") + ReminderPlanner.joinNames(names))
        case .planned(let start, let names):
            LabeledContent("Nächste Live-Aktivität", value: start.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · " + ReminderPlanner.joinNames(names))
        case .none:
            LabeledContent("Nächste Live-Aktivität", value: L10n.t("keine geplant", "none planned"))
        }
    }

    /// Erklärt, wie die Live-Aktivität auf genau diesem iPhone startet.
    @ViewBuilder
    private var liveActivityFooter: some View {
        if !liveActivities {
            Text("Die Live-Aktivität zeigt „Tonne rausstellen“ auf dem Sperrbildschirm und in der Dynamic Island.")
        } else if !LiveActivityManager.systemAllows {
            Text("Live-Aktivitäten sind in den iOS-Einstellungen für Tonne & Torte ausgeschaltet: Einstellungen › Apps › Tonne & Torte › Live-Aktivitäten.")
        } else if LiveActivityManager.canSchedule {
            Text("Am Vorabend um \(eveningTimeText) erscheint „Tonne rausstellen“ von selbst auf dem Sperrbildschirm und in der Dynamic Island – auch wenn die App geschlossen ist. Sie meldet sich mit einem Hinweis, die Abend-Erinnerung kommt dann nicht doppelt. Geplant werden immer die nächsten zwei Abholungen; öffne die App dafür ab und zu.")
        } else {
            Text("Auf diesem iPhone (iOS \(UIDevice.current.systemVersion)) erscheint die Live-Aktivität, sobald du die App am Vorabend öffnest – erst ab iOS 26 kommt sie von selbst. Ohne Öffnen geht es mit dem Kurzbefehl „Tonnen-Erinnerung starten“, z. B. als Automation in der Kurzbefehle-App.")
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
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func refresh() {
        Task {
            await model.refreshAll()
            activityStatus = LiveActivityManager.status()
        }
    }
}
