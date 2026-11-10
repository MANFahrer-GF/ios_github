import XCTest
@testable import TonneCore

/// Geht für einen Katalogeintrag je Zeile der ersten Auswahl bis zu den Terminen durch (weitere Ebenen: mittlere Zeile)
/// und druckt je Ort die Zahl der künftigen Termine. Belegt, dass ein Ort der Ortsliste wirklich Termine liefert –
/// die Ortsliste allein beweist das nicht (Abfall+-Apps führen Orte, für die nur ein PDF existiert).
/// Läuft nur mit `TONNE_PLACE_DATES=<kind>:<serviceKey>[,…]`, optional `TONNE_PLACE_DATES_ONLY=<Ort>|<Ort>…`.
final class PlaceDatesLiveTests: XCTestCase {
    private static let probes = ["Haupt", "Bahnhof", "Kirch", "Schul", "Garten", "Berg", "Ring", "Weg", "Str"]

    func testEveryPlaceHasDates() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let spec = env["TONNE_PLACE_DATES"], !spec.isEmpty else {
            throw XCTSkip("TONNE_PLACE_DATES nicht gesetzt")
        }
        let only = env["TONNE_PLACE_DATES_ONLY"].map { Set($0.split(separator: "|").map(String.init)) }
        L10n.forcedLanguage = "de"
        for item in spec.split(separator: ",") {
            let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let kind = ProviderKind(rawValue: parts[0]) else {
                XCTFail("ungültig: \(item)"); continue
            }
            let provider = ProviderFactory.make(kind: kind, serviceKey: parts[1])
            guard let first = try await provider.nextStep(after: []) else { XCTFail("\(item): keine erste Auswahl"); continue }
            for option in first.options where only == nil || only!.contains(option.title) {
                var selections = [option]
                var line = "PLACEDATES|\(item)|\(option.title)|"
                do {
                    while let step = try await provider.nextStep(after: selections) {
                        // Freie Hausnummer (Bürgerportal): „1“ eintragen – ohne sie liefern manche Portale nur Sammeltermine
                        if step.input == .text, step.title == SelectionStep.houseNumberTitle {
                            selections.append(SelectionOption(id: "1", title: "1")); continue
                        }
                        if step.input == .text {
                            // Suchfeld: mit häufigen Straßenwörtern sondieren, bis eine Trefferliste kommt
                            var found: [SelectionOption] = []
                            for text in Self.probes {
                                let probe = selections + [SelectionOption(id: text, title: text)]
                                // „Keine Straße gefunden“ ist hier kein Fehler, sondern das Zeichen fürs nächste Suchwort
                                if let next = try? await provider.nextStep(after: probe), next.input == .list, !next.options.isEmpty {
                                    selections = probe; found = next.options; break
                                }
                            }
                            guard !found.isEmpty else { line += "texteingabe ohne Treffer"; break }
                            selections.append(found[found.count / 2])
                            continue
                        }
                        guard !step.options.isEmpty else { line += "leere Auswahl"; break }
                        selections.append(step.options[step.options.count / 2])
                        if selections.count > 6 { break }
                    }
                    if !line.hasSuffix("Treffer"), !line.hasSuffix("Auswahl") {
                        let pickups = try await provider.pickups(for: selections, calendar: .current)
                        let future = pickups.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
                        let kinds = Set(future.map(\.name)).sorted().prefix(6).joined(separator: ",")
                        line += "termine=\(future.count)|\(selections.dropFirst().map(\.title).joined(separator: " > "))|\(kinds)"
                    }
                } catch {
                    line += "FEHLER|\(error.localizedDescription)"
                }
                print(line)
            }
        }
    }
}
