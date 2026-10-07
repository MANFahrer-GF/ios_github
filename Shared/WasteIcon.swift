import SwiftUI
import TonneCore

/// Abfall-Piktogramm: eigenes Symbol (Tonne mit Rädern, zugeknoteter Sack, Flasche …) oder SF Symbol als Rückfall.
/// Die eigenen Symbole liegen als Symbol-Vorlagen in `Shared/Waste.xcassets` und verhalten sich wie SF Symbols:
/// Sie wachsen mit der Schrift, auch eingebettet in `Text`. `size` ist die Schriftgröße.
struct WasteIcon: View {
    let symbolName: String
    var name: String = ""
    var size: CGFloat
    var weight: Font.Weight = .bold

    var body: some View {
        // Die eigenen Symbole haben nur eine Strichstärke; `weight` wirkt beim SF-Rückfall.
        Image.waste(symbolName, name: name).font(.system(size: size, weight: weight))
    }
}

extension Image {
    /// Abfall-Piktogramm für Text-Einbettungen wie `Text("\(Image.waste(...)) morgen")`.
    static func waste(_ symbolName: String, name: String = "") -> Image {
        if let asset = WasteGlyph.assetName(for: symbolName, name: name) {
            return Image(asset)
        }
        return Image(systemName: symbolName)
    }
}
