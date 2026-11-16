import XCTest
@testable import TonneCore

/// Gesundheitsprüfung aller Portale gegen das echte Netz: spielt das Einrichten wie ein Nutzer bis zu den Terminen durch und
/// bewertet, ob die Antwort plausibel ist. Ergebnis je Zeile als JSON in `TONNE_HEALTH`, daraus baut `tools/health/report.py`
/// die Bericht-Seite. Start über `tools/health/pruefen.sh` (Thomas, 12.11.2026: „Das ist eine Blackbox für mich“).
///
/// - `TONNE_HEALTH=<Datei>`: Ausgabe (JSON-Zeilen). Schon vorhandene Zeilen werden übersprungen – ein abgebrochener Lauf macht weiter.
/// - `TONNE_HEALTH_MODE=entsorger|gemeinden`: je Katalogeintrag eine Musteradresse, oder je Gemeinde mit ihrem Entsorger.
/// - `TONNE_HEALTH_ONLY=<Text>`: nur Einträge/Gemeinden, deren Name oder Kennung den Text enthält.
/// - `TONNE_HEALTH_PARALLEL=<Zahl>`: gleichzeitige Abfragen (Vorgabe 6; Müllmax läuft immer einzeln, es sperrt sonst 24 h).
final class PortalHealthLiveTests: XCTestCase {
    struct Job: @unchecked Sendable {
        let key: String
        let entry: CatalogEntry
        let district: String?
        let place: String?
    }

    struct Result: Codable {
        var key: String
        var mode: String
        var title: String
        var kind: String
        var serviceKey: String
        var website: String?
        var district: String?
        var place: String?
        var status = "ok"
        var reasons: [String] = []
        var path: [String] = []
        var placeFound: Bool?
        var future = 0
        var types: [String] = []
        var next: String?
        var last: String?
        var seconds = 0.0
        var error: String?
    }

    /// Freie Hausnummern der Reihe nach, wie ein Nutzer mit seiner echten Nummer.
    static let houseNumbers = ["1", "2", "3", "5", "10", "20"]
    private static let probes = ["Haupt", "Bahnhof", "Kirch", "Schul", "Garten", "Berg", "Ring", "Weg", "Str", "Dorf", "Markt"]
    private static let timeout: UInt64 = 120

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func testPortalHealth() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["TONNE_HEALTH"], !out.isEmpty else { throw XCTSkip("TONNE_HEALTH nicht gesetzt") }
        L10n.forcedLanguage = "de"
        let mode = env["TONNE_HEALTH_MODE"] ?? "entsorger"
        let only = env["TONNE_HEALTH_ONLY"].flatMap { $0.isEmpty ? nil : $0.lowercased() }
        let parallel = max(1, Int(env["TONNE_HEALTH_PARALLEL"] ?? "") ?? 6)

        var jobs = mode == "gemeinden" ? Self.placeJobs() : ProviderCatalog.entries.map { Job(key: "E|\($0.id)", entry: $0, district: nil, place: nil) }
        if let only {
            jobs = jobs.filter { "\($0.key) \($0.entry.title) \($0.place ?? "")".lowercased().contains(only) }
        }
        let done = Self.doneKeys(out)
        jobs = jobs.filter { !done.contains($0.key) }
        print("HEALTH: \(jobs.count) offen (\(done.count) schon geprüft), Modus \(mode), \(parallel) parallel")

        let writer = try LineWriter(path: out)
        let muellmax = jobs.filter { $0.entry.kind == .muellmax }
        let others = jobs.filter { $0.entry.kind != .muellmax }
        let calendar = self.calendar
        await withTaskGroup(of: Void.self) { group in
            // Müllmax als eine eigene, langsame Spur
            group.addTask {
                for job in muellmax { await writer.write(await Self.check(job, mode: mode, calendar: calendar)) }
            }
            var iterator = others.makeIterator()
            for _ in 0..<parallel {
                guard let job = iterator.next() else { break }
                group.addTask { await writer.write(await Self.check(job, mode: mode, calendar: calendar)) }
            }
            while await group.next() != nil {
                if let job = iterator.next() {
                    group.addTask { await writer.write(await Self.check(job, mode: mode, calendar: calendar)) }
                }
            }
        }
        print("HEALTH: fertig, \(await writer.count) Zeilen geschrieben")
    }

    // MARK: Aufträge

    /// Je Gemeinde („Landkreis|Gemeinde“) ein Auftrag pro zuständigem Katalogeintrag.
    static func placeJobs() -> [Job] {
        let byID = Dictionary(ProviderCatalog.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return PlaceMapIndex.entryIDs.sorted { $0.key < $1.key }.flatMap { key, ids -> [Job] in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return [] }
            return ids.compactMap { id in byID[id].map { Job(key: "G|\(key)|\(id)", entry: $0, district: parts[0], place: parts[1]) } }
        }
    }

    static func doneKeys(_ path: String) -> Set<String> {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").compactMap { line in
            (try? JSONDecoder().decode(Result.self, from: Data(line.utf8)))?.key
        })
    }

    // MARK: Prüfung

    static func check(_ job: Job, mode: String, calendar: Calendar) async -> Result {
        let started = Date()
        var result = Result(key: job.key, mode: mode, title: job.entry.title, kind: job.entry.kind.rawValue, serviceKey: job.entry.serviceKey,
                            website: job.entry.website, district: job.district, place: job.place)
        // Bis zu drei Adressen: Eine einzelne Straße ohne Behälter oder ohne Hausnummer 1 ist kein Portalfehler
        var failures: [String] = []
        for variant in 0..<3 {
            var attempt = result
            do {
                var (selections, placeFound, typedNumber) = try await withTimeout(timeout) { try await walk(job, variant: variant, calendar: calendar) }
                // nil: Der Eintrag hat keinen Ortsschritt (eigener Ortseintrag, Jahresdaten, Straßenfeld) – nichts zu finden
                attempt.placeFound = job.place == nil ? nil : placeFound
                let provider = ProviderFactory.make(kind: job.entry.kind, serviceKey: job.entry.serviceKey)
                // Freie Hausnummer: Manche Portale kennen „1“ in der Straße nicht und liefern dann nur Sammeltermine
                // (Cochem-Zell). Wie ein Nutzer mit seiner echten Nummer: weitere Nummern derselben Straße versuchen.
                // `walk` hat schon die erste Nummer gesucht, die das Portal kennt (München AWM): ab dieser weiter
                let numbers = typedNumber ? Array(houseNumbers.drop(while: { $0 != selections.last?.id })) : [""]
                var lastError: Error?
                for (index, number) in numbers.enumerated() {
                    if !number.isEmpty { selections[selections.count - 1] = SelectionOption(id: number, title: number) }
                    let current = selections
                    do {
                        let pickups = try await withTimeout(timeout) { try await provider.pickups(for: current, calendar: calendar) }
                        var probe = attempt
                        judge(pickups, into: &probe, calendar: calendar)
                        if probe.status != "fehler" || index == numbers.count - 1 { attempt = probe; lastError = nil; break }
                    } catch {
                        lastError = error
                        // Zeitüberschreitung, Sperre oder Serverfehler: eine andere Nummer hilft nicht und verschärft nur die Drosselung
                        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                        if error is TimeoutError || message.contains("HTTP 4") || message.contains("HTTP 5") { break }
                    }
                }
                attempt.path = selections.map(\.title)
                if let lastError { throw lastError }
                if attempt.status != "fehler" || variant == 2 {
                    if !failures.isEmpty { attempt.reasons.append("erst mit Adresse \(variant + 1) von 3 (vorher: \(failures.joined(separator: " | ")))") }
                    result = attempt
                    break
                }
                failures.append(attempt.reasons.joined(separator: ", "))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                failures.append(message)
                attempt.status = "fehler"
                attempt.error = message
                attempt.reasons.append(error is TimeoutError ? "Portal antwortet nicht (über \(timeout) s)" : "Abfrage gescheitert")
                // Zeitüberschreitung oder Serverfehler: eine andere Adresse hilft nicht
                if error is TimeoutError || message.contains("HTTP 5") || message.contains("HTTP 4") || variant == 2 {
                    if failures.count > 1 { attempt.reasons.append("auch mit \(failures.count) Adressen") }
                    result = attempt
                    break
                }
            }
        }
        if job.place != nil, result.placeFound == false, result.status == "ok" {
            result.status = "warnung"
            result.reasons.append("Gemeinde nicht in der Auswahl gefunden, Musteradresse geprüft")
        }
        result.seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
        return result
    }

    /// Wie ein Nutzer: in Listen die Gemeinde wählen (falls gesucht), sonst den mittleren Eintrag; Suchfelder mit häufigen
    /// Straßenwörtern sondieren; freie Hausnummer „1“.
    /// `variant`: 0 = mittlerer Eintrag, 1 = bei einem Drittel, 2 = bei zwei Dritteln (für den zweiten und dritten Versuch).
    /// Drittes Ergebnis: Der letzte Schritt war eine frei eingegebene Hausnummer (siehe `check`).
    static func walk(_ job: Job, variant: Int = 0, calendar: Calendar, provider: WasteProvider? = nil) async throws -> ([SelectionOption], Bool?, Bool) {
        let provider = provider ?? ProviderFactory.make(kind: job.entry.kind, serviceKey: job.entry.serviceKey)
        var selections: [SelectionOption] = []
        var placeFound = false, sawPlaceStep = false
        var numberIndex: Int?
        let wanted = job.place.map(searchName)
        // `district` ist optional: nicht direkt einsetzen, sonst lautet der Schlüssel „Optional(…)|Gemeinde“ und trifft nie
        let localities = job.district.flatMap { district in job.place.flatMap { Self.localities["\(district)|\($0)"] } } ?? []
        walking: while true {
            let step: SelectionStep
            do {
                guard let next = try await provider.nextStep(after: selections) else { break walking }
                step = next
            } catch let error as ProviderError where numberIndex == selections.count - 1 {
                // Das Portal prüft die Nummer schon im nächsten Schritt (München AWM: „Adresse konnte nicht gefunden
                // werden“ für Kronwinkler Str. 1, 2, 3, 5; 10 geht): die nächste Nummer versuchen
                guard let index = houseNumbers.firstIndex(of: selections[selections.count - 1].id), index + 1 < houseNumbers.count else { throw error }
                selections[selections.count - 1] = SelectionOption(id: houseNumbers[index + 1], title: houseNumbers[index + 1])
                continue
            }
            if selections.count > 7 { throw WalkError("mehr als 7 Schritte") }
            if step.input == .text {
                if step.title == SelectionStep.houseNumberTitle {
                    numberIndex = selections.count
                    selections.append(SelectionOption(id: houseNumbers[0], title: houseNumbers[0])); continue
                }
                // Ein Ortsfeld mit dem Gemeindenamen füllen, ein Straßenfeld sondieren
                // Je Versuch andere Suchwörter zuerst: „Haupt“ traf in Bremerhaven nur „Auswanderer Haus“ (ohne Plan)
                var texts = Array(probes.dropFirst(variant * 2) + probes.prefix(variant * 2))
                if let wanted, !placeFound, step.title == SelectionStep.cityTitle { texts = [wanted] + probes; sawPlaceStep = true }
                var found: [SelectionOption] = []
                for text in texts {
                    let probe = selections + [SelectionOption(id: text, title: text)]
                    let next: SelectionStep?
                    do { next = try await provider.nextStep(after: probe) } catch { continue }
                    // Fertig nach dem Suchwort: Müllmax springt bei genau einem Straßentreffer direkt zur Formatwahl
                    // (Allendorf (Lumda), „Garten“ → 122 Termine) – wie ein Nutzer das Suchwort übernehmen
                    guard let next else {
                        selections = probe
                        if text == wanted { placeFound = true }
                        break walking
                    }
                    if next.input == .list, !next.options.isEmpty {
                        selections = probe; found = next.options
                        if text == wanted { placeFound = true }
                        break
                    }
                }
                guard !found.isEmpty else { throw WalkError("Suchfeld „\(step.title)“ findet nichts (Suchwörter: \(texts.prefix(4).joined(separator: ", ")) …)") }
                selections.append(pick(found, wanted: placeFound ? nil : wanted, variant: variant, found: &placeFound, localities: localities))
                continue
            }
            // Leere erste Liste: Lobbe antwortet nach ein paar Gemeinden in Folge mit „[]“ auf die Bundesländer, nach einer
            // Pause wieder voll (Gemeinde-Prüfung 16.11.2026: 4 ok, 38 leer, 4 ok …; einzeln Vöhl 66 Termine).
            guard !step.options.isEmpty else {
                throw WalkError(selections.isEmpty ? "leere erste Auswahl bei „\(step.title)“ (Abfragegrenze)" : "leere Auswahl bei „\(step.title)“")
            }
            if step.isPlaceStep { sawPlaceStep = true }
            // Verbandsgemeinde zuerst (A.R.T. Trier, AWB Altenkirchen, AWB Bad Dürkheim): die Ortsgemeinde steht erst eine Ebene
            // tiefer. Wie ein Nutzer, der seine VG kennt: die VG wählen, unter der die Gemeinde steht. Ebenso ein erster
            // Schritt „Bundesland“ (Lobbe: Battenberg (Eder) steht unter Hessen).
            if let wanted, !placeFound, step.isPlaceStep || selections.isEmpty, step.options.count <= 40,
               !step.options.contains(where: { matches($0, wanted) }),
               let parent = try await parentOption(of: wanted, in: step.options, after: selections, provider: provider, localities: localities) {
                selections.append(parent); continue
            }
            selections.append(pick(step.options, wanted: placeFound ? nil : wanted, variant: variant, found: &placeFound,
                                   localities: placeFound ? [] : localities))
        }
        return (selections, sawPlaceStep || placeFound ? placeFound : nil, numberIndex == selections.count - 1)
    }

    /// Ortsteile je Gemeinde („Landkreis|Gemeinde“ → Namen) aus `CatalogLocalities`.
    static let localities: [String: [String]] = {
        var out: [String: [String]] = [:]
        for line in CatalogLocalities.localities.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            out["\(parts[0])|\(parts[1])"] = parts[2].split(separator: ",").map(String.init)
        }
        return out
    }()

    /// Gemeinde bevorzugt (genau, dann Suchtreffer), sonst der mittlere Eintrag.
    static func pick(_ options: [SelectionOption], wanted: String?, variant: Int = 0, found: inout Bool, localities: [String] = []) -> SelectionOption {
        if let wanted {
            // 2. und 3. Versuch: ein Ortsteil des Orts (Zell (Mosel): echte Straßen nur unter „Zell (Mosel) – Zell-Stadt“,
            // Aurich: unter „Aurich / Aurich-Stadt“; der bloße Ort hat dort nur Platzhalter wie „dummystrasse“)
            let districts = options.filter { ($0.title.contains(" – ") || $0.title.contains(" / ")) && $0.title.lowercased().hasPrefix(wanted.lowercased() + " ") }
            if variant > 0, !districts.isEmpty { found = true; return districts[min(districts.count - 1, (variant - 1) * districts.count / 2)] }
            // Genauer Name vor Zusatz-/Kerntreffer („Mühlheim am Main“ statt „Mühlheim“), mehrdeutige Kerne gar nicht
            // („Neustadt am Kulm“ und „Neustadt/WN“ für Neustadt a.d.Waldnaab) – wie die Vorauswahl der App.
            let hits = options.filter { matches($0, wanted) }
            if let exact = hits.first(where: { ProviderCatalog.fold(searchName($0.title)) == ProviderCatalog.fold(wanted) }) ?? (hits.count == 1 ? hits[0] : nil) {
                found = true; return exact
            }
            if let hit = OptionSearch(options).filter(query: wanted).first { found = true; return hit }
            // Doppelname: KAEV führt „Krausnick-Groß Wasserburg“ als „Krausnick“ und „Groß Wasserburg“
            if let part = options.first(where: { wanted.lowercased().hasPrefix(searchName($0.title).lowercased() + "-") }) { found = true; return part }
            // Liste der Ortsteile (Landkreis Göttingen: „Klein Wiershausen“ statt „Gleichen“): wie ein Nutzer seinen Ortsteil wählen
            let folded = Set(localities.map(ProviderCatalog.fold))
            let parts = options.filter { folded.contains(ProviderCatalog.fold(searchName($0.title))) }
            if !parts.isEmpty { found = true; return parts[min(parts.count - 1, variant * parts.count / 3)] }
        }
        switch variant {
        case 1: return options[options.count / 3]
        case 2: return options[min(options.count - 1, options.count * 2 / 3)]
        default: return options[options.count / 2]
        }
    }

    /// Option ist die gesuchte Gemeinde: gleicher Name, oder der amtliche Name hängt nur einen Zusatz an
    /// („Graach an der Mosel“ ↔ Portal „Graach“, „Kirchheim an der Weinstraße“ ↔ „Kirchheim“).
    static func matches(_ option: SelectionOption, _ wanted: String) -> Bool {
        let title = searchName(option.title).lowercased(), plain = wanted.lowercased()
        // Kernname wie die Vorauswahl der App: „Gemeinde Saal“ ↔ „Saal a.d.Donau“, „Brünn“ ↔ „Brünn/Thür.“
        return title == plain || plain.hasPrefix(title + " ") || SelectionStep.placeCore(option.title) == SelectionStep.placeCore(wanted)
    }

    /// Die Option des Ortsschritts, unter der die gesuchte Gemeinde eine Ebene tiefer steht (nil, wenn keine eindeutig passt).
    /// Steht die Gemeinde selbst nicht darunter, zählen ihre Ortsteile: Burgenlandkreis „VerbG An der Finne“ führt
    /// Finneland als „Borgau“, „Kahlwinkel“ …, Gifhorn „Papenteich“ Schwülper als „Groß Schwülper“ (Punkt 6, 16.11.2026).
    /// Bei mehreren Kandidaten gewinnt die Option mit den meisten Treffern (Gleina: Unstruttal 4, Elsteraue nur 1).
    static func parentOption(of wanted: String, in options: [SelectionOption], after selections: [SelectionOption],
                             provider: any WasteProvider, localities: [String] = []) async throws -> SelectionOption? {
        let folded = Set(localities.map(ProviderCatalog.fold))
        var named: [SelectionOption] = [], scored: [(option: SelectionOption, score: Int)] = []
        for option in options {
            guard let next = try? await provider.nextStep(after: selections + [option]), next.input == .list else { continue }
            if next.options.contains(where: { matches($0, wanted) }) { named.append(option) }
            let score = next.options.filter { matches($0, wanted) || folded.contains(ProviderCatalog.fold(searchName($0.title))) }.count
            if score > 0 { scored.append((option, score)) }
        }
        if named.count == 1 { return named[0] }
        // Mehrdeutiger Name: nur unter diesen Kandidaten nach Ortsteilen entscheiden
        if named.count > 1 { scored = scored.filter { candidate in named.contains { $0.id == candidate.option.id } } }
        let best = scored.map(\.score).max() ?? 0
        let top = scored.filter { $0.score == best }
        return !folded.isEmpty && top.count == 1 ? top[0].option : nil
    }

    /// Sperre, Drosselung, Server- oder Zeitfehler: sagt nichts über die Gemeinde. Solche Ergebnisse werden nicht
    /// gespeichert, damit ein Fortsetzen sie erneut prüft (sonst stünden sie für immer als „fehler“ in der Datei).
    static func isTransient(_ result: Result) -> Bool {
        guard result.status == "fehler" else { return false }
        let text = (result.error ?? "") + " " + result.reasons.joined(separator: " ")
        // Netzausfall auf dem Prüfrechner (Punkt-6-Nachlauf 16.11.2026: 650 Zeilen „keine Verbindung zum Internet“ für Trier,
        // Altenkirchen, Kusel) sagt nichts über das Portal; „kein Server mit dem Hostnamen“ bleibt ein Befund
        return ["HTTP 429", "HTTP 5", "gesperrt", "Portal antwortet nicht", "Abfragegrenze",
                "keine Verbindung zum Internet", "Internet connection appears to be offline"].contains { text.contains($0) }
            // Müllmax sperrt die IP des Prüfrechners mit HTTP 403 (16.11.2026: von gsg/live aus 200, Dillingen 11 Termine)
            || (result.kind == ProviderKind.muellmax.rawValue && text.contains("HTTP 403"))
    }

    /// „Gronau (Westf.)“ → „Gronau“, „Ahaus, Stadt“ → „Ahaus“
    static func searchName(_ place: String) -> String {
        var name = place
        if let cut = name.firstIndex(of: "(") { name = String(name[..<cut]) }
        if let cut = name.firstIndex(of: ",") { name = String(name[..<cut]) }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Bewertung der Termine. Fehler: keine kommenden Termine. Warnung: auffällig wenig oder unplausibel.
    static func judge(_ pickups: [Pickup], into result: inout Result, calendar: Calendar) {
        let today = calendar.startOfDay(for: Date())
        let future = pickups.filter { $0.date >= today }.sorted { $0.date < $1.date }
        result.future = future.count
        result.types = Array(Set(future.map(\.name))).sorted()
        result.next = future.first.map { Days.iso($0.date, calendar: calendar) }
        result.last = future.last.map { Days.iso($0.date, calendar: calendar) }
        guard let first = future.first, let last = future.last else {
            result.status = "fehler"
            result.reasons.append(pickups.isEmpty ? "keine Termine" : "nur vergangene Termine (letzter \(Days.iso(pickups.map(\.date).max()!, calendar: calendar)))")
            return
        }
        var warnings: [String] = []
        if Days.between(today, first.date, calendar: calendar) > 28 { warnings.append("nächste Abfuhr erst in \(Days.between(today, first.date, calendar: calendar)) Tagen") }
        if Days.between(today, last.date, calendar: calendar) < 21 { warnings.append("Termine enden schon am \(Days.iso(last.date, calendar: calendar))") }
        if result.types.count == 1 { warnings.append("nur eine Müllart (\(result.types[0]))") }
        if future.count < 4 { warnings.append("nur \(future.count) kommende Termine") }
        let odd = result.types.filter { name in
            name.trimmingCharacters(in: .whitespaces).isEmpty || name.count > 60 || name.contains("http") || name.contains("<")
                || name.allSatisfy { $0.isNumber || $0.isPunctuation || $0.isWhitespace }
        }
        if !odd.isEmpty { warnings.append("seltsame Müllart-Namen: \(odd.prefix(3).map { "„\($0)“" }.joined(separator: ", "))") }
        let years = Set(future.map { calendar.component(.year, from: $0.date) })
        if let far = years.max(), far > calendar.component(.year, from: today) + 2 { warnings.append("Termine im Jahr \(far)") }
        if !warnings.isEmpty {
            result.status = "warnung"
            result.reasons += warnings
        }
    }

    // MARK: Hilfen

    struct WalkError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    struct TimeoutError: Error {}

    static func withTimeout<T: Sendable>(_ seconds: UInt64, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw TimeoutError()
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    actor LineWriter {
        private let handle: FileHandle
        private(set) var count = 0

        init(path: String) throws {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            handle.seekToEndOfFile()
        }

        func write(_ result: Result) {
            if PortalHealthLiveTests.isTransient(result) {
                print("HEALTH ~ \(result.title)\(result.place.map { " / \($0)" } ?? "") – vorübergehend, nicht gespeichert: \(result.error ?? "")")
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(result) else { return }
            handle.write(data + Data("\n".utf8))
            count += 1
            let mark = result.status == "ok" ? "✓" : (result.status == "warnung" ? "!" : "✗")
            print("HEALTH \(mark) \(result.title)\(result.place.map { " / \($0)" } ?? "") – \(result.future) Termine \(result.reasons.joined(separator: "; "))")
        }
    }
}
