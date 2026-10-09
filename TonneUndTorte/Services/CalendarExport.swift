import Foundation
import EventKit
import CoreGraphics
import TonneCore

/// Trägt Termine in einen Kalender der Kalender-App ein und hält ihn aktuell.
///
/// Ziel ist wahlweise ein eigener Kalender „Tonne & Torte“ in einem Konto (iCloud, Google, Outlook,
/// nur auf dem Gerät) oder ein vorhandener Kalender. iOS gleicht diese Konten selbst mit dem
/// jeweiligen Dienst ab, die Termine erscheinen also auch bei Google oder auf dem iPad.
/// Die App markiert ihre Termine und löscht beim Aktualisieren nur diese.
enum CalendarExport {
    enum ExportError: LocalizedError {
        case denied
        case noSource
        case targetMissing
        var errorDescription: String? {
            switch self {
            case .denied: return L10n.t("Kalenderzugriff wurde nicht erlaubt. Bitte in den Einstellungen freigeben.", "Calendar access was not allowed. Please enable it in Settings.")
            case .noSource: return L10n.t("Es wurde kein Kalenderkonto gefunden.", "No calendar account was found.")
            case .targetMissing: return L10n.t("Der gewählte Kalender existiert nicht mehr. Bitte einen anderen wählen.", "The chosen calendar no longer exists. Please pick another one.")
            }
        }
    }

    struct Item {
        var date: Date
        var title: String
        var notes: String?
        var alarmMinutesFromMidnight: [Int]
        /// Uhrzeit (Minuten ab Mitternacht) – dann ein einstündiger Termin statt ganztägig.
        var timeMinutes: Int? = nil
    }

    /// Wohin geschrieben wird.
    enum Target: Hashable, Codable {
        /// Eigener Kalender „Tonne & Torte“ im Konto mit dieser Kennung (nil = automatisch, bevorzugt iCloud).
        case own(sourceID: String?)
        /// Ein vorhandener Kalender.
        case existing(calendarID: String)
    }

    /// Eintrag für die Auswahlliste.
    struct Choice: Identifiable, Hashable {
        let target: Target
        let title: String
        let subtitle: String
        let colorHex: String?
        var id: String {
            switch target {
            case .own(let source): return "own:\(source ?? "auto")"
            case .existing(let calendar): return "cal:\(calendar)"
            }
        }
    }

    static let autoSyncKey = "calendar.autoSync"
    static let calendarTitle = "Tonne & Torte"
    private static let fingerprintKey = "calendar.autoSync.fingerprint"
    private static let targetKey = "calendar.target"
    private static let marker = "Eingetragen von Tonne & Torte"
    private static let markerURL = URL(string: "tonne://event")
    /// Ein gemeinsamer Store für Anzeige und Auswahl (das Anlegen ist teuer).
    private static let sharedStore = EKEventStore()

    // MARK: Ziel

    static var target: Target {
        get {
            guard let data = UserDefaults.standard.data(forKey: targetKey),
                  let value = try? JSONDecoder().decode(Target.self, from: data) else { return .own(sourceID: nil) }
            return value
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: targetKey)
            resetFingerprint()
        }
    }

    /// Hat der Nutzer vollen Kalenderzugriff gegeben?
    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static func requestAccess(_ store: EKEventStore = EKEventStore()) async throws -> Bool {
        if hasFullAccess { return true }
        return try await store.requestFullAccessToEvents()
    }

    /// Alle möglichen Ziele: eigener Kalender je Konto und alle beschreibbaren vorhandenen Kalender.
    static func choices() async throws -> (own: [Choice], existing: [Choice]) {
        let store = sharedStore
        guard try await requestAccess(store) else { throw ExportError.denied }
        store.refreshSourcesIfNecessary()
        // Eigene Kalender lassen sich zuverlässig nur in iCloud anlegen. „Auf dem iPhone“ gibt es nur,
        // solange iCloud-Kalender aus ist (sonst blendet iOS diese Quelle aus). Google und Outlook
        // erlauben Apps kein Anlegen – dort wählt man einen vorhandenen Kalender.
        let iCloudSources = store.sources.filter(isICloud)
        let ownSources = iCloudSources.isEmpty ? store.sources.filter { $0.sourceType == .local } : iCloudSources
        let own = ownSources.map { source in
            Choice(target: .own(sourceID: source.sourceIdentifier),
                   title: sourceName(source),
                   subtitle: L10n.t("Eigener Kalender „\(calendarTitle)“", "Own calendar “\(calendarTitle)”"),
                   colorHex: nil)
        }
        let existing = store.calendars(for: .event)
            .filter { $0.allowsContentModifications && $0.title != calendarTitle && $0.type != .birthday && $0.type != .subscription }
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
            .map { calendar in
                Choice(target: .existing(calendarID: calendar.calendarIdentifier),
                       title: calendar.title,
                       subtitle: sourceName(calendar.source),
                       colorHex: calendar.cgColor.flatMap(hex(from:)))
            }
        return (own, existing)
    }

    private static func isICloud(_ source: EKSource) -> Bool {
        source.sourceType == .calDAV && source.title.lowercased().contains("icloud")
    }

    /// Das tatsächlich verwendete Ziel – „automatisch“ wird auf das konkrete Konto aufgelöst.
    static func resolvedTarget() -> Target {
        if case .own(nil) = target, let source = preferredSource(in: sharedStore) {
            return .own(sourceID: source.sourceIdentifier)
        }
        return target
    }

    /// Lesbarer Name des aktuellen Ziels, z. B. „Tonne & Torte (Google)“ oder „Privat (iCloud)“.
    static func targetDescription() -> String {
        guard hasFullAccess else { return L10n.t("Noch nicht gewählt", "Not chosen yet") }
        let store = sharedStore
        switch target {
        case .own(let sourceID):
            let source = sourceID.flatMap { id in store.sources.first { $0.sourceIdentifier == id } } ?? preferredSource(in: store)
            return "\(calendarTitle) (\(source.map(sourceName) ?? L10n.t("automatisch", "automatic")))"
        case .existing(let id):
            guard let calendar = store.calendar(withIdentifier: id) else { return L10n.t("Kalender fehlt", "Calendar missing") }
            return "\(calendar.title) (\(sourceName(calendar.source)))"
        }
    }

    static func sourceName(_ source: EKSource) -> String {
        let title = source.title
        if title.lowercased().contains("icloud") { return "iCloud" }
        if title.lowercased().contains("gmail") || title.lowercased().contains("google") { return "Google (\(title))" }
        switch source.sourceType {
        case .local: return L10n.t("Auf dem iPhone", "On this iPhone")
        case .exchange: return "Exchange/Outlook (\(title))"
        default: return title
        }
    }

    private static func hex(from color: CGColor) -> String? {
        guard let components = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))
    }

    // MARK: Abgleich

    /// Hält den Kalender von selbst aktuell: läuft nach jedem Abgleich, fragt nie nach Rechten und
    /// schreibt nur, wenn sich die Termine seit dem letzten Mal geändert haben.
    static func autoSyncIfEnabled(items: [Item]) async {
        guard UserDefaults.standard.bool(forKey: autoSyncKey), hasFullAccess else { return }
        guard UserDefaults.standard.string(forKey: fingerprintKey) != fingerprint(items) else { return }
        _ = try? await export(items: items, askForAccess: false)
    }

    /// Fingerabdruck verwerfen, damit der nächste automatische Abgleich sicher schreibt.
    static func resetFingerprint() {
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
    }

    private static func fingerprint(_ items: [Item]) -> String {
        stableHash(items.map { "\(Days.iso($0.date))|\($0.title)|\($0.alarmMinutesFromMidnight)|\($0.timeMinutes ?? -1)" }.joined(separator: ";") + "#\(String(describing: resolvedTarget()))")
    }

    /// Über Programmstarts hinweg gleich (anders als `hashValue`).
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// Alle Schreibvorgänge laufen nacheinander. Zwei gleichzeitige Abgleiche würden sonst dieselben
    /// alten Termine lesen und die neuen doppelt eintragen.
    private static let queue = SerialQueue()

    @discardableResult
    static func export(items: [Item], askForAccess: Bool = true) async throws -> Int {
        if askForAccess { guard try await requestAccess() else { throw ExportError.denied } }
        guard hasFullAccess else { throw ExportError.denied }
        return try await queue.run {
            let store = EKEventStore()
            let calendar = try resolveCalendar(in: store, target: target, create: true)
            let count = try write(items, into: calendar, store: store)
            UserDefaults.standard.set(fingerprint(items), forKey: fingerprintKey)
            return count
        }
    }

    /// Zieht in einen anderen Kalender um. Erst wird ins neue Ziel geschrieben; nur wenn das klappt,
    /// werden die Termine im alten Ziel entfernt. Schlägt das neue Ziel fehl, bleibt alles wie es war.
    static func move(to newTarget: Target, items: [Item]) async throws -> Int {
        guard try await requestAccess() else { throw ExportError.denied }
        return try await queue.run {
            let store = EKEventStore()
            let oldTarget = resolvedTarget()
            let newCalendar = try resolveCalendar(in: store, target: newTarget, create: true)
            let oldCalendar = try? resolveCalendar(in: store, target: oldTarget, create: false)
            let count = try write(items, into: newCalendar, store: store)
            target = newTarget
            if let oldCalendar, oldCalendar.calendarIdentifier != newCalendar.calendarIdentifier {
                if case .own = oldTarget {
                    // Der eigene Kalender enthält nur Termine dieser App – er wird ganz entfernt.
                    try? store.removeCalendar(oldCalendar, commit: true)
                } else {
                    removeOwnEvents(from: oldCalendar, in: store)
                    try? store.commit()
                }
            }
            UserDefaults.standard.set(fingerprint(items), forKey: fingerprintKey)
            return count
        }
    }

    /// Ersetzt die Termine dieser App ab heute durch die neuen.
    private static func write(_ items: [Item], into calendar: EKCalendar, store: EKEventStore) throws -> Int {
        removeOwnEvents(from: calendar, in: store)
        var count = 0
        for item in items {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.notes = [item.notes, marker].compactMap { $0 }.joined(separator: "\n")
            event.url = markerURL
            if let time = item.timeMinutes, let start = Days.at(minutes: time, on: item.date) {
                event.isAllDay = false
                event.startDate = start
                event.endDate = start.addingTimeInterval(3600)
            } else {
                event.isAllDay = true
                event.startDate = item.date
                event.endDate = item.date
            }
            for minutes in item.alarmMinutesFromMidnight {
                // Alarme beziehen sich auf den Beginn – bei ganztägigen Terminen Mitternacht
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval((minutes - (item.timeMinutes ?? 0)) * 60)))
            }
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        return count
    }

    /// Entfernt nur Termine, die diese App angelegt hat – eigene Termine im Kalender bleiben.
    private static func removeOwnEvents(from calendar: EKCalendar, in store: EKEventStore) {
        // Ab heute: vergangene Einträge bleiben als Verlauf stehen, der Export schreibt ebenfalls ab heute.
        let from = Days.today()
        let to = Days.add(800, to: Days.today())
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        for event in store.events(matching: predicate) {
            let ours = event.url?.scheme == "tonne" || (event.notes ?? "").contains(marker) || calendar.title == calendarTitle
            if ours { try? store.remove(event, span: .thisEvent, commit: false) }
        }
    }

    private static func preferredSource(in store: EKEventStore) -> EKSource? {
        store.sources.first(where: isICloud)
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
    }

    private static func resolveCalendar(in store: EKEventStore, target: Target, create: Bool) throws -> EKCalendar {
        switch target {
        case .existing(let id):
            guard let calendar = store.calendar(withIdentifier: id) else { throw ExportError.targetMissing }
            return calendar
        case .own(let sourceID):
            let source = sourceID.flatMap { id in store.sources.first { $0.sourceIdentifier == id } } ?? preferredSource(in: store)
            guard let source else { throw ExportError.noSource }
            if let existing = store.calendars(for: .event).first(where: { $0.title == calendarTitle && $0.source.sourceIdentifier == source.sourceIdentifier }) {
                return existing
            }
            guard create else { throw ExportError.targetMissing }
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = calendarTitle
            calendar.cgColor = CGColor(red: 0.18, green: 0.62, blue: 0.42, alpha: 1)
            calendar.source = source
            try store.saveCalendar(calendar, commit: true)
            return calendar
        }
    }
}

/// Führt asynchrone Aufgaben streng nacheinander aus.
actor SerialQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task { () async throws -> T in
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
