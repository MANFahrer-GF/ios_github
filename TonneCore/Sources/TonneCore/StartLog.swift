import Foundation

/// Ein App-Start mit den Zeiten seiner Schritte. Wird nach jedem Schritt sofort abgelegt: Beendet iOS den Start
/// (Watchdog 0x8BADF00D), bleibt der Teilstand stehen und lässt sich dem späteren Absturzbericht zuordnen.
public struct StartRecord: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public let name: String
        /// Dauer des Schritts.
        public let milliseconds: Int
        /// Ende des Schritts, gezählt ab Beginn des Starts.
        public let atMilliseconds: Int
    }

    /// Kennung des Starts: Schritte landen nur im eigenen Eintrag, nie in einem fremden (fehlt in Dateien vor dem Feld).
    public var id: UUID?
    public let started: Date
    public let appVersion: String
    public var steps: [Step] = []
    public var finished = false
}

/// Bewahrt die letzten Starts in einer Datei auf (Hintergrund und Hauptthread schreiben, deshalb mit Sperre).
public final class StartLogStore: @unchecked Sendable {
    /// Großzügig: iOS liefert den Absturzbericht bis zu einen Tag später, bis dahin kommen viele Hintergrundstarts dazu.
    public static let maxRecords = 40

    private let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [StartRecord] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    /// Neuer Start; die ältesten fallen heraus.
    public func begin(id: UUID, appVersion: String, at date: Date) {
        change { $0.append(StartRecord(id: id, started: date, appVersion: appVersion)) }
    }

    /// Schritt des Starts `start`. Fehlt dessen Eintrag (Datei war bei `begin` nicht lesbar), bleibt alles unverändert.
    public func step(_ name: String, milliseconds: Int, atMilliseconds: Int, start: UUID) {
        change { records in
            guard let index = records.lastIndex(where: { $0.id == start }) else { return }
            records[index].steps.append(.init(name: name, milliseconds: milliseconds, atMilliseconds: atMilliseconds))
        }
    }

    /// Start vollständig: Datenbank offen, Oberfläche hat ihr Modell.
    public func finish(start: UUID) {
        change { records in
            guard let index = records.lastIndex(where: { $0.id == start }) else { return }
            records[index].finished = true
        }
    }

    /// Lesbare Zeilen für den Absturzbericht, ältester Start zuerst.
    public static func text(_ records: [StartRecord]) -> String {
        let format = ISO8601DateFormatter()
        return records.map { record in
            let steps = record.steps.map { "\($0.name) \($0.milliseconds) ms (bei \($0.atMilliseconds) ms)" }.joined(separator: " · ")
            let end = record.finished ? "abgeschlossen" : "NICHT abgeschlossen"
            return "Start \(format.string(from: record.started)) (\(record.appVersion)): \(steps.isEmpty ? "–" : steps) – \(end)"
        }.joined(separator: "\n")
    }

    private func change(_ edit: (inout [StartRecord]) -> Void) {
        lock.lock(); defer { lock.unlock() }
        // Datei da, aber nicht lesbar: nichts schreiben – sonst ersetzte ein einzelner neuer Eintrag die alten Starts
        guard var records = readIfPossible() else { return }
        edit(&records)
        records = Array(records.suffix(Self.maxRecords))
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Ohne Dateischutz: Mit der iOS-Vorgabe (bis zum ersten Entsperren geschützt) wäre die Datei genau beim
        // Hintergrundstart nach einem Neustart weder les- noch schreibbar – dem Fall, den das Protokoll festhalten soll.
        // Sie enthält nur Zeiten, Schrittnamen und die App-Version, keine Nutzerdaten.
        try? data.write(to: url, options: [.atomic, .noFileProtection])
    }

    private func read() -> [StartRecord] { readIfPossible() ?? [] }

    /// Fehlt die Datei oder ist sie kaputt: leer (das Protokoll darf den Start nie aufhalten). `nil`: Datei da, aber gerade
    /// nicht lesbar (z. B. vor dem ersten Entsperren) – Vorbild `CrashReportStore.read`.
    private func readIfPossible() -> [StartRecord]? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            return nil
        }
        return (try? JSONDecoder().decode([StartRecord].self, from: data)) ?? []
    }
}
