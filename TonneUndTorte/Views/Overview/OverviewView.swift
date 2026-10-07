import SwiftUI
import SwiftData

/// Startseite: Was steht heute/morgen an, die nächsten Abholungen und Geburtstage.
struct OverviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Location.sortOrder) private var locations: [Location]
    @Query(sort: \WasteType.sortOrder) private var wasteTypes: [WasteType]
    @Query(sort: \Person.name) private var people: [Person]
    @ObservedObject private var notifications = NotificationManager.shared
    @AppStorage(LocationFilter.key) private var filterID: String = ""

    private var filteredTypes: [WasteType] {
        LocationFilter.apply(wasteTypes, filterID: filterID)
    }

    private var upcomingDays: [(day: Date, events: [CalendarEvent])] {
        EventEngine.upcomingEventsByDay(wasteTypes: filteredTypes, people: people, days: 60)
    }

    private var wasteDays: [(day: Date, events: [CalendarEvent])] {
        upcomingDays.compactMap { entry in
            let waste = entry.events.filter { $0.kind == .waste }
            return waste.isEmpty ? nil : (day: entry.day, events: waste)
        }
    }

    private var upcomingBirthdays: [CalendarEvent] {
        upcomingDays.flatMap { $0.events }.filter { $0.kind == .birthday }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !notifications.isAuthorized {
                        permissionBanner
                    }
                    heroCard
                    nextPickupsSection
                    birthdaysSection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Übersicht")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LocationFilterMenu(locations: locations)
                }
            }
            .refreshable {
                await notifications.reschedule(using: context)
            }
        }
    }

    // MARK: - Hinweis auf fehlende Berechtigung

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Erinnerungen sind aus")
                    .font(.subheadline.weight(.semibold))
                Text("Erlaube Mitteilungen, damit du keinen Gelben Sack mehr verpasst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(notifications.authorizationStatus == .denied ? "Einstellungen" : "Erlauben") {
                if notifications.authorizationStatus == .denied {
                    notifications.openSystemSettings()
                } else {
                    Task {
                        await notifications.requestAuthorization()
                        await notifications.reschedule(using: context)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .card()
    }

    // MARK: - Hero

    private var heroCard: some View {
        let next = wasteDays.first
        let gradientColor = next?.events.first?.color ?? Color.accentColor

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heroEyebrow(for: next))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .opacity(0.85)
                    Text(heroTitle(for: next))
                        .font(.title.weight(.bold))
                }
                Spacer()
                Image(systemName: next == nil ? "checkmark.circle.fill" : (next?.events.first?.symbolName ?? "trash.fill"))
                    .font(.system(size: 44, weight: .semibold))
                    .opacity(0.9)
            }

            if let next {
                FlowLayout(spacing: 8) {
                    ForEach(next.events) { event in
                        EventChip(event: event)
                    }
                }
                Text(DateText.long(next.day))
                    .font(.subheadline)
                    .opacity(0.9)
            } else {
                Text("Lege im Tab „Müll“ Termine an oder aktualisiere deine Standorte.")
                    .font(.subheadline)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [gradientColor, gradientColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: gradientColor.opacity(0.4), radius: 16, x: 0, y: 8)
        )
    }

    private func heroEyebrow(for next: (day: Date, events: [CalendarEvent])?) -> String {
        guard let next else { return "Alles ruhig" }
        switch DateText.daysUntil(next.day) {
        case 0: return "Heute"
        case 1: return "Morgen"
        default: return "Nächste Abholung"
        }
    }

    private func heroTitle(for next: (day: Date, events: [CalendarEvent])?) -> String {
        guard let next else { return "Keine Abholung geplant" }
        switch DateText.daysUntil(next.day) {
        case 0: return "Heute wird abgeholt"
        case 1: return "Heute Abend rausstellen!"
        case let days: return "In \(days) Tagen"
        }
    }

    // MARK: - Nächste Abholungen

    private var nextPickupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Nächste Abholungen", systemImage: "trash.fill")
            if wasteDays.isEmpty {
                Text("Keine Abholungen in den nächsten 60 Tagen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(wasteDays.prefix(8).enumerated()), id: \.element.day) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DateText.countdown(entry.day))
                                    .font(.subheadline.weight(.semibold))
                                Text(DateText.short(entry.day))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 92, alignment: .leading)
                            FlowLayout(spacing: 6) {
                                ForEach(entry.events) { event in
                                    EventChip(event: event, onLight: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        if index < min(wasteDays.count, 8) - 1 {
                            Divider()
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Geburtstage

    private var birthdaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Geburtstage", systemImage: "birthday.cake.fill")
            if upcomingBirthdays.isEmpty {
                Text(people.isEmpty ? "Noch keine Geburtstage eingetragen." : "In den nächsten 60 Tagen hat niemand Geburtstag.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingBirthdays.prefix(6).enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 12) {
                            SymbolBadge(symbolName: "gift.fill", colorHex: event.colorHex, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.body.weight(.semibold))
                                Text("\(event.subtitle) · \(DateText.short(event.date))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DateText.countdown(event.date))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DateText.daysUntil(event.date) == 0 ? Color.pink : .secondary)
                        }
                        .padding(.vertical, 8)
                        if index < min(upcomingBirthdays.count, 6) - 1 {
                            Divider()
                        }
                    }
                }
                .card()
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.leading, 4)
    }
}

/// Einfaches Umbruch-Layout für Chips (iOS 16+ Layout-Protokoll).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: maxWidth == .infinity ? totalWidth : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
