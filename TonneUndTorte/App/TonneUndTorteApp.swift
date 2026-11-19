import SwiftUI
import SwiftData
import TonneCore

/// Hält das App-Modell. Die Datenbank öffnet direkt nach dem Start abseits des Hauptthreads (Absturzbericht 2.0.11 (15):
/// Watchdog 0x8BADF00D beim Hintergrundstart, die App wartete 30 s); bis dahin ist `model` nil und es gibt kein Modell,
/// das leere Daten an Widgets, Watch, Kalender oder Erinnerungen geben könnte. War die Datenbank gesperrt (Hintergrundstart
/// vor dem ersten Entsperren), tauscht `openIfNeeded` das Notfall-Modell später gegen eines mit der echten Datenbank.
@MainActor
final class ModelHolder: ObservableObject {
    static let shared = ModelHolder()
    @Published private(set) var model: AppModel?
    /// Laufendes Öffnen – nie zwei gleichzeitig (Umzug und Container doppelt nebeneinander wären gefährlich).
    private var opening: Task<Void, Never>?

    private init() {
        // Mitteilungs-Aktionen können beim Hintergrundstart vor dem fertigen Öffnen kommen: warten statt verlieren
        let notifications = NotificationManager.shared
        notifications.onPickupDone = { dayKey in Task { await ModelHolder.shared.opened().markDone(dayKey: dayKey) } }
        notifications.onPickupSkip = { dayKey in Task { await ModelHolder.shared.opened().skipOpen(dayKey: dayKey) } }
        // Gespeichert hat die Mitteilung schon selbst – hier nur neu planen und Ansichten auffrischen
        notifications.onCustomDone = { _, _ in
            Task {
                let model = await ModelHolder.shared.opened()
                model.objectWillChange.send()
                await model.refreshAll()
            }
        }
    }

    /// Öffnet die Datenbank, wenn sie noch nicht offen oder beim letzten Mal nicht lesbar war. Läuft schon ein Öffnen, wird
    /// nur darauf gewartet.
    func openIfNeeded() async {
        if let opening { return await opening.value }
        guard model == nil || TonneUndTorteApp.storeUnavailable else { return }
        let task = Task { await open() }
        opening = task
        await task.value
        opening = nil
    }

    /// Das fertig geöffnete Modell – für alles, was schon beim Start Daten braucht (Hintergrundaufgabe, Mitteilung, Link).
    func opened() async -> AppModel {
        if model == nil { await openIfNeeded() }
        return model!   // `open` setzt beim ersten Mal immer ein Modell (notfalls das leere Notfall-Modell)
    }

    private func open() async {
        let first = model == nil
        // ModelContainer ist Sendable, nur `mainContext` gehört zum Hauptthread: Umzug und Öffnen laufen nebenher
        let opened = await Task.detached(priority: .userInitiated) {
            StartTimings.measure("Container gesamt") { TonneUndTorteApp.makeContainer() }
        }.value
        if !first && opened.unavailable { return }   // weiterhin nicht lesbar – Notfall-Modell und Hinweis bleiben
        TonneUndTorteApp.storeUnavailable = opened.unavailable
        if first {
            if TonneUndTorteApp.isDemo { TonneUndTorteApp.seedDemo(opened.container) } else if TonneUndTorteApp.isUITesting { TonneUndTorteApp.seedForUITests(opened.container) }
        }
        let model = StartTimings.measure("Modell") { AppModel(container: opened.container) }
        self.model = model
        if first { StartTimings.finish() } else { await model.start() }
    }
}

@main
struct TonneUndTorteApp: App {
    @StateObject private var holder = ModelHolder.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        StartTimings.begin()
        CrashReportCollector.shared.start()   // vor allem anderen, damit auch Abstürze beim Start berichtet werden
        // Oberflächen-Tests: eigene Einstellungs-Ablage, jedes Mal auf Werkszustand – die echten Einstellungen bleiben unberührt
        if TonneUndTorteApp.isUITesting {
            SettingsKeys.store.removePersistentDomain(forName: SettingsKeys.uiTestSuite)
            SettingsKeys.store.set(true, forKey: SettingsKeys.onboardingDone)
            // Schriftart für die Screenshot-Reihe: -typography serif
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-typography"), i + 1 < args.count, let family = TypographySettings.Family(rawValue: args[i + 1]) {
                TypographySettings(family: family).write(to: SettingsKeys.store)
            }
            #if DEBUG
            CrashReportCollector.seedForUITests()
            CrashReportCenter.shared.reload()
            #endif
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulateCrash") { fatalError("Absichtlicher Testabsturz (-simulateCrash)") }
        #endif
        // Muss vor dem Ende des App-Starts passieren (sonst Exception von BGTaskScheduler) – unabhängig von der Datenbank
        AppModel.registerBackgroundTask()
        StartTimings.measure("Mitteilungen") { NotificationManager.shared.configure() }
        // Datenbank sofort öffnen, auch beim Hintergrundstart ohne Szene (Hintergrundaufgabe und Mitteilungen warten darauf),
        // aber ohne den Start aufzuhalten
        Task { await ModelHolder.shared.openIfNeeded() }
        StartTimings.markOnce("init fertig")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = holder.model {
                    RootView()
                        .environmentObject(model)
                        .modelContainer(model.container)
                        .id(ObjectIdentifier(model))   // neues Modell (nach dem Entsperren) = Oberfläche neu aufbauen
                        .task { await model.start() }
                } else {
                    StoreOpeningView()
                }
            }
            .modifier(NavigationBarTypographySync())
            .appTypography()
            .defaultAppStorage(SettingsKeys.store)
            .environmentObject(CrashReportCenter.shared)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    StartTimings.markOnce("Vordergrund")
                    Task {
                        await holder.openIfNeeded()   // erstes Öffnen abwarten bzw. nach dem Entsperren erneut versuchen
                        await holder.model?.becameActive()
                    }
                }
                if phase == .background { AppModel.scheduleBackgroundRefresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: TonneUndTorteApp.retryStoreNotification)) { _ in
                Task { await holder.openIfNeeded() }
            }
            .onOpenURL { url in Task { await holder.opened().handle(url: url) } }
        }
    }

    /// Bis 2.0.10 (13) lag die Datenbank im App-Group-Ordner (SwiftData-Vorgabe bei vorhandener App Group).
    nonisolated static func moveStoreOutOfAppGroup() -> StoreMigration.Outcome {
        let fm = FileManager.default
        guard let group = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.de.manfahrer.TonneUndTorte")?
                .appendingPathComponent("Library/Application Support"),
              let own = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return .nothingToMove }
        return StoreMigration.move(store: "TonneUndTorte", from: group, to: own)
    }

    /// SwiftData-Container mit iCloud-Sync; fällt ohne iCloud-Berechtigung auf lokalen Speicher zurück.
    /// `unavailable`: Datenbank nicht lesbar, Notfall-Container im Speicher. Läuft abseits des Hauptthreads (`ModelHolder`).
    nonisolated static func makeContainer() -> (container: ModelContainer, unavailable: Bool) {
        let schema = Schema([Location.self, WasteType.self, Person.self, CustomEvent.self])
        #if DEBUG
        // Langsamer Speicher (-simulateSlowStore <Sekunden>): blockiert wie ein hängendes Öffnen von SQLite/iCloud – auch im Testmodus
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-simulateSlowStore"), i + 1 < args.count, let seconds = Double(args[i + 1]) {
            StartTimings.measure("Langsamer Speicher (Test)") { Thread.sleep(forTimeInterval: seconds) }
        }
        #endif
        // Oberflächen-Tests: leere Datenbank nur im Speicher, kein iCloud – echte Daten bleiben unberührt.
        // Klappt das nicht, sofort abbrechen statt still auf die echte Datenbank auszuweichen.
        if isUITesting {
            do {
                return (try ModelContainer(for: schema, configurations: [ModelConfiguration("UITests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]), false)
            } catch {
                fatalError("Testdatenbank konnte nicht angelegt werden: \(error)")
            }
        }
        #if DEBUG
        let simulateFailure = ProcessInfo.processInfo.arguments.contains("-simulateStoreFailure")
        #else
        let simulateFailure = false
        #endif
        if !simulateFailure {
            // Datenbank im eigenen App-Ordner statt im gemeinsamen App-Group-Ordner: Dort beendet iOS die App mit 0xdead10cc,
            // wenn beim Suspendieren noch eine SQLite-Sperre gehalten wird (Absturzbericht 2.0.10 (13)). Einmalig verschieben;
            // klappt das nicht (Gerät nach Neustart noch gesperrt), diesmal den alten Ort öffnen – nie zwei Datenbanken.
            let group: ModelConfiguration.GroupContainer = StartTimings.measure("Umzug") { moveStoreOutOfAppGroup() } == .failed ? .automatic : .none
            let cloud = ModelConfiguration("TonneUndTorte", schema: schema, groupContainer: group, cloudKitDatabase: .automatic)
            if let container = StartTimings.measure("Cloud", { try? ModelContainer(for: schema, configurations: [cloud]) }) {
                return (container, false)
            }
            let local = ModelConfiguration("TonneUndTorte", schema: schema, groupContainer: group, cloudKitDatabase: .none)
            if let container = StartTimings.measure("Lokal", { try? ModelContainer(for: schema, configurations: [local]) }) {
                return (container, false)
            }
        }
        // Datenbank nicht lesbar – typisch: iCloud weckt die App nach einem Neustart im Hintergrund, bevor das iPhone
        // entsperrt wurde; dann sind die App-Daten noch verschlüsselt. Nicht abstürzen (2.0.4-Absturzberichte), sondern
        // leer im Speicher weiterlaufen und nichts nach außen schreiben (`storeUnavailable`). Der nächste Start öffnet sie normal.
        return (try! ModelContainer(for: schema, configurations: [ModelConfiguration("Notfall", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]), true)
    }

    /// Echte Datenbank war beim Start nicht lesbar – dann keine Widgets, Erinnerungen, Abgleiche oder Kalender anfassen.
    @MainActor static var storeUnavailable = false
    static let retryStoreNotification = Notification.Name("TonneUndTorte.retryStore")

    /// Oberflächen-Test läuft (Startschalter oder Umgebungsvariable aus TonneUITests).
    /// Nur in Entwickler-Builds – eine App-Store-Version kennt den Testmodus nicht.
    nonisolated static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTesting") || ProcessInfo.processInfo.environment["TONNE_UITESTING"] == "1"
        #else
        false
        #endif
    }

    /// Beispieldaten für die App-Store-Bilder (nur im Testmodus, Startschalter -demoData).
    nonisolated static var isDemo: Bool { isUITesting && ProcessInfo.processInfo.arguments.contains("-demoData") }

    /// Schöne Beispieldaten für die App-Store-Bilder: heute ein runder Geburtstag, morgen zwei Tonnen, danach gemischt.
    @MainActor
    static func seedDemo(_ container: ModelContainer) {
        let context = container.mainContext
        func dayMonth(_ offset: Int) -> (Int, Int) {
            let c = Calendar.current.dateComponents([.day, .month], from: Days.add(offset, to: Days.today()))
            return (c.day ?? 1, c.month ?? 1)
        }
        let people: [(String, Int, Int?, String, String?)] = [
            ("Oma Erika", 0, 1946, "#EC4899", "0171 2345678"), ("Paul", 6, 1991, "#2F6FED", nil),
            ("Lena", 13, 1998, "#16A34A", nil), ("Jonas", 21, nil, "#F97316", nil), ("Tante Gabi", 34, 1966, "#7C3AED", nil),
        ]
        for (name, offset, year, color, phone) in people {
            let (d, m) = dayMonth(offset)
            let person = Person(name: name, day: d, month: m, year: year, colorHex: color)
            person.phone = phone
            if name == "Paul" { person.giftIdeas = ["Kochbuch", "Konzertkarten"] }
            context.insert(person)
        }
        let location = Location(name: "Gifhorn")
        context.insert(location)
        let bins: [(String, WasteCategory, Int, Int)] = [("Gelber Sack", .packaging, 1, 2), ("Restmüll", .residual, 1, 2),
                                                         ("Papier", .paper, 4, 4), ("Biotonne", .organic, 8, 2)]
        for (index, (name, category, first, every)) in bins.enumerated() {
            let type = WasteType(name: name, category: category, sortOrder: index)
            type.intervalWeeks = every
            type.anchorDate = Days.add(first, to: Days.today())
            type.location = location
            context.insert(type)
        }
        let tuev = CustomEvent(title: "TÜV / Hauptuntersuchung", symbolName: "car.fill", colorHex: "#2F6FED", startDate: Days.add(10, to: Days.today()), recurrence: .everyMonths(24))
        tuev.timeMinutes = 9 * 60 + 30
        context.insert(tuev)
        context.insert(CustomEvent(title: "Rauchmelder testen", symbolName: "flame.fill", colorHex: "#DC2626", startDate: Days.add(17, to: Days.today()), recurrence: .everyMonths(6)))
        try? context.save()
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
        // Schadstoffmobil: keine Tonne, mit Zeit und Ort vom Entsorger
        let hazardous = WasteType(name: "Schadstoffmobil", category: .hazardous)
        let hazardousDay = Days.add(2, to: Days.today())
        hazardous.explicitDates = [hazardousDay]
        hazardous.dayNotes = [Days.iso(hazardousDay): "Rathausplatz Gifhorn (09:00 - 11:00)"]
        hazardous.location = location
        context.insert(hazardous)
        // Leerungs-Statistik (Startschalter -uiTestingQuota): Restmüll mit drei vergangenen Terminen, morgen zusammen mit dem Gelben Sack
        if ProcessInfo.processInfo.arguments.contains("-uiTestingQuota") {
            let rest = WasteType(name: "Restmüll", category: .residual, sortOrder: 1)
            rest.explicitDates = [-6, -4, -2, 1, 15].map { Days.add($0, to: Days.today()) }
            rest.location = location
            context.insert(rest)
            let yellow = WasteType(name: "Gelber Sack", category: .packaging, sortOrder: 2)
            yellow.explicitDates = [Days.add(1, to: Days.today())]
            yellow.location = location
            context.insert(yellow)
        }
        try? context.save()
    }
}
