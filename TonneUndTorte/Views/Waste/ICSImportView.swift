import SwiftUI
import SwiftData

/// Zuordnung der Titel aus einer ICS-Datei zu Müllarten, dann Import.
struct ICSImportView: View {
    let events: [ICSEvent]
    let location: Location?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mappings: [CalendarImporter.Mapping] = []
    @State private var replaceExisting = true

    private var dateRange: String {
        guard let first = events.first?.date, let last = events.last?.date else { return "" }
        return "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Termine", value: "\(events.count)")
                    LabeledContent("Zeitraum", value: dateRange)
                    if let location {
                        LabeledContent("Standort", value: location.name)
                    }
                }

                Section {
                    ForEach($mappings) { $mapping in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(mapping.summary)
                                    .font(.body.weight(.semibold))
                                Spacer()
                                Text("\(mapping.count)×")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Picker("Ziel", selection: $mapping.target) {
                                Text("Ignorieren").tag(CalendarImporter.Target.ignore)
                                if let location {
                                    ForEach(location.sortedWasteTypes) { type in
                                        Label(type.name, systemImage: type.symbolName)
                                            .tag(CalendarImporter.Target.existing(type))
                                    }
                                }
                                ForEach(WastePreset.allCases) { preset in
                                    Label("Neu: \(preset == .sonstiges ? mapping.summary : preset.name)", systemImage: preset.symbolName)
                                        .tag(CalendarImporter.Target.new(preset))
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Zuordnung")
                } footer: {
                    Text("„Neu“ legt eine Müllart mit dem Namen aus der Datei und der Farbe der Vorlage an.")
                }

                Section {
                    Toggle("Bisherige Einzeltermine ersetzen", isOn: $replaceExisting)
                } footer: {
                    Text("Aus: Termine werden nur ergänzt. An: Die Müllart übernimmt genau die Termine aus der Datei.")
                }
            }
            .navigationTitle("ICS importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") { importNow() }
                        .disabled(mappings.allSatisfy { $0.target == .ignore })
                }
            }
            .onAppear {
                if mappings.isEmpty {
                    mappings = CalendarImporter.suggestMappings(for: events, location: location)
                }
            }
        }
    }

    private func importNow() {
        CalendarImporter.apply(events: events, mappings: mappings, location: location, context: context, replace: replaceExisting)
        location?.lastSyncMessage = "ICS-Datei importiert"
        try? context.save()
        Task { await NotificationManager.shared.reschedule(using: context) }
        dismiss()
    }
}
