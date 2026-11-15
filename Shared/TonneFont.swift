import SwiftUI
import TonneCore

// Eine Stelle für alle Schriften in App, Widget und Watch. Jede Textangabe läuft über `.tonneFont(...)`:
// die Schriftart kommt aus der Einstellung „Schrift“, die Größe folgt der iOS-Textgröße (nach oben begrenzt).
// Grundeinstellung (Abgerundet, iOS-Textgröße „Standard“) sieht aus wie bis 2.0.11.

extension TypographySettings {
    var design: Font.Design {
        switch family {
        case .rounded: .rounded
        case .standard: .default
        case .serif: .serif
        }
    }
}

private struct TypographyKey: EnvironmentKey {
    static let defaultValue = TypographySettings.standard
}

private struct TypographyRootKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var typography: TypographySettings {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }

    /// Schon eine Wurzel darüber? Dann nicht noch einmal verschieben (Sheets erben die Umgebung nicht immer).
    fileprivate var typographyRootApplied: Bool {
        get { self[TypographyRootKey.self] }
        set { self[TypographyRootKey.self] = newValue }
    }
}

private extension Font.TextStyle {
    /// Gewicht, das iOS dem Textstil von sich aus gibt.
    var defaultWeight: Font.Weight { self == .headline ? .semibold : .regular }
}

/// Setzt eine Schrift aus der zentralen Einstellung.
struct TonneFontModifier: ViewModifier {
    enum Base { case style(Font.TextStyle), size(CGFloat) }

    let base: Base
    let weight: Font.Weight?
    /// Feste Größen aus der Gestalt (z. B. Ziffer auf der Tonne) wachsen nicht mit, sie wechseln nur Schriftart und Gewicht.
    let scales: Bool

    @Environment(\.typography) private var typography
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View { content.font(font) }

    private var font: Font {
        switch base {
        case .style(let style):
            return .system(style, design: typography.design, weight: weight ?? style.defaultWeight)
        case .size(let size):
            let index = DynamicTypeSize.allCases.firstIndex(of: dynamicTypeSize) ?? TypographySettings.defaultSizeIndex
            let factor = scales ? TypographySettings.scale(sizeIndex: index, baseSize: size) : 1
            return .system(size: size * factor, weight: weight ?? .regular, design: typography.design)
        }
    }
}

extension View {
    /// Textstil von iOS (`.caption`, `.headline` …) in der gewählten Schrift.
    func tonneFont(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> some View {
        modifier(TonneFontModifier(base: .style(style), weight: weight, scales: true))
    }

    /// Feste Punktgröße der Gestaltung; wächst mit der Textgröße (große Zahlen gedämpft).
    func tonneFont(size: CGFloat, _ weight: Font.Weight = .bold) -> some View {
        modifier(TonneFontModifier(base: .size(size), weight: weight, scales: true))
    }

    /// Feste Größe, die an der Gestalt hängt (Tonnen-Ziffer, Avatar-Initialen) und nicht mitwachsen darf.
    func tonneFont(fixed size: CGFloat, _ weight: Font.Weight = .bold) -> some View {
        modifier(TonneFontModifier(base: .size(size), weight: weight, scales: false))
    }

    /// An jede Wurzel (App, Widget, Watch): liest die Einstellung, begrenzt die Textgröße nach oben
    /// und gibt die Schrift an alles darunter weiter – auch an Texte ohne eigene Angabe (Schaltflächen, Listen).
    func tonneTypography(store: UserDefaults = SnapshotStore.defaults, maxSize: DynamicTypeSize = .xxxLarge) -> some View {
        modifier(TonneTypographyRoot(store: store, maxSize: maxSize))
    }
}

struct TonneTypographyRoot: ViewModifier {
    @AppStorage private var family: String
    let maxSize: DynamicTypeSize
    @Environment(\.dynamicTypeSize) private var systemSize
    @Environment(\.typographyRootApplied) private var alreadyApplied

    init(store: UserDefaults, maxSize: DynamicTypeSize) {
        _family = AppStorage(wrappedValue: TypographySettings.Family.rounded.rawValue, TypographySettings.familyKey, store: store)
        self.maxSize = maxSize
    }

    private var settings: TypographySettings {
        TypographySettings(family: .init(rawValue: family) ?? .rounded)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if alreadyApplied {
            content
        } else {
            let all = DynamicTypeSize.allCases
            let system = all.firstIndex(of: systemSize) ?? TypographySettings.defaultSizeIndex
            let index = TypographySettings.sizeIndex(system: system, maxIndex: all.firstIndex(of: maxSize) ?? all.count - 1)
            content
                .environment(\.typography, settings)
                .environment(\.typographyRootApplied, true)
                .fontDesign(settings.design)
                .dynamicTypeSize(all[index])
        }
    }
}
