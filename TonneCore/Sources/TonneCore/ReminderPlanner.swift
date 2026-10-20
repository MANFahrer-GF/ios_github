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
    /// Am Abholtag: Tonnen wieder hereinholen (nur Tonnen, keine Säcke).
    public var bringInEnabled: Bool = true
    public var bringInMinutes: Int = 17 * 60
    /// Hauptschalter für alle Geburtstags-Erinnerungen.
    public var birthdayEnabled: Bool = true
    /// Am Geburtstag selbst.
    public var birthdayMinutes: Int = 9 * 60
    /// Vorab-Erinnerungen („morgen“, „in einer Woche“).
    public var birthdayPreMinutes: Int = 9 * 60
    /// Zusätzlich eine Woche vorher – zum Geschenk-Besorgen, für alle Personen.
    public var birthdayWeekBefore: Bool = false
    /// Hauptschalter für alle Erinnerungen an eigene Termine.
    public var customEnabled: Bool = true
    /// Am Termintag – für Termine ohne Uhrzeit.
    public var customMinutes: Int = 9 * 60
    /// Vorab-Erinnerungen an eigene Termine.
    public var customPreMinutes: Int = 9 * 60
    /// Bei Terminen mit Uhrzeit: so viele Minuten vorher erinnern (0 = zur Terminzeit).
    public var customLeadMinutes: Int = 60
    /// Zusätzlich am Vortag – für Termine, deren Vorab-Erinnerung früher liegt (z. B. TÜV: 2 Wochen und 1 Tag vorher).
    public var customDayBefore: Bool = false

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
    /// Nach der Abfuhr schon wieder hereingeholt („Ist drin“).
    public var broughtIn: Bool
    /// Hinweis des Entsorgers zu diesem Termin (Zeit/Ort beim Schadstoffmobil).
    public var note: String?
    /// Art aus der gespeicherten Kategorie (App); nil = aus dem Namen bestimmen.
    public var handling: WasteHandling?
    /// Wann „Erledigt“ getippt wurde – am Vorabend heißt beim Hinbringen: morgen trotzdem erinnern.
    public var doneAt: Date?

    public init(date: Date, name: String, locationName: String? = nil, colorHex: String = "#5B6470", symbolName: String = "trash.fill", remindersEnabled: Bool = true, done: Bool = false, broughtIn: Bool = false, note: String? = nil, handling: WasteHandling? = nil, doneAt: Date? = nil) {
        self.date = date; self.name = name; self.locationName = locationName; self.colorHex = colorHex; self.symbolName = symbolName; self.remindersEnabled = remindersEnabled; self.done = done; self.broughtIn = broughtIn
        self.note = note; self.handling = handling; self.doneAt = doneAt
    }

    /// Eine Tonne, die nach der Abfuhr wieder hereingeholt wird.
    /// Hinbringen (auch umbenannt, über die gespeicherte Kategorie) ist nie eine Tonne zum Reinholen.
    public var isBin: Bool { handling != .bringTo && WasteReturn.isBin(name: name, symbol: symbolName) }
}

public struct PlannedBirthday: Hashable {
    public var date: Date
    public var name: String
    public var years: Int?
    public var remindDaysBefore: Int
    public var remindersEnabled: Bool
    /// Kennung der Person – für stabile Mitteilungs-IDs und zum Öffnen aus der Mitteilung.
    public var id: String
    public var phone: String?
    public var giftIdeas: [String]

    public init(date: Date, name: String, years: Int?, remindDaysBefore: Int, remindersEnabled: Bool = true, id: String? = nil, phone: String? = nil, giftIdeas: [String] = []) {
        self.date = date; self.name = name; self.years = years; self.remindDaysBefore = remindDaysBefore; self.remindersEnabled = remindersEnabled
        self.id = id ?? name; self.phone = phone; self.giftIdeas = giftIdeas
    }
}

public struct PlannedCustomEvent: Hashable {
    public var date: Date
    public var title: String
    public var remindDaysBefore: Int
    public var remindersEnabled: Bool
    public var id: String
    /// Uhrzeit des Termins in Minuten ab Mitternacht, nil = ganztägig.
    public var timeMinutes: Int?
    /// Schon als „Erledigt“ markiert – dann kommt keine Erinnerung mehr.
    public var done: Bool

    public init(date: Date, title: String, remindDaysBefore: Int, remindersEnabled: Bool = true, id: String? = nil, timeMinutes: Int? = nil, done: Bool = false) {
        self.date = date; self.title = title; self.remindDaysBefore = remindDaysBefore; self.remindersEnabled = remindersEnabled
        self.id = id ?? title; self.timeMinutes = timeMinutes; self.done = done
    }
}

/// Eine konkrete Mitteilung mit Zeitpunkt.
public struct PlannedNotification: Hashable {
    public enum Category: String { case wasteEvening = "WASTE_EVENING", wasteMorning = "WASTE_MORNING", wasteEscalation = "WASTE_ESCALATION", wasteBringIn = "WASTE_BRINGIN", birthday = "BIRTHDAY", birthdayPre = "BIRTHDAY_PRE", custom = "CUSTOM" }

    public var identifier: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var category: Category
    public var threadIdentifier: String
    /// Tag der Abholung bzw. des Ereignisses (ISO) für Aktionen wie „Erledigt“.
    public var dayKey: String
    /// Person bzw. eigener Termin, den ein Tipp auf die Mitteilung öffnet (nil bei mehreren zusammengefassten).
    public var targetID: String?
    /// Nur Geburtstag einer einzelnen Person: Name und Telefon für „Anrufen“ und „Glückwunsch schreiben“.
    public var personName: String?
    public var phone: String?
    /// Abholtag mit Hinbringen (Schadstoffmobil, auch gemischt) – Knopf „Erledigt“ ohne „steht draußen“.
    public var bringOnly: Bool

    public init(identifier: String, fireDate: Date, title: String, body: String, category: Category, threadIdentifier: String, dayKey: String, targetID: String? = nil, personName: String? = nil, phone: String? = nil, bringOnly: Bool = false) {
        self.identifier = identifier; self.fireDate = fireDate; self.title = title; self.body = body; self.category = category; self.threadIdentifier = threadIdentifier; self.dayKey = dayKey
        self.targetID = targetID; self.personName = personName; self.phone = phone; self.bringOnly = bringOnly
    }
}

/// Baut aus Terminen die Liste der Mitteilungen – rein funktional, damit sie testbar ist.
public enum ReminderPlanner {
    public static func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return L10n.t("\(names[0]) und \(names[1])", "\(names[0]) and \(names[1])")
        default: return names.dropLast().joined(separator: ", ") + L10n.t(" und ", " and ") + names[names.count - 1]
        }
    }

    /// Text der Abend-Erinnerung – auch für den Hinweis, mit dem sich die geplante Live-Aktivität meldet.
    /// Tonne: rausstellen; Sack, Sperrmüll, Weihnachtsbaum: bereitstellen; Schadstoffmobil: hinbringen (nie „Tonne“).
    public static func eveningText(_ wording: PickupWording) -> (title: String, body: String) {
        let items = wording.items, out = wording.outNames, bring = wording.bringNames
        if items.count == 1 {
            let name = items[0].name
            let body: String
            switch items[0].handling {
            case .bin: body = L10n.t("Heute Abend rausstellen – morgen kommt die Abfuhr.", "Put it out tonight – collection is tomorrow.")
            case .setOut: body = L10n.t("Heute Abend bereitstellen – morgen wird abgeholt.", "Put it out tonight – collection is tomorrow.")
            case .bringTo:
                body = items[0].note.map { L10n.t("Abfälle bereitlegen und morgen hinbringen: \($0)", "Get your items ready and drop them off tomorrow: \($0)") }
                    ?? L10n.t("Abfälle bereitlegen und morgen hinbringen.", "Get your items ready and drop them off tomorrow.")
            }
            return (L10n.t("Morgen: \(name)", "Tomorrow: \(name)"), body)
        }
        let list = joinNames(items.map(\.name))
        if bring.isEmpty {
            return (L10n.t("Morgen wird abgeholt", "Collection tomorrow"), L10n.t("\(list) – heute Abend rausstellen.", "\(list) – put them out tonight."))
        }
        if out.isEmpty {
            return (L10n.t("Morgen: \(list)", "Tomorrow: \(list)"), L10n.t("Morgen hinbringen: \(joinNames(bring)).", "Drop off tomorrow: \(joinNames(bring))."))
        }
        return (L10n.t("Morgen: \(list)", "Tomorrow: \(list)"),
                L10n.t("\(joinNames(out)) heute Abend rausstellen, \(joinNames(bring)) morgen hinbringen.",
                       "Put out \(joinNames(out)) tonight, drop off \(joinNames(bring)) tomorrow."))
    }

    /// Kurzform mit reinen Namen (ältere Aufrufer): Art wird aus dem Namen bestimmt.
    public static func eveningText(names: [String]) -> (title: String, body: String) {
        eveningText(PickupWording(names: names, symbols: []))
    }

    /// Später Nachhak-Abend (nur, wenn etwas rausgestellt wird) und Morgen des Abholtags.
    static func escalationText(_ wording: PickupWording) -> (title: String, body: String) {
        let out = wording.items.filter { $0.handling != .bringTo }
        let title: String
        if out.count == 1 {
            title = out[0].handling == .bin ? L10n.t("Steht die Tonne schon draußen?", "Is the bin out yet?") : L10n.t("Schon rausgestellt?", "Put out yet?")
        } else {
            title = L10n.t("Steht alles draußen?", "Is everything out yet?")
        }
        return (title, L10n.t("\(joinNames(out.map(\.name))) – morgen früh ist die Abfuhr. Tippe „Erledigt“, wenn alles draußen ist.",
                              "\(joinNames(out.map(\.name))) – collection is tomorrow morning. Tap “Done” once \(out.count == 1 ? "it's" : "they're") out."))
    }

    static func morningText(_ wording: PickupWording) -> (title: String, body: String) {
        let items = wording.items, out = wording.outNames, bring = wording.bringNames
        if items.count == 1 {
            let body: String
            switch items[0].handling {
            case .bin: body = L10n.t("Steht die Tonne schon draußen?", "Is the bin out yet?")
            case .setOut: body = L10n.t("Ist alles bereitgestellt?", "Is everything out?")
            case .bringTo:
                body = items[0].note.map { L10n.t("Heute hinbringen: \($0)", "Drop off today: \($0)") } ?? L10n.t("Heute hinbringen – nicht verpassen.", "Drop off today – don't miss it.")
            }
            return (L10n.t("Heute: \(items[0].name)", "Today: \(items[0].name)"), body)
        }
        let list = joinNames(items.map(\.name))
        if bring.isEmpty { return (L10n.t("Heute wird abgeholt", "Collection today"), L10n.t("\(list) – steht alles draußen?", "\(list) – is everything out?")) }
        if out.isEmpty { return (L10n.t("Heute: \(list)", "Today: \(list)"), L10n.t("Heute hinbringen: \(joinNames(bring)).", "Drop off today: \(joinNames(bring)).")) }
        return (L10n.t("Heute: \(list)", "Today: \(list)"),
                L10n.t("\(joinNames(out)) rausstellen, \(joinNames(bring)) heute hinbringen.", "Put out \(joinNames(out)), drop off \(joinNames(bring)) today."))
    }

    /// Kurzform für Widgets (wenig Platz, darum Kommas statt „und“): „A, B“ bzw. „A, B +2“.
    /// „Gelbe Tonne wieder reinholen“ – nach der Abfuhr am Abholtag.
    public static func bringInText(names: [String]) -> (title: String, body: String) {
        let list = joinNames(names)
        if names.count == 1 {
            return (L10n.t("\(names[0]) wieder reinholen", "Bring the \(names[0]) back in"),
                    L10n.t("Die Tonne ist geleert. Tippe „Ist drin“, wenn sie wieder steht.", "The bin has been emptied. Tap “It's in” once it's back."))
        }
        return (L10n.t("Tonnen wieder reinholen", "Bring the bins back in"),
                L10n.t("\(list) sind geleert. Tippe „Ist drin“, wenn alles wieder steht.", "\(list) have been emptied. Tap “It's in” once they're back."))
    }

    public static func shortNames(_ names: [String], max: Int) -> String {
        let limit = Swift.max(1, max)
        let shown = names.prefix(limit).joined(separator: ", ")
        return names.count > limit ? shown + " +\(names.count - limit)" : shown
    }

    /// „morgen“, „in 3 Tagen“, „in einer Woche“, „in zwei Wochen“.
    public static func whenText(daysBefore: Int) -> String {
        switch daysBefore {
        case 1: return L10n.t("morgen", "tomorrow")
        case 7: return L10n.t("in einer Woche", "in one week")
        case 14: return L10n.t("in zwei Wochen", "in two weeks")
        case 30: return L10n.t("in einem Monat", "in one month")
        default: return L10n.t("in \(daysBefore) Tagen", "in \(daysBefore) days")
        }
    }

    /// Mitteilung am Geburtstag – eine Person oder mehrere am selben Tag.
    public static func birthdayText(_ people: [PlannedBirthday]) -> (title: String, body: String) {
        if people.count == 1 {
            let person = people[0]
            let body: String
            if let years = person.years {
                body = AnnualDate.isMilestone(years) ? L10n.t("\(person.name) wird heute \(years) – ein runder Geburtstag! 🎉", "\(person.name) turns \(years) today – a big one! 🎉") : L10n.t("\(person.name) wird heute \(years). Zeit zum Gratulieren!", "\(person.name) turns \(years) today. Time to celebrate!")
            } else {
                body = L10n.t("Zeit zum Gratulieren!", "Time to celebrate!")
            }
            return (L10n.t("🎂 \(person.name) hat heute Geburtstag", "🎂 It's \(person.name)'s birthday today"), body)
        }
        let ages = people.compactMap { person in person.years.map { L10n.t("\(person.name) wird \($0)", "\(person.name) turns \($0)") + (AnnualDate.isMilestone($0) ? " 🎉" : "") } }
        let body = (ages.isEmpty ? "" : ages.joined(separator: ", ") + ". ") + L10n.t("Zeit zum Gratulieren!", "Time to celebrate!")
        return (L10n.t("🎂 Heute haben \(joinNames(people.map(\.name))) Geburtstag", "🎂 Birthdays today: \(joinNames(people.map(\.name)))"), body)
    }

    /// Vorab-Erinnerung – bei einer Person mit ihren Geschenkideen.
    public static func birthdayPreText(_ people: [PlannedBirthday], daysBefore: Int) -> (title: String, body: String) {
        let when = whenText(daysBefore: daysBefore)
        if people.count == 1 {
            let person = people[0]
            var parts: [String] = []
            if let years = person.years { parts.append(L10n.t("Wird \(years)", "Turns \(years)") + (AnnualDate.isMilestone(years) ? L10n.t(" – ein runder Geburtstag!", " – a big one!") : ".")) }
            let ideas = person.giftIdeas.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            parts.append(ideas.isEmpty ? L10n.t("Noch ein Geschenk besorgen?", "Need a present?") : L10n.t("Deine Geschenkideen: ", "Your gift ideas: ") + ideas.joined(separator: ", "))
            return (L10n.t("🎁 \(person.name) hat \(when) Geburtstag", "🎁 \(person.name)'s birthday is \(when)"), parts.joined(separator: " "))
        }
        return (L10n.t("🎁 \(joinNames(people.map(\.name))) haben \(when) Geburtstag", "🎁 Birthdays \(when): \(joinNames(people.map(\.name)))"),
                L10n.t("Noch Geschenke besorgen?", "Need presents?"))
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
        func handling(_ item: PlannedPickup) -> WasteHandling { item.handling ?? WasteHandling.of(name: item.name, symbol: item.symbolName) }
        func wordingItem(_ item: PlannedPickup) -> PickupWording.Item {
            PickupWording.Item(name: multiLocation && item.locationName != nil ? "\(item.name) (\(item.locationName!))" : item.name,
                               handling: handling(item), note: item.note)
        }
        var byDay: [Date: [PlannedPickup]] = [:]
        // Morgen-Erinnerung: offene Müllarten plus Hinbringen, auch wenn der Tag am Vorabend schon „erledigt“ ist –
        // wer abends die Tonne rausstellt und „Erledigt“ tippt, muss morgens trotzdem noch zum Schadstoffmobil.
        var morningByDay: [Date: [PlannedPickup]] = [:]
        for pickup in pickups where pickup.remindersEnabled {
            let day = calendar.startOfDay(for: pickup.date)
            guard day >= today && day <= horizon else { continue }
            if !pickup.done { byDay[day, default: []].append(pickup) }
            // Hinbringen bleibt in der Morgen-Erinnerung, wenn vor dem Abholtag abgehakt (oder Zeitpunkt unbekannt);
            // am Abholtag selbst abgehakt heißt: schon hingebracht
            let doneBeforeDay = pickup.doneAt.map { $0 < day } ?? true
            if !pickup.done || (handling(pickup) == .bringTo && doneBeforeDay) { morningByDay[day, default: []].append(pickup) }
        }
        for (day, items) in morningByDay {
            let key = Days.iso(day, calendar: calendar)
            let wording = PickupWording(items.map(wordingItem))
            if settings.morningEnabled, let fire = Days.at(minutes: settings.morningMinutes, on: day, calendar: calendar), fire > now {
                let text = morningText(wording)
                result.append(PlannedNotification(
                    identifier: "waste-morning-\(key)", fireDate: fire, title: text.title, body: text.body,
                    category: .wasteMorning, threadIdentifier: "waste", dayKey: key, bringOnly: !wording.bringNames.isEmpty))
            }
        }
        for (day, items) in byDay {
            // Art je Müllart: bestimmt die Worte (Tonne / bereitstellen / hinbringen)
            let wording = PickupWording(items.map(wordingItem))
            let key = Days.iso(day, calendar: calendar)
            if settings.eveningEnabled, let fire = Days.at(minutes: settings.eveningMinutes, on: Days.add(-1, to: day, calendar: calendar), calendar: calendar), fire > now {
                let text = eveningText(wording)
                result.append(PlannedNotification(
                    identifier: "waste-evening-\(key)", fireDate: fire, title: text.title, body: text.body,
                    category: .wasteEvening, threadIdentifier: "waste", dayKey: key, bringOnly: !wording.bringNames.isEmpty))
            }
            // Nachhaken „Steht … draußen?“ nur, wenn überhaupt etwas rausgestellt wird
            if settings.eveningEnabled, settings.escalationEnabled, settings.escalationMinutes > settings.eveningMinutes, !wording.onlyBringTo,
               let fire = Days.at(minutes: settings.escalationMinutes, on: Days.add(-1, to: day, calendar: calendar), calendar: calendar), fire > now {
                let text = escalationText(wording)
                result.append(PlannedNotification(
                    identifier: "waste-escalation-\(key)", fireDate: fire, title: text.title, body: text.body,
                    category: .wasteEscalation, threadIdentifier: "waste", dayKey: key))
            }
        }

        // --- Tonnen wieder hereinholen (nur Tonnen; Säcke, Grünschnitt, Sperrmüll bleiben draußen) ---
        if settings.bringInEnabled {
            var binsByDay: [Date: [PlannedPickup]] = [:]
            // Nur zwei Wochen im Voraus – iOS erlaubt nur 64 geplante Mitteilungen, die Abend-Erinnerungen gehen vor
            let bringInHorizon = Days.add(14, to: today, calendar: calendar)
            for pickup in pickups where pickup.remindersEnabled && !pickup.broughtIn && pickup.isBin {
                let day = calendar.startOfDay(for: pickup.date)
                guard day >= today && day <= min(horizon, bringInHorizon) else { continue }
                binsByDay[day, default: []].append(pickup)
            }
            for (day, items) in binsByDay {
                guard let fire = Days.at(minutes: settings.bringInMinutes, on: day, calendar: calendar), fire > now else { continue }
                let names = items.map { multiLocation && $0.locationName != nil ? "\($0.name) (\($0.locationName!))" : $0.name }
                let text = bringInText(names: names)
                result.append(PlannedNotification(
                    identifier: "waste-bringin-\(Days.iso(day, calendar: calendar))", fireDate: fire, title: text.title, body: text.body,
                    category: .wasteBringIn, threadIdentifier: "waste", dayKey: Days.iso(day, calendar: calendar)))
            }
        }

        // --- Geburtstage: pro Tag zusammenfassen ---
        if settings.birthdayEnabled {
            var onDay: [Date: [PlannedBirthday]] = [:]
            var before: [Int: [Date: [PlannedBirthday]]] = [:]
            for birthday in birthdays where birthday.remindersEnabled {
                let day = calendar.startOfDay(for: birthday.date)
                // Vorab-Erinnerungen dürfen für Geburtstage knapp hinter dem Horizont schon fällig sein
                guard day >= today && day <= Days.add(14, to: horizon, calendar: calendar) else { continue }
                if day <= horizon { onDay[day, default: []].append(birthday) }
                var stages = Set<Int>()
                if birthday.remindDaysBefore > 0 { stages.insert(birthday.remindDaysBefore) }
                if settings.birthdayWeekBefore { stages.insert(7) }
                for days in stages { before[days, default: [:]][day, default: []].append(birthday) }
            }
            for (day, people) in onDay {
                guard let fire = Days.at(minutes: settings.birthdayMinutes, on: day, calendar: calendar), fire > now else { continue }
                let key = Days.iso(day, calendar: calendar)
                let text = birthdayText(people)
                let single = people.count == 1 ? people[0] : nil
                result.append(PlannedNotification(identifier: "bday-\(key)" + (single.map { "-\($0.id)" } ?? ""), fireDate: fire, title: text.title, body: text.body,
                                                  category: .birthday, threadIdentifier: "birthday", dayKey: key,
                                                  targetID: single?.id, personName: single?.name, phone: single?.phone.flatMap { $0.isEmpty ? nil : $0 }))
            }
            for (days, byDay) in before {
                for (day, people) in byDay {
                    guard let fire = Days.at(minutes: settings.birthdayPreMinutes, on: Days.add(-days, to: day, calendar: calendar), calendar: calendar), fire > now else { continue }
                    let key = Days.iso(day, calendar: calendar)
                    let text = birthdayPreText(people, daysBefore: days)
                    let single = people.count == 1 ? people[0] : nil
                    result.append(PlannedNotification(identifier: "bday-pre\(days)-\(key)" + (single.map { "-\($0.id)" } ?? ""), fireDate: fire, title: text.title, body: text.body,
                                                      category: .birthdayPre, threadIdentifier: "birthday", dayKey: key, targetID: single?.id, personName: single?.name))
                }
            }
        }

        // --- Eigene Termine ---
        if settings.customEnabled {
            for event in customEvents where event.remindersEnabled && !event.done {
                let day = calendar.startOfDay(for: event.date)
                guard day >= today && day <= Days.add(31, to: horizon, calendar: calendar) else { continue }
                let key = Days.iso(day, calendar: calendar)
                let time = event.timeMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
                // Mit Uhrzeit: die eingestellte Vorlaufzeit vorher – bei 0:30 Uhr und 1 Std. also am Vorabend um 23:30.
                // Ohne Uhrzeit: zur Tageszeit aus den Einstellungen.
                let dayFire: Date? = event.timeMinutes.map { minutes in
                    Days.at(minutes: minutes, on: day, calendar: calendar).flatMap { calendar.date(byAdding: .minute, value: -settings.customLeadMinutes, to: $0) }
                } ?? Days.at(minutes: settings.customMinutes, on: day, calendar: calendar)
                if day <= horizon, let fire = dayFire, fire > now {
                    let title = time.map { L10n.t("📌 Heute um \($0): \(event.title)", "📌 Today at \($0): \(event.title)") } ?? L10n.t("📌 Heute: \(event.title)", "📌 Today: \(event.title)")
                    result.append(PlannedNotification(identifier: "custom-\(key)-\(event.id)", fireDate: fire, title: title, body: DateText.long(day),
                                                      category: .custom, threadIdentifier: "custom", dayKey: key, targetID: event.id))
                }
                var stages = Set<Int>()
                if event.remindDaysBefore > 0 { stages.insert(event.remindDaysBefore) }
                if settings.customDayBefore && event.remindDaysBefore > 1 { stages.insert(1) }
                for days in stages {
                    guard let fire = Days.at(minutes: settings.customPreMinutes, on: Days.add(-days, to: day, calendar: calendar), calendar: calendar), fire > now else { continue }
                    let when = Self.whenText(daysBefore: days)
                    let title = time.map { L10n.t("📌 \(event.title) \(when) um \($0)", "📌 \(event.title) \(when) at \($0)") } ?? L10n.t("📌 \(event.title) \(when)", "📌 \(event.title) \(when)")
                    result.append(PlannedNotification(identifier: "custom-pre\(days)-\(key)-\(event.id)", fireDate: fire, title: title, body: DateText.long(day),
                                                      category: .custom, threadIdentifier: "custom", dayKey: key, targetID: event.id))
                }
            }
        }

        return result.sorted { $0.fireDate < $1.fireDate }
    }
}
