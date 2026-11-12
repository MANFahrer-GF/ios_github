import XCTest
@testable import TonneCore

/// Vorübergehende Diagnose: TONNE_DIAG="kind;serviceKey;Eingabe1|Eingabe2|…" – Eingabe ist Text (Textfeld),
/// „#n“ (n-ter Listeneintrag), „*“ (mittlerer) oder ein Titel (genau).
final class AgentBDiagLiveTests: XCTestCase {
    func testDiag() async throws {
        guard let spec = ProcessInfo.processInfo.environment["TONNE_DIAG"] else { throw XCTSkip("kein TONNE_DIAG") }
        L10n.forcedLanguage = "de"
        for line in spec.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: ";")
            let provider = ProviderFactory.make(kind: ProviderKind(rawValue: parts[0])!, serviceKey: parts[1])
            var inputs = parts.count > 2 ? parts[2].components(separatedBy: "|") : []
            var selections: [SelectionOption] = []
            do {
                while let step = try await provider.nextStep(after: selections) {
                    let titles = step.options.map(\.title)
                    print("DIAG [\(step.title)] \(step.input) \(titles.count): \(titles.prefix(25).joined(separator: " · "))")
                    let input = inputs.isEmpty ? "*" : inputs.removeFirst()
                    if step.input == .text { selections.append(SelectionOption(id: input, title: input)); continue }
                    let option: SelectionOption?
                    if input == "*" { option = step.options[step.options.count / 2] }
                    else if input.hasPrefix("#"), let n = Int(input.dropFirst()) { option = step.options[min(n, step.options.count - 1)] }
                    else { option = step.options.first { $0.title == input } }
                    guard let option else { print("DIAG nicht gefunden: \(input)"); break }
                    print("DIAG → \(option.title) [\(option.id)]")
                    selections.append(option)
                }
                let pickups = try await provider.pickups(for: selections, calendar: .current)
                let future = pickups.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
                print("DIAG ERGEBNIS \(pickups.count) Termine, \(future.count) kommend: \(Set(future.map(\.name)).sorted().joined(separator: ", ")) – \(provider.label(for: selections))")
            } catch {
                print("DIAG FEHLER \(error.localizedDescription)")
            }
        }
    }
}

final class AgentBRawLiveTests: XCTestCase {
    func testRaw() async throws {
        guard ProcessInfo.processInfo.environment["TONNE_RAW"] != nil else { throw XCTSkip("kein TONNE_RAW") }
        let s = AbfallPlusAppProvider.Session(appID: "de.abfallwecker")
        _ = try await s.app("config.xml")
        let login = HTTPClient.text(from: try await s.app("login/"))
        print("RAW login inputs", HTMLText.allInputs(in: login).filter { $0.name.hasPrefix("f_id") })
        let bl = HTTPClient.text(from: Data(try await s.get("bundesland/").utf8))
        print("RAW bl", AbfallPlusAppProvider.items(in: bl).prefix(3).map { "\($0.id) \($0.name) \($0.extra)" })
        let lk = try await s.assistant("landkreis/", [("id_bundesland", "9"), ("id_landkreis", "0")])
        let leer = AbfallPlusAppProvider.items(in: lk).first { $0.name.contains("Leer") }
        print("RAW leer", leer.map { "\($0.id) step=\($0.step) next=\($0.next) \($0.extra)" } ?? "-")
        for (path, fields) in [("kommune/", [("id_landkreis", "462|0|Kreis Leer"), ("awk_href_back", "undefined")]),
                               ("kommune/", [("id_landkreis", "462|0|Kreis Leer"), ("id_kommune", "0")]),
                               ("region/", [("id_bundesland", "9"), ("id_landkreis", "462|0|Kreis Leer")]),
                               ("bezirk/", [("id_landkreis", "462|0|Kreis Leer"), ("id_kommune", "0")]),
                               ("strasse/", [("id_landkreis", "462|0|Kreis Leer"), ("id_kommune", "0"), ("id_bezirk", "0"), ("strasse_qry", "a")])] {
            let html: String
            do { html = try await s.assistant(path, fields) } catch { print("RAW \(path) \(fields): \(error)"); continue }
            let fieldsDesc = "\(path) \(fields)"
            print("RAW \(fieldsDesc): \(AbfallPlusAppProvider.items(in: html).count) items; \(html.prefix(400))")
        }
    }
}

final class AgentBLoginLiveTests: XCTestCase {
    func testLogin() async throws {
        guard let app = ProcessInfo.processInfo.environment["TONNE_LOGIN"] else { throw XCTSkip("kein TONNE_LOGIN") }
        let s = AbfallPlusAppProvider.Session(appID: app)
        _ = try await s.app("config.xml")
        let login = HTTPClient.text(from: try await s.app("login/"))
        try login.write(toFile: "/private/tmp/claude-501/apl-login.html", atomically: true, encoding: .utf8)
    }
}
