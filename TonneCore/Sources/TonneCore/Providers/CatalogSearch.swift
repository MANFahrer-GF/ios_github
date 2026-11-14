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
        if let items = LocalityIndex.byName[needle] {
            return (items.prefix(30).map { (name: $0.municipality, district: $0.district) }, items[0].name)
        }
        // Zusammengesetzte Eingabe: an jedem Trenner von hinten nach vorn in „Gemeinde“ und „Ortsteil“ teilen.
        let separators: Set<Character> = [" ", "-", ",", "/", "("]
        for cut in needle.indices.reversed() where separators.contains(needle[cut]) {
            // Links bleibt eine schließende Klammer stehen („Gronau (Westf.)-Epe“).
            let left = needle[..<cut].trimmingCharacters(in: CharacterSet(charactersIn: " -,/("))
            let right = needle[cut...].trimmingCharacters(in: CharacterSet(charactersIn: " -,/()"))
            guard left.count >= 3, !right.isEmpty else { continue }
            let locals = Set((LocalityIndex.byName[right] ?? []).map { "\($0.district)|\($0.municipality)" })
            // „Riedstadt-Erfelden“: links die Gemeinde (genau, oder Anfang wie „Frankfurt“, wenn rechts ihr Ortsteil steht)
            let municipality = municipalityHits(left)
            let exact = municipality.filter { fold($0.name) == left }
            let fitting = municipality.filter { locals.contains("\($0.district)|\($0.name)") }
            if !fitting.isEmpty { return (fitting, LocalityIndex.byName[right]?.first?.name) }
            if !exact.isEmpty { return (exact, nil) }
            // „Erfelden (Riedstadt)“: links der Ortsteil, rechts seine Gemeinde
            let reversed = (LocalityIndex.byName[left] ?? []).filter { fold($0.municipality).hasPrefix(right) }
            if !reversed.isEmpty { return (reversed.map { (name: $0.municipality, district: $0.district) }, reversed[0].name) }
        }
        return ([], nil)
    }

    private static func municipalityHits(_ needle: String) -> [(name: String, district: String)] {
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

    /// Kurzer Hinweis für die Suche, z. B. „Nostorf liegt im Landkreis Ludwigslust-Parchim.“
    static func municipalityHint(for query: String) -> String? {
        let (hits, locality) = resolve(fold(query))
        guard let first = hits.first else { return nil }
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
}

/// Ortsteile mit Gemeinde und Landkreis, einmalig aus `CatalogLocalities.localities` gelesen. Gesucht wird nur genau
/// (gefaltet, „Albertsdorf (Fehmarn)“ auch als „Albertsdorf“), damit kein Tastendruck 60.000 Namen durchläuft.
enum LocalityIndex {
    struct Item { let name: String; let municipality: String; let district: String }

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

/// Einmal gefaltete Suchtexte, damit die Suche nicht bei jedem Tastendruck alle Einträge neu aufbereitet.
enum SearchIndex {
    static let text: [String: String] = Dictionary(ProviderCatalog.entries.map { ($0.id, $0.searchText) }, uniquingKeysWith: { first, _ in first })
    static let places: [String: [String]] = Dictionary(ProviderCatalog.entries.map { ($0.id, $0.places.map(ProviderCatalog.fold)) },
                                                        uniquingKeysWith: { first, _ in first })
}
