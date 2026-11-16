import Foundation

/// Wann ein Standort automatisch neu abgeglichen wird. Portale mit mitlaufendem Fenster (SBAZV: rund 6 Wochen voraus)
/// bringen neue Termine nach und nach – reichen die bekannten Termine weniger als 8 Wochen voraus, alle 2 Tage, sonst
/// wöchentlich. Manueller Abgleich ist davon unberührt.
public enum SyncRhythm {
    static let shortLead: TimeInterval = 8 * 7 * 86_400
    static let shortInterval: TimeInterval = 2 * 86_400
    static let longInterval: TimeInterval = 7 * 86_400

    /// Wie weit der Standort voraus bekannt ist: das kürzeste Ende unter den Müllarten, die noch künftige Termine haben.
    /// Ein einzelner ferner Termin (Sperrmüll in 10 Wochen) darf ein 6-Wochen-Fenster nicht auf wöchentlich stellen.
    public static func lastKnownPickup(latestPerType: [Date], now: Date = Date()) -> Date? {
        latestPerType.filter { $0 >= now }.min()
    }

    /// `lastKnownPickup`: spätester abgeglichener Termin des Standorts (nil, wenn keiner bekannt ist).
    public static func isDue(lastSync: Date?, lastKnownPickup: Date?, now: Date = Date()) -> Bool {
        guard let lastSync else { return true }
        let lead = lastKnownPickup.map { $0.timeIntervalSince(now) } ?? 0
        let interval = lead < shortLead ? shortInterval : longInterval
        return now.timeIntervalSince(lastSync) > interval
    }
}
