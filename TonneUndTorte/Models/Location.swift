import Foundation
import SwiftData
import TonneCore

/// Ein Standort bzw. Haushalt mit eigenen Müllarten und optionaler Online-Quelle.
/// CloudKit-tauglich: alle Beziehungen optional, alle Werte mit Standard.
@Model
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var symbolName: String = "house.fill"
    var colorHex: String = "#2F6FED"
    var sortOrder: Int = 0
    /// Kodierte `SourceConfiguration`; nil = manuell gepflegt.
    var sourceConfigJSON: String?
    var lastSyncAt: Date?
    var lastSyncMessage: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \WasteType.location)
    var wasteTypes: [WasteType]?

    init(name: String, address: String = "", symbolName: String = "house.fill", colorHex: String = "#2F6FED", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var source: SourceConfiguration? {
        get { SourceConfiguration.decode(sourceConfigJSON) }
        set { sourceConfigJSON = newValue?.encoded() }
    }

    var canSync: Bool { source != nil }

    var sourceDescription: String {
        guard let source else { return "Manuell / ICS-Datei" }
        return "\(source.providerKind.displayName) · \(source.label)"
    }

    var sortedWasteTypes: [WasteType] {
        (wasteTypes ?? []).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}
