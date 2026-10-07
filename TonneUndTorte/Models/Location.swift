import Foundation
import SwiftData

/// Ein Standort bzw. Haushalt, z. B. „Gifhorn“ oder „Kuhlhausen“.
/// Jeder Standort hat seine eigenen Müllarten und optional eine Online-Datenquelle,
/// über die sich die Abfuhrtermine automatisch aktualisieren lassen.
@Model
final class Location {
    enum SourceKind: String, CaseIterable {
        /// Termine werden manuell gepflegt oder aus einer ICS-Datei importiert.
        case manual
        /// AWIDO-Portal (cubefour) – z. B. Landkreis Gifhorn.
        case awido
        /// Eine ICS-Datei im Internet, die regelmäßig neu geladen wird.
        case icsURL
    }

    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var symbolName: String = "house.fill"
    var colorHex: String = "#2E9E6B"
    var sortOrder: Int = 0

    var sourceKindRaw: String = SourceKind.manual.rawValue
    /// AWIDO: Kundenkennung (z. B. „gifhorn“)
    var awidoCustomer: String?
    /// AWIDO: Objekt-ID der gewählten Straße bzw. Hausnummer
    var awidoOid: String?
    /// AWIDO: Lesbarer Name der Auswahl (z. B. „Gifhorn, Steinstraße“)
    var awidoLabel: String?
    /// ICS-Abo: URL der Kalenderdatei
    var icsURLString: String?

    var lastSyncAt: Date?
    var lastSyncMessage: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \WasteType.location)
    var wasteTypes: [WasteType] = []

    init(name: String, address: String = "", symbolName: String = "house.fill", colorHex: String = "#2E9E6B", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var sourceKind: SourceKind {
        get { SourceKind(rawValue: sourceKindRaw) ?? .manual }
        set { sourceKindRaw = newValue.rawValue }
    }

    /// Kann dieser Standort seine Termine online aktualisieren?
    var canSync: Bool {
        switch sourceKind {
        case .manual: return false
        case .awido: return awidoCustomer != nil && awidoOid != nil
        case .icsURL: return icsURLString.flatMap(URL.init(string:)) != nil
        }
    }

    var sourceDescription: String {
        switch sourceKind {
        case .manual: return "Manuell / ICS-Datei"
        case .awido: return "AWIDO-Portal" + (awidoLabel.map { " · \($0)" } ?? "")
        case .icsURL: return "ICS-Abo"
        }
    }

    var sortedWasteTypes: [WasteType] {
        wasteTypes.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}
