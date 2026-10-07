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

    /// ICS und CSV (Excel/Numbers-Export); das Format wird beim Lesen am Inhalt erkannt.
    static let importTypes: [UTType] = [UTType(filenameExtension: "ics") ?? .data, .calendarEvent, .commaSeparatedText,
                                        UTType(filenameExtension: "csv") ?? .data, .text, .data]

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
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: Self.importTypes, onCompletion: handleFile)
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
                Label(L10n.t("ICS- oder CSV-Datei importieren", "Import ICS or CSV file"), systemImage: "square.and.arrow.down")
            }
            let rows = SyncService.csvRows(for: location)
            if !rows.isEmpty {
                ShareLink(item: PickupCSVFile(text: PickupCSV.build(rows), fileName: "\(location.name.isEmpty ? "Abfuhrtermine" : location.name).csv"),
                          preview: SharePreview(L10n.t("Abfuhrtermine (CSV)", "Pickup dates (CSV)"))) {
                    Label(L10n.t("Termine als CSV exportieren", "Export dates as CSV"), systemImage: "tablecells")
                }
            }
            ShareLink(item: PickupCSVFile(text: PickupCSV.template(), fileName: L10n.t("Abfuhrtermine-Vorlage.csv", "Pickup-template.csv")),
                      preview: SharePreview(L10n.t("CSV-Vorlage", "CSV template"))) {
                Label(L10n.t("CSV-Vorlage zum Ausfüllen", "CSV template to fill in"), systemImage: "doc.badge.plus")
            }
        } header: {
            Text("Abfuhrtermine")
        } footer: {
            Text(L10n.t("Verbundene Standorte gleichen ihre Termine wöchentlich automatisch ab. Verschiebt der Entsorger einen Termin, bekommst du eine Mitteilung. Ohne Anbindung: Termine in die CSV-Vorlage eintragen (Datum;Abfallart, z. B. in Excel oder Numbers) und hier importieren.",
                        "Connected locations sync weekly. If the operator moves a date, you get a notification. Without a connection: fill in the CSV template (date;waste type, e.g. in Excel or Numbers) and import it here."))
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
                importPickups = try SyncService.readPickupFile(at: url)
                if importPickups.isEmpty {
                    message = L10n.t("In der Datei wurden keine Termine gefunden. CSV-Dateien brauchen je Zeile ein Datum (z. B. 07.10.2026) und eine Abfallart.",
                                     "No dates found in the file. CSV files need a date (e.g. 2026-10-07) and a waste type per line.")
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
    /// Nach erfolgreichem Import (z. B. um den Assistenten zu schließen).
    var onImported: (() -> Void)? = nil
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
            .navigationTitle(L10n.t("Termine importieren", "Import dates"))
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
        location?.lastSyncMessage = L10n.t("Datei importiert (\(pickups.count) Termine)", "File imported (\(pickups.count) dates)")
        try? context.save()
        Task { await model.refreshAll() }
        dismiss()
        onImported?()
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
                    WasteLabel(title: type.name, symbolName: type.displaySymbol, name: type.name).tag(SyncService.Target.existing(type))
                }
                ForEach(WasteCategory.allCases, id: \.self) { category in
                    WasteCategoryLabel(category: category, title: newTitle(for: category)).tag(SyncService.Target.new(category))
                }
            }
            .labelsHidden()
        }
    }

    private func newTitle(for category: WasteCategory) -> String {
        "Neu: \(mapping.summary) (\(category.name))"
    }
}

/// Abfuhrtermine als CSV-Datei zum Teilen (Excel, Numbers, Mail).
struct PickupCSVFile: Transferable {
    let text: String
    var fileName = "Abfuhrtermine.csv"
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.safeFileName)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    /// Ohne Schrägstriche und Doppelpunkte, damit der Dateiname überall gültig ist.
    private var safeFileName: String {
        let cleaned = fileName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Abfuhrtermine.csv" : cleaned
    }
}
