import WidgetKit
import SwiftUI
import TonneCore

// MARK: - Timeline

struct BirthdayEntry: TimelineEntry {
    let date: Date
    let birthdays: [WidgetSnapshot.BirthdayItem]
}

struct BirthdayTimelineProvider: TimelineProvider {
    static let sample: [WidgetSnapshot.BirthdayItem] = [
        .init(date: Days.add(3, to: Days.today()), name: "Oma Erika", years: 80, colorHex: "#FF5FA2", initials: "OE"),
        .init(date: Days.add(12, to: Days.today()), name: "Paul Kant", years: 12, colorHex: "#4F8CFF", initials: "PK"),
        .init(date: Days.add(20, to: Days.today()), name: "Maria Schulz", years: nil, colorHex: "#2ECC9A", initials: "MS"),
    ]

    func placeholder(in context: Context) -> BirthdayEntry { BirthdayEntry(date: Date(), birthdays: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (BirthdayEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BirthdayEntry>) -> Void) {
        let now = Date()
        let current = entry()
        var entries = [current]
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime) {
            entries.append(BirthdayEntry(date: midnight, birthdays: current.birthdays))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    private func entry() -> BirthdayEntry {
        let today = Days.today()
        let upcoming = (SnapshotStore.load()?.birthdays ?? []).filter { $0.date >= today }.sorted { $0.date < $1.date }
        return BirthdayEntry(date: Date(), birthdays: upcoming)
    }
}

// MARK: - Widget

struct BirthdayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "de.manfahrer.TonneUndTorte.birthday", provider: BirthdayTimelineProvider()) { entry in
            BirthdayWidgetView(entry: entry)
        }
        .configurationDisplayName("Nächster Geburtstag")
        .description("Wer hat als Nächstes Geburtstag? Mit Alter und Countdown.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct BirthdayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: BirthdayEntry

    private var next: WidgetSnapshot.BirthdayItem? { entry.birthdays.first }
    private var later: [WidgetSnapshot.BirthdayItem] { Array(entry.birthdays.dropFirst()) }
    private var textColor: Color { DesignColor.text(scheme) }
    private var mutedColor: Color { DesignColor.muted(scheme) }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Bausteine

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next {
                InitialsAvatar(initials: next.initials, colorHex: next.colorHex, size: 46)
                Text(next.name).font(.system(size: 19, weight: .black)).tracking(-0.4).foregroundStyle(textColor).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 10)
                Text(PickupWords.birthdaySubline(years: next.years, date: next.date)).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor).lineLimit(1).padding(.top, 3)
                Spacer(minLength: 6)
                BirthdayPill(text: PickupWords.birthdayPill(date: next.date))
            } else {
                Text("🎂").font(.system(size: 34))
                Text(L10n.t("Keine Geburtstage", "No birthdays")).font(.system(size: 17, weight: .black)).foregroundStyle(textColor).padding(.top, 8)
                Text(L10n.t("In der App unter „Geburtstage“ eintragen.", "Add them under “Birthdays” in the app.")).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor).lineLimit(2).padding(.top, 3)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ birthday: WidgetSnapshot.BirthdayItem) -> some View {
        HStack(spacing: 8) {
            InitialsAvatar(initials: birthday.initials, colorHex: birthday.colorHex, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(birthday.name).font(.system(size: 11, weight: .bold)).foregroundStyle(textColor).lineLimit(1)
                Text(detail(birthday)).font(.system(size: 10, weight: .semibold)).foregroundStyle(mutedColor).lineLimit(1)
            }
        }
    }

    private func detail(_ birthday: WidgetSnapshot.BirthdayItem) -> String {
        let when = DateText.countdown(birthday.date)
        if let years = birthday.years { return "\(years) · \(when)" }
        return when
    }

    private func surface() -> some View { DesignSurface(glowHex: next.map { _ in DesignColor.birthday }) }

    // MARK: Home-Screen

    private var small: some View {
        hero
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { surface() }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 0) {
            hero
            Rectangle().fill(DesignColor.hairline(scheme)).frame(width: 1).padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("DANACH", "UP NEXT")).font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(mutedColor)
                ForEach(Array(later.prefix(3).enumerated()), id: \.offset) { _, birthday in row(birthday) }
                if later.isEmpty { Text(L10n.t("Keine weiteren", "None further")).font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedColor) }
                Spacer(minLength: 0)
            }
            .frame(width: 136, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { surface() }
    }

    // MARK: Sperrbildschirm

    private var inline: some View {
        Group {
            if let next { Text("🎂 \(next.name) · \(DateText.countdown(next.date))") }
            else { Text(L10n.t("Keine Geburtstage", "No birthdays")) }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text("🎂").font(.title3)
                Text(next.map { Days.until($0.date) }.map { $0 == 0 ? L10n.t("heute", "today") : "\($0) T." } ?? "–").font(.caption2.weight(.semibold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next {
                Text("🎂 \(next.name)").font(.headline).lineLimit(1)
                Text(PickupWords.birthdaySubline(years: next.years, date: next.date)).font(.caption).lineLimit(1)
                Text(DateText.countdown(next.date)).font(.caption2).opacity(0.8)
            } else {
                Text(L10n.t("Keine Geburtstage", "No birthdays")).font(.headline)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
