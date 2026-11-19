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
        // Starts vor diesem: Der abgestürzte ist einer davon. Nur den eigenen ausnehmen – scheiterte dessen `begin`, wäre der
        // letzte Eintrag ein fremder, womöglich genau der abgestürzte
        let startLog = StartLogStore.text(StartTimings.store.load().filter { $0.id != StartTimings.id })
        let reports = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map { Self.report(from: $0, date: payload.timeStampEnd, startLog: startLog) }
        }
        guard !reports.isEmpty else { return }
        Self.store.add(reports)
        DispatchQueue.main.async { CrashReportCenter.shared.reload() }
    }

    private static func report(from crash: MXCrashDiagnostic, date: Date, startLog: String) -> CrashReport {
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
                           callStackJSON: String(decoding: crash.callStackTree.jsonRepresentation(), as: UTF8.self),
                           startLog: startLog)
    }

    #if DEBUG
    /// Oberflächen-Tests: leere Ablage, auf Wunsch (Startschalter -simulateCrashReport) mit einem Beispielbericht.
    /// -keepCrashReports lässt die Ablage stehen, um einen Neustart nachzustellen.
    static func seedForUITests() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("-keepCrashReports") else { return }
        store.removeAll()
        guard arguments.contains("-simulateCrashReport") else { return }
        // Version der installierten App: Ein älterer Bericht löste sonst die Update-Prüfung vor dem Senden aus (`StoreVersion`)
        store.add([CrashReport(reportDate: Date(), appVersion: StoreVersion.installed, osVersion: "iPhone OS 27.2", deviceType: "iPad16,6",
                               exceptionType: 6, exceptionCode: 0, signal: 5, terminationReason: "Testabsturz",
                               objectiveCException: nil, callStackJSON: "{\"callStacks\":[]}")])
    }
    #endif
}

/// Schrittzeiten des App-Starts, nach jedem Schritt abgelegt (`StartLogStore`). Ein späterer Absturzbericht trägt sie mit.
enum StartTimings {
    static let store = StartLogStore(url: TonneUndTorteApp.isUITesting
        ? FileManager.default.temporaryDirectory.appendingPathComponent("uitest-start-log.json")
        : URL.applicationSupportDirectory.appendingPathComponent("StartLog.json"))
    private static let launch = Date()
    /// Kennung dieses Starts im Protokoll.
    static let id = UUID()

    /// Als Erstes in `App.init`.
    static func begin() {
        store.begin(id: id, appVersion: StoreVersion.installed, at: launch)
    }

    /// Misst einen Schritt und legt ihn sofort ab – auch von einem Nebenthread aus.
    @discardableResult
    static func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        let start = Date()
        defer {
            let end = Date()
            store.step(name, milliseconds: Int(end.timeIntervalSince(start) * 1000), atMilliseconds: Int(end.timeIntervalSince(launch) * 1000), start: id)
        }
        return try work()
    }

    static func finish() { store.finish(start: id) }

    @MainActor private static var marked: Set<String> = []
    /// Zeitpunkt ohne Dauer, je Start einmal (Ende von `init`, erstes Mal im Vordergrund).
    @MainActor static func markOnce(_ name: String) {
        guard marked.insert(name).inserted else { return }
        measure(name) {}
    }
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

/// Installierte Version und die aktuelle im App Store (für die Update-Prüfung vor dem Senden eines Absturzberichts).
enum StoreVersion {
    /// „2.1.0 (17)“
    static var installed: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// Aktuelle Version im App Store des Geräte-Lands; nil ohne Netz, nach 5 s oder wenn die App dort nicht steht.
    /// Gefragt wird nur mit der Kennung der App. Oberflächen-Tests fragen nie im Netz: -simulateStoreVersion <Version>.
    static func latest() async -> (version: String, url: URL?)? {
        if TonneUndTorteApp.isUITesting {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-simulateStoreVersion"), i + 1 < args.count else { return nil }
            return (args[i + 1], URL(string: "https://apps.apple.com"))
        }
        guard let bundle = Bundle.main.bundleIdentifier else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "bundleId", value: bundle),
                                  URLQueryItem(name: "country", value: (Locale.current.region?.identifier ?? "DE").lowercased())]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UpdateCheck.storeVersion(fromLookup: data)
    }
}
