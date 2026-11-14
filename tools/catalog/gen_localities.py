#!/usr/bin/env python3
"""Erzeugt TonneCore/Sources/TonneCore/Providers/CatalogLocalities.swift: Ortsteile je Gemeinde für die Suche
(„Erfelden“, „Riedstadt-Erfelden“ → Riedstadt, Landkreis Groß-Gerau).

    python3 tools/catalog/gen_localities.py                      # aus den Daten im Repo
    python3 tools/catalog/gen_localities.py --extract DE.txt     # Auszug neu aus dem GeoNames-Abzug ziehen

Quellen:
  data/geo/geonames_orte.tsv – Auszug aus GeoNames DE (https://download.geonames.org/export/dump/DE.zip, Abruf 14.11.2026,
                               Lizenz CC BY 4.0, https://www.geonames.org): bewohnte Orte (Klasse P, Codes in KEEP) mit
                               8-stelligem Gemeindeschlüssel (admin4). Spalten: Name, Code, Schlüssel.
  data/geo/ortsteile.csv     – Ortsteile aus dem Gemeinde-Abgleich (ags;ortsteil).
  data/place_map/belege.json – Schlüssel → Landkreis und Gemeinde in der Schreibweise der App (CatalogRegions).

Ortsteile, die wie irgendeine Gemeinde heißen (oder deren Anfang sind, „Lauenburg“ → „Lauenburg/Elbe“), bleiben weg:
Gemeindenamen haben in der Suche Vorrang.
"""
import json, os, sys, collections

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(REPO, 'tools', 'catalog', 'data')
TSV = os.path.join(DATA, 'geo', 'geonames_orte.tsv')
OUT = os.path.join(REPO, 'TonneCore', 'Sources', 'TonneCore', 'Providers', 'CatalogLocalities.swift')
KEEP = {'PPL', 'PPLX', 'PPLA', 'PPLA2', 'PPLA3', 'PPLA4', 'PPLC'}


def extract(dump):
    count = 0
    with open(dump, encoding='utf-8') as src, open(TSV, 'w', encoding='utf-8') as out:
        for line in src:
            r = line.rstrip('\n').split('\t')
            if r[6] == 'P' and r[7] in KEEP:
                out.write(f'{r[1]}\t{r[7]}\t{r[13]}\n')
                count += 1
    print(f'{count} Orte nach {TSV}')


def fold(text):
    import unicodedata
    text = unicodedata.normalize('NFD', text.strip().lower())
    return ''.join(c for c in text if not unicodedata.combining(c)).replace('ß', 'ss')


def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--extract':
        extract(sys.argv[2])
    places = {}
    for e in json.load(open(os.path.join(DATA, 'place_map', 'belege.json'), encoding='utf-8')):
        places[e['code'][:5] + e['code'][9:]] = (e['kreis'], e['gemeinde'])
    # Gemeindenamen so, wie die Suche sie kennt (CatalogRegions.municipalities, auch gemeindefreie Gebiete)
    regions = open(os.path.join(REPO, 'TonneCore', 'Sources', 'TonneCore', 'Providers', 'CatalogRegions.swift'), encoding='utf-8').read()
    block = regions.split('static let municipalities: String = #"""\n', 1)[1].split('\n"""#', 1)[0]
    municipality_names = sorted({fold(n) for line in block.split('\n') if '|' in line for n in line.split('|', 1)[1].split(',')})

    def shadowed(name):
        """Wie die Suche (municipalityHits): Gemeinde heißt so oder beginnt so, gefolgt von einem Nicht-Buchstaben."""
        import bisect
        i = bisect.bisect_left(municipality_names, name)
        while i < len(municipality_names) and municipality_names[i].startswith(name):
            rest = municipality_names[i][len(name):]
            if not rest or not rest[0].isalpha():
                return True
            i += 1
        return False

    sources = []
    with open(TSV, encoding='utf-8') as f:
        sources += [('geonames',) + tuple(line.rstrip('\n').split('\t')[::2]) for line in f]
    with open(os.path.join(DATA, 'geo', 'ortsteile.csv'), encoding='utf-8-sig') as f:
        next(f)
        sources += [('abgleich', name, ags) for ags, name in (line.rstrip('\n').split(';', 1) for line in f)]

    by_place = collections.defaultdict(set)
    stats = collections.Counter()
    for source, name, ags in sources:
        name = name.strip()
        stats[source] += 1
        if ags not in places:
            stats[f'{source}: ohne Gemeinde'] += 1
            continue
        if shadowed(fold(name)) or fold(name.split(' (')[0]) == fold(places[ags][1]):
            stats[f'{source}: heißt wie eine Gemeinde'] += 1
            continue
        if ',' in name or '|' in name or len(fold(name)) < 3:
            stats[f'{source}: unbrauchbarer Name'] += 1
            continue
        by_place[places[ags]].add(name)

    lines = [f'{k}|{g}|{",".join(sorted(names))}' for (k, g), names in sorted(by_place.items())]
    total = sum(len(v) for v in by_place.values())
    distinct = len({fold(n) for v in by_place.values() for n in v})
    with open(OUT, 'w', encoding='utf-8') as out:
        out.write('// Erzeugt von tools/catalog/gen_localities.py – nicht von Hand ändern.\n')
        out.write('// Ortsteile: GeoNames (https://www.geonames.org, CC BY 4.0) und Gemeinde-Abgleich.\n\n')
        out.write('enum CatalogLocalities {\n')
        out.write(f'    /// Je Zeile: „Landkreis|Gemeinde|Ortsteil,Ortsteil,…“ – {total} Ortsteile in {len(by_place)} Gemeinden.\n')
        out.write('    static let localities: String = #"""\n' + '\n'.join(lines) + '\n"""#\n}\n')
    for key, value in sorted(stats.items()):
        print(f'{key}: {value}')
    print(f'{total} Ortsteile ({distinct} verschiedene Namen) in {len(by_place)} von {len(places)} Gemeinden → {OUT}')


if __name__ == '__main__':
    main()
