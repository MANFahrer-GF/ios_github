import Foundation

/// Eigene Abfall-Piktogramme statt SF Symbols: Tonne mit Rädern, zugeknoteter Sack, Flasche, Zweig.
/// Gespeichert bleibt der SF-Symbolname; erst beim Anzeigen wird auf das passende Bild aus dem Asset-Katalog umgeschaltet.
public enum WasteGlyph {
    /// Name des Bildes im Asset-Katalog oder `nil`, wenn das SF Symbol passt.
    /// - Parameter name: Name der Abfallart, z. B. „Gelbe Tonne“ statt „Gelber Sack“.
    public static func assetName(for symbolName: String, name: String = "") -> String? {
        let lower = name.lowercased()
        switch symbolName {
        case "trash.fill", "trash":
            return "tt.bin"
        case "leaf.fill":
            return lower.contains("laub") ? nil : "tt.bin.bio"
        case "newspaper.fill":
            return "tt.bin.paper"
        case "bag.fill":
            return lower.contains("tonne") ? "tt.bin.yellow" : "tt.sack"
        case "wineglass.fill":
            return "tt.glass"
        case "tree.fill":
            return ["weihnacht", "tanne", "christ"].contains(where: lower.contains) ? nil : "tt.green"
        default:
            return all.contains(symbolName) ? symbolName : nil
        }
    }

    /// Alle eigenen Piktogramme.
    public static let all: Set<String> = ["tt.bin", "tt.bin.bio", "tt.bin.paper", "tt.bin.yellow", "tt.sack", "tt.glass", "tt.green"]
}
