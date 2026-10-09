import SwiftUI
import TonneCore

/// „Geht mein Ort?“: Ort eingeben → welcher Entsorger ihn bedient und mit welcher Einschränkung.
/// Ohne Eingabe: Stand der Abdeckung, Entsorger mit Einschränkungen und die Wege, trotzdem zu Terminen zu kommen.
struct CoverageView: View {
    /// Im Einrichtungsassistenten: Antippen eines Entsorgers wählt ihn direkt aus.
    var onChoose: ((CatalogEntry) -> Void)? = nil

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
                workaroundSection
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
        Section(L10n.t("Noch nicht angebunden", "Not connected yet")) {
            ForEach(missing) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                    if !item.missingPlaces.isEmpty {
                        Text(L10n.t("Es fehlen noch: \(item.missingPlaces.joined(separator: ", "))",
                                    "Still missing: \(item.missingPlaces.joined(separator: ", "))"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
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
                workaroundSection
            } else {
                Section(L10n.t("Passende Entsorger", "Matching providers")) {
                    ForEach(found) { entryRow($0) }
                }
            }
        } else {
            ForEach(checks) { check in
                Section {
                    if check.isCovered {
                        ForEach(check.entries) { entryRow($0) }
                    } else {
                        Label(L10n.t("Noch nicht angebunden – unten steht, wie du trotzdem zu Terminen kommst.",
                                     "Not connected yet – see below how to still get your dates."),
                              systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("\(check.name) · \(DistrictCoverage.displayName(check.district))")
                }
                if !check.otherEntries.isEmpty {
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
            if checks.contains(where: { !$0.isCovered }) { workaroundSection }
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

    /// Mail mit Ort und PDF-Link an den Entwickler; der Ort kommt bei der Jahrespflege über tools/pdfkalender dazu.
    private var pdfMail: URL? {
        let place = trimmedQuery
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "thomas@kant.ovh"
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.t("PDF-Abfallkalender", "PDF waste calendar") + (place.isEmpty ? "" : " – \(place)")),
            URLQueryItem(name: "body", value: L10n.t("Ort / Landkreis: \(place)\nLink zum PDF-Abfallkalender (oder PDF anhängen):\n\n",
                                                     "Town / district: \(place)\nLink to the PDF waste calendar (or attach the PDF):\n\n")),
        ]
        return components.url
    }

    private var workaroundSection: some View {
        Section {
            Label(L10n.t("ICS-Link: Viele Abfallportale bieten „Kalender abonnieren“ oder „iCal-Export“. Den Link beim Anlegen eines Standorts unter „Entsorger nicht dabei?“ einfügen – er wird wöchentlich neu geladen.",
                         "ICS link: many waste portals offer “subscribe to calendar” or “iCal export”. Paste the link under “Provider not listed?” when adding a location – it is reloaded weekly."),
                  systemImage: "link")
            Label(L10n.t("CSV-Datei: Vorlage unten in „Dateien“ sichern oder an dich selbst schicken, Termine vom Papierkalender eintragen (Datum;Müllart, z. B. in Excel oder Numbers) und beim Standort „ICS- oder CSV-Datei importieren“ wählen.",
                         "CSV file: save the template below to Files or send it to yourself, enter the dates from your paper calendar (date;waste type, e.g. in Excel or Numbers) and choose “Import ICS or CSV file” in the location."),
                  systemImage: "tablecells")
            Label(L10n.t("Rhythmus: Feste Abfuhr (z. B. alle 2 Wochen dienstags) direkt bei der Müllart einstellen.",
                         "Rhythm: set a fixed schedule (e.g. every 2 weeks on Tuesday) directly in the waste type."),
                  systemImage: "repeat")
            ShareLink(item: PickupCSVFile(text: PickupCSV.template(), fileName: L10n.t("Abfuhrtermine-Vorlage.csv", "Pickup-template.csv")),
                      preview: SharePreview(L10n.t("CSV-Vorlage", "CSV template"))) {
                Label(L10n.t("CSV-Vorlage speichern oder senden", "Save or send CSV template"), systemImage: "square.and.arrow.up")
            }
            Label(L10n.t("Nur PDF? Schick uns den Abfallkalender deines Orts. Er wird geprüft und mit einem der nächsten Updates eingebaut.",
                         "Only a PDF? Send us your town’s waste calendar. It will be checked and added in a future update."),
                  systemImage: "doc.richtext")
            if let pdfMail {
                Link(destination: pdfMail) {
                    Label(L10n.t("PDF-Kalender schicken", "Send PDF calendar"), systemImage: "envelope")
                }
            }
        } header: {
            Text(L10n.t("Ort fehlt? So geht es trotzdem", "Town missing? How to still get your dates"))
        }
        .font(.subheadline)
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
