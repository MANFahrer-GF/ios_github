import Foundation

/// Ausstehende Markierungen (Tage aus Widget, Live-Aktivität, Watch, Mitteilung) abarbeiten.
public enum PendingMarkers {
    /// Arbeitet die Tage einzeln ab und fragt vor jedem neu, ob er noch aussteht. Laufen zwei Durchläufe nebeneinander
    /// (Öffnen der Datenbank und Start der Szene), übernimmt der zweite keinen Tag, den der erste schon erledigt hat – sonst
    /// gälte die Markierung als neu und ihre Erledigt-Zeit würde „jetzt“ (Prüfbefund 4 zu Teil 13).
    @MainActor public static func apply(_ pending: () -> Set<String>, _ body: (String) async -> Void) async {
        for key in pending().sorted() where pending().contains(key) {
            await body(key)
        }
    }
}
