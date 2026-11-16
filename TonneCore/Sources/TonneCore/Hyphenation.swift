import Foundation

/// Weiche Trennstriche für lange Wörter in schmalen Spalten.
/// SwiftUI bricht ein Wort, das breiter als die Zeile ist, sonst mitten drin („Hauptuntersuc|hung“).
/// Mit U+00AD trennt der Textsatz an Silbengrenzen und zeigt dort einen Strich; ohne Umbruch bleibt das Zeichen unsichtbar.
public enum Hyphenation {
    public static let softHyphen: Character = "\u{00AD}"

    /// Setzt an jeder Trennstelle der Sprache einen weichen Trennstrich, nur in Wörtern ab `minLength` Buchstaben.
    /// Teile eines Bindestrich-Worts („Grundhöfer-Kantorowicz“) bleiben bis `compoundMinLength` Buchstaben ganz: Dort bricht
    /// die Zeile am Bindestrich, sonst zöge der Textsatz „Grundhö-“ / „fer-Kantorowicz“ vor. Längere Teile
    /// („TÜV-Hauptuntersuchung“) werden weiter getrennt, sonst bräche SwiftUI wieder mitten im Wort.
    public static func soft(_ text: String, english: Bool = L10n.isEnglish, minLength: Int = 8, compoundMinLength: Int = 13) -> String {
        let locale = Locale(identifier: english ? "en_US" : "de_DE") as CFLocale
        guard CFStringIsHyphenationAvailableForLocale(locale) else { return text }
        var result = ""
        var word = ""
        var afterHyphen = false
        func flush(before next: Character?) {
            let compound = afterHyphen || next == "-"
            result += word.count >= (compound ? compoundMinLength : minLength) ? hyphenate(word, locale: locale) : word
            word = ""
        }
        for ch in text {
            if ch.isLetter { word.append(ch); continue }
            flush(before: ch)
            result.append(ch)
            afterHyphen = ch == "-"
        }
        flush(before: nil)
        return result
    }

    private static func hyphenate(_ word: String, locale: CFLocale) -> String {
        let cf = word as CFString
        let length = CFStringGetLength(cf)
        var points: [CFIndex] = []
        var location = length
        while location > 0 {
            let p = CFStringGetHyphenationLocationBeforeIndex(cf, location, CFRange(location: 0, length: length), 0, locale, nil)
            // kein Strich direkt am Wortrand (nur 1–2 Buchstaben abgetrennt)
            guard p != kCFNotFound, p > 1, p < location else { break }
            if p <= length - 2 { points.append(p) }
            location = p
        }
        guard !points.isEmpty else { return word }
        let utf16 = Array(word.utf16)
        var out: [UInt16] = []
        let cuts = Set(points)
        for (i, unit) in utf16.enumerated() {
            if cuts.contains(i) { out.append(0x00AD) }
            out.append(unit)
        }
        return String(decoding: out, as: UTF16.self)
    }
}
