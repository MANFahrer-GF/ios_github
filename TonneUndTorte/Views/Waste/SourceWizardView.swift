import SwiftUI
import SwiftData
import TonneCore

/// Einrichtungsassistent für eine Online-Quelle: Entsorger finden (Standort oder Suche),
/// Auswahlschritte des Anbieters durchlaufen, Tonnen auswählen, Termine laden.
struct SourceWizardView: View {
    /// Vorhandener Standort (Quelle ändern) oder nil (neuen Standort anlegen).
    let location: Location?
    var onFinished: ((Location) -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var region = RegionSuggest()

    private enum Stage { case search, steps, bins, done }
    @State private var stage: Stage = .search
    @State private var query = ""
    @State private var icsURL = ""
    @State private var entry: CatalogEntry?
    @State private var provider: WasteProvider?
    @State private var selections: [SelectionOption] = []
    @State private var currentStep: SelectionStep?
    @State private var stepSearch = ""
    @State private var textInput = ""
    @State private var pickups: [Pickup] = []
    @State private var categories: [WasteCategory: Bool] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var locationName = ""

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .search: searchStage
                case .steps: stepStage
                case .bins: binsStage
                case .done: doneStage
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if stage == .steps, !selections.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { Button { goBack() } label: { Image(systemName: "chevron.left") } }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Lade …").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert("Hinweis", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var title: String {
        switch stage {
        case .search: return "Entsorger finden"
        case .steps: return currentStep?.title ?? entry?.title ?? "Adresse"
        case .bins: return "Deine Tonnen"
        case .done: return "Fertig"
        }
    }

    // MARK: - Suche

    private var results: [CatalogEntry] {
        query.isEmpty ? region.suggestions : ProviderCatalog.search(query)
    }

    private var searchStage: some View {
        List {
            Section {
                Button {
                    region.locate()
                } label: {
                    HStack {
                        Label("Meinen Standort verwenden", systemImage: "location.fill")
                        Spacer()
                        if region.isWorking { ProgressView() }
                    }
                }
                if let place = region.placeName, !region.suggestions.isEmpty {
                    Text("Vorschläge für \(place)").font(.caption).foregroundStyle(.secondary)
                }
                if let message = region.errorMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(query.isEmpty && region.suggestions.isEmpty ? ProviderCatalog.entries : results) { item in
                    Button { choose(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).foregroundStyle(.primary)
                            Text(catalogSubtitle(item))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !query.isEmpty && results.isEmpty {
                    Text("Kein Entsorger gefunden. Versuche den Landkreis oder nutze unten einen ICS-Link.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text(resultsHeader)
            } footer: {
                if !query.isEmpty, let hint = ProviderCatalog.municipalityHint(for: query) {
                    Text(hint)
                }
            }
            Section {
                TextField("https://…/download?system=ical…", text: $icsURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("ICS-Link verwenden") { chooseICS() }
                    .disabled(URL(string: icsURL) == nil || !icsURL.hasPrefix("http"))
            } header: {
                Text("Entsorger nicht dabei?")
            } footer: {
                Text("Viele Abfall-Portale bieten einen Link „Sync zu Kalender“ oder „ICS-Export“. Diesen hier einfügen – die App lädt die Termine dann wöchentlich neu. Alternativ kannst du Termine auch von Hand als Rhythmus anlegen.")
            }
        }
        .searchable(text: $query, prompt: "Landkreis, Stadt oder Entsorger")
    }

    private var resultsHeader: String {
        if query.isEmpty { return region.suggestions.isEmpty ? "Alle Entsorger (\(ProviderCatalog.count))" : "Vorschläge" }
        return "Treffer (\(results.count))"
    }

    private func catalogSubtitle(_ item: CatalogEntry) -> String {
        var text = item.kind.displayName
        if !item.places.isEmpty {
            text += " · "
            text += item.places.prefix(3).joined(separator: ", ")
            if item.places.count > 3 { text += " …" }
        }
        return text
    }

    private func choose(_ item: CatalogEntry) {
        entry = item
        provider = ProviderFactory.make(kind: item.kind, serviceKey: item.serviceKey)
        selections = []
        locationName = location?.name ?? ""
        Task { await loadNextStep() }
    }

    private func chooseICS() {
        entry = CatalogEntry(kind: .icsURL, serviceKey: icsURL, title: "ICS-Link")
        provider = ICSURLProvider(url: icsURL)
        selections = []
        Task { await loadPickups() }
    }

    // MARK: - Auswahlschritte

    private var stepStage: some View {
        List {
            if !selections.isEmpty {
                Section { Text(selections.map(\.title).joined(separator: " › ")).font(.caption).foregroundStyle(.secondary) }
            }
            if let step = currentStep, step.input == .text {
                Section(step.title) {
                    TextField(step.placeholder ?? step.title, text: $textInput)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                        .onSubmit { submitText() }
                    Button { submitText() } label: { Label("Weiter", systemImage: "arrow.right.circle.fill") }
                        .disabled(textInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if let step = currentStep {
                let filtered = stepSearch.isEmpty ? step.options : step.options.filter { $0.title.localizedCaseInsensitiveContains(stepSearch) }
                Section(step.title) {
                    ForEach(filtered.prefix(400)) { option in
                        Button { select(option) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(option.title).foregroundStyle(.primary)
                                    if let subtitle = option.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if filtered.isEmpty { Text("Nichts gefunden.").foregroundStyle(.secondary) }
                }
            }
        }
        .searchable(text: $stepSearch, prompt: "Suchen")
    }

    private func select(_ option: SelectionOption) {
        selections.append(option)
        stepSearch = ""
        textInput = ""
        Task { await loadNextStep() }
    }

    private func submitText() {
        let value = textInput.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        select(SelectionOption(id: value, title: value))
    }

    private func goBack() {
        selections.removeLast()
        Task { await loadNextStep() }
    }

    private func loadNextStep() async {
        guard let provider else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let step = try await provider.nextStep(after: selections) {
                // Einzige Option automatisch wählen (z. B. „Alle Hausnummern“)
                if step.options.count == 1 {
                    selections.append(step.options[0])
                    await loadNextStep()
                    return
                }
                currentStep = step
                stage = .steps
            } else {
                await loadPickups()
            }
        } catch {
            errorMessage = error.localizedDescription
            if selections.isEmpty { stage = .search }
        }
    }

    private func loadPickups() async {
        guard let provider else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            pickups = try await provider.pickups(for: selections)
            let found = Set(pickups.map { WasteCategory.classify($0.name) })
            categories = Dictionary(uniqueKeysWithValues: found.map { ($0, [.residual, .organic, .paper, .packaging].contains($0) || found.count <= 4) })
            if locationName.isEmpty { locationName = selections.first?.title ?? entry?.title ?? "Zuhause" }
            stage = .bins
        } catch {
            errorMessage = error.localizedDescription
            stage = selections.isEmpty ? .search : .steps
        }
    }

    // MARK: - Tonnen auswählen

    private var binNames: [(category: WasteCategory, names: [String], count: Int)] {
        let grouped = Dictionary(grouping: pickups.filter { !WasteCategory.isIgnorableTitle($0.name) }, by: { WasteCategory.classify($0.name) })
        return grouped.keys.sorted { $0.rawValue < $1.rawValue }.map { category in
            let items = grouped[category] ?? []
            return (category, Array(Set(items.map(\.name))).sorted(), items.count)
        }
    }

    private var binsStage: some View {
        Form {
            Section {
                TextField("Name des Standorts", text: $locationName)
            } header: { Text("Standort") } footer: {
                Text("\(pickups.count) Termine gefunden für \(provider?.label(for: selections) ?? entry?.title ?? "").")
            }
            Section {
                ForEach(binNames, id: \.category) { bin in
                    Toggle(isOn: Binding(get: { categories[bin.category] ?? false }, set: { categories[bin.category] = $0 })) {
                        HStack(spacing: 12) {
                            SymbolBadge(symbolName: bin.category.symbolName, colorHex: bin.category.colorHex, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bin.names.joined(separator: ", ")).font(.body.weight(.semibold)).lineLimit(2)
                                Text("\(bin.count) Termine").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: { Text("Welche Tonnen hast du?") } footer: {
                Text("Abgewählte Tonnen bleiben gespeichert, aber ohne Erinnerung. Du kannst das jederzeit ändern.")
            }
            Section {
                Button { finish() } label: { Label("Standort anlegen", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }
                    .disabled(locationName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func finish() {
        guard let entry, let provider else { return }
        let target: Location
        if let location {
            target = location
        } else {
            target = Location(name: locationName.trimmingCharacters(in: .whitespaces), sortOrder: model.allLocations().count)
            target.colorHex = Palette.colors[model.allLocations().count % Palette.colors.count]
            context.insert(target)
        }
        if target.name.isEmpty { target.name = locationName }
        target.source = SourceConfiguration(providerKind: entry.kind, serviceKey: entry.serviceKey, selections: selections, label: provider.label(for: selections).isEmpty ? entry.title : provider.label(for: selections))
        let active = Set(categories.filter { $0.value }.map(\.key))
        let mappings = SyncService.suggestMappings(for: pickups, location: target)
        let result = SyncService.apply(pickups: pickups, mappings: mappings, location: target, context: context, replace: true, activeCategories: active)
        target.lastSyncAt = Date()
        target.lastSyncMessage = "\(result.importedCount) Termine übernommen"
        try? context.save()
        model.onboardingDone = true
        stage = .done
        Task { await model.refreshAll() }
        onFinished?(target)
    }

    private var doneStage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("Alles eingerichtet!").font(.title.weight(.bold))
            Text("\(pickups.count) Termine sind da. Die App erinnert dich am Vorabend – und aktualisiert die Termine jede Woche automatisch.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Button { dismiss() } label: { Text("Los geht's").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal)
        }
        .padding()
    }
}
