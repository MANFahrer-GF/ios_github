import Foundation
import SwiftUI

/// Ein konkreter Termin an einem bestimmten Tag – entweder eine Abholung oder ein Geburtstag.
/// Wird nicht gespeichert, sondern bei Bedarf aus den Modellen berechnet.
struct CalendarEvent: Identifiable, Hashable {
    enum Kind: Hashable {
        case waste
        case birthday
    }

    let id: String
    let date: Date
    let kind: Kind
    let title: String
    let subtitle: String
    let colorHex: String
    let symbolName: String
    /// Name des Standorts (nur bei Abholungen und nur, wenn ein Standort zugeordnet ist).
    let locationName: String?

    var color: Color { Color(hex: colorHex) }

    static func waste(_ type: WasteType, on date: Date) -> CalendarEvent {
        CalendarEvent(
            id: "waste-\(type.id.uuidString)-\(Int(date.timeIntervalSince1970))",
            date: date,
            kind: .waste,
            title: type.name,
            subtitle: type.location?.name ?? "Abholung",
            colorHex: type.colorHex,
            symbolName: type.symbolName,
            locationName: type.location?.name
        )
    }

    static func birthday(_ person: Person, on date: Date, age: Int?) -> CalendarEvent {
        let subtitle: String
        if let age {
            subtitle = "wird \(age)"
        } else {
            subtitle = "Geburtstag"
        }
        return CalendarEvent(
            id: "bday-\(person.id.uuidString)-\(Int(date.timeIntervalSince1970))",
            date: date,
            kind: .birthday,
            title: person.name,
            subtitle: subtitle,
            colorHex: person.colorHex,
            symbolName: "birthday.cake.fill",
            locationName: nil
        )
    }
}
