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

    private var ink: Color { KlarStyle.birthdayInk(scheme) }

    private func top(_ title: String) -> some View {
        HStack {
            Text(title).font(KlarStyle.font(11, .heavy)).tracking(0.6).foregroundStyle(ink).lineLimit(1)
            Spacer(minLength: 4)
            Text("🎂").font(.system(size: 17))
        }
    }

    private func detail(_ birthday: WidgetSnapshot.BirthdayItem) -> String {
        let when = DateText.countdown(birthday.date)
        if let years = birthday.years { return "\(years) · \(when)" }
        return when
    }

    private func row(_ birthday: WidgetSnapshot.BirthdayItem) -> some View {
        HStack(spacing: 8) {
            KlarAvatar(initials: birthday.initials, colorHex: birthday.colorHex, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(birthday.name).font(KlarStyle.font(12, .heavy)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1)
                Text(detail(birthday)).font(KlarStyle.font(11, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            top(L10n.t("GEBURTSTAG", "BIRTHDAY"))
            Spacer(minLength: 0)
            Text(L10n.t("Keine Geburtstage", "No birthdays")).font(KlarStyle.font(16, .black)).foregroundStyle(KlarStyle.text(scheme))
            Text(L10n.t("In der App unter „Geburtstage“ eintragen.", "Add them under “Birthdays” in the app.")).font(KlarStyle.font(11, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(2)
        }
    }

    private func surface() -> some View { KlarSurface(tintHex: KlarStyle.birthday) }

    // MARK: Home-Screen

    private var small: some View {
        Group {
            if let next {
                VStack(alignment: .leading, spacing: 0) {
                    top(Days.until(next.date) == 0 ? L10n.t("HEUTE", "TODAY") : L10n.t("GEBURTSTAG", "BIRTHDAY"))
                    KlarAvatar(initials: next.initials, colorHex: next.colorHex, size: 42).padding(.top, 8)
                    Spacer(minLength: 4)
                    Text(next.name).font(KlarStyle.font(16, .black)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        if let years = next.years {
                            Text(L10n.t("wird \(years) ·", "turns \(years) ·")).foregroundStyle(KlarStyle.muted(scheme))
                        }
                        Text(DateText.countdown(next.date)).foregroundStyle(ink)
                    }
                    .font(KlarStyle.font(12, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)
                }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { surface() }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if let next {
                    VStack(alignment: .leading, spacing: 0) {
                        top(Days.until(next.date) == 0 ? L10n.t("HEUTE", "TODAY") : L10n.t("NÄCHSTER GEBURTSTAG", "NEXT BIRTHDAY"))
                        Spacer(minLength: 4)
                        HStack(spacing: 10) {
                            KlarAvatar(initials: next.initials, colorHex: next.colorHex, size: 42)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(next.name).font(KlarStyle.font(17, .black)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1).minimumScaleFactor(0.7)
                                Text(PickupWords.birthdaySubline(years: next.years, date: next.date)).font(KlarStyle.font(11, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
                            }
                        }
                        Text(DateText.countdown(next.date)).font(KlarStyle.font(22, .black)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 8)
                    }
                } else {
                    empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(KlarStyle.hairline(scheme)).frame(width: 1).padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.t("DANACH", "UP NEXT")).font(KlarStyle.font(10, .heavy)).tracking(1).foregroundStyle(KlarStyle.muted(scheme))
                ForEach(Array(later.prefix(3).enumerated()), id: \.offset) { _, birthday in row(birthday) }
                if later.isEmpty {
                    Text(L10n.t("Keine weiteren", "None further")).font(KlarStyle.font(11, .bold)).foregroundStyle(KlarStyle.muted(scheme))
                }
                Spacer(minLength: 0)
            }
            .frame(width: 128, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
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
