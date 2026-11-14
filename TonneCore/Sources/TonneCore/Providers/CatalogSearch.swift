import Foundation

public extension ProviderCatalog {
    static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
    }

    /// Volltextsuche über Titel und Orte, diakritik- und schreibweisenunabhängig.
    /// Ist die Eingabe eine Gemeinde, kommen danach alle Entsorger ihres Landkreises.
    static func search(_ query: String) -> [CatalogEntry] {
        let needle = fold(query)
        guard !needle.isEmpty else { return entries }
        let words = needle.split(separator: " ").map(String.init)
        let direct = entries.filter { entry in
            let haystack = SearchIndex.text[entry.id] ?? entry.searchText
            return words.allSatisfy { haystack.contains($0) }
        }
        // Reihenfolge: Titel beginnt mit der Eingabe, dann exakter Ortsname, dann nur Wortteil
        // („Rensdorf“ vor „Behrensdorf“).
        let ranks = Dictionary(direct.map { ($0.id, rank($0, needle: needle)) }, uniquingKeysWith: { first, _ in first })
        let ranked = direct.sorted { lhs, rhs in
            let l = ranks[lhs.id] ?? 2, r = ranks[rhs.id] ?? 2
            return l != r ? l < r : lhs.title < rhs.title
        }
        // Kreisname („Landkreis Konstanz“, „Kreis Konstanz“): dazu alle Einträge, die belegt Orte dieses Kreises führen –
        // die Müllmann-App heißt nicht mehr nach dem Kreis, gehört aber zu ihm.
        let namedDistricts = districts(matching: needle)
        if !namedDistricts.isEmpty {
            let known = Set(ranked.map(\.id))
            let extra = entries.filter { entry in
                !known.contains(entry.id) && ((EntryPlacesIndex.pairs[entry.id] ?? []).contains {
                    namedDistricts.contains(String($0.split(separator: "|", maxSplits: 1)[0]))
                } || (CatalogRegions.entryDistricts[entry.id] ?? []).contains(where: namedDistricts.contains))
            }.sorted { $0.title < $1.title }
            return ranked + extra
        }
        let hits = municipalities(matching: query)
        let districts = Set(hits.map(\.district))
        guard !districts.isEmpty else { return ranked }
        // Entsorger des Kreises, in dem der gesuchte Ort liegt, vor bloßen Wortteil-Treffern
        // („Bergen“ → erst Landkreis Celle, dann „Bergenhusen“ in Schleswig-Flensburg).
        let strong = ranked.filter { (ranks[$0.id] ?? 2) < 2 }
        let weak = ranked.filter { (ranks[$0.id] ?? 2) >= 2 }
        // Kreisweite Entsorger des Kreises – Gemeinde-Einträge (z. B. Mein-Abfallkalender einer Stadt) nur für genau diese Gemeinde.
        let pairs = Set(hits.map { "\($0.district)|\($0.name)" })
        // Gemeinden mit belegter Zuordnung zeigen nur die Einträge, die sie führen (Neuss → AWL Neuss, nicht jeden
        // Entsorger des Rhein-Kreises). Nur wo die Zuordnung keinen kennt, bleiben die Einträge des Kreises als Kandidaten.
        let proven = Set(pairs.flatMap { PlaceMapIndex.entryIDs[$0] ?? [] })
        // Nachweislich nicht holbare Gemeinden (Portal abgeschaltet, nur PDF, nicht geführt) bekommen keine Kandidaten aus dem
        // Kreis – die führen sie nicht, und die Auswahl endete bei „Nichts gefunden“.
        let openDistricts = Set(hits.filter {
            let pair = "\($0.district)|\($0.name)"
            return PlaceMapIndex.entryIDs[pair] == nil && PlaceMapIndex.gaps[pair]?.isUnavailable != true
        }.map(\.district))
        let inDistrict = { (entry: CatalogEntry) in
            proven.contains(entry.id)
                || (CatalogRegions.entryDistricts[entry.id] ?? []).contains(where: openDistricts.contains)
                || (CatalogRegions.localEntries[entry.id] ?? []).contains(where: pairs.contains)
        }
        // Sind alle gefundenen Gemeinden nachweislich nicht holbar, fallen auch Titel-Treffer weg, die an deren Kreis
        // gebunden sind („Garmisch-Partenkirchen“ → nicht „Kreis Garmisch-Partenkirchen“, der die Gemeinde nicht führt).
        let allUnavailable = proven.isEmpty && hits.allSatisfy {
            PlaceMapIndex.gaps["\($0.district)|\($0.name)"]?.isUnavailable == true
        }
        let boundToUnavailable = { (entry: CatalogEntry) in
            allUnavailable && ((CatalogRegions.entryDistricts[entry.id] ?? []).contains(where: districts.contains)
                || (CatalogRegions.localEntries[entry.id] ?? []).contains(where: pairs.contains))
        }
        let known = Set(strong.map(\.id))
        let viaDistrict = entries.filter { !known.contains($0.id) && inDistrict($0) }.sorted { $0.title < $1.title }
        let rest = weak.filter { !inDistrict($0) }
        return (strong + viaDistrict + rest).filter { !boundToUnavailable($0) }
    }

    /// Kreise, die die Eingabe genau nennt: voller Name („Landkreis Konstanz“) oder mit anderer Kreis-Vorsilbe
    /// („Kreis Konstanz“). Ein bloßer Ortsname („Konstanz“) nennt keinen Kreis.
    static func districts(matching needle: String) -> Set<String> {
        let prefixes = ["landkreis ", "kreis ", "kreisfreie stadt ", "stadtkreis ", "lk "]
        guard let prefix = prefixes.first(where: { needle.hasPrefix($0) }) else { return [] }
        let core = needle.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard core.count >= 3 else { return [] }
        // Voller Kreisname trifft nur diesen Kreis („Stadtkreis Karlsruhe“ nicht auch den Landkreis)
        if let exact = DistrictIndex.folded[needle] { return [exact] }
        return Set(DistrictIndex.folded.filter { folded, _ in
            prefixes.contains { folded == $0 + core }
        }.map(\.value))
    }

    /// 0: Titel beginnt mit der Eingabe · 1: ein Ort heißt so (oder beginnt so, gefolgt von Leerzeichen/Klammer) · 2: nur Wortteil.
    private static func rank(_ entry: CatalogEntry, needle: String) -> Int {
        if (SearchIndex.text[entry.id] ?? entry.searchText).hasPrefix(needle) { return 0 }
        for folded in SearchIndex.places[entry.id] ?? entry.places.map(fold) {
            guard folded.hasPrefix(needle) else { continue }
            if folded.count == needle.count { return 1 }
            let next = folded[folded.index(folded.startIndex, offsetBy: needle.count)]
            if !next.isLetter { return 1 }
        }
        return 2
    }

    /// Gemeinden, deren Name der Eingabe entspricht oder mit ihr beginnt (z. B. „Lauenburg“ → „Lauenburg/Elbe“).
    /// Trifft keine Gemeinde, gilt die Eingabe als Ortsteil: „Erfelden“, „Riedstadt-Erfelden“, „Riedstadt Erfelden“
    /// und „Erfelden (Riedstadt)“ führen zu Riedstadt.
    static func municipalities(matching query: String) -> [(name: String, district: String)] {
        resolve(fold(query)).hits
    }

    /// Gemeinden zur Eingabe und, wenn sie über einen Ortsteil gefunden wurden, dessen Name.
    private static func resolve(_ needle: String) -> (hits: [(name: String, district: String)], locality: String?) {
        guard needle.count >= 3 else { return ([], nil) }
        let direct = municipalityHits(needle)
        if !direct.isEmpty { return (direct, nil) }
        // Ausgeschriebene Kurzform: „Altenstadt an der Waldnaab“ = „Altenstadt a.d.Waldnaab“
        if let items = MunicipalityIndex.byLongForm[MunicipalityIndex.longForm(needle)] {
            return (items.map { (name: $0.name, district: $0.district) }, nil)
        }
        if let items = LocalityIndex.byName[needle] {
            // Allgemeine Ortsteilnamen („Altstadt“, „Thal“ in 36 Gemeinden) allein liefern keine Gemeinde, sonst stünden
            // beliebige Kreise in der Trefferliste; der Hinweis bittet um „Gemeinde Ortsteil“.
            var seen = Set<String>()
            let places = items.filter { seen.insert("\($0.district)|\($0.municipality)").inserted }
            guard places.count <= LocalityIndex.maxMunicipalities else { return ([], items[0].name) }
            return (places.map { (name: $0.municipality, district: $0.district) }, items[0].name)
        }
        // Ein Kreisname ohne Vorsilbe („Darmstadt-Dieburg“, „Lüchow-Dannenberg“) ist keine Gemeinde mit Ortsteil.
        if DistrictIndex.cores.contains(needle) { return ([], nil) }
        // Zusammengesetzte Eingabe: an jedem Trenner von hinten nach vorn in „Gemeinde“ und „Ortsteil“ teilen.
        let separators: Set<Character> = [" ", "-", ",", "/", "("]
        for cut in needle.indices.reversed() where separators.contains(needle[cut]) {
            // Links bleibt eine schließende Klammer stehen („Gronau (Westf.)-Epe“).
            let left = needle[..<cut].trimmingCharacters(in: CharacterSet(charactersIn: " -,/("))
            let right = needle[cut...].trimmingCharacters(in: CharacterSet(charactersIn: " -,/()"))
            guard left.count >= 3, !right.isEmpty else { continue }
            let locals = Set((LocalityIndex.byName[right] ?? []).map { "\($0.district)|\($0.municipality)" })
            // „Riedstadt-Erfelden“: links die Gemeinde (genau, oder Anfang wie „Frankfurt“, wenn rechts ihr Ortsteil steht)
            let exact = municipalityHits(left).filter { fold($0.name) == left }
            let namesakes = MunicipalityIndex.namesakes(left)
            let candidates = exact + namesakes.map { (name: $0.name, district: $0.district) }
            // „Riedstadt-Erfelden“, „Borken Singlis“: links die Gemeinde (auch ein Namensvetter mit Zusatz), rechts ihr Ortsteil
            let fitting = candidates.filter { locals.contains("\($0.district)|\($0.name)") }
            if !fitting.isEmpty { return (fitting, LocalityIndex.byName[right]?.first?.name) }
            // Kreiswort rechts („München Landkreis“): an dieser Stelle nicht teilen, die Volltextsuche findet den Eintrag
            if ["landkreis", "kreis", "lk"].contains(right) { continue }
            // Rechts der ganze Zusatz eines Namensvetters: „Halle Saale“ → „Halle (Saale)“, „Halle Westfalen“ → „Halle (Westf.)“,
            // „Neustadt Weinstraße“ → „Neustadt an der Weinstraße“; ein bloßer Anfangsbuchstabe reicht nicht („Hamm S“).
            let suffixed = namesakes.filter { MunicipalityIndex.suffix(of: $0.folded, after: left, matches: right) }
            if !suffixed.isEmpty { return (suffixed.map { (name: $0.name, district: $0.district) }, nil) }
            // Sonst gilt die Gemeinde links („Berlin-Lichtenberg“, „Stuttgart Vaihingen“, auch wenn der Ortsteil wie eine
            // andere Gemeinde heißt und deshalb nicht in der Ortsteil-Tabelle steht).
            if !exact.isEmpty { return (exact, nil) }
            // „Erfelden (Riedstadt)“: links der Ortsteil, rechts seine Gemeinde
            let reversed = (LocalityIndex.byName[left] ?? []).filter { fold($0.municipality).hasPrefix(right) }
            if !reversed.isEmpty { return (reversed.map { (name: $0.municipality, district: $0.district) }, reversed[0].name) }
        }
        return ([], nil)
    }

    static func municipalityHits(_ needle: String) -> [(name: String, district: String)] {
        // Über die sortierte Liste statt alle 11.000 Gemeinden je Aufruf; Reihenfolge der Treffer wie in der Gemeindeliste.
        let all = MunicipalityIndex.all, sorted = MunicipalityIndex.sortedOffsets
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if all[sorted[mid]].folded < needle { low = mid + 1 } else { high = mid }
        }
        var offsets: [Int] = []
        while low < sorted.count, all[sorted[low]].folded.hasPrefix(needle) { offsets.append(sorted[low]); low += 1 }
        let candidates = offsets.sorted().map { all[$0] }
        let exact = candidates.filter { $0.folded == needle }
        let hits = exact.isEmpty ? candidates.filter { item in
            let next = item.folded[item.folded.index(item.folded.startIndex, offsetBy: needle.count)]
            return !next.isLetter
        } : exact
        // Gleichnamige Gemeinden vollständig (Neuenkirchen gibt es zehnmal), bloße Anfänge begrenzt
        return Array(exact.isEmpty ? hits.prefix(8) : hits[...]).map { (name: $0.name, district: $0.district) }
    }

    /// Gefundene Gemeinden ohne belegten Entsorger, jede mit ihrem eigenen Kreis und Grund. Geprüft wird je Gemeinde,
    /// nicht je Kreis: Ein Kreis mit Entsorger kann einzelne Gemeinden haben, die dieser nicht führt.
    static func uncoveredPlaces(matching query: String) -> [PlaceCheck] {
        checkPlace(query).filter { !$0.isCovered }
    }

    /// Gesuchte Gemeinde, die der Eintrag belegt führt (für die Vorauswahl im ersten Schritt), sonst nil.
    static func servedPlace(for entry: CatalogEntry, query: String) -> String? {
        let pairs = Set(EntryPlacesIndex.pairs[entry.id] ?? [])
        return municipalities(matching: query).first { pairs.contains("\($0.district)|\($0.name)") }?.name
    }

    /// Zusatz für den Untertitel in der Trefferliste, bezogen auf die Eingabe: „Führt Karlsruhe · auch 14 Orte im
    /// Landkreis Konstanz“ oder „Führt Karlsruhe nicht“. Nur aus der belegten Zuordnung, sonst nil.
    static func placeNote(for entry: CatalogEntry, query: String) -> String? {
        let hits = municipalities(matching: query)
        guard !hits.isEmpty else { return nil }
        let pairs = EntryPlacesIndex.pairs[entry.id] ?? []
        let matched = hits.filter { pairs.contains("\($0.district)|\($0.name)") }
        if let place = matched.first {
            let matchedPairs = Set(matched.map { "\($0.district)|\($0.name)" })
            let others = pairs.filter { !matchedPairs.contains($0) }
            let districts = Set(others.map { $0.split(separator: "|", maxSplits: 1)[0] })
            switch (others.count, districts.count) {
            case (0, _):
                return L10n.t("Führt \(place.name)", "Covers \(place.name)")
            case (1, _):
                let other = others[0].split(separator: "|", maxSplits: 1)[1]
                return L10n.t("Führt \(place.name) · auch \(other)", "Covers \(place.name) · also \(other)")
            case (let count, 1):
                let district = districts.first!
                return L10n.t("Führt \(place.name) · auch \(count) Orte im \(district)", "Covers \(place.name) · also \(count) places in \(district)")
            case (let count, _):
                return L10n.t("Führt \(place.name) · auch \(count) weitere Orte", "Covers \(place.name) · also \(count) other places")
            }
        }
        // Nur eine gesuchte Gemeinde mit belegter Zuordnung, die diesen Eintrag nicht nennt
        guard hits.count == 1, let proven = PlaceMapIndex.entryIDs["\(hits[0].district)|\(hits[0].name)"], !proven.contains(entry.id) else { return nil }
        // Nennt der Eintrag die Gemeinde selbst unter seinen Orten und liegt im selben Kreis (oder hat keinen), widerspricht
        // er der Zuordnung – dann lieber nichts behaupten (Messung 14.11.: 2 von 9.794, „Reutlingen“ der TBR-App).
        let name = fold(hits[0].name), needle = fold(query)
        // Namensvettern mit Zusatz („Frankenthal“ → auch „Frankenthal (Pfalz)“, „Borken“ → „Borken (Hessen)“): die Eingabe
        // meint nicht sicher diese Gemeinde.
        let others = (MunicipalityIndex.namesakes(name) + MunicipalityIndex.namesakes(needle)).filter {
            $0.name != hits[0].name || $0.district != hits[0].district
        }
        if !others.isEmpty { return nil }
        // Nennt der Eintrag die Eingabe oder die Gemeinde selbst unter seinen Orten und liegt im selben Kreis (oder hat keinen),
        // widerspricht er der Zuordnung. Ein Namensvetter in einem anderen Kreis bleibt „nicht“ (Ortsteil Heide ≠ Heide in Dithmarschen).
        let places = SearchIndex.places[entry.id] ?? [], districts = CatalogRegions.entryDistricts[entry.id] ?? []
        if places.contains(name) || places.contains(needle), districts.isEmpty || districts.contains(hits[0].district) { return nil }
        return L10n.t("Führt \(hits[0].name) nicht", "Does not cover \(hits[0].name)")
    }

    /// Kurzer Hinweis für die Suche, z. B. „Nostorf liegt im Landkreis Ludwigslust-Parchim.“
    static func municipalityHint(for query: String) -> String? {
        let (hits, locality) = resolve(fold(query))
        guard let first = hits.first else {
            guard let locality else { return nil }
            return L10n.t("\(locality) gibt es in vielen Gemeinden – bitte mit Gemeinde suchen, z. B. „Riedstadt Erfelden“.",
                          "\(locality) exists in many municipalities – please add the municipality, e.g. “Riedstadt Erfelden”.")
        }
        if let locality, hits.count == 1 {
            return L10n.t("\(locality) gehört zu \(first.name) (\(first.district)).", "\(locality) is part of \(first.name) (\(first.district)).")
        }
        let districts = Array(Set(hits.map(\.district))).sorted()
        if districts.count == 1 {
            return L10n.t("\(first.name) liegt im \(districts[0]).", "\(first.name) is in \(districts[0]).")
        }
        return L10n.t("Gefunden in: \(districts.prefix(3).joined(separator: ", "))", "Found in: \(districts.prefix(3).joined(separator: ", "))")
    }
}

/// Alle Gemeinden mit Landkreis, einmalig aus `CatalogRegions.municipalities` gelesen.
enum MunicipalityIndex {
    struct Item { let name: String; let folded: String; let district: String }

    static let all: [Item] = {
        var result: [Item] = []
        result.reserveCapacity(11_000)
        for line in CatalogRegions.municipalities.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let district = String(parts[0])
            for name in parts[1].split(separator: ",") {
                let text = String(name)
                result.append(Item(name: text, folded: ProviderCatalog.fold(text), district: district))
            }
        }
        return result
    }()

    /// Positionen in `all`, nach gefaltetem Namen sortiert (für die Suche nach Anfang).
    static let sortedOffsets: [Int] = all.indices.sorted { all[$0].folded < all[$1].folded }

    /// Gemeinden, deren Name mit `needle` und einem Zusatz beginnt („halle“ → „Halle (Saale)“, „Halle (Westf.)“).
    static func namesakes(_ needle: String) -> [Item] {
        var low = 0, high = sortedOffsets.count
        while low < high {
            let mid = (low + high) / 2
            if all[sortedOffsets[mid]].folded < needle { low = mid + 1 } else { high = mid }
        }
        var result: [Item] = []
        while low < sortedOffsets.count, all[sortedOffsets[low]].folded.hasPrefix(needle) {
            let item = all[sortedOffsets[low]]
            if item.folded.count > needle.count, !item.folded[item.folded.index(item.folded.startIndex, offsetBy: needle.count)].isLetter {
                result.append(item)
            }
            low += 1
        }
        return result
    }

    /// Passt der Zusatz eines Namensvetters ganz zur Eingabe rechts? Füllwörter („an der“, „am“, „in“) zählen nicht, Abkürzungen
    /// dürfen Buchstaben auslassen („westf“ ⊂ „westfalen“, „rhld“ ⊂ „rheinland“), der erste Buchstabe muss gleich sein.
    static func suffix(of folded: String, after left: String, matches right: String) -> Bool {
        let fillers: Set<String> = ["an", "der", "am", "im", "in", "bei", "ob", "vor", "vorm", "unter", "dem", "den", "zu", "zum", "auf"]
        // Das letzte Wort zählt nie als Füllwort („Haag i.OB“: „ob“ = Oberbayern, „Rothenburg ob der Tauber“: Füllwort)
        func core(_ text: String) -> [Character] {
            let words = longForm(text).split(whereSeparator: { !$0.isLetter }).map(String.init)
            return Array(words.enumerated().filter { $0.offset == words.count - 1 || !fillers.contains($0.element) }.map(\.element).joined())
        }
        let wanted = core(String(folded.dropFirst(left.count))), given = core(right)
        guard let first = wanted.first, first == given.first else { return false }
        var index = given.startIndex
        for character in wanted {
            guard let found = given[index...].firstIndex(of: character) else { return false }
            index = given.index(after: found)
        }
        return true
    }

    /// Amtliche Kurzformen ausgeschrieben, Punkte und Leerraum vereinheitlicht („lohr a.main“ → „lohr am main“).
    static func longForm(_ folded: String) -> String {
        var text = folded
        for (short, full) in [("a.d.", " an der "), ("i.d.", " in der "), ("v.d.", " vor der "), ("a.", " am "), ("i.", " im "),
                              ("b.", " bei "), ("st.", " sankt ")] {
            text = text.replacingOccurrences(of: short, with: full)
        }
        return text.split(whereSeparator: { $0 == " " || $0 == "." }).joined(separator: " ")
    }

    /// Nur Gemeinden mit Kurzform im Namen, unter ihrer Langform.
    static let byLongForm: [String: [Item]] = {
        var result: [String: [Item]] = [:]
        for item in all where item.folded.contains(".") {
            let long = longForm(item.folded)
            if long != item.folded { result[long, default: []].append(item) }
        }
        return result
    }()
}

/// Ortsteile mit Gemeinde und Landkreis, einmalig aus `CatalogLocalities.localities` gelesen. Gesucht wird nur genau
/// (gefaltet, „Albertsdorf (Fehmarn)“ auch als „Albertsdorf“), damit kein Tastendruck 60.000 Namen durchläuft.
enum LocalityIndex {
    struct Item { let name: String; let municipality: String; let district: String }

    /// Mehr Gemeinden mit gleichnamigem Ortsteil liefert ein Ortsteilname allein nicht (Stand 14.11.: 112 Namen > 8).
    static let maxMunicipalities = 8

    static let all: [Item] = CatalogLocalities.localities.split(separator: "\n").flatMap { line -> [Item] in
        let parts = line.split(separator: "|", maxSplits: 2)
        guard parts.count == 3 else { return [] }
        return parts[2].split(separator: ",").map { Item(name: String($0), municipality: String(parts[1]), district: String(parts[0])) }
    }

    static let byName: [String: [Item]] = {
        var result: [String: [Item]] = [:]
        for item in all {
            let folded = ProviderCatalog.fold(item.name)
            result[folded, default: []].append(item)
            if let open = folded.range(of: " (") {
                let base = String(folded[..<open.lowerBound])
                if base != folded { result[base, default: []].append(item) }
            }
        }
        return result
    }()
}

/// Alle Kreisnamen gefaltet → Originalname.
enum DistrictIndex {
    static let folded: [String: String] = Dictionary(CatalogRegions.districtStates.keys.map { (ProviderCatalog.fold($0), $0) },
                                                     uniquingKeysWith: { first, _ in first })

    /// Kreisnamen ohne Vorsilbe („darmstadt-dieburg“); „Landkreis Konstanz“ → „konstanz“ zählt nicht, weil es eine Gemeinde ist.
    static let cores: Set<String> = Set(folded.keys.compactMap { name in
        for prefix in ["landkreis ", "kreisfreie stadt ", "stadtkreis ", "kreis ", "regionalverband ", "region "] where name.hasPrefix(prefix) {
            let core = String(name.dropFirst(prefix.count))
            return MunicipalityIndex.all.contains { $0.folded == core } ? nil : core
        }
        return nil
    })
}

/// Belegte Gemeinden je Eintrag („Landkreis|Gemeinde“), umgekehrt aus `PlaceMapIndex.entryIDs`.
enum EntryPlacesIndex {
    static let pairs: [String: [String]] = {
        var out: [String: [String]] = [:]
        for (pair, ids) in PlaceMapIndex.entryIDs { for id in ids { out[id, default: []].append(pair) } }
        return out.mapValues { $0.sorted() }
    }()
}

/// Einmal gefaltete Suchtexte, damit die Suche nicht bei jedem Tastendruck alle Einträge neu aufbereitet.
enum SearchIndex {
    static let text: [String: String] = Dictionary(ProviderCatalog.entries.map { ($0.id, $0.searchText) }, uniquingKeysWith: { first, _ in first })
    static let places: [String: [String]] = Dictionary(ProviderCatalog.entries.map { ($0.id, $0.places.map(ProviderCatalog.fold)) },
                                                        uniquingKeysWith: { first, _ in first })
}
