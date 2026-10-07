import Foundation

/// Grundtypen von Abfall mit Farbe, Symbol und Suchwörtern zur automatischen Zuordnung.
public enum WasteCategory: String, CaseIterable, Codable, Hashable {
    case residual, organic, paper, packaging, glass, bulky, hazardous, green, textiles, electronics, other

    public var name: String {
        switch self {
        case .residual: return L10n.t("Restmüll", "General waste")
        case .organic: return L10n.t("Biotonne", "Organic waste")
        case .paper: return L10n.t("Papier", "Paper")
        case .packaging: return L10n.t("Gelber Sack", "Packaging")
        case .glass: return L10n.t("Glas", "Glass")
        case .bulky: return L10n.t("Sperrmüll", "Bulky waste")
        case .hazardous: return L10n.t("Schadstoffmobil", "Hazardous waste")
        case .green: return L10n.t("Grünschnitt", "Garden waste")
        case .textiles: return L10n.t("Altkleider", "Textiles")
        case .electronics: return L10n.t("Elektroschrott", "E-waste")
        case .other: return L10n.t("Sonstiges", "Other")
        }
    }

    public var colorHex: String {
        switch self {
        case .residual: return "#5B6470"
        case .organic: return "#8B5E34"
        case .paper: return "#2F6FED"
        case .packaging: return "#F2C230"
        case .glass: return "#2E9E6B"
        case .bulky: return "#B45309"
        case .hazardous: return "#DC2626"
        case .green: return "#16A34A"
        case .textiles: return "#0D9488"
        case .electronics: return "#0EA5E9"
        case .other: return "#7C3AED"
        }
    }

    /// SF Symbol
    public var symbolName: String {
        switch self {
        case .residual: return "trash.fill"
        case .organic: return "leaf.fill"
        case .paper: return "newspaper.fill"
        case .packaging: return "bag.fill"
        case .glass: return "wineglass.fill"
        case .bulky: return "sofa.fill"
        case .hazardous: return "exclamationmark.triangle.fill"
        case .green: return "tree.fill"
        case .textiles: return "tshirt.fill"
        case .electronics: return "bolt.fill"
        case .other: return "shippingbox.fill"
        }
    }

    public var emoji: String {
        switch self {
        case .residual: return "🗑️"
        case .organic: return "🍂"
        case .paper: return "📰"
        case .packaging: return "🛍️"
        case .glass: return "🍾"
        case .bulky: return "🛋️"
        case .hazardous: return "☣️"
        case .green: return "🌳"
        case .textiles: return "👕"
        case .electronics: return "🔌"
        case .other: return "📦"
        }
    }

    /// Reihenfolge ist relevant: speziellere Kategorien stehen vor allgemeinen („Grünschnitt“ vor „grün“ = Bio).
    static let keywords: [(WasteCategory, [String])] = [
        (.green, ["grünschnitt", "gruenschnitt", "grünabfall", "gruenabfall", "grünrück", "gruenrueck", "gartenabf", "baumschnitt", "weihnachtsb", "christbaum", "tannenbaum", "laub", "strauch"]),
        (.hazardous, ["schadstoff", "problemstoff", "sondermüll", "sondermuell", "giftmobil", "umweltmobil"]),
        (.textiles, ["altkleider", "textil", "kleider", "altschuhe"]),
        (.electronics, ["elektro", "e-schrott", "eschrott", "altgeräte", "altgeraete"]),
        (.bulky, ["sperr", "sperrgut", "altholz", "altmetall", "schrott", "weiße ware"]),
        (.glass, ["glas"]),
        (.paper, ["papier", "pappe", "karton", "blau", "ppk", "altpap"]),
        (.packaging, ["gelb", "wertstoff", "leichtverpack", "lvp", "plastik", "kunststoff", "verpackung", "dsd", "dual"]),
        (.organic, ["bio", "grün", "gruen", "kompost", "organ", "braun", "küchen", "kuechen"]),
        (.residual, ["rest", "hausmüll", "hausmuell", "grau", "schwarz", "haus", "restabf"]),
    ]

    /// Rät anhand eines Titels aus einem Abfuhrkalender die Kategorie.
    public static func classify(_ title: String) -> WasteCategory {
        let lower = title.lowercased()
        for (category, words) in keywords where words.contains(where: { lower.contains($0) }) {
            return category
        }
        return .other
    }

    /// Titel, die keine Abholung sind (Sprechstunden, Repair-Cafés …).
    public static func isIgnorableTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return ["repair", "café", "cafe", "feiertag", "sprechstunde", "öffnungszeit", "oeffnungszeit"].contains { lower.contains($0) }
    }
}

/// Farbpalette und Symbolauswahl für die Bearbeitung.
public enum Palette {
    public static let colors: [String] = [
        "#5B6470", "#8B5E34", "#2F6FED", "#F2C230", "#2E9E6B", "#B45309",
        "#7C3AED", "#DC2626", "#EC4899", "#0D9488", "#F97316", "#0EA5E9",
    ]
    public static let wasteSymbols: [String] = [
        "trash.fill", "leaf.fill", "newspaper.fill", "bag.fill", "wineglass.fill", "sofa.fill",
        "shippingbox.fill", "tree.fill", "exclamationmark.triangle.fill", "tshirt.fill", "bolt.fill",
        "drop.fill", "hammer.fill", "paintpalette.fill", "flame.fill", "arrow.3.trianglepath", "cart.fill", "car.fill",
    ]
    public static let homeSymbols: [String] = [
        "house.fill", "house.and.flag.fill", "building.2.fill", "tent.fill", "tree.fill", "car.fill", "building.columns.fill", "leaf.fill", "sailboat.fill", "mountain.2.fill",
    ]
    public static let eventSymbols: [String] = [
        "heart.fill", "car.fill", "flame.fill", "wrench.and.screwdriver.fill", "stethoscope", "creditcard.fill", "pawprint.fill", "drop.fill", "bolt.fill", "key.fill", "bell.fill", "star.fill",
    ]
}
