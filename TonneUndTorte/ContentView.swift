import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notifications = NotificationManager.shared

    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("Übersicht", systemImage: "house.fill") }
            MonthCalendarView()
                .tabItem { Label("Kalender", systemImage: "calendar") }
            WasteListView()
                .tabItem { Label("Müll", systemImage: "trash.fill") }
            BirthdayListView()
                .tabItem { Label("Geburtstage", systemImage: "birthday.cake.fill") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .task {
            SeedData.seedIfNeeded(context: context)
            await notifications.refreshStatus()
            await notifications.reschedule(using: context)
            await SyncCoordinator.autoSyncIfDue(context: context)
            await notifications.reschedule(using: context)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await notifications.refreshStatus()
                await notifications.reschedule(using: context)
            }
        }
    }
}

/// Aktualisiert Standorte mit Online-Quelle automatisch, wenn der letzte Abgleich länger zurückliegt.
enum SyncCoordinator {
    static let autoSyncInterval: TimeInterval = 7 * 24 * 60 * 60

    @MainActor
    static func autoSyncIfDue(context: ModelContext) async {
        let locations = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        for location in locations where location.canSync {
            let due = location.lastSyncAt.map { Date().timeIntervalSince($0) > autoSyncInterval } ?? true
            guard due else { continue }
            do {
                _ = try await CalendarImporter.sync(location: location, context: context)
            } catch {
                location.lastSyncMessage = "Automatischer Abgleich fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Location.self, WasteType.self, Person.self], inMemory: true)
}
