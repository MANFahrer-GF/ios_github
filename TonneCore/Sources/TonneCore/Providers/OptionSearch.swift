import Foundation

/// Suche in den Auswahllisten des Assistenten: Titel und Untertitel, unabhängig von Groß-/Kleinschreibung,
/// Umlaut-Schreibweise, ß/ss, Bindestrichen und „Str.“/„Straße“. Alle eingegebenen Wörter müssen passen.
/// Die Suchtexte werden je Liste einmal vorbereitet, damit auch München (5835 Einträge) beim Tippen flüssig bleibt.
public struct OptionSearch {
    private let entries: [(option: SelectionOption, plain: String, umlaut: String)]

    public init(_ options: [SelectionOption]) {
        entries = options.map { option in
            let parts = Self.words(option.title + " " + (option.subtitle ?? "")).map { Self.forms(Self.expandStreet($0)) }
            return (option, parts.map(\.plain).joined(), parts.map(\.umlaut).joined())
        }
    }

    public func filter(query: String) -> [SelectionOption] {
        let needles = Self.words(query).map(Self.forms)
        guard !needles.isEmpty else { return entries.map(\.option) }
        return entries.filter { entry in
            needles.allSatisfy { entry.plain.contains($0.plain) || entry.umlaut.contains($0.umlaut) }
        }.map(\.option)
    }

    /// Kleingeschriebene Wörter; alles außer Buchstaben und Ziffern trennt, weiche Trennzeichen zählen nicht.
    private static func words(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{AD}", with: "").lowercased()
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Nur im Listeneintrag: „Hauptstr“ → „Hauptstrasse“, damit beim Tippen von „Hauptstra…“ nichts verschwindet.
    private static func expandStreet(_ word: String) -> String {
        word.hasSuffix("str") ? word + "asse" : word
    }

    /// Zwei Schreibweisen: ü → u (für „Muhlen“) und ü → ue (für „Muehlen“).
    private static func forms(_ word: String) -> (plain: String, umlaut: String) {
        var plain = "", umlaut = ""
        for character in word {
            switch character {
            case "ä": plain += "a"; umlaut += "ae"
            case "ö": plain += "o"; umlaut += "oe"
            case "ü": plain += "u"; umlaut += "ue"
            case "ß": plain += "ss"; umlaut += "ss"
            default: plain.append(character); umlaut.append(character)
            }
        }
        if plain.utf8.allSatisfy({ $0 < 0x80 }) { return (plain, umlaut) }
        return (plain.folding(options: .diacriticInsensitive, locale: nil), umlaut.folding(options: .diacriticInsensitive, locale: nil))
    }
}
