import Foundation

/// Kompakter Datenstand, den die App für Widget, Live-Aktivität und Siri in die App-Gruppe schreibt.
public struct WidgetSnapshot: Codable, Hashable {
    public struct Location: Codable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var symbolName: String
        public var colorHex: String
        public init(id: String, name: String, symbolName: String, colorHex: String) {
            self.id = id; self.name = name; self.symbolName = symbolName; self.colorHex = colorHex
        }
    }

    public struct PickupItem: Codable, Hashable {
        public var name: String
        public var symbolName: String
        public var colorHex: String
        public var locationID: String?
        public var locationName: String?
        public init(name: String, symbolName: String, colorHex: String, locationID: String? = nil, locationName: String? = nil) {
            self.name = name; self.symbolName = symbolName; self.colorHex = colorHex; self.locationID = locationID; self.locationName = locationName
        }
    }

    public struct PickupDay: Codable, Hashable {
        public var date: Date
        public var items: [PickupItem]
        public var done: Bool
        public init(date: Date, items: [PickupItem], done: Bool = false) {
            self.date = date; self.items = items; self.done = done
        }
    }

    public struct BirthdayItem: Codable, Hashable {
        public var date: Date
        public var name: String
        public var years: Int?
        public var colorHex: String
        public var initials: String
        public init(date: Date, name: String, years: Int?, colorHex: String, initials: String) {
            self.date = date; self.name = name; self.years = years; self.colorHex = colorHex; self.initials = initials
        }
    }

    public var generatedAt: Date
    public var locations: [Location]
    public var pickupDays: [PickupDay]
    public var birthdays: [BirthdayItem]
    public var missedCountThisYear: Int
    public var doneCountThisYear: Int

    public init(generatedAt: Date = Date(), locations: [Location] = [], pickupDays: [PickupDay] = [], birthdays: [BirthdayItem] = [], missedCountThisYear: Int = 0, doneCountThisYear: Int = 0) {
        self.generatedAt = generatedAt; self.locations = locations; self.pickupDays = pickupDays; self.birthdays = birthdays; self.missedCountThisYear = missedCountThisYear; self.doneCountThisYear = doneCountThisYear
    }

    public static let appGroup = "group.de.manfahrer.TonneUndTorte"
    public static let fileName = "widget-snapshot.json"

    /// Nur Geburtstage ab dem Tag von `date`, nach Datum sortiert – für Widget-Einträge, die erst später (z. B. um Mitternacht) gezeigt werden.
    public func upcomingBirthdays(from date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        var copy = self
        let start = calendar.startOfDay(for: date)
        copy.birthdays = birthdays.filter { $0.date >= start }.sorted { $0.date < $1.date }
        return copy
    }

    /// Nur Tage eines Standorts (nil = alle).
    public func filtered(locationID: String?) -> WidgetSnapshot {
        guard let locationID else { return self }
        var copy = self
        copy.pickupDays = pickupDays.compactMap { day in
            let items = day.items.filter { $0.locationID == locationID }
            return items.isEmpty ? nil : PickupDay(date: day.date, items: items, done: day.done)
        }
        return copy
    }

    public func nextPickupDay(from date: Date = Date(), calendar: Calendar = .current) -> PickupDay? {
        let today = calendar.startOfDay(for: date)
        return pickupDays.first { $0.date >= today }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}
