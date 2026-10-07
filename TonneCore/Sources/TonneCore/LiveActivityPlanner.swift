import Foundation

/// Plant die Live-Aktivität „Tonne rausstellen“ – rein funktional und testbar.
///
/// Ab iOS 26 kann eine Live-Aktivität für einen späteren Zeitpunkt geplant werden; iOS startet sie dann
/// selbst, auch wenn die App nicht offen ist. Die App plant deshalb bei jedem Öffnen die nächsten Abende
/// im Voraus. Vor iOS 26 geht das nicht – dann wird nur gezeigt, was gerade dran ist.
public enum LiveActivityPlanner {
    public struct Entry: Hashable {
        public var day: WidgetSnapshot.PickupDay
        public var dayKey: String
        /// `nil`: jetzt zeigen. Sonst: Startzeitpunkt am Vorabend.
        public var start: Date?
    }

    /// - Parameters:
    ///   - eveningMinutes: Uhrzeit am Vorabend (Minuten nach Mitternacht), ab der die Aktivität erscheint.
    ///   - canSchedule: iOS 26 oder neuer – spätere Abende werden geplant.
    ///   - showTomorrowNow: Morgen-Abholung sofort zeigen, auch vor der Abendzeit (Kurzbefehl, ältere iOS-Versionen).
    ///   - scheduleAhead: wie viele kommende Abende höchstens geplant werden (zählen zum Systemlimit).
    public static func plan(
        pickupDays: [WidgetSnapshot.PickupDay],
        now: Date = Date(),
        eveningMinutes: Int,
        canSchedule: Bool,
        showTomorrowNow: Bool = false,
        scheduleAhead: Int = 2,
        calendar: Calendar = .current
    ) -> [Entry] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = Days.add(1, to: today, calendar: calendar)
        var result: [Entry] = []
        var shownNow = false
        var scheduled = 0
        for day in pickupDays.sorted(by: { $0.date < $1.date }) where !day.done {
            let start = calendar.startOfDay(for: day.date)
            guard start >= today else { continue }
            let key = Days.iso(start, calendar: calendar)
            let evening = Days.at(minutes: eveningMinutes, on: Days.add(-1, to: start, calendar: calendar), calendar: calendar) ?? start
            let showNow: Bool
            if start == today {
                showNow = calendar.component(.hour, from: now) < 12
            } else if start == tomorrow {
                showNow = now >= evening || showTomorrowNow || !canSchedule
            } else {
                showNow = false
            }
            if showNow {
                guard !shownNow else { continue }
                shownNow = true
                result.append(Entry(day: day, dayKey: key, start: nil))
            } else if canSchedule, evening > now, scheduled < scheduleAhead {
                scheduled += 1
                result.append(Entry(day: day, dayKey: key, start: evening))
            }
        }
        return result
    }
}
