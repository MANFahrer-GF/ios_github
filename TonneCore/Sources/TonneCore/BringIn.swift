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
        if lower.contains("container") && !lower.contains("tonne") {
            let sized = lower.range(of: #"\d+[.,]?\d*\s*(ltr|liter|l|m³|m3|cbm)(?![a-zäöü])"#, options: .regularExpression) != nil
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

/// Wie man mit einer Abfuhr umgeht – bestimmt die Worte in Erinnerungen, Widgets, Live-Aktivität und Siri.
public enum WasteHandling: Equatable {
    /// Tonne: rausstellen, steht draußen, nach der Abfuhr wieder reinholen.
    case bin
    /// Kein Behälter, der zurückkommt – Sack, Sperrmüll, Grünschnitt, Weihnachtsbaum: bereitstellen.
    case setOut
    /// Nichts rausstellen, sondern hinbringen – Schadstoffmobil, Problemmüll, Annahmestellen.
    case bringTo

    /// Art einer Müllart. „Tonne“ entscheidet `WasteReturn.isBin` (eine Quelle für beides, damit Wortwahl und
    /// „wieder reinholen“ nie auseinanderlaufen).
    /// `category`: die gespeicherte Kategorie der Müllart – zählt vor dem Namen (umbenanntes „Schadstoffmobil“ bleibt Hinbringen).
    public static func of(name: String, symbol: String? = nil, category: WasteCategory? = nil) -> WasteHandling {
        let lower = name.lowercased()
        if category == .hazardous || WasteCategory.classify(name) == .hazardous || bringToWords.contains(where: { lower.contains($0) }) || isAcceptance(lower) { return .bringTo }
        return WasteReturn.isBin(name: name, symbol: symbol) ? .bin : .setOut
    }

    private static let bringToWords = ["schadstoff", "problemmüll", "problemmuell", "problemabfall", "problemstoff", "sondermüll",
                                       "sondermuell", "sonderabfall", "giftmobil", "umweltmobil", "wertstoffhof", "recyclinghof",
                                       "annahmestelle", "sammelstelle", "sammelplatz"]

    /// „Grüngut-Annahme“, „Elektroschrottannahme“, „Annahme“ – nicht „Annahmeschluss“, „Annahmetonne“ oder „Sperrmüll nach Annahme“.
    private static func isAcceptance(_ lower: String) -> Bool {
        guard !lower.contains("tonne"), !lower.contains("nach annahme") else { return false }
        return lower.split(whereSeparator: { !$0.isLetter }).contains { $0.hasSuffix("annahme") }
    }
}

/// Worte für einen Abholtag mit gemischten Müllarten – dieselben Sätze in Mitteilungen, Widgets und Live-Aktivität.
public struct PickupWording {
    public struct Item {
        public var name: String
        public var handling: WasteHandling
        /// Hinweis des Entsorgers, z. B. „08:00–12:00, Am Grauen Stein 6“ – nur beim Hinbringen gezeigt.
        public var note: String?
        public init(name: String, handling: WasteHandling, note: String? = nil) {
            self.name = name; self.handling = handling
            self.note = handling == .bringTo ? note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) } : nil
        }
    }

    /// Müllarten des Tages, in der Reihenfolge der Anzeige.
    public let items: [Item]

    public init(_ items: [Item]) { self.items = items }

    /// Aus dem Widget-Schnappschuss – mit der von der App bestimmten Art, sonst aus dem Namen.
    public init(day: WidgetSnapshot.PickupDay?) {
        items = (day?.items ?? []).map { item in
            let byName = WasteHandling.of(name: item.name, symbol: item.displaySymbol)
            switch item.dropOff {
            case true?: return Item(name: item.name, handling: .bringTo)
            case false?: return Item(name: item.name, handling: byName == .bringTo ? .setOut : byName)
            case nil: return Item(name: item.name, handling: byName)   // älterer Schnappschuss
            }
        }
    }

    /// Aus Namen und Symbolen (Live-Aktivität).
    public init(names: [String], symbols: [String?]) {
        items = names.enumerated().map { index, name in Item(name: name, handling: WasteHandling.of(name: name, symbol: index < symbols.count ? symbols[index] : nil)) }
    }

    /// Was rausgestellt wird (Tonnen und Bereitzustellendes) und was hingebracht wird – Letzteres mit Zeit/Ort, falls bekannt.
    public var outNames: [String] { items.filter { $0.handling != .bringTo }.map(\.name) }
    public var bringNames: [String] { items.filter { $0.handling == .bringTo }.map { item in item.note.map { "\(item.name) (\($0))" } ?? item.name } }
    /// Zeit/Ort des einzigen Hinbringens, falls bekannt.
    public var bringNote: String? { items.filter { $0.handling == .bringTo }.count == 1 ? items.first { $0.handling == .bringTo }?.note : nil }
    public var allBins: Bool { !items.isEmpty && items.allSatisfy { $0.handling == .bin } }
    /// Nur Hinbringen – dann gibt es nichts rauszustellen (keine Spät-Erinnerung, keine Live-Aktivität).
    public var onlyBringTo: Bool { !items.isEmpty && outNames.isEmpty }

    /// Kurzer Hinweis für den Vorabend („abends rausstellen“) bzw. den Abholtag.
    public func hint(daysUntil: Int, done: Bool) -> String {
        let mixed = !onlyBringTo && !bringNames.isEmpty
        if done { return onlyBringTo || mixed ? L10n.t("erledigt 👍", "done 👍") : L10n.t("steht draußen 👍", "already out 👍") }
        switch daysUntil {
        case 0: return onlyBringTo ? L10n.t("heute hinbringen", "drop off today") : mixed ? L10n.t("Abfuhr und hinbringen", "pickup and drop-off") : L10n.t("wird heute abgeholt", "collected today")
        case 1: return onlyBringTo ? L10n.t("morgen hinbringen", "drop off tomorrow") : mixed ? L10n.t("rausstellen und hinbringen", "put out and drop off") : L10n.t("abends rausstellen", "put out tonight")
        default: return onlyBringTo ? L10n.t("nächster Termin", "next date") : L10n.t("nächste Abholung", "next pickup")
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
    var isBin: Bool { dropOff != true && WasteReturn.isBin(name: name, symbol: displaySymbol) }
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
        if let day = pickupDays.first(where: { calendar.isDate($0.date, inSameDayAs: today) }),
           PickupTiming.minutes(of: date, calendar: calendar) < PickupTiming.collectionOverMinutes {
            if !day.done { return day }
            // Gerade erst erledigt (Doppeltipp, zweimal gesagt): nicht auf morgen springen
            if !PickupTiming.isFinished(day: day.date, done: true, doneAt: day.doneAt, now: date, calendar: calendar) { return nil }
        }
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
