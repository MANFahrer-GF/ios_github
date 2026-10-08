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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.bringInEnabled) private var bringInEnabled = true
    @AppStorage(SettingsKeys.bringInMinutes) private var bringInMinutes = 17 * 60
    @State private var refreshToken = 0
    /// Alle fünf Minuten neu auswerten – mittags kommt „wieder reinholen“, um 17 Uhr springt die Abholung weiter.
    private let clock = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

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

    /// Abholungen, um die man sich noch kümmern muss – die heutige fällt weg, sobald sie erledigt ist oder es nach 17 Uhr ist.
    private var activeWasteDays: [(day: Date, events: [CalendarEvent])] {
        let now = Date()
        let doneTimes = SnapshotStore.doneTimes()
        return wasteDays.filter { !PickupTiming.isFinished(day: $0.day, done: $0.events.allSatisfy(\.done), doneAt: doneTimes[Days.iso($0.day)], now: now) }
    }

    /// Heute geleerte Tonnen, die wieder herein müssen (ab mittags, bis „Ist drin“). Säcke und Grünschnitt zählen nicht.
    private var bringIn: (day: Date, names: [String])? {
        _ = refreshToken
        let now = Date()
        guard bringInEnabled, let today = wasteDays.first(where: { Calendar.current.isDate($0.day, inSameDayAs: now) }),
              PickupTiming.showsBringIn(day: today.day, broughtIn: SnapshotStore.broughtInDays().contains(Days.iso(today.day)), now: now,
                                        fromMinutes: min(PickupTiming.bringInHintMinutes, bringInMinutes)) else { return nil }
        let names = today.events.filter { WasteReturn.isBin(name: $0.title, symbol: $0.symbolName) }.map(\.title)
        return names.isEmpty ? nil : (day: today.day, names: names)
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
                    if let bringIn { bringInCard(bringIn) }
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
            .onReceive(NotificationCenter.default.publisher(for: SnapshotStore.broughtInNotification)) { _ in refreshToken += 1 }
            .onReceive(clock) { _ in refreshToken += 1 }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshToken += 1 } }
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

    private func bringInCard(_ bringIn: (day: Date, names: [String])) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2).foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(bringIn.names.count == 1 ? L10n.t("\(bringIn.names[0]) wieder reinholen", "Bring the \(bringIn.names[0]) back in")
                                              : L10n.t("Tonnen wieder reinholen", "Bring the bins back in"))
                    .font(.subheadline.weight(.semibold))
                Text(bringIn.names.count == 1 ? L10n.t("Die Abfuhr war heute.", "Collection was today.")
                                              : ReminderPlanner.joinNames(bringIn.names))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Haptics.success()
                SnapshotStore.markBroughtIn(dayKey: Days.iso(bringIn.day))
                refreshToken += 1
            } label: {
                Text(L10n.t("Ist drin", "It's in"))
            }
            .buttonStyle(.borderedProminent).controlSize(.small)
            .accessibilityLabel(L10n.t("\(ReminderPlanner.joinNames(bringIn.names)) ist wieder drin", "\(ReminderPlanner.joinNames(bringIn.names)) is back in"))
        }
        .card()
    }

    // MARK: - Hero

    private var heroCard: some View {
        let next = activeWasteDays.first
        let n = next.map { Days.until($0.day) }
        let allDone = next?.events.allSatisfy(\.done) ?? false
        let tiles = next?.events.map { BinTileItem(name: $0.title, symbolName: $0.symbolName, colorHex: $0.colorHex) } ?? []
        let nextAfter = activeWasteDays.dropFirst().first
        let subline: String = {
            if next == nil, let first = activeWasteDays.first { return "nächste \(DateText.countdown(first.day))" }
            return PickupWords.subline(days: n, done: allDone)
        }()
        let eyebrow: String = {
            guard let next else { return PickupWords.eyebrow(date: nil) }
            let single = Set(next.events.compactMap(\.locationName))
            return PickupWords.eyebrow(date: next.day, location: locations.count > 1 && single.count == 1 ? single.first : nil)
        }()

        return VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow).font(KlarStyle.font(12, .heavy)).tracking(0.8)
                .foregroundStyle(allDone ? KlarStyle.done : (tiles.first.map { KlarStyle.ink($0.colorHex, scheme) } ?? KlarStyle.muted(scheme)))
                .lineLimit(1)
            Text(PickupWords.headline(days: n, done: allDone))
                .font(KlarStyle.font(40, .black)).foregroundStyle(KlarStyle.text(scheme))
                .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 2)
            Text(subline).font(KlarStyle.font(15, .bold)).foregroundStyle(KlarStyle.muted(scheme)).padding(.top, 1)
            if let next {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                            BinLine(name: tile.name, symbolName: tile.symbolName, colorHex: tile.colorHex, dot: 32, fontSize: 18)
                        }
                    }
                    .opacity(allDone ? 0.55 : 1)
                    Spacer(minLength: 0)
                    if let n, n <= 1 {
                        if allDone {
                            Button {
                                Haptics.tap()
                                Task { await model.markUndone(dayKey: Days.iso(next.day)); refreshToken += 1 }
                            } label: {
                                Label("Zurück", systemImage: "arrow.uturn.backward")
                                    .font(KlarStyle.font(15, .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(KlarStyle.done, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                Haptics.success()
                                Task { await model.markDone(dayKey: Days.iso(next.day)); refreshToken += 1 }
                            } label: {
                                Label("Erledigt", systemImage: "checkmark")
                                    .font(KlarStyle.font(15, .heavy))
                                    .foregroundStyle(KlarStyle.buttonForeground(scheme))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(KlarStyle.buttonBackground(scheme), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 18)
                if let nextAfter {
                    HStack(spacing: 8) {
                        Text("Danach").font(KlarStyle.font(12, .heavy)).foregroundStyle(KlarStyle.muted(scheme))
                        MiniDots(hexes: nextAfter.events.map(\.colorHex), size: 11)
                        Text("\(DateText.countdown(nextAfter.day)) · \(nextAfter.events.map(\.title).joined(separator: ", "))")
                            .font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
                    }
                    .padding(.top, 14)
                }
            } else {
                Text("Lege unter „Müll“ einen Standort an – die Termine kommen automatisch.")
                    .font(KlarStyle.font(15, .semibold)).foregroundStyle(KlarStyle.muted(scheme)).padding(.top, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            KlarSurface(tintHex: allDone ? "#34C759" : tiles.first?.colorHex)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 16, x: 0, y: 6)
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
