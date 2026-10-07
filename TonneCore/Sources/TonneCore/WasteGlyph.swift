import Foundation

/// Eigene Abfall-Piktogramme statt SF Symbols: Tonne mit Rädern, zugeknoteter Sack, Flasche, Zweig.
/// Gespeichert bleibt der SF-Symbolname; erst beim Anzeigen wird auf das passende Bild aus dem Asset-Katalog umgeschaltet.
/// Bewusst keine Umschreibung der gespeicherten Namen: Die Daten laufen über iCloud auch zu Geräten mit älterer
/// App-Version, die nur SF Symbols kennen. Ein `tt.*`-Name wird nur gespeichert, wenn die Wahl in der Auswahl
/// vom Namen abweicht (siehe `storedName`).
public enum WasteGlyph {
    /// Name des Bildes im Asset-Katalog oder `nil`, wenn das SF Symbol passt.
    /// - Parameter name: Name der Abfallart, z. B. „Gelbe Tonne“ statt „Gelber Sack“.
    public static func assetName(for symbolName: String, name: String = "") -> String? {
        switch symbolName {
        case "trash.fill", "trash":
            return "tt.bin"
        case "leaf.fill":
            return mentions(name, ["laub", "leaf", "leaves"]) ? nil : "tt.bin.bio"
        case "newspaper.fill":
            return "tt.bin.paper"
        case "bag.fill":
            return mentions(name, ["tonne", "container"], words: ["bin"]) ? "tt.bin.yellow" : "tt.sack"
        case "wineglass.fill":
            return "tt.glass"
        case "tree.fill":
            return mentions(name, ["weihnacht", "christbaum", "tanne", "christmas", "xmas"], words: ["fir"]) ? nil : "tt.green"
        default:
            return all.contains(symbolName) ? symbolName : nil
        }
    }

    /// Deutsche Wortteile („Wertstofftonne“) als Teilstring, kurze englische Wörter („bin“, „fir“) nur als ganzes Wort.
    /// Wird nur für die wenigen namensabhängigen Symbole ausgewertet.
    private static func mentions(_ name: String, _ parts: [String], words whole: [String] = []) -> Bool {
        guard !name.isEmpty else { return false }
        let lower = name.lowercased()
        if parts.contains(where: lower.contains) { return true }
        guard !whole.isEmpty else { return false }
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return whole.contains(where: words.contains)
    }

    /// Was beim Antippen in der Auswahl gespeichert wird. Ergibt der bisherige SF-Name mit diesem Namen dasselbe
    /// Piktogramm, bleibt es beim SF-Namen – so sehen auch Geräte mit älterer App-Version (iCloud) ein Symbol.
    /// Nur wenn die Wahl vom Namen abweicht (z. B. Tonne bei „Gelber Sack“), wird der `tt.*`-Name gespeichert.
    public static func storedName(for choice: String, name: String) -> String {
        guard let base = sfBase[choice], assetName(for: base, name: name) == choice else { return choice }
        return base
    }

    private static let sfBase: [String: String] = [
        "tt.bin": "trash.fill", "tt.bin.bio": "leaf.fill", "tt.bin.paper": "newspaper.fill",
        "tt.bin.yellow": "bag.fill", "tt.sack": "bag.fill", "tt.glass": "wineglass.fill", "tt.green": "tree.fill",
    ]

    /// Auswahl für Abfallarten: zuerst die eigenen Piktogramme (Gelber Sack und Gelbe Tonne getrennt wählbar),
    /// dann die übrigen SF Symbols ohne die, die ohnehin durch ein eigenes Piktogramm ersetzt werden.
    /// „leaf“ und „tree“ (ohne .fill) bleiben als echte SF Symbols wählbar, z. B. für Laub oder Weihnachtsbäume.
    public static let pickerSymbols: [String] = ordered + ["leaf", "tree"] + Palette.wasteSymbols.filter { assetName(for: $0) == nil }

    /// Ist `candidate` in der Auswahl das Symbol, das `symbolName` gerade anzeigt?
    public static func matches(_ candidate: String, current symbolName: String, name: String = "") -> Bool {
        if candidate == symbolName { return true }
        if let asset = assetName(for: symbolName, name: name) { return asset == candidate }
        // Gespeichertes „leaf.fill“ bei „Laubsammlung“ bleibt SF und entspricht der Auswahl „leaf“.
        return symbolName.hasSuffix(".fill") && candidate == String(symbolName.dropLast(5))
    }

    static let ordered = ["tt.bin", "tt.bin.bio", "tt.bin.paper", "tt.bin.yellow", "tt.sack", "tt.glass", "tt.green"]

    /// Alle eigenen Piktogramme.
    public static let all = Set(ordered)
}
