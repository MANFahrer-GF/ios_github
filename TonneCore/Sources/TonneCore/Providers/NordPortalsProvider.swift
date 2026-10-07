import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Portale in Hamburg, Bremen, Niedersachsen und Schleswig-Holstein, die kein gemeinsames System nutzen.
/// `serviceKey` wählt den Betreiber:
/// - `hamburg`: Stadtreinigung Hamburg – Adresssuche, ICS je Hausnummer (`hnIds`)
/// - `bremerhaven`: BEG Bremerhaven/Cuxhaven – Formular mit Sitzung, Termine der nächsten 30 Tage
/// - `kiel`: ABK Kiel – JSON je Straße/Hausnummer
/// - `zvo`: ZVO Ostholstein – JSON-API (Ort, ggf. Straße)
/// - `wolfsburg`: WAS Wolfsburg – JSON-API mit Straßen- und Hausnummernliste
/// - `awigo`: AWIGO Landkreis Osnabrück – Ort → Straße → Hausnummer, ICS
/// - `osnabrueck`: OSB Stadt Osnabrück – Straßensuche, Termine aus der Ergebnistabelle
/// - `harburg`: Landkreis Harburg – Gebietsbaum, ICS je Abfuhrbezirk
/// - `ammerland`: AWB Ammerland – Datenpaket der App, Termine werden aus Rhythmen berechnet
/// - `helmstedt`: Landkreis Helmstedt – ICS je Gemeinde, Abfuhrgebiete je Abfallart
/// - `hildesheim`: ZAH Hildesheim – abfuhrkalender.de (ASP.NET), ICS je Straße
/// - `emden`: BEE Emden – ICS je Bezirk
/// - `delmenhorst`: Stadt Delmenhorst – ICS je Abfuhrbezirk und Altpapiertour
public struct NordPortalsProvider: WasteProvider {
    public let kind: ProviderKind = .portalsNord
    public let serviceKey: String
    public var displayName: String { Self.names[serviceKey] ?? kind.displayName }
    private let client: HTTPClient

    static let names: [String: String] = [
        "hamburg": "Stadtreinigung Hamburg",
        "bremerhaven": "BEG Bremerhaven",
        "kiel": "ABK Kiel",
        "zvo": "ZVO Ostholstein",
        "wolfsburg": "WAS Wolfsburg",
        "awigo": "AWIGO Landkreis Osnabrück",
        "osnabrueck": "OSB Osnabrück",
        "harburg": "Abfallwirtschaft Landkreis Harburg",
        "ammerland": "AWB Ammerland",
        "helmstedt": "Landkreis Helmstedt",
        "hildesheim": "ZAH Hildesheim",
        "emden": "BEE Emden",
        "delmenhorst": "Stadt Delmenhorst",
    ]

    public init(service: String, client: HTTPClient = HTTPClient()) {
        self.serviceKey = service
        self.client = client
    }

    public func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep? {
        switch serviceKey {
        case "hamburg": return try await hamburgStep(selections)
        case "bremerhaven": return try await bremerhavenStep(selections)
        case "kiel": return try await kielStep(selections)
        case "zvo": return try await zvoStep(selections)
        case "wolfsburg": return try await wolfsburgStep(selections)
        case "awigo": return try await awigoStep(selections)
        case "osnabrueck": return try await osnabrueckStep(selections)
        case "harburg": return try await harburgStep(selections)
        case "ammerland": return try await ammerlandStep(selections)
        case "helmstedt": return try await helmstedtStep(selections)
        case "hildesheim": return try await hildesheimStep(selections)
        case "emden": return try await emdenStep(selections)
        case "delmenhorst": return try await delmenhorstStep(selections)
        default: throw Self.unknown
        }
    }

    public func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        let result: [Pickup]
        switch serviceKey {
        case "hamburg": result = try await hamburgPickups(selections, calendar: calendar)
        case "bremerhaven": result = try await bremerhavenPickups(selections, calendar: calendar)
        case "kiel": result = try await kielPickups(selections, calendar: calendar)
        case "zvo": result = try await zvoPickups(selections, calendar: calendar)
        case "wolfsburg": result = try await wolfsburgPickups(selections, calendar: calendar)
        case "awigo": result = try await awigoPickups(selections, calendar: calendar)
        case "osnabrueck": result = try await osnabrueckPickups(selections, calendar: calendar)
        case "harburg": result = try await harburgPickups(selections, calendar: calendar)
        case "ammerland": result = try await ammerlandPickups(selections, calendar: calendar)
        case "helmstedt": result = try await helmstedtPickups(selections, calendar: calendar)
        case "hildesheim": result = try await hildesheimPickups(selections, calendar: calendar)
        case "emden": result = try await emdenPickups(selections, calendar: calendar)
        case "delmenhorst": result = try await delmenhorstPickups(selections, calendar: calendar)
        default: throw Self.unknown
        }
        let unique = Array(Set(result.filter { !WasteCategory.isIgnorableTitle($0.name) })).sorted {
            $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name
        }
        guard !unique.isEmpty else { throw ProviderError.noDataGeneric }
        return unique
    }

    public func label(for selections: [SelectionOption]) -> String {
        let titles = selections.map(\.title)
        func joined(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: ", ") }
        switch serviceKey {
        case "hamburg" where selections.count >= 3: return "Hamburg, \(titles[1]) \(titles[2])"
        case "kiel" where selections.count >= 3: return "Kiel, \(titles[1]) \(titles[2])"
        case "wolfsburg" where selections.count >= 2: return "Wolfsburg, \(titles[0]) \(titles[1])"
        case "bremerhaven" where selections.count >= 3:
            // „Hafenstraße, Bremerhaven“ → „Bremerhaven, Hafenstraße 2“
            let parts = titles[1].components(separatedBy: ", ")
            let street = parts.first ?? titles[1]
            let town = parts.count > 1 ? parts[parts.count - 1] : "Bremerhaven"
            return "\(town), \(street) \(titles[2])".trimmingCharacters(in: .whitespaces)
        case "awigo" where selections.count >= 3:
            let town = titles[0].replacingOccurrences(of: #"\s*\(\d+\)"#, with: "", options: .regularExpression)
            return "\(town), \(titles[1]) \(titles[2])"
        case "osnabrueck": return joined(["Osnabrück"] + titles)
        case "emden": return joined(["Emden"] + titles)
        case "delmenhorst": return joined(["Delmenhorst"] + titles)
        case "hildesheim" where selections.count >= 3: return joined([titles[0], titles[2]])
        case "harburg", "ammerland", "helmstedt":
            // Zusatzschritte (Rhythmus, Abfuhrgebiet) gehören nicht zur Adresse.
            return joined(selections.filter { !$0.id.hasPrefix("rhythm:") && !$0.id.hasPrefix("vier:") && !$0.id.contains("|") }.map(\.title))
        default: return joined(titles)
        }
    }

    // MARK: - Gemeinsame Helfer

    static var unknown: ProviderError {
        .notSupported(L10n.t("Dieser Betreiber wird nicht unterstützt.", "This operator is not supported."))
    }

    static var streetNotFound: ProviderError {
        .invalidSelection(L10n.t("Keine passende Straße gefunden. Bitte den Anfang des Straßennamens prüfen.",
                                 "No matching street found. Please check the beginning of the street name."))
    }

    static var streetSearchStep: SelectionStep {
        .text(title: SelectionStep.streetTitle, placeholder: L10n.t("Anfang des Straßennamens", "Beginning of the street name"))
    }

    static func sorted(_ options: [SelectionOption]) -> [SelectionOption] {
        var seen = Set<String>()
        return options.filter { !$0.title.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// „13.01.2026“ (auch mitten im Text) → Tagesanfang.
    static func germanDate(_ text: String, calendar: Calendar) -> Date? {
        guard let m = HTMLText.matches(#"(\d{1,2})\.(\d{1,2})\.(\d{4})"#, in: text).first,
              let day = Int(m[0]), let month = Int(m[1]), let year = Int(m[2]) else { return nil }
        return Days.parse(String(format: "%04d-%02d-%02d", year, month, day), calendar: calendar)
    }

    static func currentYear(_ calendar: Calendar) -> Int { calendar.component(.year, from: Date()) }

    static func jsonObject(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data) }

    private func ics(_ url: String, calendar: Calendar) async -> [ICSEvent] {
        guard let text = try? await client.string(url) else { return [] }
        return ICS.parse(text, calendar: calendar)
    }

    private func postJSON(_ url: String, _ body: [String: Any]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await client.post(url, body: data, contentType: "application/json", headers: ["Accept": "application/json"])
    }

    // MARK: - Stadtreinigung Hamburg

    private static let srhSearch = "https://www.stadtreinigung.hamburg/abfuhrkalender?tx_srh_pickups%5Baction%5D=addresses&tx_srh_pickups%5Bcontroller%5D=PickUps&type=10002"
    private struct SRHStreet: Decodable { let asId: Int; let name: String; let hnIds: [SRHNumber] }
    private struct SRHNumber: Decodable { let hnId: Int; let name: String }

    /// Adresssuche des Abfuhrkalenders (Präfixsuche, höchstens 50 Straßen).
    private func srhStreets(_ query: String) async throws -> [SRHStreet] {
        let data = try await client.postForm(Self.srhSearch, fields: [("tx_srh_pickups[street]", query), ("tx_srh_pickups[limit]", "50")])
        return try HTTPClient.decode(data)
    }

    private func hamburgStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            return Self.streetSearchStep
        case 1:
            let query = s[0].title.trimmingCharacters(in: .whitespaces)
            guard query.count >= 3 else {
                throw ProviderError.invalidSelection(L10n.t("Bitte mindestens drei Buchstaben eingeben.", "Please enter at least three letters."))
            }
            let streets = try await srhStreets(query)
            guard !streets.isEmpty else { throw Self.streetNotFound }
            return SelectionStep(title: SelectionStep.streetTitle,
                                 options: Self.sorted(streets.map { SelectionOption(id: String($0.asId), title: $0.name) }))
        case 2:
            let street = try await srhStreets(s[1].title).first { String($0.asId) == s[1].id }
            let numbers = (street?.hnIds ?? []).map { SelectionOption(id: String($0.hnId), title: $0.name) }
            guard !numbers.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sorted(numbers))
        default:
            return nil
        }
    }

    private func hamburgPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 3, Int(s[2].id) != nil else { throw ProviderError.selectAddressFirst }
        let url = "https://backend.stadtreinigung.hamburg/kalender/abholtermine.ics?hnIds=\(s[2].id)&adresse=MeineAdresse"
        return await ics(url, calendar: calendar).map { event in
            // „Abfuhr schwarze Restmülltonne“ → „schwarze Restmülltonne“ → „Schwarze Restmülltonne“
            var name = event.summary.replacingOccurrences(of: #"^Abfuhr\s+"#, with: "", options: .regularExpression)
            name = name.prefix(1).uppercased() + name.dropFirst()
            return Pickup(date: event.date, name: NameCleaner.clean(name))
        }
    }

    // MARK: - BEG Bremerhaven

    private static let begBase = "https://kalender.beg-logistics.de"

    private func bremerhavenStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            return Self.streetSearchStep
        case 1:
            let data = try await client.get("\(Self.begBase)/auto_complete/streets.json?term=\(HTTPClient.query(s[0].title.trimmingCharacters(in: .whitespaces)))",
                                            headers: ["Accept": "application/json"])
            let streets: [String] = (try? HTTPClient.decode(data)) ?? []
            guard !streets.isEmpty else { throw Self.streetNotFound }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sorted(streets.map { SelectionOption(id: $0, title: $0) }))
        case 2:
            return .text(title: SelectionStep.houseNumberTitle, placeholder: L10n.t("z. B. 12", "e.g. 12"))
        default:
            return nil
        }
    }

    /// Abruf mit gesetztem Sitzungs-Cookie; liefert auch die Antwort-Header. Das Cookie wird selbst
    /// weitergereicht, weil FoundationNetworking (Linux) `Set-Cookie` nicht zuverlässig übernimmt.
    private static func begRequest(_ path: String, cookie: String?, form: [(String, String)]? = nil) async throws -> (html: String, setCookie: String?) {
        guard let url = URL(string: begBase + path) else { throw HTTPError.badURL(path) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let form {
            request.httpMethod = "POST"
            request.httpBody = Data(form.map { "\(HTTPClient.formEncode($0.0))=\(HTTPClient.formEncode($0.1))" }.joined(separator: "&").utf8)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode, url.host ?? "Server")
        }
        return (HTTPClient.text(from: data), (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie"))
    }

    /// Das Portal arbeitet mit Rails-Sitzung (Cookie + Token) und zeigt nur die Termine der nächsten 30 Tage.
    private func bremerhavenPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 3 else { throw ProviderError.selectAddressFirst }
        let start = try await Self.begRequest("/sessions/new", cookie: nil)
        guard let token = HTMLText.firstMatch(#"name="authenticity_token" type="hidden" value="([^"]*)""#, in: start.html, group: 1),
              let cookie = start.setCookie.flatMap({ HTMLText.firstMatch(#"(_abfuhr_session[^=;]*=[^;]+)"#, in: $0, group: 1) }) else {
            throw ProviderError.noDataGeneric
        }
        let html: String
        do {
            html = try await Self.begRequest("/sessions", cookie: cookie, form: [
                ("utf8", "✓"), ("authenticity_token", HTMLText.decodeEntities(token)),
                ("session[street]", s[1].id), ("session[number]", s[2].title.trimmingCharacters(in: .whitespaces)),
                ("session[two_weeks]", "0"), ("session[selection]", "abfuhrtermine"), ("commit", "weiter"),
            ]).html
        } catch HTTPError.status(404, _) {
            // Unbekannte Adressen leitet das Portal auf eine Fehlerseite um.
            throw ProviderError.invalidSelection(L10n.t("Diese Hausnummer kennt das Portal nicht.", "The portal does not know this house number."))
        }
        var result: [Pickup] = []
        for day in HTMLText.matches(#"<li class="day">([\s\S]*?)</li>"#, in: html) {
            guard let date = Self.germanDate(day[0], calendar: calendar) else { continue }
            for alt in HTMLText.matches(#"alt="([^"]+)""#, in: day[0]) {
                // „Graue tonne“ → „Graue Tonne“
                let name = alt[0].split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                result.append(Pickup(date: date, name: NameCleaner.clean(HTMLText.decodeEntities(name))))
            }
        }
        return result
    }

    // MARK: - ABK Kiel

    private static let abkBase = "https://abki.de/abki-services"
    private struct ABKStreet: Decodable { let IDSTREET: String; let Strasse: String }
    private struct ABKNumber: Decodable { let id: String; let IDSTANDORT: String; let NUMBER: String }
    private struct ABKDates: Decodable { let termine: [ABKType]? }
    private struct ABKType: Decodable { let titel: String; let list: [ABKDate] }
    private struct ABKDate: Decodable { let VALUE: String }

    private func kielStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            return Self.streetSearchStep
        case 1:
            let q = HTTPClient.query(s[0].title.trimmingCharacters(in: .whitespaces))
            let filter = "filter%5Blogic%5D=and&filter%5Bfilters%5D%5B0%5D%5Bvalue%5D=\(q)&filter%5Bfilters%5D%5B0%5D%5Bfield%5D=Strasse"
                + "&filter%5Bfilters%5D%5B0%5D%5Boperator%5D=startswith&filter%5Bfilters%5D%5B0%5D%5BignoreCase%5D=true"
            let streets: [ABKStreet] = try await client.json("\(Self.abkBase)/strassennamen?\(filter)")
            guard !streets.isEmpty else { throw Self.streetNotFound }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sorted(streets.map { SelectionOption(id: $0.IDSTREET, title: $0.Strasse) }))
        case 2:
            let numbers: [ABKNumber] = try await client.json("\(Self.abkBase)/streetnumber?IDSTREET=\(HTTPClient.query(s[1].id))")
            let options = numbers.map { SelectionOption(id: "\($0.id)|\($0.IDSTANDORT)", title: $0.NUMBER.trimmingCharacters(in: .whitespaces)) }
            guard !options.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sorted(options))
        default:
            return nil
        }
    }

    private func kielPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 3 else { throw ProviderError.selectAddressFirst }
        let ids = s[2].id.components(separatedBy: "|")
        guard ids.count == 2 else { throw ProviderError.selectAddressFirst }
        let year = Self.currentYear(calendar)
        var result: [Pickup] = []
        for target in [year, year + 1] {
            let url = "\(Self.abkBase)/leerungen-data?Zeitraum=\(target)&Strasse_input=\(HTTPClient.query(s[1].title))&Strasse=\(s[1].id)"
                + "&IDSTANDORT_input=\(HTTPClient.query(s[2].title))&IDSTANDORT=\(ids[1])&Hausnummernwahl=\(ids[0])"
            guard let answer: ABKDates = try? await client.json(url) else { continue }
            for type in answer.termine ?? [] {
                for entry in type.list {
                    if let date = Self.germanDate(entry.VALUE, calendar: calendar) {
                        result.append(Pickup(date: date, name: NameCleaner.clean(type.titel)))
                    }
                }
            }
        }
        return result
    }

    // MARK: - ZVO Ostholstein

    private static let zvoAPI = "https://www.zvo.com/api/wastecollection"
    private struct ZVOPlace: Decodable { let id: Int; let name: String; let zipcode: String? }
    private struct ZVOCollection: Decodable { let id: Int; let tstamp: Int; let color: Int }
    private struct ZVODate: Decodable { let color: Int; let collect_date: ZVOStamp }
    private struct ZVOStamp: Decodable { let date: String }

    private func zvoStreets(city: String) async throws -> [ZVOPlace] {
        guard let id = Int(city) else { throw ProviderError.selectAddressFirst }
        return try HTTPClient.decode(try await postJSON("\(Self.zvoAPI)/streets", ["city": id]))
    }

    private func zvoStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let places: [ZVOPlace] = try await client.json("\(Self.zvoAPI)/cities")
            let options = places.map { SelectionOption(id: String($0.id), title: $0.name, subtitle: ($0.zipcode ?? "0") == "0" ? nil : $0.zipcode) }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sorted(options))
        case 1:
            // Kleine Orte haben keine Straßenliste – dann gilt der ganze Ort.
            let streets = try await zvoStreets(city: s[0].id)
            guard !streets.isEmpty else { return nil }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sorted(streets.map { SelectionOption(id: String($0.id), title: $0.name) }))
        default:
            return nil
        }
    }

    /// Restmüll, Bio und Gelbe Tonne kommen an jedem Termin, die Papiertonne nur an Terminen
    /// in der Farbe des Abfuhrplans (wie im Kalender-Widget des ZVO).
    private func zvoPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let city = s.first.flatMap({ Int($0.id) }) else { throw ProviderError.selectAddressFirst }
        let street = s.count > 1 ? Int(s[1].id) ?? 0 : 0
        let plans: [ZVOCollection] = try HTTPClient.decode(try await postJSON("\(Self.zvoAPI)/wastecollection", ["city": city, "street": street]))
        guard let plan = plans.max(by: { $0.tstamp < $1.tstamp }) else { throw ProviderError.noDataGeneric }
        let dates: [ZVODate] = try HTTPClient.decode(try await postJSON("\(Self.zvoAPI)/wastecollectiondates", ["collection": plan.id]))
        let from = calendar.date(from: DateComponents(year: Self.currentYear(calendar), month: 1, day: 1)) ?? Date()
        var result: [Pickup] = []
        for entry in dates {
            guard let date = Days.parse(String(entry.collect_date.date.prefix(10)), calendar: calendar), date >= from else { continue }
            for name in ["Restmülltonne", "Biotonne", "Gelbe Tonne"] { result.append(Pickup(date: date, name: name)) }
            if entry.color == plan.color { result.append(Pickup(date: date, name: "Papiertonne")) }
        }
        return result
    }

    // MARK: - WAS Wolfsburg

    private static let wasAPI = "https://abfuhrtermine.waswob.de/php/abfuhr_api.php"

    /// Straßenname → Hausnummern.
    private func wolfsburgStreets() async throws -> [String: [String]] {
        let data = try await client.get("\(Self.wasAPI)?action=strassen", headers: ["Accept": "application/json"])
        guard let dict = Self.jsonObject(data) as? [String: Any] else { throw ProviderError.noDataGeneric }
        var result: [String: [String]] = [:]
        for case let entry as [String: Any] in dict.values {
            guard let name = entry["strName"] as? String else { continue }
            let numbers = (entry["Hausnummer"] as? [Any] ?? []).map { "\($0)" }
            result[name, default: []].append(contentsOf: numbers)
        }
        return result
    }

    private func wolfsburgStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        switch s.count {
        case 0:
            let streets = try await wolfsburgStreets()
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sorted(streets.keys.map { SelectionOption(id: $0, title: $0) }))
        case 1:
            let numbers = try await wolfsburgStreets()[s[0].id] ?? []
            guard !numbers.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.houseNumberTitle, options: Self.sorted(numbers.map { SelectionOption(id: $0, title: $0) }))
        default:
            return nil
        }
    }

    private func wolfsburgPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 2 else { throw ProviderError.selectAddressFirst }
        let url = "\(Self.wasAPI)?action=termine&strasse=\(HTTPClient.query(s[0].id))&hausnummer=\(HTTPClient.query(s[1].id))"
        let data = try await client.get(url, headers: ["Accept": "application/json"])
        guard let root = Self.jsonObject(data) else { throw ProviderError.noDataGeneric }
        var result: [Pickup] = []
        // Antwort: Adresse → behaelter → Tonnengröße → Abfallart → {Datum: Hinweis}. Rekursiv suchen,
        // damit auch die ältere flache Form ohne „behaelter“ funktioniert.
        func walk(_ node: Any, name: String) {
            guard let dict = node as? [String: Any] else { return }
            for (key, value) in dict {
                if let date = Days.parse(key, calendar: calendar), key.count == 10 {
                    result.append(Pickup(date: date, name: NameCleaner.clean(name), note: (value as? String).flatMap { $0.isEmpty ? nil : $0 }))
                } else {
                    walk(value, name: key)
                }
            }
        }
        walk(root, name: "")
        return result
    }

    // MARK: - AWIGO Landkreis Osnabrück

    /// Immer alle Abfallarten anfragen – mit nur einer liefert das Portal eine leere ICS-Datei.
    private static let awigoBase = "https://www.awigo.de/index.php?legacy_eID=awigoCalendar"
        + "&calendar%5Brest%5D=1&calendar%5Bpaper%5D=1&calendar%5Byellow%5D=1&calendar%5Bbrown%5D=1&calendar%5Bmobile%5D=1"

    private func awigo(_ method: String, _ ids: [(String, String)]) async throws -> String {
        var url = Self.awigoBase + "&calendar%5Bmethod%5D=\(method)"
        for (key, value) in ids { url += "&calendar%5B\(key)%5D=\(HTTPClient.query(value))" }
        return HTTPClient.text(from: try await client.post(url, body: Data(), contentType: "application/x-www-form-urlencoded"))
    }

    private static func awigoOptions(_ html: String) -> [SelectionOption] {
        HTMLText.matches(#"<option value="(\d+)"[^>]*>([^<]*)</option>"#, in: html).map {
            SelectionOption(id: $0[0], title: HTMLText.decodeEntities($0[1]).trimmingCharacters(in: .whitespaces))
        }
    }

    private func awigoStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        let options: [SelectionOption]
        let title: String
        switch s.count {
        case 0:
            options = Self.awigoOptions(try await awigo("getCities", []))
            title = SelectionStep.cityTitle
        case 1:
            options = Self.awigoOptions(try await awigo("getStreets", [("cityID", s[0].id)]))
            title = SelectionStep.streetTitle
        case 2:
            options = Self.awigoOptions(try await awigo("getNumbers", [("cityID", s[0].id), ("streetID", s[1].id)]))
            title = SelectionStep.houseNumberTitle
        default:
            return nil
        }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: title, options: Self.sorted(options))
    }

    private func awigoPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 3 else { throw ProviderError.selectAddressFirst }
        let link = try await awigo("getICSfile", [("cityID", s[0].id), ("streetID", s[1].id), ("locationID", s[2].id)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.hasPrefix("https://") else { throw ProviderError.noDataGeneric }
        return await ics(link, calendar: calendar).map {
            Pickup(date: $0.date, name: NameCleaner.clean($0.summary.replacingOccurrences(of: "wird abgeholt.", with: "")))
        }
    }

    // MARK: - OSB Osnabrück

    private static let osbPage = "https://nachhaltig.osnabrueck.de/de/abfall/muellabfuhr/muellabfuhr-digital/online-abfuhrkalender/"

    private func osnabrueckStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        guard s.isEmpty else { return nil }
        let html = try await client.string(Self.osbPage)
        let list = HTMLText.firstMatch(#"<datalist id="waste-collection-street-list">([\s\S]*?)</datalist>"#, in: html, group: 1) ?? ""
        let streets = HTMLText.matches(#"<option>([^<]+)</option>"#, in: list).map { HTMLText.decodeEntities($0[0]).trimmingCharacters(in: .whitespaces) }
        guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: SelectionStep.streetTitle, options: Self.sorted(streets.map { SelectionOption(id: $0, title: $0) }))
    }

    /// Das Formular liefert eine Tabelle je Jahr („<h4>2026</h4>“) mit Zellen „Di 13.10.“ und der Abfallart im `title`.
    private func osnabrueckPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let street = s.first?.id else { throw ProviderError.selectAddressFirst }
        let page = try await client.string(Self.osbPage)
        guard let start = page.range(of: "class=\"waste-collection-form\"") else { throw ProviderError.noDataGeneric }
        let formHTML = String(page[start.lowerBound...]).components(separatedBy: "</form>").first ?? ""
        var fields = HTMLText.hiddenInputs(in: formHTML).map { ($0.name, $0.value) }
        fields.append(("tx_ytosn_wastecollection[street]", street))
        let html = HTTPClient.text(from: try await client.postForm(Self.osbPage, fields: fields))
        var result: [Pickup] = []
        let sections = html.components(separatedBy: "<h4>").dropFirst()
        for section in sections {
            guard let year = Int(section.prefix(4)), section.dropFirst(4).hasPrefix("</h4>") else { continue }
            for cell in HTMLText.matches(#"<td title="([^"]+)"[^>]*>\s*\S+\s+(\d{1,2})\.(\d{1,2})\."#, in: section) {
                guard let day = Int(cell[1]), let month = Int(cell[2]),
                      let date = Days.parse(String(format: "%04d-%02d-%02d", year, month, day), calendar: calendar) else { continue }
                for name in Self.splitCombined(HTMLText.decodeEntities(cell[0])) {
                    result.append(Pickup(date: date, name: name))
                }
            }
        }
        return result
    }

    /// „Restmüll- und Altpapiertonne“ → [„Restmülltonne“, „Altpapiertonne“],
    /// „Altpapier und Altglas“ → [„Altpapier“, „Altglas“].
    static func splitCombined(_ title: String) -> [String] {
        let parts = title.components(separatedBy: " und ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count > 1, let last = parts.last else { return [NameCleaner.clean(title)] }
        let suffix = ["tonne", "sack"].first { last.lowercased().hasSuffix($0) }
        return parts.map { part in
            if part.hasSuffix("-"), let suffix { return NameCleaner.clean(String(part.dropLast()) + suffix) }
            return NameCleaner.clean(part)
        }
    }

    // MARK: - Landkreis Harburg

    private static let harburgBase = "https://www.landkreis-harburg.de"
    private static let harburgLevelTitles = [L10n.t("Gemeinde", "Municipality"), SelectionStep.cityTitle, SelectionStep.streetTitle, L10n.t("Bereich", "Area")]

    private func harburgLevel(parent: String?, depth: Int) async throws -> [SelectionOption] {
        var html: String
        if let parent {
            html = try await client.string("\(Self.harburgBase)/ajax/abfall_gebiete_struktur_select.html?parent=\(parent)&ebene=\(depth)&portal=1&selected_ebene=0")
        } else {
            // Beim ersten Aufruf zeigt die Seite manchmal einen Hinweis statt des Formulars.
            html = try await client.string("\(Self.harburgBase)/bauen-umwelt/abfallwirtschaft/abfallkalender/")
            if !html.contains("strukturEbene1") {
                html = try await client.string("\(Self.harburgBase)/bauen-umwelt/abfallwirtschaft/abfallkalender/")
            }
        }
        return HTMLText.options(ofSelect: "strukturEbene\(depth + 1)", in: html)
            .filter { $0.value != "0" && !$0.value.isEmpty }
            .map { SelectionOption(id: $0.value, title: $0.label.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)) }
    }

    private func harburgEvents(area: String, calendar: Calendar) async throws -> [ICSEvent] {
        let html = try await client.string("\(Self.harburgBase)/abfallkalender/abfallkalender_struktur_daten_suche.html?selected_ebene=\(area)&owner=20100")
        // Zum Jahreswechsel gibt es mehrere iCal-Links (je Jahr einen).
        let links = Set(HTMLText.matches(#"href='([^']*icalendar/ical\.html[^']*)'"#, in: html).map { HTMLText.decodeEntities($0[0]) })
        var events: [ICSEvent] = []
        for link in links.sorted() { events += await ics(link, calendar: calendar) }
        return events
    }

    private func harburgStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        if s.last?.id.hasPrefix("rhythm:") == true { return nil }
        if s.count < 4 {
            let options = try await harburgLevel(parent: s.last?.id, depth: s.count)
            if !options.isEmpty {
                return SelectionStep(title: Self.harburgLevelTitles[s.count], options: s.isEmpty ? options : Self.sorted(options))
            }
            if s.isEmpty { throw ProviderError.noDataGeneric }
        }
        // Gibt es im Bezirk mehrere Hausmüll-Rhythmen, fragen wir nach der eigenen Tonne.
        guard let area = s.last?.id else { return nil }
        let variants = Set(try await harburgEvents(area: area, calendar: .current).map(\.summary).filter { $0.hasPrefix("Hausmüll") })
        guard variants.count > 1 else { return nil }
        var options = variants.sorted().map { SelectionOption(id: "rhythm:\($0)", title: $0) }
        options.append(SelectionOption(id: "rhythm:*", title: L10n.t("Alle anzeigen", "Show all")))
        return SelectionStep(title: L10n.t("Hausmüll-Rhythmus", "Residual waste interval"), options: options, searchable: false)
    }

    private func harburgPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let area = s.last(where: { !$0.id.hasPrefix("rhythm:") })?.id else { throw ProviderError.selectAddressFirst }
        let rhythm = s.last.flatMap { $0.id.hasPrefix("rhythm:") ? String($0.id.dropFirst(7)) : nil } ?? "*"
        return try await harburgEvents(area: area, calendar: calendar)
            .filter { rhythm == "*" || !$0.summary.hasPrefix("Hausmüll") || $0.summary == rhythm }
            .map { Pickup(date: $0.date, name: NameCleaner.clean($0.summary)) }
    }

    // MARK: - AWB Ammerland

    private static let ammerlandURL = "https://firebasestorage.googleapis.com/v0/b/abfall-ammerland.appspot.com/o/and%2F7%2Fawbapp.json?alt=media"
    private static let ammerlandTowns = ["1": "Apen", "2": "Bad Zwischenahn", "3": "Edewecht", "4": "Rastede", "5": "Westerstede", "6": "Wiefelstede"]

    private struct AWBStreet: Decodable { let id: Int; let ortid: Int; let bez: String }
    private struct AWBSection: Decodable { let id: Int; let strid: Int; let grenze: String }
    private struct AWBPlan: Decodable {
        let strid: Int; let strgrid: Int; let jahr: Int
        let resttag: Int; let restgu: Bool; let vier: Bool
        let biotag: Int; let biogu: Bool; let werttag: Int; let wertgu: Bool; let papier: Int
    }
    private struct AWBAst: Decodable { let strid: Int; let astgrid: Int; let ast: Int }
    private struct AWBDay: Decodable { let datum: String; let gu: Bool; let vier: Bool; let papier: Int }
    private struct AWBAstDay: Decodable { let ortid: Int; let datum: String; let ast: Int }
    private struct AWBTownDay: Decodable { let ortid: Int; let datum: String }
    private struct AWBShift: Decodable { let datum: String; let fdatum: String }

    /// Datenpaket der App: zwölf JSON-Listen, getrennt durch „##“.
    private struct AWBData {
        let streets: [AWBStreet]; let sections: [AWBSection]; let plans: [AWBPlan]; let asts: [AWBAst]
        let days: [AWBDay]; let astDays: [AWBAstDay]; let problemDays: [AWBTownDay]; let shifts: [AWBShift]
    }

    private func ammerlandData() async throws -> AWBData {
        let text = try await client.string(Self.ammerlandURL)
        let blocks = text.components(separatedBy: "##").map { Data($0.utf8) }
        guard blocks.count >= 9 else { throw ProviderError.noDataGeneric }
        return AWBData(streets: try HTTPClient.decode(blocks[0]), sections: try HTTPClient.decode(blocks[1]),
                       plans: try HTTPClient.decode(blocks[3]), asts: try HTTPClient.decode(blocks[4]),
                       days: try HTTPClient.decode(blocks[5]), astDays: try HTTPClient.decode(blocks[6]),
                       problemDays: try HTTPClient.decode(blocks[7]), shifts: try HTTPClient.decode(blocks[8]))
    }

    private func ammerlandStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        if s.isEmpty {
            let towns = Self.ammerlandTowns.map { SelectionOption(id: $0.key, title: $0.value) }
            return SelectionStep(title: SelectionStep.cityTitle, options: Self.sorted(towns), searchable: false)
        }
        if s.contains(where: { $0.id.hasPrefix("vier:") }) { return nil }
        if s.count == 1 {
            let data = try await ammerlandData()
            let streets = data.streets.filter { String($0.ortid) == s[0].id }.map { SelectionOption(id: String($0.id), title: $0.bez) }
            guard !streets.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: SelectionStep.streetTitle, options: Self.sorted(streets))
        }
        if s.count == 2 {
            let data = try await ammerlandData()
            let sections = data.sections.filter { String($0.strid) == s[1].id }
            if !sections.isEmpty {
                return SelectionStep(title: L10n.t("Straßenabschnitt", "Street section"),
                                     options: sections.map { SelectionOption(id: "sec:\($0.id)", title: $0.grenze) }, searchable: false)
            }
        }
        return SelectionStep(title: L10n.t("Restabfall-Rhythmus", "Residual waste interval"), options: [
            SelectionOption(id: "vier:0", title: L10n.t("14-täglich", "Every two weeks")),
            SelectionOption(id: "vier:1", title: L10n.t("4-wöchentlich (auf Antrag)", "Every four weeks (on request)")),
        ], searchable: false)
    }

    /// Nachbau der App-Logik: Ein Tag aus dem Referenzkalender gilt, wenn Wochentag und gerade/ungerade Woche
    /// zum Abfuhrplan der Straße passen; Papier hat eigene Tour-Nummern, Feiertage werden verschoben.
    private func ammerlandPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 2, let ortid = Int(s[0].id), let strid = Int(s[1].id) else { throw ProviderError.selectAddressFirst }
        let section = s.first { $0.id.hasPrefix("sec:") }.flatMap { Int($0.id.dropFirst(4)) } ?? 0
        let fourWeekly = s.contains { $0.id == "vier:1" }
        let data = try await ammerlandData()
        let year = Self.currentYear(calendar) - 2000
        let candidates = data.plans.filter { $0.strid == strid && $0.strgrid == section }
        guard let plan = candidates.filter({ $0.jahr <= year }).max(by: { $0.jahr < $1.jahr }) ?? candidates.max(by: { $0.jahr < $1.jahr }) else {
            throw ProviderError.noDataGeneric
        }
        let ast = (data.asts.first { $0.strid == strid && $0.astgrid == section } ?? data.asts.first { $0.strid == strid && $0.astgrid == 0 })?.ast
        let shifts = Dictionary(data.shifts.map { ($0.datum, $0.fdatum) }, uniquingKeysWith: { a, _ in a })
        let from = calendar.date(from: DateComponents(year: Self.currentYear(calendar), month: 1, day: 1)) ?? Date()
        func day(_ iso: String) -> Date? {
            guard let date = Days.parse(shifts[iso] ?? iso, calendar: calendar), date >= from else { return nil }
            return date
        }
        var result: [Pickup] = []
        for entry in data.days {
            guard let raw = Days.parse(entry.datum, calendar: calendar), let date = day(entry.datum) else { continue }
            let weekday = calendar.component(.weekday, from: raw) - 1 // Sonntag = 0 wie in der App
            if weekday == plan.resttag && entry.gu == plan.restgu && (!fourWeekly || entry.vier == plan.vier) {
                result.append(Pickup(date: date, name: "Restabfall"))
            }
            if weekday == plan.biotag && entry.gu == plan.biogu { result.append(Pickup(date: date, name: "Bioabfall")) }
            if weekday == plan.werttag && entry.gu == plan.wertgu { result.append(Pickup(date: date, name: "Gelber Sack")) }
            if entry.papier != 0 && entry.papier == plan.papier { result.append(Pickup(date: date, name: "Papier")) }
        }
        if let ast {
            for entry in data.astDays where entry.ortid == ortid && entry.ast == ast {
                if let date = day(entry.datum) { result.append(Pickup(date: date, name: "Ast- und Strauchwerk")) }
            }
        }
        for entry in data.problemDays where entry.ortid == ortid {
            if let date = day(entry.datum) { result.append(Pickup(date: date, name: "Problemstoffe")) }
        }
        return result
    }

    // MARK: - Landkreis Helmstedt

    private static let helmstedtPage = "https://www.landkreis-helmstedt.de/portal/seiten/abfuhrkalender-900000002-34150.html?vs=1"

    /// ICS-Dateien der Seite: Gemeinde (ohne Jahr) → Links.
    private func helmstedtCalendars() async throws -> [String: [String]] {
        let html = try await client.string(Self.helmstedtPage)
        let pattern = #"<a href="([^"]+)"[^>]*title="herunterladen/öffnen">([^<]+)</a>[\s\S]*?Dateiendung:\s*</td>\s*<td class="dokumente_inhalt">\.?(\w+)</td>"#
        var result: [String: [String]] = [:]
        for m in HTMLText.matches(pattern, in: html) where m[2].lowercased() == "ics" {
            let name = HTMLText.decodeEntities(m[1])
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s*\d{4}\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            result[name, default: []].append(HTMLText.decodeEntities(m[0]))
        }
        return result
    }

    /// „Altpapier 2“ → („Altpapier“, „2“).
    static func areaSplit(_ summary: String) -> (type: String, area: String?) {
        guard let m = HTMLText.matches(#"^(.*\S)\s+(\d+)$"#, in: summary).first else { return (summary, nil) }
        return (m[0], m[1])
    }

    private func helmstedtEvents(_ town: String, calendar: Calendar) async throws -> [ICSEvent] {
        guard let links = try await helmstedtCalendars()[town], !links.isEmpty else { throw ProviderError.noDataGeneric }
        var events: [ICSEvent] = []
        for link in links { events += await ics(link, calendar: calendar) }
        return events
    }

    private func helmstedtStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        guard let town = s.first?.id else {
            let towns = try await helmstedtCalendars().keys.map { SelectionOption(id: $0, title: $0) }
            guard !towns.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Gemeinde", "Municipality"), options: Self.sorted(towns), searchable: false)
        }
        // Je Abfallart mit mehreren Abfuhrgebieten das eigene Gebiet erfragen (Nummer steht im PDF-Kalender).
        var areas: [String: Set<String>] = [:]
        var order: [String] = []
        for event in try await helmstedtEvents(town, calendar: .current) {
            let (type, area) = Self.areaSplit(event.summary)
            guard let area else { continue }
            if areas[type] == nil { order.append(type) }
            areas[type, default: []].insert(area)
        }
        let answered = Set(s.dropFirst().compactMap { $0.id.components(separatedBy: "|").first })
        guard let type = order.first(where: { (areas[$0]?.count ?? 0) > 1 && !answered.contains($0) }) else { return nil }
        let options = (areas[type] ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map {
            SelectionOption(id: "\(type)|\($0)", title: L10n.t("Gebiet \($0)", "Area \($0)"), subtitle: type)
        }
        return SelectionStep(title: L10n.t("Abfuhrgebiet \(type) (siehe PDF-Kalender)", "Collection area \(type) (see PDF calendar)"),
                             options: options, searchable: false)
    }

    private func helmstedtPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let town = s.first?.id else { throw ProviderError.selectAddressFirst }
        var chosen: [String: String] = [:]
        for option in s.dropFirst() {
            let parts = option.id.components(separatedBy: "|")
            if parts.count == 2 { chosen[parts[0]] = parts[1] }
        }
        return try await helmstedtEvents(town, calendar: calendar).compactMap { event in
            let (type, area) = Self.areaSplit(event.summary)
            if let area, let wanted = chosen[type], wanted != area { return nil }
            return Pickup(date: event.date, name: NameCleaner.clean(type))
        }
    }

    // MARK: - ZAH Hildesheim (abfuhrkalender.de)

    private static let hildesheimBase = "https://hildesheim.abfuhrkalender.de/"

    /// ASP.NET-Formular: Gemeinde und Ortsteil werden per Postback gewählt, danach ist die Straßenliste gefüllt.
    private func hildesheimPage(town: String?, district: String?) async throws -> String {
        var html = try await client.string(Self.hildesheimBase)
        func postBack(_ target: String, _ values: [(String, String)]) async throws {
            let own = Set(values.map(\.0) + ["__EVENTTARGET", "__EVENTARGUMENT"])
            var fields = HTMLText.hiddenInputs(in: html).filter { !own.contains($0.name) }.map { ($0.name, $0.value) }
            fields += [("__EVENTTARGET", target), ("__EVENTARGUMENT", "")] + values
            html = HTTPClient.text(from: try await client.postForm(Self.hildesheimBase, fields: fields))
        }
        if let town {
            try await postBack("ddGemeinde", [("ddGemeinde", town)])
            if let district { try await postBack("ddOrtsteil", [("ddGemeinde", town), ("ddOrtsteil", district)]) }
        }
        return html
    }

    private func hildesheimStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        let select: String
        let title: String
        switch s.count {
        case 0: select = "ddGemeinde"; title = L10n.t("Gemeinde", "Municipality")
        case 1: select = "ddOrtsteil"; title = SelectionStep.districtTitle
        case 2: select = "ddStrasse"; title = SelectionStep.streetTitle
        case 3:
            // Restabfall gibt es 14-täglich oder (auf Antrag) 4-wöchentlich; nur fragen, wenn der Kalender beides kennt.
            let events = await hildesheimEvents(street: s[2].id, calendar: .current)
            guard events.contains(where: { $0.summary.contains("vierwöchentlich") }) else { return nil }
            return SelectionStep(title: L10n.t("Restabfall-Rhythmus", "Residual waste interval"), options: [
                SelectionOption(id: "rest:14", title: L10n.t("14-täglich", "Every two weeks")),
                SelectionOption(id: "rest:4", title: L10n.t("4-wöchentlich", "Every four weeks")),
            ], searchable: false)
        default: return nil
        }
        let html = try await hildesheimPage(town: s.first?.id, district: s.count > 1 ? s[1].id : nil)
        let options = HTMLText.options(ofSelect: select, in: html)
            .filter { !$0.value.isEmpty && $0.value != "-1" }
            .map { SelectionOption(id: $0.value, title: $0.label) }
        guard !options.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: title, options: Self.sorted(options))
    }

    private func hildesheimEvents(street: String, calendar: Calendar) async -> [ICSEvent] {
        let year = Self.currentYear(calendar)
        var events: [ICSEvent] = []
        for target in [year, year + 1] {
            events += await ics("\(Self.hildesheimBase)ICalendar/Index.aspx?year=\(target)&streetID=\(HTTPClient.query(street))", calendar: calendar)
        }
        return events
    }

    /// Titel wie „Abfuhr Restabfall (14tägige und vierwöchentliche Abfuhr“ oder „Abfuhr Bioabfall (verschoben)“.
    private func hildesheimPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 3 else { throw ProviderError.selectAddressFirst }
        let fourWeekly = s.contains { $0.id == "rest:4" }
        return await hildesheimEvents(street: s[2].id, calendar: calendar).compactMap { event in
            var name = event.summary.replacingOccurrences(of: #"^Abfuhr\s+"#, with: "", options: .regularExpression)
            var note: String?
            if name.hasSuffix("(verschoben)") {
                name = String(name.dropLast("(verschoben)".count))
                note = L10n.t("verschoben", "moved")
            }
            if name.hasPrefix("Restabfall") {
                // 4-wöchentliche Tonnen kommen nur an den gemeinsamen Terminen.
                if fourWeekly && !name.contains("vierwöchentlich") { return nil }
                name = "Restabfall"
            }
            return Pickup(date: event.date, name: NameCleaner.clean(name), note: note)
        }
    }

    // MARK: - BEE Emden

    private static let emdenPage = "https://www.bee-emden.de/abfall/entsorgungssystem/abfuhrkalender"
    private static let emdenColors: [(String, String)] = [
        ("Grau", "Restmüll (graue Tonne)"), ("Gelb", "Gelber Sack"), ("Blau", "Papier (blaue Tonne)"),
        ("Braun", "Bioabfall (braune Tonne)"), ("Grün", "Grünabfall"),
    ]

    private func emdenStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        guard s.isEmpty else { return nil }
        let html = try await client.string(Self.emdenPage)
        let pattern = #"<td class="td-0">([^<]+)</td>\s*<td class="td-1">[\s\S]*?/abfuhrkalender/ics/([a-z0-9-]+)/abfuhrkalender\.ics"#
        let districts = HTMLText.matches(pattern, in: html).map {
            SelectionOption(id: $0[1], title: HTMLText.decodeEntities($0[0]).trimmingCharacters(in: .whitespaces))
        }
        guard !districts.isEmpty else { throw ProviderError.noDataGeneric }
        return SelectionStep(title: L10n.t("Abfuhrbezirk", "Collection district"), options: Self.sorted(districts))
    }

    /// Titel wie „Grau,Gelb,Blau“ (manchmal ohne Komma) – je Farbe ein Termin.
    private func emdenPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard let slug = s.first?.id, slug.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil else { throw ProviderError.selectAddressFirst }
        let events = await ics("\(Self.emdenPage)/ics/\(slug)/abfuhrkalender.ics", calendar: calendar)
        return events.flatMap { event -> [Pickup] in
            let names = Self.emdenColors.filter { event.summary.localizedCaseInsensitiveContains($0.0) }.map(\.1)
            return (names.isEmpty ? [NameCleaner.clean(event.summary)] : names).map { Pickup(date: event.date, name: $0) }
        }
    }

    // MARK: - Stadt Delmenhorst

    private static let delmenhorstPage = "https://www.delmenhorst.de/leben/umwelt/abfallentsorgung/abfallkalender.php"

    /// ICS-Links der Seite: (Jahr, Bezirk, Altpapiertour, Pfad).
    private func delmenhorstLinks() async throws -> [(year: String, district: String, tour: String, path: String)] {
        let html = try await client.string(Self.delmenhorstPage)
        let links = HTMLText.matches(#"href="(/medien/bindata/leben/umwelt-abfall/(\d{4})_AB(\d{2})([A-Z])\.ics)""#, in: html)
        return links.map { (year: $0[1], district: $0[2], tour: $0[3], path: $0[0]) }
    }

    private func delmenhorstStep(_ s: [SelectionOption]) async throws -> SelectionStep? {
        let links = try await delmenhorstLinks()
        switch s.count {
        case 0:
            let districts = Set(links.map(\.district)).sorted().map {
                SelectionOption(id: $0, title: L10n.t("Abfuhrbezirk \(Int($0) ?? 0)", "District \(Int($0) ?? 0)"))
            }
            guard !districts.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Abfuhrbezirk (siehe Straßenverzeichnis)", "Collection district (see street index)"), options: districts, searchable: false)
        case 1:
            let tours = Set(links.filter { $0.district == s[0].id }.map(\.tour)).sorted().map {
                SelectionOption(id: $0, title: L10n.t("Altpapiertour \($0)", "Paper route \($0)"))
            }
            guard !tours.isEmpty else { throw ProviderError.noDataGeneric }
            return SelectionStep(title: L10n.t("Altpapiertour", "Paper route"), options: tours, searchable: false)
        default:
            return nil
        }
    }

    private func delmenhorstPickups(_ s: [SelectionOption], calendar: Calendar) async throws -> [Pickup] {
        guard s.count >= 2 else { throw ProviderError.selectAddressFirst }
        let links = try await delmenhorstLinks().filter { $0.district == s[0].id && $0.tour == s[1].id }
        var result: [Pickup] = []
        for link in links {
            for event in await ics("https://www.delmenhorst.de\(link.path)", calendar: calendar) {
                result += Self.splitCombined(event.summary).map { Pickup(date: event.date, name: $0) }
            }
        }
        return result
    }
}
