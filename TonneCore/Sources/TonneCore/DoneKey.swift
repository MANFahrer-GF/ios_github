import Foundation

/// Schlüssel für „Erledigt“: Tag („2026-11-21“) oder Tag eines Standorts („2026-11-21@<Standort-ID>“).
/// Ohne Standort (Mitteilung, Watch, Live-Aktivität, Siri) gilt er für alle Standorte des Tages; mit Standort
/// (gefilterte Übersicht, Standort-Widget) nur für diesen – vorher erledigte ein Tipp im Widget „Zuhause“ auch den
/// anderen Standort samt seiner Erinnerungen (Thomas 20.11.2026: je Standort).
public enum DoneKey {
    public static func make(day: String, locationID: String?) -> String {
        guard let locationID, !locationID.isEmpty else { return day }
        return "\(day)@\(locationID)"
    }

    public static func split(_ key: String) -> (day: String, locationID: String?) {
        guard let at = key.firstIndex(of: "@") else { return (key, nil) }
        let location = String(key[key.index(after: at)...])
        return (String(key[..<at]), location.isEmpty ? nil : location)
    }
}

extension WidgetSnapshot.PickupDay {
    /// Markiert die Müllarten eines Standorts (nil: alle) als erledigt bzw. offen. `done` des Tages = alle erledigt.
    public mutating func setDone(_ done: Bool, locationID: String?) {
        let before = self.done
        items = items.map { item in
            var copy = item
            if copy.done == nil { copy.done = before }
            if locationID == nil || copy.locationID == locationID { copy.done = done }
            return copy
        }
        self.done = items.allSatisfy { $0.done == true }
        // Zeitstempel nur weg, wenn nichts mehr erledigt ist – ein anderer, weiter erledigter Standort behält sein
        // Rückgängig-Fenster im Standort-Widget (Prüfbefund 20.11.2026)
        if !items.contains(where: { $0.done == true }) { doneAt = nil }
    }
}

extension DoneKey {
    public enum Action { case done(String), undo(String) }

    /// Ausstehende Markierungen (aus Widget/Watch, von der App später übernommen) widerspruchsfrei halten. Die App wendet
    /// erst alle Rücknahmen, dann alle Erledigt an – ein übrig gebliebener Schlüssel desselben Tages überschriebe sonst die
    /// letzte Handlung (Prüfbefund 20.11.2026). `locations`: Standorte mit Abholung an diesem Tag.
    public static func reconcile(done: Set<String>, undo: Set<String>, _ action: Action, locations: [String]) -> (done: Set<String>, undo: Set<String>) {
        var done = done, undo = undo
        func ofDay(_ day: String) -> (String) -> Bool { { split($0).day == day } }
        switch action {
        case .done(let key):
            let (day, location) = split(key)
            if let location {
                undo.remove(make(day: day, locationID: location))
            } else {
                undo = undo.filter { !ofDay(day)($0) }
                done = done.filter { !ofDay(day)($0) }
            }
            done.insert(key)
        case .undo(let key):
            let (day, location) = split(key)
            if let location {
                done.remove(key)
                // Ein noch offenes „ganzer Tag erledigt“ gilt dann nur noch für die übrigen Standorte
                if done.remove(day) != nil {
                    for other in locations where other != location { done.insert(make(day: day, locationID: other)) }
                }
            } else {
                done = done.filter { !ofDay(day)($0) }
                undo = undo.filter { !ofDay(day)($0) }
            }
            undo.insert(key)
        }
        return (done, undo)
    }
}
