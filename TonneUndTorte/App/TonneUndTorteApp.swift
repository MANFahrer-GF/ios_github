import SwiftUI
import SwiftData
import TonneCore

@main
struct TonneUndTorteApp: App {
    @StateObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Oberflächen-Tests: eigene Einstellungs-Ablage, jedes Mal auf Werkszustand – die echten Einstellungen bleiben unberührt
        if TonneUndTorteApp.isUITesting {
            SettingsKeys.store.removePersistentDomain(forName: SettingsKeys.uiTestSuite)
            SettingsKeys.store.set(true, forKey: SettingsKeys.onboardingDone)
        }
        let container = TonneUndTorteApp.makeContainer()
        if TonneUndTorteApp.isUITesting { TonneUndTorteApp.seedForUITests(container) }
        _model = StateObject(wrappedValue: AppModel(container: container))
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .defaultAppStorage(SettingsKeys.store)
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
        // Oberflächen-Tests: leere Datenbank nur im Speicher, kein iCloud – echte Daten bleiben unberührt.
        // Klappt das nicht, sofort abbrechen statt still auf die echte Datenbank auszuweichen.
        if isUITesting {
            do {
                return try ModelContainer(for: schema, configurations: [ModelConfiguration("UITests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
            } catch {
                fatalError("Testdatenbank konnte nicht angelegt werden: \(error)")
            }
        }
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

    /// Oberflächen-Test läuft (Startschalter oder Umgebungsvariable aus TonneUITests).
    /// Nur in Entwickler-Builds – eine App-Store-Version kennt den Testmodus nicht.
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTesting") || ProcessInfo.processInfo.environment["TONNE_UITESTING"] == "1"
        #else
        false
        #endif
    }

    /// Testdaten für die Oberflächen-Tests: Geburtstag in drei Tagen (mit Jahr und Telefon), eigener Termin heute mit Uhrzeit, Papiertonne.
    @MainActor
    static func seedForUITests(_ container: ModelContainer) {
        let context = container.mainContext
        let birthday = Days.add(3, to: Days.today())
        let c = Calendar.current.dateComponents([.day, .month], from: birthday)
        let person = Person(name: "Test Person", day: c.day ?? 1, month: c.month ?? 1, year: 1960)
        person.phone = "0171 1234567"
        context.insert(person)
        // Für die Layout-Prüfung: langer Name mit rundem Geburtstag am selben Tag, einer ohne Jahr, einer später mit Geschenkideen
        let long = Person(name: "Gabriele Grundhöfer-Kantorowicz", day: c.day ?? 1, month: c.month ?? 1, year: 1956)
        long.phone = "05371 123456"
        context.insert(long)
        context.insert(Person(name: "Albi", day: c.day ?? 1, month: c.month ?? 1))
        // Heute Geburtstag – dann gibt es Anrufen und Nachricht direkt in der Zeile
        let tc = Calendar.current.dateComponents([.day, .month], from: Days.today())
        let today = Person(name: "Lena Sommer", day: tc.day ?? 1, month: tc.month ?? 1, year: 1990)
        today.phone = "0151 7654321"
        context.insert(today)
        let laterDay = Days.add(15, to: Days.today())
        let lc = Calendar.current.dateComponents([.day, .month], from: laterDay)
        let later = Person(name: "Maximilian Mustermann-Schulz", day: lc.day ?? 1, month: lc.month ?? 1, year: 1953)
        later.giftIdeas = ["Buch", "Gutschein"]
        context.insert(later)
        context.insert(CustomEvent(title: "Hauptuntersuchung beim TÜV Nord in Gifhorn", symbolName: "car.fill", startDate: Days.add(8, to: Days.today()), recurrence: .everyMonths(24)))
        let event = CustomEvent(title: "Testtermin", symbolName: "car.fill", startDate: Days.today(), recurrence: .yearly)
        event.timeMinutes = 14 * 60 + 30
        context.insert(event)
        // Ein Standort mit Papiertonne in fünf und zwölf Tagen
        let location = Location(name: "Teststraße")
        context.insert(location)
        let paper = WasteType(name: "Papier", category: .paper)
        paper.explicitDates = [Days.add(5, to: Days.today()), Days.add(12, to: Days.today())]
        paper.location = location
        context.insert(paper)
        try? context.save()
    }
}
