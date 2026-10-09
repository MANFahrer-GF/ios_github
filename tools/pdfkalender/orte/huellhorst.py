"""Gemeinde Hüllhorst (Kreis Minden-Lübbecke): ein Jahreskalender für die ganze Gemeinde (Serviceportal,
„Abfuhrkalender / Sortierhilfe 2026“). Die Abfallart steckt in farbigen Kästchen am rechten Zellrand:
schwarz R Restabfall, blau P Papier, braun B Biotonne bzw. S Bio- und Sommerbiotonne, gelb G Gelbe Tonne,
orange C Gelbe Container (1.100 l), grün X Sperrmüll (nach Anmeldung), rot Sondermüll (Wertstoffhof).
Achtung: Die Textebene der PDF ist unzuverlässig (Buchstaben doppelt und um eine Zeile versetzt, Wochentage
30./31.07. falsch) – maßgeblich sind die Kästchen; der Buchstabe wird nur innerhalb des Kästchens gelesen.
Gegenprobe: Die Gemeinde verlinkt auf derselben Seite eine Kalenderdatei (ICS) mit allen Terminen; check_ics()
vergleicht beide und bricht bei Abweichungen ab."""
import collections
import datetime
import re

import common

PAGE = 'https://serviceportal.huellhorst.de/detail/-/vr-bis-detail/dienstleistung/10882/show'
PDF = {2026: 'https://serviceportal.huellhorst.de:443/detail/-/vr-bis-detail/dokument/39157/download?_19_WAR_vrportlet_priv_r_p_action=vr-bis-detail-dienstleistung-show'}
ICS = {2026: 'https://serviceportal.huellhorst.de/documents/d/guest/kalenderimport-abfuhrtermine-hullhorst-2026'}
BOX = [((0.0, 0.0, 0.0), 'R'), ((0.32, 0.55, 0.84), 'P'), ((0.8, 0.4, 0.0), 'B/S'), ((1.0, 1.0, 0.0), 'G'),
       ((1.0, 0.75, 0.0), 'C'), ((0.25, 1.0, 0.13), 'X'), ((1.0, 0.0, 0.0), 'rot')]
NAMES = {'R': ('Restmüll', None), 'P': ('Altpapier', None), 'B': ('Biomüll', None),
         'S': ('Biomüll und Sommerbiotonne', None), 'G': ('Gelbe Tonne', None),
         'C': ('Gelbe Container (1.100 l)', None), 'X': ('Sperrmüll', 'nur nach Anmeldung bei der EMiL-AöR'),
         'rot': ('Sondermüll-Annahme', 'Wertstoffhof der EMiL-AöR, Hüllhorst')}
# Bezeichnungen der ICS-Datei → Kürzel des Kalenders (nur für die Gegenprobe)
ICS_MAP = {'Restabfalltonne': 'R', 'Papiertonne': 'P', 'Biotonne': 'B', '(Sommer-)Biotonne': 'S', 'Gelbe Tonne': 'G',
           'Gelbe Container (1.1 cbm)': 'C', 'Sperrmüllabfuhr (Anmeldung erforderlich)': 'X', 'Sondermüll (Wertstoffhof)': 'rot'}


def calendar(pdf, year):
    doc = common.fitz.open(pdf)
    cells, notes = common.parse_grid(pdf, year)
    common.assert_grid_ok(notes, 'huellhorst')
    words = {p: common.page_words(doc[p]) for p in range(len(doc))}
    fills = {p: common.page_fills(doc[p]) for p in range(len(doc))}
    out = []
    for c in cells:
        for r, col in fills[c['page']]:
            cy = (r.y0 + r.y1) / 2
            if not (c['y0'] - 2 <= cy <= c['y1'] + 2 and c['x0'] - 3 <= r.x0 and r.x1 <= c['right'] + 3 and r.width < 30):
                continue
            code = next((n for ref, n in BOX if common.near(col, ref)), None)
            if code is None:
                continue
            if code == 'B/S':
                inside = [w[4] for w in words[c['page']] if r.x0 <= (w[0] + w[2]) / 2 <= r.x1 and r.y0 <= (w[1] + w[3]) / 2 <= r.y1]
                letters = set(inside) & {'B', 'S'}
                if len(letters) != 1:
                    raise SystemExit(f'huellhorst: {c["date"]}: braunes Kästchen ohne eindeutigen Buchstaben {inside}')
                code = letters.pop()
            out.append((c['date'], code))
    return out


def check_ics(events, ics_path, year):
    text = open(ics_path, encoding='utf-8', errors='replace').read()
    ref = set()
    for block in text.split('BEGIN:VEVENT')[1:]:
        d = re.search(r'DTSTART[^:]*:(\d{8})', block).group(1)
        s = re.search(r'SUMMARY[^:]*:(.*)', block).group(1).strip()
        ref.add((datetime.datetime.strptime(d, '%Y%m%d').date(), ICS_MAP[s]))
    mine = set(events)
    if mine != ref:
        raise SystemExit(f'huellhorst: PDF ≠ ICS – nur PDF {sorted(mine - ref)}, nur ICS {sorted(ref - mine)}')
    print(f'  [huellhorst] Gegenprobe ICS: {len(ref)} Termine identisch')


def run(refresh=False):
    year = max(PDF)
    pdf = common.fetch(PDF[year], f'huellhorst_{year}.pdf', refresh=refresh)
    events = calendar(pdf, year)
    check_ics(events, common.fetch(ICS[year], f'huellhorst_{year}.ics', refresh=refresh), year)
    rows = [(d,) + NAMES[code] for d, code in events]
    print(f'  [huellhorst] {collections.Counter(code for _, code in events)}')
    common.write_output('huellhorst', 'Gemeinde Hüllhorst', PDF[year], [year],
                        [('huellhorst', 'Hüllhorst', None, rows)], step_title='Ort')
