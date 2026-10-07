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
            case .denied: return "Kalenderzugriff wurde nicht erlaubt. Bitte in den Einstellungen freigeben."
            case .noSource: return "Es wurde kein Kalenderkonto gefunden."
            case .targetMissing: return "Der gewählte Kalender existiert nicht mehr. Bitte einen anderen wählen."
            }
        }
    }

    struct Item {
        var date: Date
        var title: String
        var notes: String?
        var alarmMinutesFromMidnight: [Int]
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
        let store = EKEventStore()
        guard try await requestAccess(store) else { throw ExportError.denied }
        let sources = store.sources.filter { source in
            source.sourceType != .birthdays && source.sourceType != .subscribed
                && (source.sourceType == .local || !source.calendars(for: .event).isEmpty || source.sourceType == .calDAV || source.sourceType == .exchange)
        }
        let own = sources.map { source in
            Choice(target: .own(sourceID: source.sourceIdentifier),
                   title: sourceName(source),
                   subtitle: "Eigener Kalender „\(calendarTitle)“",
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

    /// Lesbarer Name des aktuellen Ziels, z. B. „Tonne & Torte (Google)“ oder „Privat (iCloud)“.
    static func targetDescription() -> String {
        guard hasFullAccess else { return "Noch nicht gewählt" }
        let store = EKEventStore()
        switch target {
        case .own(let sourceID):
            let source = sourceID.flatMap { id in store.sources.first { $0.sourceIdentifier == id } } ?? preferredSource(in: store)
            return "\(calendarTitle) (\(source.map(sourceName) ?? "automatisch"))"
        case .existing(let id):
            guard let calendar = store.calendar(withIdentifier: id) else { return "Kalender fehlt" }
            return "\(calendar.title) (\(sourceName(calendar.source)))"
        }
    }

    static func sourceName(_ source: EKSource) -> String {
        let title = source.title
        if title.lowercased().contains("icloud") { return "iCloud" }
        if title.lowercased().contains("gmail") || title.lowercased().contains("google") { return "Google (\(title))" }
        switch source.sourceType {
        case .local: return "Auf dem iPhone"
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
        let fingerprint = stableHash(items.map { "\(Days.iso($0.date))|\($0.title)|\($0.alarmMinutesFromMidnight)" }.joined(separator: ";") + "#\(String(describing: target))")
        guard UserDefaults.standard.string(forKey: fingerprintKey) != fingerprint else { return }
        do {
            try await export(items: items, askForAccess: false)
            UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
        } catch {
            // Beim nächsten Abgleich erneut versuchen.
        }
    }

    /// Fingerabdruck verwerfen, damit der nächste automatische Abgleich sicher schreibt.
    static func resetFingerprint() {
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
    }

    /// Über Programmstarts hinweg gleich (anders als `hashValue`).
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    @discardableResult
    static func export(items: [Item], askForAccess: Bool = true) async throws -> Int {
        let store = EKEventStore()
        let granted = askForAccess ? try await requestAccess(store) : hasFullAccess
        guard granted else { throw ExportError.denied }

        let calendar = try resolveCalendar(in: store, create: true)
        removeOwnEvents(from: calendar, in: store)
        var count = 0
        for item in items {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.notes = [item.notes, marker].compactMap { $0 }.joined(separator: "\n")
            event.url = markerURL
            event.isAllDay = true
            event.startDate = item.date
            event.endDate = item.date
            for minutes in item.alarmMinutesFromMidnight {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(minutes * 60)))
            }
            try store.save(event, span: .thisEvent, commit: false)
            count += 1
        }
        try store.commit()
        return count
    }

    /// Zieht in einen anderen Kalender um: Termine im alten Ziel entfernen, im neuen anlegen.
    static func move(to newTarget: Target, items: [Item]) async throws -> Int {
        let store = EKEventStore()
        guard try await requestAccess(store) else { throw ExportError.denied }
        if let old = try? resolveCalendar(in: store, create: false) {
            removeOwnEvents(from: old, in: store)
            try? store.commit()
            // Ein eigener, nun leerer Kalender wird entfernt.
            if old.title == calendarTitle, store.events(matching: store.predicateForEvents(withStart: Days.add(-400, to: Days.today()), end: Days.add(800, to: Days.today()), calendars: [old])).isEmpty {
                try? store.removeCalendar(old, commit: true)
            }
        }
        target = newTarget
        return try await export(items: items, askForAccess: false)
    }

    /// Entfernt nur Termine, die diese App angelegt hat – eigene Termine im Kalender bleiben.
    private static func removeOwnEvents(from calendar: EKCalendar, in store: EKEventStore) {
        let from = Days.add(-30, to: Days.today())
        let to = Days.add(800, to: Days.today())
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [calendar])
        for event in store.events(matching: predicate) {
            let ours = event.url?.scheme == "tonne" || (event.notes ?? "").contains(marker) || calendar.title == calendarTitle
            if ours { try? store.remove(event, span: .thisEvent, commit: false) }
        }
    }

    private static func preferredSource(in store: EKEventStore) -> EKSource? {
        store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
    }

    private static func resolveCalendar(in store: EKEventStore, create: Bool) throws -> EKCalendar {
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
