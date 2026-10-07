import XCTest
@testable import TonneCore

/// Offline-Prüfungen der Hilfsfunktionen.
final class BayernPortalsProviderTests: XCTestCase {
    func testHeinzParamMatchesWebApp() {
        // Kennung aus der Web-App (vertauschte Base64-Zeichenpaare)
        let param = BayernPortalsProvider.heinzParam([
            ("landkreis", "Landkreis Freising"), ("ort", "Allershausen"), ("strasse", "Moosstr."), ("jahr", "2025"),
        ])
        XCTAssertEqual(param, "yesJWYk53alJXaiMiOMJWYk53alJXagMnRlJXapNmbicCLvJnciQiOBJGblxncoNXYzVWZi4CLzJHdhJ3clNjIioWTv93c0Nici4CLqJWYyhjIiojMyASN9J")
    }

    func testErhSplit() {
        let bins = BayernPortalsProvider.erhSplit("Restmülltonne / Biotonne / Restmüllcontainer , Di")
        XCTAssertEqual(bins.map(\.name), ["Restmülltonne", "Biotonne"])
        XCTAssertNil(bins.first?.note)
        let garden = BayernPortalsProvider.erhSplit("Gartenabfall , Fr, 16.00 - 18.00, Trautenauer Str., Süd")
        XCTAssertEqual(garden.map(\.name), ["Gartenabfall"])
        XCTAssertEqual(garden.first?.note, "16.00 - 18.00, Trautenauer Str., Süd")
    }

    /// Kleine XLSX-artige ZIP-Datei (mit Python erzeugt: DEFLATE-Einträge und ein gespeicherter Eintrag).
    private static let sampleXLSX = "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"

    func testXLSXAndAmbergParse() throws {
        let data = try XCTUnwrap(Data(base64Encoded: Self.sampleXLSX))
        let files = try BayernPortalsProvider.Zip.entries(Array(data))
        XCTAssertEqual(files["stored.txt"].map { String(decoding: $0, as: UTF8.self) }, "abc")
        let rows = try XCTUnwrap(BayernPortalsProvider.XLSX.rows(of: "Dateneingabe", in: data))
        XCTAssertEqual(rows.count, 59)
        XCTAssertEqual(rows[1]["C"], "C")
        XCTAssertEqual(rows[1]["F"], "34")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let pickups = BayernPortalsProvider.ambergParse(rows, zone: "C4", calendar: calendar)
        XCTAssertEqual(Set(pickups.map(\.name)), ["Restmüll", "Biomüll", "Gelber Sack"])
        XCTAssertEqual(pickups.map { Days.iso($0.date, calendar: calendar) }.first, "2026-01-02")
        XCTAssertEqual(BayernPortalsProvider.ambergParse(rows, zone: "D2", calendar: calendar).count, 56)
    }

    func testUnknownServiceThrows() async {
        do {
            _ = try await BayernPortalsProvider(service: "gibtsnicht").nextStep(after: [])
            XCTFail("Fehler erwartet")
        } catch {}
    }
}

/// Live-Abfragen (nur mit TONNE_LIVE=1).
extension LiveProviderTests {
    private func bayern(_ key: String) -> BayernPortalsProvider { BayernPortalsProvider(service: key) }

    func testBayernCham() async throws { try await check(bayern("cham"), prefer: ["Arrach", "Am Anger"], minCount: 3) }
    func testBayernChamHausnummer() async throws { try await check(bayern("cham"), prefer: ["Cham", "Further Str.", "10"], minCount: 3) }
    func testBayernSchwandorf() async throws { try await check(bayern("schwandorf"), prefer: ["Burglengenfeld", "Hauptstraße"], minCount: 3) }
    func testBayernSchwandorfHausnummer() async throws { try await check(bayern("schwandorf"), prefer: ["Schwandorf", "Wackersdorfer Straße", "10"], minCount: 3) }
    func testBayernBambergLand() async throws { try await check(bayern("bamberg_lk"), prefer: ["Burgebrach", "Ampferbach"], minCount: 3) }
    func testBayernForchheim() async throws { try await check(bayern("forchheim"), prefer: ["Dormitz", "Dormitz"], minCount: 3) }
    func testBayernEVA() async throws { try await check(bayern("eva"), prefer: ["Penzberg", "Ahlener Straße"], minCount: 3) }
    func testBayernERH() async throws { try await check(bayern("erh"), prefer: ["Höchstadt", "Böhmerwaldstraße"], minCount: 3) }
    func testBayernNeumarkt() async throws { try await check(bayern("neumarkt"), prefer: ["Parsberg", "Bogenmühle"], minCount: 3) }
    func testBayernSchwabach() async throws { try await check(bayern("schwabach"), prefer: ["Ahornweg"], minCount: 3) }
    func testBayernHeinzFreising() async throws { try await check(bayern("heinz"), prefer: ["Freising", "Obere Hauptstr."], minCount: 3) }
    func testBayernCoburg() async throws { try await check(bayern("coburg"), prefer: ["Adamistraße"], minCount: 3) }
    func testBayernFuerth() async throws { try await checkTyped(bayern("fuerth"), typed: ["Mühltal"], prefer: ["Mühltalstraße", "14"], minCount: 3) }
    func testBayernSchweinfurt() async throws { try await check(bayern("schweinfurt"), prefer: ["Ahornstrasse"], minCount: 3) }
    func testBayernHofStadt() async throws { try await check(bayern("hof_stadt"), prefer: ["Albert-Einstein-Straße"], minCount: 3) }
    func testBayernHofLand() async throws { try await check(bayern("hof_lk"), prefer: ["Ahornberg"], minCount: 3) }
    func testBayernHofLandStrasse() async throws { try await check(bayern("hof_lk"), prefer: ["Naila", "Amselweg"], minCount: 3) }
    func testBayernAmberg() async throws { try await check(bayern("amberg"), prefer: ["Adalbert-Stifter-Str."], minCount: 3) }
    func testBayernNuernbergerLand() async throws {
        try await check(bayern("nuernberger_land"), prefer: ["Burgthann", "Burgthann (Hauptort)", "Bahnhofstr.", "5"], minCount: 3)
    }
    func testBayernRhoenGrabfeld() async throws { try await check(bayern("rhoen_grabfeld"), prefer: ["Ostheim", "Oberwaldbehrungen"], minCount: 3) }
}
