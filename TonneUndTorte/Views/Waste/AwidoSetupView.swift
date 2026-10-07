import SwiftUI
import SwiftData

/// Assistent: Entsorger → Ort → Straße → (Hausnummer) im AWIDO-Portal auswählen.
struct AwidoSetupView: View {
    @Bindable var location: Location
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case provider, place, street, houseNumber
    }

    @State private var step: Step = .provider
    @State private var provider: AwidoProvider = AwidoProvider.known[0]
    @State private var places: [AwidoEntry] = []
    @State private var streets: [AwidoEntry] = []
    @State private var houseNumbers: [AwidoEntry] = []
    @State private var selectedPlace: AwidoEntry?
    @State private var selectedStreet: AwidoEntry?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let client = AwidoClient()

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .provider: providerStep
                case .place: entryList(places, title: "Ort wählen") { place in
                    selectedPlace = place
                    Task { await loadStreets(for: place) }
                }
                case .street: entryList(streets, title: "Straße wählen") { street in
                    selectedStreet = street
                    Task { await loadHouseNumbers(for: street) }
                }
                case .houseNumber: entryList(houseNumbers, title: "Hausnummer wählen") { number in
                    finish(oid: number.key, label: "\(selectedPlace?.value ?? ""), \(selectedStreet?.value ?? "") \(number.value)")
                }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if step != .provider {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Lade Daten …")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            if let customer = location.awidoCustomer, let known = AwidoProvider.known.first(where: { $0.id == customer }) {
                provider = known
            }
        }
    }

    private var title: String {
        switch step {
        case .provider: return "AWIDO-Portal"
        case .place: return provider.title
        case .street: return selectedPlace?.value ?? "Straße"
        case .houseNumber: return selectedStreet?.value ?? "Hausnummer"
        }
    }

    // MARK: - Schritte

    private var providerStep: some View {
        Form {
            Section("Entsorger") {
                Picker("Entsorger", selection: $provider) {
                    ForEach(AwidoProvider.known) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section {
                Button {
                    Task { await loadPlaces() }
                } label: {
                    Label("Weiter zur Ortsauswahl", systemImage: "arrow.right.circle.fill")
                }
            }
            Section {
                Text("Der Assistent fragt die Auswahllisten direkt beim AWIDO-Portal (awido.cubefour.de) ab – genau wie die Abfall-App deines Landkreises.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func entryList(_ entries: [AwidoEntry], title: String, onSelect: @escaping (AwidoEntry) -> Void) -> some View {
        let filtered = searchText.isEmpty
            ? entries
            : entries.filter { $0.value.localizedCaseInsensitiveContains(searchText) }
        return List {
            Section(title) {
                ForEach(filtered) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack {
                            Text(entry.value)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Suchen")
    }

    // MARK: - Laden

    private func loadPlaces() async {
        await run {
            places = try await client.places(customer: provider.id)
            searchText = ""
            step = .place
        }
    }

    private func loadStreets(for place: AwidoEntry) async {
        await run {
            streets = try await client.streets(customer: provider.id, placeOid: place.key)
            searchText = ""
            if streets.isEmpty {
                finish(oid: place.key, label: place.value)
            } else {
                step = .street
            }
        }
    }

    private func loadHouseNumbers(for street: AwidoEntry) async {
        await run {
            houseNumbers = try await client.houseNumbers(customer: provider.id, streetOid: street.key)
            searchText = ""
            if houseNumbers.isEmpty {
                finish(oid: street.key, label: "\(selectedPlace?.value ?? ""), \(street.value)")
            } else {
                step = .houseNumber
            }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goBack() {
        searchText = ""
        switch step {
        case .provider: break
        case .place: step = .provider
        case .street: step = .place
        case .houseNumber: step = .street
        }
    }

    private func finish(oid: String, label: String) {
        location.sourceKind = .awido
        location.awidoCustomer = provider.id
        location.awidoOid = oid
        location.awidoLabel = label.trimmingCharacters(in: .whitespaces)
        location.lastSyncAt = nil
        location.lastSyncMessage = "Adresse gewählt – Termine werden geladen …"
        try? context.save()
        dismiss()
        Task {
            do {
                _ = try await CalendarImporter.sync(location: location, context: context)
                await NotificationManager.shared.reschedule(using: context)
            } catch {
                location.lastSyncMessage = "Fehler: \(error.localizedDescription)"
            }
        }
    }
}
