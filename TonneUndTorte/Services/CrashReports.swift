import Foundation
import MetricKit
import TonneCore

/// Nimmt Absturzberichte von iOS (MetricKit) entgegen und legt sie sofort ab – auch wenn die App danach wieder abstürzt,
/// bleibt der Bericht erhalten. Die ältere MetricKit-Schnittstelle, weil die neue erst ab iOS 27 läuft und die App ab iOS 17.
final class CrashReportCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReportCollector()

    static let store = CrashReportStore(url: TonneUndTorteApp.isUITesting
        ? FileManager.default.temporaryDirectory.appendingPathComponent("uitest-crash-reports.json")
        : URL.applicationSupportDirectory.appendingPathComponent("CrashReports.json"))

    /// Als Erstes beim App-Start aufrufen: Abstürze beim Start sollen ebenfalls ankommen.
    func start() {
        guard !TonneUndTorteApp.isUITesting else { return }
        MXMetricManager.shared.add(self)
        DispatchQueue.global(qos: .utility).async { self.ingest(MXMetricManager.shared.pastDiagnosticPayloads) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        ingest(payloads)
    }

    private func ingest(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map { Self.report(from: $0, date: payload.timeStampEnd) }
        }
        guard !reports.isEmpty else { return }
        Self.store.add(reports)
        DispatchQueue.main.async { CrashReportCenter.shared.reload() }
    }

    private static func report(from crash: MXCrashDiagnostic, date: Date) -> CrashReport {
        // Nur Art und Klasse: der Meldungstext einer Ausnahme kann Nutzerdaten enthalten
        let objectiveC = crash.exceptionReason.map { "\($0.exceptionName) (\($0.className))" }
        return CrashReport(reportDate: date,
                           appVersion: "\(crash.applicationVersion) (\(crash.metaData.applicationBuildVersion))",
                           osVersion: crash.metaData.osVersion,
                           deviceType: crash.metaData.deviceType,
                           exceptionType: crash.exceptionType?.intValue,
                           exceptionCode: crash.exceptionCode?.intValue,
                           signal: crash.signal?.intValue,
                           terminationReason: crash.terminationReason,
                           objectiveCException: objectiveC,
                           callStackJSON: String(decoding: crash.callStackTree.jsonRepresentation(), as: UTF8.self))
    }

    #if DEBUG
    /// Oberflächen-Tests: leere Ablage, auf Wunsch (Startschalter -simulateCrashReport) mit einem Beispielbericht.
    /// -keepCrashReports lässt die Ablage stehen, um einen Neustart nachzustellen.
    static func seedForUITests() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("-keepCrashReports") else { return }
        store.removeAll()
        guard arguments.contains("-simulateCrashReport") else { return }
        store.add([CrashReport(reportDate: Date(), appVersion: "2.0.7 (8)", osVersion: "iPhone OS 27.2", deviceType: "iPad16,6",
                               exceptionType: 6, exceptionCode: 0, signal: 5, terminationReason: "Testabsturz",
                               objectiveCException: nil, callStackJSON: "{\"callStacks\":[]}")])
    }
    #endif
}

/// Stand der Absturzberichte für die Oberfläche.
@MainActor
final class CrashReportCenter: ObservableObject {
    static let shared = CrashReportCenter()

    @Published private(set) var reports: [CrashReport] = CrashReportCollector.store.load()

    /// Neuester Bericht, zu dem der Nutzer noch nicht gefragt wurde.
    var reportToOffer: CrashReport? { reports.first { !$0.prompted } }

    func reload() {
        reports = CrashReportCollector.store.load()
    }

    /// Noch nicht angebotene Berichte. Einmal gefragt genügt je Schub, die übrigen stehen in den Einstellungen.
    var idsToOffer: [String] { reports.filter { !$0.prompted }.map(\.id) }

    func markOffered(_ ids: [String]) {
        for id in ids { CrashReportCollector.store.markPrompted(id: id) }
        reload()
    }

    func removeAll() {
        CrashReportCollector.store.removeAll()
        reload()
    }
}
