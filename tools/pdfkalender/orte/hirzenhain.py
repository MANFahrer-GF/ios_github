"""Gemeinde Hirzenhain (Wetteraukreis): Jahresraster, Abfallart steht als Text auf farbiger Fläche.
Die PDF enthält unsichtbaren Text (weiß auf weiß: „Gelbe Tonne Tour 1“, „HM Tour 2“ …), den die Gemeinde nicht
anzeigt. Gezählt wird deshalb nur Text, hinter dem eine Fläche der Palette liegt.
Tour 1 = Glashütten und Merkenfritz, Tour 2 = Hirzenhain (nur Leichtverpackungen/Gelbe Tonne je Tour).
Feiertage (rot) und „GA“ (Schadstoffsammlung, nur Ortsteil Hirzenhain) werden nicht als Abfuhr gezählt,
GA kommt als eigener Termin für Tour 2."""
import datetime
import re

import common

PAGE = 'https://www.hirzenhain.de/seite/207414/abfall.html'
PDF = {2026: 'https://daten2.verwaltungsportal.de/dateien/seitengenerator/afd40d00c1a2eb22c5bdd03cfdd13940138863/Abfallkalender_2026.pdf'}
MONTHS = ['januar', 'februar', 'märz', 'april', 'mai', 'juni', 'juli', 'august', 'september', 'oktober', 'november', 'dezember']
KINDS = {'RM': 'Restmüll', 'BIO': 'Biomüll', 'PPK': 'Altpapier', 'GRÜN': 'Grünschnitt', 'GA': 'Schadstoffmobil'}
TOUR_NOTE = {1: 'Tour 1 (Glashütten, Merkenfritz)', 2: 'Tour 2 (Hirzenhain)'}
WD = ['mo', 'di', 'mi', 'do', 'fr', 'sa', 'so']
HOLIDAYS = ('neujahr', 'karfreitag', 'ostermontag', 'ostern', 'tag der arbeit', 'tag d. dt. einheit', 'christi himmelfahrt',
            'pfingstmontag', 'fronleichnam', 'heiligabend', '1. weihnachtstag', '2. weihnachtstag', 'pfingstsonntag',
            'ostersonntag', 'silvester', 'reformationstag', 'allerheiligen')


def _near(f, ref, tol=0.04):
    return all(abs(a - b) <= tol for a, b in zip(f, ref))


def events(pdf, year):
    doc = common.fitz.open(pdf)
    out, seen_days, unknown = [], set(), []
    for page in doc:
        words = common.page_words(page)
        fills = [(r, f) for r, f in common.page_fills(page) if r.width > 8 and r.height > 8]
        nums = [w for w in words if re.fullmatch(r'\d{1,2}', w[4])]
        hy = [w[1] for w in words if w[4].lower() in MONTHS]
        top = min(hy)  # Kopfzeile; eine verirrte Überschrift (Seite 2: „DEZEMBER“ rechts oben) liegt höher
        heads = sorted([w for w in words if w[4].lower() in MONTHS and abs(w[1] - max(hy, key=hy.count)) < 3], key=lambda w: w[0])
        assert len(heads) == 6, [h[4] for h in heads]
        mid = [(heads[i][0] + heads[i][2]) / 2 for i in range(6)]
        bounds = [0] + [(mid[i] + mid[i + 1]) / 2 for i in range(5)] + [10000]
        for i, h in enumerate(heads):
            month = MONTHS.index(h[4].lower()) + 1
            x0, x1 = bounds[i], bounds[i + 1]
            cut = x0 + (x1 - x0) * 0.35  # Tageszahl steht am linken Rand der Spalte
            for w in nums:
                yc = (w[1] + w[3]) / 2
                if not x0 <= w[0] < cut or yc < h[3]:
                    continue
                wd = [v for v in words if abs((v[1] + v[3]) / 2 - yc) < 3 and 0 < v[0] - w[2] < 8 and v[4].lower() in WD]
                if not wd:
                    continue
                try:
                    day = datetime.date(year, month, int(w[4]))
                except ValueError:
                    raise SystemExit(f'hirzenhain: ungültiges Datum {w[4]}.{month}.')
                label = wd[0][4].lower()
                if WD[day.weekday()] != label:
                    print(f'  [hirzenhain] Wochentag falsch im PDF: {day} ist mit „{wd[0][4]}“ beschriftet')
                seen_days.add(day)
                row = [v for v in words if abs((v[1] + v[3]) / 2 - yc) < 3 and wd[0][2] < v[0] < x1 and v[0] >= x0 and v is not wd[0]
                      ]
                # nur sichtbarer Text: Fläche der Palette dahinter
                items = []
                for v in sorted(row, key=lambda v: v[0]):
                    cx, cy = (v[0] + v[2]) / 2, (v[1] + v[3]) / 2
                    under = [f for r, f in fills if r.x0 <= cx <= r.x1 and r.y0 <= cy <= r.y1]
                    items.append((v, under))
                out += _row(day, items, unknown)
    if unknown:
        raise SystemExit(f'hirzenhain: nicht zugeordnet {sorted(set(unknown))}')
    if len(seen_days) != (datetime.date(year, 12, 31) - datetime.date(year, 1, 1)).days + 1:
        raise SystemExit(f'hirzenhain: {len(seen_days)} Tage statt Jahr, fehlt: {sorted(d.isoformat() for d in (datetime.date(year,1,1)+datetime.timedelta(n) for n in range(365)) if d not in seen_days)[:12]}')
    return out


def _row(day, items, unknown):
    # zusammenhängende Wörter derselben Fläche zu einem Text verbinden
    groups = []
    for v, under in items:
        pal = next((f for f in reversed(under) if not _near(f, (1, 1, 1)) and not _near(f, (1, .8, .6), .05)
                    and not _near(f, (1, 1, .8)) and not _near(f, (.98, .75, .56), .05) and not _near(f, (.99, .91, .85), .05)), None)
        if pal is None:
            continue  # unsichtbar (weiß auf weiß oder auf Wochenendfläche)
        if groups and groups[-1][1] == pal and v[0] - groups[-1][2] < 6:
            groups[-1][0] += ' ' + v[4]
            groups[-1][2] = v[2]
        else:
            groups.append([v[4], pal, v[2]])
    res = []
    for text, pal, _ in groups:
        t = text.strip()
        m = re.fullmatch(r'LVP ([12])', t)
        if m:
            res.append((day, 'Gelbe Tonne', TOUR_NOTE[int(m.group(1))], int(m.group(1))))
        elif t in KINDS:
            res.append((day, KINDS[t], None, 0))
        elif t.lower() in HOLIDAYS or _near(pal, (1, 0, 0), .05):
            pass
        else:
            unknown.append((str(day), t))
    return res


def run(refresh=False):
    evs = []
    for year, url in PDF.items():
        pdf = common.fetch(url, f'hirzenhain_{year}.pdf', refresh=refresh)
        evs += events(pdf, year)
    t1 = [(d, a) for d, a, n, tour in evs if tour in (0, 1) and a != 'Schadstoffmobil']  # Schadstoffmobil nur Ortsteil Hirzenhain
    t2 = [(d, a) for d, a, n, tour in evs if tour in (0, 2)]
    common.write_output('hirzenhain', 'Gemeinde Hirzenhain', PAGE, sorted(PDF),
                        [('glashuetten_merkenfritz', 'Glashütten und Merkenfritz', None, t1),
                         ('hirzenhain', 'Hirzenhain', None, t2)], step_title='Ortsteil')
