import Foundation

/// Ein Entsorger, der das AWIDO-Portal (awido.cubefour.de) nutzt.
struct AwidoProvider: Identifiable, Hashable {
    let id: String
    let title: String

    /// Bekannte AWIDO-Kunden. Die Kennung ist der Pfadbestandteil in der Portal-URL
    /// `https://awido.cubefour.de/Customer/<kennung>/...`.
    static let known: [AwidoProvider] = [
        AwidoProvider(id: "gifhorn", title: "Landkreis Gifhorn"),
        AwidoProvider(id: "awb-altenburg", title: "Abfallwirtschaft Altenburger Land"),
        AwidoProvider(id: "awv-isar-inn", title: "Abfallwirtschaft Isar-Inn"),
        AwidoProvider(id: "awld", title: "Abfallwirtschaft Lahn-Dill-Kreis"),
        AwidoProvider(id: "rmk", title: "Abfallwirtschaft Rems-Murr (AWRM)"),
        AwidoProvider(id: "awv-nordschwaben", title: "Abfall-Wirtschafts-Verband Nordschwaben"),
        AwidoProvider(id: "awb-ak", title: "Abfallwirtschaftsbetrieb Landkreis Altenkirchen"),
        AwidoProvider(id: "azv-hef-rof", title: "AZV Landkreis Hersfeld-Rotenburg"),
        AwidoProvider(id: "awb-duerkheim", title: "AWB Landkreis Bad Dürkheim"),
        AwidoProvider(id: "ffb", title: "AWB Landkreis Fürstenfeldbruck"),
        AwidoProvider(id: "ebu", title: "EBU Ulm"),
        AwidoProvider(id: "unterhaching", title: "Gemeinde Unterhaching"),
        AwidoProvider(id: "ansbach", title: "Landkreis Ansbach"),
        AwidoProvider(id: "lra-ab", title: "Landkreis Aschaffenburg"),
        AwidoProvider(id: "bgl", title: "Landkreis Berchtesgadener Land"),
        AwidoProvider(id: "coburg", title: "Landkreis Coburg"),
        AwidoProvider(id: "erding", title: "Landkreis Erding"),
        AwidoProvider(id: "fulda", title: "Landkreis Fulda"),
        AwidoProvider(id: "lkgi", title: "Landkreis Gießen"),
        AwidoProvider(id: "gotha", title: "Landkreis Gotha"),
        AwidoProvider(id: "kaw-guenzburg", title: "Landkreis Günzburg"),
        AwidoProvider(id: "kelheim", title: "Landkreis Kelheim"),
        AwidoProvider(id: "kronach", title: "Landkreis Kronach"),
        AwidoProvider(id: "kulmbach", title: "Landkreis Kulmbach"),
        AwidoProvider(id: "lichtenfels", title: "Landkreis Lichtenfels"),
        AwidoProvider(id: "lra-mue", title: "Landkreis Mühldorf a. Inn"),
        AwidoProvider(id: "rosenheim", title: "Landkreis Rosenheim"),
        AwidoProvider(id: "roth", title: "Landkreis Roth"),
        AwidoProvider(id: "lra-schweinfurt", title: "Landkreis Schweinfurt"),
        AwidoProvider(id: "eww-suew", title: "Landkreis Südliche Weinstraße"),
        AwidoProvider(id: "kreis-tir", title: "Landkreis Tirschenreuth"),
        AwidoProvider(id: "tuebingen", title: "Landkreis Tübingen"),
        AwidoProvider(id: "ebe", title: "Landkreis Ebersberg"),
        AwidoProvider(id: "landkreisbetriebe", title: "Landkreisbetriebe Neuburg-Schrobenhausen"),
        AwidoProvider(id: "aic-fdb", title: "Landratsamt Aichach-Friedberg"),
        AwidoProvider(id: "lra-dah", title: "Landratsamt Dachau"),
        AwidoProvider(id: "lra-regensburg", title: "Landratsamt Regensburg"),
        AwidoProvider(id: "neustadt", title: "Neustadt a.d. Waldnaab"),
        AwidoProvider(id: "pullach", title: "Pullach im Isartal"),
        AwidoProvider(id: "fulda-stadt", title: "Stadt Fulda"),
        AwidoProvider(id: "kaufbeuren", title: "Stadt Kaufbeuren"),
        AwidoProvider(id: "koenigstein", title: "Stadt Königstein im Taunus"),
        AwidoProvider(id: "memmingen", title: "Stadt Memmingen"),
        AwidoProvider(id: "regensburg", title: "Stadt Regensburg"),
        AwidoProvider(id: "unterschleissheim", title: "Stadt Unterschleißheim"),
        AwidoProvider(id: "wgv", title: "WGV Recycling GmbH"),
        AwidoProvider(id: "zaso", title: "Zweckverband Abfallwirtschaft Saale-Orla"),
        AwidoProvider(id: "zv-muc-so", title: "Zweckverband München-Südost"),
    ]
}

/// Ein Eintrag aus den AWIDO-Auswahllisten (Ort, Straße, Hausnummer).
struct AwidoEntry: Identifiable, Hashable, Decodable {
    let key: String
    let value: String
    var id: String { key }
}

enum AwidoError: LocalizedError {
    case badResponse(Int)
    case emptyCalendar

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Das AWIDO-Portal hat mit Status \(code) geantwortet."
        case .emptyCalendar: return "Das AWIDO-Portal hat keine Termine für diese Adresse geliefert."
        }
    }
}

/// Zugriff auf das AWIDO-Portal, das u. a. der Landkreis Gifhorn für seinen Abfuhrkalender nutzt.
///
/// Ablauf: Ort wählen → Straße wählen → ggf. Hausnummer wählen → Termine laden.
/// Jede Auswahl liefert eine Objekt-ID (`oid`), mit der die nächste Stufe abgefragt wird.
struct AwidoClient {
    private let base = "https://awido.cubefour.de/WebServices/Awido.Service.svc/secure"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func places(customer: String) async throws -> [AwidoEntry] {
        try await get("\(base)/getPlaces/client=\(customer)")
    }

    func streets(customer: String, placeOid: String) async throws -> [AwidoEntry] {
        try await get("\(base)/getGroupedStreets/\(placeOid)?client=\(customer)")
    }

    /// Hausnummern einer Straße. Viele Kunden liefern nur einen Eintrag mit leerem Wert –
    /// dann ist keine Hausnummernauswahl nötig.
    func houseNumbers(customer: String, streetOid: String) async throws -> [AwidoEntry] {
        let entries: [AwidoEntry] = try await get("\(base)/getStreetAddons/\(streetOid)?client=\(customer)")
        return entries.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Lädt alle Abfuhrtermine für die gewählte Adresse.
    func pickups(customer: String, oid: String, calendar: Calendar = .current) async throws -> [ICSEvent] {
        let data: AwidoData = try await get("\(base)/getData/\(oid)?fractions=&client=\(customer)")
        let names = Dictionary(data.fracts.map { ($0.snm, AwidoClient.clean($0.nm)) }, uniquingKeysWith: { first, _ in first })

        var events: [ICSEvent] = []
        for item in data.calendar {
            // Feiertage stehen ebenfalls im Kalender, dann ist `ad` leer.
            guard let fractions = item.fr, item.ad != nil else { continue }
            guard let date = ICSParser.parseDate(item.dt, calendar: calendar) else { continue }
            for code in fractions {
                let name = names[code] ?? code
                events.append(ICSEvent(summary: name, date: date))
            }
        }
        guard !events.isEmpty else { throw AwidoError.emptyCalendar }
        var seen = Set<ICSEvent>()
        return events.filter { seen.insert($0).inserted }.sorted { $0.date < $1.date }
    }

    /// Entfernt HTML-Reste wie `&shy;` aus Fraktionsnamen.
    static func clean(_ name: String) -> String {
        name
            .replacingOccurrences(of: "&shy;", with: "")
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Intern

    private struct AwidoFraction: Decodable {
        let snm: String
        let nm: String
    }

    private struct AwidoCalendarItem: Decodable {
        let dt: String
        let fr: [String]?
        let ad: [String?]?
    }

    private struct AwidoData: Decodable {
        let fracts: [AwidoFraction]
        let calendar: [AwidoCalendarItem]
    }

    private func get<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AwidoError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
