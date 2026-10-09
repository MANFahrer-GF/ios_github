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
    /// Gemeinden ohne Gemeinde-Eintrag – bei „teilweise“ die, die noch fehlen.
    public let missingPlaces: [String]

    public var id: String { district }
    /// Ein Entsorger für den Kreis – oder Gemeinde-Einträge für alle seine Gemeinden (z. B. eine kreisfreie Stadt).
    public var isCovered: Bool { !entryIDs.isEmpty || (municipalityCount > 0 && missingPlaces.isEmpty) }
    /// Kein Kreis-Entsorger, aber einzelne Gemeinden sind dabei.
    public var isPartial: Bool { !isCovered && !localEntryIDs.isEmpty }
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
                             missingPlaces: (places[district] ?? []).filter { !(localNames[district] ?? []).contains($0) }.sorted())
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
    public var id: String { "\(district)|\(name)" }
    public var isCovered: Bool { !entries.isEmpty || !otherEntries.isEmpty }
}

public extension ProviderCatalog {
    /// Gemeinden zur Eingabe mit ihren Entsorgern (leer, wenn die Eingabe keine Gemeinde ist).
    static func checkPlace(_ query: String) -> [PlaceCheck] {
        municipalities(matching: query).map { hit in
            let pair = "\(hit.district)|\(hit.name)"
            let local = entries.filter { (CatalogRegions.localEntries[$0.id] ?? []).contains(pair) }
            let regional = entries.filter { (CatalogRegions.entryDistricts[$0.id] ?? []).contains(hit.district) && !local.contains($0) }
            let fits = regional.filter { serves($0, municipality: hit.name, district: hit.district) }
            let others = regional.filter { !fits.contains($0) }
            let byTitle = { (a: CatalogEntry, b: CatalogEntry) in a.title.localizedStandardCompare(b.title) == .orderedAscending }
            return PlaceCheck(name: hit.name, district: hit.district, entries: (local + fits).sorted(by: byTitle), otherEntries: others.sorted(by: byTitle))
        }
    }

    /// Gilt ein kreisweit zugeordneter Eintrag für diese Gemeinde? Ja, wenn er sie (oder den Kreis) in der Ortsliste
    /// oder im Titel nennt oder ohne Ortsliste nicht nach einer einzelnen Gemeinde benannt ist („Landkreis Ansbach“ ja,
    /// „Gemeinde Gumtow (Landkreis Prignitz)“ nicht für Perleberg).
    private static func serves(_ entry: CatalogEntry, municipality: String, district: String) -> Bool {
        let place = fold(municipality.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression))
        let county = fold(DistrictCoverage.displayName(district).replacingOccurrences(of: #"^(Landkreis|Kreis) "#, with: "", options: .regularExpression))
        let names = entry.places.map(fold)
        if names.contains(where: { $0 == place || $0.hasPrefix(place + " ") || $0.hasPrefix(place + "(") || $0 == county }) { return true }
        let title = fold(entry.title)
        if title.range(of: #"(^|[^\p{L}])"# + NSRegularExpression.escapedPattern(for: place) + #"($|[^\p{L}])"#, options: .regularExpression) != nil { return true }
        let namedForOneTown = ["gemeinde ", "stadt ", "amt ", "markt ", "verbandsgemeinde ", "samtgemeinde ", "ortsgemeinde "].contains { title.hasPrefix($0) }
        return names.isEmpty && !namedForOneTown
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
