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
        let known = Set(strong.map(\.id))
        let viaDistrict = entries.filter { !known.contains($0.id) && inDistrict($0) }.sorted { $0.title < $1.title }
        let rest = weak.filter { !inDistrict($0) }
        return strong + viaDistrict + rest
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
    static func municipalities(matching query: String) -> [(name: String, district: String)] {
        let needle = fold(query)
        guard needle.count >= 3 else { return [] }
        let exact = MunicipalityIndex.all.filter { $0.folded == needle }
        let hits = exact.isEmpty ? MunicipalityIndex.all.filter { item in
            guard item.folded.hasPrefix(needle) else { return false }
            if item.folded.count == needle.count { return true }
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
        let hits = municipalities(matching: query)
        guard let first = hits.first else { return nil }
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
}

/// Einmal gefaltete Suchtexte, damit die Suche nicht bei jedem Tastendruck alle Einträge neu aufbereitet.
enum SearchIndex {
    static let text: [String: String] = Dictionary(ProviderCatalog.entries.map { ($0.id, $0.searchText) }, uniquingKeysWith: { first, _ in first })
    static let places: [String: [String]] = Dictionary(ProviderCatalog.entries.map { ($0.id, $0.places.map(ProviderCatalog.fold)) },
                                                        uniquingKeysWith: { first, _ in first })
}
