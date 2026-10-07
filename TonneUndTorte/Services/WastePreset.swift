import Foundation

/// Vorlagen für die gängigen Müllarten in Deutschland.
enum WastePreset: String, CaseIterable, Identifiable {
    case restmuell, bio, papier, gelberSack, glas, sperrmuell, sonstiges

    var id: String { rawValue }

    var name: String {
        switch self {
        case .restmuell: return "Restmüll"
        case .bio: return "Biotonne"
        case .papier: return "Papier"
        case .gelberSack: return "Gelber Sack"
        case .glas: return "Glas"
        case .sperrmuell: return "Sperrmüll"
        case .sonstiges: return "Sonstiges"
        }
    }

    var colorHex: String {
        switch self {
        case .restmuell: return "#5B6470"
        case .bio: return "#8B5E34"
        case .papier: return "#2F6FED"
        case .gelberSack: return "#F2C230"
        case .glas: return "#2E9E6B"
        case .sperrmuell: return "#B45309"
        case .sonstiges: return "#7C3AED"
        }
    }

    var symbolName: String {
        switch self {
        case .restmuell: return "trash.fill"
        case .bio: return "leaf.fill"
        case .papier: return "newspaper.fill"
        case .gelberSack: return "bag.fill"
        case .glas: return "wineglass.fill"
        case .sperrmuell: return "sofa.fill"
        case .sonstiges: return "shippingbox.fill"
        }
    }

    func makeWasteType(sortOrder: Int) -> WasteType {
        WasteType(name: name, colorHex: colorHex, symbolName: symbolName, sortOrder: sortOrder)
    }
}

/// Auswahl an SF Symbols, die sich für Müllarten eignen.
enum WasteSymbols {
    static let all: [String] = [
        "trash.fill", "leaf.fill", "newspaper.fill", "bag.fill", "wineglass.fill",
        "sofa.fill", "shippingbox.fill", "tree.fill", "drop.fill", "bolt.fill",
        "tshirt.fill", "cart.fill", "hammer.fill", "paintpalette.fill", "flame.fill",
        "arrow.3.trianglepath",
    ]
}

/// Farbpalette für Müllarten und Personen.
enum PaletteColors {
    static let all: [String] = [
        "#5B6470", "#8B5E34", "#2F6FED", "#F2C230", "#2E9E6B", "#B45309",
        "#7C3AED", "#DC2626", "#EC4899", "#0D9488", "#F97316", "#0EA5E9",
    ]
}
