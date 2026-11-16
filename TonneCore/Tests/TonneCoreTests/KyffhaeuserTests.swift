import XCTest
@testable import TonneCore

/// Kyffhäuserkreis: Die Ortsauswahl kommt aus dem Filter „tribe_venues[]“ der Kalenderseite.
final class KyffhaeuserTests: XCTestCase {
    /// Nach der Ortsliste folgen die Filter für Behälter und Gemeinden. Deren Kennungen („Artern“ = 101) haben keine
    /// Termine, die API antwortet mit HTTP 400 – sechs Gemeinden scheiterten so in der Gemeinde-Prüfung vom 16.11.
    func testVenuesStopAtEndOfVenueFilter() {
        let html = #"""
        "name":"tribe_venues[]","options":[{"text":"Abtsbessingen","id":"1439","value":1439},{"text":"Artern – Tour 1","id":"1160","value":1160}]}],"type":"dropdown"},{"filter_object":{"type":"select","name":"Abfallbehälter","values":[{"name":"Biotonne","value":94}]},"options":[{"text":"Biotonne","id":"94","value":94},{"text":"Artern","id":"101","value":101}]}
        """#
        let venues = MitteldeutschlandPortalsProvider.kyffVenues(in: html)
        XCTAssertEqual(venues.map(\.title), ["Abtsbessingen", "Artern - Tour 1"])
        XCTAssertEqual(venues.map(\.id), ["1439", "1160"])
    }
}
