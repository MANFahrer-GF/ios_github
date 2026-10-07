import Foundation

/// Abfall-ABC: Was gehört in welche Tonne? Eine kuratierte Liste gängiger Gegenstände.
/// Hinweis: Regeln unterscheiden sich regional – die Angaben folgen den üblichen Empfehlungen.
public struct WasteABCEntry: Identifiable, Hashable {
    public let name: String
    public let category: WasteCategory
    public let hint: String?
    public var id: String { name }

    public init(_ name: String, _ category: WasteCategory, _ hint: String? = nil) {
        self.name = name; self.category = category; self.hint = hint
    }
}

public enum WasteABC {
    public static let entries: [WasteABCEntry] = [
        WasteABCEntry("Aluminiumfolie", .packaging), WasteABCEntry("Asche (kalt)", .residual, "Nur vollständig erkaltet."),
        WasteABCEntry("Backpapier", .residual, "Beschichtet – nicht ins Altpapier."), WasteABCEntry("Bananenschale", .organic),
        WasteABCEntry("Batterien", .hazardous, "Rücknahme im Handel oder Wertstoffhof."), WasteABCEntry("Blumenerde", .organic),
        WasteABCEntry("Blumen (Schnittblumen)", .organic), WasteABCEntry("Bücher", .paper, "Oder spenden."),
        WasteABCEntry("CDs / DVDs", .residual, "Besser: Wertstoffhof (Recycling)."), WasteABCEntry("Chipstüte", .packaging),
        WasteABCEntry("Dosen (Konserven)", .packaging), WasteABCEntry("Eierkarton", .paper), WasteABCEntry("Eierschalen", .organic),
        WasteABCEntry("Energiesparlampe", .hazardous, "Enthält Quecksilber – Sammelstelle."), WasteABCEntry("Fahrrad", .bulky, "Oder Wertstoffhof/Metall."),
        WasteABCEntry("Farbreste", .hazardous, "Eingetrocknete Farbe: Restmüll."), WasteABCEntry("Fensterglas", .residual, "Kein Behälterglas – Wertstoffhof/Bauschutt."),
        WasteABCEntry("Fleischreste", .organic, "Regional unterschiedlich – oft erlaubt."), WasteABCEntry("Folie (Verpackung)", .packaging),
        WasteABCEntry("Getränkekarton (Tetra Pak)", .packaging), WasteABCEntry("Glühbirne", .residual, "Keine Energiesparlampe!"),
        WasteABCEntry("Gartenabfälle", .green), WasteABCEntry("Haare", .organic), WasteABCEntry("Handy / Smartphone", .electronics, "Rücknahme im Handel."),
        WasteABCEntry("Holz (behandelt)", .bulky), WasteABCEntry("Hygieneartikel", .residual), WasteABCEntry("Joghurtbecher", .packaging, "Löffelrein, Deckel abziehen."),
        WasteABCEntry("Kaffeefilter", .organic), WasteABCEntry("Kaffeekapseln (Alu)", .packaging), WasteABCEntry("Kassenbon", .residual, "Thermopapier – kein Altpapier."),
        WasteABCEntry("Katzenstreu", .residual), WasteABCEntry("Kerzenreste", .residual), WasteABCEntry("Kleidung", .textiles, "Altkleidercontainer."),
        WasteABCEntry("Knochen", .organic, "Regional unterschiedlich."), WasteABCEntry("Korken", .residual, "Sammelstellen für Kork."),
        WasteABCEntry("Kronkorken", .packaging), WasteABCEntry("Küchenpapier", .organic), WasteABCEntry("Laub", .green),
        WasteABCEntry("LED-Lampe", .electronics), WasteABCEntry("Matratze", .bulky), WasteABCEntry("Medikamente", .residual, "Oder Apotheke/Schadstoffmobil."),
        WasteABCEntry("Milchtüte", .packaging), WasteABCEntry("Möbel", .bulky), WasteABCEntry("Nussschalen", .organic),
        WasteABCEntry("Öl (Speiseöl)", .residual, "In Flasche verschlossen; Altöl: Schadstoff."), WasteABCEntry("Papiertaschentuch", .residual),
        WasteABCEntry("Pizzakarton", .paper, "Stark verschmutzt → Restmüll."), WasteABCEntry("Plastikflasche", .packaging), WasteABCEntry("Plastikspielzeug", .residual, "Keine Verpackung → Restmüll."),
        WasteABCEntry("Porzellan", .residual), WasteABCEntry("Prospekte", .paper), WasteABCEntry("Rasenschnitt", .green),
        WasteABCEntry("Schrauben", .residual, "Metall: Wertstoffhof."), WasteABCEntry("Spiegel", .residual, "Wertstoffhof."), WasteABCEntry("Spraydosen (leer)", .packaging),
        WasteABCEntry("Staubsaugerbeutel", .residual), WasteABCEntry("Steingut", .residual), WasteABCEntry("Styropor (Verpackung)", .packaging),
        WasteABCEntry("Tapeten", .residual), WasteABCEntry("Teebeutel", .organic), WasteABCEntry("Teppich", .bulky),
        WasteABCEntry("Toner / Druckerpatrone", .hazardous, "Rücknahme Hersteller/Handel."), WasteABCEntry("Trinkglas", .residual, "Kein Behälterglas."),
        WasteABCEntry("Tüten (Plastik)", .packaging), WasteABCEntry("Verpackungsglas (Flaschen, Gläser)", .glass, "Nach Farben trennen."),
        WasteABCEntry("Weihnachtsbaum", .green, "Oft eigene Abholung im Januar."), WasteABCEntry("Windeln", .residual), WasteABCEntry("Zahnbürste", .residual),
        WasteABCEntry("Zeitungen", .paper), WasteABCEntry("Zigarettenkippen", .residual), WasteABCEntry("Zahnpastatube", .packaging),
        WasteABCEntry("Eis am Stiel (Holzstäbchen)", .residual), WasteABCEntry("Essensreste (gekocht)", .organic), WasteABCEntry("Fensterumschläge", .paper, "Folie darf dran bleiben."),
        WasteABCEntry("Fotos", .residual), WasteABCEntry("Geschenkpapier", .paper, "Nur unbeschichtet."), WasteABCEntry("Gummi", .residual),
        WasteABCEntry("Holzasche", .residual), WasteABCEntry("Kabel", .electronics), WasteABCEntry("Kleiderbügel (Plastik)", .residual),
        WasteABCEntry("Kugelschreiber", .residual), WasteABCEntry("Luftballons", .residual), WasteABCEntry("Nagellack", .hazardous),
        WasteABCEntry("Obstreste", .organic), WasteABCEntry("Pfanne", .residual, "Metall: Wertstoffhof."), WasteABCEntry("Röntgenbilder", .hazardous),
        WasteABCEntry("Sägespäne (unbehandelt)", .organic), WasteABCEntry("Schuhe", .textiles, "Paarweise gebündelt."), WasteABCEntry("Thermoskanne", .residual),
        WasteABCEntry("Tonpapier", .paper), WasteABCEntry("Tierkot", .residual), WasteABCEntry("Unkraut", .green),
        WasteABCEntry("Verbandsmaterial", .residual), WasteABCEntry("Wattestäbchen", .residual), WasteABCEntry("Zigarettenschachtel", .paper, "Folie: Gelber Sack."),
    ].sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    public static func search(_ query: String) -> [WasteABCEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de")).contains(needle) }
    }
}
