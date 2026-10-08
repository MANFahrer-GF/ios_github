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
        /// Eigenes Piktogramm („tt.sack“). `symbolName` bleibt ein SF-Name, damit eine Watch mit älterer
        /// App-Version (die den Schnappschuss ebenfalls bekommt) weiter ein Symbol zeigt.
        public var glyphName: String?
        /// Anzuzeigendes Symbol.
        public var displaySymbol: String { glyphName ?? symbolName }
        public init(name: String, symbolName: String, colorHex: String, locationID: String? = nil, locationName: String? = nil) {
            self.name = name; self.locationID = locationID; self.locationName = locationName; self.colorHex = colorHex
            if WasteGlyph.all.contains(symbolName) {
                self.symbolName = WasteGlyph.sfFallback(for: symbolName)
                self.glyphName = symbolName
            } else {
                self.symbolName = symbolName
            }
        }
    }

    public struct PickupDay: Codable, Hashable {
        public var date: Date
        public var items: [PickupItem]
        public var done: Bool
        /// Tonnen nach der Abfuhr wieder hereingeholt („Ist drin“).
        public var broughtIn: Bool
        /// Wann „Erledigt“ getippt wurde – kurz danach bleibt der Tag noch stehen (zum Zurücknehmen).
        public var doneAt: Date?
        public init(date: Date, items: [PickupItem], done: Bool = false, broughtIn: Bool = false, doneAt: Date? = nil) {
            self.date = date; self.items = items; self.done = done; self.broughtIn = broughtIn; self.doneAt = doneAt
        }

        private enum CodingKeys: String, CodingKey { case date, items, done, broughtIn, doneAt }

        /// `broughtIn` fehlt in Schnappschüssen älterer App-Versionen (z. B. auf der Watch).
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(Date.self, forKey: .date)
            items = try container.decode([PickupItem].self, forKey: .items)
            done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
            broughtIn = try container.decodeIfPresent(Bool.self, forKey: .broughtIn) ?? false
            doneAt = try container.decodeIfPresent(Date.self, forKey: .doneAt)
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
    /// Einstellung „Tonnen wieder reinholen“ (das Widget kann die App-Einstellungen nicht lesen).
    public var bringInEnabled: Bool
    /// Ab dieser Uhrzeit (Minuten) erscheint am Abholtag „wieder reinholen“.
    public var bringInFromMinutes: Int

    public init(generatedAt: Date = Date(), locations: [Location] = [], pickupDays: [PickupDay] = [], birthdays: [BirthdayItem] = [], missedCountThisYear: Int = 0, doneCountThisYear: Int = 0,
                bringInEnabled: Bool = true, bringInFromMinutes: Int = PickupTiming.bringInHintMinutes) {
        self.generatedAt = generatedAt; self.locations = locations; self.pickupDays = pickupDays; self.birthdays = birthdays; self.missedCountThisYear = missedCountThisYear; self.doneCountThisYear = doneCountThisYear
        self.bringInEnabled = bringInEnabled; self.bringInFromMinutes = bringInFromMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, locations, pickupDays, birthdays, missedCountThisYear, doneCountThisYear, bringInEnabled, bringInFromMinutes
    }

    /// Neuere Felder fehlen in Schnappschüssen älterer App-Versionen (z. B. vom iPhone an eine neuere Watch).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        locations = try container.decode([Location].self, forKey: .locations)
        pickupDays = try container.decode([PickupDay].self, forKey: .pickupDays)
        birthdays = try container.decode([BirthdayItem].self, forKey: .birthdays)
        missedCountThisYear = try container.decodeIfPresent(Int.self, forKey: .missedCountThisYear) ?? 0
        doneCountThisYear = try container.decodeIfPresent(Int.self, forKey: .doneCountThisYear) ?? 0
        bringInEnabled = try container.decodeIfPresent(Bool.self, forKey: .bringInEnabled) ?? true
        bringInFromMinutes = try container.decodeIfPresent(Int.self, forKey: .bringInFromMinutes) ?? PickupTiming.bringInHintMinutes
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
            return items.isEmpty ? nil : PickupDay(date: day.date, items: items, done: day.done, broughtIn: day.broughtIn, doneAt: day.doneAt)
        }
        return copy
    }

    /// Die nächste Abholung, um die man sich kümmern muss. Die heutige zählt nicht mehr, sobald sie als erledigt
    /// markiert ist (15 Minuten später, zum Zurücknehmen) oder es nach 17 Uhr ist – dann steht die nächste im Widget.
    public func nextPickupDay(from date: Date = Date(), calendar: Calendar = .current) -> PickupDay? {
        let today = calendar.startOfDay(for: date)
        return pickupDays.first { $0.date >= today && !PickupTiming.isFinished(day: $0.date, done: $0.done, doneAt: $0.doneAt, now: date, calendar: calendar) }
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
