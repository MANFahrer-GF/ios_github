"""Stadt Rahden (Kreis Minden-Lübbecke): Seite 1 Jahresraster, in der Zelle der Bezirk (To/We, Ost, West,
Pr.Str., Va/Si), die Abfallart als Farbkästchen (grau Restmüll, grün Biomüll, blau Papier, gelb Gelbe Tonne,
rot Sperrmüll, rosa Schadstoff). „!“ = geänderter Abfuhrtermin (Legende).
Sperrmüll (16.01., 24.04., 17.07., 20.10.) und Schadstoffannahme (03.01., 04.04., 04.07., 10.10.) gelten laut
Infokasten für alle Bezirke, auch wenn das Kästchen in der Zeile eines Bezirks steht.
Seite 2: Straßenverzeichnis Straße → Abfuhrbezirk (wird zur Auswahl in der App)."""
import collections
import re

import common
from orte import colorgrid

PDF = {2026: 'https://www.rahden.de/wp-content/uploads/Abfall-Entsorgungskalender2026.pdf'}
PALETTE = [((0.57, 0.82, 0.31), 'Biomüll'), ((0.55, 0.71, 0.89), 'Altpapier'), ((0.75, 0.75, 0.75), 'Restmüll'),
           ((1.0, 1.0, 0.0), 'Gelbe Tonne'), ((1.0, 0.0, 0.0), 'Sperrmüll'), ((1.0, 0.6, 0.8), 'Schadstoffannahme')]
IGNORE = [(1.0, 1.0, 1.0)]
CITYWIDE = {'Sperrmüll': 'nur mit Anmeldung bei der Stadt Rahden (spätestens eine Woche vorher), kostenpflichtig',
            'Schadstoffannahme': '9–11 Uhr, Betriebshof AMR Entsorgung, Wellerstraße 15'}
BEZIRKE = {'To/We': 'Tonnenheide/Wehe', 'Ost': 'Rahden Ost', 'West': 'Rahden West', 'Pr.Str.': 'Pr. Ströhen',
           'Va/Si': 'Varl/Sielhorst'}
SHIFTED = 'geänderter Abfuhrtermin'


def calendar(pdf, year):
    cells, notes = common.parse_grid(pdf, year, pages=[0])
    common.assert_grid_ok(notes, 'rahden')
    colorgrid.cell_fills(common.fitz.open(pdf), cells)
    per, everyone = collections.defaultdict(list), []
    for c in cells:
        kinds, unknown = colorgrid.cell_kinds(c, PALETTE, IGNORE)
        if not kinds:
            continue
        words = [t for _, t in c['words']]
        text = ' '.join(t for t in words if t not in ('!', 'Schadst.', 'Sperr.'))
        if unknown or (kinds - set(CITYWIDE) and text not in BEZIRKE):
            raise SystemExit(f'rahden: {c["date"]}: unklar {words} {unknown}')
        note = SHIFTED if '!' in words else None
        for k in kinds:
            if k in CITYWIDE:
                everyone.append((c['date'], k, CITYWIDE[k]))
            else:
                per[text].append((c['date'], k, note))
    return per, everyone


def streets(pdf):
    """Straßenverzeichnis (Seite 2): Spalten „Straße | Abfuhrbezirk“, Einträge teils zweizeilig."""
    page = common.fitz.open(pdf)[1]
    words = common.page_words(page)
    heads = sorted(w[0] for w in words if w[4] == 'Abfuhr-')
    if len(heads) != 7:
        raise SystemExit(f'rahden: Straßenverzeichnis hat {len(heads)} statt 7 Spalten')
    top = max(w[3] for w in words if w[4] == 'bezirk') + 2
    result = []
    for i, bx in enumerate(heads):
        # Bezirksspalte: ab „Abfuhr-“ gut 20 pt breit; Namensspalte: dazwischen
        left = heads[i - 1] + 22 if i else 0
        col = [w for w in words if w[1] > top and left <= w[0] < bx + 22]
        lines = collections.defaultdict(list)
        for w in col:
            lines[round((w[1] + w[3]) / 2 / 2.5)].append(w)
        entries = []
        for _, ws in sorted(lines.items()):
            ws.sort(key=lambda w: w[0])
            name = [w for w in ws if w[0] < bx - 2]
            bez = [w[4] for w in ws if w[0] >= bx - 2]
            # Registerbuchstabe links vor der Namensspalte („A Ahlfeld“) weglassen
            if len(name) > 1 and re.fullmatch(r'[A-ZÄÖÜ]', name[0][4]) and name[1][4][:1].isupper():
                name = name[1:]
            entries.append([' '.join(w[4] for w in name), ''.join(bez) or None])
        merged = []
        for i2, (text, bez) in enumerate(entries):
            if merged and merged[-1][1] is None:  # Vorzeile ohne Bezirk ging weiter
                merged[-1] = [merged[-1][0] + ' ' + text, bez]
            elif bez is None and merged and not text.endswith(','):
                merged[-1][0] += ' ' + text  # Fortsetzung („erfolgt an der Specker Str.)“)
            else:
                merged.append([text, bez])
        result += [(t.strip(), b) for t, b in merged if t.strip()]
    bad = [r for r in result if r[1] not in BEZIRKE]
    if bad:
        raise SystemExit(f'rahden: Straßen ohne gültigen Bezirk: {bad[:10]}')
    return result


def run(refresh=False):
    year = max(PDF)
    pdf = common.fetch(PDF[year], f'rahden_{year}.pdf', refresh=refresh)
    per, everyone = calendar(pdf, year)
    if set(per) != set(BEZIRKE):
        raise SystemExit(f'rahden: Bezirke im Kalender {sorted(per)}')
    areas, ids = [], collections.Counter()
    for street, bez in streets(pdf):
        sid = common.slug(street)
        ids[sid] += 1
        areas.append((sid, street, None, per[bez] + everyone))
    dup = [k for k, n in ids.items() if n > 1]
    if dup:
        raise SystemExit(f'rahden: doppelte Straßen {dup}')
    print(f'rahden: {len(areas)} Straßen, Bezirke {collections.Counter(b for _, b in streets(pdf))}')
    common.write_output('rahden', 'Stadt Rahden', PDF[year], [year], areas, step_title='Straße')
