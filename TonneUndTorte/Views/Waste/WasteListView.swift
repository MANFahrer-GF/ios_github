import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Verwaltung der Standorte und Müllarten.
struct WasteListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Location.sortOrder) private var locations: [Location]
    @Query(sort: \WasteType.sortOrder) private var wasteTypes: [WasteType]

    @State private var path = NavigationPath()
    @State private var newTypeLocation: Location?
    @State private var showNewType = false
    @State private var showNewLocation = false
    @State private var syncingLocationID: UUID?
    @State private var syncError: String?

    private var orphanTypes: [WasteType] {
        wasteTypes.filter { $0.location == nil }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(locations) { location in
                    Section {
                        locationRow(location)
                        ForEach(location.sortedWasteTypes) { type in
                            NavigationLink(value: type) {
                                WasteTypeRow(type: type)
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { location.sortedWasteTypes[$0] })
                        }
                        Button {
                            newTypeLocation = location
                            showNewType = true
                        } label: {
                            Label("Müllart hinzufügen", systemImage: "plus.circle.fill")
                        }
                    }
                }

                if !orphanTypes.isEmpty {
                    Section("Ohne Standort") {
                        ForEach(orphanTypes) { type in
                            NavigationLink(value: type) {
                                WasteTypeRow(type: type)
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { orphanTypes[$0] })
                        }
                    }
                }

                if locations.isEmpty && orphanTypes.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Standorte",
                        systemImage: "house",
                        description: Text("Lege einen Standort an und hole dir die Abfuhrtermine online oder per ICS-Datei.")
                    )
                }
            }
            .navigationTitle("Müll")
            .navigationDestination(for: WasteType.self) { type in
                WasteDetailView(type: type)
            }
            .navigationDestination(for: Location.self) { location in
                LocationDetailView(location: location)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showNewLocation = true
                        } label: {
                            Label("Standort hinzufügen", systemImage: "mappin.circle")
                        }
                        if !locations.isEmpty {
                            Menu {
                                ForEach(locations) { location in
                                    Button(location.name) {
                                        newTypeLocation = location
                                        showNewType = true
                                    }
                                }
                            } label: {
                                Label("Müllart hinzufügen", systemImage: "plus.circle")
                            }
                        }
                        Button {
                            Task { await syncAll() }
                        } label: {
                            Label("Alle Standorte aktualisieren", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!locations.contains { $0.canSync })
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewType) {
                NewWasteTypeSheet(location: newTypeLocation)
            }
            .sheet(isPresented: $showNewLocation) {
                NewLocationSheet { location in
                    path.append(location)
                }
            }
            .alert("Aktualisierung fehlgeschlagen", isPresented: Binding(
                get: { syncError != nil },
                set: { if !$0 { syncError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncError ?? "")
            }
        }
    }

    // MARK: - Standortzeile

    private func locationRow(_ location: Location) -> some View {
        NavigationLink(value: location) {
            HStack(spacing: 12) {
                SymbolBadge(symbolName: location.symbolName, colorHex: location.colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.headline)
                    if !location.address.isEmpty {
                        Text(location.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let last = location.lastSyncAt {
                        Text("Aktualisiert \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if location.canSync {
                    if syncingLocationID == location.id {
                        ProgressView()
                    } else {
                        Button {
                            Task { await sync(location) }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Aktionen

    private func delete(_ types: [WasteType]) {
        for type in types {
            context.delete(type)
        }
        try? context.save()
        Task { await NotificationManager.shared.reschedule(using: context) }
    }

    private func sync(_ location: Location) async {
        syncingLocationID = location.id
        defer { syncingLocationID = nil }
        do {
            _ = try await CalendarImporter.sync(location: location, context: context)
            await NotificationManager.shared.reschedule(using: context)
        } catch {
            location.lastSyncMessage = "Fehler: \(error.localizedDescription)"
            syncError = error.localizedDescription
        }
    }

    private func syncAll() async {
        for location in locations where location.canSync {
            await sync(location)
        }
    }
}

/// Zeile einer Müllart mit nächstem Termin.
struct WasteTypeRow: View {
    let type: WasteType

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbolName: type.symbolName, colorHex: type.colorHex, size: 40)
                .opacity(type.isActive ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(type.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(type.isActive ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !type.remindersEnabled {
                Image(systemName: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var subtitle: String {
        guard type.isActive else { return "Deaktiviert" }
        guard let next = EventEngine.nextPickup(for: type) else {
            return type.hasSchedule ? "Keine weiteren Termine" : "Noch keine Termine"
        }
        return "\(DateText.countdown(next)) · \(DateText.short(next))"
    }
}

/// Neue Müllart anlegen – mit Vorlagen für die gängigen Tonnen.
struct NewWasteTypeSheet: View {
    let location: Location?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WasteType.sortOrder) private var allTypes: [WasteType]

    @State private var preset: WastePreset = .restmuell
    @State private var name: String = WastePreset.restmuell.name
    @State private var colorHex: String = WastePreset.restmuell.colorHex
    @State private var symbolName: String = WastePreset.restmuell.symbolName

    var body: some View {
        NavigationStack {
            Form {
                Section("Vorlage") {
                    Picker("Vorlage", selection: $preset) {
                        ForEach(WastePreset.allCases) { preset in
                            Label(preset.name, systemImage: preset.symbolName).tag(preset)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: preset) { _, newValue in
                        name = newValue == .sonstiges ? "" : newValue.name
                        colorHex = newValue.colorHex
                        symbolName = newValue.symbolName
                    }
                }
                Section("Darstellung") {
                    TextField("Name", text: $name)
                    PaletteColorPicker(colorHex: $colorHex)
                    SymbolPicker(symbolName: $symbolName, colorHex: colorHex)
                }
                if let location {
                    Section {
                        Label(location.name, systemImage: location.symbolName)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Standort")
                    }
                }
            }
            .navigationTitle("Neue Müllart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let sortOrder = (allTypes.map(\.sortOrder).max() ?? -1) + 1
        let type = WasteType(
            name: name.trimmingCharacters(in: .whitespaces),
            colorHex: colorHex,
            symbolName: symbolName,
            sortOrder: sortOrder
        )
        context.insert(type)
        type.location = location
        try? context.save()
        dismiss()
    }
}

/// Neuen Standort anlegen.
struct NewLocationSheet: View {
    var onCreate: (Location) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Location.sortOrder) private var locations: [Location]

    @State private var name = ""
    @State private var address = ""
    @State private var colorHex = "#2E9E6B"
    @State private var symbolName = "house.fill"

    private let symbols = ["house.fill", "house.and.flag.fill", "building.2.fill", "tent.fill", "tree.fill", "car.fill", "building.columns.fill", "leaf.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Standort") {
                    TextField("Name (z. B. Gifhorn)", text: $name)
                    TextField("Adresse", text: $address)
                }
                Section("Darstellung") {
                    PaletteColorPicker(colorHex: $colorHex)
                    SymbolPicker(symbolName: $symbolName, colorHex: colorHex, symbols: symbols)
                }
                Section {
                    Text("Nach dem Anlegen kannst du die Abfuhrtermine aus dem AWIDO-Portal, per ICS-Link oder aus einer ICS-Datei laden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Neuer Standort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        let location = Location(
                            name: name.trimmingCharacters(in: .whitespaces),
                            address: address.trimmingCharacters(in: .whitespaces),
                            symbolName: symbolName,
                            colorHex: colorHex,
                            sortOrder: (locations.map(\.sortOrder).max() ?? -1) + 1
                        )
                        context.insert(location)
                        try? context.save()
                        dismiss()
                        onCreate(location)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
