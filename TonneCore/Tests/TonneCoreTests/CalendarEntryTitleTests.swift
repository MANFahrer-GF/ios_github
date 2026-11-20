import XCTest
@testable import TonneCore

final class CalendarEntryTitleTests: XCTestCase {
    /// Standard wie bisher: mit Emoji.
    func testWithEmoji() {
        XCTAssertEqual(CalendarEntryTitle.make(.waste, "Restmüll (Gifhorn)", emoji: true), "🗑️ Restmüll (Gifhorn)")
        XCTAssertEqual(CalendarEntryTitle.make(.birthday, "Oma Erika (80)", emoji: true), "🎂 Oma Erika (80)")
        XCTAssertEqual(CalendarEntryTitle.make(.custom, "TÜV", emoji: true), "📌 TÜV")
    }

    /// Schalter aus: nur der Text, kein Emoji, kein führendes Leerzeichen.
    func testWithoutEmoji() {
        XCTAssertEqual(CalendarEntryTitle.make(.waste, "Restmüll (Gifhorn)", emoji: false), "Restmüll (Gifhorn)")
        XCTAssertEqual(CalendarEntryTitle.make(.birthday, "Oma Erika (80)", emoji: false), "Oma Erika (80)")
        XCTAssertEqual(CalendarEntryTitle.make(.custom, "TÜV", emoji: false), "TÜV")
    }

    /// ICS-Kennung: gleich mit und ohne Emojis und identisch mit der Formel bis 2.1.0 (aus „🗑️ Restmüll“) –
    /// schon importierte Dateien bekommen beim erneuten Import keine Doppel (Prüfbefund 20.11.2026).
    func testFeedUIDStableAndCompatible() {
        let old = "2026-12-01-\("🗑️ Restmüll".unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF })@tonneundtorte"
        XCTAssertEqual(CalendarEntryTitle.feedUID(day: "2026-12-01", .waste, "Restmüll"), old)
        XCTAssertNotEqual(CalendarEntryTitle.feedUID(day: "2026-12-01", .birthday, "Restmüll"), old)
    }
}

