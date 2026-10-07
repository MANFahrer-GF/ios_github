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
    @State private var picked: [ContactsImport.Candidate] = []
    @State private var pickNotice: String?
    @State private var search = ""
    @Environment(\.scenePhase) private var scenePhase

    /// Bereits angelegte Personen je Kontakt-ID. Wird nur neu berechnet, wenn sich die Kandidaten ändern.
    @State private var existing: [String: Person] = [:]

    /// Zuordnung über die Kontakt-ID oder – bei von Hand angelegten – über gleichen Namen und Geburtstag,
    /// damit niemand doppelt in der Liste landet.
    private func matchExisting() -> [String: Person] {
        let linked = Dictionary(people.compactMap { person in person.contactIdentifier.map { ($0, person) } }, uniquingKeysWith: { first, _ in first })
        let manual = Dictionary(people.filter { $0.contactIdentifier == nil }.map { (Self.matchKey(name: $0.name, day: $0.day, month: $0.month), $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: Person] = [:]
        for candidate in candidates {
            if let person = linked[candidate.identifier] ?? manual[Self.matchKey(name: candidate.name, day: candidate.day, month: candidate.month)] {
                result[candidate.identifier] = person
            }
        }
        return result
    }

    private static func matchKey(name: String, day: Int, month: Int) -> String {
        "\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces))|\(day)|\(month)"
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
                if let pickNotice { Text(pickNotice).foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                if !isLoading && candidates.isEmpty && errorMessage == nil {
                    if access == .full {
                        Text("In deinen Kontakten ist kein Geburtstag eingetragen.").foregroundStyle(.secondary)
                    } else {
                        Text("Tippe auf „Personen auswählen“ und hake alle an, deren Geburtstag du übernehmen möchtest.").foregroundStyle(.secondary)
                    }
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
            .task { await load() }
            .onChange(of: candidates) { _, _ in existing = matchExisting() }
            // Zurück aus den Einstellungen: geänderte Kontaktfreigabe sofort übernehmen.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !isLoading, ContactsImport.access != access { Task { await load() } }
            }
        }
    }

    /// Ohne vollen Kontaktzugriff wählt man die Personen direkt in der Systemauswahl aus – dafür braucht es keine Freigabe.
    @ViewBuilder
    private var accessSection: some View {
        if access != .full && !isLoading {
            Section {
                Button { pickContacts() } label: {
                    Label("Personen auswählen", systemImage: "person.crop.circle.badge.plus").font(.body.weight(.semibold))
                }
                Button { openSettings() } label: { Label("Allen Kontakten Zugriff geben (Einstellungen)", systemImage: "gearshape") }
                DisclosureGroup {
                    accessExplanation
                } label: {
                    Label("Warum sehe ich nicht alle Kontakte?", systemImage: "questionmark.circle")
                }
            } footer: {
                if access == .limited {
                    Text("Du hast der App nur einzelne Kontakte freigegeben. Kein Problem: Wähle die Personen einfach aus, ganz ohne weitere Freigabe.")
                } else {
                    Text("Die App darf deine Kontakte nicht lesen. Kein Problem: Wähle die Personen einfach aus, ganz ohne Freigabe.")
                }
            }
        }
    }

    /// Erklärt, warum iOS der App nur einen Teil des Adressbuchs zeigt und was man tun kann.
    private var accessExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            if access == .limited {
                Text("iOS schützt dein Adressbuch: Seit iOS 18 entscheidest du selbst, welche Kontakte eine App sehen darf. Du hast beim Nachfragen nur einzelne Kontakte ausgewählt – alle anderen bleiben für Tonne & Torte unsichtbar, auch wenn dort ein Geburtstag eingetragen ist.")
            } else {
                Text("iOS schützt dein Adressbuch: Du hast der App den Zugriff auf deine Kontakte nicht erlaubt. Deshalb kann Tonne & Torte von sich aus keine Geburtstage lesen.")
            }
            Text("„Personen auswählen“ öffnet die Kontaktliste von iOS selbst. Die App bekommt dabei nur die Personen, die du anhakst – sonst nichts aus deinem Adressbuch.")
            Text("Lieber alle auf einmal? Dann in den Einstellungen unter Apps › Tonne & Torte › Kontakte „Vollständiger Zugriff“ wählen.")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func pickContacts() {
        pickNotice = nil
        ContactsPicker.present { chosen, skipped in
            if skipped > 0 {
                pickNotice = skipped == 1
                    ? L10n.t("Bei einer ausgewählten Person ist kein Geburtstag eingetragen.", "One selected person has no birthday.")
                    : L10n.t("Bei \(skipped) ausgewählten Personen ist kein Geburtstag eingetragen.", "\(skipped) selected people have no birthday.")
            }
            guard !chosen.isEmpty else { return }
            picked = merge(picked, chosen)
            candidates = merge(candidates, chosen)
            // Wie beim Laden: nur neue Personen vorauswählen. Bereits angelegte bleiben unverändert,
            // außer man hakt sie bewusst zum Aktualisieren an.
            existing = matchExisting()
            let known = Set(existing.keys)
            selected.formUnion(chosen.map(\.identifier).filter { !known.contains($0) })
        }
    }

    /// Ergänzt Kandidaten ohne Dubletten; neuere Daten ersetzen ältere.
    private func merge(_ base: [ContactsImport.Candidate], _ extra: [ContactsImport.Candidate]) -> [ContactsImport.Candidate] {
        let ids = Set(extra.map(\.identifier))
        return (base.filter { !ids.contains($0.identifier) } + extra).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            candidates = merge(try await ContactsImport.candidates(), picked)
            existing = matchExisting()
            let known = Set(existing.keys)
            // Neue Kontakte vorauswählen, bisherige Auswahl behalten
            selected.formUnion(Set(candidates.map(\.identifier)).subtracting(known))
            selected = selected.intersection(Set(candidates.map(\.identifier)))
        } catch ContactsImport.ImportError.denied {
            // Kein Fehler: Personen lassen sich trotzdem über die Systemauswahl übernehmen.
            candidates = picked
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
                // Ein von Hand eingetragenes Geburtsjahr nicht löschen, wenn der Kontakt keins hat.
                if let year = candidate.year { person.year = year }
                person.contactIdentifier = candidate.identifier
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
