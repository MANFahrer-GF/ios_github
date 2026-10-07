import SwiftUI
import TonneCore

/// Abdeckung nach Landkreis: welche Kreise und kreisfreien Städte schon angebunden sind und welche noch nicht –
/// mit dem Weg, wie man dort trotzdem zu Terminen kommt (ICS-Link, CSV-Datei, Rhythmus).
struct CoverageView: View {
    enum Tab: Hashable { case missing, covered }

    /// Im Einrichtungsassistenten: Antippen eines Entsorgers wählt ihn direkt aus.
    var onChoose: ((CatalogEntry) -> Void)? = nil

    @State private var tab: Tab = .missing
    @State private var query = ""

    private let all = ProviderCatalog.coverage

    private var missingCount: Int { all.filter { !$0.isCovered }.count }
    private var coveredCount: Int { all.count - missingCount }

    private var filtered: [DistrictCoverage] {
        let base = all.filter { tab == .covered ? $0.isCovered : !$0.isCovered }
        let needle = ProviderCatalog.fold(query)
        guard !needle.isEmpty else { return base }
        let viaMunicipality = Set(ProviderCatalog.municipalities(matching: query).map(\.district))
        return base.filter { item in
            viaMunicipality.contains(item.district)
                || ProviderCatalog.fold(item.district).contains(needle)
                || ProviderCatalog.fold(item.state).contains(needle)
        }
    }

    private var grouped: [(state: String, items: [DistrictCoverage])] {
        let groups = Dictionary(grouping: filtered, by: \.state)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Picker(L10n.t("Ansicht", "View"), selection: $tab) {
                    Text(L10n.t("Noch nicht dabei (\(missingCount))", "Not yet (\(missingCount))")).tag(Tab.missing)
                    Text(L10n.t("Verfügbar (\(coveredCount))", "Available (\(coveredCount))")).tag(Tab.covered)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(L10n.t("\(coveredCount) von \(all.count) Landkreisen und kreisfreien Städten haben mindestens einen angebundenen Entsorger. In manchen Kreisen sind nur einzelne Gemeinden dabei.",
                            "\(coveredCount) of \(all.count) districts have at least one connected operator. In some districts only individual municipalities are covered."))
            }

            if tab == .missing { workaroundSection }

            ForEach(grouped, id: \.state) { group in
                Section(group.state) {
                    ForEach(group.items) { item in
                        if item.isCovered {
                            NavigationLink { DistrictEntriesView(coverage: item, onChoose: onChoose) } label: { row(item) }
                        } else {
                            row(item)
                        }
                    }
                }
            }
            if filtered.isEmpty {
                Text(L10n.t("Nichts gefunden.", "Nothing found.")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.t("Abdeckung", "Coverage"))
        .searchable(text: $query, prompt: L10n.t("Landkreis oder Gemeinde", "District or municipality"))
    }

    private func row(_ item: DistrictCoverage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isCovered ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(item.isCovered ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                Text(item.isCovered
                     ? L10n.t("\(item.entryIDs.count) Entsorger · \(item.municipalityCount) Gemeinden", "\(item.entryIDs.count) operators · \(item.municipalityCount) municipalities")
                     : L10n.t("Noch nicht angebunden · \(item.municipalityCount) Gemeinden", "Not connected yet · \(item.municipalityCount) municipalities"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var workaroundSection: some View {
        Section {
            Label(L10n.t("ICS-Link: Viele Abfallportale bieten „Kalender abonnieren“ oder „iCal-Export“. Den Link beim Anlegen eines Standorts unter „Entsorger nicht dabei?“ einfügen – er wird wöchentlich neu geladen.",
                         "ICS link: many waste portals offer “subscribe to calendar” or “iCal export”. Paste the link under “Operator not listed?” when adding a location – it is reloaded weekly."),
                  systemImage: "link")
            Label(L10n.t("CSV-Datei: Termine in die Vorlage eintragen (Datum;Abfallart, z. B. in Excel oder Numbers) und beim Standort „ICS- oder CSV-Datei importieren“ wählen.",
                         "CSV file: enter the dates in the template (date;waste type, e.g. in Excel or Numbers) and choose “Import ICS or CSV file” in the location."),
                  systemImage: "tablecells")
            Label(L10n.t("Rhythmus: Feste Abfuhr (z. B. alle 2 Wochen dienstags) direkt bei der Müllart einstellen.",
                         "Rhythm: set a fixed schedule (e.g. every 2 weeks on Tuesday) directly in the waste type."),
                  systemImage: "repeat")
            ShareLink(item: PickupCSVFile(text: PickupCSV.template(), fileName: L10n.t("Abfuhrtermine-Vorlage.csv", "Pickup-template.csv")),
                      preview: SharePreview(L10n.t("CSV-Vorlage", "CSV template"))) {
                Label(L10n.t("CSV-Vorlage teilen", "Share CSV template"), systemImage: "square.and.arrow.up")
            }
        } header: {
            Text(L10n.t("So geht es trotzdem", "How to still get your dates"))
        }
        .font(.subheadline)
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
        }
    }
}
