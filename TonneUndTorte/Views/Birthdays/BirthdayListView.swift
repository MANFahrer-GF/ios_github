import SwiftUI
import SwiftData
import TonneCore

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
                Text((years.map { isToday ? "wird heute \($0) · " : "wird \($0) · " } ?? "") + DateText.short(next) + (person.giftIdeas.isEmpty ? "" : " · 🎁 \(person.giftIdeas.count)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(isToday ? "🎉" : DateText.countdown(next)).font(.subheadline.weight(.semibold)).foregroundStyle(isToday ? .pink : .primary)
            if !person.remindersEnabled { Image(systemName: "bell.slash").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 4)
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
                Button("Löschen", role: .destructive) { if let person { context.delete(person); try? context.save(); Task { await model.refreshAll() } }; dismiss() }
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

    private var existingIDs: Set<String> { Set(people.compactMap(\.contactIdentifier)) }

    var body: some View {
        NavigationStack {
            List {
                if isLoading { ProgressView("Kontakte werden gelesen …") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                ForEach(candidates) { candidate in
                    let already = existingIDs.contains(candidate.identifier)
                    Button {
                        if selected.contains(candidate.identifier) { selected.remove(candidate.identifier) } else { selected.insert(candidate.identifier) }
                    } label: {
                        HStack {
                            Image(systemName: already ? "checkmark.circle" : selected.contains(candidate.identifier) ? "checkmark.circle.fill" : "circle").foregroundStyle(already ? .secondary : Color.accentColor)
                            VStack(alignment: .leading) {
                                Text(candidate.name).foregroundStyle(.primary)
                                Text("\(candidate.day).\(candidate.month).\(candidate.year.map { "\($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if already { Text("schon drin").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(already)
                }
            }
            .navigationTitle("Aus Kontakten").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { Button("Alle") { selected = Set(candidates.map(\.identifier)).subtracting(existingIDs) } }
                ToolbarItem(placement: .confirmationAction) { Button("Importieren (\(selected.count))") { importSelected() }.disabled(selected.isEmpty) }
            }
            .task {
                do { candidates = try await ContactsImport.candidates(); selected = Set(candidates.map(\.identifier)).subtracting(existingIDs) }
                catch { errorMessage = error.localizedDescription }
                isLoading = false
            }
        }
    }

    private func importSelected() {
        for (index, candidate) in candidates.enumerated() where selected.contains(candidate.identifier) {
            let person = Person(name: candidate.name, day: candidate.day, month: candidate.month, year: candidate.year, colorHex: Palette.colors[index % Palette.colors.count])
            person.contactIdentifier = candidate.identifier
            person.phone = candidate.phone
            context.insert(person)
        }
        try? context.save()
        Task { await model.refreshAll() }
        dismiss()
    }
}
