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
}
