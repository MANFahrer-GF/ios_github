import Foundation
import SwiftData

/// Legt beim allerersten Start die beiden Standorte mit ihren echten Abfuhrkalendern an.
enum SeedData {

    /// Gifhorn, Steinstraße 1 – AWIDO-Portal des Landkreises Gifhorn
    static let gifhornAwidoCustomer = "gifhorn"
    static let gifhornAwidoOid = "968d9cf6-f840-4229-9b98-6fbcc09828a9"

    /// Kuhlhausen (Hansestadt Havelberg) – „Sync zu Kalender“-Link des Portals der Abfall-App Landkreis Stendal
    static let kuhlhausenICSURL = "https://landkreis-stendal.abfall-app.net/download?system=ical&period=2&district=1465&categories=&view=month"

    static func seedIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: ReminderSettings.Keys.didSeed) else { return }

        let existing = (try? context.fetchCount(FetchDescriptor<Location>())) ?? 0
        if existing == 0 {
            insertDefaultLocations(context: context)
        }
        defaults.set(true, forKey: ReminderSettings.Keys.didSeed)
    }

    /// Die zwei Standorte samt gebündelter Kalender (Stand: Oktober 2026 bzw. Kalenderjahr 2026).
    static func insertDefaultLocations(context: ModelContext) {
        let existingNames = Set(((try? context.fetch(FetchDescriptor<Location>())) ?? []).map { $0.name })

        // --- Gifhorn -----------------------------------------------------------------
        if !existingNames.contains("Gifhorn") {
            insertGifhorn(context: context)
        }
        if !existingNames.contains("Kuhlhausen") {
            insertKuhlhausen(context: context)
        }
        try? context.save()
    }

    private static func insertGifhorn(context: ModelContext) {
        let gifhorn = Location(
            name: "Gifhorn",
            address: "Steinstraße 1, 38518 Gifhorn",
            symbolName: "house.fill",
            colorHex: "#2F6FED",
            sortOrder: 0
        )
        gifhorn.sourceKind = .awido
        gifhorn.awidoCustomer = gifhornAwidoCustomer
        gifhorn.awidoOid = gifhornAwidoOid
        gifhorn.awidoLabel = "Gifhorn, Steinstraße"
        context.insert(gifhorn)

        let gifhornEvents = CalendarImporter.bundledEvents(named: "gifhorn_steinstrasse_2026")
        let gifhornMappings = CalendarImporter.suggestMappings(for: gifhornEvents, location: gifhorn)
        CalendarImporter.apply(events: gifhornEvents, mappings: gifhornMappings, location: gifhorn, context: context, replace: true)
        gifhorn.lastSyncMessage = "Gebündelter Kalender 2026 – bitte online aktualisieren"
    }

    /// Kuhlhausen (Hansestadt Havelberg, Landkreis Stendal)
    private static func insertKuhlhausen(context: ModelContext) {
        let kuhlhausen = Location(
            name: "Kuhlhausen",
            address: "Havelberger Straße 18, 39539 Hansestadt Havelberg",
            symbolName: "house.and.flag.fill",
            colorHex: "#2E9E6B",
            sortOrder: 1
        )
        kuhlhausen.sourceKind = .icsURL
        kuhlhausen.icsURLString = kuhlhausenICSURL
        context.insert(kuhlhausen)

        let kuhlhausenEvents = CalendarImporter.bundledEvents(named: "kuhlhausen")
        let kuhlhausenMappings = CalendarImporter.suggestMappings(for: kuhlhausenEvents, location: kuhlhausen)
        CalendarImporter.apply(events: kuhlhausenEvents, mappings: kuhlhausenMappings, location: kuhlhausen, context: context, replace: true)
        kuhlhausen.lastSyncMessage = "Gebündelter Kalender (Abfall-App Landkreis Stendal, Tour Garz/Jederitz/Kuhlhausen/Warnau)"
    }

    /// Beispiel-Geburtstage zum Ausprobieren (Einstellungen → „Beispieldaten laden“).
    static func insertDemoBirthdays(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        guard people.isEmpty else { return }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let inTwoWeeks = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        let c1 = calendar.dateComponents([.day, .month], from: tomorrow)
        let c2 = calendar.dateComponents([.day, .month], from: inTwoWeeks)
        context.insert(Person(name: "Oma Erika", day: c1.day ?? 1, month: c1.month ?? 1, year: 1948, colorHex: "#EC4899"))
        context.insert(Person(name: "Max Mustermann", day: c2.day ?? 1, month: c2.month ?? 1, year: 1990, colorHex: "#2F6FED"))
        context.insert(Person(name: "Lena", day: 24, month: 12, year: nil, colorHex: "#2E9E6B"))
        try? context.save()
    }

    static func deleteEverything(context: ModelContext) {
        try? context.delete(model: WasteType.self)
        try? context.delete(model: Location.self)
        try? context.delete(model: Person.self)
        try? context.save()
    }
}
