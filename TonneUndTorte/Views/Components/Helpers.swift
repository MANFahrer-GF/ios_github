import SwiftUI
import UIKit
import TonneCore

// MARK: - Farben

extension Color {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

// MARK: - Uhrzeit

enum TimeOfDay {
    static func date(fromMinutes minutes: Int) -> Date {
        Days.add(0, to: Days.today()).addingTimeInterval(TimeInterval(minutes * 60))
    }
    static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

struct TimeOfDayPicker: View {
    let title: String
    @Binding var minutes: Int
    var body: some View {
        DatePicker(title, selection: Binding(get: { TimeOfDay.date(fromMinutes: minutes) }, set: { minutes = TimeOfDay.minutes(from: $0) }), displayedComponents: .hourAndMinute)
    }
}

// MARK: - Karten

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

struct SymbolBadge: View {
    let symbolName: String
    let colorHex: String
    var size: CGFloat = 44
    /// Name der Abfallart. Gesetzt: eigenes Tonnen-Piktogramm statt SF Symbol (nicht für Orte).
    var wasteName: String? = nil
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: colorHex), Color(hex: colorHex).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Group {
                if let wasteName {
                    WasteIcon(symbolName: symbolName, name: wasteName, size: size * 0.45, weight: .semibold)
                } else {
                    Image(systemName: symbolName).font(.system(size: size * 0.45, weight: .semibold))
                }
            }
            .foregroundStyle(HexLuma.glyphColor(on: colorHex))
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: colorHex).opacity(0.35), radius: 6, x: 0, y: 3)
    }
}

struct InitialsBadge: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: colorHex), Color(hex: colorHex).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct EventChip: View {
    let event: CalendarEvent
    var onLight = false
    var showLocation = true
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 12
    var body: some View {
        HStack(spacing: 6) {
            if onLight {
                Group {
                    if event.kind == .waste {
                        WasteIcon(symbolName: event.symbolName, name: event.title, size: iconSize, weight: .semibold)
                    } else {
                        Image(systemName: event.symbolName).font(.system(size: iconSize, weight: .semibold))
                    }
                }
            } else {
                BinBadge(symbolName: event.symbolName, colorHex: event.colorHex, name: event.title, size: 22, waste: event.kind == .waste)
            }
            Text(event.title).font(.caption.weight(.semibold))
            if showLocation, let location = event.locationName { Text("· \(location)").font(.caption).opacity(0.8) }
            if event.done { Image(systemName: "checkmark.circle.fill").font(.caption) }
        }
        .padding(.leading, onLight ? 10 : 4).padding(.trailing, 10).padding(.vertical, onLight ? 6 : 4)
        .background(onLight ? event.color.opacity(0.15) : Color.white.opacity(0.16), in: Capsule())
        .foregroundStyle(onLight ? event.color : .white)
    }
}

struct EventRow: View {
    let event: CalendarEvent
    var body: some View {
        HStack(spacing: 12) {
            if event.kind == .birthday {
                InitialsBadge(initials: NameText.initials(event.title), colorHex: event.colorHex, size: 38)
            } else {
                SymbolBadge(symbolName: event.symbolName, colorHex: event.colorHex, size: 38, wasteName: event.kind == .waste ? event.title : nil)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.semibold))
                Text(event.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if event.kind == .birthday { Text(event.isMilestone ? "🎉" : "🎂") }
            if event.done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }
}

/// Einfaches Umbruch-Layout für Chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: maxWidth == .infinity ? totalWidth : maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Auswahl

struct PaletteColorPicker: View {
    @Binding var colorHex: String
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Palette.colors, id: \.self) { hex in
                Circle().fill(Color(hex: hex)).frame(width: 36, height: 36)
                    .overlay { if hex.uppercased() == colorHex.uppercased() { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) } }
                    .onTapGesture { colorHex = hex }
            }
            ColorPicker("", selection: Binding(get: { Color(hex: colorHex) }, set: { colorHex = $0.hexString })).labelsHidden().frame(width: 36, height: 36)
        }
    }
}

struct SymbolPicker: View {
    @Binding var symbolName: String
    let colorHex: String
    var symbols: [String] = Palette.wasteSymbols
    /// Gesetzt bei Abfallarten: Auswahl mit den eigenen Piktogrammen (Gelber Sack und Gelbe Tonne getrennt).
    /// Orte und Termine zeigen weiter SF Symbols.
    var wasteName: String? = nil
    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 10)]

    private var choices: [String] { wasteName == nil ? symbols : WasteGlyph.pickerSymbols }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(choices, id: \.self) { symbol in
                let isSelected = wasteName.map { WasteGlyph.matches(symbol, current: symbolName, name: $0) } ?? (symbol == symbolName)
                Group {
                    if wasteName != nil {
                        Image.waste(symbol).font(.title3)
                    } else {
                        Image(systemName: symbol).font(.title3)
                    }
                }
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Color(hex: colorHex).opacity(0.2) : Color(.tertiarySystemFill)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? Color(hex: colorHex) : .clear, lineWidth: 2))
                .foregroundStyle(isSelected ? Color(hex: colorHex) : .primary)
                .onTapGesture { symbolName = wasteName.map { WasteGlyph.storedName(for: symbol, name: $0) } ?? symbol }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Standortfilter

enum LocationFilter {
    static func apply(_ id: String) -> UUID? { UUID(uuidString: id) }
}

struct LocationFilterMenu: View {
    let locations: [Location]
    @AppStorage(SettingsKeys.locationFilter) private var filterID: String = ""
    var body: some View {
        if locations.count > 1 {
            Menu {
                Picker("Standort", selection: $filterID) {
                    Label("Alle Standorte", systemImage: "square.grid.2x2").tag("")
                    ForEach(locations) { Label($0.name, systemImage: $0.symbolName).tag($0.id.uuidString) }
                }
            } label: {
                Image(systemName: filterID.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
    }
}

/// Haptisches Feedback für „Erledigt“ & Co.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
