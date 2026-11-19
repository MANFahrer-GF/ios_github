import Foundation

/// Vor dem Senden eines Absturzberichts: Ist die App aktuell? Viele Berichte kamen von alten Versionen, deren Fehler
/// längst behoben waren (Thomas, 19.11.2026). Die App fragt dafür die öffentliche App-Store-Abfrage
/// (`itunes.apple.com/lookup?bundleId=…`) – sie braucht nur die Kennung der App, keine Daten des Nutzers.
public enum UpdateCheck {
    public enum Verdict: Equatable, Sendable {
        /// Nichts bekannt, das neuer ist: senden wie bisher (auch ohne Netz).
        case current
        /// Im App Store gibt es eine neuere Version als die installierte.
        case updateAvailable(store: String)
        /// Installiert ist schon eine neuere Version als die, in der der Absturz passierte (iOS liefert Berichte bis zu
        /// einen Tag später, oft erst nach dem Update).
        case reportFromOlderVersion(report: String, installed: String)
    }

    public static func verdict(report: String, installed: String, store: String?) -> Verdict {
        if let store, isOlder(installed, than: store) { return .updateAvailable(store: number(store) ?? store) }
        if isOlder(report, than: installed) {
            return .reportFromOlderVersion(report: number(report) ?? report, installed: number(installed) ?? installed)
        }
        return .current
    }

    /// Versionsnummern vergleichen: „2.0.11 (15)“ < „2.1.0“, „2.1“ = „2.1.0“. Unlesbar → nie älter (im Zweifel senden).
    public static func isOlder(_ a: String, than b: String) -> Bool {
        guard let x = parts(a), let y = parts(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p < q }
        }
        return false
    }

    /// Version und Store-Seite aus der Antwort der App-Store-Abfrage; nil, wenn die App dort (noch) nicht steht.
    public static func storeVersion(fromLookup data: Data) -> (version: String, url: URL?)? {
        struct Response: Decodable {
            struct Item: Decodable { let version: String; let trackViewUrl: String? }
            let results: [Item]
        }
        guard let item = (try? JSONDecoder().decode(Response.self, from: data))?.results.first, parts(item.version) != nil else { return nil }
        return (item.version, item.trackViewUrl.flatMap(URL.init(string:)))
    }

    /// Erste Versionsnummer im Text („2.0.11 (15)“ → „2.0.11“).
    static func number(_ text: String) -> String? {
        text.range(of: #"\d+(\.\d+)*"#, options: .regularExpression).map { String(text[$0]) }
    }

    private static func parts(_ text: String) -> [Int]? {
        number(text).map { $0.split(separator: ".").compactMap { Int($0) } }
    }
}
