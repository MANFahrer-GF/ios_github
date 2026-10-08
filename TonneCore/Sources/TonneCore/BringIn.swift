import Foundation

/// Tonnen werden nach der Abfuhr wieder hereingeholt – Säcke, Bündel, Grünschnitt oder Sperrmüll nicht.
public enum WasteReturn {
    /// Wörter, bei denen nichts zurückgeholt wird (Sack, Bündel, Sammlungen ohne eigenen Behälter).
    private static let neverReturned = ["sack", "säcke", "saecke", "beutel", "bündel", "buendel", "sperr", "schadstoff", "problem",
                                        "grünschnitt", "gruenschnitt", "strauch", "baum", "laub", "container", "mobil", "elektro",
                                        "schrott", "altkleider", "kleider"]
    /// Wörter, die eindeutig einen Behälter meinen.
    private static let bins = ["tonne", "behälter", "behaelter", "mülleimer", "muelleimer", "bin"]

    /// Ob diese Abfallart nach der Abfuhr wieder hereingeholt werden muss.
    /// `symbol` ist das angezeigte Symbol: Wer „Sack“ oder „Tonne“ ausdrücklich gewählt hat, bekommt genau das.
    public static func isBin(name: String, symbol: String? = nil) -> Bool {
        if symbol == "tt.sack" { return false }
        let lower = name.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if neverReturned.contains(where: { lower.contains($0) }) && !lower.contains("tonne") { return false }
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

    /// Der Abholtag ist für die Anzeige erledigt: vergangen, heute schon als erledigt markiert oder heute nach 17 Uhr.
    public static func isFinished(day: Date, done: Bool, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: day)
        if start < today { return true }
        guard start == today else { return false }
        return done || minutes(of: now, calendar: calendar) >= collectionOverMinutes
    }

    /// Soll am Abholtag „wieder reinholen“ angezeigt werden?
    public static func showsBringIn(day: Date, broughtIn: Bool, now: Date, calendar: Calendar = .current) -> Bool {
        guard !broughtIn, calendar.isDate(day, inSameDayAs: now) else { return false }
        return minutes(of: now, calendar: calendar) >= bringInHintMinutes
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
        guard let day = pickupDays.first(where: { calendar.isDate($0.date, inSameDayAs: date) }),
              PickupTiming.showsBringIn(day: day.date, broughtIn: day.broughtIn, now: date, calendar: calendar) else { return nil }
        let bins = day.items.filter(\.isBin)
        guard !bins.isEmpty else { return nil }
        var copy = day
        copy.items = bins
        return copy
    }
}
