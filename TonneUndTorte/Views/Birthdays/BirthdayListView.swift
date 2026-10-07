import SwiftUI
import ContactsUI
import SwiftData
import UniformTypeIdentifiers
import TonneCore

/// CSV-Datei zum Teilen (Excel).
struct CSVFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in Data(file.text.utf8) }
            .suggestedFileName("Geburtstage.csv")
    }
}

/// PDF-Datei zum Teilen.
struct PDFFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { file in file.data }
            .suggestedFileName("Geburtstage.pdf")
    }
}

struct BirthdayListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]
    @State private var editing: Person?
    @State private var showNew = false
    @State private var showImport = false

    private var sorted: [(person: Person, next: Date, years: Int?)] {
        people.compactMap { p in p.nextBirthday.map { (p, $0, p.annual.years(on: $0)) } }.sorted { $0.next < $1.next }
    }

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Geburtstage", systemImage: "birthday.cake")
                    } description: {
                        Text("Importiere sie aus deinen Kontakten oder lege sie von Hand an.")
                    } actions: {
                        Button("Aus Kontakten importieren") { showImport = true }.buttonStyle(.borderedProminent)
                        Button("Von Hand anlegen") { showNew = true }
                    }
                } else {
                    List {
                        ForEach(sorted, id: \.person.id) { entry in
                            Button { editing = entry.person } label: { BirthdayRow(person: entry.person, next: entry.next, years: entry.years) }.buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.forEach { context.delete(sorted[$0].person) }
                            try? context.save()
                            Task { await model.refreshAll() }
                        }
                    }
                }
            }
            .navigationTitle("Geburtstage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNew = true } label: { Label("Neuer Geburtstag", systemImage: "plus") }
                        Button { showImport = true } label: { Label("Aus Kontakten importieren", systemImage: "person.crop.circle.badge.plus") }
                        if !people.isEmpty {
                            Divider()
                            ShareLink(item: CSVFile(text: BirthdayExport.csv(people.map(\.exportRow))), preview: SharePreview("Geburtstage.csv")) {
                                Label("Als CSV exportieren (Excel)", systemImage: "tablecells")
                            }
                            ShareLink(item: PDFFile(data: BirthdayPDF.render(people.map(\.exportRow))), preview: SharePreview("Geburtstage.pdf")) {
                                Label("Als PDF exportieren", systemImage: "doc.richtext")
                            }
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) { BirthdayEditView(person: nil) }
            .sheet(item: $editing) { BirthdayEditView(person: $0) }
            .sheet(isPresented: $showImport) { ContactsImportView() }
        }
    }
}

struct BirthdayRow: View {
    let person: Person
    let next: Date
    let years: Int?
    private var isToday: Bool { Days.until(next) == 0 }
    var body: some View {
        HStack(spacing: 12) {
            InitialsBadge(initials: person.initials, colorHex: person.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.name).font(.body.weight(.semibold))
                    if let years, AnnualDate.isMilestone(years) { Text("🎉 \(years)").font(.caption.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.pink.opacity(0.15), in: Capsule()).foregroundStyle(.pink) }
                }
                Text(subtitle(next: next, years: years, isToday: isToday))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(isToday ? "🎉" : DateText.countdown(next)).font(.subheadline.weight(.semibold)).foregroundStyle(isToday ? .pink : .primary)
            if !person.remindersEnabled { Image(systemName: "bell.slash").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 4)
    }

    private func subtitle(next: Date, years: Int?, isToday: Bool) -> String {
        var text = ""
        if let years {
            text = isToday ? "wird heute \(years) · " : "wird \(years) · "
        }
        text += DateText.short(next)
        if !person.giftIdeas.isEmpty {
            text += " · 🎁 \(person.giftIdeas.count)"
        }
        return text
    }
}

struct BirthdayEditView: View {
    let person: Person?
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Days.make(year: 1990, month: 1, day: 1) ?? Date()
    @State private var yearKnown = true
    @State private var notes = ""
    @State private var colorHex = "#EC4899"
    @State private var remindersEnabled = true
    @State private var remindDaysBefore = 1
    @State private var giftIdeas: [String] = []
    @State private var newGift = ""
    @State private var phone = ""
    @State private var showDeleteConfirm = false

    private let options: [(String, Int)] = [("Nur am Geburtstag", 0), ("1 Tag vorher", 1), ("2 Tage vorher", 2), ("3 Tage vorher", 3), ("1 Woche vorher", 7), ("2 Wochen vorher", 14)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    DatePicker("Geburtstag", selection: $date, in: ...Date(), displayedComponents: .date)
                    Toggle("Geburtsjahr bekannt", isOn: $yearKnown)
                    if yearKnown {
                        let annual = AnnualDate(day: Calendar.current.component(.day, from: date), month: Calendar.current.component(.month, from: date), year: Calendar.current.component(.year, from: date))
                        LabeledContent("Alter", value: "\(annual.years(on: Date()) ?? 0) Jahre · \(annual.zodiac)")
                    }
                    TextField("Telefon (für Glückwunsch per Nachricht)", text: $phone).keyboardType(.phonePad)
                }
                Section("Erinnerung") {
                    Toggle("Erinnern", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Picker("Zusätzlich", selection: $remindDaysBefore) { ForEach(options, id: \.1) { Text($0.0).tag($0.1) } }
                    }
                }
                Section("Geschenkideen") {
                    ForEach(giftIdeas, id: \.self) { idea in Text("🎁 \(idea)") }
                        .onDelete { giftIdeas.remove(atOffsets: $0) }
                    HStack {
                        TextField("Idee hinzufügen", text: $newGift)
                        Button { let t = newGift.trimmingCharacters(in: .whitespaces); if !t.isEmpty { giftIdeas.append(t); newGift = "" } } label: { Image(systemName: "plus.circle.fill") }
                            .disabled(newGift.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Farbe") { PaletteColorPicker(colorHex: $colorHex) }
                Section("Notizen") { TextField("Adresse, Vorlieben …", text: $notes, axis: .vertical).lineLimit(3...6) }
                if let person {
                    Section {
                        if let url = greetingURL(for: person) {
                            Link(destination: url) { Label("Glückwunsch per Nachricht senden", systemImage: "message.fill") }
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Geburtstag löschen", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(person == nil ? "Neuer Geburtstag" : "Geburtstag bearbeiten").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .confirmationDialog("Geburtstag wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { dismiss(); if let person { model.deleteLater(person) } }
            }
            .onAppear(perform: load)
        }
    }

    private func greetingURL(for person: Person) -> URL? {
        let text = "Alles Gute zum Geburtstag, \(person.name.split(separator: " ").first.map(String.init) ?? person.name)! 🎂🎉"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let phone = person.phone, !phone.isEmpty {
            return URL(string: "sms:\(phone.filter { "+0123456789".contains($0) })&body=\(encoded)")
        }
        return URL(string: "sms:&body=\(encoded)")
    }

    private func load() {
        guard let person else { return }
        name = person.name; notes = person.notes; colorHex = person.colorHex; remindersEnabled = person.remindersEnabled
        remindDaysBefore = person.remindDaysBefore; giftIdeas = person.giftIdeas; phone = person.phone ?? ""
        yearKnown = person.year != nil
        date = Days.make(year: person.year ?? 2000, month: person.month, day: person.day) ?? Date()
    }

    private func save() {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let target = person ?? Person(name: name, day: c.day ?? 1, month: c.month ?? 1)
        if person == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.day = c.day ?? 1; target.month = c.month ?? 1; target.year = yearKnown ? c.year : nil
        target.notes = notes; target.colorHex = colorHex; target.remindersEnabled = remindersEnabled
        target.remindDaysBefore = remindDaysBefore; target.giftIdeas = giftIdeas; target.phone = phone.isEmpty ? nil : phone
        try? context.save()
        Task { await model.refreshAll() }
        dismiss()
    }
}

struct ContactsImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var people: [Person]
    @State private var candidates: [ContactsImport.Candidate] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var access: ContactsImport.Access = ContactsImport.access
    @State private var showAccessPicker = false
    @State private var search = ""

    private var existing: [String: Person] {
        Dictionary(people.compactMap { person in person.contactIdentifier.map { ($0, person) } }, uniquingKeysWith: { first, _ in first })
    }

    private var visible: [ContactsImport.Candidate] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return candidates }
        return candidates.filter { $0.name.lowercased().contains(needle) }
    }

    private var newCount: Int { selected.filter { existing[$0] == nil }.count }
    private var updateCount: Int { selected.count - newCount }

    var body: some View {
        NavigationStack {
            List {
                accessSection
                if isLoading { ProgressView("Kontakte werden gelesen …") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                if !isLoading && candidates.isEmpty && errorMessage == nil {
                    Text("In den freigegebenen Kontakten ist kein Geburtstag eingetragen.").foregroundStyle(.secondary)
                }
                Section {
                    ForEach(visible) { candidate in row(candidate) }
                } footer: {
                    if !existing.isEmpty {
                        Text("Bereits importierte Personen kannst du erneut auswählen, dann werden Name, Datum und Telefon aus den Kontakten aktualisiert. Geschenkideen und Notizen bleiben erhalten.")
                    }
                }
            }
            .searchable(text: $search, prompt: "Kontakt suchen")
            .navigationTitle("Aus Kontakten").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(updateCount > 0 && newCount == 0 ? "Aktualisieren (\(updateCount))" : "Importieren (\(selected.count))") { importSelected() }
                        .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Alle neuen") { selected = Set(candidates.map(\.identifier)).filter { existing[$0] == nil } }
                        Spacer()
                        Button("Keine") { selected = [] }
                    }
                }
            }
            .modifier(ContactAccessPickerModifier(isPresented: $showAccessPicker) { Task { await load() } })
            .task { await load() }
        }
    }

    @ViewBuilder
    private var accessSection: some View {
        if access == .limited {
            Section {
                Label("Du hast der App nur ausgewählte Kontakte freigegeben.", systemImage: "person.crop.circle.badge.exclamationmark")
                Button { showAccessPicker = true } label: { Label("Weitere Kontakte freigeben", systemImage: "person.crop.circle.badge.plus") }
                Button { openSettings() } label: { Label("Alle Kontakte freigeben (Einstellungen)", systemImage: "gearshape") }
            }
        } else if access == .denied {
            Section {
                Label("Kontaktzugriff ist ausgeschaltet.", systemImage: "person.crop.circle.badge.xmark")
                Button { openSettings() } label: { Label("In den Einstellungen erlauben", systemImage: "gearshape") }
            }
        }
    }

    private func row(_ candidate: ContactsImport.Candidate) -> some View {
        let already = existing[candidate.identifier] != nil
        let isSelected = selected.contains(candidate.identifier)
        return Button {
            if isSelected { selected.remove(candidate.identifier) } else { selected.insert(candidate.identifier) }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading) {
                    Text(candidate.name).foregroundStyle(.primary)
                    Text("\(candidate.day).\(candidate.month).\(candidate.year.map { "\($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if already {
                    Text(isSelected ? "wird aktualisiert" : "schon drin").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            candidates = try await ContactsImport.candidates()
            let known = Set(existing.keys)
            // Neue Kontakte vorauswählen, bisherige Auswahl behalten
            selected.formUnion(Set(candidates.map(\.identifier)).subtracting(known))
            selected = selected.intersection(Set(candidates.map(\.identifier)))
        } catch {
            errorMessage = error.localizedDescription
        }
        access = ContactsImport.access
        isLoading = false
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func importSelected() {
        let current = existing
        for (index, candidate) in candidates.enumerated() where selected.contains(candidate.identifier) {
            let person: Person
            if let known = current[candidate.identifier] {
                person = known
                person.name = candidate.name
                person.day = candidate.day
                person.month = candidate.month
                person.year = candidate.year
            } else {
                person = Person(name: candidate.name, day: candidate.day, month: candidate.month, year: candidate.year, colorHex: Palette.colors[index % Palette.colors.count])
                person.contactIdentifier = candidate.identifier
                context.insert(person)
            }
            if let phone = candidate.phone { person.phone = phone }
        }
        try? context.save()
        Task { await model.refreshAll() }
        dismiss()
    }
}

/// iOS 18: Systemauswahl „Weitere Kontakte freigeben“. Auf älteren Systemen ohne Wirkung.
private struct ContactAccessPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onChange: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.contactAccessPicker(isPresented: $isPresented) { _ in onChange() }
        } else {
            content
        }
    }
}
