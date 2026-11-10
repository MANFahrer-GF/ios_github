#!/usr/bin/env python3
"""Erzeugt TonneCore/Sources/TonneCore/Providers/CatalogPlaceMap.swift: die belegte Zuordnung Gemeinde → Katalogeinträge.

    python3 tools/catalog/gen_place_map.py

Eingaben (beide im Repo, damit der Lauf ohne Netz wiederholbar ist):
  data/place_map/belege.json   – aus `place_coverage.py … --map data/place_map/belege.json`
  data/place_map/luecken.json  – ausdrückliche Lücken je amtlichem Schlüssel: {"art": "nicht_holbar"|"offen", "grund": …}

Jede Gemeinde steht in genau einer der beiden Mengen. Fehlt eine in beiden oder steht eine in beiden, bricht der Lauf ab
(und der feste Test PlaceMapTests wird rot). App und Messung lesen dieselbe erzeugte Datei.
"""
import json, os, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(REPO, 'tools', 'catalog', 'data', 'place_map')
OUT = os.path.join(REPO, 'TonneCore', 'Sources', 'TonneCore', 'Providers', 'CatalogPlaceMap.swift')


def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    rows = json.load(open(os.path.join(DATA, 'belege.json'), encoding='utf-8'))
    gaps = json.load(open(os.path.join(DATA, 'luecken.json'), encoding='utf-8'))
    mapped = {r['code'] for r in rows if r['eintraege']}
    codes = {r['code'] for r in rows}
    errors = [f'weder Zuordnung noch Lücke: {r["kreis"]}|{r["gemeinde"]}' for r in rows
              if not r['eintraege'] and r['code'] not in gaps]
    errors += [f'Zuordnung UND Lücke: {c}' for c in gaps if c in mapped]
    errors += [f'Lücke für unbekannten Schlüssel: {c}' for c in gaps if c not in codes]
    errors += [f'Lücke ohne Grund oder mit unbekannter Art: {c}' for c, g in gaps.items()
               if g.get('art') not in ('nicht_holbar', 'offen') or not g.get('grund')]
    if errors:
        sys.exit('\n'.join(errors[:40]) + f'\n{len(errors)} Fehler')

    ids = sorted({e for r in rows for e in r['eintraege']})
    index = {e: i for i, e in enumerate(ids)}
    # Zwei Gemeinden gleichen Namens im selben Kreis (Neuenkirchen, Vorpommern-Greifswald) teilen sich eine Zeile.
    place_lines, gap_lines = {}, {}
    for r in rows:
        key = f'{r["kreis"]}|{r["gemeinde"]}'
        if r['eintraege']:
            place_lines.setdefault(key, set()).update(index[e] for e in r['eintraege'])
        else:
            gap_lines[key] = gaps[r['code']]
    reasons = sorted({g['grund'] for g in gap_lines.values()})
    rindex = {g: i for i, g in enumerate(reasons)}
    out = ['// Erzeugt von tools/catalog/gen_place_map.py – nicht von Hand ändern.', 'import Foundation', '',
           '/// Belegte Zuordnung Gemeinde → Katalogeinträge (Abgleich der echten Ortslisten je Gemeinde).',
           'enum CatalogPlaceMap {',
           '    /// Katalogeinträge (`CatalogEntry.id`), auf die sich `places` mit ihrer Position bezieht.',
           '    static let entryIDs: [String] = [']
    out += ['        ' + q(e) + ',' for e in ids]
    out += ['    ]', '', '    /// Je Zeile: „Landkreis|Gemeinde=Position,Position“.', '    static let places: String = #"""']
    out += [k + '=' + ','.join(str(i) for i in sorted(v)) for k, v in sorted(place_lines.items())]
    out += ['"""#', '', '    /// Gründe der ausdrücklichen Lücken, auf die sich `gaps` bezieht.', '    static let gapReasons: [String] = [']
    out += ['        ' + q(g) + ',' for g in reasons]
    out += ['    ]', '',
            '    /// Je Zeile: „Landkreis|Gemeinde=Art,Grund“; Art n = nachweislich kein abrufbarer Kalender, o = noch nicht belegt.',
            '    static let gaps: String = #"""']
    out += [f'{k}={g["art"][0]},{rindex[g["grund"]]}' for k, g in sorted(gap_lines.items()) if k not in place_lines]
    out += ['"""#', '}', '']
    open(OUT, 'w', encoding='utf-8').write('\n'.join(out))
    kinds = [g['art'] for k, g in gap_lines.items() if k not in place_lines]
    print('Gemeinden', len(rows), 'belegt', len(mapped), 'nicht holbar', kinds.count('nicht_holbar'), 'offen', kinds.count('offen'))


if __name__ == '__main__':
    main()
