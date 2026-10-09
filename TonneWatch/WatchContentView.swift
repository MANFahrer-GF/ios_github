import SwiftUI
import TonneCore

/// Watch-App im Design „Klar“: nächste Abholung mit „Erledigt“/„Zurück“, weitere Tage, Geburtstage.
struct WatchContentView: View {
    @State private var snapshot: WidgetSnapshot? = SnapshotStore.load()
    @Environment(\.scenePhase) private var scenePhase

    private var next: WidgetSnapshot.PickupDay? { snapshot?.nextPickupDay() }

    var body: some View {
        TabView {
            PickupPage(snapshot: snapshot, next: next, reload: reload)
            UpcomingPage(snapshot: snapshot, next: next)
            BirthdayPage(snapshot: snapshot)
        }
        .tabViewStyle(.verticalPage)
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: WatchSync.updatedNotification).receive(on: DispatchQueue.main)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: SnapshotStore.notificationName).receive(on: DispatchQueue.main)) { _ in reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload(); WatchSync.requestRefresh() }
        }
    }

    private func reload() { snapshot = SnapshotStore.load() }
}

// MARK: - Seite 1: nächste Abholung

private struct PickupPage: View {
    let snapshot: WidgetSnapshot?
    let next: WidgetSnapshot.PickupDay?
    let reload: () -> Void

    private var days: Int? { next.map { Days.until($0.date) } }
    private var done: Bool { next?.done ?? false }
    private var tintHex: String { done ? "#34C759" : (next?.items.first?.colorHex ?? HeroPalette.idle) }

    private var eyebrow: String {
        if done, days == 0 { return L10n.t("HEUTE", "TODAY") }
        return PickupWords.eyebrow(date: next?.date)
    }

    private var eyebrowColor: Color {
        if done { return KlarStyle.done }
        guard let hex = next?.items.first?.colorHex else { return KlarStyle.muted(.dark) }
        return KlarStyle.ink(hex, .dark)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .font(KlarStyle.font(12, .heavy)).tracking(0.6)
                    .foregroundStyle(eyebrowColor)
                    .lineLimit(1)
                Text(PickupWords.headline(days: days, done: done))
                    .font(KlarStyle.font(30, .black))
                    .foregroundStyle(KlarStyle.text(.dark))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(PickupWords.subline(days: days, done: done))
                    .font(KlarStyle.font(13, .bold))
                    .foregroundStyle(KlarStyle.muted(.dark))
                    .lineLimit(1).minimumScaleFactor(0.8)

                if let next {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(next.items.enumerated()), id: \.offset) { _, item in
                            BinLine(name: item.name, symbolName: item.displaySymbol, colorHex: item.colorHex, dot: 26, fontSize: 16)
                        }
                    }
                    .opacity(done ? 0.55 : 1)
                    .padding(.top, 12)

                    if let days, days <= 1 { actionButton(next).padding(.top, 14) }
                } else if snapshot == nil {
                    Text("Öffne Tonne & Torte auf dem iPhone, dann erscheinen hier deine Termine.")
                        .font(KlarStyle.font(13, .semibold))
                        .foregroundStyle(KlarStyle.muted(.dark))
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
        .containerBackground(
            LinearGradient(colors: [Color(hex: tintHex).opacity(0.45), .black], startPoint: .top, endPoint: .center),
            for: .tabView
        )
    }

    @ViewBuilder
    private func actionButton(_ day: WidgetSnapshot.PickupDay) -> some View {
        let key = Days.iso(day.date)
        if day.done {
            Button {
                SnapshotStore.markUndone(dayKey: key)
                WatchSync.sendUndo(dayKey: key)
                reload()
            } label: {
                Label(L10n.t("Rückgängig", "Undo"), systemImage: "arrow.uturn.backward")
                    .font(KlarStyle.font(16, .heavy))
                    .frame(maxWidth: .infinity)
            }
            .tint(KlarStyle.done)
        } else {
            Button {
                SnapshotStore.markDone(dayKey: key)
                WatchSync.sendDone(dayKey: key)
                reload()
            } label: {
                Label(L10n.t("Erledigt", "Done"), systemImage: "checkmark")
                    .font(KlarStyle.font(16, .heavy))
                    .foregroundStyle(Color(hex: "#111114"))
                    .frame(maxWidth: .infinity)
            }
            .tint(Color(hex: "#F5F5F7"))
        }
    }
}

// MARK: - Seite 2: weitere Abholungen

private struct UpcomingPage: View {
    let snapshot: WidgetSnapshot?
    let next: WidgetSnapshot.PickupDay?

    private var later: [WidgetSnapshot.PickupDay] {
        (snapshot?.pickupDays ?? []).filter { $0.date > (next?.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("DANACH", "UP NEXT"))
                    .font(KlarStyle.font(11, .heavy)).tracking(1)
                    .foregroundStyle(KlarStyle.muted(.dark))
                if later.isEmpty {
                    Text(L10n.t("Keine weiteren Termine", "No further pickups"))
                        .font(KlarStyle.font(14, .bold))
                        .foregroundStyle(KlarStyle.muted(.dark))
                }
                ForEach(Array(later.prefix(10).enumerated()), id: \.offset) { _, day in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(DateText.countdown(day.date)).font(KlarStyle.font(15, .heavy)).foregroundStyle(KlarStyle.text(.dark))
                            Spacer(minLength: 4)
                            Text(DateText.short(day.date)).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(.dark))
                        }
                        ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                            BinLine(name: item.name, symbolName: item.displaySymbol, colorHex: item.colorHex, dot: 18, fontSize: 13)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#1C1C20"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(Color.black, for: .tabView)
    }
}

// MARK: - Seite 3: Geburtstage

private struct BirthdayPage: View {
    let snapshot: WidgetSnapshot?

    private var birthdays: [WidgetSnapshot.BirthdayItem] {
        (snapshot?.birthdays ?? []).filter { $0.date >= Days.today() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.t("GEBURTSTAGE", "BIRTHDAYS"))
                        .font(KlarStyle.font(11, .heavy)).tracking(1)
                        .foregroundStyle(KlarStyle.birthdayInk(.dark))
                    Spacer()
                    Text("🎂")
                }
                if birthdays.isEmpty {
                    Text(L10n.t("Keine Geburtstage eingetragen", "No birthdays yet"))
                        .font(KlarStyle.font(14, .bold))
                        .foregroundStyle(KlarStyle.muted(.dark))
                }
                ForEach(Array(birthdays.prefix(10).enumerated()), id: \.offset) { _, birthday in
                    HStack(spacing: 10) {
                        KlarAvatar(initials: birthday.initials, colorHex: birthday.colorHex, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(birthday.name).font(KlarStyle.font(15, .heavy)).foregroundStyle(KlarStyle.text(.dark)).lineLimit(1)
                            HStack(spacing: 4) {
                                if let years = birthday.years {
                                    Text(L10n.t("wird \(years) ·", "turns \(years) ·")).foregroundStyle(KlarStyle.muted(.dark))
                                }
                                Text(DateText.countdown(birthday.date)).foregroundStyle(KlarStyle.birthdayInk(.dark))
                            }
                            .font(KlarStyle.font(12, .heavy))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(
            LinearGradient(colors: [Color(hex: KlarStyle.birthday).opacity(0.35), .black], startPoint: .top, endPoint: .center),
            for: .tabView
        )
    }
}
