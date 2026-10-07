import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HTTPError: LocalizedError {
    case badURL(String)
    case status(Int, String)
    case transport(String)
    case decoding(String)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .badURL(let url): return "Ungültige Adresse: \(url)"
        case .status(let code, let host): return "\(host) antwortete mit HTTP \(code)."
        case .transport(let message): return "Verbindung fehlgeschlagen: \(message)"
        case .decoding(let message): return "Antwort konnte nicht gelesen werden: \(message)"
        case .unexpected(let message): return message
        }
    }
}

/// Kleiner HTTP-Client für alle Anbieter – mit Browser-ähnlichem User-Agent, weil manche
/// Portale sonst blocken. Auf Linux (Tests) läuft er über FoundationNetworking.
public struct HTTPClient {
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TonneUndTorte/2.0"
    public var timeout: TimeInterval = 30
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ urlString: String, headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw HTTPError.badURL(urlString) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request, headers: headers)
    }

    public func post(_ urlString: String, body: Data, contentType: String, headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw HTTPError.badURL(urlString) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        var allHeaders = headers
        allHeaders["Content-Type"] = contentType
        return try await perform(request, headers: allHeaders)
    }

    public func postForm(_ urlString: String, fields: [(String, String)], headers: [String: String] = [:]) async throws -> Data {
        let body = fields.map { "\(HTTPClient.formEncode($0.0))=\(HTTPClient.formEncode($0.1))" }.joined(separator: "&")
        return try await post(urlString, body: Data(body.utf8), contentType: "application/x-www-form-urlencoded; charset=utf-8", headers: headers)
    }

    public func json<T: Decodable>(_ urlString: String, as type: T.Type = T.self, headers: [String: String] = [:]) async throws -> T {
        let data = try await get(urlString, headers: headers.merging(["Accept": "application/json"]) { a, _ in a })
        return try HTTPClient.decode(data)
    }

    /// Liefert die endgültige URL nach Weiterleitungen (z. B. mit Sitzungs-ID im Pfad).
    public func finalURL(_ urlString: String) async throws -> URL? {
        guard let url = URL(string: urlString) else { throw HTTPError.badURL(urlString) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        return response.url
    }

    public func string(_ urlString: String, headers: [String: String] = [:]) async throws -> String {
        let data = try await get(urlString, headers: headers)
        return HTTPClient.text(from: data)
    }

    public static func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(String(describing: error).prefix(200).description)
        }
    }

    public static func text(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    public static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: "%20", with: "+") ?? value
    }

    public static func query(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func perform(_ request: URLRequest, headers: [String: String]) async throws -> Data {
        var request = request
        request.timeoutInterval = timeout
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode, request.url?.host ?? "Server")
        }
        return data
    }
}

/// Kleine HTML-Helfer für Portale ohne JSON-Schnittstelle.
public enum HTMLText {
    /// Alle `<option value="…">Text</option>` eines `<select name="…">`.
    public static func options(ofSelect name: String, in html: String) -> [(value: String, label: String)] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let select = firstMatch(#"<select[^>]*(?:name|id)=["']\#(escaped)["'][^>]*>([\s\S]*?)</select>"#, in: html, group: 1) else { return [] }
        return matches(#"<option[^>]*value=(?:"([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)</option>"#, in: select).map { groups in
            let value = groups[0].isEmpty ? groups[1] : groups[0]
            return (value: decodeEntities(value), label: decodeEntities(stripTags(groups[2])).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Alle versteckten Eingabefelder als Name → Wert.
    public static func hiddenInputs(in html: String) -> [(name: String, value: String)] {
        matches(#"<input[^>]*type=["']hidden["'][^>]*>"#, in: html, wholeMatch: true).compactMap { tag in
            guard let name = firstMatch(#"name=["']([^"']*)["']"#, in: tag[0], group: 1) else { return nil }
            let value = firstMatch(#"value=["']([^"']*)["']"#, in: tag[0], group: 1) ?? ""
            return (decodeEntities(name), decodeEntities(value))
        }
    }

    public static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    public static func decodeEntities(_ text: String) -> String {
        var result = text
        let map = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&szlig;": "ß", "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&shy;": "", "&#x27;": "'", "&#x2F;": "/"]
        for (entity, char) in map { result = result.replacingOccurrences(of: entity, with: char) }
        // numerische Entities &#123;
        if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            let ns = result as NSString
            var output = result
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
                if let code = Int(ns.substring(with: match.range(at: 1))), let scalar = UnicodeScalar(code) {
                    output = (output as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
            result = output
        }
        return result
    }

    public static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: match.range(at: group))
    }

    /// Liefert je Treffer die Capture-Gruppen (oder bei `wholeMatch` den ganzen Treffer als einziges Element).
    public static func matches(_ pattern: String, in text: String, wholeMatch: Bool = false) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            if wholeMatch { return [ns.substring(with: match.range)] }
            return (1..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
        }
    }
}
