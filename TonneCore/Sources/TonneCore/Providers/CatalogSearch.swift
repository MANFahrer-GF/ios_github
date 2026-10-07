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
            let haystack = entry.searchText
            return words.allSatisfy { haystack.contains($0) }
        }
        // Reihenfolge: Titel beginnt mit der Eingabe, dann exakter Ortsname, dann nur Wortteil
        // („Rensdorf“ vor „Behrensdorf“).
        let ranks = Dictionary(direct.map { ($0.id, rank($0, needle: needle)) }, uniquingKeysWith: { first, _ in first })
        let ranked = direct.sorted { lhs, rhs in
            let l = ranks[lhs.id] ?? 2, r = ranks[rhs.id] ?? 2
            return l != r ? l < r : lhs.title < rhs.title
        }
        let districts = Set(municipalities(matching: query).map(\.district))
        guard !districts.isEmpty else { return ranked }
        let known = Set(direct.map(\.id))
        let viaDistrict = entries.filter { entry in
            !known.contains(entry.id) && (CatalogRegions.entryDistricts[entry.id] ?? []).contains(where: districts.contains)
        }.sorted { $0.title < $1.title }
        return ranked + viaDistrict
    }

    /// 0: Titel beginnt mit der Eingabe · 1: ein Ort heißt so (oder beginnt so, gefolgt von Leerzeichen/Klammer) · 2: nur Wortteil.
    private static func rank(_ entry: CatalogEntry, needle: String) -> Int {
        if entry.searchText.hasPrefix(needle) { return 0 }
        for place in entry.places {
            let folded = fold(place)
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
        return Array(hits.prefix(8)).map { (name: $0.name, district: $0.district) }
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
