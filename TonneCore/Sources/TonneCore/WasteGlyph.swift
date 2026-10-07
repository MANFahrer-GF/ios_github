import Foundation

/// Eigene Abfall-Piktogramme statt SF Symbols: Tonne mit Rädern, zugeknoteter Sack, Flasche, Zweig.
/// Gespeichert bleibt der SF-Symbolname; erst beim Anzeigen wird auf das passende Bild aus dem Asset-Katalog umgeschaltet.
/// Bewusst keine Umschreibung der gespeicherten Namen: Die Daten laufen über iCloud auch zu Geräten mit älterer
/// App-Version, die nur SF Symbols kennen. Nur wer in der Auswahl ausdrücklich ein eigenes Piktogramm wählt,
/// speichert einen `tt.*`-Namen.
public enum WasteGlyph {
    /// Name des Bildes im Asset-Katalog oder `nil`, wenn das SF Symbol passt.
    /// - Parameter name: Name der Abfallart, z. B. „Gelbe Tonne“ statt „Gelber Sack“.
    public static func assetName(for symbolName: String, name: String = "") -> String? {
        let lower = name.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        // Deutsche Wortteile („Wertstofftonne“) als Teilstring, kurze englische Wörter („bin“, „fir“) nur als ganzes Wort.
        func mentions(_ parts: [String], words whole: [String] = []) -> Bool {
            parts.contains(where: lower.contains) || whole.contains(where: words.contains)
        }
        switch symbolName {
        case "trash.fill", "trash":
            return "tt.bin"
        case "leaf.fill":
            return mentions(["laub", "leaf", "leaves"]) ? nil : "tt.bin.bio"
        case "newspaper.fill":
            return "tt.bin.paper"
        case "bag.fill":
            return mentions(["tonne", "container"], words: ["bin"]) ? "tt.bin.yellow" : "tt.sack"
        case "wineglass.fill":
            return "tt.glass"
        case "tree.fill":
            return mentions(["weihnacht", "tanne", "christmas", "xmas"], words: ["fir"]) ? nil : "tt.green"
        default:
            return all.contains(symbolName) ? symbolName : nil
        }
    }

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
