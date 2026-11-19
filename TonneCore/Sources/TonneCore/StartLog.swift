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

    public let started: Date
    public let appVersion: String
    public var steps: [Step] = []
    public var finished = false
}

/// Bewahrt die letzten Starts in einer Datei auf (Hintergrund und Hauptthread schreiben, deshalb mit Sperre).
public final class StartLogStore: @unchecked Sendable {
    public static let maxRecords = 5

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
    public func begin(appVersion: String, at date: Date) {
        change { $0.append(StartRecord(started: date, appVersion: appVersion)) }
    }

    public func step(_ name: String, milliseconds: Int, atMilliseconds: Int) {
        change { records in
            guard !records.isEmpty else { return }
            records[records.count - 1].steps.append(.init(name: name, milliseconds: milliseconds, atMilliseconds: atMilliseconds))
        }
    }

    /// Start vollständig: Datenbank offen, Oberfläche hat ihr Modell.
    public func finish() {
        change { records in
            guard !records.isEmpty else { return }
            records[records.count - 1].finished = true
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
        var records = read()
        edit(&records)
        records = Array(records.suffix(Self.maxRecords))
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Fehlt oder ist kaputt = leer: Das Protokoll ist nur eine Hilfe, es darf den Start nie aufhalten.
    private func read() -> [StartRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StartRecord].self, from: data)) ?? []
    }
}
