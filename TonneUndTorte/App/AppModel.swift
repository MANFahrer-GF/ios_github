import Foundation
import SwiftData
import SwiftUI
import BackgroundTasks
import UserNotifications
import TonneCore

/// Einstellungs-Schlüssel (UserDefaults) – von Views per @AppStorage und vom Modell genutzt.
enum SettingsKeys {
    static let onboardingDone = "app.onboardingDone"
    static let eveningEnabled = "reminder.evening.enabled"
    static let eveningMinutes = "reminder.evening.minutes"
    static let morningEnabled = "reminder.morning.enabled"
    static let morningMinutes = "reminder.morning.minutes"
    static let escalationEnabled = "reminder.escalation.enabled"
    static let escalationMinutes = "reminder.escalation.minutes"
    static let birthdayMinutes = "reminder.birthday.minutes"
    static let customMinutes = "reminder.custom.minutes"
    static let locationFilter = "filter.locationID"
    static let liveActivities = "feature.liveActivities"
    static let backgroundRefreshID = "de.manfahrer.TonneUndTorte.refresh"

    static func reminderSettings(_ defaults: UserDefaults = .standard) -> ReminderSettings {
        var settings = ReminderSettings()
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key) }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        settings.eveningEnabled = bool(eveningEnabled, true)
        settings.eveningMinutes = int(eveningMinutes, 19 * 60)
        settings.morningEnabled = bool(morningEnabled, false)
        settings.morningMinutes = int(morningMinutes, 7 * 60)
        settings.escalationEnabled = bool(escalationEnabled, true)
        settings.escalationMinutes = int(escalationMinutes, 21 * 60)
        settings.birthdayMinutes = int(birthdayMinutes, 9 * 60)
        settings.customMinutes = int(customMinutes, 9 * 60)
        return settings
    }
}

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
    @Published var onboardingDone: Bool = UserDefaults.standard.bool(forKey: SettingsKeys.onboardingDone) {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: SettingsKeys.onboardingDone) }
    }

    private let notifications = NotificationManager.shared
    private var started = false

    init(container: ModelContainer) {
        self.container = container
        // Muss vor dem Ende des App-Starts passieren, sonst wirft BGTaskScheduler eine Exception.
        registerBackgroundTask()
        notifications.onPickupDone = { [weak self] dayKey in
            Task { await self?.markDone(dayKey: dayKey) }
        }
        // Apple Watch: Snapshot hinschicken, „Erledigt“ entgegennehmen
        WatchSync.shared.activate()
        WatchSync.shared.onUndoReceived = { [weak self] dayKey in
            Task { await self?.markUndone(dayKey: dayKey) }
        }
        WatchSync.shared.onDoneReceived = { [weak self] dayKey in
            Task { await self?.markDone(dayKey: dayKey) }
        }
        NotificationCenter.default.addObserver(forName: WatchSync.updatedNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refreshAll() }
        }
        NotificationCenter.default.addObserver(forName: SnapshotStore.notificationName, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.applyPendingDoneMarkers() }
        }
    }

    // MARK: - Lebenszyklus

    func start() async {
        guard !started else { return }
        started = true
        await notifications.refreshStatus()
        await becameActive()
    }

    func becameActive() async {
        await applyPendingDoneMarkers()
        _ = await syncAll(force: false)
        await refreshAll()
    }

    /// Erinnerungen, Widget-Snapshot und Live-Aktivität neu aufbauen.
    func refreshAll() async {
        let snapshot = buildSnapshot()
        SnapshotStore.save(snapshot)
        WatchSync.shared.send(snapshot)
        let plan = ReminderPlanner.plan(pickups: plannedPickups(), birthdays: plannedBirthdays(), customEvents: plannedCustomEvents(), settings: SettingsKeys.reminderSettings())
        await notifications.apply(plan)
        if UserDefaults.standard.object(forKey: SettingsKeys.liveActivities) == nil || UserDefaults.standard.bool(forKey: SettingsKeys.liveActivities) {
            await LiveActivityManager.refresh(with: snapshot)
        } else {
            await LiveActivityManager.endAll()
        }
        await CalendarExport.autoSyncIfEnabled(items: calendarExportItems())
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
            for date in type.pickupDates(from: from, to: to) {
                result.append(CalendarEvent(id: "waste-\(type.id)-\(Days.iso(date))", date: date, kind: .waste, title: type.name, subtitle: type.location?.name ?? "Abholung", colorHex: type.colorHex, symbolName: type.symbolName, locationID: type.location?.id, locationName: type.location?.name, years: nil, done: type.isDone(on: date)))
            }
        }
        for person in allPeople() {
            for date in person.annual.occurrences(from: from, to: to) {
                let years = person.annual.years(on: date)
                result.append(CalendarEvent(id: "bday-\(person.id)-\(Days.iso(date))", date: date, kind: .birthday, title: person.name, subtitle: years.map { "wird \($0)" } ?? "Geburtstag", colorHex: person.colorHex, symbolName: "birthday.cake.fill", locationID: nil, locationName: nil, years: years, done: false))
            }
        }
        for event in allCustomEvents() {
            for date in event.occurrences(from: from, to: to) {
                result.append(CalendarEvent(id: "custom-\(event.id)-\(Days.iso(date))", date: date, kind: .custom, title: event.title, subtitle: event.recurrence.label, colorHex: event.colorHex, symbolName: event.symbolName, locationID: nil, locationName: nil, years: nil, done: false))
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
        return allWasteTypes().filter(\.isActive).flatMap { type in
            type.pickupDates(from: today, to: horizon).map {
                PlannedPickup(date: $0, name: type.name, locationName: type.location?.name, colorHex: type.colorHex, symbolName: type.symbolName, remindersEnabled: type.remindersEnabled, done: type.isDone(on: $0))
            }
        }
    }

    private func plannedBirthdays() -> [PlannedBirthday] {
        allPeople().compactMap { person in
            guard let next = person.nextBirthday else { return nil }
            return PlannedBirthday(date: next, name: person.name, years: person.annual.years(on: next), remindDaysBefore: person.remindDaysBefore, remindersEnabled: person.remindersEnabled)
        }
    }

    private func plannedCustomEvents() -> [PlannedCustomEvent] {
        allCustomEvents().compactMap { event in
            guard let next = event.nextOccurrence else { return nil }
            return PlannedCustomEvent(date: next, title: event.title, remindDaysBefore: event.remindDaysBefore, remindersEnabled: event.remindersEnabled)
        }
    }

    // MARK: - Erledigt

    func markDone(dayKey: String) async {
        guard let day = Days.parse(dayKey) else { return }
        for type in allWasteTypes() where type.isActive && type.pickupDates(from: day, to: day).contains(day) {
            type.markDone(on: day)
        }
        try? context.save()
        notifications.cancelWasteReminders(dayKey: dayKey)
        SnapshotStore.clearDone(dayKey: dayKey)
        await refreshAll()
    }

    /// „Erledigt“ zurücknehmen, wenn man versehentlich getippt hat. Die Erinnerungen werden neu geplant.
    func markUndone(dayKey: String) async {
        guard let day = Days.parse(dayKey) else { return }
        for type in allWasteTypes() where type.isDone(on: day) {
            type.unmarkDone(on: day)
        }
        try? context.save()
        SnapshotStore.clearUndo(dayKey: dayKey)
        SnapshotStore.clearDone(dayKey: dayKey)
        await refreshAll()
    }

    /// „Erledigt“-Markierungen (und Rücknahmen) aus Widget/Live-Aktivität/Watch in die Datenbank übernehmen.
    func applyPendingDoneMarkers() async {
        let undo = SnapshotStore.undoDays()
        for key in undo { await markUndone(dayKey: key) }
        let pending = SnapshotStore.doneDays()
        for key in pending { await markDone(dayKey: key) }
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
        var messages: [String] = []
        for location in allLocations() where location.canSync {
            let due = force || location.lastSyncAt.map { Date().timeIntervalSince($0) > 7 * 24 * 3600 } ?? true
            guard due else { continue }
            do {
                let result = try await sync(location: location)
                messages.append("\(location.name): \(result.importedCount) Termine")
            } catch {
                location.lastSyncMessage = "Abgleich fehlgeschlagen: \(error.localizedDescription)"
                messages.append("\(location.name): \(error.localizedDescription)")
            }
        }
        return messages
    }

    private func notifyChanges(_ changes: [String], location: Location) {
        let content = UNMutableNotificationContent()
        content.title = "Termine geändert: \(location.name)"
        content.body = changes.prefix(3).joined(separator: "\n")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "changes-\(location.id)", content: content, trigger: nil))
    }

    // MARK: - Widget-Snapshot & Statistik

    func buildSnapshot() -> WidgetSnapshot {
        let locations = allLocations().map { WidgetSnapshot.Location(id: $0.id.uuidString, name: $0.name, symbolName: $0.symbolName, colorHex: $0.colorHex) }
        let days = upcomingByDay(days: 60)
        let pickupDays: [WidgetSnapshot.PickupDay] = days.compactMap { entry in
            let items = entry.events.filter { $0.kind == .waste }
            guard !items.isEmpty else { return nil }
            return WidgetSnapshot.PickupDay(date: entry.day, items: items.map { WidgetSnapshot.PickupItem(name: $0.title, symbolName: $0.symbolName, colorHex: $0.colorHex, locationID: $0.locationID?.uuidString, locationName: $0.locationName) }, done: items.allSatisfy(\.done))
        }
        let birthdays = upcomingByDay(days: 366).flatMap { $0.events }.filter { $0.kind == .birthday }.prefix(10).map {
            WidgetSnapshot.BirthdayItem(date: $0.date, name: $0.title, years: $0.years, colorHex: $0.colorHex, initials: NameText.initials($0.title))
        }
        let stats = statistics()
        return WidgetSnapshot(generatedAt: Date(), locations: locations, pickupDays: pickupDays, birthdays: Array(birthdays), missedCountThisYear: stats.total - stats.confirmed, doneCountThisYear: stats.confirmed)
    }

    func statistics() -> (total: Int, confirmed: Int) {
        let year = Calendar.current.component(.year, from: Date())
        guard let start = Days.make(year: year, month: 1, day: 1) else { return (0, 0) }
        let today = Days.today()
        var total = 0
        var confirmed = 0
        for type in allWasteTypes() where type.isActive {
            let dates = type.pickupDates(from: start, to: today)
            total += dates.count
            confirmed += dates.filter { type.isDone(on: $0) }.count
        }
        return (total, confirmed)
    }

    // MARK: - Export

    func calendarExportItems() -> [CalendarExport.Item] {
        let settings = SettingsKeys.reminderSettings()
        let today = Days.today()
        var alarms: [Int] = []
        if settings.eveningEnabled { alarms.append(settings.eveningMinutes - 1440) }
        if settings.morningEnabled { alarms.append(settings.morningMinutes) }
        let multi = allLocations().count > 1
        return events(from: today, to: Days.add(400, to: today)).map { event in
            switch event.kind {
            case .waste:
                return CalendarExport.Item(date: event.date, title: "🗑️ \(event.title)\(multi && event.locationName != nil ? " (\(event.locationName!))" : "")", notes: "Abholung", alarmMinutesFromMidnight: alarms)
            case .birthday:
                return CalendarExport.Item(date: event.date, title: "🎂 \(event.title)\(event.years.map { " (\($0))" } ?? "")", notes: nil, alarmMinutesFromMidnight: [settings.birthdayMinutes])
            case .custom:
                return CalendarExport.Item(date: event.date, title: "📌 \(event.title)", notes: nil, alarmMinutesFromMidnight: [settings.customMinutes])
            }
        }
    }

    // MARK: - Hintergrund

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: SettingsKeys.backgroundRefreshID, using: nil) { [weak self] task in
            guard let self else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in
                await self.syncAll(force: false)
                await self.refreshAll()
                task.setTaskCompleted(success: true)
                self.scheduleBackgroundRefresh()
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: SettingsKeys.backgroundRefreshID)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Löscht ein Objekt erst, nachdem die Detailansicht geschlossen wurde (sonst greift SwiftUI auf ein
    /// ungültiges Model zu).
    func deleteLater(_ object: any PersistentModel) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.context.delete(object)
            try? self.context.save()
            await self.refreshAll()
        }
    }

    func handle(url: URL) {
        // tonne://done?day=2026-10-08 (z. B. aus Kurzbefehlen)
        guard url.scheme == "tonne", url.host == "done" else { return }
        if let day = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "day" })?.value {
            Task { await self.markDone(dayKey: day) }
        }
    }
}
