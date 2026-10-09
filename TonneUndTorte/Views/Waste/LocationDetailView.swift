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
    /// CSV der Termine – nur beim Öffnen und nach einem Abgleich berechnet, nicht bei jedem Tastendruck.
    @State private var exportCSV: String?

    /// ICS und CSV (Excel/Numbers-Export); das Format wird beim Lesen am Inhalt erkannt.
    static let importTypes: [UTType] = [UTType(filenameExtension: "ics") ?? .data, .calendarEvent, .commaSeparatedText,
                                        UTType(filenameExtension: "csv") ?? .data, .text, .data]

    private var title: String { location.name.isEmpty ? L10n.t("Standort", "Location") : location.name }

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
        .onAppear(perform: updateExport)
        .onChange(of: location.lastSyncAt) { _, _ in updateExport() }
        .onChange(of: location.lastSyncMessage) { _, _ in updateExport() }
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
            if let notice = location.source.flatMap({ ProviderFactory.make($0).notice }) {
                Label(notice, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
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
                    Label("Verbindung trennen", systemImage: "xmark.circle")
                }
            }
            Button {
                showFileImporter = true
            } label: {
                Label(L10n.t("ICS- oder CSV-Datei importieren", "Import ICS or CSV file"), systemImage: "square.and.arrow.down")
            }
            if let exportCSV {
                ShareLink(item: PickupCSVFile(text: exportCSV, fileName: "\(location.name.isEmpty ? "Abfuhrtermine" : location.name).csv"),
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
            Text(L10n.t("Verbundene Standorte gleichen ihre Termine wöchentlich automatisch ab. Verschiebt der Entsorger einen Termin, bekommst du eine Mitteilung. Ohne Anbindung: Termine in die CSV-Vorlage eintragen (Datum;Müllart, z. B. in Excel oder Numbers) und hier importieren.",
                        "Connected locations sync weekly. If the provider moves a date, you get a notification. Without a connection: fill in the CSV template (date;waste type, e.g. in Excel or Numbers) and import it here."))
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

    private func updateExport() {
        let rows = SyncService.csvRows(for: location)
        exportCSV = rows.isEmpty ? nil : PickupCSV.build(rows)
    }

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                importPickups = try SyncService.readPickupFile(at: url)
                if importPickups.isEmpty {
                    message = L10n.t("In der Datei wurden keine Termine gefunden. CSV-Dateien brauchen je Zeile ein Datum (z. B. 07.10.2026) und eine Müllart.",
                                     "No dates found in the file. CSV files need a date (e.g. 07.10.2026) and a waste type per line.")
                } else {
                    showImport = true
                }
            } catch {
                message = (error as? SyncService.ImportError)?.errorDescription
                    ?? L10n.t("Datei konnte nicht gelesen werden: \(error.localizedDescription)", "Could not read the file: \(error.localizedDescription)")
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
    /// Legt den Standort erst beim Importieren an (Einrichtungsassistent) – bei Abbruch bleibt nichts zurück.
    var makeLocation: (() -> Location)? = nil
    /// Nach erfolgreichem Import, z. B. um den Assistenten zu schließen (schließt dann auch diese Ansicht).
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
                    LabeledContent(L10n.t("Termine", "Dates"), value: "\(pickups.count)")
                    if let first = pickups.first?.date, let last = pickups.last?.date {
                        LabeledContent(L10n.t("Zeitraum", "Period"), value: "\(DateText.short(first)) – \(DateText.short(last))")
                    }
                }
                Section(L10n.t("Zuordnung", "Assignment")) {
                    ForEach($mappings) { $mapping in
                        MappingRow(mapping: $mapping, existingTypes: location?.sortedWasteTypes ?? [])
                    }
                }
                Section {
                    Toggle(L10n.t("Bisherige Einzeltermine ersetzen", "Replace existing single dates"), isOn: $replace)
                } footer: {
                    if replace && replacesRhythm {
                        Text(L10n.t("Achtung: Bei Müllarten mit festem Rhythmus wird der Rhythmus durch die importierten Termine ersetzt.",
                                    "Note: for waste types with a fixed rhythm, the rhythm is replaced by the imported dates."))
                    }
                }
            }
            .navigationTitle(L10n.t("Termine importieren", "Import dates"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.t("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Importieren", "Import"), action: importNow).disabled(nothingSelected)
                }
            }
            .onAppear {
                guard mappings.isEmpty else { return }
                mappings = SyncService.suggestMappings(for: pickups, location: location, exclusive: false)
                // Nur ergänzen statt ersetzen, wenn sonst ein fester Rhythmus verloren ginge
                if replacesRhythm { replace = false }
            }
        }
    }

    private var nothingSelected: Bool { mappings.allSatisfy { $0.target == .ignore } }

    /// Eine Zuordnung zielt auf eine vorhandene Müllart mit festem Rhythmus.
    private var replacesRhythm: Bool {
        mappings.contains { mapping in
            if case .existing(let type) = mapping.target { return type.intervalWeeks > 0 }
            return false
        }
    }

    private func importNow() {
        let target = location ?? makeLocation?()
        SyncService.apply(pickups: pickups, mappings: mappings, location: target, context: context, replace: replace)
        target?.lastSyncMessage = L10n.t("Datei importiert (\(L10n.dates(pickups.count)))", "File imported (\(L10n.dates(pickups.count)))")
        try? context.save()
        Task { await model.refreshAll() }
        if let onImported { onImported() } else { dismiss() }
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
            Picker(L10n.t("Ziel", "Target"), selection: $mapping.target) {
                Text(L10n.t("Ignorieren", "Ignore")).tag(SyncService.Target.ignore)
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
        L10n.t("Neu: \(mapping.summary) (\(category.name))", "New: \(mapping.summary) (\(category.name))")
    }
}

/// Abfuhrtermine als CSV-Datei zum Teilen (Excel, Numbers, Mail).
struct PickupCSVFile: Transferable {
    let text: String
    var fileName = "Abfuhrtermine.csv"
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            // Eigener Unterordner je Export, damit sich gleichzeitige Exporte nicht überschreiben
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(file.safeFileName)
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
