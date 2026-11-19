import Foundation
import CoreData
import SwiftData
import SwiftUI
import BackgroundTasks
import UserNotifications
import TonneCore

/// Einstellungs-Schlüssel (UserDefaults) – von Views per @AppStorage und vom Modell genutzt.
enum SettingsKeys {
    /// Ablage aller Einstellungen. Im Oberflächen-Test eine eigene Ablage – echte Einstellungen bleiben unberührt.
    static let store: UserDefaults = TonneUndTorteApp.isUITesting ? (UserDefaults(suiteName: uiTestSuite) ?? .standard) : .standard
    static let uiTestSuite = "de.manfahrer.TonneUndTorte.uitests"
    /// Schrift-Einstellung: in der App-Gruppe, damit Widget und Watch sie lesen (im Oberflächen-Test die Test-Ablage).
    static var typographyStore: UserDefaults { TonneUndTorteApp.isUITesting ? store : SnapshotStore.defaults }
    static let onboardingDone = "app.onboardingDone"
    static let dutyTipDismissed = "tip.dutyDismissed"
    static let eveningEnabled = "reminder.evening.enabled"
    static let eveningMinutes = "reminder.evening.minutes"
    static let morningEnabled = "reminder.morning.enabled"
    static let morningMinutes = "reminder.morning.minutes"
    static let escalationEnabled = "reminder.escalation.enabled"
    static let escalationMinutes = "reminder.escalation.minutes"
    static let birthdayEnabled = "reminder.birthday.enabled"
    static let birthdayMinutes = "reminder.birthday.minutes"
    static let birthdayPreMinutes = "reminder.birthday.preMinutes"
    static let birthdayWeekBefore = "reminder.birthday.weekBefore"
    static let customEnabled = "reminder.custom.enabled"
    static let customMinutes = "reminder.custom.minutes"
    static let customPreMinutes = "reminder.custom.preMinutes"
    static let customLeadMinutes = "reminder.custom.leadMinutes"
    static let customDayBefore = "reminder.custom.dayBefore"
    static let customDone = "custom.doneOccurrences"
    /// Wecker am Vorabend (AlarmKit, ab iOS 26) – Standard aus, nur auf diesem Gerät.
    static let alarmEnabled = "reminder.alarm.enabled"
    static let alarmMinutes = "reminder.alarm.minutes"
    // Übersicht anpassen
    static let overviewWaste = "overview.showWaste"
    static let overviewBirthdays = "overview.showBirthdays"
    static let overviewCustom = "overview.showCustom"
    static let overviewDays = "overview.days"
    static let overviewStats = "overview.showStats"
    /// Tag (ISO), an dem die Nachtragen-Karte weggewischt wurde.
    static let catchUpDismissed = "quota.catchUpDismissed"

    /// „Erledigt“ für eigene Termine: je Vorkommen „<id>|<Tag>“. Nur auf diesem Gerät – es unterdrückt Erinnerungen,
    /// damit ist kein neues Feld im iCloud-Schema nötig. Ältere Einträge als 60 Tage fallen beim Speichern heraus.
    static func customDoneKeys(_ defaults: UserDefaults = SettingsKeys.store) -> Set<String> {
        Set(defaults.stringArray(forKey: customDone) ?? [])
    }
    static func setCustomDone(_ done: Bool, id: UUID, dayKey: String, defaults: UserDefaults = SettingsKeys.store) {
        var keys = customDoneKeys(defaults)
        let key = "\(id.uuidString)|\(dayKey)"
        if done { keys.insert(key) } else { keys.remove(key) }
        let cutoff = Days.iso(Days.add(-60, to: Days.today()))
        defaults.set(keys.filter { $0.split(separator: "|").last.map { String($0) >= cutoff } ?? false }.sorted(), forKey: customDone)
    }
    static func isCustomDone(id: UUID, day: Date, keys: Set<String>) -> Bool { keys.contains("\(id.uuidString)|\(Days.iso(day))") }
    static let bringInEnabled = "reminder.bringIn.enabled"
    static let bringInMinutes = "reminder.bringIn.minutes"
    static let locationFilter = "filter.locationID"
    static let liveActivities = "feature.liveActivities"
    /// Live-Aktivitäten sind an, solange der Schalter nicht ausdrücklich ausgeschaltet wurde.
    static func liveActivitiesEnabled(_ defaults: UserDefaults = SettingsKeys.store) -> Bool {
        defaults.object(forKey: liveActivities) == nil || defaults.bool(forKey: liveActivities)
    }
    static let backgroundRefreshID = "de.manfahrer.TonneUndTorte.refresh"

    static func reminderSettings(_ defaults: UserDefaults = SettingsKeys.store) -> ReminderSettings {
        var settings = ReminderSettings()
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key) }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        settings.eveningEnabled = bool(eveningEnabled, true)
        settings.eveningMinutes = int(eveningMinutes, 19 * 60)
        settings.morningEnabled = bool(morningEnabled, false)
        settings.morningMinutes = int(morningMinutes, 7 * 60)
        settings.escalationEnabled = bool(escalationEnabled, true)
        settings.escalationMinutes = int(escalationMinutes, 21 * 60)
        settings.birthdayEnabled = bool(birthdayEnabled, true)
        settings.birthdayMinutes = int(birthdayMinutes, 9 * 60)
        settings.birthdayPreMinutes = int(birthdayPreMinutes, 9 * 60)
        settings.birthdayWeekBefore = bool(birthdayWeekBefore, false)
        settings.customEnabled = bool(customEnabled, true)
        settings.customMinutes = int(customMinutes, 9 * 60)
        settings.customPreMinutes = int(customPreMinutes, 9 * 60)
        settings.customLeadMinutes = int(customLeadMinutes, 60)
        settings.customDayBefore = bool(customDayBefore, false)
        settings.bringInEnabled = bool(bringInEnabled, true)
        settings.bringInMinutes = int(bringInMinutes, 17 * 60)
        settings.alarmEnabled = AlarmScheduler.isSupported && bool(alarmEnabled, false)
        settings.alarmMinutes = int(alarmMinutes, 20 * 60)
        return settings
    }

    /// Bis 2.0.2 kamen Vorab-Erinnerungen zur selben Uhrzeit wie am Tag selbst. Wer die Uhrzeit geändert hatte,
    /// behält sie darum auch für die neue, getrennte Vorab-Uhrzeit.
    static func migrate(_ defaults: UserDefaults = SettingsKeys.store) {
        for (day, pre) in [(birthdayMinutes, birthdayPreMinutes), (customMinutes, customPreMinutes)]
        where defaults.object(forKey: pre) == nil && defaults.object(forKey: day) != nil {
            defaults.set(defaults.integer(forKey: day), forKey: pre)
        }
    }
}

/// Die Tabs der App – damit eine Mitteilung den passenden öffnen kann.
enum AppTab: Hashable { case overview, calendar, waste, birthdays, more }

/// Ein Termin für die Anzeige – Abholung, Geburtstag oder eigener Termin.
struct CalendarEvent: Identifiable, Hashable {
    enum Kind: Hashable { case waste, birthday, custom }
    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let subtitle: String
    let colorHex: String
    let symbolName: String
    let locationID: UUID?
    let locationName: String?
    let years: Int?
    let done: Bool
    /// Die Person hinter einem Geburtstag bzw. der eigene Termin.
    var personID: UUID? = nil
    var eventID: UUID? = nil
    var wasteTypeID: UUID? = nil
    /// Zeit/Ort beim Hinbringen (Schadstoffmobil), falls der Entsorger sie liefert.
    var note: String? = nil
    /// Tonne / bereitstellen / hinbringen – bestimmt Worte und ob es „draußen“ heißt.
    var handling: WasteHandling? = nil
    /// „Diesmal nicht rausstellen“ – die Abfuhr kommt, diese Müllart bleibt aber drin.
    var notPutOut: Bool = false
    /// Tonnendienst: An diesem Tag ist jemand anderes dran.
    var offDuty: Bool = false
    /// Gezählte Müllart: „noch 5 von 12 frei“.
    var quotaLine: String? = nil
    /// Nichts mehr zu tun: erledigt, bewusst drin gelassen oder nicht zuständig.
    var settled: Bool { done || notPutOut || offDuty }
    var color: Color { Color(hex: colorHex) }
    var isMilestone: Bool { years.map { AnnualDate.isMilestone($0) } ?? false }
}

/// Zentrales App-Modell: Zugriff auf die Datenbank, Abgleich, Erinnerungen, Widget-Snapshot.
@MainActor
final class AppModel: ObservableObject {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    @Published var isSyncing = false
    @Published var recentChanges: [String] = []
    @Published var lastError: String?
    @Published var selectedTab: AppTab = .overview
    /// Aus einer Mitteilung angetippt: diese Person bzw. diesen Termin öffnen.
    @Published var personToOpen: UUID?
    @Published var eventToOpen: UUID?
    @Published var onboardingDone: Bool = SettingsKeys.store.bool(forKey: SettingsKeys.onboardingDone) {
        didSet { SettingsKeys.store.set(onboardingDone, forKey: SettingsKeys.onboardingDone) }
    }

    private let notifications = NotificationManager.shared
    private var started = false
    private var plannedDuty: [String] = []
    private var dutyRecheck: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
        SettingsKeys.migrate()
        // „Erledigt“, „Diesmal nicht“ und eigene Termine aus Mitteilungen verdrahtet `ModelHolder` (wartet aufs Öffnen)
        notifications.onOpen = { [weak self] target in self?.open(target) }
        // Apple Watch: Snapshot hinschicken, „Erledigt“ entgegennehmen
        WatchSync.shared.activate()
        // Von der Watch: erst ablegen wie ein Tipp im Widget – ist die Datenbank gerade nicht lesbar, holt das nächste Öffnen es nach
        WatchSync.shared.onUndoReceived = { dayKey in
            SnapshotStore.markUndone(dayKey: dayKey)
            ModelHolder.shared.applyPendingMarkers()
        }
        WatchSync.shared.onDoneReceived = { dayKey in
            SnapshotStore.markDone(dayKey: dayKey)
            ModelHolder.shared.applyPendingMarkers()
        }
        NotificationCenter.default.addObserver(forName: WatchSync.updatedNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
        NotificationCenter.default.addObserver(forName: SnapshotStore.notificationName, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.applyPendingDoneMarkers() }
        }
        // Auf einem anderen Gerät geänderter Tonnendienst oder „Erledigt“: sonst gälten alte Mitteilungen und Wecker bis zum nächsten Öffnen
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { self?.recheckDutyAfterImport() }
        }
        // „Ist drin“ aus Widget oder Mitteilung: Hinweis und Erinnerung für heute entfallen
        NotificationCenter.default.addObserver(forName: SnapshotStore.broughtInNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
    }

    // MARK: - Lebenszyklus

    func start() async {
        guard !started else { return }
        started = true
        repairSearchTextLabels()
        await notifications.refreshStatus()
        await becameActive()
    }

    /// Standorte aus Leipzig, Köln, Hannover, Müllmax und sector27 trugen bis 2.0.9 den getippten Suchtext im Namen.
    /// Nur der unveränderte automatische Name wird ersetzt; ein selbst vergebener Name bleibt.
    func repairSearchTextLabels() {
        var changed = false
        for location in allLocations() {
            guard var source = location.source, let fresh = source.repairedSearchTextLabel() else { continue }
            if location.name == source.label { location.name = fresh }
            source.label = fresh
            location.source = source
            changed = true
        }
        if changed { _ = save() }
    }

    func becameActive() async {
        await applyPendingDoneMarkers()
        _ = await syncAll(force: false)
        await refreshAll()
    }

    /// Erinnerungen, Widget-Snapshot und Live-Aktivität neu aufbauen.
    func refreshAll() async {
        // Oberflächen-Test: keine Widgets, Watch, Live-Aktivität, Mitteilungen oder Kalender anfassen
        guard !TonneUndTorteApp.isUITesting, !TonneUndTorteApp.storeUnavailable else { return }
        plannedDuty = dutyFingerprint()
        let snapshot = buildSnapshot()
        SnapshotStore.save(snapshot)
        WatchSync.shared.send(snapshot)
        let settings = SettingsKeys.reminderSettings()
        // Zuerst die Live-Aktivitäten: Für Abende, an denen iOS die geplante Aktivität selbst startet,
        // meldet sich diese mit eigenem Hinweis – die gleichlautende Abend-Mitteilung entfällt dann.
        var scheduledDays: Set<String> = []
        if SettingsKeys.liveActivitiesEnabled() {
            scheduledDays = await LiveActivityManager.refresh(with: snapshot, eveningMinutes: settings.eveningMinutes).scheduledDays
        } else {
            await LiveActivityManager.endAll()
        }
        let pickups = plannedPickups()
        let plan = ReminderPlanner.plan(pickups: pickups, birthdays: plannedBirthdays(), customEvents: plannedCustomEvents(), settings: settings)
            .filter { !($0.category == .wasteEvening && scheduledDays.contains($0.dayKey)) }
        await notifications.apply(plan, offDutyDays: offDutyDayKeys())
        // Wecker aus denselben Terminen – unabhängig von Live-Aktivität und Abend-Mitteilung
        await AlarmScheduler.apply(ReminderPlanner.alarms(pickups: pickups, settings: settings))
        await CalendarExport.autoSyncIfEnabled(items: calendarExportItems())
    }

    /// Stand, nach dem zuletzt geplant wurde: Tonnendienste und Termine samt „Erledigt“/„Diesmal nicht“.
    private func dutyFingerprint() -> [String] {
        allLocations().map { "\($0.id)|\($0.dutyPeriodsJSON)" }.sorted() + ReminderPlanner.replanFingerprint(pickups: plannedPickups())
    }

    /// iCloud liefert in Schüben: Erst nach kurzer Ruhe prüfen und nur bei geändertem Stand neu planen
    /// (Tonnendienst oder „Erledigt“/„Diesmal nicht“ von einem anderen Gerät).
    private func recheckDutyAfterImport() {
        dutyRecheck?.cancel()
        dutyRecheck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, self.dutyFingerprint() != self.plannedDuty else { return }
            await self.refreshAll()
        }
    }

    /// Tage mit Abholung, an denen niemand an einem Standort Dienst hat.
    private func offDutyDayKeys() -> Set<String> {
        let today = Days.today()
        let horizon = Days.add(90, to: today)
        var onDuty = Set<String>(), offDuty = Set<String>()
        for type in allWasteTypes() where type.isActive {
            for date in type.pickupDates(from: today, to: horizon) {
                if type.isOnDuty(on: date) { onDuty.insert(Days.iso(date)) } else { offDuty.insert(Days.iso(date)) }
            }
        }
        return offDuty.subtracting(onDuty)
    }

    // MARK: - Daten

    func allLocations() -> [Location] {
        (try? context.fetch(FetchDescriptor<Location>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func allWasteTypes() -> [WasteType] {
        (try? context.fetch(FetchDescriptor<WasteType>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func allPeople() -> [Person] {
        (try? context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func allCustomEvents() -> [CustomEvent] {
        (try? context.fetch(FetchDescriptor<CustomEvent>(sortBy: [SortDescriptor(\.title)]))) ?? []
    }

    /// Alle Termine im Zeitraum, optional auf einen Standort gefiltert.
    func events(from: Date, to: Date, locationID: UUID? = nil) -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        for type in allWasteTypes() where type.isActive {
            if let locationID, type.location?.id != locationID { continue }
            let duty = type.dutyPeriods
            let quota = quotaLines(for: type)
            for date in type.pickupDates(from: from, to: to) {
                // displaySymbol kann ein eigenes Piktogramm („tt.sack“) sein. Im Schnappschuss für Widgets und Watch
                // landet es in PickupItem.glyphName, symbolName bleibt dort ein SF-Name für ältere Watch-Versionen.
                result.append(CalendarEvent(id: "waste-\(type.id)-\(Days.iso(date))", date: date, kind: .waste, title: type.name, subtitle: type.location?.name ?? "Abholung", colorHex: type.colorHex, symbolName: type.displaySymbol, locationID: type.location?.id, locationName: type.location?.name, years: nil, done: type.isDone(on: date), wasteTypeID: type.id,
                                            note: type.note(on: date), handling: type.handling, notPutOut: type.isNotPutOut(on: date), offDuty: !DutySchedule.isOnDuty(on: date, periods: duty),
                                            quotaLine: quota(date)))
            }
        }
        for person in allPeople() {
            for date in person.annual.occurrences(from: from, to: to) {
                let years = person.annual.years(on: date)
                result.append(CalendarEvent(id: "bday-\(person.id)-\(Days.iso(date))", date: date, kind: .birthday, title: person.name, subtitle: years.map { "wird \($0)" } ?? "Geburtstag", colorHex: person.colorHex, symbolName: "birthday.cake.fill", locationID: nil, locationName: nil, years: years, done: false, personID: person.id))
            }
        }
        for event in allCustomEvents() {
            for date in event.occurrences(from: from, to: to) {
                result.append(CalendarEvent(id: "custom-\(event.id)-\(Days.iso(date))", date: date, kind: .custom, title: event.title, subtitle: (event.timeText.map { "\($0) · " } ?? "") + event.recurrence.label, colorHex: event.colorHex, symbolName: event.symbolName, locationID: nil, locationName: nil, years: nil, done: false, eventID: event.id))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.kind != rhs.kind { return lhs.kind == .waste || (lhs.kind == .birthday && rhs.kind == .custom) }
            return lhs.title < rhs.title
        }
    }

    func upcomingByDay(days: Int, locationID: UUID? = nil) -> [(day: Date, events: [CalendarEvent])] {
        let today = Days.today()
        let all = events(from: today, to: Days.add(days, to: today), locationID: locationID)
        let grouped = Dictionary(grouping: all, by: \.date)
        return grouped.keys.sorted().map { (day: $0, events: grouped[$0] ?? []) }
    }

    // MARK: - Erinnerungen

    private func plannedPickups() -> [PlannedPickup] {
        let today = Days.today()
        let horizon = Days.add(90, to: today)
        let broughtIn = SnapshotStore.broughtInDays()
        let doneTimes = SnapshotStore.doneTimes()
        return allWasteTypes().filter(\.isActive).flatMap { type in
            let duty = type.dutyPeriods
            let quota = quotaLines(for: type)
            return type.pickupDates(from: today, to: horizon).map {
                PlannedPickup(date: $0, name: type.name, locationName: type.location?.name, colorHex: type.colorHex, symbolName: type.displaySymbol,
                              remindersEnabled: type.remindersEnabled && DutySchedule.isOnDuty(on: $0, periods: duty), done: type.isDone(on: $0), broughtIn: broughtIn.contains(Days.iso($0)), note: type.note(on: $0), handling: type.handling, doneAt: doneTimes[Days.iso($0)],
                              skipped: type.isNotPutOut(on: $0), quotaTypeID: type.isCounted ? type.id.uuidString : nil, quotaLine: quota($0))
            }
        }
    }

    private func plannedBirthdays() -> [PlannedBirthday] {
        allPeople().compactMap { person in
            guard let next = person.nextBirthday else { return nil }
            return PlannedBirthday(date: next, name: person.name, years: person.annual.years(on: next), remindDaysBefore: person.remindDaysBefore, remindersEnabled: person.remindersEnabled,
                                   id: person.id.uuidString, phone: person.phone, giftIdeas: person.giftIdeas)
        }
    }

    /// Die nächsten zwei Vorkommen: Ist das heutige schon vorbei, steht die Vorab-Erinnerung fürs nächste trotzdem.
    private func plannedCustomEvents() -> [PlannedCustomEvent] {
        let today = Days.today()
        let done = SettingsKeys.customDoneKeys()
        return allCustomEvents().flatMap { event in
            event.occurrences(from: today, to: Days.add(121, to: today)).prefix(2).map {
                PlannedCustomEvent(date: $0, title: event.title, remindDaysBefore: event.remindDaysBefore, remindersEnabled: event.remindersEnabled,
                                   id: event.id.uuidString, timeMinutes: event.timeMinutes, done: SettingsKeys.isCustomDone(id: event.id, day: $0, keys: done))
            }
        }
    }

    /// Eigenen Termin für ein Vorkommen als erledigt markieren (oder zurücknehmen); die Erinnerungen dafür entfallen.
    func setCustomDone(_ done: Bool, id: UUID, dayKey: String) async {
        SettingsKeys.setCustomDone(done, id: id, dayKey: dayKey)
        if done { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["custom-snooze-\(dayKey)-\(id.uuidString)"]) }
        objectWillChange.send()
        await refreshAll()
    }

    /// Ziel einer angetippten Mitteilung öffnen.
    func open(_ target: NotificationManager.OpenTarget) {
        switch target {
        case .birthdays:
            selectedTab = .birthdays
        case .person(let id):
            selectedTab = .birthdays
            personToOpen = id
        case .event(let id):
            selectedTab = .birthdays
            eventToOpen = id
        }
    }

    // MARK: - Erledigt

    /// Die Müllarten, die ein „Erledigt“ an diesem Tag markiert.
    private func doneCandidates(day: Date) -> [WasteType] {
        allWasteTypes().filter { $0.isActive && !$0.isNotPutOut(on: day) && $0.isOnDuty(on: day) && $0.pickupDates(from: day, to: day).contains(day) }
    }

    /// Braucht „Erledigt“ an diesem Tag das Blatt je Müllart? Nur mit gezählter und weiterer Müllart (sonst ein Tipp wie bisher).
    func needsDoneChoice(day: Date) -> Bool {
        PickupQuota.needsChoice(counted: doneChoiceTypes(day: day).map(\.isCounted))
    }

    /// Müllarten für das Blatt „Was stand draußen?“.
    func doneChoiceTypes(day: Date) -> [WasteType] { doneCandidates(day: day).filter { !$0.isDone(on: day) } }

    /// „Erledigt“ für einen Tag. `leftIn`: ausdrücklich gewählt (Blatt) – diese Müllarten blieben drin. Ohne Angabe gilt
    /// eine in der Mitteilung abgelegte Wahl („Alles raus“ / „Ohne …“), sonst ist es ein pauschaler Tipp (Widget, Watch,
    /// Live-Aktivität, Kurzbefehl): Der markiert wie bisher alles, ein Tag mit gezählter Müllart wird aber nachgefragt.
    func markDone(dayKey: String, leftIn: Set<UUID>? = nil) async {
        // Gegen das leere Notfall-Modell wäre „gespeichert“ wahr, die Markierung aber verbraucht – liegen lassen
        guard !TonneUndTorteApp.storeUnavailable, let day = Days.parse(dayKey) else { return }
        // Zeitpunkt: aus dem Widget/der Watch schon gemerkt (ausstehende Markierung) – sonst jetzt
        let pendingFromWidget = SnapshotStore.doneDays().contains(dayKey)
        SnapshotStore.recordDoneTime(dayKey: dayKey, overwrite: !pendingFromWidget)
        let types = doneCandidates(day: day)
        let choice = leftIn.map { Set($0.map(\.uuidString)) } ?? SnapshotStore.choice(dayKey: dayKey)
        let resolution = PickupQuota.resolve(choice.map { .chosen(left: $0) } ?? .blanket, types: types.map { (id: $0.id.uuidString, counted: $0.isCounted) })
        for type in types {
            let id = type.id.uuidString
            if resolution.notOut.contains(id) {
                type.setNotPutOut(true, on: day)
            } else if resolution.out.contains(id), !type.isDone(on: day) {
                // Schon Erledigtes bleibt, wie es ist: Ein zweiter Durchlauf (Mitteilung + ausstehende Markierung) macht
                // eine ausdrückliche Wahl nicht nachträglich pauschal
                type.markDone(on: day)
                if resolution.bulk.contains(id) { type.markBulk(on: day) } else { type.clearBulk(on: day) }
            } else if choice != nil {
                type.clearBulk(on: day)
            }
        }
        // Nicht gespeichert: Markierung aus Widget/Watch liegen lassen, beim nächsten Mal erneut versuchen
        guard save() else { return }
        notifications.cancelWasteReminders(dayKey: dayKey)
        SnapshotStore.clearDone(dayKey: dayKey)
        SnapshotStore.clearChoice(dayKey: dayKey)
        await refreshAll()
    }

    /// „Erledigt“ zurücknehmen, wenn man versehentlich getippt hat. Die Erinnerungen werden neu geplant.
    func markUndone(dayKey: String) async {
        guard !TonneUndTorteApp.storeUnavailable, let day = Days.parse(dayKey) else { return }
        for type in allWasteTypes() where type.isDone(on: day) {
            type.unmarkDone(on: day)
            type.clearBulk(on: day)
        }
        guard save() else { return }
        SnapshotStore.clearDoneTime(dayKey: dayKey)
        SnapshotStore.clearUndo(dayKey: dayKey)
        SnapshotStore.clearDone(dayKey: dayKey)
        await refreshAll()
    }

    // MARK: - Leerungs-Statistik

    /// Ein Termin einer gezählten Müllart (Nachtragen-Karte, Statistik).
    struct QuotaItem: Identifiable {
        let type: WasteType
        let date: Date
        let bulk: Bool
        var id: String { "\(type.id)-\(Days.iso(date))" }
    }

    /// Zustand eines Termins setzen (raus, nicht raus, offen) – auch an Tagen, an denen jemand anderes dran ist.
    func setPickupMark(_ mark: PickupMark, wasteTypeID: UUID, day: Date) async {
        guard let type = allWasteTypes().first(where: { $0.id == wasteTypeID }) else { return }
        type.setPickupMark(mark, on: day)
        guard save() else { return }
        objectWillChange.send()
        await refreshAll()
    }

    /// Nachtragen-Karte: offene oder pauschal bestätigte Termine gezählter Müllarten aus den letzten 30 Tagen.
    func catchUpItems(locationID: UUID? = nil) -> [QuotaItem] {
        let today = Days.today()
        return allWasteTypes().filter { $0.isActive && $0.isCounted && (locationID == nil || $0.location?.id == locationID) }
            .flatMap { type in type.catchUpEntries(today: today).map { QuotaItem(type: type, date: $0.date, bulk: $0.bulkConfirmed) } }
            .sorted { ($0.date, $0.type.sortOrder) < ($1.date, $1.type.sortOrder) }
    }

    /// Alle offenen oder pauschal bestätigten Termine des laufenden Zeitraums (Statistik „3 Termine offen – nachtragen“).
    func openItems(locationID: UUID? = nil) -> [QuotaItem] {
        let today = Days.today()
        // Ohne die mit „Kein Kontingent“ ausgeblendeten – sonst listet das Blatt mehr, als der Knopf zählt
        return allWasteTypes().filter { $0.isActive && !$0.hidesInStatistics && (locationID == nil || $0.location?.id == locationID) }
            .flatMap { type in
                type.quotaSummary(period: type.quotaPeriod(containing: today), today: today).entries
                    .filter { !$0.upcoming && !$0.coveredByBaseline && ($0.mark == .open || $0.bulkConfirmed) }
                    .map { QuotaItem(type: type, date: $0.date, bulk: $0.bulkConfirmed) }
            }
            .sorted { ($0.date, $0.type.sortOrder) > ($1.date, $1.type.sortOrder) }
    }

    /// „noch 5 von 12 frei“ für eine gezählte Müllart (laufender Zeitraum), sonst nil.
    func quotaLine(for type: WasteType) -> String? {
        guard type.isCounted else { return nil }
        return PickupQuota.freeLine(type.quotaSummary(period: type.quotaPeriod(containing: Days.today())))
    }

    /// Dieselbe Zeile je Abholtag, im Zeitraum des Abholtags: Am 30.12. mit 12 von 12 genutzt
    /// zeigt die Abholung am 2.1. „12 von 12 frei“, nicht „alle genutzt“. Je Zeitraum nur einmal gerechnet.
    func quotaLines(for type: WasteType) -> (Date) -> String? {
        guard type.isCounted else { return { _ in nil } }
        return PickupQuota.freeLines(anchor: type.quotaStart, today: Days.today()) { type.quotaInput(period: $0) }
    }

    /// Statistik als CSV: laufender und vorheriger Zeitraum aller (bzw. eines Standorts) Müllarten, vergangene Termine.
    func statisticsCSV(locationID: UUID? = nil) -> String {
        let today = Days.today()
        var rows: [PickupQuota.CSVRow] = []
        for type in allWasteTypes() where type.isActive && !type.hidesInStatistics && (locationID == nil || type.location?.id == locationID) {
            let current = type.quotaPeriod(containing: today)
            for period in [PickupQuota.previous(current, anchor: type.quotaStart), current] {
                for entry in type.quotaSummary(period: period, today: today).entries where !entry.upcoming {
                    rows.append(PickupQuota.CSVRow(date: entry.date, location: type.location?.name ?? "", wasteType: type.name, mark: entry.mark, isExtra: entry.isExtra))
                }
            }
        }
        return PickupQuota.csv(rows)
    }

    // MARK: - Diesmal nicht rausstellen

    /// Eine Müllart an diesem Tag diesmal nicht rausstellen (oder es zurücknehmen). Die Erinnerungen werden neu geplant –
    /// sie nennen danach nur noch, was wirklich rausgeht.
    func setNotPutOut(_ notOut: Bool, wasteTypeID: UUID, dayKey: String) async {
        guard let day = Days.parse(dayKey), let type = allWasteTypes().first(where: { $0.id == wasteTypeID }) else { return }
        type.setNotPutOut(notOut, on: day)
        guard save() else { return }
        // Neu planen ersetzt die Erinnerungen des Tages durch Fassungen ohne diese Müllart (oder streicht sie ganz)
        objectWillChange.send()
        await refreshAll()
    }

    /// Aus der Mitteilung: alle Tonnen, die an dem Tag noch offen sind, bleiben diesmal drin.
    /// Hinbringen (Schadstoffmobil) ist nicht „rausstellen“ – das bleibt stehen, samt Morgen-Erinnerung.
    func skipOpen(dayKey: String) async {
        guard !TonneUndTorteApp.storeUnavailable, let day = Days.parse(dayKey) else { return }
        for type in allWasteTypes() where type.isActive && type.handling != .bringTo && !type.isDone(on: day) && type.isOnDuty(on: day) && type.pickupDates(from: day, to: day).contains(day) {
            type.setNotPutOut(true, on: day)
        }
        // Nicht gespeichert: Markierung liegen lassen, beim nächsten Mal erneut versuchen
        guard save() else { return }
        SnapshotStore.clearSkipped(dayKey: dayKey)
        objectWillChange.send()
        await refreshAll()
    }

    /// „Erledigt“-Markierungen (und Rücknahmen) aus Widget/Live-Aktivität/Watch in die Datenbank übernehmen.
    func applyPendingDoneMarkers() async {
        // Ohne echte Datenbank liegen lassen – sonst wären die Häkchen aus Widget/Watch verbraucht, aber nicht gespeichert
        guard !TonneUndTorteApp.storeUnavailable else { return }
        let undo = SnapshotStore.undoDays()
        for key in undo { await markUndone(dayKey: key) }
        let pending = SnapshotStore.doneDays()
        for key in pending { await markDone(dayKey: key) }
        for key in SnapshotStore.skipDays() { await skipOpen(dayKey: key) }
    }

    // MARK: - Abgleich

    func sync(location: Location) async throws -> SyncService.Result {
        isSyncing = true
        defer { isSyncing = false }
        let result = try await SyncService.sync(location: location, context: context)
        if !result.changes.isEmpty {
            recentChanges = result.changes
            notifyChanges(result.changes, location: location)
        }
        await refreshAll()
        return result
    }

    /// Wöchentlicher Abgleich aller Standorte mit Online-Quelle (force = sofort).
    @discardableResult
    func syncAll(force: Bool) async -> [String] {
        guard !TonneUndTorteApp.storeUnavailable else { return [] }
        var messages: [String] = []
        for location in allLocations() where location.canSync {
            // Kurzer Vorlauf (mitlaufendes Fenster wie SBAZV) → alle 2 Tage, sonst wöchentlich
            let lastKnown = SyncRhythm.lastKnownPickup(latestPerType: (location.wasteTypes ?? []).filter { $0.isActive && $0.sourceKey != nil }.compactMap { $0.explicitDates.max() })
            let due = force || SyncRhythm.isDue(lastSync: location.lastSyncAt, lastKnownPickup: lastKnown)
            guard due else { continue }
            let name = location.name
            do {
                let result = try await sync(location: location)
                messages.append("\(name): \(L10n.dates(result.importedCount))")
            } catch {
                // Während des Abrufs gelöscht (z. B. per iCloud von einem anderen Gerät): nicht mehr anfassen
                if location.modelContext != nil, !location.isDeleted {
                    location.lastSyncMessage = L10n.t("Abgleich fehlgeschlagen: \(error.localizedDescription)", "Sync failed: \(error.localizedDescription)")
                    save()
                }
                messages.append("\(name): \(error.localizedDescription)")
            }
        }
        return messages
    }

    private func notifyChanges(_ changes: [String], location: Location) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t("Termine geändert: \(location.name)", "Dates changed: \(location.name)")
        content.body = changes.prefix(3).joined(separator: "\n")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "changes-\(location.id)", content: content, trigger: nil))
    }

    // MARK: - Widget-Snapshot & Statistik

    func buildSnapshot() -> WidgetSnapshot {
        let locations = allLocations().map { WidgetSnapshot.Location(id: $0.id.uuidString, name: $0.name, symbolName: $0.symbolName, colorHex: $0.colorHex) }
        let days = upcomingByDay(days: 60)
        let broughtIn = SnapshotStore.broughtInDays()
        let doneTimes = SnapshotStore.doneTimes()
        let pickupDays: [WidgetSnapshot.PickupDay] = days.compactMap { entry in
            // Diesmal nicht rausgestellt oder nicht zuständig: gehört nicht ins Widget, auf die Watch oder in die Live-Aktivität
            let items = entry.events.filter { $0.kind == .waste && !$0.notPutOut && !$0.offDuty }
            guard !items.isEmpty else { return nil }
            let key = Days.iso(entry.day), done = items.allSatisfy(\.done)
            return WidgetSnapshot.PickupDay(date: entry.day, items: items.map { WidgetSnapshot.PickupItem(name: $0.title, symbolName: $0.symbolName, colorHex: $0.colorHex, locationID: $0.locationID?.uuidString, locationName: $0.locationName, dropOff: $0.handling == .bringTo) },
                                            done: done, broughtIn: broughtIn.contains(key), doneAt: done ? doneTimes[key] : nil)
        }
        let birthdays = upcomingByDay(days: 366).flatMap { $0.events }.filter { $0.kind == .birthday }.prefix(10).map {
            WidgetSnapshot.BirthdayItem(date: $0.date, name: $0.title, years: $0.years, colorHex: $0.colorHex, initials: NameText.initials($0.title))
        }
        let stats = statistics()
        let settings = SettingsKeys.reminderSettings()
        return WidgetSnapshot(generatedAt: Date(), locations: locations, pickupDays: pickupDays, birthdays: Array(birthdays), missedCountThisYear: stats.total - stats.confirmed, doneCountThisYear: stats.confirmed,
                              bringInEnabled: settings.bringInEnabled, bringInFromMinutes: min(PickupTiming.bringInHintMinutes, settings.bringInMinutes))
    }

    func statistics() -> (total: Int, confirmed: Int) {
        let year = Calendar.current.component(.year, from: Date())
        guard let start = Days.make(year: year, month: 1, day: 1) else { return (0, 0) }
        let today = Days.today()
        var total = 0
        var confirmed = 0
        for type in allWasteTypes() where type.isActive {
            // Bewusst nicht rausgestellt oder nicht zuständig zählt weder als erledigt noch als verpasst
            let duty = type.dutyPeriods
            let dates = type.pickupDates(from: start, to: today).filter { !type.isNotPutOut(on: $0) && DutySchedule.isOnDuty(on: $0, periods: duty) }
            total += dates.count
            confirmed += dates.filter { type.isDone(on: $0) }.count
        }
        return (total, confirmed)
    }

    // MARK: - Export

    /// Termine für die Kalender-App. `applyingSyncOptions: false` liefert alles (für die ICS-Datei).
    func calendarExportItems(applyingSyncOptions: Bool = true) -> [CalendarExport.Item] {
        let settings = SettingsKeys.reminderSettings()
        let today = Days.today()
        var alarms: [Int] = []
        if settings.eveningEnabled { alarms.append(settings.eveningMinutes - 1440) }
        if settings.morningEnabled { alarms.append(settings.morningMinutes) }
        let multi = allLocations().count > 1
        let options = CalendarSyncOptions.current
        let fromContacts = Set(allPeople().filter { $0.contactIdentifier != nil }.map(\.id))
        var customTimes: [String: Int] = [:]
        for event in allCustomEvents() {
            guard let time = event.timeMinutes else { continue }
            for date in event.occurrences(from: today, to: Days.add(400, to: today)) { customTimes["custom-\(event.id)-\(Days.iso(date))"] = time }
        }
        let wanted = events(from: today, to: Days.add(400, to: today)).filter { event in
            guard applyingSyncOptions else { return true }
            switch event.kind {
            case .waste: return options.includeWaste
            case .custom: return options.includeCustom
            case .birthday:
                switch options.birthdays {
                case .none: return false
                case .all: return true
                case .manualOnly: return !(event.personID.map(fromContacts.contains) ?? false)
                }
            }
        }
        return wanted.map { event in
            switch event.kind {
            case .waste:
                return CalendarExport.Item(date: event.date, title: "🗑️ \(event.title)\(multi && event.locationName != nil ? " (\(event.locationName!))" : "")", notes: L10n.t("Abholung", "Collection"), alarmMinutesFromMidnight: event.offDuty ? [] : alarms)
            case .birthday:
                return CalendarExport.Item(date: event.date, title: "🎂 \(event.title)\(event.years.map { " (\($0))" } ?? "")", notes: nil, alarmMinutesFromMidnight: [settings.birthdayMinutes])
            case .custom:
                // Mit Uhrzeit ein einstündiger Termin, Alarm mit dem eingestellten Vorlauf (darf auf den Vortag fallen)
                let time = customTimes[event.id]
                let alarm = time.map { $0 - settings.customLeadMinutes } ?? settings.customMinutes
                return CalendarExport.Item(date: event.date, title: "📌 \(event.title)", notes: nil, alarmMinutesFromMidnight: [alarm], timeMinutes: time)
            }
        }
    }

    /// Alle eingetragenen Termine als ICS-Datei (zum Teilen).
    func feedText() -> String {
        let events = calendarExportItems(applyingSyncOptions: false).map { item in
            ICS.FeedEvent(uid: "\(Days.iso(item.date))-\(item.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF })@tonneundtorte", date: item.date, summary: item.title, description: item.notes, alarmMinutes: item.alarmMinutesFromMidnight, timeMinutes: item.timeMinutes)
        }
        return ICS.build(name: "Tonne & Torte", events: events)
    }

    // MARK: - Hintergrund

    private static var backgroundTaskRegistered = false

    /// Synchron in `App.init`: BGTaskScheduler verlangt die Anmeldung vor dem Ende des App-Starts – und nur EINMAL je Prozess.
    static func registerBackgroundTask() {
        guard !backgroundTaskRegistered else { return }
        backgroundTaskRegistered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: SettingsKeys.backgroundRefreshID, using: nil) { task in
            let work = Task { @MainActor in
                // Beim Hintergrundstart ist die Datenbank evtl. noch nicht offen: darauf warten, nie ohne Daten abgleichen
                let model = await ModelHolder.shared.readyModel()
                guard !Task.isCancelled else { return }   // Zeit schon abgelaufen, bevor die Datenbank offen war
                guard let model else {
                    // Weiterhin nicht lesbar (vor dem ersten Entsperren): nichts erledigt, später erneut
                    task.setTaskCompleted(success: false)
                    AppModel.scheduleBackgroundRefresh()
                    return
                }
                await model.syncAll(force: false)
                await model.refreshAll()
                guard !Task.isCancelled else { return }
                task.setTaskCompleted(success: true)
                AppModel.scheduleBackgroundRefresh()
            }
            // iOS gibt nur rund 30 Sekunden: bei Zeitablauf sauber abbrechen, statt die App beenden zu lassen
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
                Task { @MainActor in AppModel.scheduleBackgroundRefresh() }
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: SettingsKeys.backgroundRefreshID)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Speichert; bei einem Fehler Änderungen verwerfen und eine Meldung zeigen (RootView). `false` = nicht gespeichert –
    /// dann bleibt ein Bearbeiten-Fenster offen, statt so zu tun, als wäre alles gesichert.
    @discardableResult
    func save() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            lastError = L10n.t("Konnte nicht gespeichert werden: \(error.localizedDescription)", "Could not be saved: \(error.localizedDescription)")
            return false
        }
    }

    /// Löscht ein Objekt erst, nachdem die Detailansicht geschlossen wurde (sonst greift SwiftUI auf ein
    /// ungültiges Model zu).
    func deleteLater(_ object: any PersistentModel) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.context.delete(object)
            self.save()
            await self.refreshAll()
        }
    }
}
