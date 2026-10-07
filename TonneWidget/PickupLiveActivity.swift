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
                    Image(systemName: context.state.symbolNames.first ?? "trash.fill").font(.title2).foregroundStyle(Color(hex: context.state.colorHexes.first ?? "#F2C230"))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.done {
                        Button(intent: MarkPickupDoneIntent(dayKey: context.attributes.dayKey)) { Image(systemName: "checkmark.circle.fill").font(.title2) }.buttonStyle(.plain).tint(.green)
                    } else {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.done ? "Steht draußen 👍" : (Days.until(context.attributes.pickupDate) == 0 ? "Heute wird abgeholt" : "Heute Abend rausstellen")).font(.headline)
                        Text(ReminderPlanner.joinNames(context.state.names)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbolNames.first ?? "trash.fill").foregroundStyle(Color(hex: context.state.colorHexes.first ?? "#F2C230"))
            } compactTrailing: {
                Text(context.state.done ? "✓" : (Days.until(context.attributes.pickupDate) == 0 ? "heute" : "morgen")).font(.caption2.weight(.semibold))
            } minimal: {
                Image(systemName: context.state.done ? "checkmark.circle.fill" : (context.state.symbolNames.first ?? "trash.fill"))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<PickupActivityAttributes>) -> some View {
        let color = Color(hex: context.state.colorHexes.first ?? "#F2C230")
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.25))
                Image(systemName: context.state.symbolNames.first ?? "trash.fill").font(.title2).foregroundStyle(color)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.done ? "Alles steht draußen 👍" : (Days.until(context.attributes.pickupDate) == 0 ? "Heute wird abgeholt" : "Heute Abend rausstellen!")).font(.headline)
                Text(ReminderPlanner.joinNames(context.state.names) + (context.attributes.locationName.map { " · \($0)" } ?? "")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if !context.state.done {
                Button(intent: MarkPickupDoneIntent(dayKey: context.attributes.dayKey)) {
                    Label("Erledigt", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(color.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
    }
}
