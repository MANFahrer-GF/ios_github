import SwiftUI

/// Eine Tonne als farbiger Kreis mit Symbol. Überall gleich: App, Widget, Live-Aktivität, Watch.
/// Der weiße Ring sorgt dafür, dass der Kreis auch auf einem Hintergrund in derselben Farbe sichtbar bleibt.
struct BinBadge: View {
    let symbolName: String
    let colorHex: String
    var size: CGFloat = 28
    var ring = true

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: colorHex))
            if ring {
                Circle().strokeBorder(.white.opacity(0.9), lineWidth: max(1, size / 16))
            }
            Image(systemName: symbolName)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size / 10, x: 0, y: size / 16)
    }
}

/// Symbol und Farbe einer Tonne, unabhängig vom Datenmodell.
struct BinRef: Hashable {
    let symbolName: String
    let colorHex: String
}

/// Mehrere Tonnen leicht überlappend, für Kopfzeilen.
struct BinStack: View {
    let bins: [BinRef]
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(bins.prefix(4).enumerated()), id: \.offset) { _, bin in
                BinBadge(symbolName: bin.symbolName, colorHex: bin.colorHex, size: size)
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
            BinBadge(symbolName: bin.symbolName, colorHex: bin.colorHex, size: size)
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: size * 2)
    }
}

/// Hintergrundfarben für die große Karte: eine Tonne bekommt ihre Farbe, bei mehreren bleibt der
/// Hintergrund neutral dunkel, damit jede Tonne in ihrer eigenen Farbe erkennbar ist.
enum HeroPalette {
    static let neutralTop = "#2E3646"
    static let neutralBottom = "#161B25"
    static let idle = "#2F6FED"

    static func colors(for hexes: [String]) -> [Color] {
        let unique = Array(Set(hexes))
        if unique.count == 1, let hex = unique.first {
            let color = Color(hex: hex)
            return [color, color.opacity(0.65)]
        }
        if unique.isEmpty {
            let color = Color(hex: idle)
            return [color, color.opacity(0.65)]
        }
        return [Color(hex: neutralTop), Color(hex: neutralBottom)]
    }

    static func gradient(for hexes: [String]) -> LinearGradient {
        LinearGradient(colors: colors(for: hexes), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Farbe für Text und Symbole auf hellem Grund: bei einer Tonne ihre Farbe, sonst Standard.
    static func tint(for hexes: [String]) -> Color? {
        let unique = Array(Set(hexes))
        return unique.count == 1 ? unique.first.map { Color(hex: $0) } : nil
    }
}
