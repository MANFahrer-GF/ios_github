import SwiftUI
import TonneCore

/// „Geht mein Ort?“: Ort eingeben → welcher Entsorger ihn bedient und mit welcher Einschränkung.
/// Ohne Eingabe: Stand der Abdeckung, Entsorger mit Einschränkungen und die Wege, trotzdem zu Terminen zu kommen.
struct CoverageView: View {
    /// Im Einrichtungsassistenten: Antippen eines Entsorgers wählt ihn direkt aus.
    var onChoose: ((CatalogEntry) -> Void)? = nil
    /// Im Einrichtungsassistenten: zum Feld für den Kalender-Link springen.
    var onPasteLink: (() -> Void)? = nil
    /// Im Einrichtungsassistenten: Termine aus einer ICS-/CSV-Datei laden.
    var onImportFile: (() -> Void)? = nil

    @State private var query = ""
    /// Treffer zur Eingabe – nur bei geänderter Eingabe neu berechnet, nicht bei jedem Neuzeichnen.
    @State private var checks: [PlaceCheck] = []
    @State private var fallback: [CatalogEntry] = []

    private let all = ProviderCatalog.coverage
    /// Einmal ermittelt – Jahresdaten lesen für ihren Hinweis ihre Termindaten.
    private static let restricted = ProviderCatalog.restrictedEntries

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var coveredCount: Int { all.filter(\.isCovered).count }
    private var missing: [DistrictCoverage] { all.filter { !$0.isCovered } }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                introSection
                restrictedSection
                if !missing.isEmpty { missingSection }
                districtsSection
                MissingPlaceHelpSection(query: "", onPasteLink: onPasteLink, onImportFile: onImportFile)
            } else {
                resultSections
            }
        }
        .navigationTitle(L10n.t("Geht mein Ort?", "Is my town covered?"))
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L10n.t("Ort eingeben, z. B. Soltau", "Enter a town, e.g. Soltau"))
        .onChange(of: trimmedQuery) { _, text in
            checks = text.isEmpty ? [] : ProviderCatalog.checkPlace(text)
            fallback = text.isEmpty || !checks.isEmpty ? [] : Array(ProviderCatalog.search(text).prefix(20))
        }
    }

    // MARK: Ohne Eingabe

    private var introSection: some View {
        Section {
            Label(L10n.t("\(coveredCount) von \(all.count) Landkreisen und kreisfreien Städten sind angebunden.",
                         "\(coveredCount) of \(all.count) districts are connected."),
                  systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text(L10n.t("Gib oben deinen Ort ein – du siehst sofort, welcher Entsorger ihn bedient und ob es Einschränkungen gibt.",
                        "Enter your town above – you will see right away which provider serves it and whether there are any limitations."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var restrictedSection: some View {
        Section {
            ForEach(Self.restricted) { entryRow($0) }
        } header: {
            Text(L10n.t("Mit Einschränkungen", "With limitations"))
        } footer: {
            Text(L10n.t("Alle anderen Entsorger liefern ihre Termine direkt aus dem Portal und werden wöchentlich abgeglichen.",
                        "All other providers deliver their dates straight from their portal and are synced weekly."))
        }
    }

    /// Durch die Kreise blättern – vor allem im Assistenten, wenn der Ort nicht gefunden wird.
    private var districtsSection: some View {
        Section {
            NavigationLink {
                DistrictListView(onChoose: onChoose)
            } label: {
                Label(L10n.t("Alle Landkreise und Städte", "All districts and cities"), systemImage: "list.bullet")
            }
        }
    }

    private var missingSection: some View {
        Section {
            ForEach(missing) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                    if !item.missingPlaces.isEmpty {
                        Text(L10n.count(item.missingPlaces.count, "Gemeinde ohne abrufbaren Online-Kalender", "Gemeinden ohne abrufbaren Online-Kalender",
                                        "municipality without an online calendar", "municipalities without an online calendar"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(L10n.t("Noch nicht vollständig angebunden", "Not fully connected yet"))
        } footer: {
            Text(L10n.t("Gib oben einen Ort ein, um den Grund und die Webseite des Entsorgers zu sehen.",
                        "Enter a town above to see the reason and the provider's website."))
        }
    }

    // MARK: Mit Eingabe

    @ViewBuilder
    private var resultSections: some View {
        if checks.isEmpty {
            // Keine Gemeinde dieses Namens (Ortsteil, Entsorger- oder Kreisname): normale Entsorgersuche
            let found = fallback
            if found.isEmpty {
                Section {
                    Text(L10n.t("Nichts gefunden. Gesucht wird nach Gemeinden – bei einem Ortsteil bitte die Gemeinde eingeben, zu der er gehört.",
                                "Nothing found. The search looks for municipalities – for a village that belongs to one, enter the municipality."))
                        .foregroundStyle(.secondary)
                }
                MissingPlaceHelpSection(query: trimmedQuery, onPasteLink: onPasteLink, onImportFile: onImportFile)
            } else {
                Section(L10n.t("Passende Entsorger", "Matching providers")) {
                    ForEach(found) { entryRow($0) }
                }
            }
        } else {
            ForEach(checks) { check in
                if check.isCovered {
                    Section {
                        ForEach(check.entries) { entryRow($0) }
                    } header: {
                        Text("\(check.name) · \(DistrictCoverage.displayName(check.district))")
                    }
                } else {
                    // Gleiche Karte wie im Assistenten: Grund mit Entsorger und Prüftag, dann direkte Wege zu den Terminen
                    PlaceGapSection(check: check, onPasteLink: onPasteLink, onImportFile: onImportFile)
                }
                // Nachweislich kein abrufbarer Kalender: keine Kandidaten anbieten, die die Gemeinde nicht führen
                if !check.otherEntries.isEmpty, !check.isUnavailable {
                    Section {
                        ForEach(check.otherEntries) { entryRow($0) }
                    } header: {
                        Text(L10n.t("Weitere Entsorger im \(DistrictCoverage.displayName(check.district))", "Other providers in \(DistrictCoverage.displayName(check.district))"))
                    } footer: {
                        Text(L10n.t("Gelten für andere Gemeinden des Kreises – ein Amt bedient auch seine Mitgliedsgemeinden.",
                                    "These serve other municipalities of the district – an Amt also serves its member municipalities."))
                    }
                }
            }
        }
    }

    // MARK: Bausteine

    @ViewBuilder
    private func entryRow(_ entry: CatalogEntry) -> some View {
        if let onChoose {
            Button { onChoose(entry) } label: { entryContent(entry) }
        } else {
            entryContent(entry)
        }
    }

    private func entryContent(_ entry: CatalogEntry) -> some View {
        let restriction = ProviderCatalog.restriction(for: entry)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: restriction == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(restriction == nil ? .green : .yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).foregroundStyle(.primary)
                Text(entry.kind.displayName).font(.caption).foregroundStyle(.secondary)
                if let restriction {
                    Text(restriction).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Alle Kreise nach Bundesland; Antippen zeigt die Entsorger des Kreises.
private struct DistrictListView: View {
    var onChoose: ((CatalogEntry) -> Void)?
    @State private var query = ""
    private let all = ProviderCatalog.coverage

    private var grouped: [(state: String, items: [DistrictCoverage])] {
        let needle = ProviderCatalog.fold(query)
        let items = needle.isEmpty ? all : all.filter { ProviderCatalog.fold($0.district).contains(needle) || ProviderCatalog.fold($0.state).contains(needle) }
        let groups = Dictionary(grouping: items, by: \.state)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.state) { group in
                Section(group.state) {
                    ForEach(group.items) { item in
                        NavigationLink(item.displayName) { DistrictEntriesView(coverage: item, onChoose: onChoose) }
                    }
                }
            }
        }
        .navigationTitle(L10n.t("Landkreise", "Districts"))
        .searchable(text: $query, prompt: L10n.t("Landkreis oder Bundesland", "District or state"))
    }
}

/// Die Entsorger eines Kreises.
private struct DistrictEntriesView: View {
    let coverage: DistrictCoverage
    var onChoose: ((CatalogEntry) -> Void)?

    var body: some View {
        List(ProviderCatalog.entries(inDistrict: coverage.district)) { entry in
            if let onChoose {
                Button { onChoose(entry) } label: { content(entry) }
            } else {
                content(entry)
            }
        }
        .navigationTitle(coverage.displayName)
    }

    private func content(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title).foregroundStyle(.primary)
            Text(entry.kind.displayName).font(.caption).foregroundStyle(.secondary)
            if let restriction = ProviderCatalog.restriction(for: entry) {
                Text(restriction).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
