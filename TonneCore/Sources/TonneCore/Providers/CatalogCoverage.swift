import Foundation

/// Welche Landkreise und kreisfreien Städte der Katalog abdeckt – für die Übersicht „Abdeckung“ in der App.
public struct DistrictCoverage: Identifiable, Hashable, Sendable {
    /// Name wie im Gemeindeverzeichnis, z. B. „Landkreis Heidekreis“.
    public let district: String
    public let state: String
    /// Katalogeinträge (`CatalogEntry.id`), die mindestens einen Teil des Kreises abdecken.
    public let entryIDs: [String]
    public let municipalityCount: Int

    public var id: String { district }
    public var isCovered: Bool { !entryIDs.isEmpty }
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

    /// Katalogeinträge eines Kreises.
    static func entries(inDistrict district: String) -> [CatalogEntry] {
        entries.filter { (CatalogRegions.entryDistricts[$0.id] ?? []).contains(district) }
    }
}

enum CoverageIndex {
    static let all: [DistrictCoverage] = {
        var byDistrict: [String: [String]] = [:]
        for (entryID, districts) in CatalogRegions.entryDistricts {
            for district in districts { byDistrict[district, default: []].append(entryID) }
        }
        let known = Set(ProviderCatalog.entries.map(\.id))
        var counts: [String: Int] = [:]
        for item in MunicipalityIndex.all { counts[item.district, default: 0] += 1 }
        return CatalogRegions.districtStates.map { district, state in
            DistrictCoverage(district: district, state: state,
                             entryIDs: (byDistrict[district] ?? []).filter(known.contains).sorted(),
                             municipalityCount: counts[district] ?? 0)
        }
        .sorted { ($0.state, $0.displayName) < ($1.state, $1.displayName) }
    }()
}
