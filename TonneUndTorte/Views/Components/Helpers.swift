import SwiftUI
import UIKit

// MARK: - Farben

extension Color {
    /// Erzeugt eine Farbe aus „#RRGGBB“ oder „#RRGGBBAA“.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "#", with: "")
        if cleaned.count == 6 { cleaned += "FF" }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 24) & 0xFF) / 255
        let green = Double((value >> 16) & 0xFF) / 255
        let blue = Double((value >> 8) & 0xFF) / 255
        let alpha = Double(value & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// „#RRGGBB“-Darstellung der Farbe.
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}

// MARK: - Datum

enum DateText {
    static func daysUntil(_ date: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: day).day ?? 0
    }

    /// „Heute“, „Morgen“, „Übermorgen“, „in 5 Tagen“, „vor 2 Tagen“
    static func countdown(_ date: Date, calendar: Calendar = .current) -> String {
        let diff = daysUntil(date, calendar: calendar)
        switch diff {
        case 0: return "Heute"
        case 1: return "Morgen"
        case 2: return "Übermorgen"
        case -1: return "Gestern"
        case ..<0: return "vor \(-diff) Tagen"
        default: return "in \(diff) Tagen"
        }
    }

    /// „Heute“, „Morgen“, sonst Wochentag + Datum: „Di., 14. Okt.“
    static func relativeDay(_ date: Date, calendar: Calendar = .current) -> String {
        let diff = daysUntil(date, calendar: calendar)
        switch diff {
        case 0: return "Heute"
        case 1: return "Morgen"
        default: return short(date)
        }
    }

    /// „Di., 14. Okt.“
    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// „Dienstag, 14. Oktober 2026“
    static func long(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    /// „14. Oktober“
    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }

    /// „Oktober 2026“
    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

// MARK: - Uhrzeit (Minuten seit Mitternacht ↔ Date)

enum TimeOfDay {
    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: base) ?? base
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// Uhrzeit-Auswahl, die ihren Wert als Minuten seit Mitternacht speichert (für @AppStorage).
struct TimeOfDayPicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { TimeOfDay.date(fromMinutes: minutes) },
                set: { minutes = TimeOfDay.minutes(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }
}

// MARK: - Karten & Bausteine

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// Farbiger Kreis mit Symbol – das Markenzeichen jeder Müllart und jedes Standorts.
struct SymbolBadge: View {
    let symbolName: String
    let colorHex: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: colorHex), Color(hex: colorHex).opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: colorHex).opacity(0.35), radius: 6, x: 0, y: 3)
    }
}

/// Kleiner farbiger Chip mit Symbol und Text, z. B. „Gelber Sack · Gifhorn“.
struct EventChip: View {
    let event: CalendarEvent
    var onLight: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: event.symbolName)
                .font(.caption.weight(.semibold))
            Text(event.title)
                .font(.caption.weight(.semibold))
            if let location = event.locationName {
                Text("· \(location)")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(onLight ? event.color.opacity(0.15) : Color.white.opacity(0.22), in: Capsule())
        .foregroundStyle(onLight ? event.color : .white)
    }
}

/// Zeile mit Badge, Titel und Untertitel – für Listen von Terminen.
struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbolName: event.symbolName, colorHex: event.colorHex, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                Text(event.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if event.kind == .birthday {
                Text("🎂")
            }
        }
    }
}

/// Auswahl aus der Farbpalette.
struct PaletteColorPicker: View {
    @Binding var colorHex: String

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(PaletteColors.all, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 36, height: 36)
                    .overlay {
                        if hex.uppercased() == colorHex.uppercased() {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { colorHex = hex }
            }
            ColorPicker("", selection: Binding(
                get: { Color(hex: colorHex) },
                set: { colorHex = $0.hexString }
            ))
            .labelsHidden()
            .frame(width: 36, height: 36)
        }
    }
}

/// Auswahl eines SF Symbols.
struct SymbolPicker: View {
    @Binding var symbolName: String
    let colorHex: String
    var symbols: [String] = WasteSymbols.all

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(symbol == symbolName ? Color(hex: colorHex).opacity(0.2) : Color(.tertiarySystemFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(symbol == symbolName ? Color(hex: colorHex) : .clear, lineWidth: 2)
                    )
                    .foregroundStyle(symbol == symbolName ? Color(hex: colorHex) : .primary)
                    .onTapGesture { symbolName = symbol }
            }
        }
    }
}

// MARK: - Standortfilter (Übersicht & Kalender teilen sich die Auswahl)

enum LocationFilter {
    static let key = "filter.locationID"

    static func apply(_ types: [WasteType], filterID: String) -> [WasteType] {
        guard !filterID.isEmpty, let uuid = UUID(uuidString: filterID) else { return types }
        return types.filter { $0.location?.id == uuid }
    }
}

/// Menü zum Umschalten zwischen „Alle Standorte“ und einem einzelnen Standort.
struct LocationFilterMenu: View {
    let locations: [Location]
    @AppStorage(LocationFilter.key) private var filterID: String = ""

    var body: some View {
        if locations.count > 1 {
            Menu {
                Picker("Standort", selection: $filterID) {
                    Label("Alle Standorte", systemImage: "square.grid.2x2").tag("")
                    ForEach(locations) { location in
                        Label(location.name, systemImage: location.symbolName).tag(location.id.uuidString)
                    }
                }
            } label: {
                Image(systemName: filterID.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
    }
}
