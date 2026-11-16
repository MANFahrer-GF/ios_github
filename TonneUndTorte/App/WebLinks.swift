import Foundation

/// Die Webseite der App (tonne.kant.ovh, seit 14.11.2026). Alle Adressen nur hier, damit ein Umzug eine Zeile ist.
enum WebLinks {
    static let base = URL(string: "https://tonne.kant.ovh/")!
    static let help = URL(string: "support.html", relativeTo: base)!.absoluteURL
    static let contact = URL(string: "kontakt.html", relativeTo: base)!.absoluteURL
    static let privacy = URL(string: "datenschutz.html", relativeTo: base)!.absoluteURL
    static let imprint = URL(string: "impressum.html", relativeTo: base)!.absoluteURL
}
