import SwiftUI
import SwiftData

/// Eine Müllart bearbeiten: Darstellung, Rhythmus, Einzeltermine, Ausnahmen.
struct WasteDetailView: View {
    @Bindable var type: WasteType
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var newDate = Date()
    @State private var showAddDate = false
    @State private var moveSource: Date?
    @State private var moveTarget = Date()
    @State private var showDeleteConfirm = false

    private let intervalOptions: [(label: String, weeks: Int)] = [
        ("Kein fester Rhythmus", 0),
        ("Jede Woche", 1),
        ("Alle 2 Wochen", 2),
        ("Alle 3 Wochen", 3),
        ("Alle 4 Wochen", 4),
        ("Alle 6 Wochen", 6),
        ("Alle 8 Wochen", 8),
    ]

    private var upcoming: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        guard let horizon = Calendar.current.date(byAdding: .month, value: 6, to: today) else { return [] }
        return EventEngine.pickupDates(for: type, from: today, to: horizon)
    }

    private var upcomingSkipped: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return type.skippedDates.filter { $0 >= today }.sorted()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    SymbolBadge(symbolName: type.symbolName, colorHex: type.colorHex, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $type.name)
                            .font(.title3.weight(.semibold))
                        if let location = type.location {
                            Label(location.name, systemImage: location.symbolName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                Toggle("Aktiv", isOn: $type.isActive)
                Toggle("Erinnerungen", isOn: $type.remindersEnabled)
            }

            Section("Farbe & Symbol") {
                PaletteColorPicker(colorHex: $type.colorHex)
                SymbolPicker(symbolName: $type.symbolName, colorHex: type.colorHex)
            }

            Section {
                Picker("Rhythmus", selection: $type.intervalWeeks) {
                    ForEach(intervalOptions, id: \.weeks) { option in
                        Text(option.label).tag(option.weeks)
                    }
                }
                if type.intervalWeeks > 0 {
                    DatePicker("Ein Abholtag", selection: $type.anchorDate, displayedComponents: .date)
                }
            } header: {
                Text("Wiederkehrend")
            } footer: {
                if type.intervalWeeks > 0 {
                    Text("Von diesem Tag aus werden alle weiteren Termine im gewählten Abstand berechnet.")
                } else if type.sourceKey != nil {
                    Text("Diese Müllart bekommt ihre Termine aus dem Abfuhrkalender des Standorts (\(type.sourceKey ?? "")).")
                }
            }

            Section {
                if upcoming.isEmpty {
                    Text("Keine Termine in den nächsten 6 Monaten.")
                        .foregroundStyle(.secondary)
                }
                ForEach(upcoming.prefix(12), id: \.self) { date in
                    HStack {
                        Text(DateText.short(date))
                        Spacer()
                        Text(DateText.countdown(date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            type.skip(date)
                            touch()
                        } label: {
                            Label("Fällt aus", systemImage: "xmark.circle")
                        }
                        Button {
                            moveSource = date
                            moveTarget = date
                        } label: {
                            Label("Verschieben", systemImage: "arrow.right.circle")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                Text("Nächste Termine")
            } footer: {
                Text("Nach links wischen, um einen Termin zu verschieben oder ausfallen zu lassen (z. B. an Feiertagen).")
            }

            Section {
                Button {
                    newDate = Date()
                    showAddDate = true
                } label: {
                    Label("Einzeltermin hinzufügen", systemImage: "calendar.badge.plus")
                }
                if !type.explicitDates.isEmpty {
                    LabeledContent("Gespeicherte Einzeltermine", value: "\(type.explicitDates.count)")
                }
            } header: {
                Text("Einzeltermine")
            }

            if !upcomingSkipped.isEmpty {
                Section("Ausgefallene Termine") {
                    ForEach(upcomingSkipped, id: \.self) { date in
                        HStack {
                            Text(DateText.short(date))
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Wiederherstellen") {
                                type.unskip(date)
                                touch()
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Müllart löschen", systemImage: "trash")
                }
            }
        }
        .navigationTitle(type.name.isEmpty ? "Müllart" : type.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddDate) {
            datePickerSheet(title: "Einzeltermin", selection: $newDate) {
                type.addExplicitDate(newDate)
                touch()
            }
        }
        .sheet(isPresented: Binding(get: { moveSource != nil }, set: { if !$0 { moveSource = nil } })) {
            datePickerSheet(title: "Termin verschieben", selection: $moveTarget) {
                if let source = moveSource {
                    type.move(source, to: moveTarget)
                    touch()
                }
                moveSource = nil
            }
        }
        .confirmationDialog("„\(type.name)“ wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(type)
                try? context.save()
                Task { await NotificationManager.shared.reschedule(using: context) }
                dismiss()
            }
        }
        .onChange(of: type.intervalWeeks) { _, _ in touch() }
        .onChange(of: type.anchorDate) { _, _ in touch() }
        .onChange(of: type.isActive) { _, _ in touch() }
        .onChange(of: type.remindersEnabled) { _, _ in touch() }
        .onDisappear { touch() }
    }

    private func datePickerSheet(title: String, selection: Binding<Date>, onConfirm: @escaping () -> Void) -> some View {
        NavigationStack {
            VStack {
                DatePicker(title, selection: selection, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        showAddDate = false
                        moveSource = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        onConfirm()
                        showAddDate = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func touch() {
        try? context.save()
        Task { await NotificationManager.shared.reschedule(using: context) }
    }
}
