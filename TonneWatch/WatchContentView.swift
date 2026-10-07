import SwiftUI
import TonneCore

/// Watch-App: nächste Abholung mit „Erledigt“, weitere Tage, Geburtstage.
struct WatchContentView: View {
    @State private var snapshot: WidgetSnapshot? = SnapshotStore.load()
    @Environment(\.scenePhase) private var scenePhase

    private var next: WidgetSnapshot.PickupDay? { snapshot?.nextPickupDay() }

    var body: some View {
        TabView {
            heroPage
            listPage
            birthdayPage
        }
        .tabViewStyle(.verticalPage)
        .onReceive(NotificationCenter.default.publisher(for: WatchSync.updatedNotification)) { _ in snapshot = SnapshotStore.load() }
        .onReceive(NotificationCenter.default.publisher(for: SnapshotStore.notificationName)) { _ in snapshot = SnapshotStore.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { snapshot = SnapshotStore.load(); WatchSync.requestRefresh() }
        }
    }

    // MARK: Seite 1 – Nächste Abholung

    private var heroPage: some View {
        let color = Color(hex: next?.items.first?.colorHex ?? "#2F6FED")
        let days = next.map { Days.until($0.date) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(next == nil ? "ALLES RUHIG" : days == 0 ? "HEUTE" : days == 1 ? "MORGEN" : "NÄCHSTE ABHOLUNG")
                        .font(.caption2.weight(.bold)).foregroundStyle(color)
                    Spacer()
                    Image(systemName: next?.items.first?.symbolName ?? "checkmark.circle.fill").foregroundStyle(color)
                }
                if let next, let days {
                    Text(next.done ? "Steht draußen 👍" : days == 0 ? "Heute wird abgeholt" : days == 1 ? "Heute Abend rausstellen!" : "In \(days) Tagen")
                        .font(.headline)
                    ForEach(next.items, id: \.name) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.symbolName).foregroundStyle(Color(hex: item.colorHex))
                            Text(item.name).font(.footnote)
                        }
                    }
                    Text(DateText.long(next.date)).font(.caption2).foregroundStyle(.secondary)
                    if !next.done && days <= 1 {
                        Button {
                            let key = Days.iso(next.date)
                            SnapshotStore.markDone(dayKey: key)
                            WatchSync.sendDone(dayKey: key)
                            snapshot = SnapshotStore.load()
                        } label: {
                            Label("Erledigt", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                        .padding(.top, 4)
                    }
                } else if snapshot == nil {
                    Text("Öffne Tonne & Torte auf dem iPhone, dann erscheinen hier deine Termine.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Keine Abholung geplant").font(.headline)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Tonne & Torte")
    }

    // MARK: Seite 2 – Weitere Tage

    private var listPage: some View {
        List {
            if let snapshot, !snapshot.pickupDays.isEmpty {
                ForEach(snapshot.pickupDays.prefix(10), id: \.date) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(DateText.countdown(day.date)).font(.footnote.weight(.semibold))
                            Spacer()
                            Text(DateText.short(day.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(day.items, id: \.name) { item in
                            HStack(spacing: 5) {
                                Image(systemName: item.symbolName).font(.caption2).foregroundStyle(Color(hex: item.colorHex))
                                Text(item.name).font(.caption2)
                                if day.done { Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green) }
                            }
                        }
                    }
                }
            } else {
                Text("Keine Termine").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Abholungen")
    }

    // MARK: Seite 3 – Geburtstage

    private var birthdayPage: some View {
        List {
            if let snapshot, !snapshot.birthdays.isEmpty {
                ForEach(snapshot.birthdays, id: \.name) { birthday in
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Color(hex: birthday.colorHex))
                            Text(birthday.initials).font(.caption2.weight(.bold)).foregroundStyle(.white)
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(birthday.name).font(.footnote.weight(.semibold)).lineLimit(1)
                            Text((birthday.years.map { "wird \($0) · " } ?? "") + DateText.countdown(birthday.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Keine Geburtstage in den nächsten Wochen").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Geburtstage")
    }
}
