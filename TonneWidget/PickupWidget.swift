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
    @Environment(\.colorScheme) private var scheme
    let entry: PickupEntry

    private var next: WidgetSnapshot.PickupDay? { entry.snapshot.nextPickupDay(from: entry.date) }
    private var days: Int? { next.map { Days.until($0.date) } }
    private var tiles: [BinTileItem] { (next?.items ?? []).map { BinTileItem(name: $0.name, symbolName: $0.symbolName, colorHex: $0.colorHex) } }
    private var later: [WidgetSnapshot.PickupDay] { entry.snapshot.pickupDays.filter { $0.date > (next?.date ?? .distantPast) } }
    /// Knopf nur, wenn heute oder morgen abgeholt wird.
    private var showsButton: Bool { next != nil && (days ?? 99) <= 1 }

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

    private var eyebrow: String { PickupWords.eyebrow(date: next?.date, location: family == .systemSmall ? nil : entry.locationName) }
    private var headline: String { PickupWords.headline(days: days, done: next?.done ?? false) }
    private var subline: String {
        if next == nil, let first = entry.snapshot.pickupDays.first {
            return L10n.t("nächste \(DateText.countdown(first.date))", "next \(DateText.countdown(first.date))")
        }
        return PickupWords.subline(days: days, done: next?.done ?? false)
    }

    private func names(_ day: WidgetSnapshot.PickupDay, max: Int) -> String {
        let all = day.items.map(\.name)
        let shown = all.prefix(max).joined(separator: ", ")
        return all.count > max ? shown + " +\(all.count - max)" : shown
    }

    // MARK: Bausteine

    private var textColor: Color { DesignColor.text(scheme) }
    private var mutedColor: Color { DesignColor.muted(scheme) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow).font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundStyle(DesignColor.accent(scheme)).lineLimit(1)
            Text(headline).font(.system(size: 24, weight: .black)).tracking(-0.6).foregroundStyle(textColor).lineLimit(1).minimumScaleFactor(0.65).padding(.top, 3)
            Text(subline).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor).lineLimit(1).padding(.top, 3)
        }
    }

    /// Kachelreihe plus Knopf: feste Plätze, nichts überlappt.
    private func tileRow(slots: Int, width: CGFloat = 38, height: CGFloat = 44) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            BinTileRow(items: tiles, slots: showsButton ? min(slots, 2) : slots, width: width, height: height, spacing: 5)
            Spacer(minLength: 4)
            if let next, showsButton { actionButton(next) }
        }
    }

    private func actionButton(_ day: WidgetSnapshot.PickupDay) -> some View {
        Group {
            if day.done {
                Button(intent: UndoPickupDoneIntent(dayKey: Days.iso(day.date))) {
                    ZStack {
                        Circle().fill(DesignColor.button(scheme))
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: MarkPickupDoneIntent(dayKey: Days.iso(day.date))) {
                    CheckCircleLabel(size: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func laterRow(_ day: WidgetSnapshot.PickupDay, maxNames: Int) -> some View {
        HStack(spacing: 7) {
            Text(DateText.short(day.date)).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor).frame(width: 46, alignment: .leading).lineLimit(1)
            BinDots(hexes: day.items.map(\.colorHex))
            Text(names(day, max: maxNames)).font(.system(size: 11, weight: .bold)).foregroundStyle(textColor).lineLimit(1)
        }
    }

    private func birthdayRow(_ birthday: WidgetSnapshot.BirthdayItem) -> some View {
        HStack(spacing: 8) {
            InitialsAvatar(initials: birthday.initials, colorHex: birthday.colorHex, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(birthday.name).font(.system(size: 11, weight: .bold)).foregroundStyle(textColor).lineLimit(1)
                Text(birthdayDetail(birthday)).font(.system(size: 10, weight: .semibold)).foregroundStyle(mutedColor).lineLimit(1)
            }
        }
    }

    private func birthdayDetail(_ birthday: WidgetSnapshot.BirthdayItem) -> String {
        let when = DateText.countdown(birthday.date)
        if let years = birthday.years { return "\(years) · \(when)" }
        return when
    }

    private var caption: (String) -> Text {
        { Text($0).font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(mutedColor) }
    }

    private func surface() -> some View { DesignSurface(glowHex: tiles.first?.colorHex) }

    // MARK: Home-Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 6)
            if next != nil { tileRow(slots: 3) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { surface() }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 6)
                if next != nil { tileRow(slots: 3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(DesignColor.hairline(scheme)).frame(width: 1).padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 8) {
                caption(L10n.t("DANACH", "UP NEXT"))
                ForEach(Array(later.prefix(2).enumerated()), id: \.offset) { _, day in laterRow(day, maxNames: 2) }
                if later.isEmpty { Text(L10n.t("Keine weiteren Termine", "No further pickups")).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor) }
                Spacer(minLength: 0)
                if let birthday = entry.snapshot.birthdays.first {
                    birthdayRow(birthday)
                } else if later.count > 2 {
                    laterRow(later[2], maxNames: 2)
                }
            }
            .frame(width: 136, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { surface() }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                header
                Spacer(minLength: 8)
                if let next, showsButton { actionButton(next) }
            }
            if !tiles.isEmpty { BinTileRow(items: tiles, slots: 5, width: 44, height: 50, spacing: 7) }
            Rectangle().fill(DesignColor.hairline(scheme)).frame(height: 1)
            VStack(alignment: .leading, spacing: 7) {
                caption(L10n.t("DANACH", "UP NEXT"))
                ForEach(Array(later.prefix(4).enumerated()), id: \.offset) { _, day in
                    HStack {
                        laterRow(day, maxNames: 3)
                        Spacer(minLength: 4)
                        Text(DateText.countdown(day.date)).font(.system(size: 10, weight: .semibold)).foregroundStyle(mutedColor).lineLimit(1)
                    }
                }
                if later.isEmpty { Text(L10n.t("Keine weiteren Termine", "No further pickups")).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor) }
            }
            Rectangle().fill(DesignColor.hairline(scheme)).frame(height: 1)
            VStack(alignment: .leading, spacing: 7) {
                caption(L10n.t("GEBURTSTAGE", "BIRTHDAYS"))
                ForEach(Array(entry.snapshot.birthdays.prefix(2).enumerated()), id: \.offset) { _, birthday in birthdayRow(birthday) }
                if entry.snapshot.birthdays.isEmpty { Text(L10n.t("Keine Geburtstage eingetragen", "No birthdays yet")).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { surface() }
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
        VStack(alignment: .leading, spacing: 1) {
            if let next {
                if next.items.count == 1, let item = next.items.first {
                    Text("\(Image(systemName: item.symbolName)) \(DateText.countdown(next.date))").font(.headline).lineLimit(1)
                    Text(item.name).font(.caption).lineLimit(1)
                    if let second = entry.snapshot.pickupDays.first(where: { $0.date > next.date }) {
                        Text("\(DateText.countdown(second.date)): \(names(second, max: 2))").font(.caption2).opacity(0.8).lineLimit(1)
                    }
                } else {
                    Text(DateText.countdown(next.date)).font(.headline).lineLimit(1)
                    ForEach(Array(next.items.prefix(2).enumerated()), id: \.offset) { _, item in
                        Text("\(Image(systemName: item.symbolName)) \(item.name)").font(.caption).lineLimit(1)
                    }
                    if next.items.count > 2 {
                        Text("+\(next.items.count - 2) weitere").font(.caption2).opacity(0.8)
                    }
                }
            } else {
                Text("Keine Abholung").font(.headline)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
