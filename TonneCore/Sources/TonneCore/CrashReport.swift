import Foundation
import CryptoKit

/// Ein Absturzbericht von iOS, bereit zum Verschicken. Enthält nur technische Angaben (Gerät, Versionen, Aufrufstapel),
/// keine Termine, Namen oder Orte.
public struct CrashReport: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// Ende des Zeitraums, für den iOS den Bericht liefert (bis zu 24 h) – nicht der genaue Absturzzeitpunkt.
    public let reportDate: Date
    public let appVersion: String
    public let osVersion: String
    public let deviceType: String
    public let exceptionType: Int?
    public let exceptionCode: Int?
    public let signal: Int?
    public let terminationReason: String?
    public let objectiveCException: String?
    public let callStackJSON: String
    /// Wurde dem Nutzer schon einmal angeboten – der Hinweis beim Start kommt je Bericht nur einmal.
    public var prompted: Bool

    public init(reportDate: Date, appVersion: String, osVersion: String, deviceType: String,
                exceptionType: Int?, exceptionCode: Int?, signal: Int?,
                terminationReason: String?, objectiveCException: String?, callStackJSON: String) {
        self.reportDate = reportDate
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceType = deviceType
        self.exceptionType = exceptionType
        self.exceptionCode = exceptionCode
        self.signal = signal
        self.terminationReason = terminationReason
        self.objectiveCException = objectiveCException
        self.callStackJSON = callStackJSON
        self.prompted = false
        // iOS kann denselben Bericht mehrfach liefern; die Kennung hängt nur am Inhalt, damit er einmal zählt.
        let key = [String(reportDate.timeIntervalSince1970), appVersion, osVersion, deviceType,
                   exceptionType.map(String.init) ?? "", exceptionCode.map(String.init) ?? "", signal.map(String.init) ?? "",
                   terminationReason ?? "", objectiveCException ?? "", callStackJSON].joined(separator: "|")
        self.id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Kopfzeilen des Berichts – steht im Mail-Text und oben in der Datei.
    public var summary: String {
        var lines = [
            "App: \(appVersion)",
            "System: \(osVersion)",
            "Gerät: \(deviceType)",
            "Berichtszeitraum endet: \(ISO8601DateFormatter().string(from: reportDate))",
        ]
        if let exceptionType { lines.append("Exception-Typ: \(exceptionType)") }
        if let exceptionCode { lines.append("Exception-Code: \(exceptionCode)") }
        if let signal { lines.append("Signal: \(signal)") }
        if let terminationReason { lines.append("Grund: \(terminationReason)") }
        if let objectiveCException { lines.append("Objective-C: \(objectiveCException)") }
        return lines.joined(separator: "\n")
    }

    /// Vollständiger Bericht als Text: Kopfzeilen und Aufrufstapel.
    public var fileText: String { summary + "\n\n" + callStackJSON + "\n" }
}

/// Bewahrt die letzten Absturzberichte in einer Datei auf. Wird aus dem MetricKit-Rückruf (Hintergrund) und von der
/// Oberfläche benutzt, deshalb mit Sperre.
public final class CrashReportStore: @unchecked Sendable {
    public static let maxReports = 5
    private static let maxSeen = 50

    /// `seen` überlebt das Löschen: iOS liefert alte Berichte bei jedem Start erneut, gelöschte sollen nicht wiederkommen.
    private struct Archive: Codable {
        var reports: [CrashReport] = []
        var seen: [String] = []
    }

    private let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [CrashReport] {
        lock.lock(); defer { lock.unlock() }
        return read()?.reports ?? []
    }

    /// Nimmt neue Berichte auf, überspringt schon bekannte und behält die neuesten `maxReports`.
    public func add(_ new: [CrashReport]) {
        lock.lock(); defer { lock.unlock() }
        guard var archive = read() else { return }
        for report in new where !archive.seen.contains(report.id) {
            archive.reports.append(report)
            archive.seen.append(report.id)
        }
        archive.reports.sort { $0.reportDate > $1.reportDate }
        archive.reports = Array(archive.reports.prefix(Self.maxReports))
        archive.seen = Array(archive.seen.suffix(Self.maxSeen))
        write(archive)
    }

    public func markPrompted(id: String) {
        lock.lock(); defer { lock.unlock() }
        guard var archive = read(), let index = archive.reports.firstIndex(where: { $0.id == id }) else { return }
        archive.reports[index].prompted = true
        write(archive)
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        guard var archive = read() else { return }
        archive.reports = []
        write(archive)
    }

    /// `nil`: Datei gerade nicht lesbar (z. B. Hintergrundstart vor dem ersten Entsperren) – dann nichts überschreiben,
    /// iOS liefert die Berichte beim nächsten Start erneut. Eine fehlende Datei zählt als leer, eine kaputte wird beiseitegelegt.
    private func read() -> Archive? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return Archive()
        } catch {
            return nil
        }
        if let archive = try? JSONDecoder().decode(Archive.self, from: data) { return archive }
        let aside = url.appendingPathExtension("kaputt")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return Archive()
    }

    private func write(_ archive: Archive) {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
