import Foundation

/// Rechnet aus Müllarten und Personen konkrete Termine aus.
/// Alle Rückgabedaten sind auf den Tagesanfang (00:00 Uhr) normalisiert.
enum EventEngine {

    // MARK: - Müll

    /// Alle Abholtermine einer Müllart im Zeitraum `start...end` (beide inklusive, tagesgenau).
    static func pickupDates(
        for type: WasteType,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay <= endDay else { return [] }

        var days = Set<Date>()

        if type.intervalWeeks > 0 {
            let stepDays = type.intervalWeeks * 7
            let anchor = calendar.startOfDay(for: type.anchorDate)
            let diff = calendar.dateComponents([.day], from: anchor, to: startDay).day ?? 0
            let firstStep = diff <= 0 ? 0 : Int((Double(diff) / Double(stepDays)).rounded(.up))
            var current = calendar.date(byAdding: .day, value: firstStep * stepDays, to: anchor) ?? anchor
            var guardCounter = 0
            while current <= endDay && guardCounter < 1000 {
                days.insert(current)
                guard let next = calendar.date(byAdding: .day, value: stepDays, to: current) else { break }
                current = next
                guardCounter += 1
            }
        }

        for date in type.explicitDates {
            let day = calendar.startOfDay(for: date)
            if day >= startDay && day <= endDay {
                days.insert(day)
            }
        }

        let skipped = Set(type.skippedDates.map { calendar.startOfDay(for: $0) })
        return days.subtracting(skipped).sorted()
    }

    /// Nächster Abholtermin ab `date` (inklusive), oder nil wenn keiner innerhalb von zwei Jahren liegt.
    static func nextPickup(for type: WasteType, after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let horizon = calendar.date(byAdding: .year, value: 2, to: date) else { return nil }
        return pickupDates(for: type, from: date, to: horizon, calendar: calendar).first
    }

    // MARK: - Geburtstage

    /// Das Datum des Geburtstags einer Person in einem bestimmten Jahr.
    /// Ein 29. Februar wird in Nicht-Schaltjahren am 28. Februar gefeiert.
    static func birthdayDate(for person: Person, inYear year: Int, calendar: Calendar = .current) -> Date? {
        var day = person.day
        if person.month == 2 && person.day == 29 && !isLeapYear(year) {
            day = 28
        }
        let components = DateComponents(year: year, month: person.month, day: day, hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Nächster Geburtstag ab `date` (inklusive heute).
    static func nextBirthday(for person: Person, after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: today)
        if let thisYear = birthdayDate(for: person, inYear: year, calendar: calendar), thisYear >= today {
            return thisYear
        }
        return birthdayDate(for: person, inYear: year + 1, calendar: calendar)
    }

    /// Alter, das die Person an einem Geburtstagstermin erreicht (nil, wenn das Jahr unbekannt ist).
    static func age(of person: Person, on date: Date, calendar: Calendar = .current) -> Int? {
        guard let birthYear = person.year else { return nil }
        let age = calendar.component(.year, from: date) - birthYear
        return age >= 0 ? age : nil
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    // MARK: - Kombiniert

    /// Alle Termine (Müll + Geburtstage) im Zeitraum, sortiert nach Datum.
    static func events(
        wasteTypes: [WasteType],
        people: [Person],
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        var result: [CalendarEvent] = []

        for type in wasteTypes where type.isActive {
            for date in pickupDates(for: type, from: start, to: end, calendar: calendar) {
                result.append(.waste(type, on: date))
            }
        }

        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let startYear = calendar.component(.year, from: startDay)
        let endYear = calendar.component(.year, from: endDay)
        if startYear <= endYear {
            for person in people {
                for year in startYear...endYear {
                    guard let date = birthdayDate(for: person, inYear: year, calendar: calendar) else { continue }
                    if date >= startDay && date <= endDay {
                        result.append(.birthday(person, on: date, age: age(of: person, on: date, calendar: calendar)))
                    }
                }
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.kind != rhs.kind { return lhs.kind == .waste }
            return lhs.title < rhs.title
        }
    }

    /// Termine der nächsten `days` Tage ab heute, gruppiert nach Tag.
    static func upcomingEventsByDay(
        wasteTypes: [WasteType],
        people: [Person],
        days: Int,
        calendar: Calendar = .current
    ) -> [(day: Date, events: [CalendarEvent])] {
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: days, to: today) else { return [] }
        let all = events(wasteTypes: wasteTypes, people: people, from: today, to: end, calendar: calendar)
        let grouped = Dictionary(grouping: all, by: { $0.date })
        return grouped.keys.sorted().map { (day: $0, events: grouped[$0] ?? []) }
    }
}
