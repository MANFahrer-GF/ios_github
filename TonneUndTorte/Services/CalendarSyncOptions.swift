import Foundation
import TonneCore

/// Was in den Kalender übertragen wird.
struct CalendarSyncOptions {
    enum Birthdays: String, CaseIterable, Identifiable {
        case none, manualOnly, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return L10n.t("Keine", "None")
            case .manualOnly: return L10n.t("Nur von Hand angelegte", "Only added by hand")
            case .all: return L10n.t("Alle", "All")
            }
        }
    }

    static let wasteKey = "calendar.include.waste"
    static let customKey = "calendar.include.custom"
    static let birthdaysKey = "calendar.include.birthdays"
    /// Emojis im Titel (🗑️/🎂/📌) – Standard an.
    static let emojiKey = "calendar.emoji"
    /// Müll am Vorabend zur Abend-Erinnerungszeit eintragen („Restmüll rausstellen“) statt ganztägig am Abholtag – Standard aus.
    static let wasteEveningKey = "calendar.waste.evening"

    var includeWaste: Bool
    var includeCustom: Bool
    var birthdays: Birthdays
    var emoji: Bool = true
    var wasteEvening: Bool = false

    static var current: CalendarSyncOptions {
        let defaults = SettingsKeys.store
        return CalendarSyncOptions(
            includeWaste: defaults.object(forKey: wasteKey) as? Bool ?? true,
            includeCustom: defaults.object(forKey: customKey) as? Bool ?? true,
            // Geburtstage aus Kontakten zeigt iOS ohnehin im Kalender „Geburtstage“ – daher standardmäßig nur eigene.
            birthdays: Birthdays(rawValue: defaults.string(forKey: birthdaysKey) ?? "") ?? .manualOnly,
            emoji: defaults.object(forKey: emojiKey) as? Bool ?? true,
            wasteEvening: defaults.bool(forKey: wasteEveningKey)
        )
    }
}
