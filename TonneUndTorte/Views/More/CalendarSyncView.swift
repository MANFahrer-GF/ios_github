import SwiftUI
import TonneCore

/// Kalender-Abgleich: Zielkalender wählen (iCloud, Google, Outlook …), Inhalte wählen, automatisch aktuell halten.
struct CalendarSyncView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(CalendarExport.autoSyncKey) private var autoSync = false
    @AppStorage(CalendarSyncOptions.wasteKey) private var includeWaste = true
    @AppStorage(CalendarSyncOptions.customKey) private var includeCustom = true
    @AppStorage(CalendarSyncOptions.birthdaysKey) private var birthdays = CalendarSyncOptions.Birthdays.manualOnly.rawValue
    @State private var targetText = CalendarExport.targetDescription()
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Toggle(isOn: $autoSync) {
                    Label("Automatisch aktuell halten", systemImage: "arrow.triangle.2.circlepath")
                }
                NavigationLink {
                    CalendarTargetPicker { target in
                        await move(to: target)
                    }
                } label: {
                    LabeledContent {
                        Text(targetText).lineLimit(1)
                    } label: {
                        Label("Kalender", systemImage: "calendar")
                    }
                }
            } footer: {
                Text("Neue und verschobene Termine landen nach jedem Abgleich von selbst in der Kalender-App. iOS gleicht den gewählten Kalender mit iCloud, Google oder Outlook ab, du musst nichts kopieren.")
            }

            Section {
                Toggle(isOn: $includeWaste) { Label("Müllabfuhr", systemImage: "trash.fill") }
                Toggle(isOn: $includeCustom) { Label("Eigene Termine", systemImage: "pin.fill") }
                Picker(selection: $birthdays) {
                    ForEach(CalendarSyncOptions.Birthdays.allCases) { Text($0.title).tag($0.rawValue) }
                } label: {
                    Label("Geburtstage", systemImage: "birthday.cake.fill")
                }
            } header: {
                Text("Was eintragen")
            } footer: {
                Text("Geburtstage aus deinen Kontakten zeigt iOS schon im Kalender „Geburtstage“. Mit „Nur von Hand angelegte“ wird nichts doppelt.")
            }

            Section {
                Button {
                    Task { await exportNow() }
                } label: {
                    HStack {
                        Label("Jetzt eintragen", systemImage: "calendar.badge.plus")
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(isWorking)
                ShareLink(item: FeedFile(text: model.feedText()), preview: SharePreview("Tonne & Torte.ics")) {
                    Label("Als ICS-Datei teilen", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Google-Kalender erscheinen in der Auswahl, sobald dein Google-Konto in den iOS-Einstellungen unter Apps → Kalender → Kalender-Accounts eingerichtet ist.")
            }
        }
        .navigationTitle("Kalender-Abgleich")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: autoSync) { _, enabled in if enabled { Task { await exportNow() } } }
        .onChange(of: includeWaste) { _, _ in optionsChanged() }
        .onChange(of: includeCustom) { _, _ in optionsChanged() }
        .onChange(of: birthdays) { _, _ in optionsChanged() }
        .onAppear { targetText = CalendarExport.targetDescription() }
        .alert("Kalender", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func optionsChanged() {
        CalendarExport.resetFingerprint()
        if autoSync { Task { await exportNow(silent: true) } }
    }

    private func exportNow(silent: Bool = false) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let count = try await CalendarExport.export(items: model.calendarExportItems())
            CalendarExport.resetFingerprint()
            targetText = CalendarExport.targetDescription()
            if !silent { message = "\(count) Termine in „\(targetText)“ eingetragen." }
        } catch {
            if autoSync && !CalendarExport.hasFullAccess { autoSync = false }
            message = error.localizedDescription
        }
    }

    private func move(to target: CalendarExport.Target) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let count = try await CalendarExport.move(to: target, items: model.calendarExportItems())
            targetText = CalendarExport.targetDescription()
            message = "\(count) Termine in „\(targetText)“ eingetragen."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Auswahl des Zielkalenders: eigener Kalender je Konto oder ein vorhandener Kalender.
struct CalendarTargetPicker: View {
    var onSelect: (CalendarExport.Target) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var own: [CalendarExport.Choice] = []
    @State private var existing: [CalendarExport.Choice] = []
    @State private var errorMessage: String?
    @State private var current = CalendarExport.target

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            }
            Section {
                ForEach(own) { choice in row(choice, symbol: "calendar.badge.plus") }
            } header: {
                Text("Eigener Kalender „Tonne & Torte“ in")
            } footer: {
                Text("Empfohlen: Die App legt einen eigenen Kalender an, den du in der Kalender-App ein- und ausblenden kannst.")
            }
            if !existing.isEmpty {
                Section {
                    ForEach(existing) { choice in row(choice, symbol: nil) }
                } header: {
                    Text("Oder in einen vorhandenen Kalender")
                } footer: {
                    Text("Die App markiert ihre Termine und ändert oder löscht nur diese. Deine eigenen Termine bleiben unberührt.")
                }
            }
        }
        .navigationTitle("Kalender wählen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let result = try await CalendarExport.choices()
                own = result.own
                existing = result.existing
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isCurrent(_ choice: CalendarExport.Choice) -> Bool {
        if choice.target == current { return true }
        if case .own(nil) = current, case .own(let id?) = choice.target {
            return own.first?.target == .own(sourceID: id) && own.first(where: { $0.title == "iCloud" }) == nil
        }
        return false
    }

    private func row(_ choice: CalendarExport.Choice, symbol: String?) -> some View {
        Button {
            Task {
                current = choice.target
                await onSelect(choice.target)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                if let hex = choice.colorHex {
                    Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                } else if let symbol {
                    Image(systemName: symbol).foregroundStyle(Color(hex: "#2E9E6B"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title).foregroundStyle(.primary)
                    Text(choice.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent(choice) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
    }
}
