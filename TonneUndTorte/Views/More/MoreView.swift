import SwiftUI
import SwiftData
import TonneCore

/// Mehr: eigene Termine, Abfall-ABC, Kalender-Export, Einstellungen.
struct MoreView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(CalendarExport.autoSyncKey) private var calendarAutoSync = false
    @State private var openedEvent: CustomEvent?

    private var syncSubtitle: String {
        guard calendarAutoSync else { return L10n.t("Aus", "Off") }
        let target = CalendarExport.targetDescription()
        return L10n.t("Automatisch · \(target)", "Automatic · \(target)")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { CustomEventsView() } label: { Label("Eigene Termine", systemImage: "pin.fill") }
                    NavigationLink { WasteABCView() } label: { Label("Abfall-ABC", systemImage: "book.fill") }
                    NavigationLink { CoverageView() } label: { Label(L10n.t("Geht mein Ort?", "Is my town covered?"), systemImage: "map.fill") }
                }
                Section {
                    NavigationLink { CalendarSyncView() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kalender-Abgleich")
                                Text(syncSubtitle)
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
                    NavigationLink { SiriView() } label: { Label("Siri & Kurzbefehle", systemImage: "waveform") }
                    NavigationLink { SettingsView() } label: { Label("Einstellungen", systemImage: "gearshape.fill") }
                }
            }
            .navigationTitle("Mehr")
            .sheet(item: $openedEvent) { CustomEventEditView(event: $0) }
            .onChange(of: model.eventToOpen, initial: true) { _, id in
                guard let id else { return }
                model.eventToOpen = nil
                openedEvent = model.allCustomEvents().first { $0.id == id }
            }
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
    private var doneKeys: Set<String> { SettingsKeys.customDoneKeys() }

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView("Noch keine eigenen Termine", systemImage: "pin", description: Text("Hochzeitstag, TÜV, Rauchmelder – alles, was regelmäßig wiederkommt."))
            }
            ForEach(events.sorted { ($0.nextOccurrence ?? .distantFuture) < ($1.nextOccurrence ?? .distantFuture) }) { event in
                let next = event.nextOccurrence
                let isDone = next.map { SettingsKeys.isCustomDone(id: event.id, day: $0, keys: doneKeys) } ?? false
                Button { editing = event } label: {
                    HStack(spacing: 12) {
                        SymbolBadge(symbolName: event.symbolName, colorHex: event.colorHex, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(event.recurrence.label + (event.nextOccurrence.map { " · \(DateText.short($0))" } ?? "") + (event.timeText.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isDone {
                            Label(L10n.t("Erledigt", "Done"), systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.green)
                        } else if let next { Text(DateText.countdown(next)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
                    }
                }
                .swipeActions(edge: .leading) {
                    if let next {
                        Button {
                            Task { await model.setCustomDone(!isDone, id: event.id, dayKey: Days.iso(next)) }
                        } label: {
                            isDone ? Label(L10n.t("Nicht erledigt", "Not done"), systemImage: "arrow.uturn.backward") : Label(L10n.t("Erledigt", "Done"), systemImage: "checkmark")
                        }
                        .tint(isDone ? .gray : .green)
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
    @State private var hasTime = false
    @State private var timeMinutes = 9 * 60

    /// Auswahl der Wiederholungen; „jeden n-ten Wochentag“ richtet sich nach dem gewählten Datum.
    private var recurrences: [Recurrence] {
        [.yearly, .once, .everyWeeks(1), .everyWeeks(2), .everyWeeks(4), .everyMonths(1), .monthlyWeekday(matching: startDate), .everyMonths(3), .everyMonths(6), .everyMonths(12), .everyMonths(24)]
    }

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
                    Toggle("Uhrzeit", isOn: $hasTime.animation())
                    if hasTime { TimeOfDayPicker(title: L10n.t("Um", "At"), minutes: $timeMinutes) }
                }
                Section {
                    Toggle("Erinnern", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Picker("Vorab erinnern", selection: $remindDaysBefore) {
                            ForEach(preOptions, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                } header: { Text("Erinnerung") } footer: { Text(reminderFooter) }
                Section("Darstellung") {
                    PaletteColorPicker(colorHex: $colorHex)
                    NavigationLink {
                        EventSymbolPicker(symbolName: $symbolName, colorHex: colorHex)
                    } label: {
                        HStack {
                            Text(L10n.t("Symbol", "Symbol"))
                            Spacer()
                            SymbolBadge(symbolName: symbolName, colorHex: colorHex, size: 32)
                        }
                    }
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
                hasTime = event.timeMinutes != nil; timeMinutes = event.timeMinutes ?? 9 * 60
                clampPreReminder()
            }
            .onChange(of: recurrenceIndex) { _, _ in clampPreReminder() }
        }
    }

    /// Vorab-Erinnerungen, die vor dem nächsten Vorkommen liegen – „1 Monat vorher“ bei einem wöchentlichen Termin käme nie.
    private var preOptions: [(Int, String)] {
        let all = [(0, L10n.t("Nein", "No")), (1, L10n.t("1 Tag vorher", "1 day before")), (3, L10n.t("3 Tage vorher", "3 days before")), (7, L10n.t("1 Woche vorher", "1 week before")), (14, L10n.t("2 Wochen vorher", "2 weeks before")), (30, L10n.t("1 Monat vorher", "1 month before"))]
        let interval: Int
        switch recurrences[recurrenceIndex] {
        case .everyWeeks(let n): interval = 7 * max(1, n)
        case .everyMonths(let n): interval = 28 * max(1, n)
        case .monthlyWeekday: interval = 28
        case .yearly, .once: interval = .max
        }
        return all.filter { $0.0 < interval }
    }

    private func clampPreReminder() {
        if !preOptions.contains(where: { $0.0 == remindDaysBefore }) { remindDaysBefore = preOptions.last?.0 ?? 0 }
    }

    /// Sagt, wann genau erinnert wird – Tageszeiten und Vorlauf stehen in den Einstellungen.
    private var reminderFooter: String {
        let settings = SettingsKeys.reminderSettings()
        guard settings.customEnabled else { return L10n.t("Erinnerungen an eigene Termine sind unter Mehr › Einstellungen ausgeschaltet.", "Reminders for custom events are turned off in More › Settings.") }
        guard remindersEnabled else { return L10n.t("Für diesen Termin kommt keine Erinnerung.", "No reminders for this event.") }
        func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
        var text: String
        if hasTime {
            let lead = settings.customLeadMinutes
            let at = timeMinutes - lead
            let when = at < 0 ? L10n.t("am Vortag um \(time(at + 1440))", "the day before at \(time(at + 1440))") : L10n.t("um \(time(at))", "at \(time(at))")
            text = lead == 0 ? L10n.t("Erinnerung zur Terminzeit", "Reminder at the event time")
                : L10n.t("Erinnerung \(SettingsView.leadText(lead)) vorher, \(when)", "Reminder \(SettingsView.leadText(lead)) before, \(when)")
        } else {
            text = L10n.t("Erinnerung am Termintag um \(time(settings.customMinutes))", "Reminder on the day at \(time(settings.customMinutes))")
        }
        if remindDaysBefore > 0 { text += L10n.t(", vorab um \(time(settings.customPreMinutes))", ", in advance at \(time(settings.customPreMinutes))") }
        if settings.customDayBefore && remindDaysBefore > 1 { text += L10n.t(" – zusätzlich am Vortag", " – plus the day before") }
        return text + L10n.t(". Uhrzeiten und Vorlauf stellst du unter Mehr › Einstellungen ein.", ". Times and lead time can be changed in More › Settings.")
    }

    private func save() {
        let target = event ?? CustomEvent(title: title, startDate: startDate, recurrence: recurrences[recurrenceIndex])
        if event == nil { context.insert(target) }
        target.title = title.trimmingCharacters(in: .whitespaces); target.symbolName = symbolName; target.colorHex = colorHex
        target.startDate = Days.start(of: startDate); target.timeMinutes = hasTime ? timeMinutes : nil; target.recurrence = recurrences[recurrenceIndex]
        target.remindDaysBefore = remindDaysBefore; target.remindersEnabled = remindersEnabled; target.notes = notes
        try? context.save()
        Task { await model.refreshAll() }
        dismiss()
    }
}

/// Alle Symbole für eigene Termine, nach Themen; Antippen wählt und geht zurück.
struct EventSymbolPicker: View {
    @Binding var symbolName: String
    let colorHex: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            ForEach(Palette.eventSymbolGroups, id: \.title) { group in
                Section(group.title) {
                    SymbolPicker(symbolName: Binding(get: { symbolName }, set: { symbolName = $0; dismiss() }), colorHex: colorHex, symbols: group.symbols)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(L10n.t("Symbol", "Symbol")).navigationBarTitleDisplayMode(.inline)
    }
}
