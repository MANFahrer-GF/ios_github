import SwiftUI
import TonneCore

/// Abfall-Piktogramm: eigenes Bild (Tonne mit Rädern, zugeknoteter Sack, Flasche …) oder SF Symbol als Rückfall.
/// `size` entspricht der Schriftgröße, die ein SF Symbol an derselben Stelle hätte.
struct WasteIcon: View {
    let symbolName: String
    var name: String = ""
    var size: CGFloat
    var weight: Font.Weight = .bold

    var body: some View {
        if let asset = WasteGlyph.assetName(for: symbolName, name: name) {
            Image(asset)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size * 1.2, height: size * 1.2)
        } else {
            Image(systemName: symbolName).font(.system(size: size, weight: weight))
        }
    }
}

extension Image {
    /// Abfall-Piktogramm für Text-Einbettungen wie `Text("\(Image.waste(...)) morgen")`.
    static func waste(_ symbolName: String, name: String = "") -> Image {
        if let asset = WasteGlyph.assetName(for: symbolName, name: name) {
            return Image(asset).renderingMode(.template)
        }
        return Image(systemName: symbolName)
    }
}
