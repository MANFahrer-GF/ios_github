import Foundation
import TonneCore
#if os(iOS)
import UserNotifications
#endif
#if os(iOS) && canImport(AlarmKit)
import AlarmKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Liest und schreibt den Widget-Snapshot sowie „Erledigt“-Markierungen in der App-Gruppe.
/// Wird von App, Widget und App Intents gemeinsam genutzt.
enum SnapshotStore {
    static let appGroup = WidgetSnapshot.appGroup
    static let doneKey = "pickup.doneDays"
    static let notificationName = Notification.Name("de.manfahrer.TonneUndTorte.snapshotChanged")

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Eine einzige Instanz: Die Schrift-Einstellung schreibt hier, die App-Wurzel liest hier (beide per `@AppStorage`).
    /// Mit je einer neuen Instanz pro Zugriff bekam die Wurzel den Wechsel nicht mit – Schrift und Vorschau änderten sich
    /// erst nach hartem Beenden der App (Thomas 20.11.2026).
    static let defaults: UserDefaults =
        isUITestRun ? (UserDefaults(suiteName: uiTestSuite) ?? .standard) : (UserDefaults(suiteName: appGroup) ?? .standard)

    private static var fileURL: URL? {
        isUITestRun ? nil : containerURL?.appendingPathComponent(WidgetSnapshot.fileName)
    }

    /// Oberflächen-Test (nur Entwickler-Build, wie `TonneUndTorteApp.isUITesting`): Markierungen in eigener Ablage, kein
    /// Snapshot, keine Erinnerungen oder Wecker anfassen. Sonst löschte der Test echte Markierungen und Erinnerungen, und ein
    /// abgebrochener Test hinterließ „morgen erledigt“ für den nächsten normalen Start (Prüfbefund 3 zu Teil 13).
    static var isUITestRun: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTesting") || ProcessInfo.processInfo.environment["TONNE_UITESTING"] == "1"
        #else
        false
        #endif
    }
    static let uiTestSuite = "de.manfahrer.TonneUndTorte.uitests.markers"

    #if os(iOS)
    private static func removeNotifications(_ ids: [String]) {
        guard !isUITestRun else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
    #endif

    // MARK: - Sperre über Prozesse hinweg

    /// App, Widget und Watch-Bridge ändern dieselben Markierungen. Ohne Sperre gewinnt bei zwei gleichzeitigen Tipps
    /// der zuletzt Schreibende und die andere Markierung geht verloren – darum Lesen-Ändern-Schreiben unter einer Datei-Sperre.
    private static let processLock = NSRecursiveLock()
    nonisolated(unsafe) private static var lockDepth = 0

    @discardableResult
    static func locked<T>(_ body: () -> T) -> T {
        processLock.lock(); defer { processLock.unlock() }
        lockDepth += 1
        var fd: Int32 = -1
        if lockDepth == 1, let url = containerURL?.appendingPathComponent(".snapshot.lock") {
            fd = open(url.path, O_CREAT | O_RDWR, 0o644)
            if fd >= 0 { flock(fd, LOCK_EX) }
        }
        defer {
            lockDepth -= 1
            if fd >= 0 { flock(fd, LOCK_UN); close(fd) }
        }
        return body()
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL, let data = try? snapshot.encoded() else { return }
        locked { _ = try? data.write(to: url, options: .atomic) }
        reloadWidgets()
    }

    // MARK: - Heimat-Zeitzone (`HomeTimeZone`)

    static let homeTimeZoneKey = "app.homeTimeZone"

    /// An jedem Prozessstart (App, Widget, Watch): Heimat-Zeitzone bestimmen und als Standard setzen. Danach rechnen
    /// `Calendar.current`, Formatierer und Datumsauswahl in ihr – gespeicherte Tage bleiben auf Reisen ihr Tag.
    /// Die Watch übernimmt die Heimat des iPhones aus dem Schnappschuss (App-Gruppen reichen nicht bis zur Watch).
    static func applyHomeTimeZone() {
        let snapshot = load()
        #if os(watchOS)
        let stored = snapshot?.homeTimeZone ?? defaults.string(forKey: homeTimeZoneKey)
        #else
        let stored = defaults.string(forKey: homeTimeZoneKey)
        #endif
        // Ein Schnappschuss vom letzten Lauf zeigt eine bestehende Installation (Daten in der damaligen Gerätezone)
        let home = HomeTimeZone.resolve(stored: stored, device: NSTimeZone.system.identifier, existingInstall: snapshot != nil)
        if home != defaults.string(forKey: homeTimeZoneKey) { defaults.set(home, forKey: homeTimeZoneKey) }
        if let zone = TimeZone(identifier: home) { NSTimeZone.default = zone }
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - „Erledigt“-Markierungen (Tag als ISO-String)

    static func doneDays() -> Set<String> {
        Set(defaults.stringArray(forKey: doneKey) ?? [])
    }

    /// `dayKey`: Tag oder Tag eines Standorts (`DoneKey`) – mit Standort wird nur dieser erledigt.
    static func markDone(dayKey key: String, at date: Date = Date()) {
        locked {
            let (dayKey, locationID) = DoneKey.split(key)
            var pickupDay = load()?.pickupDays.first { Days.iso($0.date) == dayKey }
            reconcilePending(.done(key), day: pickupDay)
            // Neuer Zeitstempel, außer der Tag war schon erledigt (sonst gälte eine alte Markierung)
            let at = recordDoneTime(dayKey: dayKey, at: date, overwrite: !(pickupDay?.done ?? false))
            pickupDay?.setDone(true, locationID: locationID)
            if var snapshot = load() {
                snapshot.pickupDays = snapshot.pickupDays.map { day in
                    var copy = day
                    // Zeitstempel auch bei einem Standort: Das Standort-Widget hält den Tag dann zum Zurücknehmen stehen
                    if Days.iso(day.date) == dayKey { copy.setDone(true, locationID: locationID); copy.doneAt = at }
                    return copy
                }
                save(snapshot)
            }
            #if os(iOS)
            // Erinnerungen für diesen Tag sofort entfernen – auch wenn die App gerade nicht läuft. Nur wenn der ganze Tag
            // erledigt ist: Ein anderer, noch offener Standort behält seine Erinnerung (die App plant beim Öffnen neu).
            // Ist am Vorabend etwas hinzubringen (Schadstoffmobil), bleibt die Morgen-Erinnerung.
            if locationID == nil || pickupDay?.done == true {
                let keepMorning = pickupDay.map { !PickupWording(day: $0).bringNames.isEmpty && date < Calendar.current.startOfDay(for: $0.date) } ?? false
                let ids = ["evening", "escalation", "snooze"].map { "waste-\($0)-\(dayKey)" } + (keepMorning ? [] : ["waste-morning-\(dayKey)"])
                removeNotifications(ids)
                cancelAlarm(dayKey: dayKey)
            }
            #endif
            DispatchQueue.main.async { NotificationCenter.default.post(name: notificationName, object: nil) }
        }
    }

    /// Wecker am Vorabend dieses Tages entfernen (AlarmKit, ab iOS 26) – „Erledigt“ läuft oft ohne App-Modell im Hintergrund.
    static func cancelAlarm(dayKey: String) {
        guard !isUITestRun else { return }
        #if os(iOS) && canImport(AlarmKit)
        if #available(iOS 26.0, *), let id = PlannedAlarm.id(dayKey: dayKey) { try? AlarmManager.shared.cancel(id: id) }
        #endif
    }

    /// Ausstehende Erledigt-/Rücknahme-Schlüssel nach einer Handlung widerspruchsfrei ablegen (`DoneKey.reconcile`).
    private static func reconcilePending(_ action: DoneKey.Action, day: WidgetSnapshot.PickupDay?) {
        let locations = Array(Set(day?.items.compactMap(\.locationID) ?? []))
        let result = DoneKey.reconcile(done: doneDays(), undo: undoDays(), action, locations: locations)
        defaults.set(Array(result.done).sorted(), forKey: doneKey)
        defaults.set(Array(result.undo).sorted(), forKey: undoKey)
    }

    static func clearDone(dayKey: String) {
        locked {
            var days = doneDays()
            days.remove(dayKey)
            defaults.set(Array(days).sorted(), forKey: doneKey)
        }
    }

    // MARK: - Wahl je Müllart aus der Mitteilung („Alles raus“ / „Ohne Restmüll“)

    static let choiceKey = "pickup.choices"

    /// Ausdrücklich gewählt: Diese Müllarten (IDs) blieben drin; leer = alles raus. nil = keine Wahl (pauschaler Tipp).
    static func choice(dayKey: String) -> Set<String>? {
        (defaults.dictionary(forKey: choiceKey) as? [String: [String]])?[dayKey].map(Set.init)
    }

    /// „Erledigt“ mit Wahl ablegen – die App läuft nach dem Tipp evtl. nur im Hintergrund und übernimmt es später.
    static func markDone(dayKey: String, leftIn: Set<String>) {
        locked {
            var choices = defaults.dictionary(forKey: choiceKey) as? [String: [String]] ?? [:]
            choices[dayKey] = Array(leftIn).sorted()
            defaults.set(choices, forKey: choiceKey)
            markDone(dayKey: dayKey)
        }
    }

    static func clearChoice(dayKey: String) {
        locked {
            var choices = defaults.dictionary(forKey: choiceKey) as? [String: [String]] ?? [:]
            guard choices.removeValue(forKey: dayKey) != nil else { return }
            defaults.set(choices, forKey: choiceKey)
        }
    }

    // MARK: - „Diesmal nicht rausstellen“ aus der Mitteilung (Tag als ISO-String)

    static let skipKey = "pickup.skipDays"

    /// Noch nicht in die Datenbank übernommene „Diesmal nicht rausstellen“-Tage.
    static func skipDays() -> Set<String> {
        Set(defaults.stringArray(forKey: skipKey) ?? [])
    }

    /// Alles, was an diesem Tag noch offen ist, bleibt diesmal drin. Die App übernimmt es in die Datenbank und plant neu;
    /// die Erinnerungen des Tages verschwinden aber sofort – auch wenn die App gerade nicht läuft.
    static func markSkipped(dayKey: String) {
        locked {
            var days = skipDays()
            days.insert(dayKey)
            defaults.set(Array(days).sorted(), forKey: skipKey)
            #if os(iOS)
            // Nur was sicher wegfällt: „Reinholen“ braucht evtl. eine schon rausgestellte Tonne desselben Tags, und
            // Hinbringen wird nicht ausgelassen (Morgen-Erinnerung bleibt). Das Neuplanen im Modell erledigt den Rest.
            let pickupDay = load()?.pickupDays.first { Days.iso($0.date) == dayKey }
            let keepMorning = pickupDay.map { !PickupWording(day: $0).bringNames.isEmpty } ?? false
            let ids = ["evening", "escalation", "snooze"].map { "waste-\($0)-\(dayKey)" } + (keepMorning ? [] : ["waste-morning-\(dayKey)"])
            removeNotifications(ids)
            cancelAlarm(dayKey: dayKey)
            #endif
            DispatchQueue.main.async { NotificationCenter.default.post(name: notificationName, object: nil) }
        }
    }

    static func clearSkipped(dayKey: String) {
        locked {
            var days = skipDays()
            days.remove(dayKey)
            defaults.set(Array(days).sorted(), forKey: skipKey)
        }
    }

    // MARK: - „Erledigt“ zurücknehmen (versehentlich getippt)

    static let undoKey = "pickup.undoDays"

    static func undoDays() -> Set<String> {
        Set(defaults.stringArray(forKey: undoKey) ?? [])
    }

    /// Nimmt die Markierung im Snapshot sofort zurück und merkt den Tag für die App vor.
    static func markUndone(dayKey key: String) {
        locked {
            let (dayKey, locationID) = DoneKey.split(key)
            var pickupDay = load()?.pickupDays.first { Days.iso($0.date) == dayKey }
            reconcilePending(.undo(key), day: pickupDay)
            pickupDay?.setDone(false, locationID: locationID)
            if pickupDay?.doneAt == nil { clearDoneTime(dayKey: dayKey) }
            if var snapshot = load() {
                snapshot.pickupDays = snapshot.pickupDays.map { day in
                    var copy = day
                    if Days.iso(day.date) == dayKey { copy.setDone(false, locationID: locationID) }
                    return copy
                }
                save(snapshot)
            }
            DispatchQueue.main.async { NotificationCenter.default.post(name: notificationName, object: nil) }
        }
    }

    static func clearUndo(dayKey: String) {
        locked {
            var days = undoDays()
            days.remove(dayKey)
            defaults.set(Array(days).sorted(), forKey: undoKey)
        }
    }

    // MARK: - Zeitpunkt von „Erledigt“ (kurz danach bleibt der Tag zum Zurücknehmen stehen)

    static let doneAtKey = "pickup.doneAt"

    static func doneTimes() -> [String: Date] {
        (defaults.dictionary(forKey: doneAtKey) as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// Merkt, wann der Tag als erledigt markiert wurde, und gibt den Zeitpunkt zurück.
    /// `overwrite: false` behält einen vorhandenen Zeitpunkt (Markierung aus dem Widget, die die App nachträgt).
    @discardableResult
    static func recordDoneTime(dayKey: String, at date: Date = Date(), overwrite: Bool = true) -> Date {
        locked {
            var times = defaults.dictionary(forKey: doneAtKey) as? [String: Double] ?? [:]
            if !overwrite, let existing = times[dayKey] { return Date(timeIntervalSince1970: existing) }
            let cutoff = Days.iso(Days.add(-14, to: Days.today()))
            times = times.filter { $0.key >= cutoff }
            times[dayKey] = date.timeIntervalSince1970
            defaults.set(times, forKey: doneAtKey)
            return date
        }
    }

    static func clearDoneTime(dayKey: String) {
        locked {
            var times = defaults.dictionary(forKey: doneAtKey) as? [String: Double] ?? [:]
            times.removeValue(forKey: dayKey)
            defaults.set(times, forKey: doneAtKey)
        }
    }

    // MARK: - „Ist drin“: Tonnen nach der Abfuhr wieder hereingeholt (nur auf diesem Gerät gemerkt)

    static let broughtInKey = "pickup.broughtInDays"
    static let broughtInNotification = Notification.Name("de.manfahrer.TonneUndTorte.broughtIn")

    static func broughtInDays() -> Set<String> {
        Set(defaults.stringArray(forKey: broughtInKey) ?? [])
    }

    static func markBroughtIn(dayKey: String) {
        locked {
            guard !dayKey.isEmpty else { return }
            // „Ist drin“ heißt: Die Tonne stand draußen – noch nicht bestätigte Abholung zählt als erledigt.
            // Zeitpunkt Tagesbeginn, damit der Tag nicht noch 15 Minuten zum Zurücknehmen stehen bleibt.
            if let day = load()?.pickupDays.first(where: { Days.iso($0.date) == dayKey }), !day.done {
                markDone(dayKey: dayKey, at: Days.parse(dayKey) ?? Date())
            }
            // Nur die letzten Tage aufheben – ältere Markierungen braucht niemand mehr
            let cutoff = Days.iso(Days.add(-14, to: Days.today()))
            var days = broughtInDays().filter { $0 >= cutoff }
            days.insert(dayKey)
            defaults.set(Array(days).sorted(), forKey: broughtInKey)
            if var snapshot = load() {
                snapshot.pickupDays = snapshot.pickupDays.map { day in
                    var copy = day
                    if Days.iso(day.date) == dayKey { copy.broughtIn = true }
                    return copy
                }
                save(snapshot)
            }
            #if os(iOS)
            // Erinnerung „wieder reinholen“ für diesen Tag entfernen (geplant und schon angezeigt)
            let ids = ["waste-bringin-\(dayKey)", "waste-bringin-snooze-\(dayKey)"]
            removeNotifications(ids)
            #endif
            DispatchQueue.main.async { NotificationCenter.default.post(name: broughtInNotification, object: nil) }
        }
    }
}
