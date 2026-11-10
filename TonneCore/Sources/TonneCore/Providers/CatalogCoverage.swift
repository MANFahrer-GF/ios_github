import Foundation

/// Welche Landkreise und kreisfreien Städte der Katalog abdeckt – für die Übersicht „Abdeckung“ in der App.
public struct DistrictCoverage: Identifiable, Hashable, Sendable {
    /// Name wie im Gemeindeverzeichnis, z. B. „Landkreis Heidekreis“.
    public let district: String
    public let state: String
    /// Katalogeinträge (`CatalogEntry.id`) für den Kreis oder einen größeren Teil davon.
    public let entryIDs: [String]
    /// Einträge, die nur eine einzelne Gemeinde des Kreises abdecken (Gemeinde-Portale).
    public let localEntryIDs: [String]
    /// Gemeinden, die über solche Einzel-Einträge abgedeckt sind.
    public let localPlaces: [String]
    /// Bewohnte Gemeinden des Kreises (ohne gemeindefreie Gebiete).
    public let municipalityCount: Int
    /// Gemeinden, die kein Eintrag belegt führt (laut erzeugter Zuordnung Gemeinde → Einträge).
    public let missingPlaces: [String]

    public var id: String { district }
    /// Abgedeckt ist ein Kreis nur, wenn jede seiner Gemeinden einen Eintrag hat, der sie belegt führt.
    public var isCovered: Bool { municipalityCount > 0 && missingPlaces.isEmpty }
    /// Ein Teil der Gemeinden ist dabei, andere fehlen noch.
    public var isPartial: Bool { !isCovered && !allEntryIDs.isEmpty }
    public var allEntryIDs: [String] { entryIDs + localEntryIDs }
    public var displayName: String { DistrictCoverage.displayName(district) }

    /// „Landkreis Rems-Murr-Kreis“ → „Rems-Murr-Kreis“, „Kreisfreie Stadt Kassel“ → „Kassel (Stadt)“.
    public static func displayName(_ district: String) -> String {
        for prefix in ["Kreisfreie Stadt ", "Stadtkreis "] where district.hasPrefix(prefix) {
            return L10n.t("\(district.dropFirst(prefix.count)) (Stadt)", "\(district.dropFirst(prefix.count)) (city)")
        }
        for prefix in ["Landkreis ", "Kreis "] where district.hasPrefix(prefix) {
            let rest = String(district.dropFirst(prefix.count))
            let lower = rest.lowercased()
            if lower.hasSuffix("kreis") || lower.hasPrefix("regionalverband") || lower.hasPrefix("städteregion") || lower.hasPrefix("region ") {
                return rest
            }
            return "\(prefix.trimmingCharacters(in: .whitespaces)) \(rest)"
        }
        return district
    }
}

public extension ProviderCatalog {
    /// Alle Kreise mit Abdeckungsstand, sortiert nach Bundesland und Name.
    static var coverage: [DistrictCoverage] { CoverageIndex.all }

    /// Katalogeinträge eines Kreises (kreisweit und für einzelne Gemeinden).
    static func entries(inDistrict district: String) -> [CatalogEntry] {
        entries.filter { entry in
            (CatalogRegions.entryDistricts[entry.id] ?? []).contains(district)
                || (CatalogRegions.localEntries[entry.id] ?? []).contains { $0.hasPrefix(district + "|") }
        }
    }
}

enum CoverageIndex {
    static let all: [DistrictCoverage] = {
        let known = Set(ProviderCatalog.entries.map(\.id))
        var regional: [String: [String]] = [:], local: [String: Set<String>] = [:], localNames: [String: Set<String>] = [:]
        for (entryID, districts) in CatalogRegions.entryDistricts where known.contains(entryID) {
            for district in districts { regional[district, default: []].append(entryID) }
        }
        for (entryID, pairs) in CatalogRegions.localEntries where known.contains(entryID) {
            for pair in pairs {
                let parts = pair.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                local[parts[0], default: []].insert(entryID)
                localNames[parts[0], default: []].insert(parts[1])
            }
        }
        var places: [String: [String]] = [:]
        for item in MunicipalityIndex.all where !CatalogRegions.unincorporated.contains("\(item.district)|\(item.name)") {
            places[item.district, default: []].append(item.name)
        }
        return CatalogRegions.districtStates.map { district, state in
            DistrictCoverage(district: district, state: state,
                             entryIDs: (regional[district] ?? []).sorted(),
                             localEntryIDs: (local[district] ?? []).filter { !(regional[district] ?? []).contains($0) }.sorted(),
                             localPlaces: (localNames[district] ?? []).sorted(), municipalityCount: places[district]?.count ?? 0,
                             missingPlaces: (places[district] ?? []).filter { PlaceMapIndex.entryIDs["\(district)|\($0)"] == nil }.sorted())
        }
        .sorted { ($0.state, $0.displayName) < ($1.state, $1.displayName) }
    }()
}

/// Antwort auf „Geht mein Ort?“: eine Gemeinde mit den Entsorgern, die sie bedienen.
public struct PlaceCheck: Identifiable, Hashable {
    public let name: String
    public let district: String
    /// Entsorger für diese Gemeinde: kreisweit, mit der Gemeinde in der Ortsliste oder im Namen, oder eigens für sie.
    public let entries: [CatalogEntry]
    /// Weitere Einträge desselben Kreises, die erkennbar für andere Gemeinden gelten (z. B. „Gemeinde Gumtow“ bei Perleberg)
    /// – ein Amt kann trotzdem auch seine Mitgliedsgemeinden bedienen.
    public let otherEntries: [CatalogEntry]
    /// Warum kein Entsorger belegt ist (ausdrückliche Lücke der Zuordnung), sonst nil.
    public let gapNote: String?
    /// Nachweislich kein abrufbarer Online-Kalender (z. B. Portal des Entsorgers abgeschaltet).
    public let isUnavailable: Bool

    public init(name: String, district: String, entries: [CatalogEntry], otherEntries: [CatalogEntry],
                gapNote: String? = nil, isUnavailable: Bool = false) {
        self.name = name
        self.district = district
        self.entries = entries
        self.otherEntries = otherEntries
        self.gapNote = gapNote
        self.isUnavailable = isUnavailable
    }

    public var id: String { "\(district)|\(name)" }
    /// Nur, wenn ein Entsorger die Gemeinde belegt führt – weitere Einträge des Kreises zählen nicht.
    public var isCovered: Bool { !entries.isEmpty }
}

/// Die erzeugte Zuordnung Gemeinde → Einträge (`CatalogPlaceMap`), einmal gelesen. Schlüssel: „Landkreis|Gemeinde“.
enum PlaceMapIndex {
    static let entryIDs: [String: [String]] = {
        var out: [String: [String]] = [:]
        for line in CatalogPlaceMap.places.split(separator: "\n") {
            guard let cut = line.lastIndex(of: "=") else { continue }
            out[String(line[..<cut])] = line[line.index(after: cut)...].split(separator: ",")
                .compactMap { Int($0) }.filter { CatalogPlaceMap.entryIDs.indices.contains($0) }.map { CatalogPlaceMap.entryIDs[$0] }
        }
        return out
    }()

    /// Ausdrückliche Lücken: Gemeinde → (nachweislich nicht holbar, Grund-Kürzel).
    static let gaps: [String: (unavailable: Bool, reason: String)] = {
        var out: [String: (unavailable: Bool, reason: String)] = [:]
        for line in CatalogPlaceMap.gaps.split(separator: "\n") {
            guard let cut = line.lastIndex(of: "=") else { continue }
            let parts = line[line.index(after: cut)...].split(separator: ",")
            guard parts.count == 2, let index = Int(parts[1]), CatalogPlaceMap.gapReasons.indices.contains(index) else { continue }
            out[String(line[..<cut])] = (parts[0] == "n", CatalogPlaceMap.gapReasons[index])
        }
        return out
    }()

    static func note(_ reason: String) -> String {
        switch reason {
        case "portal_abgeschaltet":
            return L10n.t("Das Portal des Entsorgers ist derzeit abgeschaltet – es gibt keinen abrufbaren Online-Kalender.",
                          "The provider's portal is currently offline – there is no online calendar to fetch.")
        case "kein_eintrag":
            return L10n.t("Für diesen Kreis gibt es noch keinen Entsorger im Katalog.",
                          "There is no provider for this district in the catalogue yet.")
        case "nicht_in_liste":
            return L10n.t("Kein Entsorger im Katalog führt diese Gemeinde in seiner Ortsliste.",
                          "No provider in the catalogue lists this municipality.")
        default:
            return L10n.t("Für diese Gemeinde ist noch nicht belegt, welcher Entsorger sie führt.",
                          "It is not yet verified which provider covers this municipality.")
        }
    }
}

public extension ProviderCatalog {
    /// Gemeinden zur Eingabe mit ihren Entsorgern (leer, wenn die Eingabe keine Gemeinde ist).
    static func checkPlace(_ query: String) -> [PlaceCheck] {
        municipalities(matching: query).map { hit in
            let pair = "\(hit.district)|\(hit.name)"
            // Belegt ist nur, was die erzeugte Zuordnung führt (Abgleich der echten Ortslisten) – keine Vermutung aus dem Kreis.
            let proven = Set(PlaceMapIndex.entryIDs[pair] ?? [])
            let fits = entries.filter { proven.contains($0.id) }
            let others = entries.filter { !proven.contains($0.id) && (CatalogRegions.entryDistricts[$0.id] ?? []).contains(hit.district) }
            let gap = PlaceMapIndex.gaps[pair]
            let byTitle = { (a: CatalogEntry, b: CatalogEntry) in a.title.localizedStandardCompare(b.title) == .orderedAscending }
            // Ämter/Verbandsgemeinden bedienen mehrere Gemeinden, ohne sie aufzuzählen – als wahrscheinlichste Kandidaten zuerst
            let groupsFirst = others.sorted { a, b in
                let ga = servesSeveralTowns(a), gb = servesSeveralTowns(b)
                return ga != gb ? ga : byTitle(a, b)
            }
            return PlaceCheck(name: hit.name, district: hit.district, entries: fits.sorted(by: byTitle), otherEntries: groupsFirst,
                              gapNote: fits.isEmpty ? PlaceMapIndex.note(gap?.reason ?? "") : nil,
                              isUnavailable: fits.isEmpty && gap?.unavailable == true)
        }
    }

    /// Einträge, die eine Gemeinde belegt führen („Landkreis|Gemeinde“); nil, wenn die Zuordnung keinen kennt.
    static func provenEntryIDs(forPlace pair: String) -> [String]? { PlaceMapIndex.entryIDs[pair] }

    private static func servesSeveralTowns(_ entry: CatalogEntry) -> Bool {
        let title = fold(entry.title)
        return ["amt ", "verbandsgemeinde ", "samtgemeinde ", "verwaltungsgemeinschaft "].contains { title.hasPrefix($0) }
    }

    /// Einschränkung eines Entsorgers in einem Satz (PDF-Jahresdaten, berechnete Termine, nur einzelne Müllarten …),
    /// sonst nil. Stammt aus dem Hinweis des Anbieters, den die App auch beim Standort zeigt.
    static func restriction(for entry: CatalogEntry) -> String? {
        RestrictionIndex.lock.lock(); defer { RestrictionIndex.lock.unlock() }
        if let cached = RestrictionIndex.cache[entry.id] { return cached }
        let notice = ProviderFactory.make(kind: entry.kind, serviceKey: entry.serviceKey).restriction
        RestrictionIndex.cache[entry.id] = .some(notice)
        return notice
    }

    /// Alle Entsorger mit Einschränkung – für die Übersicht der Sonderfälle.
    static var restrictedEntries: [CatalogEntry] {
        entries.filter { restriction(for: $0) != nil }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// Hinweise je Katalogeintrag, einmal ermittelt (Jahresdaten lesen dafür ihre JSON-Daten).
enum RestrictionIndex {
    static let lock = NSLock()
    nonisolated(unsafe) static var cache: [String: String?] = [:]
}
