import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import TonneCore

struct LocationDetailView: View {
    @Bindable var location: Location
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showWizard = false
    @State private var showFileImporter = false
    @State private var importPickups: [Pickup] = []
    @State private var showImport = false
    @State private var isSyncing = false
    @State private var message: String?
    @State private var showDeleteConfirm = false

    private static let icsTypes: [UTType] = [UTType(filenameExtension: "ics") ?? .data, .calendarEvent, .text, .data]

    private var title: String { location.name.isEmpty ? "Standort" : location.name }

    private var showMessage: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    var body: some View {
        Form {
            nameSection
            appearanceSection
            sourceSection
            wasteTypesSection
            deleteSection
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showWizard) { SourceWizardView(location: location).environmentObject(model) }
        .sheet(isPresented: $showImport) { ICSImportView(pickups: importPickups, location: location) }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: Self.icsTypes, onCompletion: handleFile)
        .alert("Hinweis", isPresented: showMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("Standort und alle Müllarten löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                dismiss()
                model.deleteLater(location)
            }
        }
        .onDisappear {
            try? context.save()
            Task { await model.refreshAll() }
        }
    }

    // MARK: Abschnitte

    private var nameSection: some View {
        Section("Standort") {
            TextField("Name", text: $location.name)
            TextField("Adresse", text: $location.address)
        }
    }

    private var appearanceSection: some View {
        Section("Darstellung") {
            PaletteColorPicker(colorHex: $location.colorHex)
            SymbolPicker(symbolName: $location.symbolName, colorHex: location.colorHex, symbols: Palette.homeSymbols)
        }
    }

    private var sourceSection: some View {
        Section {
            LabeledContent("Quelle", value: location.sourceDescription)
            if let last = location.lastSyncAt {
                LabeledContent("Letzter Abgleich", value: last.formatted(date: .abbreviated, time: .shortened))
            }
            if let status = location.lastSyncMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                showWizard = true
            } label: {
                Label(location.canSync ? "Entsorger oder Adresse ändern" : "Entsorger verbinden", systemImage: "antenna.radiowaves.left.and.right")
            }
            if location.canSync {
                syncButton
                Button(role: .destructive) {
                    location.source = nil
                    try? context.save()
                } label: {
                    Label("Verbindung trennen", systemImage: "link.badge.plus")
                }
            }
            Button {
                showFileImporter = true
            } label: {
                Label("ICS-Datei importieren", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Abfuhrtermine")
        } footer: {
            Text("Verbundene Standorte gleichen ihre Termine wöchentlich automatisch ab. Verschiebt der Entsorger einen Termin, bekommst du eine Mitteilung.")
        }
    }

    private var syncButton: some View {
        Button {
            Task { await sync() }
        } label: {
            HStack {
                Label("Jetzt aktualisieren", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if isSyncing { ProgressView() }
            }
        }
        .disabled(isSyncing)
    }

    private var wasteTypesSection: some View {
        Section("Müllarten") {
            if location.sortedWasteTypes.isEmpty {
                Text("Noch keine Müllarten.").foregroundStyle(.secondary)
            }
            ForEach(location.sortedWasteTypes) { type in
                NavigationLink(value: type) { WasteTypeRow(type: type) }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Standort löschen", systemImage: "trash")
            }
        }
    }

    // MARK: Aktionen

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                importPickups = try SyncService.readICSFile(at: url)
                if importPickups.isEmpty {
                    message = "In der Datei wurden keine Termine gefunden."
                } else {
                    showImport = true
                }
            } catch {
                message = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await model.sync(location: location)
            message = result.summaryText
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ICSImportView: View {
    let pickups: [Pickup]
    let location: Location?
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var mappings: [SyncService.Mapping] = []
    @State private var replace = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Termine", value: "\(pickups.count)")
                    if let first = pickups.first?.date, let last = pickups.last?.date {
                        LabeledContent("Zeitraum", value: "\(DateText.short(first)) – \(DateText.short(last))")
                    }
                }
                Section("Zuordnung") {
                    ForEach($mappings) { $mapping in
                        MappingRow(mapping: $mapping, existingTypes: location?.sortedWasteTypes ?? [])
                    }
                }
                Section { Toggle("Bisherige Einzeltermine ersetzen", isOn: $replace) }
            }
            .navigationTitle("ICS importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren", action: importNow).disabled(nothingSelected)
                }
            }
            .onAppear {
                if mappings.isEmpty { mappings = SyncService.suggestMappings(for: pickups, location: location) }
            }
        }
    }

    private var nothingSelected: Bool { mappings.allSatisfy { $0.target == .ignore } }

    private func importNow() {
        SyncService.apply(pickups: pickups, mappings: mappings, location: location, context: context, replace: replace)
        location?.lastSyncMessage = "ICS-Datei importiert"
        try? context.save()
        Task { await model.refreshAll() }
        dismiss()
    }
}

/// Eine Zeile der ICS-Zuordnung: Zusammenfassung aus der Datei und Auswahl der Ziel-Müllart.
private struct MappingRow: View {
    @Binding var mapping: SyncService.Mapping
    let existingTypes: [WasteType]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mapping.summary).font(.body.weight(.semibold))
                Spacer()
                Text("\(mapping.count)×").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Ziel", selection: $mapping.target) {
                Text("Ignorieren").tag(SyncService.Target.ignore)
                ForEach(existingTypes) { type in
                    Label { Text(type.name) } icon: { Image.waste(type.symbolName, name: type.name) }.tag(SyncService.Target.existing(type))
                }
                ForEach(WasteCategory.allCases, id: \.self) { category in
                    Label(newTitle(for: category), systemImage: category.symbolName).tag(SyncService.Target.new(category))
                }
            }
            .labelsHidden()
        }
    }

    private func newTitle(for category: WasteCategory) -> String {
        "Neu: \(mapping.summary) (\(category.name))"
    }
}
