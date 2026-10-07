import SwiftUI
import SwiftData
import TonneCore

struct WasteListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Location.sortOrder) private var locations: [Location]
    @Query(sort: \WasteType.sortOrder) private var wasteTypes: [WasteType]

    @State private var path = NavigationPath()
    @State private var showWizard = false
    @State private var showManualLocation = false
    @State private var newTypeLocation: Location?
    @State private var syncingID: UUID?
    @State private var message: String?

    private var orphanTypes: [WasteType] { wasteTypes.filter { $0.location == nil } }

    private var canSyncAny: Bool { locations.contains(where: \.canSync) }

    private var showMessage: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(locations) { location in
                    locationSection(location)
                }
                if !orphanTypes.isEmpty {
                    orphanSection
                }
                if locations.isEmpty {
                    ContentUnavailableView("Noch kein Standort", systemImage: "house", description: Text("Finde deinen Entsorger – die Termine kommen automatisch."))
                }
            }
            .navigationTitle("Müll")
            .navigationDestination(for: WasteType.self) { WasteDetailView(type: $0) }
            .navigationDestination(for: Location.self) { LocationDetailView(location: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .sheet(isPresented: $showWizard) { SourceWizardView(location: nil).environmentObject(model) }
            .sheet(isPresented: $showManualLocation) { NewLocationSheet { path.append($0) } }
            .sheet(item: $newTypeLocation) { NewWasteTypeSheet(location: $0) }
            .alert("Hinweis", isPresented: showMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: Teile der Liste

    private func locationSection(_ location: Location) -> some View {
        Section {
            LocationRow(location: location, isSyncing: syncingID == location.id) {
                Task { await sync(location) }
            }
            ForEach(location.sortedWasteTypes) { type in
                NavigationLink(value: type) { WasteTypeRow(type: type) }
            }
            .onDelete { offsets in
                delete(offsets.map { location.sortedWasteTypes[$0] })
            }
            Button {
                newTypeLocation = location
            } label: {
                Label("Müllart hinzufügen", systemImage: "plus.circle.fill")
            }
        }
    }

    private var orphanSection: some View {
        Section("Ohne Standort") {
            ForEach(orphanTypes) { type in
                NavigationLink(value: type) { WasteTypeRow(type: type) }
            }
            .onDelete { offsets in
                delete(offsets.map { orphanTypes[$0] })
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                showWizard = true
            } label: {
                Label("Standort mit Entsorger anlegen", systemImage: "antenna.radiowaves.left.and.right")
            }
            Button {
                showManualLocation = true
            } label: {
                Label("Standort manuell anlegen", systemImage: "pencil")
            }
            Button {
                Task { await syncAll() }
            } label: {
                Label("Alle aktualisieren", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!canSyncAny)
            NavigationLink {
                WasteABCView()
            } label: {
                Label("Abfall-ABC", systemImage: "book.fill")
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    private func delete(_ types: [WasteType]) {
        types.forEach { context.delete($0) }
        try? context.save()
        Task { await model.refreshAll() }
    }

    private func sync(_ location: Location) async {
        syncingID = location.id
        defer { syncingID = nil }
        do {
            let result = try await model.sync(location: location)
            message = result.summaryText
        } catch {
            message = error.localizedDescription
        }
    }

    private func syncAll() async {
        let messages = await model.syncAll(force: true)
        message = messages.joined(separator: "\n")
    }
}

/// Kopfzeile eines Standorts in der Müll-Liste.
private struct LocationRow: View {
    let location: Location
    let isSyncing: Bool
    let onSync: () -> Void

    var body: some View {
        NavigationLink(value: location) {
            HStack(spacing: 12) {
                SymbolBadge(symbolName: location.symbolName, colorHex: location.colorHex, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.headline)
                    Text(location.sourceDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let updated = updatedText {
                        Text(updated).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if location.canSync {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Button(action: onSync) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.body.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var updatedText: String? {
        guard let last = location.lastSyncAt else { return nil }
        return "Aktualisiert \(last.formatted(.relative(presentation: .named)))"
    }
}

struct WasteTypeRow: View {
    let type: WasteType
    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbolName: type.symbolName, colorHex: type.colorHex, size: 40, wasteName: type.name).opacity(type.isActive ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(type.name).font(.body.weight(.semibold)).foregroundStyle(type.isActive ? .primary : .secondary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !type.remindersEnabled { Image(systemName: "bell.slash").font(.caption).foregroundStyle(.tertiary) }
        }
    }
    private var subtitle: String {
        guard type.isActive else { return "Deaktiviert" }
        guard let next = type.nextPickup else { return type.hasSchedule ? "Keine weiteren Termine" : "Noch keine Termine" }
        return "\(DateText.countdown(next)) · \(DateText.short(next))"
    }
}

struct NewWasteTypeSheet: View {
    let location: Location?
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var category: WasteCategory = .residual
    @State private var name = WasteCategory.residual.name
    @State private var colorHex = WasteCategory.residual.colorHex
    @State private var symbolName = WasteCategory.residual.symbolName
    @State private var intervalWeeks = 2
    @State private var anchorDate = Days.today()

    var body: some View {
        NavigationStack {
            Form {
                Section("Art") {
                    Picker("Art", selection: $category) {
                        ForEach(WasteCategory.allCases, id: \.self) { category in Label { Text(category.name) } icon: { Image.waste(category.symbolName, name: category.name) }.tag(category) }
                    }
                    .onChange(of: category) { _, new in name = new == .other ? "" : new.name; colorHex = new.colorHex; symbolName = new.symbolName }
                    TextField("Name", text: $name)
                }
                Section("Darstellung") {
                    PaletteColorPicker(colorHex: $colorHex)
                    SymbolPicker(symbolName: $symbolName, colorHex: colorHex, wasteName: name)
                }
                Section("Rhythmus") {
                    Picker("Abstand", selection: $intervalWeeks) {
                        Text("Nur Einzeltermine").tag(0)
                        ForEach([1, 2, 3, 4, 6, 8], id: \.self) { Text($0 == 1 ? "Jede Woche" : "Alle \($0) Wochen").tag($0) }
                    }
                    if intervalWeeks > 0 { DatePicker("Ein Abholtag", selection: $anchorDate, displayedComponents: .date) }
                }
            }
            .navigationTitle("Neue Müllart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        let type = WasteType(name: name.trimmingCharacters(in: .whitespaces), category: category, colorHex: colorHex, symbolName: symbolName, sortOrder: model.allWasteTypes().count)
                        type.intervalWeeks = intervalWeeks
                        type.anchorDate = intervalWeeks > 0 ? Days.start(of: anchorDate) : nil
                        context.insert(type)
                        type.location = location
                        try? context.save()
                        Task { await model.refreshAll() }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct NewLocationSheet: View {
    var onCreate: (Location) -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var colorHex = "#2E9E6B"
    @State private var symbolName = "house.fill"

    var body: some View {
        NavigationStack {
            Form {
                Section("Standort") {
                    TextField("Name (z. B. Zuhause)", text: $name)
                    TextField("Adresse", text: $address)
                }
                Section("Darstellung") {
                    PaletteColorPicker(colorHex: $colorHex)
                    SymbolPicker(symbolName: $symbolName, colorHex: colorHex, symbols: Palette.homeSymbols)
                }
            }
            .navigationTitle("Neuer Standort").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        let location = Location(name: name.trimmingCharacters(in: .whitespaces), address: address, symbolName: symbolName, colorHex: colorHex, sortOrder: model.allLocations().count)
                        context.insert(location)
                        try? context.save()
                        model.onboardingDone = true
                        dismiss()
                        onCreate(location)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
