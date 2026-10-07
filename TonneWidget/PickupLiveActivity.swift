import ActivityKit
import WidgetKit
import SwiftUI
import TonneCore

/// Live-Aktivität „Tonne rausstellen“ – Sperrbildschirm und Dynamic Island.
struct PickupLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BinStack(bins: bins(context), size: 28)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.done {
                        Button(intent: MarkPickupDoneIntent(dayKey: context.attributes.dayKey)) { Image(systemName: "checkmark.circle.fill").font(.title2) }.buttonStyle(.plain).tint(.green)
                    } else {
                        Button(intent: UndoPickupDoneIntent(dayKey: context.attributes.dayKey)) { Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2) }.buttonStyle(.plain).tint(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.done ? "Steht draußen 👍" : (Days.until(context.attributes.pickupDate) == 0 ? "Heute wird abgeholt" : "Heute Abend rausstellen")).font(.headline)
                        Text(ReminderPlanner.joinNames(context.state.names)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                BinStack(bins: bins(context), size: 18)
            } compactTrailing: {
                Text(context.state.done ? "✓" : (Days.until(context.attributes.pickupDate) == 0 ? "heute" : "morgen")).font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: context.state.done ? "checkmark.circle.fill" : (context.state.symbolNames.first ?? "trash.fill"))
            }
        }
    }

    private func bins(_ context: ActivityViewContext<PickupActivityAttributes>) -> [BinRef] {
        zip(context.state.symbolNames, context.state.colorHexes).map { BinRef(symbolName: $0, colorHex: $1) }
    }

    private func lockScreen(_ context: ActivityViewContext<PickupActivityAttributes>) -> some View {
        let color = HeroPalette.tint(for: context.state.colorHexes) ?? Color(hex: HeroPalette.neutralTop)
        let subtitle = ReminderPlanner.joinNames(context.state.names) + (context.attributes.locationName.map { " · \($0)" } ?? "")
        return HStack(spacing: 14) {
            BinStack(bins: bins(context), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.done ? "Alles steht draußen 👍" : (Days.until(context.attributes.pickupDate) == 0 ? "Heute wird abgeholt" : "Heute Abend rausstellen!")).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if !context.state.done {
                Button(intent: MarkPickupDoneIntent(dayKey: context.attributes.dayKey)) {
                    Label("Erledigt", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(color.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: UndoPickupDoneIntent(dayKey: context.attributes.dayKey)) {
                    Label("Zurück", systemImage: "arrow.uturn.backward").font(.caption.weight(.semibold))
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
