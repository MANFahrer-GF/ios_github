import SwiftUI
import SwiftData

/// Alle Geburtstage, sortiert nach dem nächsten Termin.
struct BirthdayListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]

    @State private var editingPerson: Person?
    @State private var showNew = false

    private var sortedPeople: [(person: Person, next: Date, age: Int?)] {
        people.compactMap { person in
            guard let next = EventEngine.nextBirthday(for: person) else { return nil }
            return (person, next, EventEngine.age(of: person, on: next))
        }
        .sorted { $0.next < $1.next }
    }

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Geburtstage",
                        systemImage: "birthday.cake",
                        description: Text("Füge Familie und Freunde hinzu – die App erinnert dich rechtzeitig.")
                    )
                } else {
                    List {
                        ForEach(sortedPeople, id: \.person.id) { entry in
                            Button {
                                editingPerson = entry.person
                            } label: {
                                BirthdayRow(person: entry.person, next: entry.next, age: entry.age)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                context.delete(sortedPeople[index].person)
                            }
                            try? context.save()
                            Task { await NotificationManager.shared.reschedule(using: context) }
                        }
                    }
                }
            }
            .navigationTitle("Geburtstage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                BirthdayEditView(person: nil)
            }
            .sheet(item: $editingPerson) { person in
                BirthdayEditView(person: person)
            }
        }
    }
}

struct BirthdayRow: View {
    let person: Person
    let next: Date
    let age: Int?

    private var isToday: Bool { DateText.daysUntil(next) == 0 }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: person.colorHex), Color(hex: person.colorHex).opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(person.initials)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.body.weight(.semibold))
                HStack(spacing: 4) {
                    if let age {
                        Text(isToday ? "wird heute \(age)" : "wird \(age)")
                    }
                    Text("· \(DateText.short(next))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(isToday ? "🎉" : DateText.countdown(next))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isToday ? .pink : .primary)
                if !person.remindersEnabled {
                    Image(systemName: "bell.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
