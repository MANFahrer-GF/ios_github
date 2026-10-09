import Foundation

/// Gesprochene Antworten für Siri – rein funktional, damit sie testbar sind.
public enum SpokenSummary {
    /// „Oma Erika wird morgen 80. Danach: Paul in 9 Tagen, am Mi., 12. Okt.“
    public static func birthdays(_ items: [WidgetSnapshot.BirthdayItem], now: Date = Date(), calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let upcoming = items.filter { calendar.startOfDay(for: $0.date) >= today }.sorted { $0.date < $1.date }
        guard let first = upcoming.first else {
            return L10n.t("Es stehen keine Geburtstage an.", "There are no upcoming birthdays.")
        }
        let firstDay = upcoming.prefix { calendar.isDate($0.date, inSameDayAs: first.date) }
        let (when, tail) = sentenceWhen(first.date, today: today, calendar: calendar)
        var text: String
        if firstDay.count == 1 {
            if let years = first.years {
                text = L10n.t("\(first.name) wird \(when) \(years)\(tail).", "\(first.name) turns \(years) \(when)\(tail).")
            } else {
                text = L10n.t("\(first.name) hat \(when) Geburtstag\(tail).", "\(first.name)'s birthday is \(when)\(tail).")
            }
        } else {
            let names = firstDay.map { item in item.years.map { "\(item.name) (\($0))" } ?? item.name }
            text = L10n.t("\(ReminderPlanner.joinNames(names)) haben \(when) Geburtstag\(tail).", "\(ReminderPlanner.joinNames(names)) have their birthday \(when)\(tail).")
        }
        if let next = upcoming.dropFirst(firstDay.count).first {
            text += " " + L10n.t("Danach: \(next.name) \(whenText(next.date, today: today, calendar: calendar)).",
                                 "Next: \(next.name) \(whenText(next.date, today: today, calendar: calendar)).")
        }
        return text
    }

    /// Für Sätze mit Zahl dahinter („wird … 40“): nahe Tage als Wort, sonst „am Mi., 12. Okt.“ plus Nachsatz „ – in 5 Tagen“.
    static func sentenceWhen(_ date: Date, today: Date, calendar: Calendar) -> (when: String, tail: String) {
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        guard days > 2 else { return (whenText(date, today: today, calendar: calendar), "") }
        return (L10n.t("am \(DateText.short(date))", "on \(DateText.short(date))"),
                L10n.t(" – in \(days) Tagen", " – in \(days) days"))
    }

    /// „heute“, „morgen“, „übermorgen“, „in 5 Tagen, am Mi., 12. Okt.“
    static func whenText(_ date: Date, today: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return L10n.t("heute", "today")
        case 1: return L10n.t("morgen", "tomorrow")
        case 2: return L10n.t("übermorgen", "the day after tomorrow")
        default: return L10n.t("in \(days) Tagen, am \(DateText.short(date))", "in \(days) days, on \(DateText.short(date))")
        }
    }
}
