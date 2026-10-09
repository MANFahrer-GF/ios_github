"""Gemeinde Mainhausen (Landkreis Offenbach): InDesign-Jahresraster. In der Zelle stehen farbige Balken mit den
Bezirksnummern („1+2“, „1-4“ …); die Abfallart ist nur die Balkenfarbe (blau Papier, grau Restmüll, braun Bio,
gelb Gelber Sack, grün saisonaler Grünschnitt bzw. mit „WB“ Weihnachtsbäume, rot „Z“/„M“ Schadstoffmobil).
Die Balken sind keine einfachen Vektorflächen, darum wird die Farbe aus dem gerenderten Bild gelesen.
Schadstoffmobil: Termine/Uhrzeiten aus dem Textblock unter dem Raster, gegen die Z/M-Zellen geprüft.
Straßen → Bezirk aus der eigenen PDF „Müllabfuhrbezirke“ (Stand Oktober 2017, weiterhin verlinkt)."""
import collections
import datetime
import re
import subprocess

import common
from orte import colorgrid
from orte._holidays import HOLIDAYS

PAGE = 'https://www.mainhausen.de/bauen-umwelt-abfall/abfallwirtschaft/abfallkalender'
BASE = 'https://www.mainhausen.de/fileadmin/Dateien/Cross7/Startseite/Bauen%2C_Umwelt_%26_Abfall/Abfallwirtschaft/'
PDF = {2026: BASE + 'Abfallkalender/abfallkalender-2026-web.pdf'}
BEZ_PDF = BASE + 'Mullabfuhrbezirke/muellbezirke-mainhausen.pdf'
ORTE = {'Zellhausen': 'Zellhausen, Ostring gegenüber Hausnummer 25',
        'Mainflingen': 'Mainflingen, Parkplatz am TSG-Sportplatz, Am Sportplatz 1'}
DISTRICT = re.compile(r'^[1-4](?:[+-][1-4])*$')


def kind_of(col):
    r, g, b = col
    if r < 0.2 and g > 0.35 and b > 0.6:
        return 'Altpapier'
    if abs(r - g) < 0.06 and abs(g - b) < 0.06 and 0.3 < r < 0.6:
        return 'Restmüll'
    if r > 0.45 and 0.25 < g < 0.45 and b < 0.25:
        return 'Biomüll'
    if r > 0.9 and g > 0.85 and b < 0.5:
        return 'Gelber Sack'
    if g > 0.55 and r < 0.4 and b < 0.4:
        return 'grün'
    if r > 0.7 and g < 0.3 and b < 0.3:
        return 'rot'
    return None


def districts(spec):
    out = set()
    for part in spec.split('+'):
        if '-' in part:
            a, b = part.split('-')
            out |= set(range(int(a), int(b) + 1))
        else:
            out.add(int(part))
    return out


def schadstoff_text(pdf, year):
    doc = common.fitz.open(pdf)
    text = re.sub(r'\s+', ' ', ' '.join(page.get_text() for page in doc))
    res = []
    for d, von, bis, ort in re.findall(r'(\d\d\.\d\d\.\d\d) von (\d{1,2}\.\d\d) bis (\d{1,2}\.\d\d) Uhr in (\w+)', text):
        day = datetime.datetime.strptime(d, '%d.%m.%y').date()
        if day.year == year:
            res.append((day, f'{von}–{bis} Uhr, {ORTE[ort]}', ort[0]))
    return res


def calendar(pdf, year):
    cells, notes = common.parse_grid(pdf, year)
    common.assert_grid_ok(notes, 'mainhausen')
    sampler = colorgrid.PixelSampler(common.fitz.open(pdf))
    per = collections.defaultdict(list)
    zm = set()
    for c in cells:
        yc = (c['y0'] + c['y1']) / 2
        has_wb = any(t == 'WB' for _, t in c['words'])
        for x, t in c['words']:
            col = sampler.color(c['page'], c['x0'] + x - 1.2, yc)
            kind = kind_of(col)
            if t in ('Z', 'M') and kind == 'rot':
                zm.add((c['date'], t))
            elif DISTRICT.match(t):
                if col == (1.0, 1.0, 1.0):
                    # Im Text vorhanden, im Bild aber verdeckt (2026: „1“ am 31.10. unter dem Infokasten) – nicht übernehmen
                    print(f'  [mainhausen] verdeckt, nicht übernommen: {c["date"]} „{t}“')
                    continue
                if kind in (None, 'rot'):
                    raise SystemExit(f'mainhausen: {c["date"]}: Farbe {col} für „{t}“ unbekannt')
                if kind == 'grün':
                    kind = 'Weihnachtsbäume' if has_wb else 'Grünschnitt'
                for d in districts(t):
                    per[d].append((c['date'], kind, None))
            elif t == 'WB' and kind == 'grün':
                pass
            elif kind is not None and not t.isupper() and not any(h.startswith(t.lower()) for h in HOLIDAYS):
                # weiß = Feiertagsname; Großbuchstaben = Werbetext am Rand; alles andere ist unklar
                raise SystemExit(f'mainhausen: {c["date"]}: unklar {t!r} {kind}')
    return per, zm


def streets(pdf):
    res = []
    text = subprocess.run(['pdftotext', '-layout', pdf, '-'], capture_output=True, text=True).stdout
    for line in text.splitlines():
        if 'Abfuhrbezirke' in line or 'Stand:' in line:
            continue
        res += [(m.group(1).strip(), int(m.group(2))) for m in re.finditer(r'(\S.*?)\s+([1-4])(?=\s{2,}|\s*$)', line)]
    return res


def run(refresh=False):
    year = max(PDF)
    pdf = common.fetch(PDF[year], f'mainhausen_{year}.pdf', refresh=refresh)
    bez = common.fetch(BEZ_PDF, 'mainhausen_bezirke.pdf', refresh=refresh)
    per, zm = calendar(pdf, year)
    schad = schadstoff_text(pdf, year)
    if {(d, o) for d, _, o in schad} != zm:
        raise SystemExit(f'mainhausen: Schadstoffmobil Text {sorted((d, o) for d, _, o in schad)} ≠ Raster {sorted(zm)}')
    everyone = [(d, 'Schadstoffmobil', note) for d, note, _ in schad]
    areas = []
    for name, b in streets(bez):
        areas.append((common.slug(name), name, None, per[b] + everyone))
    print(f'mainhausen: {len(areas)} Straßen, je Bezirk {collections.Counter(b for _, b in streets(bez))}')
    common.write_output('mainhausen', 'Gemeinde Mainhausen', PDF[year], [year], areas, step_title='Straße')
