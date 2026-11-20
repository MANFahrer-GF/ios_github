import XCTest
@testable import TonneCore

/// Gelbe Tonne im Landkreis Helmstedt ab 2027 (PreZero-PDFs, Wunsch Julien 20.11.2026).
final class HelmstedtGelbeTonneTests: XCTestCase {
    private var berlin: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }

    /// Die sechs Gemeindegruppen heißen wie die ICS-Kalender des Landkreises – sonst fände der Abruf sie nicht.
    func testTownsMatchCountyCalendars() {
        XCTAssertEqual(Set(HelmstedtGelbeTonne.towns.keys), ["Lehre", "Nord-Elm und Königslutter Ortsteile", "Grasleben und Velpke",
                                                             "Schöningen und Heeseberg", "Helmstedt und Ortsteile", "Königslutter Stadtgebiet"])
    }

    /// Jedes Gebiet mit Terminen hat Orte/Straßen und umgekehrt; alle Termine 2027, nie sonntags, Abstand 4 Wochen (±2 Tage
    /// um Feiertage) – nur Heeseberg (Schöningen, Gebiet 5, Gelbe Säcke) 14-täglich.
    func testDataIsConsistent() throws {
        for (town, data) in HelmstedtGelbeTonne.towns {
            XCTAssertEqual(Set(data.dates.keys), Set(data.entries.map(\.area)), town)
            XCTAssertEqual(Set(data.entries.map(\.name)).count, data.entries.count, "doppelter Ort in \(town)")
            for (area, days) in data.dates {
                let dates = try days.map { try XCTUnwrap(Days.parse($0, calendar: berlin)) }
                XCTAssertTrue(dates.allSatisfy { berlin.component(.year, from: $0) == 2027 && berlin.component(.weekday, from: $0) != 1 }, "\(town) \(area)")
                let step = town == "Schöningen und Heeseberg" && area == 5 ? 14 : 28
                for (a, b) in zip(dates, dates.dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(Days.between(a, b, calendar: berlin) - step), 2, "\(town) Gebiet \(area): \(days)")
                }
            }
        }
    }

    /// Stichproben aus den PDFs (Seite 1 bzw. Einteilung).
    func testSamplesFromPDFs() {
        XCTAssertEqual(HelmstedtGelbeTonne.towns["Helmstedt und Ortsteile"]?.dates[6]?.first, "2027-01-04")
        XCTAssertEqual(HelmstedtGelbeTonne.towns["Lehre"]?.dates[1]?.first, "2027-01-07")
        XCTAssertEqual(HelmstedtGelbeTonne.towns["Helmstedt und Ortsteile"]?.entries.first { $0.name == "Barmke" }?.area, 7)
        XCTAssertEqual(HelmstedtGelbeTonne.towns["Grasleben und Velpke"]?.entries.first { $0.name == "Velpke" }?.area, 1)
        XCTAssertEqual(HelmstedtGelbeTonne.towns["Königslutter Stadtgebiet"]?.entries.first { $0.name == "Wolfsburger Straße ab Bahnlinie stadtauswärts" }?.area, 2)
    }

    /// Der Abruf liefert „Gelbe Tonne <Gebiet>“ – so greift die Gebietsauswahl wie bei Altpapier 1/2/3.
    func testEventsUseAreaSuffix() {
        let events = NordPortalsProvider.helmstedtYellowBinEvents("Lehre", calendar: berlin)
        XCTAssertEqual(events.count, 39)
        XCTAssertEqual(Set(events.map { NordPortalsProvider.areaSplit($0.summary).type }), ["Gelbe Tonne"])
        XCTAssertEqual(Set(events.compactMap { NordPortalsProvider.areaSplit($0.summary).area }), ["1", "2", "3"])
        XCTAssertTrue(NordPortalsProvider.helmstedtYellowBinEvents("Unbekannt", calendar: berlin).isEmpty)
    }

    /// Heeseberg (Gebiet 5 der Schöningen-Tabelle) behält Gelbe Säcke; die Orte stehen dort in der Tabelle.
    func testHeesebergIsSackArea() {
        XCTAssertEqual(HelmstedtGelbeTonne.sackAreas["Schöningen und Heeseberg"], [5])
        XCTAssertEqual(HelmstedtGelbeTonne.towns["Schöningen und Heeseberg"]?.entries.first { $0.name == "Jerxheim" }?.area, 5)
        XCTAssertEqual(HelmstedtGelbeTonne.towns["Schöningen und Heeseberg"]?.dates[5]?.count, 26)
    }

    /// Einrichtung vor dieser Version (kein Gebiet für die gelbe Tonne gewählt): keine gelben Termine statt aller Gebiete
    /// (Prüfbefund 20.11.2026: Lehre bekam 39 statt 13). Mit Gebiet: genau dessen 13.
    func testOldSetupGetsNoYellowBinAndNewSetupOnlyItsArea() {
        let events = NordPortalsProvider.helmstedtYellowBinEvents("Lehre", calendar: berlin)
        XCTAssertTrue(NordPortalsProvider.helmstedtFilter(events, chosen: ["Altpapier": "1"], town: "Lehre").isEmpty)
        let mine = NordPortalsProvider.helmstedtFilter(events, chosen: ["Gelbe Tonne": "2"], town: "Lehre")
        XCTAssertEqual(mine.count, 13)
        XCTAssertEqual(Set(mine.map(\.name)), ["Gelbe Tonne"])
    }

    /// Heeseberg: Gebiet 5 wird als „Gelber Sack“ geführt (passt zur bisherigen Müllart), die anderen Gebiete als Gelbe Tonne.
    func testHeesebergPickupsAreSacks() {
        let events = NordPortalsProvider.helmstedtYellowBinEvents("Schöningen und Heeseberg", calendar: berlin)
        let heeseberg = NordPortalsProvider.helmstedtFilter(events, chosen: ["Gelbe Tonne": "5"], town: "Schöningen und Heeseberg")
        XCTAssertEqual(heeseberg.count, 26)
        XCTAssertEqual(Set(heeseberg.map(\.name)), ["Gelber Sack"])
        let schoeningen = NordPortalsProvider.helmstedtFilter(events, chosen: ["Gelbe Tonne": "1"], town: "Schöningen und Heeseberg")
        XCTAssertEqual(Set(schoeningen.map(\.name)), ["Gelbe Tonne"])
    }
}

