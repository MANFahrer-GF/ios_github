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
        let entries = [entry] + dates.sorted().map { PickupEntry(date: $0, snapshot: entry.snapshot.upcomingBirthdays(from: $0), locationName: entry.locationName) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600)))
    }

    private func entry(for configuration: PickupWidgetConfiguration) -> PickupEntry {
        let full = SnapshotStore.load() ?? WidgetSnapshot()
        let filtered = full.filtered(locationID: configuration.location?.id)
        return PickupEntry(date: Date(), snapshot: filtered.upcomingBirthdays(from: Date()), locationName: configuration.location?.name)
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
    private var items: [WidgetSnapshot.PickupItem] { next?.items ?? [] }
    private var later: [WidgetSnapshot.PickupDay] { entry.snapshot.pickupDays.filter { $0.date > (next?.date ?? .distantPast) } }
    private var done: Bool { next?.done ?? false }
    /// Knopf nur, wenn heute oder morgen abgeholt wird.
    private var showsButton: Bool { next != nil && (days ?? 99) <= 1 }
    private var tintHex: String? { done ? "#34C759" : items.first?.colorHex }

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
        if done, let days, days == 0 { return L10n.t("HEUTE", "TODAY") }
        return PickupWords.eyebrow(date: next?.date)
    }
    private var headline: String { PickupWords.headline(days: days, done: done) }
    private var hint: String {
        if next == nil, let first = entry.snapshot.pickupDays.first {
            return L10n.t("nächste \(DateText.countdown(first.date))", "next \(DateText.countdown(first.date))")
        }
        return PickupWords.subline(days: days, done: done)
    }

    private func names(_ day: WidgetSnapshot.PickupDay, max: Int) -> String {
        ReminderPlanner.shortNames(day.items.map(\.name), max: max)
    }

    private var eyebrowColor: Color {
        if done { return KlarStyle.done }
        guard let hex = items.first?.colorHex else { return KlarStyle.muted(scheme) }
        return KlarStyle.ink(hex, scheme)
    }

    // MARK: Bausteine

    private func header(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text(eyebrow).font(KlarStyle.font(11, .heavy)).tracking(0.6).foregroundStyle(eyebrowColor).lineLimit(1)
                Spacer(minLength: 4)
                if let next, showsButton { button(next) }
            }
            .frame(minHeight: 28)
            Text(headline).font(KlarStyle.font(titleSize, .black)).foregroundStyle(KlarStyle.text(scheme))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func button(_ day: WidgetSnapshot.PickupDay) -> some View {
        Group {
            if day.done {
                Button(intent: UndoPickupDoneIntent(dayKey: Days.iso(day.date))) { KlarCheckButtonLabel(done: true) }
            } else {
                Button(intent: MarkPickupDoneIntent(dayKey: Days.iso(day.date))) { KlarCheckButtonLabel(done: false) }
            }
        }
        .buttonStyle(.plain)
    }

    /// Tonnen als Zeilen. Passen nicht alle hinein, steht unten „+n weitere“.
    private func binLines(max: Int, dot: CGFloat = 22, font: CGFloat = 13, spacing: CGFloat = 7) -> some View {
        let shown = items.count > max ? Array(items.prefix(max - 1)) : items
        let rest = items.count - shown.count
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                BinLine(name: item.name, symbolName: item.symbolName, colorHex: item.colorHex, dot: dot, fontSize: font)
            }
            if rest > 0 {
                Text(L10n.t("+\(rest) weitere", "+\(rest) more")).font(KlarStyle.font(font - 1, .heavy)).foregroundStyle(KlarStyle.muted(scheme))
                    .frame(height: dot)
            }
        }
        .opacity(done ? 0.55 : 1)
    }

    private var hintView: some View {
        Text(hint).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1).padding(.top, 1)
    }

    private func laterLine(_ day: WidgetSnapshot.PickupDay, maxNames: Int) -> some View {
        HStack(spacing: 7) {
            MiniDots(hexes: day.items.map(\.colorHex))
            VStack(alignment: .leading, spacing: 0) {
                Text(DateText.short(day.date)).font(KlarStyle.font(12, .heavy)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1)
                Text(names(day, max: maxNames)).font(KlarStyle.font(11, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
            }
        }
    }

    private func birthdayLine(_ birthday: WidgetSnapshot.BirthdayItem, size: CGFloat = 26) -> some View {
        HStack(spacing: 8) {
            KlarAvatar(initials: birthday.initials, colorHex: KlarStyle.birthday, size: size)
            VStack(alignment: .leading, spacing: 0) {
                Text(birthday.name).font(KlarStyle.font(12, .heavy)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1)
                Text(birthdayDetail(birthday)).font(KlarStyle.font(11, .heavy)).foregroundStyle(KlarStyle.birthdayInk(scheme)).lineLimit(1)
            }
        }
    }

    /// Alle Geburtstage des nächsten Tages in einer Zeile: Avatare übereinander, Namen zusammengefasst.
    @ViewBuilder
    private func birthdayDayLine(_ day: [WidgetSnapshot.BirthdayItem]) -> some View {
        if day.count == 1, let only = day.first {
            birthdayLine(only)
        } else if let first = day.first {
            HStack(spacing: 8) {
                KlarAvatarStack(people: day.map { ($0.initials, KlarStyle.birthday) }, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(day.names()).font(KlarStyle.font(12, .heavy)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(DateText.countdown(first.date)).font(KlarStyle.font(11, .heavy)).foregroundStyle(KlarStyle.birthdayInk(scheme)).lineLimit(1)
                }
            }
        }
    }

    private func birthdayDetail(_ birthday: WidgetSnapshot.BirthdayItem) -> String {
        let when = DateText.countdown(birthday.date)
        if let years = birthday.years { return "\(years) · \(when)" }
        return when
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(KlarStyle.font(10, .heavy)).tracking(1).foregroundStyle(KlarStyle.muted(scheme))
    }

    private var divider: some View { Rectangle().fill(KlarStyle.hairline(scheme)).frame(height: 1) }

    // MARK: Home-Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(titleSize: 27)
            if items.count <= 2 { hintView }
            Spacer(minLength: 6)
            if next != nil { binLines(max: 3) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { KlarSurface(tintHex: tintHex) }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header(titleSize: 27)
                if items.count <= 2 { hintView }
                Spacer(minLength: 6)
                if next != nil { binLines(max: 3) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(KlarStyle.hairline(scheme)).frame(width: 1).padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 9) {
                caption(L10n.t("DANACH", "UP NEXT"))
                ForEach(Array(later.prefix(2).enumerated()), id: \.offset) { _, day in laterLine(day, maxNames: 2) }
                if later.isEmpty {
                    Text(L10n.t("Keine weiteren Termine", "No further pickups")).font(KlarStyle.font(11, .bold)).foregroundStyle(KlarStyle.muted(scheme))
                }
                Spacer(minLength: 0)
                if !entry.snapshot.birthdays.isEmpty {
                    birthdayDayLine(entry.snapshot.birthdays.firstDay)
                } else if later.count > 2 {
                    laterLine(later[2], maxNames: 2)
                }
            }
            .frame(width: 128, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(for: .widget) { KlarSurface(tintHex: tintHex) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(titleSize: 30)
            hintView
            if next != nil { binLines(max: 3, dot: 24, font: 14, spacing: 7).padding(.top, 12) }
            divider.padding(.vertical, 12)
            largeUpcoming
            divider.padding(.vertical, 12)
            largeBirthdays
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { KlarSurface(tintHex: tintHex) }
    }

    private var largeUpcoming: some View {
        VStack(alignment: .leading, spacing: 0) {
                caption(L10n.t("DANACH", "UP NEXT")).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(later.prefix(3).enumerated()), id: \.offset) { _, day in
                        HStack(spacing: 8) {
                            MiniDots(hexes: day.items.map(\.colorHex))
                            Text(DateText.short(day.date)).font(KlarStyle.font(12, .heavy)).foregroundStyle(KlarStyle.text(scheme)).frame(width: 62, alignment: .leading).lineLimit(1)
                            Text(names(day, max: 3)).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(DateText.countdown(day.date)).font(KlarStyle.font(11, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
                        }
                    }
                    if later.isEmpty {
                        Text(L10n.t("Keine weiteren Termine", "No further pickups")).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme))
                    }
                }
        }
    }

    /// Platz im großen Widget: Mit Abholung (Hinweis, Tonnen, „Danach“) passen zwei Geburtstage, ohne drei.
    private var largeBirthdayRows: Int { next == nil ? 3 : 2 }

    private var largeBirthdays: some View {
        VStack(alignment: .leading, spacing: 0) {
                caption(L10n.t("GEBURTSTAGE", "BIRTHDAYS")).padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(entry.snapshot.birthdays.prefix(largeBirthdayRows).enumerated()), id: \.offset) { _, birthday in birthdayLine(birthday) }
                    if entry.snapshot.birthdays.isEmpty {
                        Text(L10n.t("Keine Geburtstage eingetragen", "No birthdays yet")).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme))
                    }
                }
        }
    }

    // MARK: Sperrbildschirm

    private var inline: some View {
        Group {
            if let next { Text("\(Image.waste(next.items.first?.symbolName ?? "trash.fill", name: next.items.first?.name ?? "")) \(DateText.countdown(next.date)): \(names(next, max: 2))") }
            else { Text("Keine Abholung") }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image.waste(next?.items.first?.symbolName ?? "trash.fill", name: next?.items.first?.name ?? "").font(.title3)
                Text(days.map { $0 == 0 ? "heute" : $0 == 1 ? "morgen" : "\($0) T." } ?? "–").font(.caption2.weight(.semibold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next {
                if next.items.count == 1, let item = next.items.first {
                    Text("\(Image.waste(item.symbolName, name: item.name)) \(DateText.countdown(next.date))").font(.headline).lineLimit(1)
                    Text(item.name).font(.caption).lineLimit(1)
                    if let second = entry.snapshot.pickupDays.first(where: { $0.date > next.date }) {
                        Text("\(DateText.countdown(second.date)): \(names(second, max: 2))").font(.caption2).opacity(0.8).lineLimit(1)
                    }
                } else {
                    Text(DateText.countdown(next.date)).font(.headline).lineLimit(1)
                    ForEach(Array(next.items.prefix(2).enumerated()), id: \.offset) { _, item in
                        Text("\(Image.waste(item.symbolName, name: item.name)) \(item.name)").font(.caption).lineLimit(1)
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
