import Foundation
import WatchConnectivity
import TonneCore

/// Datenabgleich zwischen iPhone und Apple Watch über WatchConnectivity.
/// iPhone → Watch: der Widget-Snapshot als Application Context (kommt auch im Hintergrund an).
/// Watch → iPhone: „Erledigt“ für einen Tag.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    static let snapshotKey = "snapshot"
    static let doneKey = "doneDayKey"
    static let updatedNotification = Notification.Name("de.manfahrer.TonneUndTorte.watchSnapshotUpdated")

    /// Wird auf dem iPhone gesetzt, um „Erledigt“ von der Watch zu verarbeiten.
    var onDoneReceived: ((String) -> Void)?
    var onUndoReceived: ((String) -> Void)?
    static let undoKey = "undoDayKey"

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Senden

    /// iPhone: aktuellen Snapshot an die Watch übertragen.
    func send(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported(), let data = try? snapshot.encoded() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        try? session.updateApplicationContext([WatchSync.snapshotKey: data])
    }

    /// Watch: „Erledigt“ ans iPhone melden.
    static func sendDone(dayKey: String) { deliver([doneKey: dayKey]) }

    /// Watch: „Erledigt“ zurücknehmen.
    static func sendUndo(dayKey: String) { deliver([undoKey: dayKey]) }

    /// Nachrichten, die vor dem Verbindungsaufbau entstehen (z. B. Siri startet die Watch-App im Hintergrund),
    /// warten hier und gehen raus, sobald die Verbindung steht – statt verloren zu gehen.
    private static var pending: [[String: Any]] = []
    private static let pendingLock = NSLock()

    private static func deliver(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingLock.lock(); pending.append(payload); pendingLock.unlock()
            if session.delegate == nil { shared.activate() }
            return
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in session.transferUserInfo(payload) })
        } else {
            session.transferUserInfo(payload)
        }
    }

    private static func flushPending() {
        pendingLock.lock(); let queued = pending; pending.removeAll(); pendingLock.unlock()
        queued.forEach(deliver)
    }

    /// Watch: iPhone um frische Daten bitten.
    static func requestRefresh() {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["refresh": true], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(watchOS)
        apply(context: session.receivedApplicationContext)
        if activationState == .activated { WatchSync.flushPending() }
        #else
        // iPhone: nach der Aktivierung den aktuellen Stand schicken
        if activationState == .activated {
            DispatchQueue.main.async { NotificationCenter.default.post(name: WatchSync.updatedNotification, object: nil) }
        }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(context: applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    private func apply(context: [String: Any]) {
        guard let data = context[WatchSync.snapshotKey] as? Data, let snapshot = try? WidgetSnapshot.decode(data) else { return }
        #if os(watchOS)
        // Auf dem iPhone zurückgenommen: alten „Erledigt“-Zeitpunkt der Watch verwerfen
        for day in snapshot.pickupDays where !day.done { SnapshotStore.clearDoneTime(dayKey: Days.iso(day.date)) }
        #endif
        SnapshotStore.save(snapshot)
        DispatchQueue.main.async { NotificationCenter.default.post(name: WatchSync.updatedNotification, object: nil) }
    }

    private func handle(_ message: [String: Any]) {
        if let dayKey = message[WatchSync.doneKey] as? String {
            DispatchQueue.main.async { self.onDoneReceived?(dayKey) }
        }
        if let dayKey = message[WatchSync.undoKey] as? String {
            DispatchQueue.main.async { self.onUndoReceived?(dayKey) }
        }
        #if os(iOS)
        if message["refresh"] != nil {
            DispatchQueue.main.async { NotificationCenter.default.post(name: WatchSync.updatedNotification, object: nil) }
        }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
