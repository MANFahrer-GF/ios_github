import Foundation

/// Ein Entsorger bzw. Gebiet im Katalog. `serviceKey` ist die Kennung beim jeweiligen Portal.
public struct CatalogEntry: Identifiable, Hashable, Codable {
    public let kind: ProviderKind
    public let serviceKey: String
    public let title: String
    public let website: String?
    /// Orte/Regionen, die zusätzlich zur Suche beitragen (z. B. Städte einer MyMüll-Kennung).
    public let places: [String]

    public var id: String { "\(kind.rawValue):\(serviceKey):\(title)" }

    public init(kind: ProviderKind, serviceKey: String, title: String, website: String? = nil, places: [String] = []) {
        self.kind = kind
        self.serviceKey = serviceKey
        self.title = title
        self.website = website
        self.places = places
    }

    public var searchText: String {
        ([title] + places).joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
    }
}

/// Katalog aller bekannten Entsorger. Generiert aus den Quellen des Projekts
/// hacs_waste_collection_schedule (MIT) – Stand Oktober 2026.
public enum ProviderCatalog {
    public static let entries: [CatalogEntry] = [
        CatalogEntry(kind: .awido, serviceKey: "rmk", title: "Abfallwirtschaft Rems-Murr (AWRM) - AWIDO Version", website: "https://www.abfallwirtschaft-rems-murr.de/"),
        CatalogEntry(kind: .awido, serviceKey: "lra-schweinfurt", title: "Landkreis Schweinfurt", website: "https://www.landkreis-schweinfurt.de"),
        CatalogEntry(kind: .awido, serviceKey: "gotha", title: "Landkreis Gotha", website: "https://www.landkreis-gotha.de/"),
        CatalogEntry(kind: .awido, serviceKey: "zaso", title: "Zweckverband Abfallwirtschaft Saale-Orla", website: "https://www.zaso-online.de/"),
        CatalogEntry(kind: .awido, serviceKey: "unterhaching", title: "Gemeinde Unterhaching", website: "https://www.unterhaching.de/"),
        CatalogEntry(kind: .awido, serviceKey: "kaufbeuren", title: "Stadt Kaufbeuren", website: "https://www.kaufbeuren.de/"),
        CatalogEntry(kind: .awido, serviceKey: "bgl", title: "Landkreis Berchtesgadener Land", website: "https://www.lra-bgl.de/"),
        CatalogEntry(kind: .awido, serviceKey: "pullach", title: "Pullach im Isartal", website: "https://www.pullach.de/"),
        CatalogEntry(kind: .awido, serviceKey: "ffb", title: "AWB Landkreis Fürstenfeldbruck", website: "https://www.awb-ffb.de/"),
        CatalogEntry(kind: .awido, serviceKey: "unterschleissheim", title: "Stadt Unterschleißheim", website: "https://www.unterschleissheim.de/"),
        CatalogEntry(kind: .awido, serviceKey: "kreis-tir", title: "Landkreis Tirschenreuth", website: "https://www.kreis-tir.de/"),
        CatalogEntry(kind: .awido, serviceKey: "rosenheim", title: "Landkreis Rosenheim", website: "https://www.abfall.landkreis-rosenheim.de/"),
        CatalogEntry(kind: .awido, serviceKey: "tuebingen", title: "Landkreis Tübingen", website: "https://www.abfall-kreis-tuebingen.de/"),
        CatalogEntry(kind: .awido, serviceKey: "kronach", title: "Landkreis Kronach", website: "https://www.landkreis-kronach.de/"),
        CatalogEntry(kind: .awido, serviceKey: "kulmbach", title: "Landkreis Kulmbach", website: "https://www.landkreis-kulmbach.de/"),
        CatalogEntry(kind: .awido, serviceKey: "lichtenfels", title: "Landkreis Lichtenfels", website: "https://www.lkr-lif.de/"),
        CatalogEntry(kind: .awido, serviceKey: "erding", title: "Landkreis Erding", website: "https://www.landkreis-erding.de/"),
        CatalogEntry(kind: .awido, serviceKey: "zv-muc-so", title: "Zweckverband München-Südost", website: "https://www.zvmso.de/"),
        CatalogEntry(kind: .awido, serviceKey: "coburg", title: "Landkreis Coburg", website: "https://www.landkreis-coburg.de/"),
        CatalogEntry(kind: .awido, serviceKey: "ansbach", title: "Landkreis Ansbach", website: "https://www.landkreis-ansbach.de/"),
        CatalogEntry(kind: .awido, serviceKey: "awb-duerkheim", title: "AWB Landkreis Bad Dürkheim", website: "http://awb.kreis-bad-duerkheim.de/"),
        CatalogEntry(kind: .awido, serviceKey: "aic-fdb", title: "Landratsamt Aichach-Friedberg", website: "https://lra-aic-fdb.de/"),
        CatalogEntry(kind: .awido, serviceKey: "wgv", title: "WGV Recycling GmbH", website: "https://wgv-quarzbichl.de/"),
        CatalogEntry(kind: .awido, serviceKey: "neustadt", title: "Neustadt a.d. Waldnaab", website: "https://www.neustadt.de/"),
        CatalogEntry(kind: .awido, serviceKey: "kelheim", title: "Landkreis Kelheim", website: "https://www.landkreis-kelheim.de/"),
        CatalogEntry(kind: .awido, serviceKey: "kaw-guenzburg", title: "Landkreis Günzburg", website: "https://kaw.landkreis-guenzburg.de/"),
        CatalogEntry(kind: .awido, serviceKey: "memmingen", title: "Stadt Memmingen", website: "https://umwelt.memmingen.de/"),
        CatalogEntry(kind: .awido, serviceKey: "eww-suew", title: "Landkreis Südliche Weinstraße", website: "https://www.suedliche-weinstrasse.de/"),
        CatalogEntry(kind: .awido, serviceKey: "lra-dah", title: "Landratsamt Dachau", website: "https://www.landratsamt-dachau.de/"),
        CatalogEntry(kind: .awido, serviceKey: "landkreisbetriebe", title: "Landkreisbetriebe Neuburg-Schrobenhausen", website: "https://www.landkreisbetriebe.de/"),
        CatalogEntry(kind: .awido, serviceKey: "awb-ak", title: "Abfallwirtschaftsbetrieb Landkreis Altenkirchen", website: "https://www.awb-ak.de/"),
        CatalogEntry(kind: .awido, serviceKey: "awld", title: "Abfallwirtschaft Lahn-Dill-Kreises", website: "https://www.awld.de/"),
        CatalogEntry(kind: .awido, serviceKey: "azv-hef-rof", title: "Abfallwirtschafts-Zweckverband des Landkreises Hersfeld-Rotenburg", website: "https://www.azv-hef-rof.de/"),
        CatalogEntry(kind: .awido, serviceKey: "awv-nordschwaben", title: "Abfall-Wirtschafts-Verband Nordschwaben", website: "https://www.awv-nordschwaben.de/"),
        CatalogEntry(kind: .awido, serviceKey: "regensburg", title: "Stadt Regensburg", website: "https://www.regensburg.de/"),
        CatalogEntry(kind: .awido, serviceKey: "awv-isar-inn", title: "Abfallwirtschaft Isar-Inn", website: "https://www.awv-isar-inn.de/"),
        CatalogEntry(kind: .awido, serviceKey: "fulda", title: "Landkreis Fulda", website: "https://www.landkreis-fulda.de/"),
        CatalogEntry(kind: .awido, serviceKey: "fulda-stadt", title: "Stadt Fulda", website: "https://www.fulda.de/"),
        CatalogEntry(kind: .awido, serviceKey: "lra-ab", title: "Landkreis Aschaffenburg", website: "https://www.landkreis-aschaffenburg.de/"),
        CatalogEntry(kind: .awido, serviceKey: "lra-mue", title: "Landkreis Mühldorf a. Inn", website: "https://www.lra-mue.de/"),
        CatalogEntry(kind: .awido, serviceKey: "roth", title: "Landkreis Roth", website: "https://www.landratsamt-roth.de/"),
        CatalogEntry(kind: .awido, serviceKey: "lra-regensburg", title: "Landratsamt Regensburg", website: "https://www.landkreis-regensburg.de/"),
        CatalogEntry(kind: .awido, serviceKey: "lkgi", title: "Landkreis Gießen", website: "https://www.lkgi.de/"),
        CatalogEntry(kind: .awido, serviceKey: "gifhorn", title: "Landkreis Gifhorn", website: "https://www.gifhorn.de/"),
        CatalogEntry(kind: .awido, serviceKey: "koenigstein", title: "Stadt Königstein im Taunus", website: "https://www.koenigstein.de/"),
        CatalogEntry(kind: .awido, serviceKey: "ebu", title: "EBU Ulm", website: "https://www.ebu-ulm.de/"),
        CatalogEntry(kind: .awido, serviceKey: "ebe", title: "Landkreis Ebersberg", website: "https://www.lra-ebe.de/"),
        CatalogEntry(kind: .awido, serviceKey: "awb-altenburg", title: "Abfallwirtschaft Altenburger Land", website: "https://www.awb-altenburg.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "efb75cbd1f08fae1d4e47ae72a85c655", title: "Landkreis Märkisch-Oderland", website: "https://www.maerkisch-oderland.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "1c230a689579b6d3ddb9ceb5a56c6072", title: "Holding Graz", website: "https://www.holding-graz.at/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "15f69fab91c4cae50d9dbb5bcfd383f0", title: "Landkreis Reutlingen", website: "https://www.kreis-reutlingen.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "51be67f3758f1fb57b420efe065c0663", title: "Entsorgungsbetriebe Essen", website: "https://www.ebe-essen.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "0d7a92192ba3ae914c028ac37d73e222", title: "KELL Kommunalentsorgung Landkreis Leipzig GmbH", website: "https://kell-gmbh.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "80acad6c77fe9342ebafad29a8c58bf6", title: "Wirtschaftsbetriebe Duisburg (WBD)", website: "https://www.wb-duisburg.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "4b5702d771c82b611c386ebbc7629026", title: "Landkreis Göttingen", website: "https://www.landkreisgoettingen.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "76bdaac8568082d77e7a90cb41129f9b", title: "Abfallwirtschaft Landkreis Böblingen", website: "https://www.awb-bb.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "2085afd95285e645e15ee9623d0c5172", title: "ASG Nordsachsen", website: "https://www.asg-nordsachsen.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "30628292bdd8b43db86a48f7e0d85f85", title: "Amt für Abfallwirtschaft Schwarzwald-Baar-Kreis", website: "https://www.lrasbk.de/"),
        CatalogEntry(kind: .abfallIOGraphQL, serviceKey: "8b016df0116d1d5094fa339bebea0c65", title: "ASO Abfall-Service Osterholz", website: "https://www.aso-ohz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "e21758b9c711463552fb9c70ac7d4273", title: "EGST Steinfurt", website: "https://www.egst.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "9583a2fa1df97ed95363382c73b41b1b", title: "ALBA Berlin", website: "https://berlin.alba.info/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "951da001077dc651a3bf437bc829964e", title: "Landkreis Bayreuth", website: "https://www.landkreis-bayreuth.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "690a3ae4906c52b232c1322e2f88550c", title: "Landkreis Calw", website: "https://www.kreis-calw.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "595f903540a36fe8610ec39aa3a06f6a", title: "Abfallwirtschaft Landkreis Freudenstadt", website: "https://www.awb-fds.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "7dd0d724cbbd008f597d18fcb1f474cb", title: "Göttinger Entsorgungsbetriebe", website: "https://www.geb-goettingen.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "1a1e7b200165683738adddc4bd0199a2", title: "Landkreis Heilbronn", website: "https://www.landkreis-heilbronn.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "594f805eb33677ad5bc645aeeeaf2623", title: "Abfallwirtschaft Landkreis Kitzingen", website: "https://www.abfallwelt.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "7df877d4f0e63decfb4d11686c54c5d6", title: "Abfallwirtschaft Landkreis Landsberg am Lech", website: "https://www.abfallberatung-landsberg.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "bd0c2d0177a0849a905cded5cb734a6f", title: "Stadt Landshut", website: "https://www.landshut.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "6efba91e69a5b454ac0ae3497978fe1d", title: "Ludwigshafen am Rhein", website: "https://www.ludwigshafen.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "e5543a3e190cb8d91c645660ad60965f", title: "MüllALARM / Schönmackers", website: "https://www.schoenmackers.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "3ca331fb42d25e25f95014693ebcf855", title: "Abfallbewirtschaftung Ostalbkreis", website: "https://www.goa-online.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "27708a019a2e35de7eb4bbe7c851609f", title: "Landkreis Oldenburg", website: "https://www.oldenburg-kreis.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "342cedd68ca114560ed4ca4b7c4e5ab6", title: "Landkreis Ostallgäu", website: "https://www.buerger-ostallgaeu.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "914fb9d000a9a05af4fd54cfba478860", title: "Rhein-Neckar-Kreis", website: "https://www.rhein-neckar-kreis.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "645adb3c27370a61f7eabbb2039de4f1", title: "Landkreis Rotenburg (Wümme)", website: "https://lk-awr.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "39886c5699d14e040063c0142cd0740b", title: "Landkreis Sigmaringen", website: "https://www.landkreis-sigmaringen.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "279cc5db4db838d1cfbf42f6f0176a90", title: "Landratsamt Traunstein", website: "https://www.traunstein.com/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "c22b850ea4eff207a273e46847e417c5", title: "Landratsamt Unterallgäu", website: "https://www.landratsamt-unterallgaeu.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "248deacbb49b06e868d29cb53c8ef034", title: "AWB Westerwaldkreis", website: "https://wab.rlp.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "0ff491ffdf614d6f34870659c0c8d917", title: "Landkreis Limburg-Weilburg", website: "https://www.awb-lm.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "31fb9c7d783a030bf9e4e1994c7d2a91", title: "Landkreis Weißenburg-Gunzenhausen", website: "https://www.landkreis-wug.de"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "4e33d4f09348fdcc924341bf2f27ec86", title: "VIVO Landkreis Miesbach", website: "https://www.vivowarngau.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "8303df78b822c30ff2c2f98e405f86e6", title: "Abfallzweckverband Rhein-Mosel-Eifel (Landkreis Mayen-Koblenz)", website: "https://www.azv-rme.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "49fe8a63a056adbfc43f051f61dd4a44", title: "Landkreis Cuxhaven", website: "https://www.landkreis-cuxhaven.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "d287412901d68d66825e588a60c94641", title: "Landkreis Rottweil", website: "https://landkreis-rottweil.de"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "914fb9d000a9a05af4fd54cfba478860", title: "AVR Kommunal, Rhein-Neckar-Kreis", website: "https://www.avr-kommunal.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "0813ea99f520c462373386564a99a51e", title: "AWG Abfallwirtschaft Landkreis Calw", website: "https://www.awg-info.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "1e9592418582666e2a5d1c62b2683435", title: "Amt Bad Wilsnack/Weisen (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "af91b65d2753a219309072837d8ea4e1", title: "Gemeinde Groß Pankow (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "3cefa45ab357d231891bb497253c630f", title: "Gemeinde Gumtow (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "798f59a75627f5d7686dab0c7226c877", title: "Gemeinde Karstädt (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "bb937857acd951dfc8de5be8b8a49f6d", title: "Amt Lenzen-Elbtalaue (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "4638881e7bebe6869e2e86de5f8aa09e", title: "Amt Meyenburg (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "9fb3e2e5498e825250105ee272102a7b", title: "Stadt Perleberg (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "a0461612534502273c518e28d4f6f1e4", title: "Gemeinde Plattenburg (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "d92f59ef4066ae6d299478996d1d8430", title: "Stadt Pritzwalk (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "4f06df48f154246415e57ce12b26abe5", title: "Amt Putlitz/Berge (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "b870ecfa6e1f882680758d374ba3fa2d", title: "Stadt Wittenberge (Landkreis Prignitz)", website: "https://www.landkreis-prignitz.de/"),
        CatalogEntry(kind: .abfallIOLegacy, serviceKey: "04b7561b94f2cbaa171cd85bb6aa56de", title: "Landkreis Landshut", website: "https://www.landkreis-landshut.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "aachen", title: "Stadt Aachen", website: "https://www.aachen.de"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "nuernberg", title: "Abfallwirtschaft Stadt Nürnberg", website: "https://www.nuernberg.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "aw-bgl2", title: "Abfallwirtschaftsbetrieb Bergisch Gladbach", website: "https://www.bergischgladbach.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "zew2", title: "AWA Entsorgungs GmbH", website: "https://www.awa-gmbh.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "krwaf", title: "AWG Kreis Warendorf", website: "https://www.awg-waf.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "bav", title: "Bergischer Abfallwirtschaftverbund", website: "https://www.bavweb.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "coe", title: "Kreis Coesfeld", website: "https://wbc-coesfeld.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "cottbus", title: "Stadt Cottbus", website: "https://www.cottbus.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "din", title: "Dinslaken", website: "https://www.dinslaken.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "dorsten", title: "Stadt Dorsten", website: "https://www.ebd-dorsten.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "wml2", title: "EGW Westmünsterland", website: "https://www.egw.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "krwaf", title: "Kreis Gütersloh GEG", website: "https://www.geg-gt.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "hlv", title: "Halver", website: "https://www.halver.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "krhs", title: "Kreis Heinsberg", website: "https://www.kreis-heinsberg.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "kronberg", title: "Kronberg im Taunus", website: "https://www.kronberg.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "muelheim", title: "MHEG Mülheim an der Ruhr", website: "https://www.mheg.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "nds", title: "Stadt Norderstedt", website: "https://www.betriebsamt-norderstedt.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "pi", title: "Kreis Pinneberg", website: "https://www.kreis-pinneberg.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "roe", title: "Gemeinde Roetgen", website: "https://www.roetgen.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "solingen", title: "Stadt Solingen", website: "https://www.solingen.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "stl", title: "STL Lüdenscheid", website: "https://www.stl-luedenscheid.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "unna", title: "GWA - Kreis Unna mbH", website: "https://www.gwa-online.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "viersen", title: "Kreis Viersen", website: "https://www.kreis-viersen.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "oberhausen", title: "WBO Wirtschaftsbetriebe Oberhausen", website: "https://www.wbo-online.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "zew2", title: "ZEW Zweckverband Entsorgungsregion West", website: "https://zew-entsorgung.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "cux", title: "Stadt Cuxhaven", website: "https://www.cuxhaven.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "frankenthal", title: "Stadt Frankenthal", website: "https://www.frankenthal.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "awvlippe", title: "Abfallwirtschaftsverband Lippe", website: "https://www.abfall-lippe.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "kranenburg", title: "Gemeinde Kranenburg", website: "https://www.kranenburg.de/"),
        CatalogEntry(kind: .abfallnavi, serviceKey: "portawestfalica", title: "Stadt Porta Westfalica", website: "https://www.portawestfalica.de/"),
        CatalogEntry(kind: .jumomind, serviceKey: "zaw", title: "Darmstadt-Dieburg (ZAW)", website: "https://www.zaw-online.de", places: ["Darmstadt-Dieburg (ZAW)"]),
        CatalogEntry(kind: .jumomind, serviceKey: "aoe", title: "Altötting (LK)", website: "https://www.lra-aoe.de", places: ["Altötting (LK)"]),
        CatalogEntry(kind: .jumomind, serviceKey: "lka", title: "Aurich (MKW)", website: "https://mkw-grossefehn.de", places: ["Aurich (MKW)"]),
        CatalogEntry(kind: .jumomind, serviceKey: "hom", title: "Bad Homburg vdH", website: "https://www.bad-homburg.de", places: ["Bad Homburg vdH"]),
        CatalogEntry(kind: .jumomind, serviceKey: "bdg", title: "Barnim", website: "https://www.kreiswerke-barnim.de/", places: ["Barnim"]),
        CatalogEntry(kind: .jumomind, serviceKey: "hat", title: "Hattersheim am Main", website: "https://www.hattersheim.de", places: ["Hattersheim am Main"]),
        CatalogEntry(kind: .jumomind, serviceKey: "ingol", title: "Ingolstadt", website: "https://www.in-kb.de", places: ["Ingolstadt"]),
        CatalogEntry(kind: .jumomind, serviceKey: "lue", title: "Lübbecke", website: "https://www.luebbecke.de", places: ["Lübbecke"]),
        CatalogEntry(kind: .jumomind, serviceKey: "sbm", title: "Minden", website: "https://www.minden.de/", places: ["Minden"]),
        CatalogEntry(kind: .jumomind, serviceKey: "ksr", title: "Recklinghausen", website: "https://www.zbh-ksr.de", places: ["Recklinghausen"]),
        CatalogEntry(kind: .jumomind, serviceKey: "rhe", title: "Rhein-Hunsrück", website: "https://www.rh-entsorgung.de/", places: ["Rhein-Hunsrück"]),
        CatalogEntry(kind: .jumomind, serviceKey: "udg", title: "Uckermark", website: "https://www.udg-uckermark.de/", places: ["Uckermark"]),
        CatalogEntry(kind: .jumomind, serviceKey: "mymuell", title: "MyMüll-App", website: "https://www.mymuell.de/", places: ["Bad Arolsen", "Beverungen", "Darmstadt", "Esens", "Flensburg", "Gelnhausen", "Glashütten", "Großkrotzenburg", "Grävenwiesbach", "Hainburg", "Holtgast", "Kamp-Lintfort", "Kirchdorf", "Landkreis Aschaffenburg", "Landkreis Biberach", "Landkreis Eichstätt", "Landkreis Friesland", "Landkreis Leer", "Landkreis Mettmann", "Landkreis Paderborn", "Landkreis Wittmund", "Main-Kinzig-Kreis", "Mühlheim am Main", "Nenndorf", "Neumünster", "Salzgitter", "Schmitten im Taunus", "Schöneck", "Seligenstadt", "Senden", "Ulm", "Usingen", "Volkmarsen", "Vöhringen", "Wegberg", "Westerholt", "Wilhelmshaven"]),
        CatalogEntry(kind: .jumomind, serviceKey: "esn", title: "Neustadt an der Weinstraße", website: "https://www.neustadt.eu/", places: ["Neustadt an der Weinstraße"]),
        CatalogEntry(kind: .jumomind, serviceKey: "zac", title: "Celle", website: "https://www.zacelle.de/", places: ["Celle"]),
        CatalogEntry(kind: .jumomind, serviceKey: "ben", title: "Landkreis Grafschaft", website: "https://awb.grafschaft-bentheim.de/", places: ["Landkreis Grafschaft"]),
        CatalogEntry(kind: .jumomind, serviceKey: "enwi", title: "Landkreis Harz", website: "https://www.enwi-hz.de/", places: ["Landkreis Harz"]),
        CatalogEntry(kind: .jumomind, serviceKey: "hox", title: "Höxter", website: "https://abfallservice.kreis-hoexter.de/", places: ["Höxter"]),
        CatalogEntry(kind: .jumomind, serviceKey: "kbl", title: "Langen", website: "https://www.kbl-langen.de/", places: ["Langen"]),
        CatalogEntry(kind: .jumomind, serviceKey: "ros", title: "Rosbach Vor Der Höhe", website: "https://www.rosbach-hessen.de/", places: ["Rosbach Vor Der Höhe"]),
        CatalogEntry(kind: .jumomind, serviceKey: "mkk", title: "Main-Kinzig-Kreis", website: "https://abfall-mkk.de/", places: ["Main-Kinzig-Kreis"]),
        CatalogEntry(kind: .jumomind, serviceKey: "wol", title: "ALW Wolfenbüttel", website: "https://www.alw-wf.de", places: ["ALW Wolfenbüttel"]),
        CatalogEntry(kind: .abfallAppNet, serviceKey: "landkreis-stendal", title: "Landkreis Stendal", website: "https://landkreis-stendal.abfall-app.net"),
        CatalogEntry(kind: .abfallAppNet, serviceKey: "soest", title: "Kreis Soest", website: "https://soest.abfall-app.net"),
        CatalogEntry(kind: .abfallAppNet, serviceKey: "boeblingen", title: "Landkreis Böblingen", website: "https://boeblingen.abfall-app.net"),
        CatalogEntry(kind: .abfallAppNet, serviceKey: "altmarkkreis-salzwedel", title: "Altmarkkreis Salzwedel", website: "https://altmarkkreis-salzwedel.abfall-app.net"),
        CatalogEntry(kind: .abfallAppNet, serviceKey: "luechow-dannenberg", title: "Landkreis Lüchow-Dannenberg", website: "https://luechow-dannenberg.abfall-app.net"),
        CatalogEntry(kind: .abfallAppNet, serviceKey: "rhein-pfalz-kreis", title: "Rhein-Pfalz-Kreis", website: "https://rhein-pfalz-kreis.abfall-app.net"),
        CatalogEntry(kind: .abfallAppNet, serviceKey: "landkreis-holzminden", title: "Landkreis Holzminden", website: "https://landkreis-holzminden.abfall-app.net"),
    ]

    /// Volltextsuche über Titel und Orte, diakritik- und schreibweisenunabhängig.
    public static func search(_ query: String) -> [CatalogEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
        guard !needle.isEmpty else { return entries }
        let words = needle.split(separator: " ").map(String.init)
        return entries.filter { entry in
            let haystack = entry.searchText
            return words.allSatisfy { haystack.contains($0) }
        }.sorted { lhs, rhs in
            let lhsExact = lhs.searchText.hasPrefix(needle) ? 0 : 1
            let rhsExact = rhs.searchText.hasPrefix(needle) ? 0 : 1
            return lhsExact != rhsExact ? lhsExact < rhsExact : lhs.title < rhs.title
        }
    }

    public static var count: Int { entries.count }
}
