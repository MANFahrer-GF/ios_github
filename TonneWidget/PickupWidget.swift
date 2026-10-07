import WidgetKit
import SwiftUI
import AppIntents
import TonneCore

// MARK: - Konfiguration (Standort wählbar)

struct PickupWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Tonne & Torte"
    static var description = IntentDescription("Zeigt die nächste Abholung – wahlweise für einen Standort.")

    @Parameter(title: "Standort")
    var location: LocationEntity?
}

// MARK: - Timeline

struct PickupEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let locationName: String?
}

struct PickupTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PickupEntry {
        PickupEntry(date: Date(), snapshot: PickupTimelineProvider.sample, locationName: nil)
    }

    func snapshot(for configuration: PickupWidgetConfiguration, in context: Context) async -> PickupEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: PickupWidgetConfiguration, in context: Context) async -> Timeline<PickupEntry> {
        let now = Date()
        let entry = entry(for: configuration)
        // Zu jedem Tageswechsel und am Abend neu rendern
        var dates: [Date] = []
        let calendar = Calendar.current
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) { dates.append(midnight) }
        if let evening = calendar.nextDate(after: now, matching: DateComponents(hour: 17, minute: 0), matchingPolicy: .nextTime) { dates.append(evening) }
        let entries = [entry] + dates.sorted().map { PickupEntry(date: $0, snapshot: entry.snapshot, locationName: entry.locationName) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600)))
    }

    private func entry(for configuration: PickupWidgetConfiguration) -> PickupEntry {
        let full = SnapshotStore.load() ?? WidgetSnapshot()
        let filtered = full.filtered(locationID: configuration.location?.id)
        return PickupEntry(date: Date(), snapshot: filtered, locationName: configuration.location?.name)
    }

    static let sample: WidgetSnapshot = {
        let tomorrow = Days.add(1, to: Days.today())
        return WidgetSnapshot(
            locations: [],
            pickupDays: [
                .init(date: tomorrow, items: [.init(name: "Gelber Sack", symbolName: "bag.fill", colorHex: "#F2C230"), .init(name: "Restmüll", symbolName: "trash.fill", colorHex: "#5B6470")]),
                .init(date: Days.add(8, to: Days.today()), items: [.init(name: "Biotonne", symbolName: "leaf.fill", colorHex: "#8B5E34")]),
            ],
            birthdays: [.init(date: Days.add(3, to: Days.today()), name: "Oma Erika", years: 80, colorHex: "#EC4899", initials: "OE")]
        )
    }()
}

// MARK: - Widget

struct PickupWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "de.manfahrer.TonneUndTorte.pickup", intent: PickupWidgetConfiguration.self, provider: PickupTimelineProvider()) { entry in
            PickupWidgetView(entry: entry)
        }
        .configurationDisplayName("Nächste Abholung")
        .description("Welche Tonne muss raus? Mit „Erledigt“-Knopf.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct PickupWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PickupEntry

    private var next: WidgetSnapshot.PickupDay? { entry.snapshot.nextPickupDay(from: entry.date) }
    private var days: Int? { next.map { Days.until($0.date) } }
    private var heroColor: Color { Color(hex: next?.items.first?.colorHex ?? "#2F6FED") }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    // MARK: Texte

    private var eyebrow: String {
        guard let days else { return "ALLES RUHIG" }
        return days == 0 ? "HEUTE" : days == 1 ? "MORGEN" : "NÄCHSTE ABHOLUNG"
    }

    private var headline: String {
        guard let next, let days else { return "Keine Abholung" }
        if next.done { return "Steht draußen 👍" }
        return days == 0 ? "Heute wird abgeholt" : days == 1 ? "Heute Abend rausstellen!" : "In \(days) Tagen"
    }

    private func names(_ day: WidgetSnapshot.PickupDay, max: Int) -> String {
        let all = day.items.map(\.name)
        let shown = all.prefix(max).joined(separator: ", ")
        return all.count > max ? shown + " +\(all.count - max)" : shown
    }

    // MARK: Home-Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(eyebrow).font(.caption2.weight(.bold)).opacity(0.85)
                Spacer()
                Image(systemName: next?.items.first?.symbolName ?? "checkmark.circle.fill").font(.title3)
            }
            Text(headline).font(.headline).minimumScaleFactor(0.7).lineLimit(2)
            if let next {
                Text(names(next, max: 2)).font(.caption.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                HStack {
                    Text(DateText.short(next.date)).font(.caption2).opacity(0.85)
                    Spacer()
                    if !next.done, let days, days <= 1 { doneButton(next) }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { gradient }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow).font(.caption2.weight(.bold)).opacity(0.85)
                Text(headline).font(.title3.weight(.bold)).minimumScaleFactor(0.7).lineLimit(2)
                if let next {
                    chips(next.items)
                    Text(DateText.long(next.date)).font(.caption).opacity(0.85)
                }
                Spacer(minLength: 0)
                if let next, !next.done, let days, days <= 1 { doneButton(next) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.snapshot.pickupDays.filter { $0.date > (next?.date ?? .distantPast) }.prefix(3), id: \.date) { day in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(DateText.countdown(day.date)).font(.caption.weight(.semibold))
                        Text(names(day, max: 2)).font(.caption2).opacity(0.85).lineLimit(1)
                    }
                }
            }
            .frame(width: 118, alignment: .leading)
            .padding(8)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { gradient }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).font(.caption2.weight(.bold)).opacity(0.85)
                    Text(headline).font(.title2.weight(.bold)).minimumScaleFactor(0.7).lineLimit(2)
                }
                Spacer()
                Image(systemName: next?.items.first?.symbolName ?? "checkmark.circle.fill").font(.largeTitle)
            }
            if let next {
                chips(next.items)
                HStack {
                    Text(DateText.long(next.date)).font(.caption).opacity(0.85)
                    Spacer()
                    if !next.done, let days, days <= 1 { doneButton(next) }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.snapshot.pickupDays.filter { $0.date > (next?.date ?? .distantPast) }.prefix(5), id: \.date) { day in
                    HStack {
                        Text(DateText.countdown(day.date)).font(.caption.weight(.semibold)).frame(width: 80, alignment: .leading)
                        Text(names(day, max: 3)).font(.caption).opacity(0.9).lineLimit(1)
                        Spacer()
                        Text(DateText.short(day.date)).font(.caption2).opacity(0.7)
                    }
                }
            }
            .padding(10)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !entry.snapshot.birthdays.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🎂 GEBURTSTAGE").font(.caption2.weight(.bold)).opacity(0.85)
                    ForEach(entry.snapshot.birthdays.prefix(3), id: \.name) { birthday in
                        HStack {
                            Text(birthday.name + (birthday.years.map { " (\($0))" } ?? "")).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(DateText.countdown(birthday.date)).font(.caption2).opacity(0.85)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { gradient }
    }

    private var gradient: some View {
        LinearGradient(colors: [heroColor, heroColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func chips(_ items: [WidgetSnapshot.PickupItem]) -> some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(3), id: \.name) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.symbolName).font(.caption2)
                    Text(item.name).font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.22), in: Capsule())
                .lineLimit(1)
            }
        }
    }

    private func doneButton(_ day: WidgetSnapshot.PickupDay) -> some View {
        Button(intent: MarkPickupDoneIntent(dayKey: Days.iso(day.date))) {
            Label("Erledigt", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.white.opacity(0.25), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Sperrbildschirm

    private var inline: some View {
        Group {
            if let next { Text("\(Image(systemName: next.items.first?.symbolName ?? "trash.fill")) \(DateText.countdown(next.date)): \(names(next, max: 2))") }
            else { Text("Keine Abholung") }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: next?.items.first?.symbolName ?? "trash.fill").font(.title3)
                Text(days.map { $0 == 0 ? "heute" : $0 == 1 ? "morgen" : "\($0) T." } ?? "–").font(.caption2.weight(.semibold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let next {
                Text("\(DateText.countdown(next.date)): \(names(next, max: 2))").font(.headline).lineLimit(2)
                if let second = entry.snapshot.pickupDays.first(where: { $0.date > next.date }) {
                    Text("\(DateText.countdown(second.date)): \(names(second, max: 2))").font(.caption).opacity(0.8).lineLimit(1)
                }
            } else {
                Text("Keine Abholung").font(.headline)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
