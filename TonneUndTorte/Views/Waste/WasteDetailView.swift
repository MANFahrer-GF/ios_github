import SwiftUI
import SwiftData
import TonneCore

struct WasteDetailView: View {
    @Bindable var type: WasteType
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pickDate = Days.today()
    @State private var showAddDate = false
    @State private var moveSource: Date?
    @State private var showDeleteConfirm = false

    private var upcoming: [Date] {
        type.pickupDates(from: Days.today(), to: Days.add(180, to: Days.today()))
    }
    private var upcomingSkipped: [Date] { type.skippedDates.filter { $0 >= Days.today() }.sorted() }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    SymbolBadge(symbolName: type.displaySymbol, colorHex: type.colorHex, size: 56, wasteName: type.name)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $type.name).font(.title3.weight(.semibold))
                        if let location = type.location { Label(location.name, systemImage: location.symbolName).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(.vertical, 4)
                Toggle("Aktiv", isOn: $type.isActive)
                Toggle("Erinnerungen", isOn: $type.remindersEnabled)
                Picker("Art", selection: Binding(get: { type.category }, set: { type.category = $0 })) {
                    ForEach(WasteCategory.allCases, id: \.self) { category in Label { Text(category.name) } icon: { Image.waste(category.symbolName, name: category.name) }.tag(category) }
                }
            }
            Section("Farbe & Symbol") {
                PaletteColorPicker(colorHex: $type.colorHex)
                WasteSymbolPicker(symbolName: $type.displaySymbol, colorHex: type.colorHex, wasteName: type.name)
            }
            Section {
                Picker("Rhythmus", selection: $type.intervalWeeks) {
                    Text("Kein fester Rhythmus").tag(0)
                    ForEach([1, 2, 3, 4, 6, 8], id: \.self) { Text($0 == 1 ? "Jede Woche" : "Alle \($0) Wochen").tag($0) }
                }
                if type.intervalWeeks > 0 {
                    DatePicker("Ein Abholtag", selection: Binding(get: { type.anchorDate ?? Days.today() }, set: { type.anchorDate = Days.start(of: $0) }), displayedComponents: .date)
                }
            } header: { Text("Wiederkehrend") } footer: {
                if type.sourceKey != nil, type.intervalWeeks == 0 { Text("Termine kommen aus dem Abfuhrkalender des Standorts („\(type.sourceKey ?? "")“).") }
            }
            Section {
                if upcoming.isEmpty { Text("Keine Termine in den nächsten 6 Monaten.").foregroundStyle(.secondary) }
                ForEach(upcoming.prefix(14), id: \.self) { date in
                    HStack {
                        Text(DateText.short(date))
                        if type.isDone(on: date) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        Spacer()
                        Text(DateText.countdown(date)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { type.skip(date); save() } label: { Label("Fällt aus", systemImage: "xmark.circle") }
                        Button { moveSource = date; pickDate = date } label: { Label("Verschieben", systemImage: "arrow.right.circle") }.tint(.orange)
                    }
                }
            } header: { Text("Nächste Termine") } footer: { Text("Nach links wischen: verschieben oder ausfallen lassen (Feiertage).") }
            Section("Einzeltermine") {
                Button { pickDate = Days.today(); showAddDate = true } label: { Label("Einzeltermin hinzufügen", systemImage: "calendar.badge.plus") }
                if !type.explicitDates.isEmpty { LabeledContent("Gespeicherte Einzeltermine", value: "\(type.explicitDates.count)") }
            }
            if !upcomingSkipped.isEmpty {
                Section("Ausgefallene Termine") {
                    ForEach(upcomingSkipped, id: \.self) { date in
                        HStack {
                            Text(DateText.short(date)).strikethrough().foregroundStyle(.secondary)
                            Spacer()
                            Button("Wiederherstellen") { type.unskip(date); save() }.font(.subheadline)
                        }
                    }
                }
            }
            Section { Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Müllart löschen", systemImage: "trash") } }
        }
        .navigationTitle(type.name.isEmpty ? "Müllart" : type.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddDate) { datePickerSheet("Einzeltermin") { type.addExplicitDate(pickDate); save() } }
        .sheet(isPresented: Binding(get: { moveSource != nil }, set: { if !$0 { moveSource = nil } })) {
            datePickerSheet("Termin verschieben") { if let source = moveSource { type.move(source, to: pickDate); save() }; moveSource = nil }
        }
        .confirmationDialog("„\(type.name)“ wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { dismiss(); model.deleteLater(type) }
        }
        .onChange(of: type.intervalWeeks) { _, _ in save() }
        .onChange(of: type.isActive) { _, _ in save() }
        .onChange(of: type.remindersEnabled) { _, _ in save() }
        .onDisappear { save() }
    }

    private func datePickerSheet(_ title: String, onConfirm: @escaping () -> Void) -> some View {
        NavigationStack {
            VStack {
                DatePicker(title, selection: $pickDate, displayedComponents: .date).datePickerStyle(.graphical).padding()
                Spacer()
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showAddDate = false; moveSource = nil } }
                ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { onConfirm(); showAddDate = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        try? context.save()
        Task { await model.refreshAll() }
    }
}

struct WasteABCView: View {
    @State private var query = ""
    var body: some View {
        List {
            ForEach(WasteABC.search(query)) { entry in
                HStack(spacing: 12) {
                    SymbolBadge(symbolName: entry.category.symbolName, colorHex: entry.category.colorHex, size: 36, wasteName: entry.category.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.body.weight(.semibold))
                        Text(entry.category.name + (entry.hint.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Was soll weg? z. B. Pizzakarton")
        .navigationTitle("Abfall-ABC")
    }
}
