import SwiftUI
import SwiftData
import TonneCore

/// Monatsansicht mit farbigen Punkten je Müllart, Torte für Geburtstage, Pin für eigene Termine.
struct MonthCalendarView: View {
    @EnvironmentObject private var model: AppModel
    @Query(sort: \Location.sortOrder) private var locations: [Location]
    @Query(sort: \WasteType.sortOrder) private var wasteTypes: [WasteType]
    @Query private var people: [Person]
    @Query private var customEvents: [CustomEvent]
    @AppStorage(SettingsKeys.locationFilter) private var filterID: String = ""

    @State private var monthStart = MonthCalendarView.firstOfMonth(Date())
    @State private var selectedDay = Days.today()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthEnd: Date {
        let next = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return Days.add(-1, to: next)
    }

    private var eventsByDay: [Date: [CalendarEvent]] {
        _ = wasteTypes.count + people.count + customEvents.count
        return Dictionary(grouping: model.events(from: monthStart, to: monthEnd, locationID: LocationFilter.apply(filterID)), by: \.date)
    }

    private var gridDays: [Date?] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        return Array(repeating: nil, count: offset) + (0..<count).map { Days.add($0, to: monthStart) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    calendarGrid.card(padding: 12)
                    selectedDaySection
                }
                .padding(.horizontal).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kalender")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Heute") { goToToday() } }
                ToolbarItem(placement: .topBarTrailing) { LocationFilterMenu(locations: locations) }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left").font(.headline).frame(width: 36, height: 36) }
            Spacer()
            Text(DateText.monthYear(monthStart)).font(.title3.weight(.bold))
            Spacer()
            Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right").font(.headline).frame(width: 36, height: 36) }
        }
        .padding(.top, 4)
    }

    private var calendarGrid: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 52) }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { shiftMonth(by: 1) } else if value.translation.width > 40 { shiftMonth(by: -1) }
        })
    }

    private func dayCell(_ day: Date) -> some View {
        let events = eventsByDay[day] ?? []
        let isSelected = day == selectedDay
        let isToday = calendar.isDateInToday(day)
        let wasteColors = events.filter { $0.kind == .waste }.map(\.color)
        return VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .frame(width: 30, height: 30)
                .background(Circle().fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.15) : .clear)))
                .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
            HStack(spacing: 3) {
                ForEach(Array(wasteColors.prefix(4).enumerated()), id: \.offset) { _, color in Circle().fill(color).frame(width: 6, height: 6) }
                if events.contains(where: { $0.kind == .birthday }) { Image(systemName: "birthday.cake.fill").font(.system(size: 8)).foregroundStyle(.pink) }
                if events.contains(where: { $0.kind == .custom }) { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.purple) }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity).frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { selectedDay = day } }
    }

    private var selectedDaySection: some View {
        let events = eventsByDay[selectedDay] ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DateText.long(selectedDay)).font(.headline)
                Spacer()
                Text(DateText.countdown(selectedDay)).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            if events.isEmpty {
                Text("Nichts geplant – freier Tag für die Tonne.").font(.subheadline).foregroundStyle(.secondary).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event).padding(.vertical, 8)
                        if index < events.count - 1 { Divider() }
                    }
                }
                .card()
            }
        }
    }

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: monthStart) else { return }
        withAnimation(.snappy) {
            monthStart = MonthCalendarView.firstOfMonth(next)
            if !calendar.isDate(selectedDay, equalTo: monthStart, toGranularity: .month) { selectedDay = monthStart }
        }
    }

    private func goToToday() {
        withAnimation(.snappy) { monthStart = MonthCalendarView.firstOfMonth(Date()); selectedDay = Days.today() }
    }

    static func firstOfMonth(_ date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components) ?? Days.start(of: date)
    }
}
