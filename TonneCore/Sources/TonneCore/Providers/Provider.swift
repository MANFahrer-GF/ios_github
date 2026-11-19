import Foundation

/// Ein Eintrag in einer Auswahlliste (Ort, Straße, Hausnummer …).
public struct SelectionOption: Identifiable, Hashable, Codable {
    public var id: String
    public var title: String
    public var subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

/// Ein Schritt im Einrichtungsassistenten: entweder eine Auswahlliste oder eine Texteingabe
/// (z. B. Straßenname bei Portalen ohne Straßenliste). Bei Texteingabe liefert der Nutzer
/// eine `SelectionOption` mit `id == title == eingegebener Text`.
public struct SelectionStep: Hashable {
    public enum Input: Hashable { case list, text }

    public var title: String
    public var options: [SelectionOption]
    public var searchable: Bool
    public var input: Input
    public var placeholder: String?
    /// Zusatzhinweis, wenn die Suche in diesem Schritt nichts findet.
    public var noMatchHint: String?
    /// Hinweis, der immer über der Liste steht (z. B. wenn das Portal die Trefferzahl begrenzt).
    public var hint: String?

    public init(title: String, options: [SelectionOption], searchable: Bool = true) {
        self.title = title
        self.options = options
        self.searchable = searchable
        self.input = .list
        self.placeholder = nil
    }

    public static func text(title: String, placeholder: String? = nil) -> SelectionStep {
        var step = SelectionStep(title: title, options: [], searchable: false)
        step.input = .text
        step.placeholder = placeholder
        return step
    }

    /// Standard-Schrittnamen
    public static var cityTitle: String { L10n.t("Ort", "Town") }
    public static var districtTitle: String { L10n.t("Ortsteil", "District") }
    public static var streetTitle: String { L10n.t("Straße", "Street") }
    public static var houseNumberTitle: String { L10n.t("Hausnummer", "House number") }

    /// Schritt, in dem eine Gemeinde gewählt wird (Titel wie bei den Anbietern) – nur hier darf die Suche vorauswählen.
    public var isPlaceStep: Bool {
        [Self.cityTitle, L10n.t("Gemeinde", "Municipality"), L10n.t("Ortschaft", "Town"), L10n.t("Ortsgemeinde", "Municipality"),
         L10n.t("Stadt / Gemeinde", "Town / municipality"), L10n.t("Stadt / Verbandsgemeinde", "Municipality"),
         L10n.t("Verbandsgemeinde / Stadt", "Municipality"), L10n.t("Gemeinde / Ortsteil", "Town / district")].contains(title)
    }

    /// Option, die zur gesuchten Gemeinde passt – nur im Gemeinde-Schritt: bei genau gleichem Namen, sonst bei gleichem
    /// Kernnamen, wenn genau eine Option ihn trägt (Kelheim „Gemeinde Saal“ für „Saal a.d.Donau“, siehe `placeCore`).
    public func preselection(for place: String) -> SelectionOption? {
        guard isPlaceStep else { return nil }
        // Genau gleich geschrieben vor gleich gefaltet: „Hüsby“ und „Husby“ falten gleich (beide Schleswig-Flensburg)
        if let exact = options.first(where: { $0.title == place }) { return exact }
        if let exact = options.first(where: { ProviderCatalog.fold($0.title) == ProviderCatalog.fold(place) }) { return exact }
        let core = Self.placeCore(place)
        // „Lambrecht ohne Iptestal und Dörrental“ schließt Teile der Gemeinde aus: nur bei genau gleichem Namen (Prüfbefund 14)
        let hits = options.filter { Self.placeCore($0.title) == core && !ProviderCatalog.fold($0.title).contains(" ohne ") }
        guard !core.isEmpty else { return nil }
        return hits.count == 1 ? hits[0] : Self.suffixMatch(hits, place: place)
    }

    /// Unter gleichen Kernen der mit dem Zusatz des Orts: Kusel „Rutsweiler/Glan“ für „Rutsweiler am Glan“,
    /// „Rutsweiler/Lauter“ für „Rutsweiler an der Lauter“ (Gemeinde-Prüfung 16.11.2026).
    static func suffixMatch(_ hits: [SelectionOption], place: String) -> SelectionOption? {
        guard hits.count > 1, let last = place.split(separator: " ").last.map(String.init), place.contains(" ") else { return nil }
        let fitting = hits.filter { option in
            guard let slash = option.title.lastIndex(of: "/") else { return false }
            return ProviderCatalog.fold(String(option.title[option.title.index(after: slash)...])) == ProviderCatalog.fold(last)
        }
        return fitting.count == 1 ? fitting[0] : nil
    }

    /// Ortsname ohne Verwaltungs-Vorsilbe und amtlichen Zusatz, wie Portale ihn verschieden schreiben (Gemeinde-Prüfung
    /// 16.11.2026): „Gemeinde Saal“ / „Saal a.d.Donau“ → „saal“, „Stadt Bingen“ / „Bingen am Rhein“ → „bingen“,
    /// „Brünn/Thür.“ → „brunn“, „Neufahrn i. Ndb.“ → „neufahrn“, „Beelitz (Stadt)“ → „beelitz“, „St.Johann“ → „sankt johann“,
    /// „Altleiningen mit Neuleiningen Tal“ → „altleiningen“. Ortsteile mit
    /// Bindestrich („Altenglan - Mühlbach“) bleiben ganz.
    static func placeCore(_ name: String) -> String {
        var text = spelling(name)
        for cut in ["(", "/", ","] { if let range = text.range(of: cut) { text = String(text[..<range.lowerBound]) } }
        for prefix in ["verbandsgemeinde ", "samtgemeinde ", "gemeinden ", "gemeinde ", "stadt ", "markt ", "amt "] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)); break
        }
        // „St.Johann“ (KAW Mainz-Bingen) = „Sankt Johann“
        if text.hasPrefix("st.") || text.hasPrefix("st ") { text = "sankt " + text.dropFirst(3).trimmingCharacters(in: .whitespaces) }
        // „mit“/„ohne“: AWB Bad Dürkheim „Altleiningen mit Neuleiningen Tal“, „Lambrecht ohne Iptestal und Dörrental“
        var kept: [Substring] = []
        for word in text.split(separator: " ") {
            if !kept.isEmpty, placeJoins.contains(String(word)) || word.contains(".") { break }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }

    /// Bindewörter der Ortsform („Wasserburg am Inn“, „Neufahrn in Niederbayern“), Abkürzungen wie „a.“, „i.d.“ erkennt
    /// `placeCore` am Punkt. Einzige Liste dafür; die Zusatzwort-Sicherung in `preselection(for:query:)` nutzt sie mit.
    /// Namen aller Gemeinden (`spelling`), einmal berechnet.
    static let municipalityNames: Set<String> = Set(MunicipalityIndex.all.map { spelling($0.name) })

    static let placeJoins: Set<String> = ["am", "an", "im", "in", "bei", "ob", "unter", "vor", "auf", "mit", "ohne"]

    /// Gefaltet und ohne Unterschied zwischen Bindestrich und Leerzeichen, wie Portale und Suchende Ortsteile verschieden
    /// schreiben (Nachprüfung N1, 16.11.2026): „Dabel-Woland“ = „Dabel Woland“, „Hagenow Heide“ = „Hagenow-Heide“,
    /// „Altenglan - Mühlbach“ → „altenglan muhlbach“. Einzige Stelle dafür; `placeCore` baut darauf auf.
    static func spelling(_ name: String) -> String {
        ProviderCatalog.fold(name).replacingOccurrences(of: "-", with: " ").split(separator: " ").joined(separator: " ")
    }

    /// Wie `preselection(for:)`, kennt aber die Suche selbst (Prüfbefunde 1–3, 16.11.2026):
    /// - Mehrdeutige Kurzform: „Rutsweiler“ passt auf „Rutsweiler/Glan“ und „Rutsweiler/Lauter“, „Weisenheim“ auf „am Berg“
    ///   und „am Sand“ – keine Vorauswahl, auch wenn die gefundene Gemeinde genau in der Liste steht.
    /// - Gesuchter Ortsteil mit eigener Option schlägt seine Gemeinde: „Kummer“ wählt „Kummer“, nicht „Ludwigslust“
    ///   (Gemos „Gemeinde / Ortsteil“), „Damelack“ für Breddin (Ostprignitz-Ruppin); bei gleichnamigen Ortsteilen der mit dem
    ///   Zusatz der Gemeinde („Zahrensdorf (Kloster Tempzin)“), ohne eindeutige Option („Klein Krams + Ausbau“) die Liste.
    /// - „Ort / Ortsteil“ (C-Trace Groß-Gerau): „Erfelden“ oder „Riedstadt-Erfelden“ wählt „Riedstadt / Erfelden“.
    /// - Bindestrich und Leerzeichen gelten gleich (`spelling`): „Dabel Woland“ wählt „Dabel-Woland“ (Nachprüfung N1).
    /// - Nennt die Suche Wörter über die Gemeinde hinaus, die eine andere Option trägt, die aber nicht eindeutig zuzuordnen
    ///   ist, zeigt der Assistent die Liste statt die Gemeinde: Eine falsche Vorauswahl ist schlimmer als keine.
    public func preselection(for place: String, query: String) -> SelectionOption? {
        guard isPlaceStep else { return nil }
        let fold = ProviderCatalog.fold, spell = Self.spelling
        let searched = fold(query), placeCore = Self.placeCore(place)
        // Wörter der Suche und Ortsform der Gemeinde: Bindewörter, Artikel und Wörter unter drei Buchstaben zählen nicht
        // („am“, „a.d.“), die Lang- und Kurzform zählt mit („Wasserburg am Inn“ = „Wasserburg a.Inn“, Prüfbefund 1 zu Paket D).
        func wordsOf(_ text: String) -> [String] { spell(text).split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        func meaningfulWords(_ text: String) -> [String] {
            wordsOf(text).filter { $0.count >= 3 && !Self.placeJoins.union(["der", "den", "dem"]).contains($0) }
        }
        func meaningful(_ text: String) -> Set<String> { Set(meaningfulWords(text)) }
        func form(_ names: [String]) -> Set<String> { Set(names.flatMap { wordsOf($0) + wordsOf(MunicipalityIndex.longForm(fold($0))) }) }
        // Mehrdeutige Kurzform – außer die Suche nennt den Zusatz der Gemeinde („Rutsweiler am Glan“, „Schwarzenbach am Wald“).
        // Ein einzelner Buchstabe ohne Punkt ist angefangene Ortsform, kein Zusatz: „Rieden a“ = „Rieden a.“ (Prüfbefund C).
        let coreParts = Self.placeCore(query).split(separator: " ").map(String.init)
        let queryCore = (coreParts.prefix(1) + coreParts.dropFirst().filter { $0.count > 1 }).joined(separator: " ")
        let suffix = meaningful(query).subtracting(wordsOf(queryCore))
        let namesSuffix = !suffix.isEmpty && suffix.isSubset(of: form([place]))
        if searched != fold(place), queryCore == placeCore, !placeCore.isEmpty, !namesSuffix,
           options.filter({ Self.placeCore($0.title) == placeCore }).count > 1 { return nil }
        let found = fold(ProviderCatalog.resolve(searched).locality ?? query)
        let locality = spell(found), typed = spell(query)
        let localityCore = Self.placeCore(locality)
        if !localityCore.isEmpty, localityCore != placeCore {
            let own = options.filter {
                Self.placeCore($0.title) == localityCore || spell($0.title).hasPrefix(locality + " ") || spell($0.title) == typed
            }
            if !own.isEmpty {
                // Nur wenn der Ortsteil zur gesuchten Gemeinde gehört (Kränzlin ist nicht Breddin): laut Ortsteil-Liste, unter
                // dem gesuchten Namen oder dem der Option, oder weil die Option mit dem Gemeindenamen beginnt („Dabel-Woland“).
                let belongs = ([found] + own.map { fold($0.title) }).contains { name in
                    (LocalityIndex.byName[name] ?? []).contains { fold($0.municipality) == fold(place) }
                } || own.contains { spell($0.title).hasPrefix(spell(place) + " ") }
                guard belongs else { return nil }
                let withPlace = own.filter { Self.bracketSuffix($0.title) == fold(place) }
                if withPlace.count == 1 { return withPlace[0] }
                return own.count == 1 && [locality, typed].contains(spell(own[0].title)) ? own[0] : nil
            }
        }
        let words = Set(searched.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let hits = options.filter {
            let parts = $0.title.components(separatedBy: " / ")
            return parts.count == 2 && fold(parts[0]) == fold(place) && words.contains(fold(parts[1]))
        }
        if hits.count == 1 { return hits[0] }
        guard let exact = preselection(for: place) else { return nil }
        // Wörter der Suche über Gemeinde und gewählte Option hinaus („Ziegelscheune“), die alle als Wortanfang in einer anderen
        // Option stehen: Die Suche meint vermutlich diese, also keine Vorauswahl. Ein Ortsteil ohne eigene Option
        // („Stuttgart Vaihingen“) wählt weiter die Gemeinde. Die Ortsform selbst ist kein Zusatz: „am“ vor „Amerang“,
        // „a.“ vor „Aldenhoven“ lösten die Sicherung aus (Prüfbefund 1 zu Paket D). Als Wortanfang zählt ein Zusatz nur in
        // Optionen, die auch die Gemeinde nennen („Grabow Ziegel“ → „Grabow Ziegelscheune“). Eine Option ohne die Gemeinde
        // muss die Suche ganz nennen („Grabow Ziegelscheune“ → „Ziegelscheune“): „Brunsbüttel Nord“ meint nicht
        // „Nordermeldorf“, „Groß Grönau Klein Grönau“ nicht „Klein Wesenberg“. Bei einem Ortsteil der gesuchten Gemeinde
        // (Ortsteil-Liste) reicht halb genannt, wenn alles, was die Suche über die Gemeinde hinaus nennt, ganze Wörter der
        // Option sind (Prüfbefund A): „Dömitz Schmölen“ meint „Groß Schmölen“ oder „Klein Schmölen“; „Wester-Ohrstedt
        // Ohrstedt“ meint nicht die Gemeinde „Oster-Ohrstedt“. Die Wörter der Gemeinde zählen dabei je einmal:
        // „Dessau-Roßlau Roßlau (Elbe)“ nennt „Roßlau (Elbe)“, „Neu Poserin OT Groß Poserin“ nennt „Groß Poserin“.
        let extra = meaningful(query).subtracting(form([place, exact.title]))
        // Abgezogen wird die Schreibweise der Gemeinde, die am meisten wegnimmt („Forst Neustädtlein am Forst“ ist die Langform)
        let rest: [String] = [place, exact.title].flatMap { [$0, MunicipalityIndex.longForm(fold($0))] }.map { (name: String) -> [String] in
            var rest = meaningfulWords(query)
            for word in wordsOf(name) { if let index = rest.firstIndex(of: word) { rest.remove(at: index) } }
            return rest
        }.min { $0.count < $1.count } ?? []
        let coreWords = wordsOf(placeCore)
        // Nennt der Rest einen Ortsteil der Gemeinde (Ortsteil-Liste), zählt auch eine Option, die ihn nur als Teil ihres Namens
        // trägt („Bahlen/Bahlendorf“, „Alt Schwinz“, „Hof Lalchow“, Prüfbefund 1 zu Paket F) – außer sie ist selbst eine
        // Gemeinde: „Ohrstedt“ ist Ortsteil von Wester-Ohrstedt, „Oster-Ohrstedt“ trotzdem nicht gemeint.
        let restIsLocality = !rest.isEmpty && ([rest.joined(separator: " ")] + rest).contains { name in
            (LocalityIndex.byName[name] ?? []).contains { fold($0.municipality) == fold(place) }
        }
        let named = (!extra.isEmpty || !rest.isEmpty) && options.contains { option in
            guard option.id != exact.id else { return false }
            let words = wordsOf(option.title)
            // Auch mit dem Gemeindenamen in der Option: „Amt Wachsenburg Wachsenburg“, „Storbeck-Frankendorf Frankendorf
            // (Storbeck-Frankendorf)“. Nicht bei derselben Gemeinde in anderer Schreibung: gleich geschrieben („Alt Mölln“
            // für „Alt-Mölln“) oder gleicher Kern mit dem Zusatz der Gemeinde („Heppenheim an der Bergstrasse“).
            let addition = meaningful(option.title).subtracting(wordsOf(placeCore))
            let samePlace = spell(option.title) == spell(place)
                || (Self.placeCore(option.title) == placeCore && !addition.isEmpty && addition.isSubset(of: form([place])))
            let halfNamed = !rest.isEmpty && rest.allSatisfy(words.contains) && !samePlace
                && ((LocalityIndex.byName[fold(option.title)] ?? []).contains { fold($0.municipality) == fold(place) }
                    || (restIsLocality && !Self.municipalityNames.contains(spell(option.title))))
            if halfNamed { return true }
            if coreWords.allSatisfy(words.contains) {
                return !extra.isEmpty && extra.allSatisfy { word in words.contains { $0.hasPrefix(word) } }
            }
            let own = meaningful(option.title)
            return !own.isEmpty && own.isSubset(of: extra)
        }
        return named ? nil : exact
    }

    /// Zusatz in Klammern am Ende: „Zahrensdorf (Kloster Tempzin)“ → „kloster tempzin“.
    static func bracketSuffix(_ title: String) -> String? {
        guard let open = title.lastIndex(of: "("), let close = title.lastIndex(of: ")"), open < close else { return nil }
        return ProviderCatalog.fold(String(title[title.index(after: open)..<close]))
    }
}

/// Ein Abholtermin aus einer Online-Quelle.
public struct Pickup: Hashable, Codable {
    public var date: Date
    public var name: String
    public var note: String?

    public init(date: Date, name: String, note: String? = nil) {
        self.date = date
        self.name = name
        self.note = note
    }
}

/// Die vollständige Konfiguration einer Online-Quelle, wie sie am Standort gespeichert wird.
public struct SourceConfiguration: Hashable, Codable {
    public var providerKind: ProviderKind
    public var serviceKey: String
    public var selections: [SelectionOption]
    public var label: String

    public init(providerKind: ProviderKind, serviceKey: String, selections: [SelectionOption], label: String) {
        self.providerKind = providerKind
        self.serviceKey = serviceKey
        self.selections = selections
        self.label = label
    }

    public func encoded() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func decode(_ string: String?) -> SourceConfiguration? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SourceConfiguration.self, from: data)
    }
}

public extension SourceConfiguration {
    /// Andere Adresse als bisher? Ein Eintragswechsel an derselben Adresse (Kreisportal Reutlingen → TBR-App, beide
    /// „Hauptstraße, 5“) ist keiner (Prüfbefund 9). Adresse = Ort + Straße/Nummer: Der Ort muss auf beiden Seiten bestimmbar
    /// und gleich sein (`addressPlace`), die übrigen Titel müssen je Schritt übereinstimmen (`sameAddress`) – „Hauptstraße 1“ gegen
    /// „10“, „12“ gegen „12a“ oder ein anderer bzw. unbekannter Ort zählen als Wechsel (Nachprüfung N2). Im Zweifel „geändert“:
    /// Dann bleiben nur markierte vergangene Termine stehen (`ScheduleEngine.datesAfterReplacingSync`).
    static func addressChanged(from old: SourceConfiguration?, to new: SourceConfiguration) -> Bool {
        guard let old else { return true }
        let sameSource = old.providerKind == new.providerKind && old.serviceKey == new.serviceKey
        if sameSource, old.selections.map(\.id) == new.selections.map(\.id) { return false }
        // Gleiche Quelle, gleiche Titel, nur andere IDs (getippter Suchtext als ID, `SourceWizardView`): dieselbe Adresse,
        // auch wenn der erste Titel ein Ortsteil ist (lwl „Kummer“, Prüfbefund 2 zu Paket D). Ebenso gleicher erster Titel mit
        // gleicher Straße und Nummer, wenn der getippte Suchtext anders war („Linden“ / „Lindenstr“ vor „Lindenstraße“).
        func shown(_ config: SourceConfiguration) -> [String] { config.selections.map { SelectionStep.spelling($0.title + "|" + ($0.subtitle ?? "")) } }
        if sameSource, shown(old) == shown(new) { return false }
        if sameSource, let first = shown(old).first, first == shown(new).first {
            if sameAddress(Array(old.selections.dropFirst()), Array(new.selections.dropFirst()), in: old.addressPlace()?.place) { return false }
        }
        guard let a = old.addressPlace(), let b = new.addressPlace(), a.place == b.place else { return true }
        // Andere Quelle: Namensvettern in verschiedenen Kreisen sind verschiedene Orte (Neuenkirchen in Dithmarschen ≠ in
        // Steinfurt, Prüfbefund 3 zu Paket D). Der Kreis muss auf beiden Seiten bestimmbar sein und übereinstimmen.
        if !sameSource {
            let (da, db) = (old.districts(of: a.place), new.districts(of: b.place))
            guard !da.isEmpty, !db.isEmpty, !da.isDisjoint(with: db) else { return true }
        }
        return !sameAddress(a.rest, b.rest, in: a.place)
    }

    /// Gleiche Titel je Schritt, in derselben Reihenfolge, ohne getippte Suchtexte (`addressSteps`). Sieht auf beiden Seiten
    /// eine andere Gemeinde oder ein anderer Ortsteil wie ein Suchtext aus, ist es ein Umzug: „Stein“ → „Steinbach“ vor
    /// „Steinbacher Straße“ (Prüfbefund B), „Greste“ → „Gresterfeld“ vor „Gresterfelder Straße“ (Prüfbefund 2 zu Paket F).
    /// Ist nur eine Seite ein Ortsname, war sie der Suchtext („Linden“ gegen „Lindenstr“ vor „Lindenstraße“). Als Ortsteil zählt
    /// nur einer der Gemeinde `place` (Prüfbefund 1 zu Teil 13: „Haupt“ vor „Hauptstraße“ ist irgendwo ein Ortsteil, in
    /// Leopoldshöhe nicht); ist die Gemeinde unbekannt, jeder Ortsteil.
    private static func sameAddress(_ a: [SelectionOption], _ b: [SelectionOption], in place: String?) -> Bool {
        let (sa, sb) = (addressSteps(a), addressSteps(b))
        let kept = sa.filter { !$0.typed }.map(\.words)
        guard !kept.isEmpty, kept == sb.filter({ !$0.typed }).map(\.words) else { return false }
        func places(_ steps: [AddressStep]) -> Set<String> {
            Set(steps.filter { step in
                guard step.typed else { return false }
                if municipalityCores.contains(SelectionStep.placeCore(step.title)) { return true }
                guard let municipalities = localityMunicipalities[step.title] else { return false }
                return place.map(municipalities.contains) ?? true
            }.map(\.title))
        }
        let (pa, pb) = (places(sa), places(sb))
        return pa.isEmpty || pb.isEmpty || pa == pb
    }

    /// Ort der Adresse (ganzer Name, `SelectionStep.spelling`) und die übrigen Titel. Führt der Katalogeintrag belegt genau
    /// einen Ort (TBR-App: nur Reutlingen), gilt dieser; ein erster Titel gleichen Namens fällt weg. Sonst gilt der erste
    /// gewählte Titel, wenn er eine Gemeinde ist („Reutlingen“ im Kreisportal) – erkannt am Kern, verglichen am ganzen Namen,
    /// denn „Rutsweiler/Glan“ und „Rutsweiler/Lauter“ teilen den Kern. Sonst nil: Der Ort ist unbekannt.
    private func addressPlace() -> (place: String, rest: [SelectionOption])? {
        let entries = ProviderCatalog.entries.filter { $0.kind == providerKind && $0.serviceKey == serviceKey }
        let mapped = Set(entries.flatMap { EntryPlacesIndex.pairs[$0.id] ?? [] }.map { SelectionStep.spelling(String($0.split(separator: "|", maxSplits: 1).last ?? "")) })
        let listed = Set(entries.flatMap(\.places).filter { Self.municipalityCores.contains(SelectionStep.placeCore($0)) }.map(SelectionStep.spelling))
        let first = selections.first.map { SelectionStep.spelling($0.title) }
        if let only = (mapped.isEmpty ? listed : mapped).first, (mapped.isEmpty ? listed : mapped).count == 1 {
            return (only, first == only ? Array(selections.dropFirst()) : selections)
        }
        if let first, Self.municipalityCores.contains(SelectionStep.placeCore(first)) { return (first, Array(selections.dropFirst())) }
        return nil
    }

    /// Kreise, in denen der Katalogeintrag den Ort führt (belegte Paare). Führt er keine, der Kreis der Gemeinde, wenn es
    /// sie unter diesem Namen nur in einem Kreis gibt. Sonst leer: Der Kreis ist unbestimmbar.
    private func districts(of place: String) -> Set<String> {
        let entries = ProviderCatalog.entries.filter { $0.kind == providerKind && $0.serviceKey == serviceKey }
        let mapped = Set(entries.flatMap { EntryPlacesIndex.pairs[$0.id] ?? [] }.compactMap { pair -> String? in
            let parts = pair.split(separator: "|", maxSplits: 1).map(String.init)
            return parts.count == 2 && SelectionStep.spelling(parts[1]) == place ? parts[0] : nil
        })
        if !mapped.isEmpty { return mapped }
        let named = Set(MunicipalityIndex.all.filter { SelectionStep.spelling($0.name) == place }.map(\.district))
        return named.count == 1 ? named : []
    }

    /// Kernnamen aller Gemeinden, einmal berechnet.
    private static let municipalityCores: Set<String> = Set(MunicipalityIndex.all.map { SelectionStep.placeCore($0.name) })

    /// Ortsteilname → Gemeinden, die ihn führen (beides `SelectionStep.spelling`), einmal berechnet.
    private static let localityMunicipalities: [String: Set<String>] = LocalityIndex.byName.reduce(into: [:]) { result, entry in
        result[SelectionStep.spelling(entry.key), default: []].formUnion(entry.value.map { SelectionStep.spelling($0.municipality) })
    }

    private typealias AddressStep = (words: Set<String>, title: String, typed: Bool)

    /// Wörter je Schritt: „Hauptstr.“, „Hauptstraße“ → „hauptstr“. Getippter Suchtext ist ein Schritt nur aus
    /// Buchstabenwörtern, die alle Wortanfang des nächsten Titels sind („Haupt“ vor „Hauptstraße“).
    private static func addressSteps(_ selections: [SelectionOption]) -> [AddressStep] {
        let steps = selections.map { option in
            (Set(ProviderCatalog.fold(option.title).replacingOccurrences(of: "ß", with: "ss")
                .replacingOccurrences(of: #"str(asse|\.)"#, with: "str", options: .regularExpression)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }), SelectionStep.spelling(option.title))
        }.filter { !$0.0.isEmpty }
        return steps.indices.map { index in
            let typed = index + 1 < steps.count && steps[index].0.allSatisfy { word in
                word.allSatisfy(\.isLetter) && steps[index + 1].0.contains { $0.hasPrefix(word) }
            }
            return (steps[index].0, steps[index].1, typed)
        }
    }

    /// Bis 2.0.9 enthielt der Name bei diesen Anbietern den getippten Suchtext („Hamburger Str., Hamburger Straße, 10“).
    /// Liefert den neuen Namen, wenn der gespeicherte noch genau der alte automatische ist – sonst nil (selbst benannt oder schon richtig).
    func repairedSearchTextLabel() -> String? {
        let titles = selections.map(\.title).filter { !$0.isEmpty }
        let legacy: String
        switch providerKind {
        case .leipzig, .awbKoeln, .ahaHannover, .muellmax:
            legacy = titles.filter { $0.lowercased() != "alle hausnummern" && $0.lowercased() != "alle straßen" }.joined(separator: ", ")
        case .portalsNRW where serviceKey == "sector27":
            legacy = titles.joined(separator: ", ")
        default:
            return nil
        }
        // Müllmax mit Direktsprung zu den Hausnummern: Build 12 (2.0.9) ließ den getippten Text weg und speicherte nur „2“
        let build12 = selections.filter { $0.id.contains(":") }.map(\.title)
            .filter { !$0.isEmpty && $0.lowercased() != "alle hausnummern" && $0.lowercased() != "alle straßen" }
            .joined(separator: ", ")
        guard label == legacy || (providerKind == .muellmax && label == build12) else { return nil }
        let fresh = ProviderFactory.make(kind: providerKind, serviceKey: serviceKey).label(for: selections)
        return fresh.isEmpty || fresh == label ? nil : fresh
    }
}

public enum ProviderKind: String, Codable, CaseIterable, Hashable {
    case awido
    case abfallIOGraphQL
    case abfallIOLegacy
    case jumomind
    case abfallnavi
    case abfallAppNet
    case icsURL
    case cTrace
    case muellmax
    case awbKoeln
    case leipzig
    case calendarPortal
    case ahaHannover
    case abfallPlusApp
    case gemosWasteBox
    case awsh
    case lobbe
    case nerdbridge
    case bsr
    case sitepark
    case insertIT
    case muellabfuhrDeutschland
    case heimatInfo
    case buergerportal
    case magdeburg
    case hausmuellInfo
    case wasteManagementServlet
    case portalsSachsen
    case portalsMV
    case portalsMitte
    case portalsBayern
    case portalsBrandenburg
    case portalsNord
    case portalsNRW
    case portalsRP
    case portalsSuedwest
    case awmMuenchen
    case jahresdaten

    public var displayName: String {
        switch self {
        case .awido: return "AWIDO"
        case .abfallIOGraphQL, .abfallIOLegacy: return "AbfallPlus"
        case .jumomind: return "Jumomind / MyMüll"
        case .abfallnavi: return "Abfallnavi"
        case .abfallAppNet: return "Abfall-App"
        case .icsURL: return L10n.t("ICS-Link", "ICS link")
        case .cTrace: return "C-Trace"
        case .muellmax: return "Müllmax"
        case .awbKoeln: return "AWB Köln"
        case .leipzig: return "Stadtreinigung Leipzig"
        case .calendarPortal: return L10n.t("Bürgerportal", "Citizen portal")
        case .ahaHannover: return "aha Region Hannover"
        case .abfallPlusApp: return "AbfallPlus-App"
        case .gemosWasteBox: return "Gemos WasteBox"
        case .awsh: return L10n.t("Kreis-Abfallkalender", "District waste calendar")
        case .lobbe: return "Lobbe App"
        case .nerdbridge: return "Nerdbridge"
        case .bsr: return "BSR Berlin"
        case .sitepark: return L10n.t("Kreis-/Stadtportal", "District portal")
        case .insertIT: return "Insert IT"
        case .muellabfuhrDeutschland: return "Müllabfuhr Deutschland"
        case .heimatInfo: return "Heimat-Info"
        case .buergerportal: return "Bürgerportal"
        case .magdeburg: return "SAB Magdeburg"
        case .hausmuellInfo: return "hausmüll.info"
        case .wasteManagementServlet: return "WasteManagement-Portal"
        case .portalsSachsen, .portalsMV, .portalsMitte, .portalsBayern, .portalsBrandenburg, .portalsNord, .portalsNRW, .portalsRP, .portalsSuedwest:
            return L10n.t("Portal des Entsorgers", "Operator portal")
        case .awmMuenchen: return "AWM München"
        case .jahresdaten: return L10n.t("Abfallkalender (PDF)", "Waste calendar (PDF)")
        }
    }
}

public enum ProviderError: LocalizedError {
    case noData(String)
    case invalidSelection(String)
    case notSupported(String)

    public var errorDescription: String? {
        switch self {
        case .noData(let message): return message
        case .invalidSelection(let message): return message
        case .notSupported(let message): return message
        }
    }

    public static var noDataGeneric: ProviderError {
        .noData(L10n.t("Das Portal hat keine Termine für diese Adresse geliefert.", "The portal returned no dates for this address."))
    }

    public static var selectAddressFirst: ProviderError {
        .invalidSelection(L10n.t("Bitte zuerst eine Adresse wählen.", "Please choose an address first."))
    }

    /// Liefert ein Portal nur noch Vergangenes, ist die Quelle veraltet (Feucht bei Heimat-Info, Stand 12.11.2026: nur Termine
    /// bis Ende 2025). Statt still „0 kommende Termine“ zu übernehmen, klar sagen, was zu tun ist.
    /// `setup`: beim Einrichten (anderen Entsorger wählen) statt beim Abgleich eines vorhandenen Standorts.
    public static func requireUpcoming(_ pickups: [Pickup], today: Date, setup: Bool = false, calendar: Calendar = .current) throws {
        let day = calendar.startOfDay(for: today)
        guard !pickups.isEmpty, !pickups.contains(where: { $0.date >= day }), let last = pickups.map(\.date).max() else { return }
        let text = last.formatted(.dateTime.day().month(.wide).year())
        if setup {
            throw ProviderError.noData(L10n.t(
                "Dieses Portal liefert keine kommenden Termine mehr, der letzte war am \(text). Bitte zurückgehen und einen anderen Entsorger wählen.",
                "This portal no longer provides upcoming dates; the last one was on \(text). Please go back and choose another provider."))
        }
        throw ProviderError.noData(L10n.t(
            "Dieses Portal liefert keine kommenden Termine mehr, der letzte war am \(text). Bitte den Entsorger neu wählen: Standort öffnen und „Entsorger oder Adresse ändern“ antippen.",
            "This portal no longer provides upcoming dates; the last one was on \(text). Please choose the provider again: open the location and tap “Change provider or address”."))
    }
}

/// Eine Online-Quelle für Abfuhrtermine: liefert Auswahlschritte und am Ende die Termine.
public protocol WasteProvider {
    var kind: ProviderKind { get }
    var serviceKey: String { get }
    var displayName: String { get }

    /// Der nächste Auswahlschritt nach den bisherigen Auswahlen – nil, wenn die Auswahl vollständig ist.
    func nextStep(after selections: [SelectionOption]) async throws -> SelectionStep?

    /// Alle Abholtermine für die vollständige Auswahl.
    func pickups(for selections: [SelectionOption], calendar: Calendar) async throws -> [Pickup]

    /// Lesbare Bezeichnung der Adresse, z. B. „Gifhorn, Steinstraße 1“. Anbieter mit Zusatzschritten
    /// (Tonnengröße, Suchtext) liefern hier nur den Adressteil.
    func label(for selections: [SelectionOption]) -> String

    /// Hinweis zur Herkunft der Termine, den die App beim Standort zeigt – z. B. „berechnet, Feiertage beachten“.
    var notice: String? { get }

    /// Kurzfassung der Einschränkung für Listen („Geht mein Ort?“); Standard ist der Hinweis selbst.
    var restriction: String? { get }
}

public extension WasteProvider {
    var notice: String? { nil }
    var restriction: String? { notice }

    /// Lesbare Bezeichnung einer Auswahl, z. B. „Gifhorn, Steinstraße 1“.
    func label(for selections: [SelectionOption]) -> String {
        let parts = selections.map(\.title).filter { !$0.isEmpty && $0.lowercased() != "alle hausnummern" && $0.lowercased() != "alle straßen" }
        return parts.joined(separator: ", ")
    }

    func pickups(for selections: [SelectionOption]) async throws -> [Pickup] {
        try await pickups(for: selections, calendar: .current)
    }
}

public enum ProviderFactory {
    public static func make(kind: ProviderKind, serviceKey: String, client: HTTPClient = HTTPClient()) -> WasteProvider {
        switch kind {
        case .awido: return AwidoProvider(customer: serviceKey, client: client)
        case .abfallIOGraphQL: return AbfallIOGraphQLProvider(key: serviceKey, client: client)
        case .abfallIOLegacy: return AbfallIOLegacyProvider(key: serviceKey, client: client)
        case .jumomind: return JumomindProvider(service: serviceKey, client: client)
        case .abfallnavi: return AbfallnaviProvider(service: serviceKey, client: client)
        case .abfallAppNet: return AbfallAppNetProvider(tenant: serviceKey, client: client)
        case .icsURL: return ICSURLProvider(url: serviceKey, client: client)
        case .cTrace: return CTraceProvider(service: serviceKey, client: client)
        case .muellmax: return MuellmaxProvider(service: serviceKey, client: client)
        case .awbKoeln: return AWBKoelnProvider(client: client)
        case .leipzig: return LeipzigProvider(client: client)
        case .calendarPortal: return CalendarPortalProvider(operator: serviceKey, client: client)
        case .ahaHannover: return AhaHannoverProvider(client: client)
        case .abfallPlusApp: return AbfallPlusAppProvider(appID: serviceKey)
        case .gemosWasteBox: return GemosWasteBoxProvider(customer: serviceKey, client: client)
        case .awsh: return AWSHProvider(region: serviceKey, client: client)
        case .lobbe: return LobbeProvider(client: client)
        case .nerdbridge: return NerdbridgeProvider(client: client)
        case .bsr: return BSRProvider(client: client)
        case .sitepark: return SiteparkProvider(tenant: serviceKey, client: client)
        case .insertIT: return InsertITProvider(city: serviceKey, client: client)
        case .muellabfuhrDeutschland: return MuellabfuhrDeutschlandProvider(mandator: serviceKey, client: client)
        case .heimatInfo: return HeimatInfoProvider(commune: serviceKey, client: client)
        case .buergerportal: return BuergerportalProvider(operator: serviceKey, client: client)
        case .magdeburg: return MagdeburgProvider(client: client)
        case .hausmuellInfo: return HausmuellInfoProvider(service: serviceKey, client: client)
        case .wasteManagementServlet: return WasteManagementServletProvider(service: serviceKey, client: client)
        case .portalsSachsen: return SachsenPortalsProvider(service: serviceKey, client: client)
        case .portalsMV: return MecklenburgPortalsProvider(service: serviceKey, client: client)
        case .portalsMitte: return MitteldeutschlandPortalsProvider(service: serviceKey, client: client)
        case .portalsBayern: return BayernPortalsProvider(service: serviceKey, client: client)
        case .portalsBrandenburg: return BrandenburgPortalsProvider(service: serviceKey, client: client)
        case .portalsNord: return NordPortalsProvider(service: serviceKey, client: client)
        case .portalsNRW: return NRWPortalsProvider(service: serviceKey, client: client)
        case .portalsRP: return RheinlandPfalzPortalsProvider(service: serviceKey, client: client)
        case .portalsSuedwest: return SuedwestPortalsProvider(service: serviceKey, client: client)
        case .awmMuenchen: return AWMMuenchenProvider(service: serviceKey, client: client)
        case .jahresdaten: return JahresdatenProvider(key: serviceKey)
        }
    }

    public static func make(_ configuration: SourceConfiguration, client: HTTPClient = HTTPClient()) -> WasteProvider {
        make(kind: configuration.providerKind, serviceKey: configuration.serviceKey, client: client)
    }
}

/// Entfernt HTML-Reste und Anbieterzusätze aus Fraktionsnamen.
public enum NameCleaner {
    public static func clean(_ name: String) -> String {
        var result = name
            .replacingOccurrences(of: "&shy;", with: "")
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = "Abholung" }
        return result
    }
}
