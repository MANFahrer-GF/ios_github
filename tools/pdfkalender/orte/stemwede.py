"""Gemeinde Stemwede (Kreis Minden-Lübbecke): Jahresraster (Excel). In der Zelle stehen nur die Ortsteile
(z. B. „AK/WT/WD“), die Abfallart ist die Zellfarbe: grau Restmüll, grün Biomüll, blau Altpapier,
gelber Streifen Gelbe Tonne (Legende unten auf Seite 2). „!“ markiert verschobene Termine.
Bekannte Tippfehler im Original 2026 (von der Wochentag-Probe gefunden, richtig aufgelöst):
11.10. ist als „15 So“ gedruckt, 21.11. als „21 So“ – beides leere Tage."""
import re

import common
from orte import colorgrid

PAGE = 'https://www.stemwede.de/bauen-wirtschaft-klimaschutz/abfall/'
PDF = {2026: 'https://www.stemwede.de/bauen-wirtschaft-klimaschutz/abfall/2026/gemeinde-stemwede-abfallkalender-2026.pdf?cid=5sa'}
PALETTE = [((0.57, 0.82, 0.31), 'Biomüll'), ((0.55, 0.71, 0.89), 'Altpapier'),
           ((0.85, 0.85, 0.85), 'Restmüll'), ((1.0, 1.0, 0.0), 'Gelbe Tonne')]
IGNORE = [(0.9, 0.9, 0.9), (1.0, 1.0, 1.0)]
ORTSTEILE = {'AK': 'Arrenkamp', 'WT': 'Westrup', 'WD': 'Wehdem', 'LV': 'Levern', 'DT': 'Destel',
             'TW-Nord': 'Twiehausen-Nord', 'TW-Süd': 'Twiehausen-Süd', 'OD': 'Oppendorf', 'OW': 'Oppenwehe',
             'DL': 'Dielingen', 'HA': 'Haldem', 'DN': 'Drohne', 'SN': 'Sundern', 'NM': 'Niedermehnen'}
SHIFTED = 'verschobener Termin (im Kalender mit „!“ markiert)'


def run(refresh=False):
    per = {k: [] for k in ORTSTEILE}
    for year, url in PDF.items():
        pdf = common.fetch(url, f'stemwede_{year}.pdf', refresh=refresh)
        cells, notes = common.parse_grid(pdf, year)
        common.assert_grid_ok(notes, 'stemwede')
        colorgrid.cell_fills(common.fitz.open(pdf), cells)
        for c in cells:
            kinds, unknown = colorgrid.cell_kinds(c, PALETTE, IGNORE)
            words = [t for _, t in c['words']]
            text = ' '.join(t for t in words if t != '!')
            codes = [p for p in re.split(r'/', text) if p]
            if not kinds:
                continue
            if unknown or not codes or any(p not in ORTSTEILE for p in codes):
                raise SystemExit(f'stemwede: {c["date"]}: unklar {text!r} {unknown}')
            note = SHIFTED if '!' in words else None
            for code in codes:
                for k in kinds:
                    per[code].append((c['date'], k, note))
    areas = [(common.slug(name), name, None, per[code]) for code, name in sorted(ORTSTEILE.items(), key=lambda kv: kv[1])]
    common.write_output('stemwede', 'Gemeinde Stemwede', PDF[max(PDF)], sorted(PDF), areas, step_title='Ortsteil')
