import SwiftUI
import UIKit
import TonneCore

/// Navigationstitel zeichnet UIKit – sie folgen `.tonneFont` nicht. Ohne Abgleich stünde über rundem oder Serif-Inhalt
/// ein SF-Pro-Titel („zwei Schriften“). Nur die Titel-Schrift wird gesetzt, Hintergrund und Glas der Leiste bleiben.
struct NavigationBarTypographySync: ViewModifier {
    @Environment(\.typography) private var typography
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .onAppear { NavigationBarTypography.apply(typography, size: dynamicTypeSize) }
            .onChange(of: typography) { _, value in NavigationBarTypography.apply(value, size: dynamicTypeSize) }
            .onChange(of: dynamicTypeSize) { _, value in NavigationBarTypography.apply(typography, size: value) }
    }
}

extension View {
    /// Schrift-Wurzel der App. Auch an jeden Sheet-Inhalt: Sheets erben Schriftart und Größengrenze nicht von der Wurzel.
    func appTypography() -> some View { tonneTypography(store: SettingsKeys.typographyStore) }
}

enum NavigationBarTypography {
    @MainActor
    static func apply(_ typography: TypographySettings, size: DynamicTypeSize) {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let design: UIFontDescriptor.SystemDesign = switch typography.family {
        case .rounded: .rounded
        case .standard: .default
        case .serif: .serif
        }
        func font(_ style: UIFont.TextStyle, _ weight: Font.Weight) -> UIFont {
            let pointSize = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
            let base = UIFont.systemFont(ofSize: pointSize, weight: uiWeight(weight))
            return UIFont(descriptor: base.fontDescriptor.withDesign(design) ?? base.fontDescriptor, size: pointSize)
        }
        let large: [NSAttributedString.Key: Any] = [.font: font(.largeTitle, .bold)]
        let inline: [NSAttributedString.Key: Any] = [.font: font(.headline, .semibold)]
        UINavigationBar.appearance().largeTitleTextAttributes = large
        UINavigationBar.appearance().titleTextAttributes = inline
        // Schon sichtbare Leisten sofort mitziehen (das Erscheinungsbild-Proxy wirkt nur auf neue)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { update(window, large: large, inline: inline) }
        }
    }

    private static func update(_ view: UIView, large: [NSAttributedString.Key: Any], inline: [NSAttributedString.Key: Any]) {
        if let bar = view as? UINavigationBar {
            bar.largeTitleTextAttributes = large
            bar.titleTextAttributes = inline
        }
        view.subviews.forEach { update($0, large: large, inline: inline) }
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
