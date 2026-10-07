import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live-Aktivität „Tonne rausstellen“ am Vorabend – auf Sperrbildschirm und in der Dynamic Island.
struct PickupActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var names: [String]
        var symbolNames: [String]
        var colorHexes: [String]
        var done: Bool
    }

    var dayKey: String
    var pickupDate: Date
    var locationName: String?
}
#endif
