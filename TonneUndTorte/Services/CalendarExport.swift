import Foundation
import EventKit
import TonneCore

/// Trägt Termine in den Apple-Kalender ein (eigener Kalender „Tonne & Torte“).
enum CalendarExport {
    enum ExportError: LocalizedError {
        case denied
        case noSource
        var errorDescription: String? {
            switch self {
            case .denied: return "Kalenderzugriff wurde nicht erlaubt. Bitte in den Einstellungen freigeben."
            case .noSource: return "Es wurde kein Kalender-Account gefunden."
            }
        }
    }

    struct Item {
        var date: Date
        var title: String
        var notes: String?
        var alarmMinutesFromMidnight: [Int]
    }

    @discardableResult
    static func export(items: [Item]) async throws -> Int {
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }
        guard granted else { throw ExportError.denied }

        let calendar = try findOrCreateCalendar(in: store)
        // Bisherige Einträge im Zielzeitraum entfernen, damit nichts doppelt landet
        if let from = items.map(\.date).min(), let to = items.map(\.date).max() {
            let predicate = store.predicateForEvents(withStart: from, end: Days.add(1, to: to), calendars: [calendar])
            for event in store.events(matching: predicate) {
                try? store.remove(event, span: .thisEvent, commit: false)
            }
        }
        var count = 0
        for item in items {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.notes = item.notes
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

    private static func findOrCreateCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == "Tonne & Torte" }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Tonne & Torte"
        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local }) else { throw ExportError.noSource }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}
