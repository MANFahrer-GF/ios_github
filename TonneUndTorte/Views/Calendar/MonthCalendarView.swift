import SwiftUI
import SwiftData

/// Monatsansicht mit farbigen Punkten je Müllart und Torte für Geburtstage.
struct MonthCalendarView: View {
    @Query(sort: \Location.sortOrder) private var locations: [Location]
    @Query(sort: \WasteType.sortOrder) private var wasteTypes: [WasteType]
    @Query(sort: \Person.name) private var people: [Person]
    @AppStorage(LocationFilter.key) private var filterID: String = ""

    @State private var monthStart: Date = MonthCalendarView.firstOfMonth(Date())
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var filteredTypes: [WasteType] {
        LocationFilter.apply(wasteTypes, filterID: filterID)
    }

    private var monthEnd: Date {
        let next = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return calendar.date(byAdding: .day, value: -1, to: next) ?? monthStart
    }

    private var eventsByDay: [Date: [CalendarEvent]] {
        let events = EventEngine.events(wasteTypes: filteredTypes, people: people, from: monthStart, to: monthEnd)
        return Dictionary(grouping: events, by: { $0.date })
    }

    /// Alle Zellen des Rasters: führende `nil`-Einträge für die Tage vor dem Monatsersten.
    private var gridDays: [Date?] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for dayIndex in 0..<count {
            cells.append(calendar.date(byAdding: .day, value: dayIndex, to: monthStart))
        }
        return cells
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
                    calendarGrid
                        .card(padding: 12)
                    selectedDaySection
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kalender")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    LocationFilterMenu(locations: locations)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Heute") { goToToday() }
                }
            }
        }
    }

    // MARK: - Kopf

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            Spacer()
            Text(DateText.monthYear(monthStart))
                .font(.title3.weight(.bold))
            Spacer()
            Button { shiftMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Raster

    private var calendarGrid: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 {
                        shiftMonth(by: 1)
                    } else if value.translation.width > 40 {
                        shiftMonth(by: -1)
                    }
                }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let events = eventsByDay[day] ?? []
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasBirthday = events.contains { $0.kind == .birthday }
        let wasteColors = events.filter { $0.kind == .waste }.map { $0.color }

        return VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: day))")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.15) : .clear))
                )
                .foregroundStyle(isSelected ? .white : (isToday ? Color.accentColor : .primary))
            HStack(spacing: 3) {
                ForEach(Array(wasteColors.prefix(4).enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                if hasBirthday {
                    Image(systemName: "birthday.cake.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.pink)
                }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { selectedDay = day }
        }
    }

    // MARK: - Ausgewählter Tag

    private var selectedDaySection: some View {
        let events = eventsByDay[selectedDay] ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DateText.long(selectedDay))
                    .font(.headline)
                Spacer()
                Text(DateText.countdown(selectedDay))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            if events.isEmpty {
                Text("Nichts geplant – freier Tag für die Tonne.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event)
                            .padding(.vertical, 8)
                        if index < events.count - 1 {
                            Divider()
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Navigation

    private func shiftMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: monthStart) else { return }
        withAnimation(.snappy) {
            monthStart = MonthCalendarView.firstOfMonth(next)
            if !calendar.isDate(selectedDay, equalTo: monthStart, toGranularity: .month) {
                selectedDay = monthStart
            }
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            monthStart = MonthCalendarView.firstOfMonth(Date())
            selectedDay = calendar.startOfDay(for: Date())
        }
    }

    static func firstOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
