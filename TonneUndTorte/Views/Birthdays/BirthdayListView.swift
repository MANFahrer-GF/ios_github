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
            text = isToday ? L10n.t("wird heute \(years) · ", "turns \(years) today · ") : L10n.t("wird \(years) · ", "turns \(years) · ")
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
                        LabeledContent("Alter", value: "\(L10n.count(annual.years(on: Date()) ?? 0, "Jahr", "Jahre", "year", "years")) · \(annual.zodiac)")
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
        let first = person.name.split(separator: " ").first.map(String.init) ?? person.name
        let text = L10n.t("Alles Gute zum Geburtstag, \(first)! 🎂🎉", "Happy birthday, \(first)! 🎂🎉")
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
        yearKnown = person.knownYear != nil
        date = Days.make(year: person.knownYear ?? 2000, month: person.month, day: person.day) ?? Date()
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
    @State private var isRefreshing = false
    /// Während eines stillen Neuladens zurückgekehrt: danach noch einmal laden.
    @State private var reloadAgain = false
    @State private var errorMessage: String?
    @State private var access: ContactsImport.Access = ContactsImport.access
    @State private var picked: [ContactsImport.Candidate] = []
    @State private var pickNotice: String?
    /// Schon einmal gezeigte Kontakte: Nur wirklich neue werden vorausgewählt, abgewählte bleiben abgewählt.
    @State private var seen: Set<String> = []
    @State private var search = ""
    @Environment(\.scenePhase) private var scenePhase

    /// Ergebnis des Abgleichs mit den vorhandenen Personen. Neu berechnet beim Laden, nach der Systemauswahl,
    /// wenn Personen dazukommen oder wegfallen – und immer frisch beim Importieren.
    @State private var matching = Matching()
    private var existing: [String: Person] { matching.existing }

    private struct Matching {
        /// Kontakt-ID → Person, die beim Import aktualisiert wird. Jede Person höchstens einmal.
        var existing: [String: Person] = [:]
        /// Kontakte mit gleichem Namen und Geburtstag wie eine andere Person bzw. ein anderer Kontakt in der Liste
        /// (doppelt im Adressbuch oder Namensvetter). Nicht vorausgewählt; wer sie anhakt, legt bewusst eine neue Person an.
        var duplicates: Set<String> = []
    }

    private func computeMatching() -> Matching {
        var result = Matching()
        let linked = Dictionary(people.compactMap { person in person.contactIdentifier.map { ($0, person) } }, uniquingKeysWith: { first, _ in first })
        // Über Name + Geburtstag: von Hand angelegte Personen und solche, deren Kontakt-ID hier nicht vorkommt
        // (Kontakt-IDs unterscheiden sich je Gerät; Personen kommen per iCloud von anderen Geräten).
        let candidateIDs = Set(candidates.map(\.identifier))
        var byKey: [String: Person] = [:]
        for person in people where person.contactIdentifier.map({ !candidateIDs.contains($0) }) ?? true {
            byKey[Self.matchKey(person)] = byKey[Self.matchKey(person)] ?? person
        }
        let personKeys = Set(people.map(Self.matchKey))
        var used = Set<UUID>()
        var seenKeys = Set<String>()
        for candidate in candidates {
            if let person = linked[candidate.identifier] {
                result.existing[candidate.identifier] = person
                used.insert(person.id)
                seenKeys.insert(Self.matchKey(candidate))
            }
        }
        for candidate in candidates where result.existing[candidate.identifier] == nil {
            let key = Self.matchKey(candidate)
            if let person = byKey[key], !used.contains(person.id) {
                result.existing[candidate.identifier] = person
                used.insert(person.id)
            } else if personKeys.contains(key) || seenKeys.contains(key) {
                result.duplicates.insert(candidate.identifier)
            }
            seenKeys.insert(key)
        }
        return result
    }

    private static func matchKey(_ person: Person) -> String { matchKey(name: person.name, day: person.day, month: person.month) }
    private static func matchKey(_ candidate: ContactsImport.Candidate) -> String { matchKey(name: candidate.name, day: candidate.day, month: candidate.month) }

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
            // Neue oder gelöschte Personen (z. B. iCloud-Abgleich). Feldänderungen fängt importSelected ab.
            .onChange(of: people) { _, _ in matching = computeMatching() }
            // Zurück aus den Einstellungen: geänderte oder erweiterte Kontaktfreigabe sofort übernehmen.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !isLoading else { return }
                if isRefreshing { reloadAgain = true } else { Task { await load(silent: true) } }
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
                VStack(alignment: .leading, spacing: 6) {
                    if access == .limited {
                        Text("Du hast der App nur einzelne Kontakte freigegeben. Kein Problem: Wähle die Personen einfach aus, ganz ohne weitere Freigabe.")
                    } else {
                        Text("Die App darf deine Kontakte nicht lesen. Kein Problem: Wähle die Personen einfach aus, ganz ohne Freigabe.")
                    }
                    Text("Bereits übernommene Personen aktualisierst du, indem du sie erneut auswählst.")
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
                    ? L10n.t("Ein ausgewählter Kontakt hat keinen Namen oder kein vollständiges Geburtsdatum und wurde ausgelassen.", "One selected contact has no name or no complete birthday and was skipped.")
                    : L10n.t("\(skipped) ausgewählte Kontakte haben keinen Namen oder kein vollständiges Geburtsdatum und wurden ausgelassen.", "\(skipped) selected contacts have no name or no complete birthday and were skipped.")
            }
            guard !chosen.isEmpty else { return }
            picked = merge(picked, chosen)
            candidates = merge(candidates, chosen)
            // Wie beim Laden: nur neue Personen vorauswählen. Bereits angelegte bleiben unverändert,
            // außer man hakt sie bewusst zum Aktualisieren an.
            matching = computeMatching()
            let skip = Set(existing.keys).union(matching.duplicates)
            selected.formUnion(chosen.map(\.identifier).filter { !skip.contains($0) })
            seen.formUnion(chosen.map(\.identifier))
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
                } else if matching.duplicates.contains(candidate.identifier) {
                    Text("doppelt?").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    /// `silent`: im Hintergrund neu lesen (Rückkehr in die App), ohne Ladeanzeige und ohne Flackern.
    private func load(silent: Bool = false) async {
        if silent { isRefreshing = true } else { isLoading = true; errorMessage = nil }
        defer { if silent { isRefreshing = false } else { isLoading = false } }
        do {
            let fetched = try await ContactsImport.candidates()
            // Erst nach dem Lesen auf `picked` zugreifen (Auswahl könnte währenddessen dazugekommen sein);
            // frisch gelesene Daten gewinnen gegenüber früher ausgewählten.
            candidates = merge(picked, fetched)
            matching = computeMatching()
            // Erstmals gezeigte, noch nicht angelegte Kontakte vorauswählen; Abwahlen des Nutzers bleiben bestehen.
            let ids = Set(candidates.map(\.identifier))
            selected.formUnion(ids.subtracting(seen).subtracting(existing.keys).subtracting(matching.duplicates))
            seen.formUnion(ids)
            errorMessage = nil
        } catch ContactsImport.ImportError.denied {
            // Kein Fehler: Personen lassen sich trotzdem über die Systemauswahl übernehmen.
            candidates = picked
            matching = computeMatching()
            errorMessage = nil
        } catch {
            // Beim stillen Neuladen die bisherige Liste behalten.
            if !silent { errorMessage = error.localizedDescription }
        }
        // Nur auswählen, was noch in der Liste steht (z. B. nach Entzug der Freigabe).
        selected = selected.intersection(Set(candidates.map(\.identifier)))
        access = ContactsImport.access
        if silent, reloadAgain {
            reloadAgain = false
            Task { await load(silent: true) }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func importSelected() {
        let current = computeMatching().existing
        for (index, candidate) in candidates.enumerated() where selected.contains(candidate.identifier) {
            let person: Person
            if let known = current[candidate.identifier] {
                person = known
                person.name = candidate.name
                person.day = candidate.day
                person.month = candidate.month
                if let year = candidate.year {
                    person.year = year
                } else if person.year != nil, person.knownYear == nil {
                    // Früher übernommenes Platzhalterjahr entfernen; ein echtes eigenes Jahr bleibt.
                    person.year = nil
                }
                // Eine bestehende Verknüpfung (Kontakt evtl. nur gerade nicht freigegeben) nicht umhängen.
                if person.contactIdentifier == nil { person.contactIdentifier = candidate.identifier }
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
