import SwiftUI
import SwiftData
import UniformTypeIdentifiers
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
    @State private var stepIndex = OptionSearch([])
    @State private var textInput = ""
    @State private var pickups: [Pickup] = []
    /// Schalter je Müllart (Titel der Quelle) im letzten Schritt.
    @State private var activeNames: [String: Bool] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var locationName = ""
    @State private var showCoverage = false
    @State private var showFileImporter = false
    @State private var importPickups: [Pickup] = []
    @State private var showImport = false
    /// Suchergebnisse, einmal je Eingabe berechnet.
    @State private var results: [CatalogEntry] = []
    /// Gefundene Gemeinden ohne belegten Entsorger – je Gemeinde geprüft, jede mit ihrem eigenen Kreis.
    @State private var uncovered: [PlaceCheck] = []
    @FocusState private var icsFieldFocused: Bool
    /// Zum Feld für den Kalender-Link scrollen (Knopf „Kalender-Link einfügen“).
    @State private var scrollToICS = false
    @State private var hint: String?

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
                if stage != .done { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
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
            .navigationDestination(isPresented: $showCoverage) {
                CoverageView(onChoose: { entry in
                    showCoverage = false
                    choose(entry)
                }, onPasteLink: {
                    showCoverage = false
                    pasteLink()
                }, onImportFile: {
                    showCoverage = false
                    // Erst nach dem Zurückgehen öffnen, sonst verwirft SwiftUI die Dateiauswahl mit der schließenden Seite
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showFileImporter = true }
                })
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: LocationDetailView.importTypes, onCompletion: handleImportFile)
            .sheet(isPresented: $showImport) {
                ICSImportView(pickups: importPickups, location: location, makeLocation: makeImportLocation) {
                    model.onboardingDone = true
                    dismiss()
                }
            }
            .onChange(of: query) { _, _ in updateResults() }
            .onChange(of: region.suggestions.map(\.id)) { _, _ in updateResults() }
            .onAppear(perform: updateResults)
        }
    }

    private var title: String {
        switch stage {
        case .search: return L10n.t("Entsorger finden", "Find provider")
        case .steps: return currentStep?.title ?? entry?.title ?? L10n.t("Adresse", "Address")
        case .bins: return L10n.t("Deine Müllarten", "Your waste types")
        case .done: return L10n.t("Fertig", "Done")
        }
    }

    // MARK: - Suche

    private func updateResults() {
        results = query.isEmpty ? region.suggestions : ProviderCatalog.search(query)
        hint = query.isEmpty ? nil : ProviderCatalog.municipalityHint(for: query)
        uncovered = query.isEmpty ? [] : ProviderCatalog.uncoveredPlaces(matching: query)
    }

    private func pasteLink() {
        scrollToICS = true
        icsFieldFocused = true
    }

    private var searchStage: some View {
        ScrollViewReader { proxy in
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
                Button { showCoverage = true } label: {
                    Label(L10n.t("Geht mein Ort?", "Is my town covered?"), systemImage: "map")
                }
            }
            ForEach(uncovered) { check in
                PlaceGapSection(check: check, onPasteLink: pasteLink, onImportFile: { showFileImporter = true })
            }
            // Leere Trefferliste nicht zusätzlich zur Karte zeigen – „Versuche den Landkreis“ widerspräche ihr
            if !(results.isEmpty && !uncovered.isEmpty) {
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
                if !query.isEmpty, let hint {
                    Text(hint)
                }
            }
            }
            Section {
                TextField("https://…/download?system=ical…", text: $icsURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($icsFieldFocused)
                    .accessibilityIdentifier("icsLinkField")
                Button("ICS-Link verwenden") { chooseICS() }
                    .disabled(URL(string: icsURL) == nil || !icsURL.hasPrefix("http"))
            } header: {
                Text("Entsorger nicht dabei?")
            } footer: {
                Text("Viele Abfallportale bieten einen Link „Kalender abonnieren“ oder „iCal-Export“. Diesen hier einfügen – die App lädt die Termine dann wöchentlich neu. Alternativ kannst du Termine auch von Hand als Rhythmus anlegen.")
            }
            .id("icsSection")
        }
        .searchable(text: $query, prompt: "Landkreis, Stadt oder Entsorger")
        .onChange(of: scrollToICS) { _, go in
            guard go else { return }
            withAnimation { proxy.scrollTo("icsSection", anchor: .center) }
            scrollToICS = false
        }
        }
    }

    private var resultsHeader: String {
        if query.isEmpty {
            return region.suggestions.isEmpty
                ? L10n.t("Alle Entsorger (\(ProviderCatalog.count))", "All providers (\(ProviderCatalog.count))")
                : L10n.t("Vorschläge", "Suggestions")
        }
        // Neben der Karte eines fehlenden Orts: Die übrigen Treffer gehören zu gleichnamigen Orten anderswo.
        if !uncovered.isEmpty {
            let places = uncovered.map { "\($0.name) (\(DistrictCoverage.displayName($0.district)))" }.joined(separator: ", ")
            return L10n.t("Andere Treffer (\(results.count)) – gelten nicht für \(places)",
                          "Other results (\(results.count)) – not for \(places)")
        }
        return L10n.t("Treffer (\(results.count))", "Results (\(results.count))")
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

    private func handleImportFile(_ result: Result<URL, Error>) {
        do {
            let pickups = try SyncService.readPickupFile(at: result.get())
            guard !pickups.isEmpty else {
                errorMessage = L10n.t("In der Datei wurden keine Termine gefunden. CSV-Dateien brauchen je Zeile ein Datum (z. B. 07.10.2026) und eine Müllart.",
                                      "No dates found in the file. CSV files need a date (e.g. 07.10.2026) and a waste type per line.")
                return
            }
            importPickups = pickups
            showImport = true
        } catch let error as SyncService.ImportError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = L10n.t("Datei konnte nicht gelesen werden: \(error.localizedDescription)", "Could not read the file: \(error.localizedDescription)")
        }
    }

    /// Neuer Standort für den Dateiimport – erst beim Bestätigen angelegt, damit ein Abbruch nichts hinterlässt.
    private func makeImportLocation() -> Location {
        let name = uncovered.first?.name ?? (query.isEmpty ? L10n.t("Zuhause", "Home") : query)
        let target = Location(name: name, sortOrder: model.allLocations().count)
        target.colorHex = Palette.colors[model.allLocations().count % Palette.colors.count]
        context.insert(target)
        onFinished?(target)
        return target
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
                let filtered = stepSearch.isEmpty ? step.options : stepIndex.filter(query: stepSearch)
                if let hint = step.hint {
                    Section { Text(hint).font(.footnote).foregroundStyle(.secondary) }
                }
                Section(step.title) {
                    ForEach(filtered) { option in
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
                    if filtered.isEmpty {
                        Text("Nichts gefunden.").foregroundStyle(.secondary)
                        if let hint = step.noMatchHint { Text(hint).font(.footnote).foregroundStyle(.secondary) }
                    }
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
        guard !selections.isEmpty else { return }   // schneller Doppeltipp auf „Zurück“
        selections.removeLast()
        Task { await loadNextStep() }
    }

    private func loadNextStep() async {
        guard let provider else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let step = try await provider.nextStep(after: selections) {
                // Einzige Option automatisch wählen (z. B. „Alle Hausnummern“) – begrenzt, falls ein Portal sich im Kreis dreht
                if step.options.count == 1, selections.count < 12 {
                    selections.append(step.options[0])
                    await loadNextStep()
                    return
                }
                stepIndex = OptionSearch(step.options)
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
            // Alles vorab eingeschaltet: Abgewählte Arten fehlen im Kalender, und abwählen soll nur der Nutzer selbst.
            // (Früher blieben ab fünf Arten nur Rest, Bio, Papier, Gelb an – der Grünschnitt fehlte dann unbemerkt.)
            // Wird ein Standort neu eingerichtet, behalten vorhandene Müllarten ihren Zustand.
            var active: [String: Bool] = [:]
            for mapping in SyncService.suggestMappings(for: pickups, location: location) {
                if case .existing(let type) = mapping.target { active[mapping.summary] = type.isActive } else { active[mapping.summary] = true }
            }
            activeNames = active
            if locationName.isEmpty {
                // Lesbare Adresse („Stadt Ansbach, Adlerstraße“) statt nur der ersten Auswahl (bei Straßensuche wäre das der Suchtext)
                let label = provider.label(for: selections)
                locationName = !label.isEmpty ? label : selections.first?.title ?? entry?.title ?? L10n.t("Zuhause", "Home")
            }
            stage = .bins
        } catch {
            errorMessage = error.localizedDescription
            stage = selections.isEmpty ? .search : .steps
        }
    }

    // MARK: - Tonnen auswählen

    /// Jede Müllart der Quelle einzeln – ein Ort kann mehrere derselben Gruppe liefern (Frechen: Restmüll alle 14 Tage
    /// und alle 4 Wochen), von denen ein Haushalt nur eine hat.
    private var binNames: [(name: String, category: WasteCategory, count: Int)] {
        let grouped = Dictionary(grouping: pickups.filter { !WasteCategory.isIgnorableTitle($0.name) }, by: \.name)
        return grouped.map { (name: $0.key, category: WasteCategory.classify($0.key), count: $0.value.count) }
            .sorted { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }
    }

    private var binsStage: some View {
        Form {
            Section {
                TextField("Name des Standorts", text: $locationName)
            } header: { Text("Standort") } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("\(L10n.dates(pickups.count)) gefunden für \(provider?.label(for: selections) ?? entry?.title ?? "").", "\(L10n.dates(pickups.count)) found for \(provider?.label(for: selections) ?? entry?.title ?? "")."))
                    if let notice = provider?.notice {
                        Label(notice, systemImage: "info.circle")
                    }
                }
            }
            Section {
                ForEach(binNames, id: \.name) { bin in
                    Toggle(isOn: Binding(get: { activeNames[bin.name] ?? false }, set: { activeNames[bin.name] = $0 })) {
                        HStack(spacing: 12) {
                            SymbolBadge(symbolName: bin.category.symbolName, colorHex: bin.category.colorHex, size: 36, wasteName: bin.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bin.name).font(.body.weight(.semibold)).lineLimit(2)
                                Text(L10n.dates(bin.count)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: { Text("Welche Müllarten hast du?") } footer: {
                Text(L10n.t("Abgewählte Müllarten erscheinen nicht im Kalender und erinnern nicht. Unter „Müll“ kannst du sie jederzeit wieder einschalten.",
                            "Deselected waste types do not appear in the calendar and send no reminders. You can switch them back on under “Waste” at any time."))
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
        let newSource = SourceConfiguration(providerKind: entry.kind, serviceKey: entry.serviceKey, selections: selections, label: provider.label(for: selections).isEmpty ? entry.title : provider.label(for: selections))
        let sourceChanged = target.source != newSource
        target.source = newSource
        let active = Set(activeNames.filter { $0.value }.map(\.key))
        let mappings = SyncService.suggestMappings(for: pickups, location: target)
        let result = SyncService.apply(pickups: pickups, mappings: mappings, location: target, context: context, replace: true, activeNames: active, sourceChanged: sourceChanged)
        target.lastSyncAt = Date()
        target.lastSyncMessage = L10n.t("\(L10n.dates(result.importedCount)) übernommen", "\(L10n.dates(result.importedCount)) imported")
        guard model.save() else { return }
        model.onboardingDone = true
        stage = .done
        Task { await model.refreshAll() }
        onFinished?(target)
    }

    private var doneStage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("Alles eingerichtet!").font(.title.weight(.bold))
            Text(L10n.t("\(L10n.dates(pickups.count)) \(pickups.count == 1 ? "ist" : "sind") da. Die App erinnert dich am Vorabend – und aktualisiert die Termine jede Woche automatisch.", "\(L10n.dates(pickups.count)) loaded. The app reminds you the evening before – and refreshes the dates every week."))
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Button { dismiss() } label: { Text("Los geht’s").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal)
        }
        .padding()
    }
}
