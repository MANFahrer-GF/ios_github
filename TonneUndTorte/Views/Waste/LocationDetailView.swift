import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Standort bearbeiten: Darstellung, Datenquelle, Abgleich, ICS-Import, Löschen.
struct LocationDetailView: View {
    @Bindable var location: Location
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showAwidoSetup = false
    @State private var showFileImporter = false
    @State private var importEvents: [ICSEvent] = []
    @State private var showImport = false
    @State private var isSyncing = false
    @State private var message: String?
    @State private var showDeleteConfirm = false

    private let symbols = ["house.fill", "house.and.flag.fill", "building.2.fill", "tent.fill", "tree.fill", "car.fill", "building.columns.fill", "leaf.fill"]

    private var sourceKindBinding: Binding<Location.SourceKind> {
        Binding(get: { location.sourceKind }, set: { location.sourceKind = $0 })
    }

    private var icsURLBinding: Binding<String> {
        Binding(get: { location.icsURLString ?? "" }, set: { location.icsURLString = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        Form {
            Section("Standort") {
                TextField("Name", text: $location.name)
                TextField("Adresse", text: $location.address)
            }

            Section("Darstellung") {
                PaletteColorPicker(colorHex: $location.colorHex)
                SymbolPicker(symbolName: $location.symbolName, colorHex: location.colorHex, symbols: symbols)
            }

            Section {
                Picker("Quelle", selection: sourceKindBinding) {
                    Text("Manuell / Datei").tag(Location.SourceKind.manual)
                    Text("AWIDO-Portal").tag(Location.SourceKind.awido)
                    Text("ICS-Link (Abo)").tag(Location.SourceKind.icsURL)
                }

                switch location.sourceKind {
                case .manual:
                    Text("Termine werden von Hand gepflegt oder aus einer ICS-Datei importiert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .awido:
                    if let label = location.awidoLabel {
                        LabeledContent("Adresse", value: label)
                    }
                    Button {
                        showAwidoSetup = true
                    } label: {
                        Label(location.awidoOid == nil ? "Adresse im AWIDO-Portal wählen" : "Adresse ändern", systemImage: "mappin.and.ellipse")
                    }
                    Text("AWIDO wird u. a. vom Landkreis Gifhorn genutzt. Die Termine werden direkt vom Portal geladen und wöchentlich automatisch aktualisiert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .icsURL:
                    TextField("https://…/download?system=ical…", text: icsURLBinding)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Viele Abfall-Portale (z. B. landkreis-stendal.abfall-app.net) bieten einen Button „Sync zu Kalender“. Diesen Link hier einfügen – die App lädt die Termine dann wöchentlich neu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if location.canSync {
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

                if let status = location.lastSyncMessage {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status)
                            .font(.footnote)
                        if let last = location.lastSyncAt {
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Datenquelle")
            }

            Section {
                Button {
                    showFileImporter = true
                } label: {
                    Label("ICS-Datei importieren", systemImage: "square.and.arrow.down")
                }
                Text("Abfuhrkalender als .ics-Datei (z. B. aus der Abfall-App deines Landkreises) in diesen Standort übernehmen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Import")
            }

            Section("Müllarten") {
                if location.wasteTypes.isEmpty {
                    Text("Noch keine Müllarten.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(location.sortedWasteTypes) { type in
                        NavigationLink(value: type) {
                            WasteTypeRow(type: type)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Standort löschen", systemImage: "trash")
                }
            }
        }
        .navigationTitle(location.name.isEmpty ? "Standort" : location.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAwidoSetup) {
            AwidoSetupView(location: location)
        }
        .sheet(isPresented: $showImport) {
            ICSImportView(events: importEvents, location: location)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data, .calendarEvent, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    importEvents = try CalendarImporter.readICSFile(at: url)
                    if importEvents.isEmpty {
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
        .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("Standort und alle zugehörigen Müllarten löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(location)
                try? context.save()
                Task { await NotificationManager.shared.reschedule(using: context) }
                dismiss()
            }
        }
        .onDisappear {
            try? context.save()
            Task { await NotificationManager.shared.reschedule(using: context) }
        }
    }

    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let count = try await CalendarImporter.sync(location: location, context: context)
            message = "\(count) Termine übernommen."
            await NotificationManager.shared.reschedule(using: context)
        } catch {
            location.lastSyncMessage = "Fehler: \(error.localizedDescription)"
            message = error.localizedDescription
        }
    }
}
