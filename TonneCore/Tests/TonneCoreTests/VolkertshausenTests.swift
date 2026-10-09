import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TonneCore

/// Gemeinde Volkertshausen (Landkreis Konstanz): Terminliste der Gemeinde-Webseite (TYPO3 hw_abfallkalender),
/// zwei Seiten. Beispielantworten echt und gekürzt (Abruf 09.10.2026); Live-Test nur mit TONNE_LIVE=1.
final class VolkertshausenTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func names(_ pickups: [Pickup]) -> [String] { pickups.map { "\(Days.iso($0.date)) \($0.name)" } }

    static let pageURL = "https://www.volkertshausen.de/leben-wohnen/ver-entsorgung/muelltermine"
    static let page2URL = "https://www.volkertshausen.de/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5BcurrentPage%5D=2&tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5Bsearch%5D=nope&cHash=3ce952b855d9c146daad698a8073eb53"

    static let page1 = #"""
    <h3>Die nächsten Termine</h3>
    <div class="hwsabfallkalender_termine list_module">
    <div class="hwsabfallkalender_termin record record_list">
    <h4 class="hwsabfallkalender_datum"> Freitag, 09.10.2026 </h4>
    <div class="hwsabfallkalender_termin_bezirk list_with_icon">
    <i class="fa-map list_icon far" title="Bezirk" aria-hidden="true"></i><span class="sr-only">Bezirk</span>
    <a class="internal-link" title="Volkertshausen" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=bezirkDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BbezirkUid%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;cHash=6b27050306ac6064ff7050d4dc9a2ba1"> Volkertshausen </a>
    </div>
    <br>
    <div class="hwsabfallkalender_termin_muelltyp list_with_icon">
    <i class="fa-trash list_icon far" title="Müll Typ" aria-hidden="true"></i><span class="sr-only">Müll Typ</span>
    <a class="internal-link" title="Biomüll" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=muelltypDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BmuelltypUid%5D=2&amp;cHash=e65be1e30294a0d967ee4509e4b01b0d"> Biomüll </a>
    </div>
    <br>
    </div>
    <div class="hwsabfallkalender_termin record record_list">
    <h4 class="hwsabfallkalender_datum"> Montag, 12.10.2026 </h4>
    <div class="hwsabfallkalender_termin_bezirk list_with_icon">
    <i class="fa-map list_icon far" title="Bezirk" aria-hidden="true"></i><span class="sr-only">Bezirk</span>
    <a class="internal-link" title="Volkertshausen" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=bezirkDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BbezirkUid%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;cHash=6b27050306ac6064ff7050d4dc9a2ba1"> Volkertshausen </a>
    </div>
    <br>
    <div class="hwsabfallkalender_termin_muelltyp list_with_icon">
    <i class="fa-trash list_icon far" title="Müll Typ" aria-hidden="true"></i><span class="sr-only">Müll Typ</span>
    <a class="internal-link" title="Restmüll" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=muelltypDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BmuelltypUid%5D=1&amp;cHash=f6b475538f880ad80cdbf4709990a6b2"> Restmüll </a>
    </div>
    <br>
    </div>
    <div class="hwsabfallkalender_termin record record_list">
    <h4 class="hwsabfallkalender_datum"> Donnerstag, 15.10.2026 </h4>
    <div class="hwsabfallkalender_termin_bezirk list_with_icon">
    <i class="fa-map list_icon far" title="Bezirk" aria-hidden="true"></i><span class="sr-only">Bezirk</span>
    <a class="internal-link" title="Volkertshausen" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=bezirkDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BbezirkUid%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;cHash=6b27050306ac6064ff7050d4dc9a2ba1"> Volkertshausen </a>
    </div>
    <br>
    <div class="hwsabfallkalender_termin_muelltyp list_with_icon">
    <i class="fa-trash list_icon far" title="Müll Typ" aria-hidden="true"></i><span class="sr-only">Müll Typ</span>
    <a class="internal-link" title="Gelbe Tonne" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=muelltypDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BmuelltypUid%5D=4&amp;cHash=21f9acf976e7e7fb1677573a84f72679"> Gelbe Tonne </a>
    </div>
    <br>
    </div>
    <div class="hwsabfallkalender_termin record record_list">
    <h4 class="hwsabfallkalender_datum"> Donnerstag, 22.10.2026 </h4>
    <div class="hwsabfallkalender_termin_bezirk list_with_icon">
    <i class="fa-map list_icon far" title="Bezirk" aria-hidden="true"></i><span class="sr-only">Bezirk</span>
    <a class="internal-link" title="Volkertshausen" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=bezirkDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BbezirkUid%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;cHash=6b27050306ac6064ff7050d4dc9a2ba1"> Volkertshausen </a>
    </div>
    <br>
    <div class="hwsabfallkalender_termin_muelltyp list_with_icon">
    <i class="fa-trash list_icon far" title="Müll Typ" aria-hidden="true"></i><span class="sr-only">Müll Typ</span>
    <a class="internal-link" title="Problemmüll" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=muelltypDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BmuelltypUid%5D=6&amp;cHash=94a348e6303559db1609c794d95911bf"> Problemmüll </a>
    </div>
    <br>
    </div> 
    <ul class="pager">
    <li class="current">
    <span>1</span>
    </li>
    <li>
    <a title="Seite 2" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5BcurrentPage%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5Bsearch%5D=nope&amp;cHash=3ce952b855d9c146daad698a8073eb53"> 2 </a>
    </li>
    <li class="next">
    <a title="Seite weiter" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5BcurrentPage%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5Bsearch%5D=nope&amp;cHash=3ce952b855d9c146daad698a8073eb53">
    </a>
    </li>
    <li class="last">
    <a title="Letzte Seite" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5BcurrentPage%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5Bsearch%5D=nope&amp;cHash=3ce952b855d9c146daad698a8073eb53">
    </a>
    </li>
    </ul>
    """#

    static let page2 = #"""
    <h3>Die nächsten Termine</h3>
    <div class="hwsabfallkalender_termine list_module">
    <div class="hwsabfallkalender_termin record record_list">
    <h4 class="hwsabfallkalender_datum"> Montag, 07.12.2026 </h4>
    <div class="hwsabfallkalender_termin_bezirk list_with_icon">
    <i class="fa-map list_icon far" title="Bezirk" aria-hidden="true"></i><span class="sr-only">Bezirk</span>
    <a class="internal-link" title="Volkertshausen" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=bezirkDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BbezirkUid%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;cHash=6b27050306ac6064ff7050d4dc9a2ba1"> Volkertshausen </a>
    </div>
    <br>
    <div class="hwsabfallkalender_termin_muelltyp list_with_icon">
    <i class="fa-trash list_icon far" title="Müll Typ" aria-hidden="true"></i><span class="sr-only">Müll Typ</span>
    <a class="internal-link" title="Restmüll" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=muelltypDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BmuelltypUid%5D=1&amp;cHash=f6b475538f880ad80cdbf4709990a6b2"> Restmüll </a>
    </div>
    <br>
    </div>
    <div class="hwsabfallkalender_termin record record_list">
    <h4 class="hwsabfallkalender_datum"> Donnerstag, 10.12.2026 </h4>
    <div class="hwsabfallkalender_termin_bezirk list_with_icon">
    <i class="fa-map list_icon far" title="Bezirk" aria-hidden="true"></i><span class="sr-only">Bezirk</span>
    <a class="internal-link" title="Volkertshausen" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=bezirkDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BbezirkUid%5D=2&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;cHash=6b27050306ac6064ff7050d4dc9a2ba1"> Volkertshausen </a>
    </div>
    <br>
    <div class="hwsabfallkalender_termin_muelltyp list_with_icon">
    <i class="fa-trash list_icon far" title="Müll Typ" aria-hidden="true"></i><span class="sr-only">Müll Typ</span>
    <a class="internal-link" title="Gelbe Tonne" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5Baction%5D=muelltypDetail&amp;tx_hwabfallkalender_hwabfallkalenderfe%5Bcontroller%5D=AbfallkalenderFrontend&amp;tx_hwabfallkalender_hwabfallkalenderfe%5BmuelltypUid%5D=4&amp;cHash=21f9acf976e7e7fb1677573a84f72679"> Gelbe Tonne </a>
    </div>
    <br>
    </div> 
    <ul class="pager">
    <li class="first">
    <a title="Erste Seite" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5Bsearch%5D=nope&amp;cHash=2432819cf4fd7df546b7d4d6b48b799b">
    </a>
    </li>
    <li class="previous">
    <a title="Seite zurück" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5Bsearch%5D=nope&amp;cHash=2432819cf4fd7df546b7d4d6b48b799b">
    </a>
    </li>
    <li>
    <a title="Seite 1" href="/leben-wohnen/ver-entsorgung/muelltermine?tx_hwabfallkalender_hwabfallkalenderfe%5B%40widget_0%5D%5Bsearch%5D=nope&amp;cHash=2432819cf4fd7df546b7d4d6b48b799b"> 1 </a>
    </li>
    <li class="current">
    <span>2</span>
    </li>
    </ul>
    """#

    func testParsing() {
        XCTAssertEqual(names(SuedwestPortalsProvider.volkertshausenPickups(Self.page1, calendar: calendar)),
                       ["2026-10-09 Biomüll", "2026-10-12 Restmüll", "2026-10-15 Gelbe Tonne", "2026-10-22 Schadstoffsammlung"])
        XCTAssertEqual(SuedwestPortalsProvider.volkertshausenNextPage(Self.page1), Self.page2URL)
        XCTAssertNil(SuedwestPortalsProvider.volkertshausenNextPage(Self.page2), "letzte Seite hat nur Zurück-Links")
        let categories = SuedwestPortalsProvider.volkertshausenPickups(Self.page1 + Self.page2, calendar: calendar).map { WasteCategory.classify($0.name) }
        XCTAssertEqual(categories, [.organic, .residual, .packaging, .hazardous, .residual, .packaging])
        for name in ["Blaue Tonne", "Elektrogroßgeräte", "Altholz", "Sperrmüll", "Schrottsammlung", "Christbaum-Abfuhr"] {
            XCTAssertNotEqual(WasteCategory.classify(SuedwestPortalsProvider.volkertshausenName(name)), .other, name)
        }
    }

    func testFlowAgainstStub() async throws {
        let provider = SuedwestPortalsProvider(service: "volkertshausen", client: HTTPClient(session: PortalStub.session { request in
            switch request.url {
            case Self.pageURL: return Self.page1
            case Self.page2URL: return Self.page2
            default: return nil
            }
        }))
        let first = try await provider.nextStep(after: [])
        XCTAssertNil(first, "gemeindeweit, keine Auswahl")
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        XCTAssertEqual(names(pickups), ["2026-10-09 Biomüll", "2026-10-12 Restmüll", "2026-10-15 Gelbe Tonne", "2026-10-22 Schadstoffsammlung",
                                        "2026-12-07 Restmüll", "2026-12-10 Gelbe Tonne"])
        XCTAssertEqual(provider.label(for: []), "Volkertshausen")
        XCTAssertEqual(PortalStub.requests().map(\.url), [Self.pageURL, Self.page2URL])
        XCTAssertTrue(PortalStub.requests().allSatisfy { $0.method == "GET" })
    }

    func testLiveVolkertshausen() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_LIVE"] == "1" else { throw XCTSkip("nur live") }
        let provider = SuedwestPortalsProvider(service: "volkertshausen")
        let first = try await provider.nextStep(after: [])
        XCTAssertNil(first)
        let pickups = try await provider.pickups(for: [], calendar: calendar)
        let upcoming = pickups.filter { $0.date >= calendar.startOfDay(for: Date()) }
        XCTAssertGreaterThanOrEqual(upcoming.count, 3)
        XCTAssertTrue(upcoming.allSatisfy { WasteCategory.classify($0.name) != .other }, "\(upcoming.map(\.name))")
        print("Volkertshausen:", pickups.count, pickups.map { "\(Days.iso($0.date)) \($0.name)" })
    }
}
