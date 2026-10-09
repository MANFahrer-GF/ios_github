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

    private var filtered: [DistrictCoverage] { Self.filter(all, tab: tab, query: query) }

    private static func filter(_ all: [DistrictCoverage], tab: Tab, query: String) -> [DistrictCoverage] {
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
                Text(L10n.t("\(coveredCount) von \(all.count) Landkreisen und kreisfreien Städten sind angebunden. Halb gefüllter Kreis: die meisten Gemeinden sind dabei, die genannten fehlen noch. Wie du dort trotzdem zu Terminen kommst, steht unten.",
                            "\(coveredCount) of \(all.count) districts are connected. Half-filled circle: most municipalities are covered, the ones listed are still missing. How to still get your dates: see below."))
            }

            ForEach(grouped, id: \.state) { group in
                Section(group.state) {
                    ForEach(group.items) { item in
                        if item.isCovered || item.isPartial {
                            NavigationLink { DistrictEntriesView(coverage: item, onChoose: onChoose) } label: { row(item) }
                        } else {
                            row(item)
                        }
                    }
                }
            }
            if grouped.isEmpty {
                Text(L10n.t("Nichts gefunden.", "Nothing found.")).foregroundStyle(.secondary)
            }

            if tab == .missing { workaroundSection }
        }
        .navigationTitle(L10n.t("Abdeckung", "Coverage"))
        .searchable(text: $query, prompt: L10n.t("Landkreis oder Gemeinde", "District or municipality"))
    }

    private func row(_ item: DistrictCoverage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isCovered ? "checkmark.circle.fill" : item.isPartial ? "circle.lefthalf.filled" : "exclamationmark.circle.fill")
                .foregroundStyle(item.isCovered ? .green : item.isPartial ? .yellow : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                Text(subtitle(item)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ item: DistrictCoverage) -> String {
        let municipalities = Self.count(item.municipalityCount, L10n.t("Gemeinde", "municipality"), L10n.t("Gemeinden", "municipalities"))
        if item.isCovered {
            return "\(Self.count(item.allEntryIDs.count, L10n.t("Entsorger", "operator"), L10n.t("Entsorger", "operators"))) · \(municipalities)"
        }
        if item.isPartial {
            let present = item.municipalityCount - item.missingPlaces.count
            return L10n.t("Es fehlen noch: \(item.missingPlaces.joined(separator: ", ")) · \(present) von \(item.municipalityCount) Gemeinden dabei",
                          "Still missing: \(item.missingPlaces.joined(separator: ", ")) · \(present) of \(item.municipalityCount) municipalities covered")
        }
        return L10n.t("Noch nicht angebunden · \(municipalities)", "Not connected yet · \(municipalities)")
    }

    private static func count(_ value: Int, _ one: String, _ many: String) -> String { "\(value) \(value == 1 ? one : many)" }

    /// Mail mit Ort und PDF-Link an den Entwickler; der Ort kommt bei der Jahrespflege über tools/pdfkalender dazu.
    private var pdfMail: URL? {
        let place = query.trimmingCharacters(in: .whitespaces)
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
            Label(L10n.t("Nur PDF? Schick uns den Abfallkalender deines Orts. Er wird geprüft und mit einem der nächsten Updates eingebaut.",
                         "Only a PDF? Send us your town’s waste calendar. It will be checked and added in a future update."),
                  systemImage: "doc.richtext")
            if let pdfMail {
                Link(destination: pdfMail) {
                    Label(L10n.t("PDF-Kalender schicken", "Send PDF calendar"), systemImage: "envelope")
                }
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
