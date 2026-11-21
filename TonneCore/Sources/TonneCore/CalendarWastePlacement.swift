import Foundation

/// Wohin ein Abholtermin im Kalender kommt. Standard: ganztägig am Abholtag. Auf Wunsch am Vorabend zur Uhrzeit der
/// Abend-Erinnerung als „Restmüll rausstellen“ – das To-do steht dann dort, wo man es erledigt (Wunsch Tobias, 20.11.2026).
/// Am Tag selbst bleibt es beim Hinbringen (Schadstoffmobil: am Vorabend stellt man nichts raus) und an Tagen ohne Zuständigkeit
/// (Tonnendienst: keine Aufgabe). Ist der Vorabend schon vorbei (Abholung heute), kommt nichts dazu: Der Eintrag von gestern
/// steht schon im Kalender, die App räumt erst ab heute auf – ein neuer Eintrag wäre ein Doppel (Prüfbefunde 20./21.11.2026).
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
    /// - Returns: nil, wenn der Vorabend-Eintrag schon gestern geschrieben wurde (Abholung heute).
    public static func make(pickupDay: Date, name: String, suffix: String = "", alarms: [Int], evening: Bool, eveningMinutes: Int,
                            stayOnDay: Bool, today: Date, calendar: Calendar = .current) -> Entry? {
        let day = calendar.startOfDay(for: pickupDay)
        guard evening, !stayOnDay else { return Entry(date: pickupDay, timeMinutes: nil, alarms: alarms, text: name + suffix) }
        let eve = Days.add(-1, to: day, calendar: calendar)
        guard eve >= calendar.startOfDay(for: today), let start = Days.at(minutes: eveningMinutes, on: eve, calendar: calendar) else { return nil }
        // Alarme über die Wanduhrzeit umrechnen: „7:00 am Abholtag“ liegt an Tagen der Zeitumstellung 11 bzw. 13 Stunden nach
        // 19:00 am Vorabend, nicht pauschal 12 (Kalender und ICS rechnen mit einem festen Abstand zum Beginn)
        let shifted = alarms.compactMap { minutes -> Int? in
            let dayOffset = Int((Double(minutes) / 1440).rounded(.down))
            guard let target = Days.at(minutes: minutes - dayOffset * 1440, on: Days.add(dayOffset, to: day, calendar: calendar), calendar: calendar)
            else { return nil }
            return eveningMinutes + Int((target.timeIntervalSince(start) / 60).rounded())
        }
        return Entry(date: eve, timeMinutes: eveningMinutes, alarms: shifted, text: L10n.t("\(name) rausstellen", "Put out \(name)") + suffix)
    }
}
