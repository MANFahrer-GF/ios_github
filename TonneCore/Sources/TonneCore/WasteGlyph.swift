import Foundation

/// Eigene Abfall-Piktogramme statt SF Symbols: Tonne mit Rädern, zugeknoteter Sack, Flasche, Zweig.
/// Im Feld `symbolName` steht immer ein SF-Name – Geräte mit älterer App-Version (iCloud) zeigen damit weiter ein Symbol.
/// Ein ausdrücklich gewähltes Piktogramm liegt zusätzlich in `WasteType.glyphName` und gilt unabhängig vom Namen.
/// Ohne Wahl wird das Piktogramm beim Anzeigen aus SF-Name und Name abgeleitet.
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

    /// SF Symbol, das ältere App-Versionen (über iCloud auf anderen Geräten) für ein eigenes Piktogramm zeigen.
    public static func sfFallback(for choice: String) -> String { sfBase[choice] ?? choice }

    /// Name für VoiceOver statt des Asset-Namens („tt.sack“).
    public static func accessibilityName(for asset: String) -> String {
        switch asset {
        case "tt.bin": return L10n.t("Mülltonne", "Bin")
        case "tt.bin.bio": return L10n.t("Biotonne", "Organic bin")
        case "tt.bin.paper": return L10n.t("Papiertonne", "Paper bin")
        case "tt.bin.yellow": return L10n.t("Gelbe Tonne", "Recycling bin")
        case "tt.sack": return L10n.t("Gelber Sack", "Recycling bag")
        case "tt.glass": return L10n.t("Glas", "Glass")
        case "tt.green": return L10n.t("Grünschnitt", "Garden waste")
        default: return asset
        }
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
