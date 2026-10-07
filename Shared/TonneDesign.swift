import SwiftUI
import TonneCore

// Gemeinsame Gestaltung „Tag & Nacht“ für Widget, Übersichtskarte und Watch:
// dunkles Glas im Dunkelmodus, frische helle Karte im Hellmodus. Tonnen sind farbige Kacheln,
// Geburtstage bekommen einen Initialen-Avatar. Alle Elemente haben feste Zonen, nichts überlappt.

// MARK: - Farben

enum DesignColor {
    static let darkTop = "#2A3245"
    static let darkMid = "#161B26"
    static let darkBottom = "#0E1117"
    static let lightTop = "#FFFDF8"
    static let lightBottom = "#F6F3EA"
    static let birthday = "#FF5FA2"
    static let birthdayWarm = "#FF9A4A"

    static func text(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : Color(hex: "#15161A") }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.62) : Color(hex: "#7B7B82") }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#4ADE95") : Color(hex: "#1F9D5F") }
    static func hairline(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.12) : Color(hex: "#E6E1D4") }
    static func button(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.14) : Color(hex: "#15161A") }
    static func tileMore(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.14) : Color(hex: "#15161A").opacity(0.08) }
}

// MARK: - Fläche

/// Hintergrund der Karte: Verlauf je nach Modus plus sanftes Leuchten unten links in der Farbe der ersten Tonne.
struct DesignSurface: View {
    var glowHex: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(colors: [Color(hex: DesignColor.darkTop), Color(hex: DesignColor.darkMid), Color(hex: DesignColor.darkBottom)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                LinearGradient(colors: [Color(hex: DesignColor.lightTop), Color(hex: DesignColor.lightBottom)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if let glowHex {
                RadialGradient(colors: [Color(hex: glowHex).opacity(scheme == .dark ? 0.42 : 0.26), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 180)
            }
        }
    }
}

// MARK: - Bausteine

/// Kurzname für die Kachel: „Gelber Sack“ → GELB, „Restmüll“ → REST.
enum ShortName {
    private static let table: [(String, String)] = [
        ("gelb", "GELB"), ("wertstoff", "GELB"), ("leichtverpack", "GELB"), ("verpack", "GELB"),
        ("rest", "REST"), ("hausmüll", "REST"), ("graue", "REST"), ("schwarze", "REST"),
        ("bio", "BIO"), ("grünabfall", "GRÜN"), ("grüngut", "GRÜN"), ("grünschnitt", "GRÜN"), ("garten", "GARTEN"), ("laub", "LAUB"),
        ("papier", "PAPIER"), ("pappe", "PAPIER"), ("blaue", "PAPIER"),
        ("sperr", "SPERR"), ("glas", "GLAS"), ("schadstoff", "SCHAD"), ("problem", "SCHAD"),
        ("weihnachtsb", "BAUM"), ("tannenb", "BAUM"), ("christb", "BAUM"),
        ("elektro", "ELEKTRO"), ("textil", "TEXTIL"), ("kleider", "TEXTIL"), ("altkleider", "TEXTIL"),
    ]

    static func bin(_ name: String) -> String {
        let lower = name.lowercased()
        for (key, value) in table where lower.contains(key) { return value }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return String(first.prefix(7)).uppercased()
    }
}

/// Eine Tonne als farbige Kachel mit Symbol und Kurznamen.
struct BinTileView: View {
    let name: String
    let symbolName: String
    let colorHex: String
    var width: CGFloat = 40
    var height: CGFloat = 46

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.95), color], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            VStack(spacing: 3) {
                Image(systemName: symbolName).font(.system(size: width * 0.42, weight: .bold))
                Text(ShortName.bin(name)).font(.system(size: max(7, width * 0.2), weight: .heavy)).tracking(0.3).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 2)
        }
        .frame(width: width, height: height)
        .shadow(color: color.opacity(0.35), radius: 5, x: 0, y: 3)
    }
}

/// Kachel „+2“ für weitere Tonnen, die nicht mehr in die Reihe passen.
struct MoreTileView: View {
    let count: Int
    var width: CGFloat = 40
    var height: CGFloat = 46
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.3, style: .continuous).fill(DesignColor.tileMore(scheme))
            Text("+\(count)").font(.system(size: width * 0.32, weight: .heavy)).foregroundStyle(DesignColor.text(scheme))
        }
        .frame(width: width, height: height)
    }
}

/// Reihe aus Kacheln mit fester Anzahl Plätze. Passt nicht alles, wird der letzte Platz zur „+n“-Kachel.
struct BinTileRow: View {
    let items: [BinTileItem]
    var slots: Int = 3
    var width: CGFloat = 40
    var height: CGFloat = 46
    var spacing: CGFloat = 6

    private var shown: [BinTileItem] { items.count > slots ? Array(items.prefix(max(slots - 1, 1))) : items }
    private var rest: Int { items.count - shown.count }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                BinTileView(name: item.name, symbolName: item.symbolName, colorHex: item.colorHex, width: width, height: height)
            }
            if rest > 0 { MoreTileView(count: rest, width: width, height: height) }
        }
    }
}

struct BinTileItem: Hashable {
    let name: String
    let symbolName: String
    let colorHex: String
}

/// Kleine farbige Quadrate, für Listen der nächsten Tage.
struct BinDots: View {
    let hexes: [String]
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(hexes.prefix(4).enumerated()), id: \.offset) { _, hex in
                RoundedRectangle(cornerRadius: size * 0.33, style: .continuous).fill(Color(hex: hex)).frame(width: size, height: size)
            }
        }
    }
}

/// Initialen-Avatar für Geburtstage.
struct InitialsAvatar: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 46

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
            Text(initials).font(.system(size: size * 0.36, weight: .black)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.35), radius: size * 0.18, x: 0, y: size * 0.1)
    }
}

/// Runder Haken-Knopf (nur Optik, Aktion kommt von außen).
struct CheckCircleLabel: View {
    var size: CGFloat = 32
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(DesignColor.button(scheme))
            if scheme == .dark { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            Image(systemName: "checkmark").font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Pinke Kapsel für den Geburtstags-Countdown.
struct BirthdayPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(LinearGradient(colors: [Color(hex: DesignColor.birthday), Color(hex: DesignColor.birthdayWarm)], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Texte

enum PickupWords {
    /// „DO 8. OKT“, optional mit Standort.
    static func eyebrow(date: Date?, location: String? = nil) -> String {
        guard let date else { return L10n.t("ALLES RUHIG", "ALL QUIET") }
        var text = compactDate(date)
        if let location, !location.isEmpty { text += " · " + location.uppercased() }
        return text
    }

    static func compactDate(_ date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated)).replacingOccurrences(of: ".", with: "")
        let day = date.formatted(.dateTime.day())
        let month = date.formatted(.dateTime.month(.abbreviated)).replacingOccurrences(of: ".", with: "")
        return "\(weekday) \(day). \(month)".uppercased()
    }

    static func headline(days: Int?, done: Bool) -> String {
        guard let days else { return L10n.t("Nichts offen", "Nothing due") }
        if done { return L10n.t("Erledigt", "Done") }
        switch days {
        case 0: return L10n.t("Heute", "Today")
        case 1: return L10n.t("Morgen", "Tomorrow")
        case 2: return L10n.t("Übermorgen", "In 2 days")
        default: return L10n.t("In \(days) Tagen", "In \(days) days")
        }
    }

    static func subline(days: Int?, done: Bool) -> String {
        guard let days else { return L10n.t("keine Abholung geplant", "no pickup planned") }
        if done { return L10n.t("steht draußen 👍", "already out 👍") }
        switch days {
        case 0: return L10n.t("wird heute abgeholt", "collected today")
        case 1: return L10n.t("abends rausstellen", "put out tonight")
        default: return L10n.t("nächste Abholung", "next pickup")
        }
    }

    static func birthdaySubline(years: Int?, date: Date) -> String {
        let days = Days.until(date)
        if days == 0 {
            if let years { return L10n.t("wird heute \(years)!", "turns \(years) today!") }
            return L10n.t("hat heute Geburtstag!", "has a birthday today!")
        }
        if let years { return L10n.t("wird \(years) · \(DateText.short(date))", "turns \(years) · \(DateText.short(date))") }
        return DateText.short(date)
    }

    static func birthdayPill(date: Date) -> String {
        let days = Days.until(date)
        if days == 0 { return "🎉 " + L10n.t("HEUTE", "TODAY") }
        return "🎂 " + DateText.countdown(date).uppercased()
    }
}
