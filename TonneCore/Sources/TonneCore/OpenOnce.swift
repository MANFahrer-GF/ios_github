import Foundation

/// Öffnet höchstens einmal gleichzeitig: Weitere Aufrufer warten auf den laufenden Versuch, statt selbst einen zu starten
/// (Umzug und Container doppelt nebeneinander wären gefährlich). Nach einem Erfolg nie wieder, nach einem Fehlschlag beim
/// nächsten Aufruf erneut – etwa die Datenbank, die vor dem ersten Entsperren nicht lesbar war.
@MainActor
public final class OpenOnce {
    /// Ein Versuch; `true` = geöffnet und nutzbar.
    private let attempt: @MainActor () async -> Bool
    private var running: Task<Void, Never>?
    public private(set) var succeeded = false

    public init(_ attempt: @escaping @MainActor () async -> Bool) {
        self.attempt = attempt
    }

    public func run() async {
        if let running { return await running.value }
        guard !succeeded else { return }
        let task = Task { @MainActor in
            self.succeeded = await self.attempt()
            self.running = nil   // im Versuch selbst zurücksetzen, nicht erst beim ersten Aufrufer nach dem Warten
        }
        running = task
        await task.value
    }
}
