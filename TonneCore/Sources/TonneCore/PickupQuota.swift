import Foundation

/// Leerungs-Statistik mit Freileerungen (Konzept 16.11.2026): Wie oft wurde eine Müllart rausgestellt, wie viele
/// inklusive Leerungen sind noch frei? Gezählt wird nur aus den Markierungen je Müllart, nicht aus dem aktuellen Plan –
/// ein verschobener oder vom Abgleich ersetzter Termin behält so seine Markierung.
///
/// Rein funktional: Termine, Markierungen, Zeitraum und Startwert hinein, Zählung, Prognose und Kosten heraus.

/// Zustand eines vergangenen Termins einer Müllart.
public enum PickupMark: String, Sendable, CaseIterable, Hashable {
    /// Rausgestellt (zählt als Leerung).
    case out
    /// Bewusst nicht rausgestellt.
    case notOut
    /// Nichts getippt – zählt nie als genutzt, wird aber eigens gezeigt.
    case open
}

/// Eine Änderung des Kontingents („ab 1. Juli 26 statt 12“). Gilt ab `from`; der bisherige Stand bleibt.
public struct QuotaChange: Codable, Hashable, Sendable {
    public var from: Date
    /// nil = ab hier ohne Kontingent.
    public var included: Int?

    public init(from: Date, included: Int?) {
        self.from = from; self.included = included
    }
}

/// Alles, was die Rechnung über eine Müllart wissen muss.
public struct QuotaInput: Sendable {
    /// Termine aus dem aktuellen Plan (auch künftige; gefiltert wird hier).
    public var scheduled: [Date]
    /// „Erledigt“ = rausgestellt.
    public var done: [Date]
    /// „Diesmal nicht“ = nicht rausgestellt.
    public var notOut: [Date]
    /// Zusatzleerungen (bestellt oder nicht im Kalender) – zählen wie ein Termin.
    public var extra: [Date]
    /// „Erledigt“ aus Widget/Watch für einen Tag mit mehreren Müllarten: zählt, steht aber zum Nachfragen bereit.
    public var bulkConfirmed: [Date]
    /// Tonnendienst: An diesen Tagen ist jemand anderes dran.
    public var offDuty: Set<Date>
    /// Auch Tage zählen, an denen jemand anderes dran ist (geteilte Tonne).
    public var countOffDuty: Bool
    /// Aktuelles Kontingent je Zeitraum (nil = ohne Kontingent).
    public var included: Int?
    /// Frühere Änderungen des Kontingents.
    public var changes: [QuotaChange]
    /// Startwert („bis 20.11. laut Angabe: 6“) und sein Stichtag.
    public var baseline: Int?
    public var baselineDate: Date?
    /// Preis je Leerung über dem Kontingent.
    public var pricePerExtra: Double?

    public init(scheduled: [Date] = [], done: [Date] = [], notOut: [Date] = [], extra: [Date] = [], bulkConfirmed: [Date] = [],
                offDuty: Set<Date> = [], countOffDuty: Bool = false, included: Int? = nil, changes: [QuotaChange] = [],
                baseline: Int? = nil, baselineDate: Date? = nil, pricePerExtra: Double? = nil) {
        self.scheduled = scheduled; self.done = done; self.notOut = notOut; self.extra = extra; self.bulkConfirmed = bulkConfirmed
        self.offDuty = offDuty; self.countOffDuty = countOffDuty; self.included = included; self.changes = changes
        self.baseline = baseline; self.baselineDate = baselineDate; self.pricePerExtra = pricePerExtra
    }
}

/// Zählzeitraum: Kalenderjahr oder ab einem Stichtag (Gebührenjahr). `end` ist der erste Tag danach.
public struct QuotaPeriod: Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) { self.start = start; self.end = end }

    public func contains(_ day: Date) -> Bool { day >= start && day < end }

    /// Nur bis einschließlich `day` – für „bis zum gleichen Tag im Vorjahr“, sonst zählen spätere Markierungen mit.
    public func through(_ day: Date, calendar: Calendar = .current) -> QuotaPeriod {
        QuotaPeriod(start: start, end: min(end, max(start, Days.add(1, to: calendar.startOfDay(for: day), calendar: calendar))))
    }

    /// „2026“ beim Kalenderjahr, sonst „2026/27“.
    public func label(calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: start)
        let year = c.year ?? 0
        if c.month == 1 && c.day == 1 { return String(year) }
        return "\(year)/\(String(format: "%02d", (year + 1) % 100))"
    }
}

/// Ein Termin in der Jahresleiste.
public struct QuotaEntry: Hashable, Sendable {
    public var date: Date
    public var mark: PickupMark
    /// Kommt noch: ab heute und ohne Markierung.
    public var upcoming: Bool
    /// Zusatzleerung statt Kalendertermin.
    public var isExtra: Bool
    /// Aus Widget/Watch pauschal bestätigt – wird einmal nachgefragt.
    public var bulkConfirmed: Bool
    /// Liegt vor dem Startwert und ist darin schon enthalten.
    public var coveredByBaseline: Bool
    /// An dem Tag ist jemand anderes dran (nur gezeigt, wenn mitgezählt wird).
    public var offDuty: Bool
}

public enum QuotaPrognosis: Hashable, Sendable {
    /// Zu wenig Erfahrung oder kein Kontingent.
    case none
    /// Bei gleichem Tempo reicht es bis zum Ende des Zeitraums.
    case lastsUntilEnd
    /// Bei gleichem Tempo ist das Kontingent etwa an diesem Termin aufgebraucht.
    case runsOut(Date)
    /// Schon aufgebraucht.
    case exhausted
}

public struct QuotaSummary: Hashable, Sendable {
    public var period: QuotaPeriod
    public var entries: [QuotaEntry]
    /// Kontingent in diesem Zeitraum (nil = ohne).
    public var included: Int?
    /// Genutzte Leerungen inklusive Startwert und Zusatzleerungen.
    public var used: Int
    /// Bis hierhin entschiedene Termine (raus oder nicht raus, ohne Startwert).
    public var decided: Int
    /// Davon rausgestellt (ohne Startwert).
    public var outCount: Int
    /// Vergangene Termine ohne Angabe.
    public var open: Int
    /// Pauschal bestätigt, wartet auf Nachfrage.
    public var bulk: Int
    /// Kommende Termine im Zeitraum (ohne „diesmal nicht“).
    public var remaining: Int
    public var prognosis: QuotaPrognosis
    /// Preis je Zusatzleerung (aus der Eingabe).
    public var pricePerExtra: Double?

    /// Noch frei (nie negativ).
    public var free: Int? { included.map { max(0, $0 - used) } }
    /// Leerungen über dem Kontingent.
    public var overBy: Int { included.map { max(0, used - $0) } ?? 0 }
    /// Kosten der Leerungen über dem Kontingent.
    public var extraCost: Double? { pricePerExtra.map { Double(overBy) * $0 } }
    /// Kontingent erreicht: jede weitere Leerung kostet extra.
    public var isExhausted: Bool { included.map { used >= $0 } ?? false }
    /// Vergangene Termine (inklusive Zusatzleerungen), über die etwas feststeht oder offen ist – Nenner für „18 von 20“.
    public var pastCount: Int { entries.filter { !$0.upcoming && !$0.coveredByBaseline }.count }
}

public enum PickupQuota {
    /// Nachtragen-Karte: offene oder pauschal bestätigte Termine der letzten so vielen Tage.
    public static let catchUpDays = 30

    // MARK: - Zeitraum

    /// Zeitraum, der `day` enthält. `anchor`: nur Tag und Monat zählen (Gebührenjahr, Einzug); nil = Kalenderjahr.
    /// Ein 29. Februar als Stichtag gilt in Nicht-Schaltjahren als 28. Februar.
    public static func period(containing day: Date, anchor: Date? = nil, calendar: Calendar = .current) -> QuotaPeriod {
        let day = calendar.startOfDay(for: day)
        var month = 1, dayOfMonth = 1
        if let anchor {
            let c = calendar.dateComponents([.month, .day], from: anchor)
            month = c.month ?? 1; dayOfMonth = c.day ?? 1
        }
        func start(in year: Int) -> Date {
            let d = month == 2 && dayOfMonth == 29 && !Days.isLeapYear(year) ? 28 : dayOfMonth
            return Days.make(year: year, month: month, day: d, calendar: calendar) ?? day
        }
        let year = calendar.component(.year, from: day)
        let thisYear = start(in: year)
        let first = thisYear <= day ? thisYear : start(in: year - 1)
        let firstYear = calendar.component(.year, from: first)
        return QuotaPeriod(start: first, end: start(in: firstYear + 1))
    }

    /// Der Zeitraum davor (Vorjahr).
    public static func previous(_ period: QuotaPeriod, anchor: Date? = nil, calendar: Calendar = .current) -> QuotaPeriod {
        self.period(containing: Days.add(-1, to: period.start, calendar: calendar), anchor: anchor, calendar: calendar)
    }

    /// Kontingent in einem Zeitraum: die letzte Änderung vor seinem Ende, sonst das aktuelle.
    /// Eine Änderung mitten im Zeitraum gilt für ihn ab sofort – die schon gezählten Leerungen bleiben stehen.
    /// Zeiträume vor der ersten Änderung haben das Kontingent, das davor galt (bei der ersten Einrichtung: keins).
    public static func included(in period: QuotaPeriod, current: Int?, changes: [QuotaChange]) -> Int? {
        guard !changes.isEmpty else { return current }
        return changes.sorted { $0.from < $1.from }.last { $0.from < period.end }?.included
    }

    /// Neue Änderung eintragen: Am selben Tag ersetzt sie die vorige.
    public static func recording(_ included: Int?, at day: Date, into changes: [QuotaChange], calendar: Calendar = .current) -> [QuotaChange] {
        let day = calendar.startOfDay(for: day)
        var result = changes.filter { calendar.startOfDay(for: $0.from) != day }
        result.append(QuotaChange(from: day, included: included))
        return result.sorted { $0.from < $1.from }
    }

    // MARK: - Rechnung

    public static func summary(_ input: QuotaInput, period: QuotaPeriod, today: Date, calendar: Calendar = .current) -> QuotaSummary {
        let today = calendar.startOfDay(for: today)
        func days(_ dates: [Date]) -> Set<Date> { Set(dates.map { calendar.startOfDay(for: $0) }.filter(period.contains)) }
        let done = days(input.done), notOut = days(input.notOut), extra = days(input.extra), bulk = days(input.bulkConfirmed)
        let offDuty = Set(input.offDuty.map { calendar.startOfDay(for: $0) })
        let baselineDay = input.baseline != nil ? input.baselineDate.map { calendar.startOfDay(for: $0) }.flatMap { period.contains($0) ? $0 : nil } : nil
        // Plan: ohne Tage, an denen jemand anderes dran ist (außer es wird mitgezählt)
        let planned = days(input.scheduled).filter { input.countOffDuty || !offDuty.contains($0) }
        // Markierungen hängen am Datum: auch Termine, die nicht mehr im Plan stehen, bleiben drin
        let all = planned.union(done).union(notOut).union(extra).sorted()

        var entries: [QuotaEntry] = []
        for day in all {
            let mark: PickupMark = done.contains(day) || extra.contains(day) ? .out : notOut.contains(day) ? .notOut : .open
            // Offen und ab heute: kommt noch. Eine Markierung zählt sofort – auch „Erledigt“ am Vorabend für morgen.
            let upcoming = mark == .open && day >= today
            let covered = baselineDay.map { day <= $0 } ?? false
            entries.append(QuotaEntry(date: day, mark: mark, upcoming: upcoming, isExtra: extra.contains(day) && !planned.contains(day),
                                      bulkConfirmed: mark == .out && bulk.contains(day) && !covered, coveredByBaseline: covered,
                                      offDuty: offDuty.contains(day)))
        }
        let counted = entries.filter { !$0.upcoming && !$0.coveredByBaseline }
        let outCount = counted.filter { $0.mark == .out }.count
        let decided = counted.filter { $0.mark != .open }.count
        let used = (baselineDay != nil ? max(0, input.baseline ?? 0) : 0) + outCount
        let future = entries.filter { $0.upcoming && $0.mark != .notOut }
        let included = self.included(in: period, current: input.included, changes: input.changes)

        var prognosis = QuotaPrognosis.none
        if let included {
            if used >= included {
                prognosis = .exhausted
            } else if decided >= 2, outCount > 0 {
                // Tempo je Termin: Anteil der bisher rausgestellten Termine
                let needed = ((included - used) * decided + outCount - 1) / outCount
                prognosis = needed <= future.count ? .runsOut(future[needed - 1].date) : .lastsUntilEnd
            } else if decided >= 2 {
                prognosis = .lastsUntilEnd
            }
        }
        return QuotaSummary(period: period, entries: entries, included: included, used: used, decided: decided, outCount: outCount,
                            open: counted.filter { $0.mark == .open }.count, bulk: counted.filter(\.bulkConfirmed).count,
                            remaining: future.count, prognosis: prognosis, pricePerExtra: input.pricePerExtra)
    }

    /// Termine für die Nachtragen-Karte: offen oder pauschal bestätigt, aus den letzten 30 Tagen (vor heute).
    /// Nur bei gezählten Müllarten (mit Kontingent).
    public static func catchUp(_ input: QuotaInput, today: Date, calendar: Calendar = .current) -> [QuotaEntry] {
        guard input.included != nil else { return [] }
        let today = calendar.startOfDay(for: today)
        // Fenster schließt heute ein: Ein Startwert von heute (Einrichtungstag) deckt sonst nichts ab
        let window = QuotaPeriod(start: Days.add(-catchUpDays, to: today, calendar: calendar), end: Days.add(1, to: today, calendar: calendar))
        return summary(input, period: window, today: today, calendar: calendar).entries
            .filter { $0.date < today && !$0.upcoming && !$0.coveredByBaseline && ($0.mark == .open || $0.bulkConfirmed) }
    }

    // MARK: - Bestätigen je Müllart

    /// Braucht ein „Erledigt“ für diesen Tag eine Wahl je Müllart? Nur wenn eine gezählte Müllart dabei ist
    /// und noch mindestens eine weitere – sonst bleibt der schnelle Ein-Tipp wie bisher.
    public static func needsChoice(counted: [Bool]) -> Bool {
        counted.count > 1 && counted.contains(true)
    }

    /// Woher ein „Erledigt“ kommt.
    public enum Confirmation: Hashable, Sendable {
        /// Ein Tipp ohne Wahl (Widget, Watch, Live-Aktivität, Kurzbefehl, offline nachgeholt).
        case blanket
        /// Ausdrücklich gewählt (Blatt in der App, „Alles raus“ / „Ohne …“ in der Mitteilung): diese blieben drin.
        case chosen(left: Set<String>)
    }

    /// Ergebnis je Müllart des Tages.
    public struct Resolution: Hashable, Sendable {
        public var out: Set<String>
        public var notOut: Set<String>
        /// Diese gezählten Müllarten sind nur pauschal bestätigt und werden nachgefragt.
        public var bulk: Set<String>
    }

    /// Löst ein „Erledigt“ für einen Tag auf. `types`: die Müllarten, die an dem Tag rausgehen (ID, gezählt?).
    public static func resolve(_ confirmation: Confirmation, types: [(id: String, counted: Bool)]) -> Resolution {
        switch confirmation {
        case .blanket:
            let ids = Set(types.map(\.id))
            let bulk = needsChoice(counted: types.map(\.counted)) ? Set(types.filter(\.counted).map(\.id)) : []
            return Resolution(out: ids, notOut: [], bulk: bulk)
        case .chosen(let left):
            let ids = Set(types.map(\.id))
            return Resolution(out: ids.subtracting(left), notOut: ids.intersection(left), bulk: [])
        }
    }

    // MARK: - Texte

    /// „noch 5 von 12 frei“ bzw. „12 von 12 genutzt“ / „2 über dem Kontingent“ – nil ohne Kontingent.
    public static func freeLine(_ summary: QuotaSummary) -> String? {
        guard let included = summary.included else { return nil }
        if summary.overBy > 0 {
            return L10n.t("\(summary.overBy) über dem Kontingent von \(included)", "\(summary.overBy) over the \(included) included")
        }
        if let free = summary.free, free == 0 {
            return L10n.t("alle \(included) genutzt", "all \(included) used")
        }
        return L10n.t("noch \(summary.free ?? 0) von \(included) frei", "\(summary.free ?? 0) of \(included) left")
    }

    /// `freeLine` je Abholtag, im Zeitraum des Abholtags (nicht im heutigen): Am 30.12. mit 12 von 12 genutzt
    /// zeigt die Abholung am 2.1. „noch 12 von 12 frei“. Je Zeitraum wird `input` nur einmal gerechnet.
    public static func freeLines(anchor: Date?, today: Date, calendar: Calendar = .current,
                                 input: @escaping (QuotaPeriod) -> QuotaInput) -> (Date) -> String? {
        var cache: [Date: String?] = [:]
        return { day in
            let period = period(containing: day, anchor: anchor, calendar: calendar)
            if let hit = cache[period.start] { return hit }
            let line = freeLine(summary(input(period), period: period, today: today, calendar: calendar))
            cache[period.start] = line
            return line
        }
    }

    /// „7 von 12“ für den Ring bzw. „18 von 20 Terminen rausgestellt“ ohne Kontingent.
    public static func headline(_ summary: QuotaSummary) -> String {
        if let included = summary.included {
            return L10n.t("\(summary.used) von \(included)", "\(summary.used) of \(included)")
        }
        if summary.pastCount == 0 { return L10n.t("Noch kein Termin vorbei", "No collection yet") }
        return L10n.t("\(summary.outCount) von \(summary.pastCount) Terminen rausgestellt", "\(summary.outCount) of \(summary.pastCount) collections put out")
    }

    // MARK: - CSV

    public struct CSVRow: Hashable, Sendable {
        public var date: Date
        public var location: String
        public var wasteType: String
        public var mark: PickupMark
        public var isExtra: Bool

        public init(date: Date, location: String, wasteType: String, mark: PickupMark, isExtra: Bool = false) {
            self.date = date; self.location = location; self.wasteType = wasteType; self.mark = mark; self.isExtra = isExtra
        }
    }

    /// `Datum;Standort;Abfallart;Zustand;Zusatzleerung` – Semikolon wie im Import, Felder mit Trennzeichen in Anführungszeichen.
    public static func csv(_ rows: [CSVRow], calendar: Calendar = .current) -> String {
        func field(_ text: String) -> String {
            text.contains(";") || text.contains("\"") || text.contains("\n") ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        func state(_ mark: PickupMark) -> String {
            switch mark {
            case .out: return L10n.t("raus", "out")
            case .notOut: return L10n.t("nicht raus", "not out")
            case .open: return L10n.t("offen", "open")
            }
        }
        var lines = [L10n.t("Datum;Standort;Abfallart;Zustand;Zusatzleerung", "Date;Location;Waste type;State;Extra collection")]
        for row in rows.sorted(by: { ($0.date, $0.location, $0.wasteType) < ($1.date, $1.location, $1.wasteType) }) {
            lines.append([Days.iso(row.date, calendar: calendar), field(row.location), field(row.wasteType), state(row.mark),
                          row.isExtra ? L10n.t("ja", "yes") : ""].joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Abgleich

    /// Ersetzt ein Abgleich die Termine, bleiben vergangene stehen: Liefert die Quelle nur noch künftige Termine,
    /// verschwänden sonst unmarkierte Termine still aus „offen“ und dem Nenner der Statistik.
    public static func pastDatesKeptOnSync(old: [Date], today: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: today)
        return Array(Set(old.map { calendar.startOfDay(for: $0) }.filter { $0 < today })).sorted()
    }

    /// Markierungen und Einzeltermine, die älter sind, braucht auch die Vorjahres-Ansicht nicht mehr.
    public static let keepDays = 800
}
