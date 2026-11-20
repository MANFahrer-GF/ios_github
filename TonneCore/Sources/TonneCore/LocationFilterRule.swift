import Foundation

/// Standortfilter in Übersicht und Kalender. Der gespeicherte Wert gilt nur, solange es den Standort noch gibt und mehr
/// als einer da ist – sonst zeigte die App nach dem Löschen des gefilterten Standorts keine Abholung mehr, und das
/// Filtermenü (nur ab zwei Standorten sichtbar) war weg, man kam nicht mehr heraus (Prüfung 20.11.2026).
public enum LocationFilterRule {
    public static func effective(_ storedID: String, existing: [UUID]) -> UUID? {
        guard existing.count > 1, let id = UUID(uuidString: storedID), existing.contains(id) else { return nil }
        return id
    }
}
