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
                WasteIcon(symbolName: symbolName, name: name, size: width * 0.42)
                Text(ShortName.bin(name)).font(.system(size: max(7, width * 0.2), weight: .heavy)).tracking(0.3).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(HexLuma.glyphColor(on: colorHex))
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

// MARK: - Aurora (kräftige Variante für Widgets und Übersichtskarte)

/// Hell oder dunkel? Für die Schriftfarbe auf einer Tonne (Gelb braucht dunkle Schrift).
enum HexLuma {
    static func isLight(_ hex: String) -> Bool {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count >= 6, let number = UInt32(value.prefix(6), radix: 16) else { return false }
        let r = Double((number >> 16) & 0xFF) / 255, g = Double((number >> 8) & 0xFF) / 255, b = Double(number & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.62
    }

    /// Farbe für ein Symbol auf einem Kreis in `hex`: dunkel auf hellen Farben (Gelb), sonst weiß.
    static func glyphColor(on hex: String) -> Color {
        isLight(hex) ? Color(hex: "#2A2210") : .white
    }
}

/// Dunkles Glas mit Farbnebel in den Farben der Tonnen. Bleibt in Hell und Dunkel gleich,
/// damit die Tonnen auf jedem Hintergrund leuchten.
struct AuroraSurface: View {
    var hexes: [String]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let first = Color(hex: hexes.first ?? HeroPalette.idle)
            let second = Color(hex: hexes.dropFirst().first ?? hexes.first ?? HeroPalette.idle)
            ZStack {
                Color(hex: "#0F1218")
                Circle().fill(first)
                    .frame(width: h * 1.05, height: h * 1.05)
                    .blur(radius: h * 0.22)
                    .opacity(0.72)
                    .position(x: h * 0.18, y: h * 0.02)
                Circle().fill(second)
                    .frame(width: h * 0.95, height: h * 0.95)
                    .blur(radius: h * 0.24)
                    .opacity(0.5)
                    .position(x: w - h * 0.12, y: h * 1.02)
                LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.24)], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// Eine Mülltonne mit Deckel, Rillen und Rädern in ihrer Farbe, beschriftet mit dem Kurznamen.
struct TrashBinView: View {
    let name: String
    let colorHex: String
    var width: CGFloat = 40

    var body: some View {
        let color = Color(hex: colorHex)
        let label = HexLuma.isLight(colorHex) ? Color(hex: "#1B1F27") : Color.white
        VStack(spacing: 0) {
            // Deckel
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .fill(color)
                .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.2)).frame(height: width * 0.06) }
                .clipShape(RoundedRectangle(cornerRadius: width * 0.12, style: .continuous))
                .frame(width: width * 1.08, height: width * 0.24)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                .zIndex(1)
            // Korpus
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: width * 0.06, bottomLeadingRadius: width * 0.2,
                                       bottomTrailingRadius: width * 0.2, topTrailingRadius: width * 0.06, style: .continuous)
                    .fill(color)
                UnevenRoundedRectangle(topLeadingRadius: width * 0.06, bottomLeadingRadius: width * 0.2,
                                       bottomTrailingRadius: width * 0.2, topTrailingRadius: width * 0.06, style: .continuous)
                    .fill(LinearGradient(stops: [
                        .init(color: .black.opacity(0.26), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .white.opacity(0.2), location: 0.52),
                        .init(color: .clear, location: 0.74),
                        .init(color: .black.opacity(0.3), location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                HStack {
                    Capsule().fill(.black.opacity(0.14)).frame(width: max(1.5, width * 0.04))
                    Spacer()
                    Capsule().fill(.black.opacity(0.14)).frame(width: max(1.5, width * 0.04))
                }
                .padding(.horizontal, width * 0.2)
                .padding(.vertical, width * 0.16)
                Text(ShortName.bin(name))
                    .font(.system(size: max(7, width * 0.19), weight: .black))
                    .tracking(0.3)
                    .foregroundStyle(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
            }
            .frame(width: width, height: width * 0.92)
            .shadow(color: .black.opacity(0.4), radius: width * 0.12, x: 0, y: width * 0.1)
            // Räder
            HStack {
                Capsule().fill(Color(hex: "#1B1F27")).frame(width: width * 0.24, height: width * 0.15)
                Spacer()
                Capsule().fill(Color(hex: "#1B1F27")).frame(width: width * 0.24, height: width * 0.15)
            }
            .frame(width: width * 0.76)
            .offset(y: -width * 0.05)
        }
        .frame(width: width * 1.08, height: width * 1.26)
    }
}

/// Reihe aus Tonnen mit fester Anzahl Plätze; bei Überlauf wird der letzte Platz „+n“.
struct TrashBinRow: View {
    let items: [BinTileItem]
    var slots: Int = 3
    var width: CGFloat = 40
    var spacing: CGFloat = 6

    private var shown: [BinTileItem] { items.count > slots ? Array(items.prefix(max(slots - 1, 1))) : items }
    private var rest: Int { items.count - shown.count }

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                TrashBinView(name: item.name, colorHex: item.colorHex, width: width)
            }
            if rest > 0 {
                Text("+\(rest)")
                    .font(.system(size: width * 0.34, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: width * 0.8, height: width * 1.26)
            }
        }
    }
}

// MARK: - „Klar“: ruhiges Design im Stil der Apple-Widgets (aktuelle Gestaltung)

enum KlarStyle {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }

    static func text(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#F5F5F7") : Color(hex: "#111114") }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#9A9AA4") : Color(hex: "#8A8A92") }
    static func hairline(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#2E2E34") : Color(hex: "#ECECF0") }
    static func base(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#1C1C20") : .white }
    static func buttonBackground(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#F5F5F7") : Color(hex: "#111114") }
    static func buttonForeground(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#111114") : .white }
    static let done = Color(hex: "#34C759")
    static let birthday = "#FF5FA2"

    /// Farbe für Überschriften in Tonnenfarbe: Gelb wird im hellen Modus abgedunkelt, damit es lesbar bleibt.
    static func ink(_ hex: String, _ scheme: ColorScheme) -> Color {
        guard scheme == .light, HexLuma.isLight(hex) else {
            if scheme == .dark, hex.uppercased() == "#8B5E34" { return Color(hex: "#D9A066") }
            return Color(hex: hex)
        }
        return HexLuma.scaled(hex, by: 0.72)
    }

    static func birthdayInk(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#FF6AA8") : Color(hex: "#E0287A") }
}

extension HexLuma {
    static func scaled(_ hex: String, by factor: Double) -> Color {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count >= 6, let number = UInt32(value.prefix(6), radix: 16) else { return Color(hex: hex) }
        let r = Double((number >> 16) & 0xFF) / 255 * factor
        let g = Double((number >> 8) & 0xFF) / 255 * factor
        let b = Double(number & 0xFF) / 255 * factor
        return Color(red: r, green: g, blue: b)
    }
}

/// Hintergrund: weiß bzw. dunkelgrau mit einem sanften Farbschleier oben in der Tonnenfarbe.
struct KlarSurface: View {
    var tintHex: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            KlarStyle.base(scheme)
            if let tintHex {
                LinearGradient(stops: [
                    .init(color: Color(hex: tintHex).opacity(scheme == .dark ? 0.26 : 0.16), location: 0),
                    .init(color: Color(hex: tintHex).opacity(0), location: 0.58),
                ], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// Farbiger Kreis mit Symbol – eine Tonne.
struct BinDot: View {
    let symbolName: String
    let colorHex: String
    var name: String = ""
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: colorHex))
            WasteIcon(symbolName: symbolName, name: name, size: size * 0.5)
                .foregroundStyle(HexLuma.glyphColor(on: colorHex))
        }
        .frame(width: size, height: size)
    }
}

/// Eine Zeile pro Tonne: Kreis + Name.
struct BinLine: View {
    let name: String
    let symbolName: String
    let colorHex: String
    var dot: CGFloat = 22
    var fontSize: CGFloat = 13
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: dot * 0.36) {
            BinDot(symbolName: symbolName, colorHex: colorHex, name: name, size: dot)
            Text(name).font(KlarStyle.font(fontSize, .heavy)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}

/// Mehrere kleine Farbpunkte überlappend (für „Danach“-Listen).
struct MiniDots: View {
    let hexes: [String]
    var size: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(Array(hexes.prefix(3).enumerated()), id: \.offset) { _, hex in
                Circle().fill(Color(hex: hex))
                    .overlay(Circle().strokeBorder(KlarStyle.base(scheme), lineWidth: max(1.5, size * 0.16)))
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Runder Knopf oben rechts: dunkel mit Haken, nach dem Tippen grün.
struct KlarCheckButtonLabel: View {
    var done: Bool
    var size: CGFloat = 28
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(done ? KlarStyle.done : KlarStyle.buttonBackground(scheme))
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(done ? .white : KlarStyle.buttonForeground(scheme))
        }
        .frame(width: size, height: size)
    }
}

/// Initialen im runden Verlauf.
struct KlarAvatar: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 26

    var body: some View {
        let color = Color(hex: colorHex)
        ZStack {
            Circle().fill(LinearGradient(colors: [color, HexLuma.scaled(colorHex, by: 1.0).opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(KlarStyle.font(size * 0.38, .black)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Mehrere Geburtstagskinder am selben Tag: Avatare leicht überlappend.
struct KlarAvatarStack: View {
    let people: [(initials: String, colorHex: String)]
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(Array(people.prefix(3).enumerated()), id: \.offset) { _, person in
                KlarAvatar(initials: person.initials, colorHex: person.colorHex, size: size)
                    .overlay(Circle().strokeBorder(KlarStyle.base(scheme), lineWidth: max(1.5, size * 0.06)))
            }
        }
    }
}

extension Array where Element == WidgetSnapshot.BirthdayItem {
    /// Alle Geburtstage am Tag des ersten Eintrags (z. B. Zwillinge oder zwei Freunde am selben Tag).
    /// Die Liste ist nach Datum sortiert; passend zu `dropFirst(firstDay.count)` zählen nur die Einträge vorne.
    var firstDay: [WidgetSnapshot.BirthdayItem] {
        guard let first = first else { return [] }
        return Array(prefix { Calendar.current.isDate($0.date, inSameDayAs: first.date) })
    }

    /// Namen kurz zusammengefasst: „Oma Erika, Paul“ bzw. „Oma Erika, Paul +1“.
    func names(max: Int = 2) -> String {
        ReminderPlanner.shortNames(map(\.name), max: max)
    }
}
