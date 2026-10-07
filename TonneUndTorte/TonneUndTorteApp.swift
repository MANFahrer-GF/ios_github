import SwiftUI
import SwiftData
import UserNotifications

@main
struct TonneUndTorteApp: App {
    private let container: ModelContainer
    private let notificationDelegate = NotificationDelegate()

    init() {
        do {
            container = try ModelContainer(for: Location.self, WasteType.self, Person.self)
        } catch {
            fatalError("SwiftData-Container konnte nicht erstellt werden: \(error)")
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
