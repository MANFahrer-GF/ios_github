import SwiftUI
import SwiftData
import TonneCore

@main
struct TonneUndTorteApp: App {
    @StateObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = TonneUndTorteApp.makeContainer()
        _model = StateObject(wrappedValue: AppModel(container: container))
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .modelContainer(model.container)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.becameActive() } }
                    if phase == .background { model.scheduleBackgroundRefresh() }
                }
                .onOpenURL { url in model.handle(url: url) }
        }
    }

    /// SwiftData-Container mit iCloud-Sync; fällt ohne iCloud-Berechtigung auf lokalen Speicher zurück.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Location.self, WasteType.self, Person.self, CustomEvent.self])
        let cloud = ModelConfiguration("TonneUndTorte", schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
            return container
        }
        let local = ModelConfiguration("TonneUndTorte", schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }
}
