import XCTest
@testable import TonneCore

/// Geht je Katalogeintrag einen Weg durch den Assistenten und schreibt jede Auswahlliste als Zeile ins Protokoll:
/// Länge, Sammeleinträge („Stadtteil - …“, „alle Straßen“), doppelte Titel, weiche Trennzeichen.
/// Läuft nur mit `TONNE_STREET_SWEEP=1`, weil es jedes Portal abfragt.
final class StreetStepSweepTests: XCTestCase {
    private static let collective = #"(?i)(^|\s)(stadtteil|stadtbezirk|ortsteil|ortschaft|gemeindeteil|bezirk)\b|alle\s+stra|übrige|restliche|sonstige"#

    func testStreetSteps() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TONNE_STREET_SWEEP"] != nil, "TONNE_STREET_SWEEP nicht gesetzt")
        L10n.forcedLanguage = "de"
        var iterator = ProviderCatalog.entries.makeIterator()
        await withTaskGroup(of: [String].self) { group in
            func addNext() {
                guard let entry = iterator.next() else { return }
                group.addTask { await Self.walk(entry) }
            }
            for _ in 0..<12 { addNext() }
            while let lines = await group.next() {
                lines.forEach { print($0) }
                addNext()
            }
        }
    }

    private static func walk(_ entry: CatalogEntry) async -> [String] {
        let provider = ProviderFactory.make(kind: entry.kind, serviceKey: entry.serviceKey)
        let head = "STREETSWEEP|\(entry.kind.rawValue)|\(entry.serviceKey)|\(entry.title)"
        var lines: [String] = []
        var selections: [SelectionOption] = []
        for depth in 0..<5 {
            let step: SelectionStep?
            do {
                step = try await provider.nextStep(after: selections)
            } catch {
                lines.append("\(head)|\(depth)|FEHLER|\(error.localizedDescription)")
                break
            }
            guard let step else {
                do {
                    let pickups = try await provider.pickups(for: selections, calendar: .current)
                    lines.append("\(head)|\(depth)|ENDE|termine=\(pickups.count)")
                } catch {
                    lines.append("\(head)|\(depth)|FEHLER-TERMINE|\(error.localizedDescription)")
                }
                break
            }
            guard step.input == .list else {
                lines.append("\(head)|\(depth)|TEXTEINGABE|\(step.title)")
                break
            }
            guard !step.options.isEmpty else {
                lines.append("\(head)|\(depth)|LEER|\(step.title)")
                break
            }
            let titles = step.options.map(\.title)
            let hits = titles.indices.filter { titles[$0].range(of: collective, options: .regularExpression) != nil }
            let duplicates = Dictionary(grouping: step.options, by: \.title).filter { Set($0.value.map(\.id)).count > 1 }.keys.sorted()
            let softHyphens = titles.filter { $0.contains("\u{AD}") }.count
            let samples = hits.prefix(4).map { titles[$0] }.joined(separator: " ; ")
            lines.append("\(head)|\(depth)|\(step.title)|n=\(titles.count)|sammel=\(hits.count)|erster=\(hits.first ?? -1)|doppelt=\(duplicates.count)|shy=\(softHyphens)|\(samples)|dup:\(duplicates.prefix(3).joined(separator: " ; "))")
            selections.append(step.options[step.options.count / 2])
        }
        return lines
    }
}
