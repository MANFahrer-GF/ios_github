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
    public let municipalityCount: Int

    public var id: String { district }
    /// Ein Entsorger für den Kreis – oder Gemeinde-Einträge für alle seine Gemeinden (z. B. eine kreisfreie Stadt).
    public var isCovered: Bool { !entryIDs.isEmpty || (municipalityCount > 0 && localPlaces.count >= municipalityCount) }
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
        var counts: [String: Int] = [:]
        for item in MunicipalityIndex.all { counts[item.district, default: 0] += 1 }
        return CatalogRegions.districtStates.map { district, state in
            DistrictCoverage(district: district, state: state,
                             entryIDs: (regional[district] ?? []).sorted(),
                             localEntryIDs: (local[district] ?? []).filter { !(regional[district] ?? []).contains($0) }.sorted(),
                             localPlaces: (localNames[district] ?? []).sorted(), municipalityCount: counts[district] ?? 0)
        }
        .sorted { ($0.state, $0.displayName) < ($1.state, $1.displayName) }
    }()
}
