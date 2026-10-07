import Foundation

/// Einstellungen für Erinnerungen. Werden in UserDefaults gespeichert,
/// die Views binden per @AppStorage an dieselben Schlüssel.
struct ReminderSettings {
    enum Keys {
        static let eveningEnabled = "reminder.evening.enabled"
        static let eveningMinutes = "reminder.evening.minutes"
        static let morningEnabled = "reminder.morning.enabled"
        static let morningMinutes = "reminder.morning.minutes"
        static let birthdayMinutes = "reminder.birthday.minutes"
        static let horizonDays = "reminder.horizon.days"
        static let didSeed = "app.didSeed"
    }

    /// Abends vorher erinnern („Morgen: Gelber Sack“)
    var eveningEnabled: Bool = true
    /// Minuten seit Mitternacht, Standard 19:00 Uhr
    var eveningMinutes: Int = 19 * 60
    /// Morgens am Abholtag erinnern
    var morningEnabled: Bool = false
    /// Standard 07:00 Uhr
    var morningMinutes: Int = 7 * 60
    /// Uhrzeit für Geburtstagserinnerungen, Standard 09:00 Uhr
    var birthdayMinutes: Int = 9 * 60

    static func load(from defaults: UserDefaults = .standard) -> ReminderSettings {
        var settings = ReminderSettings()
        if defaults.object(forKey: Keys.eveningEnabled) != nil {
            settings.eveningEnabled = defaults.bool(forKey: Keys.eveningEnabled)
        }
        if defaults.object(forKey: Keys.eveningMinutes) != nil {
            settings.eveningMinutes = defaults.integer(forKey: Keys.eveningMinutes)
        }
        if defaults.object(forKey: Keys.morningEnabled) != nil {
            settings.morningEnabled = defaults.bool(forKey: Keys.morningEnabled)
        }
        if defaults.object(forKey: Keys.morningMinutes) != nil {
            settings.morningMinutes = defaults.integer(forKey: Keys.morningMinutes)
        }
        if defaults.object(forKey: Keys.birthdayMinutes) != nil {
            settings.birthdayMinutes = defaults.integer(forKey: Keys.birthdayMinutes)
        }
        return settings
    }

    static func timeString(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
