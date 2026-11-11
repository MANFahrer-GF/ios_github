#!/usr/bin/env python3
"""Erzeugt TonneCore/Sources/TonneCore/Providers/CatalogPlaceMap.swift: die belegte Zuordnung Gemeinde → Katalogeinträge.

    python3 tools/catalog/gen_place_map.py

Eingaben (beide im Repo, damit der Lauf ohne Netz wiederholbar ist):
  data/place_map/belege.json   – aus `place_coverage.py … --map data/place_map/belege.json`
  data/place_map/luecken.json  – ausdrückliche Lücken je amtlichem Schlüssel: {"art": "nicht_holbar"|"offen", "grund": …}

Jede Gemeinde steht in genau einer der beiden Mengen. Fehlt eine in beiden oder steht eine in beiden, bricht der Lauf ab
(und der feste Test PlaceMapTests wird rot). App und Messung lesen dieselbe erzeugte Datei.
"""
import datetime
import json, os, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(REPO, 'tools', 'catalog', 'data', 'place_map')
OUT = os.path.join(REPO, 'TonneCore', 'Sources', 'TonneCore', 'Providers', 'CatalogPlaceMap.swift')



def is_iso_date(text):
    """Echtes Kalenderdatum JJJJ-MM-TT (2026-02-30 gilt nicht)."""
    try:
        return len(str(text)) == 10 and datetime.date.fromisoformat(str(text)).isoformat() == str(text)
    except ValueError:
        return False

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
    # Nicht holbar gilt nur mit bekanntem Grund; „nur PDF“ braucht Entsorger, Seite und Datum der Prüfung.
    errors += [f'nicht holbar mit unbekanntem Grund: {c}' for c, g in gaps.items()
               if g.get('art') == 'nicht_holbar' and g.get('grund') not in ('portal_abgeschaltet', 'nur_pdf', 'nicht_gefuehrt')]
    # „nicht geführt“ (der zuständige Entsorger führt die Gemeinde online nicht) braucht dieselben Belege.
    errors += [f'{g.get("grund")} ohne entsorger/url/stand/beleg: {c}' for c, g in gaps.items()
               if g.get('art') == 'nicht_holbar' and not all(g.get(f) for f in ('entsorger', 'url', 'stand', 'beleg'))]
    # Die App zeigt Entsorger, Link und Stand je Lücke: nur öffentliche Webseiten (https), Stand als Datum JJJJ-MM-TT.
    errors += [f'url nicht https oder stand kein Datum: {c}' for c, g in gaps.items() if g.get('art') == 'nicht_holbar'
               and not (str(g.get('url', '')).startswith('https://') and is_iso_date(g.get('stand')))]
    errors += [f'Trennzeichen | in entsorger/url: {c}' for c, g in gaps.items() if '|' in g.get('entsorger', '') + g.get('url', '')]
    errors += [f'nicht_gefuehrt ohne art nicht_holbar: {c}' for c, g in gaps.items()
               if g.get('grund') == 'nicht_gefuehrt' and g.get('art') != 'nicht_holbar']
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
    # Entsorger, Webseite und Stand der Prüfung, je Lücke über ihre Position (viele Gemeinden teilen einen Entsorger).
    sources = sorted({(g['entsorger'], g['url'], g['stand']) for g in gap_lines.values() if g.get('entsorger')})
    sindex = {s: i for i, s in enumerate(sources)}
    out += ['    ]', '', '    /// Je Eintrag: „Entsorger|Webseite|Stand der Prüfung (JJJJ-MM-TT)“, auf die sich `gaps` bezieht.',
            '    static let gapSources: [String] = [']
    out += ['        ' + q('|'.join(s)) + ',' for s in sources]
    out += ['    ]', '',
            '    /// Je Zeile: „Landkreis|Gemeinde=Art,Grund[,Quelle]“; Art n = nachweislich kein abrufbarer Kalender, o = noch nicht belegt.',
            '    static let gaps: String = #"""']
    out += [f'{k}={g["art"][0]},{rindex[g["grund"]]}'
            + (f',{sindex[(g["entsorger"], g["url"], g["stand"])]}' if g.get('entsorger') else '')
            for k, g in sorted(gap_lines.items()) if k not in place_lines]
    out += ['"""#', '}', '']
    open(OUT, 'w', encoding='utf-8').write('\n'.join(out))
    kinds = [g['art'] for k, g in gap_lines.items() if k not in place_lines]
    print('Gemeinden', len(rows), 'belegt', len(mapped), 'nicht holbar', kinds.count('nicht_holbar'), 'offen', kinds.count('offen'))


if __name__ == '__main__':
    main()
