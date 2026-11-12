import XCTest
@testable import TonneCore

/// Absturz 0xdead10cc (2.0.10 (13), 12.11.2026): Datenbank zieht aus dem App-Group-Ordner in den App-Ordner.
final class StoreMigrationTests: XCTestCase {
    private var root: URL!
    private var old: URL { root.appendingPathComponent("group/Library/Application Support") }
    private var new: URL { root.appendingPathComponent("app/Library/Application Support") }
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func write(_ dir: URL, _ name: String, _ text: String = "x") throws {
        try Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }

    func testMovesAllStoreFilesAndLeavesOthers() throws {
        for file in ["TonneUndTorte.store", "TonneUndTorte.store-wal", "TonneUndTorte.store-shm"] { try write(old, file, file) }
        try fm.createDirectory(at: old.appendingPathComponent(".TonneUndTorte_SUPPORT/_EXTERNAL_DATA"), withIntermediateDirectories: true)
        try write(old, "Fremd.store")
        XCTAssertEqual(StoreMigration.move(store: "TonneUndTorte", from: old, to: new), .moved)
        for file in ["TonneUndTorte.store", "TonneUndTorte.store-wal", "TonneUndTorte.store-shm", ".TonneUndTorte_SUPPORT"] {
            XCTAssertTrue(fm.fileExists(atPath: new.appendingPathComponent(file).path), file)
            XCTAssertFalse(fm.fileExists(atPath: old.appendingPathComponent(file).path), file)
        }
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("TonneUndTorte.store-wal"), encoding: .utf8), "TonneUndTorte.store-wal")
        XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent("Fremd.store").path), "fremde Dateien bleiben")
        // Zweiter Start: nichts mehr zu tun
        XCTAssertEqual(StoreMigration.move(store: "TonneUndTorte", from: old, to: new), .nothingToMove)
    }

    func testNewInstallHasNothingToMove() {
        XCTAssertEqual(StoreMigration.move(store: "TonneUndTorte", from: old, to: new), .nothingToMove)
    }

    /// Liegt am neuen Ort schon ein Speicher, wird nichts überschrieben.
    func testExistingNewStoreIsNeverOverwritten() throws {
        try write(old, "TonneUndTorte.store", "alt")
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try write(new, "TonneUndTorte.store", "neu")
        XCTAssertEqual(StoreMigration.move(store: "TonneUndTorte", from: old, to: new), .alreadyThere)
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("TonneUndTorte.store"), encoding: .utf8), "neu")
        XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent("TonneUndTorte.store").path))
    }

    /// Scheitert das Verschieben mittendrin (Ziel belegt), liegt danach alles wieder am alten Ort.
    func testFailureRollsBack() throws {
        for file in ["TonneUndTorte.store", "TonneUndTorte.store-wal"] { try write(old, file, file) }
        try fm.createDirectory(at: new.appendingPathComponent("TonneUndTorte.store-wal"), withIntermediateDirectories: true)
        XCTAssertEqual(StoreMigration.move(store: "TonneUndTorte", from: old, to: new), .failed)
        XCTAssertTrue(fm.fileExists(atPath: old.appendingPathComponent("TonneUndTorte.store").path))
        XCTAssertFalse(fm.fileExists(atPath: new.appendingPathComponent("TonneUndTorte.store").path))
    }
}
