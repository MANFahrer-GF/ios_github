"""Gemeinde Büsingen am Hochrhein (Landkreis Konstanz, Exklave in der Schweiz): die Gemeinde entsorgt selbst
(Schweizer System mit Schwarzabfuhr). Zwei Halbjahres-PDFs „Abholtermine 2026“ auf buesingen.de.
Raster: Zeilen = Tag (1–31, ohne Wochentag), Spalten = Monate; ein Tag kann mehrere Einträge untereinander haben
(Tageszahl steht oben in der Zeile). Ohne Wochentag in der Zelle gibt es keine Wochentag-Probe; stattdessen
wird geprüft, dass jede Tageszahl 1–31 genau einmal je Seite vorkommt und Einträge nur in gültigen Tagen liegen.
Sperrgut- und Giftmüllsammlungen stehen nicht im Kalender (laut PDF im Gemeindebrief)."""
import collections
import datetime
import re

import common

PAGE = 'https://www.buesingen.de/de/Rathaus/Abfallentsorgung'
PDF = {(2026, 1): 'https://www.buesingen.de/ceasy/resource/?id=2838&download=1',  # Januar bis Juni 2026
       (2026, 7): 'https://www.buesingen.de/ceasy/resource/?id=2837&download=1'}  # Juli bis Dezember 2026
MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember']
KINDS = {'Schwarzabfuhr': ('Restmüll (Schwarzabfuhr)', 'ab 13 Uhr'), 'Grünmüll': ('Grünmüll', None),
         'Gelber Sack': ('Gelber Sack', None), 'Altpapier': ('Altpapier', '9.00–11.30 Uhr')}


def half(pdf, year, first_month):
    page = common.fitz.open(pdf)[0]
    title = page.get_text()
    want = f'Abfallkalender {MONTHS[first_month - 1]} bis {MONTHS[first_month + 4]} {year}'
    if want not in re.sub(r'\s+', ' ', title):
        raise SystemExit(f'buesingen: Titel „{want}“ nicht gefunden')
    ws = common.page_words(page)
    heads = {m: next(w for w in ws if w[4] == MONTHS[m - 1]) for m in range(first_month, first_month + 6)}
    notiz = next(w for w in ws if w[4] == 'Notizen')
    top = max(h[3] for h in heads.values())
    days = sorted((w for w in ws if re.fullmatch(r'\d{1,2}', w[4]) and w[0] < heads[first_month][0] and w[1] > top),
                  key=lambda w: w[1])
    if [int(w[4]) for w in days] != list(range(1, 32)):
        raise SystemExit(f'buesingen: Tageszahlen {[w[4] for w in days]}')
    bottom = days[-1][3] + 12
    xs = sorted((h[0], m) for m, h in heads.items())
    events = []
    lines = collections.defaultdict(list)
    for w in ws:
        if top < w[1] < bottom and xs[0][0] - 3 <= w[0] < notiz[0] - 3:
            lines[(round(w[1]), max(m for x, m in xs if x - 3 <= w[0]))].append(w)
    for (y, m), lw in lines.items():
        text = ' '.join(w[4] for w in sorted(lw, key=lambda w: w[0]))
        day = int(max((d for d in days if d[1] <= y + 2), key=lambda d: d[1])[4])
        if text not in KINDS:
            raise SystemExit(f'buesingen: {day}.{m}.: unbekannt {text!r}')
        try:
            date = datetime.date(year, m, day)
        except ValueError:
            raise SystemExit(f'buesingen: Eintrag an ungültigem Tag {day}.{m}.')
        events.append((date,) + KINDS[text])
    return events


def run(refresh=False):
    events = []
    for (year, first), url in PDF.items():
        events += half(common.fetch(url, f'buesingen_{year}_{first:02d}.pdf', refresh=refresh), year, first)
    wd = collections.defaultdict(collections.Counter)
    for d, k, _ in events:
        wd[k][d.strftime('%a')] += 1
    print(f'  [buesingen] Wochentage je Art (Plausibilität): {dict(wd)}')
    common.write_output('buesingen', 'Gemeinde Büsingen am Hochrhein', PAGE, sorted({y for y, _ in PDF}),
                        [('buesingen', 'Büsingen am Hochrhein', None, events)], step_title='Ort')
