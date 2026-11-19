import SwiftUI
import TonneCore

/// „Mehr › Schrift“: Schriftart der App – gilt auch für Widgets und die Apple Watch. Die Größe folgt der iOS-Textgröße.
struct TypographyView: View {
    @AppStorage private var family: String
    @Environment(\.colorScheme) private var scheme

    init() {
        _family = AppStorage(wrappedValue: TypographySettings.Family.rounded.rawValue, TypographySettings.familyKey, store: SettingsKeys.typographyStore)
    }

    private func name(_ family: TypographySettings.Family) -> String {
        switch family {
        case .rounded: L10n.t("Abgerundet", "Rounded")
        case .standard: L10n.t("Standard (SF Pro)", "Standard (SF Pro)")
        case .serif: L10n.t("Serif (New York)", "Serif (New York)")
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(TypographySettings.Family.allCases, id: \.self) { option in
                    Button { family = option.rawValue } label: {
                        HStack {
                            // fontDesign direkt am Text: Die Umgebung allein setzte sich gegen die Schrift der App nicht
                            // durch, alle Zeilen standen in derselben Schrift (im Simulator gesehen, 19.11.2026)
                            Text(name(option)).tonneFont(.body).fontDesign(TypographySettings(family: option).design).foregroundStyle(.primary)
                            Spacer()
                            if family == option.rawValue { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        // Jede Zeile in ihrer eigenen Schriftart, damit man sieht, was man wählt
                        .environment(\.typography, TypographySettings(family: option))
                    }
                    .accessibilityAddTraits(family == option.rawValue ? .isSelected : [])
                }
            } header: {
                Text(L10n.t("Schriftart", "Typeface"))
            } footer: {
                Text(L10n.t("Gilt auch für Widgets und die Apple Watch. Die Größe folgt der Textgröße von iOS (Einstellungen › Anzeige & Helligkeit › Textgröße).",
                            "Also applies to widgets and Apple Watch. The size follows the iOS text size (Settings › Display & Brightness › Text Size)."))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Morgen", "Tomorrow")).tonneFont(size: 15, .heavy).foregroundStyle(KlarStyle.muted(scheme))
                    Text(L10n.t("Restmüll rausstellen", "Put out residual waste")).tonneFont(size: 28, .black).foregroundStyle(KlarStyle.text(scheme))
                    Text(L10n.t("Abholung ab 6 Uhr · Musterstraße", "Collection from 6 am · Sample Street")).tonneFont(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            } header: {
                Text(L10n.t("Vorschau", "Preview"))
            }
        }
        .navigationTitle(L10n.t("Schrift", "Font"))
        .onChange(of: family) { _, _ in
            SnapshotStore.reloadWidgets()
            WatchSync.shared.resendTypography()
        }
    }
}
