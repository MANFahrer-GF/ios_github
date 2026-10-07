import SwiftUI

/// Eine Tonne als farbiger Kreis mit Symbol. Überall gleich: App, Widget, Live-Aktivität, Watch.
/// Der weiße Ring sorgt dafür, dass der Kreis auch auf einem Hintergrund in derselben Farbe sichtbar bleibt.
struct BinBadge: View {
    let symbolName: String
    let colorHex: String
    var name: String = ""
    var size: CGFloat = 28
    var ring = true

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: colorHex))
            if ring {
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: max(1, size / 16))
            }
            WasteIcon(symbolName: symbolName, name: name, size: size * 0.46)
                .foregroundStyle(HexLuma.isLight(colorHex) ? Color(hex: "#2A2210") : .white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size / 10, x: 0, y: size / 16)
    }
}

/// Symbol und Farbe einer Tonne, unabhängig vom Datenmodell.
struct BinRef: Hashable {
    let symbolName: String
    let colorHex: String
    var name: String = ""
}

/// Mehrere Tonnen leicht überlappend, für Kopfzeilen.
struct BinStack: View {
    let bins: [BinRef]
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(bins.prefix(4).enumerated()), id: \.offset) { _, bin in
                BinBadge(symbolName: bin.symbolName, colorHex: bin.colorHex, name: bin.name, size: size)
            }
        }
    }
}

/// Tonne als Kreis mit Namen darunter, für Reihen in Widget und App.
struct BinTile: View {
    let name: String
    let bin: BinRef
    var size: CGFloat = 30

    var body: some View {
        VStack(spacing: 3) {
            BinBadge(symbolName: bin.symbolName, colorHex: bin.colorHex, name: bin.name, size: size)
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: size * 2)
    }
}

/// Hintergrund für die große Karte und das Widget: immer neutral dunkel, damit jede Tonne in ihrer
/// eigenen Farbe erkennbar bleibt. Die Farbe der ersten Tonne scheint nur als sanftes Leuchten oben links durch.
enum HeroPalette {
    static let neutralTop = "#2E3646"
    static let neutralBottom = "#161B25"
    static let idle = "#2F6FED"

    static func colors(for hexes: [String]) -> [Color] {
        [Color(hex: neutralTop), Color(hex: neutralBottom)]
    }

    static func glow(for hexes: [String]) -> Color {
        Color(hex: hexes.first ?? idle)
    }

    static func background(for hexes: [String]) -> some View {
        ZStack {
            LinearGradient(colors: colors(for: hexes), startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [glow(for: hexes).opacity(0.5), glow(for: hexes).opacity(0)],
                           center: .topLeading, startRadius: 0, endRadius: 240)
        }
    }

    static func gradient(for hexes: [String]) -> some View {
        background(for: hexes)
    }

    /// Farbe für Text und Symbole auf hellem Grund: bei einer Tonne ihre Farbe, sonst Standard.
    static func tint(for hexes: [String]) -> Color? {
        let unique = Array(Set(hexes))
        return unique.count == 1 ? unique.first.map { Color(hex: $0) } : nil
    }
}
