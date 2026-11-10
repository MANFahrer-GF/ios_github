#!/usr/bin/env python3
"""Legt das Quellenverzeichnis von „Waste Collection Schedule“ (Home Assistant, sources.json) gegen die Gemeinden,
die laut place_coverage.py noch keinen Entsorger haben.

    python3 tools/catalog/hacs_gap.py <gemeinden.json> <hacs-sources.json> [--out <datei>]

Je offener Gemeinde: Quellen, deren Titel den Gemeindenamen als ganzes Wort enthält („AWL Neuss“ → Neuss),
getrennt nach „Bauart haben wir schon“ (nur eintragen) und „Bauart fehlt“ (Anbieter nachbauen).
"""
import collections, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import place_coverage as pc

# Bauarten von Waste Collection Schedule, für die TonneCore schon einen Anbieter hat
HAVE = {'ics': 'icsURL', 'app_abfallplus_de': 'abfallPlusApp', 'awido_de': 'awido', 'jumomind_de': 'jumomind',
        'lobbe_app': 'lobbe', 'abfall_io': 'abfallIOLegacy', 'abfallnavi_de': 'abfallnavi',
        'heimat_info_de': 'heimatInfo', 'c_trace_de': 'cTrace', 'muellmax_de': 'muellmax',
        'abfall_io_graphql': 'abfallIOGraphQL', 'hausmuell_info': 'hausmuellInfo', 'insert_it_de': 'insertIT',
        'muellabfuhr_de': 'muellabfuhrDeutschland', 'buergerportal_de': 'buergerportal',
        'nerdbridge_de': 'nerdbridge', 'magdeburg_de': 'magdeburg', 'awlneuss_de': 'calendarPortal',
        'citiesapps_com': None}


def main():
    args = sys.argv[1:]
    out_path = None
    if '--out' in args:
        i = args.index('--out')
        out_path = args[i + 1]
        del args[i:i + 2]
    places = json.load(open(args[0], encoding='utf-8'))
    sources = json.load(open(args[1], encoding='utf-8'))['Germany']
    folded = [(' ' + pc.fold(s['title']) + ' ', s) for s in sources]
    rows = []
    for r in places:
        if r['status'] not in ('fehlt', 'unklar', 'ohne'):
            continue
        names = {k for k in pc.keys(r['gemeinde']) if len(k) >= 4}
        hits = [s for text, s in folded if any(' ' + n + ' ' in text for n in names)]
        if not hits:
            continue
        rows.append({'land': r['land'], 'kreis': r['kreis'], 'gemeinde': r['gemeinde'], 'status': r['status'],
                     'vorhanden': sorted({(s['module'], s['title']) for s in hits if s['module'] in HAVE}),
                     'neu': sorted({(s['module'], s['title']) for s in hits if s['module'] not in HAVE})})
    open_count = sum(1 for r in places if r['status'] in ('fehlt', 'unklar', 'ohne'))
    print('offen', open_count, 'mit Quelle', len(rows),
          'davon Bauart vorhanden', sum(1 for r in rows if r['vorhanden']),
          'nur neue Bauart', sum(1 for r in rows if r['neu'] and not r['vorhanden']))
    mods = collections.Counter(m for r in rows for m, _ in r['neu'])
    print('neue Bauarten', len(mods), mods.most_common(12))
    if out_path:
        json.dump(rows, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)


if __name__ == '__main__':
    main()
