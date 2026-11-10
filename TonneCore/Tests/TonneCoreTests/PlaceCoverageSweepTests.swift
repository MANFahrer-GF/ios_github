import XCTest
@testable import TonneCore

/// Holt je Katalogeintrag die erste Auswahl des Assistenten und schreibt sie als JSON-Zeile in eine Datei.
/// Daraus gleicht `tools/catalog/place_coverage.py` ab, welche Gemeinde ein Entsorger wirklich führt –
/// die Kreiszuordnung allein sagt das nicht (Rhein-Kreis Neuss galt als abgedeckt, die Stadt Neuss führte keiner).
/// Läuft nur mit `TONNE_PLACE_SWEEP=<Ausgabedatei>`, weil es jedes Portal abfragt.
/// `TONNE_PLACE_PROBES=<JSON {Eintrags-ID: [Suchtexte]}>` beschränkt den Lauf auf diese Einträge: Suchfelder werden mit
/// den Texten sondiert, bei Listen kommt die zweite Auswahl je Zeile dazu (Verbandsgemeinde → Ortsgemeinden).
final class PlaceCoverageSweepTests: XCTestCase {
    private struct Probe: Encodable {
        var text: String
        var count: Int
        var step: String?
        var sample: [String]
        var error: String?
    }

    private struct Line: Encodable {
        var id: String
        var kind: String
        var input: String
        var step: String?
        var options: [String]
        var error: String?
        var probes: [Probe]
        /// Zweite Auswahl je Zeile der ersten, wenn die erste nur Verbandsgemeinden, Ämter oder Landkreise zeigt.
        var subStep: String?
        var sub: [String: [String]]
        /// Dritte Auswahl („Bundesland|Landkreis“ → Orte), wenn die zweite erst den Landkreis abfragt (Abfall+ Wecker).
        var deepStep: String?
        var deep: [String: [String]]
    }

    func testFirstSteps() async throws {
        guard let path = ProcessInfo.processInfo.environment["TONNE_PLACE_SWEEP"], !path.isEmpty else {
            throw XCTSkip("TONNE_PLACE_SWEEP nicht gesetzt")
        }
        L10n.forcedLanguage = "de"
        var probes: [String: [String]] = [:]
        if let probePath = ProcessInfo.processInfo.environment["TONNE_PLACE_PROBES"] {
            probes = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: URL(fileURLWithPath: probePath)))
        }
        let only = probes.isEmpty ? nil : Set(probes.keys)
        let entries = ProviderCatalog.entries.filter { only?.contains($0.id) ?? true }
        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: path))
        defer { try? handle.close() }
        let encoder = JSONEncoder()
        var iterator = entries.makeIterator()
        var written = 0
        await withTaskGroup(of: Line.self) { group in
            func addNext() {
                guard let entry = iterator.next() else { return }
                let texts = probes[entry.id] ?? []
                let expand = only != nil
                group.addTask { await Self.walk(entry, probes: texts, expand: expand) }
            }
            for _ in 0..<12 { addNext() }
            while let line = await group.next() {
                if let data = try? encoder.encode(line) {
                    handle.write(data)
                    handle.write(Data("\n".utf8))
                    written += 1
                }
                addNext()
            }
        }
        XCTAssertEqual(written, entries.count)
    }

    private static func walk(_ entry: CatalogEntry, probes: [String], expand: Bool) async -> Line {
        let provider = ProviderFactory.make(kind: entry.kind, serviceKey: entry.serviceKey)
        var line = Line(id: entry.id, kind: entry.kind.rawValue, input: "fehler", step: nil, options: [], error: nil, probes: [], subStep: nil, sub: [:], deepStep: nil, deep: [:])
        var first: [SelectionOption] = []
        do {
            guard let step = try await provider.nextStep(after: []) else {
                line.input = "keine"
                return line
            }
            line.step = step.title
            line.input = step.input == .text ? "text" : "liste"
            line.options = step.options.map(\.title)
            first = step.options
        } catch {
            line.error = error.localizedDescription
            return line
        }
        if line.input == "liste", expand, first.count <= 80 {
            for option in first {
                guard let next = try? await provider.nextStep(after: [option]), next.input == .list else { continue }
                line.subStep = next.title
                line.sub[option.title] = next.options.map(\.title)
                guard next.title == "Landkreis" else { continue }
                for district in next.options {
                    guard let third = try? await provider.nextStep(after: [option, district]), third.input == .list else { continue }
                    line.deepStep = third.title
                    line.deep[option.title + "|" + district.title] = third.options.map(\.title)
                }
            }
        }
        guard line.input == "text" else { return line }
        for text in probes {
            var probe = Probe(text: text, count: 0, step: nil, sample: [], error: nil)
            do {
                if let next = try await provider.nextStep(after: [SelectionOption(id: text, title: text)]) {
                    probe.step = next.title
                    probe.count = next.input == .text ? -1 : next.options.count
                    // Straßen-Suchfeld eines Kreises: der Ort steht im Untertitel („29614 Soltau“) → „Soltau / Hauptstr.“
                    probe.sample = next.options.prefix(600).map { option in
                        let place = (option.subtitle ?? "").replacingOccurrences(of: #"^\d{5}\s*"#, with: "", options: .regularExpression)
                        return place.isEmpty ? option.title : "\(place) / \(option.title)"
                    }
                } else {
                    probe.count = -2
                }
            } catch {
                probe.error = error.localizedDescription
            }
            line.probes.append(probe)
        }
        return line
    }
}
