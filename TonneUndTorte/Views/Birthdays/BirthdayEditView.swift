import SwiftUI
import SwiftData

/// Geburtstag anlegen oder bearbeiten.
struct BirthdayEditView: View {
    let person: Person?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? Date()
    @State private var yearKnown = true
    @State private var notes = ""
    @State private var colorHex = "#EC4899"
    @State private var remindersEnabled = true
    @State private var remindDaysBefore = 1
    @State private var showDeleteConfirm = false

    private let reminderOptions: [(label: String, days: Int)] = [
        ("Nur am Geburtstag", 0),
        ("1 Tag vorher", 1),
        ("2 Tage vorher", 2),
        ("3 Tage vorher", 3),
        ("1 Woche vorher", 7),
        ("2 Wochen vorher", 14),
    ]

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? Date.distantPast
        return start...Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    DatePicker("Geburtstag", selection: $date, in: dateRange, displayedComponents: .date)
                    Toggle("Geburtsjahr bekannt", isOn: $yearKnown)
                    if yearKnown, let age = currentAge {
                        LabeledContent("Alter", value: "\(age) Jahre")
                    }
                }

                Section("Erinnerung") {
                    Toggle("Erinnern", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Picker("Zusätzlich", selection: $remindDaysBefore) {
                            ForEach(reminderOptions, id: \.days) { option in
                                Text(option.label).tag(option.days)
                            }
                        }
                    }
                }

                Section("Farbe") {
                    PaletteColorPicker(colorHex: $colorHex)
                }

                Section("Notizen") {
                    TextField("Geschenkideen, Adresse …", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if person != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Geburtstag löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(person == nil ? "Neuer Geburtstag" : "Geburtstag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Geburtstag wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let person {
                        context.delete(person)
                        try? context.save()
                        Task { await NotificationManager.shared.reschedule(using: context) }
                    }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private var currentAge: Int? {
        let calendar = Calendar.current
        return calendar.dateComponents([.year], from: date, to: Date()).year
    }

    private func load() {
        guard let person else { return }
        name = person.name
        notes = person.notes
        colorHex = person.colorHex
        remindersEnabled = person.remindersEnabled
        remindDaysBefore = person.remindDaysBefore
        yearKnown = person.year != nil
        let year = person.year ?? 2000
        date = Calendar.current.date(from: DateComponents(year: year, month: person.month, day: person.day)) ?? Date()
    }

    private func save() {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let day = components.day ?? 1
        let month = components.month ?? 1
        let year = yearKnown ? components.year : nil

        if let person {
            person.name = name.trimmingCharacters(in: .whitespaces)
            person.day = day
            person.month = month
            person.year = year
            person.notes = notes
            person.colorHex = colorHex
            person.remindersEnabled = remindersEnabled
            person.remindDaysBefore = remindDaysBefore
        } else {
            let newPerson = Person(name: name.trimmingCharacters(in: .whitespaces), day: day, month: month, year: year, colorHex: colorHex)
            newPerson.notes = notes
            newPerson.remindersEnabled = remindersEnabled
            newPerson.remindDaysBefore = remindDaysBefore
            context.insert(newPerson)
        }
        try? context.save()
        Task { await NotificationManager.shared.reschedule(using: context) }
        dismiss()
    }
}
