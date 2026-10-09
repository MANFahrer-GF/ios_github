import SwiftUI
import PhotosUI
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

/// PDF mit eigenem Dateinamen (z. B. „Eigene Termine.pdf“).
struct NamedPDFFile: Transferable {
    let data: Data
    let fileName: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(file.fileName)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
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

/// Tab „Termine“: Geburtstage und eigene Termine, umschaltbar.
struct BirthdayListView: View {
    enum Segment: String { case birthdays, custom }
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \CustomEvent.title) private var customEvents: [CustomEvent]
    @Environment(\.openURL) private var openURL
    @SceneStorage("termine.segment") private var segment: Segment = .birthdays
    /// Alle Fenster dieses Tabs über eine einzige Stelle – verschachtelte .sheet-Modifier blockieren sich sonst gegenseitig.
    enum SheetKind: Identifiable {
        case newPerson, person(Person), importContacts, newEvent, event(CustomEvent)
        var id: String {
            switch self {
            case .newPerson: return "newPerson"
            case .person(let p): return "person-\(p.id)"
            case .importContacts: return "import"
            case .newEvent: return "newEvent"
            case .event(let e): return "event-\(e.id)"
            }
        }
    }
    @State private var sheet: SheetKind?
    /// Person, die angerufen werden soll – erst nach Nachfrage.
    @State private var callPerson: Person?

    /// Nach Monat des nächsten Geburtstags; das Jahr steht nur dabei, wenn es nicht das laufende ist.
    private var monthSections: [(title: String, entries: [(person: Person, next: Date, years: Int?)])] {
        var result: [(title: String, entries: [(person: Person, next: Date, years: Int?)])] = []
        let thisYear = Calendar.current.component(.year, from: Date())
        for entry in sorted {
            let year = Calendar.current.component(.year, from: entry.next)
            let title = entry.next.formatted(.dateTime.month(.wide)) + (year == thisYear ? "" : " \(year)")
            if result.last?.title == title { result[result.count - 1].entries.append(entry) } else { result.append((title, [entry])) }
        }
        return result
    }

    /// Oben: wer als Nächstes Geburtstag hat – im Stil der Übersicht.
    private func nextBirthdayCard(day: Date, entries: [(person: Person, next: Date, years: Int?)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("NÄCHSTER GEBURTSTAG · ", "NEXT BIRTHDAY · ") + PickupWords.eyebrow(date: day)).font(KlarStyle.font(12, .heavy)).tracking(0.8).foregroundStyle(.pink)
                Text(DateText.countdown(day)).font(KlarStyle.font(32, .black)).foregroundStyle(.primary)
            }
            ForEach(entries, id: \.person.id) { entry in
                Button { sheet = .person(entry.person) } label: {
                    HStack(spacing: 14) {
                        PersonAvatar(person: entry.person, initials: entry.person.initials, colorHex: entry.person.colorHex, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.person.name).font(KlarStyle.font(19, .heavy)).foregroundStyle(.primary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            InfoTags(tags: ([entry.years.map { (AnnualDate.isMilestone($0) ? "🎉 " : "🎂 ") + L10n.t("wird \($0)", "turns \($0)") }, entry.person.knownYear.map { L10n.t("Jg. \($0)", "b. \($0)") }, entry.person.zodiacLabel] as [String?]).compactMap { $0 }, size: 13)
                                .padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var sorted: [(person: Person, next: Date, years: Int?)] {
        people.compactMap { p in p.nextBirthday.map { (p, $0, p.annual.years(on: $0)) } }.sorted { $0.next < $1.next }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L10n.t("Ansicht", "View"), selection: $segment) {
                    Text(L10n.t("Geburtstage", "Birthdays")).tag(Segment.birthdays)
                    Text(L10n.t("Eigene Termine", "Custom events")).tag(Segment.custom)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 8)
                if segment == .birthdays { birthdays } else { CustomEventsView { sheet = .event($0) } }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.t("Termine", "Events"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == .birthdays {
                        Menu {
                            Button { sheet = .newPerson } label: { Label("Neuer Geburtstag", systemImage: "plus") }
                            Button { sheet = .importContacts } label: { Label("Aus Kontakten importieren", systemImage: "person.crop.circle.badge.plus") }
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
                    } else {
                        Menu {
                            Button { sheet = .newEvent } label: { Label(L10n.t("Neuer Termin", "New event"), systemImage: "plus") }
                            if !customEvents.isEmpty {
                                Divider()
                                ShareLink(item: PickupCSVFile(text: CustomEventExport.csv(customEvents.map(\.exportRow)), fileName: L10n.t("Eigene Termine.csv", "Custom events.csv")),
                                          preview: SharePreview(L10n.t("Eigene Termine.csv", "Custom events.csv"))) {
                                    Label("Als CSV exportieren (Excel)", systemImage: "tablecells")
                                }
                                ShareLink(item: NamedPDFFile(data: CustomEventPDF.render(customEvents.map(\.exportRow)), fileName: L10n.t("Eigene Termine.pdf", "Custom events.pdf")),
                                          preview: SharePreview(L10n.t("Eigene Termine.pdf", "Custom events.pdf"))) {
                                    Label("Als PDF exportieren", systemImage: "doc.richtext")
                                }
                            }
                        } label: { Image(systemName: "plus") }
                    }
                }
            }
            .confirmationDialog(L10n.t("\(callPerson?.name ?? "") anrufen?", "Call \(callPerson?.name ?? "")?"),
                                isPresented: Binding(get: { callPerson != nil }, set: { if !$0 { callPerson = nil } }), titleVisibility: .visible) {
                Button(L10n.t("Anrufen", "Call")) { if let url = CallLink.url(callPerson?.phone) { openURL(url) } }
                Button(L10n.t("Abbrechen", "Cancel"), role: .cancel) {}
            }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .newPerson: BirthdayEditView(person: nil)
                case .person(let person): BirthdayEditView(person: person)
                case .importContacts: ContactsImportView()
                case .newEvent: CustomEventEditView(event: nil)
                case .event(let event): CustomEventEditView(event: event)
                }
            }
            .onChange(of: model.personToOpen, initial: true) { _, id in
                guard let id else { return }
                model.personToOpen = nil
                segment = .birthdays
                if let person = people.first(where: { $0.id == id }) { sheet = .person(person) }
            }
            .onChange(of: model.eventToOpen, initial: true) { _, id in
                guard let id else { return }
                model.eventToOpen = nil
                segment = .custom
                if let event = model.allCustomEvents().first(where: { $0.id == id }) { sheet = .event(event) }
            }
        }
    }

    private var birthdays: some View {
            Group {
                if people.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Geburtstage", systemImage: "birthday.cake")
                    } description: {
                        Text("Importiere sie aus deinen Kontakten oder lege sie von Hand an.")
                    } actions: {
                        Button("Aus Kontakten importieren") { sheet = .importContacts }.buttonStyle(.borderedProminent)
                        Button("Von Hand anlegen") { sheet = .newPerson }
                    }
                } else {
                    List {
                        if let next = sorted.first?.next {
                            Section { nextBirthdayCard(day: next, entries: sorted.filter { $0.next == next }) }
                                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                        // Nach Monaten gegliedert; Wischen: gratulieren, anrufen, löschen
                        ForEach(monthSections, id: \.title) { section in
                            Section {
                                ForEach(section.entries, id: \.person.id) { entry in
                                    Button { sheet = .person(entry.person) } label: { BirthdayRow(person: entry.person, next: entry.next, years: entry.years) }.buttonStyle(.plain)
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            if let url = NotificationManager.greetingURL(name: entry.person.name, phone: entry.person.phone) {
                                                Button { openURL(url) } label: { Label(L10n.t("Gratulieren", "Send wishes"), systemImage: "message.fill") }.tint(.pink)
                                            }
                                            if CallLink.url(entry.person.phone) != nil {
                                                Button { callPerson = entry.person } label: { Label(L10n.t("Anrufen", "Call"), systemImage: "phone.fill") }.tint(.green)
                                            }
                                        }
                                }
                                .onDelete { offsets in
                                    offsets.forEach { context.delete(section.entries[$0].person) }
                                    try? context.save()
                                    Task { await model.refreshAll() }
                                }
                            } header: {
                                Text(section.title).font(KlarStyle.font(13, .heavy)).tracking(0.6)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
    }
}

struct BirthdayRow: View {
    let person: Person
    let next: Date
    let years: Int?
    @Environment(\.colorScheme) private var scheme
    private var daysLeft: Int { Days.until(next) }

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(person: person, initials: person.initials, colorHex: person.colorHex, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.name).font(KlarStyle.font(17, .heavy)).foregroundStyle(KlarStyle.text(scheme))
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if !person.remindersEnabled { Image(systemName: "bell.slash").font(.caption).foregroundStyle(.tertiary) }
                }
                InfoTags(tags: tags, size: 11).padding(.top, 2)
            }
            Spacer(minLength: 8)
            countdown
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Schildchen: „wird 73 🎉“, „Jg. 1953“, „♏️ Skorpion“, „🎁 2“ – das Datum steht rechts unter den Tagen
    private var tags: [String] {
        var tags: [String] = []
        if let years { tags.append(L10n.t("wird \(years)", "turns \(years)") + (AnnualDate.isMilestone(years) ? " 🎉" : "")) }
        if let year = person.knownYear { tags.append(L10n.t("Jg. \(year)", "b. \(year)")) }
        // In der Liste nur das Sternzeichen-Symbol – ausgeschrieben passt es auf dem iPhone nicht in eine Reihe
        tags.append(String(person.zodiacLabel.prefix(while: { $0 != " " })))
        if !person.giftIdeas.isEmpty { tags.append("🎁 \(person.giftIdeas.count)") }
        return tags
    }

    /// Rechts: Tage bis zum Geburtstag groß, darunter das Datum.
    private var countdown: some View {
        VStack(alignment: .trailing, spacing: 1) {
            switch daysLeft {
            case 0:
                Text(L10n.t("Heute 🎉", "Today 🎉")).font(KlarStyle.font(16, .heavy)).foregroundStyle(.pink)
            case 1:
                Text(L10n.t("Morgen", "Tomorrow")).font(KlarStyle.font(16, .heavy)).foregroundStyle(KlarStyle.text(scheme))
            default:
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(daysLeft)").font(KlarStyle.font(20, .black)).foregroundStyle(KlarStyle.text(scheme))
                    Text(L10n.t("Tage", "days")).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme))
                }
            }
            Text(DateText.short(next)).font(KlarStyle.font(12, .bold)).foregroundStyle(KlarStyle.muted(scheme)).lineLimit(1)
        }
        .fixedSize()
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
    /// Tag und Monat, wenn das Geburtsjahr nicht bekannt ist – dann ohne Datumsauswahl mit erfundenem Jahr.
    @State private var dayOnly = 1
    @State private var monthOnly = 1
    @State private var notes = ""
    @State private var colorHex = "#EC4899"
    @State private var remindersEnabled = true
    @State private var remindDaysBefore = 1
    @State private var giftIdeas: [String] = []
    @State private var newGift = ""
    @State private var phone = ""
    @State private var showDeleteConfirm = false
    @State private var photoData: Data?
    @State private var confirmCall = false
    @State private var photoItem: PhotosPickerItem?

    private let options: [(String, Int)] = [("Nur am Geburtstag", 0), ("1 Tag vorher", 1), ("2 Tage vorher", 2), ("3 Tage vorher", 3), ("1 Woche vorher", 7), ("2 Wochen vorher", 14)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        PersonAvatar(person: person?.photoData == nil ? person : nil, initials: NameText.initials(name.isEmpty ? "?" : name), colorHex: colorHex, size: 64)
                            .overlay { if let photoData, let image = UIImage(data: photoData) { Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle()) } }
                        VStack(alignment: .leading, spacing: 6) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(photoData == nil ? L10n.t("Foto wählen", "Choose photo") : L10n.t("Anderes Foto", "Change photo"), systemImage: "photo")
                            }
                            if photoData != nil {
                                Button(role: .destructive) { photoData = nil; photoItem = nil } label: { Label(L10n.t("Foto entfernen", "Remove photo"), systemImage: "trash") }
                            } else if person?.contactIdentifier != nil {
                                Text(L10n.t("Ohne eigenes Foto wird das Foto aus dem Kontakt gezeigt.", "Without a photo of its own, the contact photo is shown."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: yearKnown) { _, known in
                    let cal = Calendar.current
                    if known {
                        // Gibt es den Tag in diesem Jahr nicht (29. Februar), ein Schaltjahr nehmen statt den Tag zu ändern
                        var year = cal.component(.year, from: date)
                        let maxDay = Days.make(year: year, month: monthOnly, day: 1).flatMap { cal.range(of: .day, in: .month, for: $0)?.count } ?? 28
                        if dayOnly > maxDay { year = 2000 }
                        date = Days.make(year: year, month: monthOnly, day: dayOnly) ?? date
                    } else {
                        dayOnly = cal.component(.day, from: date); monthOnly = cal.component(.month, from: date)
                    }
                }
                .onChange(of: monthOnly) { _, month in dayOnly = min(dayOnly, daysIn(month: month)) }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) { photoData = Self.downscaled(data) }
                    }
                }
                Section("Person") {
                    TextField("Name", text: $name)
                    Toggle("Geburtsjahr bekannt", isOn: $yearKnown)
                    if yearKnown {
                        DatePicker("Geburtstag", selection: $date, in: ...Date(), displayedComponents: .date)
                    } else {
                        // Ohne Jahr: nur Tag und Monat – kein Platzhalter-Jahr, das falsch aussieht
                        Picker(L10n.t("Tag", "Day"), selection: $dayOnly) {
                            ForEach(1...daysIn(month: monthOnly), id: \.self) { Text("\($0).").tag($0) }
                        }
                        Picker(L10n.t("Monat", "Month"), selection: $monthOnly) {
                            ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
                        }
                    }
                    if yearKnown {
                        let annual = AnnualDate(day: Calendar.current.component(.day, from: date), month: Calendar.current.component(.month, from: date), year: Calendar.current.component(.year, from: date))
                        LabeledContent("Alter", value: "\(L10n.count(annual.years(on: Date()) ?? 0, "Jahr", "Jahre", "year", "years")) · \(annual.zodiac.replacingOccurrences(of: "\u{FE0E}", with: "\u{FE0F}"))")
                    } else {
                        LabeledContent(L10n.t("Sternzeichen", "Star sign"), value: AnnualDate(day: dayOnly, month: monthOnly, year: nil).zodiac.replacingOccurrences(of: "\u{FE0E}", with: "\u{FE0F}"))
                    }
                    TextField("Telefon (für Glückwunsch per Nachricht)", text: $phone).keyboardType(.phonePad)
                }
                Section {
                    Toggle("Erinnern", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Picker("Vorab erinnern", selection: $remindDaysBefore) { ForEach(options, id: \.1) { Text($0.0).tag($0.1) } }
                    }
                } header: { Text("Erinnerung") } footer: { Text(reminderFooter) }
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
                        // Nummer aus dem Feld oben – auch wenn sie gerade erst eingetragen und noch nicht gesichert ist
                        if let url = CallLink.url(phone) {
                            Button { confirmCall = true } label: { Label(L10n.t("Anrufen", "Call"), systemImage: "phone.fill") }
                                .callConfirmation(isPresented: $confirmCall, name: name, url: url)
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Geburtstag löschen", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Geburtstag").navigationBarTitleDisplayMode(.inline)
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

    /// Sagt, wann genau erinnert wird – die Uhrzeiten gelten für alle und stehen in den Einstellungen.
    private var reminderFooter: String {
        let settings = SettingsKeys.reminderSettings()
        guard settings.birthdayEnabled else { return L10n.t("Geburtstags-Erinnerungen sind unter Mehr › Einstellungen ausgeschaltet.", "Birthday reminders are turned off in More › Settings.") }
        guard remindersEnabled else { return L10n.t("Für diese Person kommt keine Erinnerung.", "No reminders for this person.") }
        func time(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
        var text = L10n.t("Am Geburtstag um \(time(settings.birthdayMinutes))", "On the birthday at \(time(settings.birthdayMinutes))")
        if remindDaysBefore > 0 || settings.birthdayWeekBefore { text += L10n.t(", vorab um \(time(settings.birthdayPreMinutes))", ", in advance at \(time(settings.birthdayPreMinutes))") }
        if settings.birthdayWeekBefore && remindDaysBefore != 7 { text += L10n.t(" – zusätzlich eine Woche vorher", " – plus one week before") }
        return text + L10n.t(". Die Uhrzeiten stellst du unter Mehr › Einstellungen ein.", ". Times can be changed in More › Settings.")
    }

    private func greetingURL(for person: Person) -> URL? {
        NotificationManager.greetingURL(name: person.name, phone: person.phone)
    }

    /// Tage eines Monats; Februar mit 29, damit Schalttags-Geburtstage gehen.
    private func daysIn(month: Int) -> Int {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(1, min(12, month)) - 1]
    }

    /// Fotos auf höchstens 600 Pixel verkleinern (JPEG) – reicht für die runden Bilder und hält iCloud klein.
    static func downscaled(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.8)
    }

    private func load() {
        guard let person else { return }
        name = person.name; notes = person.notes; colorHex = person.colorHex; remindersEnabled = person.remindersEnabled
        remindDaysBefore = person.remindDaysBefore; giftIdeas = person.giftIdeas; phone = person.phone ?? ""
        photoData = person.photoData
        yearKnown = person.knownYear != nil
        dayOnly = person.day; monthOnly = person.month
        // Ohne bekanntes Jahr wird die Datumsauswahl nicht gezeigt; das Jahr ist nur ein Startwert, falls man es einschaltet.
        // 2000 ist ein Schaltjahr – sonst würde ein 29. Februar beim Einschalten zum 28.
        date = Days.make(year: person.knownYear ?? 2000, month: person.month, day: person.day) ?? Date()
    }

    private func save() {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        if !yearKnown { c.day = min(dayOnly, daysIn(month: monthOnly)); c.month = monthOnly }
        let target = person ?? Person(name: name, day: c.day ?? 1, month: c.month ?? 1)
        if person == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.day = c.day ?? 1; target.month = c.month ?? 1; target.year = yearKnown ? c.year : nil
        target.notes = notes; target.colorHex = colorHex; target.remindersEnabled = remindersEnabled
        if target.photoData != photoData { target.photoData = photoData }
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
