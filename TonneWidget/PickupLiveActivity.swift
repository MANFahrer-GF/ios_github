import ActivityKit
import WidgetKit
import SwiftUI
import TonneCore

/// Live-Aktivität „Tonne rausstellen“ – Sperrbildschirm und Dynamic Island.
struct PickupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupActivityAttributes.self) { context in
            lockScreen(context).tonneTypography(maxSize: .xLarge)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BinStack(bins: bins(context), size: 28).tonneTypography(maxSize: .xLarge)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if !context.state.done {
                            Button(intent: MarkPickupDoneIntent(dayKey: context.attributes.dayKey)) { Image(systemName: "checkmark.circle.fill").tonneFont(.title2) }.buttonStyle(.plain).tint(.green)
                        } else {
                            Button(intent: UndoPickupDoneIntent(dayKey: context.attributes.dayKey)) { Image(systemName: "arrow.uturn.backward.circle.fill").tonneFont(.title2) }.buttonStyle(.plain).tint(.secondary)
                        }
                    }.tonneTypography(maxSize: .xLarge)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(headline(context)).tonneFont(.headline)
                        Text(ReminderPlanner.joinNames(shownNames(context))).tonneFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.tonneTypography(maxSize: .xLarge)
                }
            } compactLeading: {
                BinStack(bins: bins(context), size: 18).tonneTypography(maxSize: .large)
            } compactTrailing: {
                Text(context.state.done ? "✓" : (Days.until(context.attributes.pickupDate) == 0 ? "heute" : "morgen")).tonneFont(.caption2, .semibold).tonneTypography(maxSize: .large)
            } minimal: {
                Group {
                    if context.state.done {
                        Image(systemName: "checkmark.circle.fill")
                    } else {
                        WasteIcon(symbolName: context.state.symbolNames.first ?? "trash.fill", name: context.state.names.first ?? "", size: 15)
                    }
                }.tonneTypography(maxSize: .large)
            }
        }
    }

    /// Unter „rausstellen“ nur, was rausgestellt wird – das Schadstoffmobil kommt per Morgen-Erinnerung.
    private func shownNames(_ context: ActivityViewContext<PickupActivityAttributes>) -> [String] {
        let wording = PickupWording(names: context.state.names, symbols: context.state.symbolNames)
        return wording.onlyBringTo ? wording.items.map(\.name) : wording.outNames
    }

    /// „Heute Abend rausstellen“ – beim Sack „bereitstellen“, beim Schadstoffmobil „hinbringen“, nie „Tonne“ ohne Tonne.
    private func headline(_ context: ActivityViewContext<PickupActivityAttributes>) -> String {
        let wording = PickupWording(names: context.state.names, symbols: context.state.symbolNames)
        if context.state.done { return wording.onlyBringTo ? L10n.t("Erledigt 👍", "Done 👍") : L10n.t("Steht draußen 👍", "It's out 👍") }
        let today = Days.until(context.attributes.pickupDate) == 0
        if wording.onlyBringTo { return today ? L10n.t("Heute hinbringen", "Drop off today") : L10n.t("Morgen hinbringen", "Drop off tomorrow") }
        return today ? L10n.t("Heute wird abgeholt", "Collected today") : L10n.t("Heute Abend rausstellen", "Put out tonight")
    }

    private func bins(_ context: ActivityViewContext<PickupActivityAttributes>) -> [BinRef] {
        context.state.symbolNames.indices.compactMap { index in
            guard index < context.state.colorHexes.count else { return nil }
            let name = index < context.state.names.count ? context.state.names[index] : ""
            return BinRef(symbolName: context.state.symbolNames[index], colorHex: context.state.colorHexes[index], name: name)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<PickupActivityAttributes>) -> some View {
        let color = HeroPalette.tint(for: context.state.colorHexes) ?? Color(hex: HeroPalette.neutralTop)
        let subtitle = ReminderPlanner.joinNames(shownNames(context)) + (context.attributes.locationName.map { " · \($0)" } ?? "")
        return HStack(spacing: 14) {
            BinStack(bins: bins(context), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline(context)).tonneFont(.headline)
                Text(subtitle).tonneFont(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if !context.state.done {
                Button(intent: MarkPickupDoneIntent(dayKey: context.attributes.dayKey)) {
                    Label("Erledigt", systemImage: "checkmark.circle.fill").tonneFont(.subheadline, .semibold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(color.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: UndoPickupDoneIntent(dayKey: context.attributes.dayKey)) {
                    Label("Rückgängig", systemImage: "arrow.uturn.backward").tonneFont(.caption, .semibold)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
    }
}
