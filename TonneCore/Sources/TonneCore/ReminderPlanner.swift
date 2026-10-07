import Foundation

/// Einstellungen für Erinnerungen (vom App-Target aus UserDefaults befüllt).
public struct ReminderSettings: Hashable, Codable {
    public var eveningEnabled: Bool = true
    public var eveningMinutes: Int = 19 * 60
    public var morningEnabled: Bool = false
    public var morningMinutes: Int = 7 * 60
    /// Zweite Erinnerung am Abend, falls „Erledigt“ nicht bestätigt wurde.
    public var escalationEnabled: Bool = true
    public var escalationMinutes: Int = 21 * 60
    public var birthdayMinutes: Int = 9 * 60
    public var customMinutes: Int = 9 * 60

    public init() {}
}

/// Ein geplanter Termin, aus dem Erinnerungen gebaut werden.
public struct PlannedPickup: Hashable {
    public var date: Date
    public var name: String
    public var locationName: String?
    public var colorHex: String
    public var symbolName: String
    public var remindersEnabled: Bool
    /// Vom Nutzer bereits als erledigt markiert (Tonne steht draußen).
    public var done: Bool

    public init(date: Date, name: String, locationName: String? = nil, colorHex: String = "#5B6470", symbolName: String = "trash.fill", remindersEnabled: Bool = true, done: Bool = false) {
        self.date = date; self.name = name; self.locationName = locationName; self.colorHex = colorHex; self.symbolName = symbolName; self.remindersEnabled = remindersEnabled; self.done = done
    }
}

public struct PlannedBirthday: Hashable {
    public var date: Date
    public var name: String
    public var years: Int?
    public var remindDaysBefore: Int
    public var remindersEnabled: Bool

    public init(date: Date, name: String, years: Int?, remindDaysBefore: Int, remindersEnabled: Bool = true) {
        self.date = date; self.name = name; self.years = years; self.remindDaysBefore = remindDaysBefore; self.remindersEnabled = remindersEnabled
    }
}

public struct PlannedCustomEvent: Hashable {
    public var date: Date
    public var title: String
    public var remindDaysBefore: Int
    public var remindersEnabled: Bool

    public init(date: Date, title: String, remindDaysBefore: Int, remindersEnabled: Bool = true) {
        self.date = date; self.title = title; self.remindDaysBefore = remindDaysBefore; self.remindersEnabled = remindersEnabled
    }
}

/// Eine konkrete Mitteilung mit Zeitpunkt.
public struct PlannedNotification: Hashable {
    public enum Category: String { case wasteEvening = "WASTE_EVENING", wasteMorning = "WASTE_MORNING", wasteEscalation = "WASTE_ESCALATION", birthday = "BIRTHDAY", custom = "CUSTOM" }

    public var identifier: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var category: Category
    public var threadIdentifier: String
    /// Tag der Abholung bzw. des Ereignisses (ISO) für Aktionen wie „Erledigt“.
    public var dayKey: String

    public init(identifier: String, fireDate: Date, title: String, body: String, category: Category, threadIdentifier: String, dayKey: String) {
        self.identifier = identifier; self.fireDate = fireDate; self.title = title; self.body = body; self.category = category; self.threadIdentifier = threadIdentifier; self.dayKey = dayKey
    }
}

/// Baut aus Terminen die Liste der Mitteilungen – rein funktional, damit sie testbar ist.
public enum ReminderPlanner {
    public static func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) und \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " und " + names[names.count - 1]
        }
    }

    public static func plan(
        pickups: [PlannedPickup],
        birthdays: [PlannedBirthday],
        customEvents: [PlannedCustomEvent] = [],
        settings: ReminderSettings,
        now: Date = Date(),
        horizonDays: Int = 90,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let today = calendar.startOfDay(for: now)
        let horizon = Days.add(horizonDays, to: today, calendar: calendar)
        var result: [PlannedNotification] = []
        let multiLocation = Set(pickups.compactMap(\.locationName)).count > 1

        // --- Müll: pro Tag zusammenfassen ---
        var byDay: [Date: [PlannedPickup]] = [:]
        for pickup in pickups where pickup.remindersEnabled && !pickup.done {
            let day = calendar.startOfDay(for: pickup.date)
            guard day >= today && day <= horizon else { continue }
            byDay[day, default: []].append(pickup)
        }
        for (day, items) in byDay {
            let names = items.map { multiLocation && $0.locationName != nil ? "\($0.name) (\($0.locationName!))" : $0.name }
            let list = joinNames(names)
            let key = Days.iso(day, calendar: calendar)
            if settings.eveningEnabled, let fire = Days.at(minutes: settings.eveningMinutes, on: Days.add(-1, to: day, calendar: calendar), calendar: calendar), fire > now {
                result.append(PlannedNotification(
                    identifier: "waste-evening-\(key)", fireDate: fire,
                    title: names.count == 1 ? "Morgen: \(names[0])" : "Morgen wird abgeholt",
                    body: names.count == 1 ? "Heute Abend rausstellen – morgen kommt die Abfuhr." : "\(list) – heute Abend rausstellen.",
                    category: .wasteEvening, threadIdentifier: "waste", dayKey: key))
            }
            if settings.eveningEnabled, settings.escalationEnabled, settings.escalationMinutes > settings.eveningMinutes,
               let fire = Days.at(minutes: settings.escalationMinutes, on: Days.add(-1, to: day, calendar: calendar), calendar: calendar), fire > now {
                result.append(PlannedNotification(
                    identifier: "waste-escalation-\(key)", fireDate: fire,
                    title: "Steht \(names.count == 1 ? "die Tonne" : "alles") schon draußen?",
                    body: "\(list) – morgen früh ist die Abfuhr. Tippe „Erledigt“, wenn alles steht.",
                    category: .wasteEscalation, threadIdentifier: "waste", dayKey: key))
            }
            if settings.morningEnabled, let fire = Days.at(minutes: settings.morningMinutes, on: day, calendar: calendar), fire > now {
                result.append(PlannedNotification(
                    identifier: "waste-morning-\(key)", fireDate: fire,
                    title: names.count == 1 ? "Heute: \(names[0])" : "Heute wird abgeholt",
                    body: names.count == 1 ? "Steht die Tonne schon draußen?" : "\(list) – steht alles draußen?",
                    category: .wasteMorning, threadIdentifier: "waste", dayKey: key))
            }
        }

        // --- Geburtstage ---
        for birthday in birthdays where birthday.remindersEnabled {
            let day = calendar.startOfDay(for: birthday.date)
            guard day >= today && day <= horizon else { continue }
            let key = Days.iso(day, calendar: calendar)
            let milestone = birthday.years.map { AnnualDate.isMilestone($0) } ?? false
            if let fire = Days.at(minutes: settings.birthdayMinutes, on: day, calendar: calendar), fire > now {
                let body: String
                if let years = birthday.years {
                    body = milestone ? "\(birthday.name) wird heute \(years) – ein runder Geburtstag! 🎉" : "\(birthday.name) wird heute \(years). Zeit zum Gratulieren!"
                } else {
                    body = "Zeit zum Gratulieren!"
                }
                result.append(PlannedNotification(identifier: "bday-\(key)-\(birthday.name.hashValue)", fireDate: fire, title: "🎂 \(birthday.name) hat heute Geburtstag", body: body, category: .birthday, threadIdentifier: "birthday", dayKey: key))
            }
            if birthday.remindDaysBefore > 0,
               let fire = Days.at(minutes: settings.birthdayMinutes, on: Days.add(-birthday.remindDaysBefore, to: day, calendar: calendar), calendar: calendar), fire > now {
                let when = birthday.remindDaysBefore == 1 ? "morgen" : "in \(birthday.remindDaysBefore) Tagen"
                let body = birthday.years.map { "Wird \($0)\(milestone ? " – runder Geburtstag!" : ""). Noch ein Geschenk besorgen?" } ?? "Noch ein Geschenk besorgen?"
                result.append(PlannedNotification(identifier: "bday-pre-\(key)-\(birthday.name.hashValue)", fireDate: fire, title: "🎁 \(birthday.name) hat \(when) Geburtstag", body: body, category: .birthday, threadIdentifier: "birthday", dayKey: key))
            }
        }

        // --- Eigene Termine ---
        for event in customEvents where event.remindersEnabled {
            let day = calendar.startOfDay(for: event.date)
            guard day >= today && day <= horizon else { continue }
            let key = Days.iso(day, calendar: calendar)
            if let fire = Days.at(minutes: settings.customMinutes, on: day, calendar: calendar), fire > now {
                result.append(PlannedNotification(identifier: "custom-\(key)-\(event.title.hashValue)", fireDate: fire, title: "📌 Heute: \(event.title)", body: DateText.long(day), category: .custom, threadIdentifier: "custom", dayKey: key))
            }
            if event.remindDaysBefore > 0, let fire = Days.at(minutes: settings.customMinutes, on: Days.add(-event.remindDaysBefore, to: day, calendar: calendar), calendar: calendar), fire > now {
                let when = event.remindDaysBefore == 1 ? "morgen" : "in \(event.remindDaysBefore) Tagen"
                result.append(PlannedNotification(identifier: "custom-pre-\(key)-\(event.title.hashValue)", fireDate: fire, title: "📌 \(event.title) \(when)", body: DateText.long(day), category: .custom, threadIdentifier: "custom", dayKey: key))
            }
        }

        return result.sorted { $0.fireDate < $1.fireDate }
    }
}
