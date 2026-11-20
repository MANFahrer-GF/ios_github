import Foundation

/// Wohin ein Abholtermin im Kalender kommt. Standard: ganztägig am Abholtag. Auf Wunsch am Vorabend zur Uhrzeit der
/// Abend-Erinnerung als „Restmüll rausstellen“ – das To-do steht dann dort, wo man es erledigt (Wunsch Tobias, 20.11.2026).
/// Am Tag selbst bleibt es beim Hinbringen (Schadstoffmobil: am Vorabend stellt man nichts raus), an Tagen ohne Zuständigkeit
/// (Tonnendienst: keine Aufgabe) und wenn der Vorabend schon vorbei ist – sonst läge der Eintrag vor heute, die App räumt erst
/// ab heute auf und legte ihn bei jedem Abgleich neu an (Prüfbefunde 20.11.2026).
public enum CalendarWastePlacement {
    public struct Entry: Equatable {
        public let date: Date
        /// nil = ganztägig
        public let timeMinutes: Int?
        /// Alarme in Minuten ab Mitternacht von `date`
        public let alarms: [Int]
        public let text: String
    }

    /// - Parameters:
    ///   - alarms: Alarme in Minuten ab Mitternacht des Abholtags (Vorabend negativ, z. B. 19:00 → -300).
    ///   - suffix: Zusatz wie „ (Gifhorn)“ bei mehreren Standorten.
    ///   - stayOnDay: Hinbringen oder nicht zuständig – ganztägig am Abholtag.
    public static func make(pickupDay: Date, name: String, suffix: String = "", alarms: [Int], evening: Bool, eveningMinutes: Int,
                            stayOnDay: Bool, today: Date, calendar: Calendar = .current) -> Entry {
        let eve = Days.add(-1, to: calendar.startOfDay(for: pickupDay), calendar: calendar)
        guard evening, !stayOnDay, eve >= calendar.startOfDay(for: today) else {
            return Entry(date: pickupDay, timeMinutes: nil, alarms: alarms, text: name + suffix)
        }
        return Entry(date: eve, timeMinutes: eveningMinutes, alarms: alarms.map { $0 + 1440 },
                     text: L10n.t("\(name) rausstellen", "Put out \(name)") + suffix)
    }
}
