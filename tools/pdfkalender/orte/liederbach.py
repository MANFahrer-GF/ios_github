"""Gemeinde Liederbach am Taunus (Main-Taunus-Kreis): ein Kalender für die ganze Gemeinde (Halbjahresseiten).
Kürzel als Text; „RM“ hat drei Bedeutungen, die nur die Kastenfarbe unterscheidet (Legende):
dunkelgrau = Restmüll 14-täglich (60–240 l), lachs = 1,1-m³-Behälter 1. Leerung, hellgrau = 1,1-m³-Behälter 2. Leerung.
„Wsh geschlossen“ (Wertstoffhof) und Feiertage sind keine Abfuhr."""
import re

import common
from orte import colorgrid
from orte._holidays import HOLIDAYS

PAGE = 'https://www.liederbach.eu/seite/de/cms09102026105224fed68926/044:430/-/Abfall_und_Entsorgung.html'
PDF = {2026: 'https://www.liederbach.eu/eigene_dateien/aktuell/2023-aktuelles/september/liederbachmuell_2026.pdf'}
RM_COLORS = [((0.25, 0.25, 0.25), 'Restmüll'),
             ((0.97, 0.77, 0.64), 'Restmüll 1,1-m³-Behälter (1. Leerung)'),
             ((0.78, 0.78, 0.78), 'Restmüll 1,1-m³-Behälter (2. Leerung)')]
TEXT = {'Bio': ('Biomüll', None), 'LVP': ('Gelber Sack', None), 'Papier': ('Altpapier', None),
        'Garten': ('Grünschnitt', None), 'Christbäume': ('Weihnachtsbäume', None),
        'S&E': ('Sperrmüll und Elektrogeräte', 'nur nach Anmeldung (069 30098-0) bis Donnerstag davor 12 Uhr')}
SONDER = 'Sondermüll-Kleinmengensammlung'
SONDER_NOTE = 'ohne Anmeldung, großer Parkplatz Liederbachhalle'


def run(refresh=False):
    events = []
    for year, url in PDF.items():
        pdf = common.fetch(url, f'liederbach_{year}.pdf', refresh=refresh)
        cells, notes = common.parse_grid(pdf, year)
        common.assert_grid_ok(notes, 'liederbach')
        colorgrid.cell_fills(common.fitz.open(pdf), cells)
        for c in cells:
            toks = [t for _, t in c['words']]
            text = ' '.join(toks).replace('S & E', 'S&E')
            times = re.findall(r'(\d{1,2}(?::\d\d)?\s*-\s*\d{1,2}:\d\d)\s*h', text)
            if 'Sondermüll' in toks or times:
                if len(times) != 1:
                    raise SystemExit(f'liederbach: {c["date"]}: Sondermüll ohne eindeutige Uhrzeit {text!r}')
                t = times[0].replace(' ', '').replace('-', '–')
                events.append((c['date'], SONDER, f'{t} Uhr, {SONDER_NOTE}'))
                text = re.sub(r'Sondermüll|\d{1,2}(?::\d\d)?\s*-\s*\d{1,2}:\d\d\s*h', ' ', text)
            for x, tok in c['words']:
                if tok == 'RM':
                    kind = colorgrid.token_kind_vector(c, x, RM_COLORS)
                    if not kind:
                        raise SystemExit(f'liederbach: {c["date"]}: RM ohne bekannte Farbe')
                    events.append((c['date'], kind, None))
            rest = text.replace('RM', ' ').split()
            for tok in rest:
                if tok in TEXT:
                    events.append((c['date'],) + TEXT[tok])
            leftover = ' '.join(t for t in rest if t not in TEXT).lower()
            if leftover and leftover != 'wsh geschlossen' and not any(leftover.startswith(h) for h in HOLIDAYS):
                raise SystemExit(f'liederbach: {c["date"]}: nicht zugeordnet {leftover!r}')
    common.write_output('liederbach', 'Gemeinde Liederbach am Taunus', PDF[max(PDF)], sorted(PDF),
                        [('liederbach', 'Liederbach am Taunus', None, events)], step_title='Ort')
