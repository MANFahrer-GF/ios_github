import SwiftUI
import SwiftData
import TonneCore

/// Startseite: die nächsten Tage (Tonnen, Geburtstage, eigene Termine) mit Erledigt-Knopf, Statistik.
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
    @AppStorage(SettingsKeys.overviewWaste) private var showWaste = true
    @AppStorage(SettingsKeys.overviewBirthdays) private var showBirthdays = true
    @AppStorage(SettingsKeys.overviewCustom) private var showCustom = true
    @AppStorage(SettingsKeys.overviewDays) private var previewDays = 60
    @AppStorage(SettingsKeys.overviewStats) private var showStats = true
    @State private var refreshToken = 0
    @State private var editingPerson: Person?
    @State private var editingEvent: CustomEvent?
    /// Alle fünf Minuten neu auswerten – mittags kommt „wieder reinholen“, um 17 Uhr springt die Abholung weiter.
    private let clock = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    private var days: [(day: Date, events: [CalendarEvent])] {
        _ = refreshToken
        _ = wasteTypes.count + people.count
        return model.upcomingByDay(days: previewDays, locationID: LocationFilter.apply(filterID))
    }

    private var wasteDays: [(day: Date, events: [CalendarEvent])] {
        guard showWaste else { return [] }
        return days.compactMap { entry in
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

    /// Die heutige Abholung, nachdem sie aus der Hauptkarte verschwunden ist (erledigt oder nach 17 Uhr):
    /// bleibt bis Mitternacht hier, damit man sie noch bestätigen oder zurücknehmen kann.
    private var todayRecap: (day: Date, events: [CalendarEvent])? {
        guard let today = wasteDays.first(where: { Calendar.current.isDateInToday($0.day) }),
              !activeWasteDays.contains(where: { $0.day == today.day }) else { return nil }
        return today
    }

    /// Ein Tag mit allem, was ansteht: Tonnen (ohne die heute schon erledigte/vorbeie Abholung), Geburtstage, eigene Termine.
    private struct DayGroup: Identifiable {
        let day: Date
        let waste: [CalendarEvent]
        let other: [CalendarEvent]
        var id: Date { day }
        var all: [CalendarEvent] { waste + other }
    }

    private var groups: [DayGroup] {
        let active = Set(activeWasteDays.map(\.day))
        return days.compactMap { entry in
            let waste = active.contains(entry.day) ? entry.events.filter { $0.kind == .waste } : []
            let other = entry.events.filter { ($0.kind == .birthday && showBirthdays) || ($0.kind == .custom && showCustom) }
            return waste.isEmpty && other.isEmpty ? nil : DayGroup(day: entry.day, waste: waste, other: other)
        }
    }

    /// Groß gezeigt: alle Tage bis einschließlich der nächsten Abholung (höchstens drei) – so steht die Tonne mit
    /// „Erledigt“ immer oben, und Geburtstage oder Termine davor gehen nicht unter.
    private var bigGroups: [DayGroup] {
        var result: [DayGroup] = []
        for group in groups.prefix(3) {
            result.append(group)
            if !group.waste.isEmpty { break }
        }
        return result
    }

    /// Alles im eingestellten Vorschau-Zeitraum, aber nicht endlos.
    private var laterGroups: [DayGroup] { Array(groups.dropFirst(bigGroups.count).prefix(6)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !notifications.isAuthorized { permissionBanner }
                    if !model.recentChanges.isEmpty { changesBanner }
                    if let bringIn { bringInCard(bringIn) } else if let todayRecap { todayRecapCard(todayRecap) }
                    nextDaysCard
                    if showStats && showWaste { statsCard }
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
            // Geburtstag oder Termin direkt hier öffnen – nicht in einen anderen Tab springen
            .sheet(item: $editingPerson) { BirthdayEditView(person: $0) }
            .sheet(item: $editingEvent) { CustomEventEditView(event: $0) }
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
            Image(systemName: "house.circle.fill").font(.title2).foregroundStyle(.tint)
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
            .accessibilityLabel(L10n.t("\(ReminderPlanner.joinNames(bringIn.names)) \(bringIn.names.count == 1 ? "ist" : "sind") wieder drin", "\(ReminderPlanner.joinNames(bringIn.names)) \(bringIn.names.count == 1 ? "is" : "are") back in"))
        }
        .card()
    }

    private func todayRecapCard(_ today: (day: Date, events: [CalendarEvent])) -> some View {
        let done = today.events.allSatisfy(\.done)
        let names = ReminderPlanner.joinNames(today.events.map(\.title))
        return HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "clock.badge.questionmark")
                .font(.title2).foregroundStyle(done ? KlarStyle.done : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("Heute: \(names)", "Today: \(names)")).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(done ? L10n.t("Erledigt – stand draußen.", "Done – it was out.") : L10n.t("Nicht als erledigt bestätigt.", "Not confirmed as done."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Haptics.tap()
                Task {
                    if done { await model.markUndone(dayKey: Days.iso(today.day)) } else { await model.markDone(dayKey: Days.iso(today.day)) }
                    refreshToken += 1
                }
            } label: {
                Text(done ? L10n.t("Rückgängig", "Undo") : L10n.t("Erledigt", "Done"))
            }
            .buttonStyle(.bordered).controlSize(.small)
            .accessibilityLabel(done ? L10n.t("\(names): erledigt zurücknehmen", "\(names): undo done") : L10n.t("\(names) als erledigt bestätigen", "Confirm \(names) as done"))
        }
        .card()
    }

    // MARK: - Die nächsten Tage

    /// Eine Karte für alles, was ansteht: groß die Tage bis zur nächsten Abholung, darunter knapp die folgenden.
    private var nextDaysCard: some View {
        let tintHex: String? = bigGroups.lazy.compactMap { group in
            group.waste.isEmpty ? nil : (group.waste.allSatisfy(\.done) ? "#34C759" : group.waste.first?.colorHex)
        }.first
        return VStack(alignment: .leading, spacing: 0) {
            if groups.isEmpty {
                Text(locations.isEmpty ? "Lege unter „Müll“ einen Standort an – die Termine kommen automatisch." : L10n.t("In den nächsten 60 Tagen steht nichts an.", "Nothing coming up in the next 60 days."))
                    .font(KlarStyle.font(15, .semibold)).foregroundStyle(KlarStyle.muted(scheme))
            } else {
                ForEach(Array(bigGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().padding(.vertical, 16) }
                    bigGroupView(group, primary: index == 0)
                }
                if !laterGroups.isEmpty {
                    Divider().padding(.top, 18).padding(.bottom, 4)
                    ForEach(Array(laterGroups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider().opacity(0.5) }
                        laterRow(group)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            KlarSurface(tintHex: tintHex)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 16, x: 0, y: 6)
        )
    }

    private func bigGroupView(_ group: DayGroup, primary: Bool) -> some View {
        let n = Days.until(group.day)
        let allDone = !group.waste.isEmpty && group.waste.allSatisfy(\.done)
        let places = Set(group.waste.compactMap(\.locationName))
        let place = locations.count > 1 && places.count == 1 ? places.first : nil
        let eyebrowColor: Color = allDone ? KlarStyle.done : (group.waste.first.map { KlarStyle.ink($0.colorHex, scheme) } ?? .pink)
        let badge: CGFloat = primary ? 36 : 32
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PickupWords.eyebrow(date: group.day, location: place)).font(KlarStyle.font(12, .heavy)).tracking(0.8)
                        .foregroundStyle(eyebrowColor).lineLimit(1)
                    Text(DateText.countdown(group.day))
                        .font(KlarStyle.font(primary ? 36 : 24, .black)).foregroundStyle(KlarStyle.text(scheme))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                // „Erledigt“ gilt für alle Tonnen des Tages – darum beim Tag, nicht an einer einzelnen Tonne
                if !group.waste.isEmpty && n <= 1 { doneButton(day: group.day, done: allDone) }
            }
            // Alle Einträge in derselben Form: helle Fläche, Symbol, Name
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.waste) { event in
                    itemCard {
                        BinDot(symbolName: event.symbolName, colorHex: event.colorHex, name: event.title, size: badge)
                    } title: {
                        event.title
                    } detail: {
                        locations.count > 1 && place == nil ? event.locationName : nil
                    }
                    .opacity(allDone ? 0.55 : 1)
                }
                ForEach(group.other) { event in
                    Button { open(event) } label: {
                        itemCard {
                            if event.kind == .birthday {
                                PersonAvatar(person: person(for: event), initials: NameText.initials(event.title), colorHex: event.colorHex, size: badge)
                            } else {
                                SymbolBadge(symbolName: event.symbolName, colorHex: event.colorHex, size: badge)
                            }
                        } title: {
                            event.kind == .birthday ? L10n.t("\(event.title) hat Geburtstag", "\(event.title)'s birthday") : event.title
                        } detail: {
                            // „Zeit zum Gratulieren“ nur am Geburtstag selbst; ohne bekanntes Alter sonst keine zweite Zeile
                            event.kind == .birthday ? (ageText(event) ?? (Days.until(event.date) == 0 ? L10n.t("Zeit zum Gratulieren", "Time to celebrate") : nil)) : event.subtitle
                        } trailing: {
                            if event.kind == .birthday { Text(event.isMilestone ? "🎉" : "🎂").font(.title3) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
        }
    }

    /// Eine Zeile der großen Karte: helle Fläche, Symbol, Titel und optional eine zweite Zeile.
    private func itemCard<Leading: View, Trailing: View>(@ViewBuilder leading: () -> Leading, title: () -> String, detail: () -> String?,
                                                         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        let detailText = detail()
        return HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(title()).font(KlarStyle.font(17, .heavy)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1).minimumScaleFactor(0.8)
                if let detailText {
                    Text(detailText).font(KlarStyle.font(15, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(.secondarySystemGroupedBackground).opacity(scheme == .dark ? 0.6 : 0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Ein späterer Tag: links Datum und Abstand wie oben, rechts dieselben Symbole – nur eine Nummer kleiner.
    private func laterRow(_ group: DayGroup) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(PickupWords.eyebrow(date: group.day)).font(KlarStyle.font(11, .heavy)).tracking(0.6)
                    .foregroundStyle(group.waste.first.map { KlarStyle.ink($0.colorHex, scheme) } ?? .pink).lineLimit(1)
                Text(DateText.countdown(group.day)).font(KlarStyle.font(17, .black)).foregroundStyle(KlarStyle.text(scheme))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.waste) { event in
                    HStack(spacing: 8) {
                        BinLine(name: event.title, symbolName: event.symbolName, colorHex: event.colorHex, dot: 26, fontSize: 15)
                        if locations.count > 1, let location = event.locationName {
                            Text(location).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
                        }
                    }
                }
                ForEach(group.other) { event in
                    Button { open(event) } label: {
                        HStack(spacing: 9) {
                            if event.kind == .birthday {
                                PersonAvatar(person: person(for: event), initials: NameText.initials(event.title), colorHex: event.colorHex, size: 26)
                            } else {
                                SymbolBadge(symbolName: event.symbolName, colorHex: event.colorHex, size: 26)
                            }
                            Text(event.kind == .birthday ? (event.years.map { L10n.t("\(event.title) wird \($0)", "\(event.title) turns \($0)") } ?? L10n.t("\(event.title) hat Geburtstag", "\(event.title)'s birthday")) : event.title)
                                .font(KlarStyle.font(15, .heavy)).foregroundStyle(KlarStyle.text(scheme)).lineLimit(1).minimumScaleFactor(0.8)
                            if let year = birthYear(event) {
                                Text(L10n.t("Jahrgang \(year)", "born \(year)")).font(KlarStyle.font(13, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
                            }
                            if event.kind == .birthday { Text(event.isMilestone ? "🎉" : "🎂").font(.subheadline) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func person(for event: CalendarEvent) -> Person? {
        event.personID.flatMap { id in people.first { $0.id == id } }
    }

    /// Geburtsjahr aus Alter und Geburtstag – nur wenn das Jahr bekannt ist.
    private func birthYear(_ event: CalendarEvent) -> Int? {
        event.years.map { Calendar.current.component(.year, from: event.date) - $0 }
    }

    private func ageText(_ event: CalendarEvent) -> String? {
        guard let years = event.years, let year = birthYear(event) else { return nil }
        return L10n.t("wird \(years) · Jahrgang \(year)", "turns \(years) · born \(year)")
    }

    private func doneButton(day: Date, done: Bool) -> some View {
        Button {
            if done { Haptics.tap() } else { Haptics.success() }
            Task {
                if done { await model.markUndone(dayKey: Days.iso(day)) } else { await model.markDone(dayKey: Days.iso(day)) }
                refreshToken += 1
            }
        } label: {
            Label(done ? "Rückgängig" : "Erledigt", systemImage: done ? "arrow.uturn.backward" : "checkmark")
                .font(KlarStyle.font(15, .heavy))
                .foregroundStyle(done ? .white : KlarStyle.buttonForeground(scheme))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(done ? KlarStyle.done : KlarStyle.buttonBackground(scheme), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func open(_ event: CalendarEvent) {
        if let id = event.personID { editingPerson = model.allPeople().first { $0.id == id } }
        else if let id = event.eventID { editingEvent = model.allCustomEvents().first { $0.id == id } }
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
