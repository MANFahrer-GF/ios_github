import Foundation

/// Minimale Zweisprachigkeit für Texte, die im Kern entstehen (Mitteilungen, Schrittnamen, Kategorien).
/// Die App-Oberfläche selbst nutzt den String-Katalog von Xcode.
public enum L10n {
    /// Für Tests überschreibbar; nil = Systemsprache.
    public static var forcedLanguage: String?

    public static var isEnglish: Bool {
        let code = forcedLanguage ?? Locale.preferredLanguages.first ?? Locale.current.identifier
        return code.lowercased().hasPrefix("en")
    }

    /// Wählt die passende Sprache: `L10n.t("Morgen", "Tomorrow")`.
    public static func t(_ de: String, _ en: String) -> String {
        isEnglish ? en : de
    }

    /// Zahl mit passender Einzahl/Mehrzahl: `L10n.count(1, "Termin", "Termine", "date", "dates")` → „1 Termin“.
    public static func count(_ n: Int, _ deOne: String, _ deMany: String, _ enOne: String, _ enMany: String) -> String {
        "\(n) " + (n == 1 ? t(deOne, enOne) : t(deMany, enMany))
    }

    /// „1 Termin“ / „5 Termine“ (EN „1 date“ / „5 dates“).
    public static func dates(_ n: Int) -> String { count(n, "Termin", "Termine", "date", "dates") }
}
