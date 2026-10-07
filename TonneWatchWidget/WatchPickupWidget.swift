import WidgetKit
import SwiftUI
import TonneCore

/// Komplikationen für die Zifferblätter: nächste Abholung.
struct WatchPickupEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WatchPickupProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPickupEntry {
        WatchPickupEntry(date: Date(), snapshot: WatchPickupProvider.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPickupEntry) -> Void) {
        completion(WatchPickupEntry(date: Date(), snapshot: SnapshotStore.load() ?? WatchPickupProvider.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPickupEntry>) -> Void) {
        let snapshot = SnapshotStore.load() ?? WidgetSnapshot()
        let now = Date()
        var entries = [WatchPickupEntry(date: now, snapshot: snapshot)]
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) {
            entries.append(WatchPickupEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    static let sample = WidgetSnapshot(pickupDays: [.init(date: Days.add(1, to: Days.today()), items: [.init(name: "Gelber Sack", symbolName: "bag.fill", colorHex: "#F2C230")])])
}

struct WatchPickupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.manfahrer.TonneUndTorte.watch.pickup", provider: WatchPickupProvider()) { entry in
            WatchPickupView(entry: entry)
        }
        .configurationDisplayName("Nächste Abholung")
        .description("Welche Tonne muss raus?")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct WatchPickupView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchPickupEntry

    private var next: WidgetSnapshot.PickupDay? { entry.snapshot.nextPickupDay(from: entry.date) }
    private var days: Int? { next.map { Days.until($0.date) } }
    private var shortWhen: String { days.map { $0 == 0 ? "heute" : $0 == 1 ? "morgen" : "\($0) T." } ?? "–" }
    private var symbol: String { next?.items.first?.symbolName ?? "trash.fill" }
    private var names: String { next.map { $0.items.map(\.name).joined(separator: ", ") } ?? "Keine Abholung" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(Image(systemName: symbol)) \(next == nil ? "Keine Abholung" : "\(DateText.countdown(next!.date)): \(names)")")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCorner:
            Image(systemName: symbol).font(.title3)
                .widgetLabel { Text(next == nil ? "–" : "\(shortWhen) · \(names)") }
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: symbol).foregroundStyle(Color(hex: next?.items.first?.colorHex ?? "#F2C230"))
                    Text(next == nil ? "Keine Abholung" : DateText.countdown(next!.date)).font(.headline)
                }
                Text(names).font(.caption2).lineLimit(2)
                if let next, next.done { Text("✓ steht draußen").font(.caption2).foregroundStyle(.green) }
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: symbol).font(.title3)
                    Text(shortWhen).font(.caption2.weight(.semibold))
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        }
    }
}
