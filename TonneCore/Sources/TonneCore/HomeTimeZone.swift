import Foundation

/// Heimat-Zeitzone der App. Termine sind als Mitternacht in der Zeitzone gespeichert, in der sie angelegt wurden; auf
/// Reisen nach Westen lag jede Mitternacht am Vortag – alle Abholungen standen einen Tag zu früh, der Abgleich meldete
/// angebliche Verschiebungen (Prüfung 20.11.2026). Umschreiben ginge nicht: iCloud trüge die verschobenen Werte auf die
/// Geräte zu Hause. Darum rechnen App, Widget und Watch dauerhaft in der Heimat-Zone; auch neue Termine werden in ihr
/// gespeichert, die Datenbank bleibt so in einer einzigen Zone. Ein späterer Wechsel der Heimat würde alle vorhandenen
/// Tage verschieben und wird darum nie automatisch vorgenommen.
public enum HomeTimeZone {
    /// - Parameters:
    ///   - stored: bereits festgelegte Heimat.
    ///   - existingInstall: Die App lief schon mit einer früheren Version (Daten liegen in der damaligen Gerätezone).
    ///     Wird diese Version auf Reisen zum ersten Mal gestartet, ist offen, ob die Daten in der Gerätezone oder zu Hause
    ///     (`fallback`) angelegt wurden. Eine gespeicherte Mitternacht liegt in jeder Zone östlich davon noch am selben Tag,
    ///     darum gilt die östlichere der beiden (gleich weit: `fallback`, z. B. Algier im Winter gegen Berlin).
    ///   - fallback: Zuhause der allermeisten Nutzer (die App kennt nur deutsche Entsorger).
    public static func resolve(stored: String?, device: String, existingInstall: Bool, now: Date = Date(),
                               fallback: String = "Europe/Berlin") -> String {
        if let stored, TimeZone(identifier: stored) != nil { return stored }
        guard existingInstall, let deviceZone = TimeZone(identifier: device), let home = TimeZone(identifier: fallback) else { return device }
        return deviceZone.secondsFromGMT(for: now) > home.secondsFromGMT(for: now) ? device : fallback
    }
}
