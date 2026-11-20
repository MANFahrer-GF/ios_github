import Foundation

/// Titel der Einträge, die die App in den Kalender schreibt. Mit Emoji („🗑️ Restmüll“) oder ohne („Restmüll“) –
/// Wunsch von Michael Klein (20.11.2026): Kalendereinträge „clean“, ohne Emojis; als Einstellung, Standard mit Emoji.
public enum CalendarEntryTitle {
    public enum Kind { case waste, birthday, custom }

    /// Kennung eines Termins in der ICS-Datei. Immer aus der Emoji-Form, unabhängig von der Einstellung – so bleibt sie
    /// beim Umschalten gleich (erneuter Import ohne Doppel) und entspricht den Kennungen bis 2.1.0.
    public static func feedUID(day: String, _ kind: Kind, _ text: String) -> String {
        let key = make(kind, text, emoji: true)
        return "\(day)-\(key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF })@tonneundtorte"
    }

    public static func make(_ kind: Kind, _ text: String, emoji: Bool) -> String {
        guard emoji else { return text }
        switch kind {
        case .waste: return "🗑️ \(text)"
        case .birthday: return "🎂 \(text)"
        case .custom: return "📌 \(text)"
        }
    }
}
