import Foundation

/// Tonnen werden nach der Abfuhr wieder hereingeholt – Säcke, Bündel, Grünschnitt oder Sperrmüll nicht.
public enum WasteReturn {
    /// Wörter, bei denen nichts zurückgeholt wird (Sack, Bündel, Sammlungen ohne eigenen Behälter).
    private static let neverReturned = ["sack", "säcke", "saecke", "beutel", "bündel", "buendel", "sperr", "schadstoff", "problem",
                                        "grünschnitt", "gruenschnitt", "grüngut", "gruengut", "grünabfall", "gruenabfall", "gartenabfall",
                                        "strauch", "baum", "laub", "mobil", "elektro", "schrott", "altkleider", "kleider"]
    /// Wörter, die eindeutig einen Behälter meinen.
    private static let bins = ["tonne", "behälter", "behaelter", "mülleimer", "muelleimer", "bin"]

    /// Ob diese Abfallart nach der Abfuhr wieder hereingeholt werden muss.
    /// `symbol` ist das angezeigte Symbol: „Sack“ heißt nie reinholen; ein Tonnen-Symbol nur, wenn der Name nicht dagegen spricht
    /// (das Symbol wird oft automatisch aus dem Namen abgeleitet, z. B. Blatt → Biotonne auch bei „Grüngut“).
    public static func isBin(name: String, symbol: String? = nil) -> Bool {
        if symbol == "tt.sack" { return false }
        let lower = name.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if neverReturned.contains(where: { lower.contains($0) }) && !lower.contains("tonne") { return false }
        // Container: öffentliche Sammelcontainer bleiben stehen, Großbehälter mit Literangabe (Wohnanlage) werden zurückgestellt
        if lower.contains("container") {
            let sized = lower.range(of: #"\d+[.,]?\d*\s*(l\b|liter|m³|m3|cbm)"#, options: .regularExpression) != nil
            if !sized { return false }
        }
        if let symbol, symbol.hasPrefix("tt.bin") { return true }
        if bins.contains(where: { key in key == "bin" ? words.contains("bin") || words.contains("bins") : lower.contains(key) }) { return true }
        switch WasteCategory.classify(name) {
        case .residual, .organic, .paper: return true
        default: return false
        }
    }
}

/// Zeitpunkte rund um den Abholtag – gemeinsam für App, Widget und Watch.
public enum PickupTiming {
    /// Ab dann gilt die heutige Abfuhr als vorbei: Widget und Übersicht zeigen die nächste.
    public static let collectionOverMinutes = 17 * 60
    /// Ab dann erinnert der Hinweis „Tonne wieder reinholen“ (vorher ist die Tonne meist noch nicht geleert).
    public static let bringInHintMinutes = 12 * 60

    /// So lange bleibt ein heute als erledigt markierter Tag noch stehen – zum Zurücknehmen und damit ein Doppeltipp
    /// nicht gleich die nächste Abholung trifft.
    public static let undoGrace: TimeInterval = 15 * 60

    /// Der Abholtag ist für die Anzeige erledigt: vergangen, heute nach 17 Uhr, oder als erledigt markiert
    /// (schon am Vorabend – oder heute vor mehr als 15 Minuten).
    public static func isFinished(day: Date, done: Bool, doneAt: Date? = nil, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: day)
        if start < today { return true }
        guard start == today else { return false }
        if minutes(of: now, calendar: calendar) >= collectionOverMinutes { return true }
        guard done else { return false }
        guard let doneAt, doneAt >= today else { return true }
        return now >= doneAt.addingTimeInterval(undoGrace)
    }

    /// Soll am Abholtag „wieder reinholen“ angezeigt werden?
    public static func showsBringIn(day: Date, broughtIn: Bool, now: Date, fromMinutes: Int = bringInHintMinutes, calendar: Calendar = .current) -> Bool {
        guard !broughtIn, calendar.isDate(day, inSameDayAs: now) else { return false }
        return minutes(of: now, calendar: calendar) >= fromMinutes
    }

    static func minutes(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

public extension WidgetSnapshot.PickupItem {
    /// Wird nach der Abfuhr wieder hereingeholt (Tonne, nicht Sack).
    var isBin: Bool { WasteReturn.isBin(name: name, symbol: displaySymbol) }
}

public extension WidgetSnapshot {
    /// Heutige Tonnen, die wieder hereingeholt werden sollen (ab mittags, bis „Ist drin“ getippt wurde).
    func bringInDay(at date: Date = Date(), calendar: Calendar = .current) -> PickupDay? {
        guard bringInEnabled, let day = pickupDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }),
              PickupTiming.showsBringIn(day: day.date, broughtIn: day.broughtIn, now: date, fromMinutes: bringInFromMinutes, calendar: calendar) else { return nil }
        let bins = day.items.filter(\.isBin)
        guard !bins.isEmpty else { return nil }
        var copy = day
        copy.items = bins
        return copy
    }
}

public extension WidgetSnapshot {
    /// Tag für „Erledigt“ per Siri oder Kurzbefehl: heute (noch offen, vor 17 Uhr), sonst morgen – nie eine Abholung in einer Woche.
    func doneTargetDay(from date: Date = Date(), calendar: Calendar = .current) -> PickupDay? {
        let today = calendar.startOfDay(for: date)
        if let day = pickupDays.first(where: { calendar.isDate($0.date, inSameDayAs: today) }), !day.done,
           PickupTiming.minutes(of: date, calendar: calendar) < PickupTiming.collectionOverMinutes { return day }
        let tomorrow = Days.add(1, to: today, calendar: calendar)
        if let day = pickupDays.first(where: { calendar.isDate($0.date, inSameDayAs: tomorrow) }), !day.done { return day }
        return nil
    }

    /// Tag für „Erledigt zurücknehmen“: der als erledigt markierte Tag von morgen oder heute.
    func undoTargetDay(from date: Date = Date(), calendar: Calendar = .current) -> PickupDay? {
        let today = calendar.startOfDay(for: date)
        let tomorrow = Days.add(1, to: today, calendar: calendar)
        return pickupDays.first(where: { calendar.isDate($0.date, inSameDayAs: tomorrow) && $0.done })
            ?? pickupDays.first(where: { calendar.isDate($0.date, inSameDayAs: today) && $0.done })
    }
}
