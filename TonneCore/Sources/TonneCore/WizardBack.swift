import Foundation

/// „Zurück“ im Einrichtungs-Assistenten. Automatisch gewählte Schritte (einzige Option) würden nach dem Entfernen sofort
/// wieder gewählt – man landete erneut auf demselben Schritt und kam nicht mehr zurück (Prüfung 20.11.2026). Darum fallen
/// sie samt der letzten eigenen Wahl davor weg.
public enum WizardBack {
    /// Wie viele Auswahlen nach „Zurück“ stehen bleiben. `auto`: Indizes automatisch gewählter Auswahlen.
    public static func remainingCount(selectionCount: Int, auto: Set<Int>) -> Int {
        var count = selectionCount
        while count > 0, auto.contains(count - 1) { count -= 1 }
        return max(count - 1, 0)
    }
}
