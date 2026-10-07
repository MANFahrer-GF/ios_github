import SwiftUI
import SwiftData
import TonneCore

/// Mehr: eigene Termine, Abfall-ABC, Kalender-Export, Einstellungen.
struct MoreView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(CalendarExport.autoSyncKey) private var calendarAutoSync = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { CustomEventsView() } label: { Label("Eigene Termine", systemImage: "pin.fill") }
                    NavigationLink { WasteABCView() } label: { Label("Abfall-ABC", systemImage: "book.fill") }
                }
                Section {
                    NavigationLink { CalendarSyncView() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kalender-Abgleich")
                                Text(calendarAutoSync ? L10n.t("Automatisch · \(CalendarExport.targetDescription())", "Automatic · \(CalendarExport.targetDescription())") : L10n.t("Aus", "Off"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "calendar")
                        }
                    }
                } header: {
                    Text("Kalender-App")
                } footer: {
                    Text("Termine in iCloud, Google oder Outlook eintragen und automatisch aktuell halten.")
                }
                Section {
                    NavigationLink { SettingsView() } label: { Label("Einstellungen", systemImage: "gearshape.fill") }
                }
            }
            .navigationTitle("Mehr")
        }
    }

}

/// ICS-Text als teilbare Datei.
struct FeedFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .calendarEvent) { file in Data(file.text.utf8) }
            .suggestedFileName("Tonne & Torte.ics")
    }
}

struct CustomEventsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomEvent.title) private var events: [CustomEvent]
    @State private var editing: CustomEvent?
    @State private var showNew = false

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView("Noch keine eigenen Termine", systemImage: "pin", description: Text("Hochzeitstag, TÜV, Rauchmelder – alles, was regelmäßig wiederkommt."))
            }
            ForEach(events.sorted { ($0.nextOccurrence ?? .distantFuture) < ($1.nextOccurrence ?? .distantFuture) }) { event in
                Button { editing = event } label: {
                    HStack(spacing: 12) {
                        SymbolBadge(symbolName: event.symbolName, colorHex: event.colorHex, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(event.recurrence.label + (event.nextOccurrence.map { " · \(DateText.short($0))" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let next = event.nextOccurrence { Text(DateText.countdown(next)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
                    }
                }
            }
            .onDelete { offsets in
                let sorted = events.sorted { ($0.nextOccurrence ?? .distantFuture) < ($1.nextOccurrence ?? .distantFuture) }
                offsets.forEach { context.delete(sorted[$0]) }
                try? context.save(); Task { await model.refreshAll() }
            }
        }
        .navigationTitle("Eigene Termine")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showNew) { CustomEventEditView(event: nil) }
        .sheet(item: $editing) { CustomEventEditView(event: $0) }
    }
}

struct CustomEventEditView: View {
    let event: CustomEvent?
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var symbolName = "star.fill"
    @State private var colorHex = "#7C3AED"
    @State private var startDate = Days.today()
    @State private var recurrenceIndex = 0
    @State private var remindDaysBefore = 1
    @State private var remindersEnabled = true
    @State private var notes = ""

    private let recurrences: [Recurrence] = [.yearly, .once, .everyWeeks(1), .everyWeeks(2), .everyWeeks(4), .everyMonths(1), .everyMonths(3), .everyMonths(6), .everyMonths(12), .everyMonths(24)]

    var body: some View {
        NavigationStack {
            Form {
                if event == nil {
                    Section("Vorlage") {
                        ForEach(CustomEvent.templates, id: \.title) { template in
                            Button {
                                title = template.title; symbolName = template.symbol; colorHex = template.color
                                recurrenceIndex = recurrences.firstIndex(of: template.recurrence) ?? 0
                            } label: { Label(template.title, systemImage: template.symbol).foregroundStyle(.primary) }
                        }
                    }
                }
                Section("Termin") {
                    TextField("Titel", text: $title)
                    DatePicker(recurrenceIndex == 1 ? "Datum" : "Erster Termin", selection: $startDate, displayedComponents: .date)
                    Picker("Wiederholung", selection: $recurrenceIndex) { ForEach(recurrences.indices, id: \.self) { Text(recurrences[$0].label).tag($0) } }
                }
                Section("Erinnerung") {
                    Toggle("Erinnern", isOn: $remindersEnabled)
                    Picker("Vorher", selection: $remindDaysBefore) {
                        ForEach([(0, "Am Tag selbst"), (1, "1 Tag vorher"), (3, "3 Tage vorher"), (7, "1 Woche vorher"), (14, "2 Wochen vorher"), (30, "1 Monat vorher")], id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("Darstellung") {
                    PaletteColorPicker(colorHex: $colorHex)
                    SymbolPicker(symbolName: $symbolName, colorHex: colorHex, symbols: Palette.eventSymbols)
                }
                Section("Notizen") { TextField("Notizen", text: $notes, axis: .vertical).lineLimit(2...5) }
                if let event {
                    Section { Button("Termin löschen", role: .destructive) { dismiss(); model.deleteLater(event) } }
                }
            }
            .navigationTitle(event == nil ? "Neuer Termin" : "Termin bearbeiten").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                guard let event else { return }
                title = event.title; symbolName = event.symbolName; colorHex = event.colorHex; startDate = event.startDate
                recurrenceIndex = recurrences.firstIndex(of: event.recurrence) ?? 0
                remindDaysBefore = event.remindDaysBefore; remindersEnabled = event.remindersEnabled; notes = event.notes
            }
        }
    }

    private func save() {
        let target = event ?? CustomEvent(title: title, startDate: startDate, recurrence: recurrences[recurrenceIndex])
        if event == nil { context.insert(target) }
        target.title = title.trimmingCharacters(in: .whitespaces); target.symbolName = symbolName; target.colorHex = colorHex
        target.startDate = Days.start(of: startDate); target.recurrence = recurrences[recurrenceIndex]
        target.remindDaysBefore = remindDaysBefore; target.remindersEnabled = remindersEnabled; target.notes = notes
        try? context.save()
        Task { await model.refreshAll() }
        dismiss()
    }
}
