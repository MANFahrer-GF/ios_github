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
    private var items: [WidgetSnapshot.PickupItem] { next?.items ?? [] }
    private var shortWhen: String {
        guard let days else { return "–" }
        switch days {
        case 0: return L10n.t("heute", "today")
        case 1: return L10n.t("morgen", "tmrw")
        default: return "\(days) T."
        }
    }
    private var symbol: String { items.first?.displaySymbol ?? "checkmark.circle" }
    private var names: String { items.isEmpty ? L10n.t("Keine Abholung", "No pickup") : items.map(\.name).joined(separator: " + ") }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(Image.waste(symbol, name: items.first?.name ?? "")) \(next == nil ? names : "\(DateText.countdown(next!.date)): \(names)")")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCorner:
            Image.waste(symbol, name: items.first?.name ?? "").font(.title3).widgetAccentable()
                .widgetLabel { Text(next == nil ? "–" : "\(shortWhen) · \(names)") }
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            rectangular
                .containerBackground(for: .widget) { Color.clear }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    if items.count > 1 {
                        Text("\(items.count)").font(.system(size: 18, weight: .black, design: .rounded)).widgetAccentable()
                    } else {
                        Image.waste(symbol, name: items.first?.name ?? "").font(.title3).widgetAccentable()
                    }
                    Text(shortWhen).font(.system(size: 11, weight: .heavy, design: .rounded))
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        }
    }

    /// Kopf mit Countdown, danach jede Tonne in einer eigenen Zeile.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(next == nil ? L10n.t("Nichts offen", "Nothing due") : DateText.countdown(next!.date))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .widgetAccentable()
                if let next, next.done {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
            }
            ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Image.waste(item.displaySymbol, name: item.name).font(.caption2).foregroundStyle(Color(hex: item.colorHex))
                    Text(item.name).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                }
            }
            if items.count > 2 {
                Text(L10n.t("+\(items.count - 2) weitere", "+\(items.count - 2) more")).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }
}
