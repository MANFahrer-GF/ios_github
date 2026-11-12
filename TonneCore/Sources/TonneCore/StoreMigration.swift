import Foundation

/// Datenbank aus dem gemeinsamen App-Group-Ordner in den eigenen Ordner der App verschieben.
///
/// SwiftData legt den Speicher bei vorhandener App Group standardmäßig im gemeinsamen Ordner ab. Hält die App dort beim
/// Suspendieren noch eine SQLite-Sperre (typisch: iCloud-Abgleich schreibt gerade), beendet iOS sie mit 0xdead10cc
/// (Absturzbericht 2.0.10 (13), 12.11.2026). Widget und Watch lesen die Datenbank nicht (eigene Snapshot-Datei), sie gehört
/// also in den App-Ordner.
public enum StoreMigration {
    public enum Outcome: Equatable {
        /// Kein alter Speicher (Neuinstallation oder schon verschoben).
        case nothingToMove
        case moved
        /// Neuer Ort hat schon einen Speicher – der alte bleibt unangetastet liegen.
        case alreadyThere
        /// Verschieben gescheitert (z. B. Gerät nach Neustart noch gesperrt): diesmal den alten Ort öffnen.
        case failed
    }

    /// Alle Dateien eines Speichers: `Name.store`, `-wal`, `-shm`, `.Name_SUPPORT`, `Name_ckAssets` …
    static func belongs(_ file: String, to name: String) -> Bool {
        file.hasPrefix(name + ".") || file.hasPrefix(name + "_") || file.hasPrefix("." + name + "_")
    }

    public static func move(store name: String, from old: URL, to new: URL, fileManager: FileManager = .default) -> Outcome {
        let storeFile = name + ".store"
        guard fileManager.fileExists(atPath: old.appendingPathComponent(storeFile).path) else { return .nothingToMove }
        if fileManager.fileExists(atPath: new.appendingPathComponent(storeFile).path) { return .alreadyThere }
        do {
            try fileManager.createDirectory(at: new, withIntermediateDirectories: true)
            let files = try fileManager.contentsOfDirectory(atPath: old.path).filter { belongs($0, to: name) }
            // Die Hauptdatei zuletzt: Bricht es mittendrin ab, gilt der alte Ort beim nächsten Start weiter als Quelle.
            var moved: [String] = []
            for file in files.filter({ $0 != storeFile }) + [storeFile] {
                do {
                    try fileManager.moveItem(at: old.appendingPathComponent(file), to: new.appendingPathComponent(file))
                    moved.append(file)
                } catch {
                    // Zurückräumen, damit nicht halb hier, halb dort ein Speicher liegt
                    for done in moved { try? fileManager.moveItem(at: new.appendingPathComponent(done), to: old.appendingPathComponent(done)) }
                    return .failed
                }
            }
            return .moved
        } catch {
            return .failed
        }
    }
}
