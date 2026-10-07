import SwiftUI
import SwiftData
import TonneCore

/// Startseite: Was steht an, Erledigt-Knopf, nächste Abholungen, Geburtstage, Streak.
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Location.sortOrder) private var locations: [Location]
    @Query(sort: \WasteType.sortOrder) private var wasteTypes: [WasteType]
    @Query(sort: \Person.name) private var people: [Person]
    @ObservedObject private var notifications = NotificationManager.shared
    @AppStorage(SettingsKeys.locationFilter) private var filterID: String = ""
    @State private var refreshToken = 0

    private var days: [(day: Date, events: [CalendarEvent])] {
        _ = refreshToken
        _ = wasteTypes.count + people.count
        return model.upcomingByDay(days: 60, locationID: LocationFilter.apply(filterID))
    }

    private var wasteDays: [(day: Date, events: [CalendarEvent])] {
        days.compactMap { entry in
            let waste = entry.events.filter { $0.kind == .waste }
            return waste.isEmpty ? nil : (day: entry.day, events: waste)
        }
    }

    private var otherUpcoming: [CalendarEvent] {
        days.flatMap(\.events).filter { $0.kind != .waste }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !notifications.isAuthorized { permissionBanner }
                    if !model.recentChanges.isEmpty { changesBanner }
                    heroCard
                    nextPickupsSection
                    birthdaysSection
                    statsCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Übersicht")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { LocationFilterMenu(locations: locations) } }
            .refreshable {
                _ = await model.syncAll(force: true)
                await model.refreshAll()
                refreshToken += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: SnapshotStore.notificationName)) { _ in refreshToken += 1 }
        }
    }

    // MARK: - Banner

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Erinnerungen sind aus").font(.subheadline.weight(.semibold))
                Text("Erlaube Mitteilungen, damit du keinen Gelben Sack mehr verpasst.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(notifications.authorizationStatus == .denied ? "Einstellungen" : "Erlauben") {
                if notifications.authorizationStatus == .denied { notifications.openSystemSettings() }
                else { Task { await notifications.requestAuthorization(); await model.refreshAll() } }
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .card()
    }

    private var changesBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Termine wurden verschoben").font(.subheadline.weight(.semibold))
                ForEach(model.recentChanges.prefix(3), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { model.recentChanges = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
        }
        .card()
    }

    // MARK: - Hero

    private var heroCard: some View {
        let next = wasteDays.first
        let hexes = next?.events.map(\.colorHex) ?? []
        let shadow = HeroPalette.glow(for: hexes)
        let n = next.map { Days.until($0.day) }
        let allDone = next?.events.allSatisfy(\.done) ?? false

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next == nil ? "ALLES RUHIG" : n == 0 ? "HEUTE" : n == 1 ? "MORGEN" : "NÄCHSTE ABHOLUNG")
                        .font(.caption.weight(.bold)).opacity(0.85)
                    Text(next == nil ? "Keine Abholung geplant" : allDone ? "Alles steht draußen 👍" : n == 0 ? "Heute wird abgeholt" : n == 1 ? "Heute Abend rausstellen!" : "In \(n ?? 0) Tagen")
                        .font(.title.weight(.bold))
                }
                Spacer()
                if let next {
                    BinStack(bins: next.events.map { BinRef(symbolName: $0.symbolName, colorHex: $0.colorHex) }, size: 46)
                } else {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44, weight: .semibold)).opacity(0.9)
                }
            }
            if let next {
                FlowLayout(spacing: 8) { ForEach(next.events) { EventChip(event: $0, showLocation: locations.count > 1) } }
                Text(DateText.long(next.day)).font(.subheadline).opacity(0.9)
                if !allDone, let n, n <= 1 {
                    Button {
                        Haptics.success()
                        Task { await model.markDone(dayKey: Days.iso(next.day)); refreshToken += 1 }
                    } label: {
                        Label("Erledigt – steht draußen", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Lege unter „Müll“ einen Standort an – die Termine kommen automatisch.").font(.subheadline).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HeroPalette.background(for: hexes)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: shadow.opacity(0.35), radius: 16, x: 0, y: 8)
        )
    }

    // MARK: - Listen

    private var nextPickupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nächste Abholungen", systemImage: "trash.fill").font(.headline).padding(.leading, 4)
            if wasteDays.isEmpty {
                Text("Keine Abholungen in den nächsten 60 Tagen.").font(.subheadline).foregroundStyle(.secondary).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(wasteDays.prefix(8).enumerated()), id: \.element.day) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DateText.countdown(entry.day)).font(.subheadline.weight(.semibold))
                                Text(DateText.short(entry.day)).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 92, alignment: .leading)
                            FlowLayout(spacing: 6) { ForEach(entry.events) { EventChip(event: $0, onLight: true, showLocation: locations.count > 1) } }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if index < min(wasteDays.count, 8) - 1 { Divider() }
                    }
                }
                .card()
            }
        }
    }

    private var birthdaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Geburtstage & Termine", systemImage: "birthday.cake.fill").font(.headline).padding(.leading, 4)
            if otherUpcoming.isEmpty {
                Text(people.isEmpty ? "Noch keine Geburtstage – unter „Geburtstage“ hinzufügen oder aus Kontakten importieren." : "In den nächsten 60 Tagen steht nichts an.")
                    .font(.subheadline).foregroundStyle(.secondary).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(otherUpcoming.prefix(6).enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 12) {
                            EventRow(event: event)
                            Text(DateText.countdown(event.date)).font(.subheadline.weight(.semibold))
                                .foregroundStyle(Days.until(event.date) == 0 ? Color.pink : .secondary)
                        }
                        .padding(.vertical, 8)
                        if index < min(otherUpcoming.count, 6) - 1 { Divider() }
                    }
                }
                .card()
            }
        }
    }

    private var statsCard: some View {
        let stats = model.statistics()
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stats.total)").font(.title2.weight(.bold))
                Text("Abholungen dieses Jahr").font(.caption).foregroundStyle(.secondary)
            }
            Divider().frame(height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stats.confirmed)").font(.title2.weight(.bold)).foregroundStyle(.green)
                Text("davon bestätigt").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: stats.total > 0 && stats.confirmed == stats.total ? "flame.fill" : "chart.bar.fill").font(.title2).foregroundStyle(.orange)
        }
        .card()
    }
}
