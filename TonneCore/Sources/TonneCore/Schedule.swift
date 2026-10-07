import Foundation

/// Abholrhythmus einer Müllart: wiederkehrend („alle N Wochen ab Ankerdatum“) und/oder
/// explizite Einzeltermine, abzüglich ausgesetzter Termine.
public struct PickupSchedule: Hashable, Codable {
    public var intervalWeeks: Int
    public var anchorDate: Date?
    public var explicitDates: [Date]
    public var skippedDates: [Date]

    public init(intervalWeeks: Int = 0, anchorDate: Date? = nil, explicitDates: [Date] = [], skippedDates: [Date] = []) {
        self.intervalWeeks = intervalWeeks
        self.anchorDate = anchorDate
        self.explicitDates = explicitDates
        self.skippedDates = skippedDates
    }

    public var hasAnyDates: Bool {
        (intervalWeeks > 0 && anchorDate != nil) || !explicitDates.isEmpty
    }
}

public enum ScheduleEngine {
    /// Alle Abholtermine im Zeitraum `from...to` (beide inklusive, tagesgenau), sortiert.
    public static func pickupDates(_ schedule: PickupSchedule, from: Date, to: Date, calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: from)
        let endDay = calendar.startOfDay(for: to)
        guard startDay <= endDay else { return [] }

        var days = Set<Date>()
        if schedule.intervalWeeks > 0, let anchorDate = schedule.anchorDate {
            let stepDays = schedule.intervalWeeks * 7
            let anchor = calendar.startOfDay(for: anchorDate)
            let diff = Days.between(anchor, startDay, calendar: calendar)
            let firstStep = diff <= 0 ? 0 : Int((Double(diff) / Double(stepDays)).rounded(.up))
            var current = Days.add(firstStep * stepDays, to: anchor, calendar: calendar)
            var guardCounter = 0
            while current <= endDay && guardCounter < 2000 {
                days.insert(current)
                current = Days.add(stepDays, to: current, calendar: calendar)
                guardCounter += 1
            }
        }
        for date in schedule.explicitDates {
            let day = calendar.startOfDay(for: date)
            if day >= startDay && day <= endDay { days.insert(day) }
        }
        let skipped = Set(schedule.skippedDates.map { calendar.startOfDay(for: $0) })
        return days.subtracting(skipped).sorted()
    }

    /// Nächster Termin ab `from` (inklusive) innerhalb von zwei Jahren.
    public static func nextPickup(_ schedule: PickupSchedule, from: Date = Date(), calendar: Calendar = .current) -> Date? {
        let horizon = calendar.date(byAdding: .year, value: 2, to: from) ?? from
        return pickupDates(schedule, from: from, to: horizon, calendar: calendar).first
    }

    /// Vergleicht alte und neue Termine (z. B. nach einem Abgleich) und liefert die Unterschiede.
    public static func diff(old: [Date], new: [Date], from: Date = Date(), calendar: Calendar = .current) -> (added: [Date], removed: [Date]) {
        let today = calendar.startOfDay(for: from)
        let oldSet = Set(old.map { calendar.startOfDay(for: $0) }.filter { $0 >= today })
        let newSet = Set(new.map { calendar.startOfDay(for: $0) }.filter { $0 >= today })
        return (newSet.subtracting(oldSet).sorted(), oldSet.subtracting(newSet).sorted())
    }
}
