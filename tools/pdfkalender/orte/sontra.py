"""Stadt Sontra (Werra-Meißner-Kreis): A3-Jahresraster mit Werbung. In der Zelle stehen die Bezirksnummern
(„1+2“, „2+3“ …) auf farbigen Flächen: grün Bioabfälle, grau Restmüll, blau Altpapier, gelb Elektroschrott.
Elektroschrott ist eine Annahme am Bauhof (7–12 Uhr, Husarenpark 11, laut sontra.de „Sonstiger Abfall“) und gilt
für alle Bezirke. Weihnachtsbäume: „Abfuhr Weihnachtsbäume 1–3 / 4–6“ im Januar.
Gelbe Tonne: nicht enthalten – die Stadt ist dafür nicht zuständig (Hinweis in der PDF).
Straßen → Bezirk: Verzeichnis „Bezirk 1 … Bezirk 6“ unten auf Seite 1."""
import collections
import re

import common
from orte import colorgrid

PAGE = 'https://www.sontra.de/seite/236198/bio-,-rest-und-papiermüll.html'
PDF = {2026: 'https://daten2.verwaltungsportal.de/dateien/seitengenerator/a702117c2bd33eabfeea1a6c5d97865587538/Abfallkalender_2026_Sontra.pdf'}
PALETTE = [((0.35, 0.69, 0.39), 'Biomüll'), ((0.53, 0.54, 0.55), 'Restmüll'), ((0.16, 0.48, 0.7), 'Altpapier'),
           ((1.0, 0.94, 0.23), 'Elektroschrott')]
ELEKTRO_NOTE = 'Annahme 7–12 Uhr, städtischer Bauhof, Husarenpark 11'
NOTICE = 'Gelbe Tonne nicht enthalten – die Termine veröffentlicht der Entsorger gesondert.'
DISTRICT = re.compile(r'^[1-6](?:\+[1-6])*$')
RANGE = re.compile(r'^([1-6])[–-]([1-6])$')


def calendar(pdf, year):
    cells, notes = common.parse_grid(pdf, year)
    common.assert_grid_ok(notes, 'sontra')
    colorgrid.cell_fills(common.fitz.open(pdf), cells)
    per, everyone = collections.defaultdict(list), []
    for c in cells:
        # Monatsspalten sind ~139 pt breit; rechts daneben (März, Juni …) steht Werbung
        c['words'] = [(x, t) for x, t in c['words'] if x < 132]
        toks = [t for _, t in c['words']]
        if 'Weihnachtsbäume' in toks or 'Abfuhr' in toks:
            for t in toks:
                m = RANGE.match(t)
                if m:
                    for d in range(int(m.group(1)), int(m.group(2)) + 1):
                        per[d].append((c['date'], 'Weihnachtsbäume', None))
        for x, t in c['words']:
            kind = colorgrid.token_kind_vector(c, x, PALETTE, max_width=120)
            if t == 'Elektroschrott' and kind == 'Elektroschrott':
                everyone.append((c['date'], 'Elektroschrott-Annahme', ELEKTRO_NOTE))
            elif DISTRICT.match(t) and kind and kind != 'Elektroschrott':
                for d in map(int, t.split('+')):
                    per[d].append((c['date'], kind, None))
            elif DISTRICT.match(t) and c['x0'] + x < c['right'] - 40:
                raise SystemExit(f'sontra: {c["date"]}: Bezirk „{t}“ ohne bekannte Farbe')
            # sonst: KW-Nummer am rechten Zellrand, Feiertag, Werbung
    return per, everyone


def streets(pdf):
    """Verzeichnis unten auf Seite 1: Spalten mit Überschrift „Bezirk N“, darunter Orte/Straßen."""
    page = common.fitz.open(pdf)[0]
    words = common.page_words(page)
    heads = [w for w in words if w[4] == 'Bezirk']
    top = min(h[1] for h in heads) - 2
    cols = sorted({round(h[0]) for h in heads})
    res = []
    for i, x in enumerate(cols):
        right = cols[i + 1] - 2 if i + 1 < len(cols) else x + 80
        ws = [w for w in words if w[1] >= top and x - 2 <= w[0] < right]
        lines = collections.defaultdict(list)
        for w in ws:
            lines[round(w[1] / 3)].append(w)
        current, carry = None, ''
        for _, lw in sorted(lines.items()):
            text = ' '.join(w[4] for w in sorted(lw, key=lambda w: w[0]))
            m = re.fullmatch(r'Bezirk ([1-6])', text)
            if m:
                current = int(m.group(1))
                continue
            if current is None:
                continue
            text = carry + text
            if text.endswith(','):
                carry = text + ' '
                continue
            carry = ''
            for name in text.split(','):
                res.append((name.strip(), current))
    return res


def run(refresh=False):
    year = max(PDF)
    pdf = common.fetch(PDF[year], f'sontra_{year}.pdf', refresh=refresh)
    per, everyone = calendar(pdf, year)
    if set(per) != set(range(1, 7)):
        raise SystemExit(f'sontra: Bezirke im Kalender {sorted(per)}')
    st = streets(pdf)
    names = collections.Counter(n for n, _ in st)
    if any(v > 1 for v in names.values()):
        raise SystemExit(f'sontra: doppelte Namen {[n for n, v in names.items() if v > 1]}')
    areas = [(common.slug(n), n, None, per[b] + everyone) for n, b in st]
    print(f'sontra: {len(areas)} Straßen/Orte, je Bezirk {collections.Counter(b for _, b in st)}')
    common.write_output('sontra', 'Stadt Sontra', PDF[year], [year], areas, step_title='Straße / Ortsteil', notice=NOTICE)
