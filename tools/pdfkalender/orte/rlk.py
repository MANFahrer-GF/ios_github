"""Rhein-Lahn-Kreis (Abfallwirtschaft): je Verbandsgemeinde eine PDF mit Texttabellen.
Je Abfallart (Restabfall, Bio, Altpapier, Gelbe Tonne) stehen Ortsspalten über einer Wochentagsspalte mit den
Terminen darunter; rot markierte Termine sind Verschiebungen wegen Feiertagen. Aus den Spalten wird je Gemeinde ein
Terminplan aus allen Abfallarten gebaut; Gemeinden mit gleichem Plan teilen einen Schlüssel (`rlk_<vg>_<erster Ort>`).
Orte mit Abfuhrbezirken (Diez 1–3, Bad Ems 1–3, Lahnstein 1–4, Friedrichssegen) bekommen einen Schlüssel für die
ganze Stadt mit Auswahl des Bezirks (laut Straßenverzeichnis in der PDF)."""
import datetime
import re

import common

BASE = ('https://www.rhein-lahn-kreis.de/rhein-lahn-kreis/abfallwirtschaft/abfuhrtermine-formulare-und-merkblaetter/')
PAGE = 'https://www.rhein-lahn-kreis.de/rhein-lahn-kreis/abfallwirtschaft/abfuhrtermine-formulare-und-merkblaetter/'
# vg-slug: (Titel, Datei, Stadt mit Bezirken oder None)
VGS = {
    'aar_einrich': ('VG Aar-Einrich', 'vg-aar-einrich-abfuhrtermine-2026.pdf?cid=top'),
    'bad_ems_nassau': ('VG Bad Ems-Nassau', 'vg-bad-ems-nassau-abfuhrtermine-2026-und-strassenverzeichnis.pdf?cid=tos'),
    'diez': ('VG Diez', 'vg-diez-abfuhrtermine-2026-und-strassenverzeichnis.pdf?cid=tog'),
    'loreley': ('VG Loreley', 'vg-loreley-abfuhrtermine-2026.pdf?cid=toj'),
    'nastaetten': ('VG Nastätten', 'vg-nastaetten-abfuhrtermine-2026.pdf?cid=tom'),
    'lahnstein': ('Stadt Lahnstein', 'lahnstein-abfuhrtermine-2026-und-strassenverzeichnis.pdf?cid=tod'),
}
YEAR = 2026
WEEKDAYS = ['montag', 'dienstag', 'mittwoch', 'donnerstag', 'freitag', 'samstag', 'sonntag']
KINDS = [('restabfall', 'Restmüll'), ('bioabfall', 'Biomüll'), ('biotonne', 'Biomüll'), ('altpapier', 'Altpapier'),
         ('gelbe tonne', 'Gelbe Tonne')]
FIX = {'Balduinsten': 'Balduinstein', 'St.Goarshausen': 'Sankt Goarshausen', 'St. Goarshausen': 'Sankt Goarshausen',
       'Friedrichsegen': 'Friedrichssegen', 'Holzhausen': 'Holzhausen an der Haide'}
BEZIRK = re.compile(r'^(Diez|Bad Ems|Lahnstein) \d$|^Friedrichssegen$')
DATE = re.compile(r'^(\d\d)\.(\d\d)\.$')


def _spans(page):
    out = []
    for b in page.get_text('dict')['blocks']:
        for line in b.get('lines', []):
            for s in line['spans']:
                t = s['text'].strip()
                if t:
                    x0, y0, x1, y1 = s['bbox']
                    out.append((x0, y0, x1, y1, t, s['color']))
    return out


def names_of(page, gap=7):
    """Ortsnamen: Wörter einer Zeile, die dichter als `gap` stehen, bilden einen Namen (mehrere Spalten pro Span)."""
    ws = sorted(page.get_text('words'), key=lambda w: (round(w[1]), w[0]))
    out = []
    for w in ws:
        if out and abs(out[-1][1] - w[1]) < 3 and w[0] - out[-1][2] < gap:
            o = out[-1]
            out[-1] = (o[0], o[1], w[2], max(o[3], w[3]), o[4] + ' ' + w[4], o[5])
        else:
            out.append((w[0], w[1], w[2], w[3], w[4], 0))
    return out


def _kind(t):
    for k, name in KINDS:
        if t.lower().startswith(k):
            return name
    return None


def parse(pdf, vg):
    """-> {Ort: {Art: [(datum, verschoben)]}}"""
    doc = common.fitz.open(pdf)
    res = {}
    for pno, page in enumerate(doc):
        sp = _spans(page)
        banners = [(dr['rect'], dr['fill']) for dr in page.get_drawings() if dr.get('fill') and dr['rect'].height < 20 and dr['rect'].width > 40]
        titles = []
        for s in sorted(sp, key=lambda s: (s[1], s[0])):
            if _kind(s[4]) and s[1] < 400:
                cx, cy = (s[0] + s[2]) / 2, (s[1] + s[3]) / 2
                bx = [r for r, f in banners if r.x0 <= cx <= r.x1 and r.y0 <= cy <= r.y1]
                # Spalten beginnen am linken Rand des Titelbalkens
                titles.append((min(r.x0 for r in bx) if bx else s[0], s[1], s[2], s[3], s[4], s[5]))
        titles.sort(key=lambda s: (s[1], s[0]))
        if not titles:
            continue
        rows = []
        for t in titles:
            if rows and abs(rows[-1][0][1] - t[1]) < 4:
                rows[-1].append(t)
            else:
                rows.append([t])
        for ri, row in enumerate(rows):
            y_top = row[0][1]
            y_bot = rows[ri + 1][0][1] if ri + 1 < len(rows) else 10000
            wds = sorted([s for s in sp if s[4].lower() in WEEKDAYS and y_top < s[1] < y_bot], key=lambda s: s[0])
            assert wds, f'{vg} S.{pno + 1}: keine Wochentage'
            wd_y = min(w[1] for w in wds)
            row = sorted(row, key=lambda s: s[0])
            for ti, t in enumerate(row):
                lo = t[0] - 3
                hi = row[ti + 1][0] - 3 if ti + 1 < len(row) else 10000
                places = [s for s in names_of(page) if lo <= s[0] < hi and t[3] < s[1] < wd_y - 1 and not DATE.match(s[4])
                          and s[4].lower() not in WEEKDAYS and not _kind(s[4])]
                cols = []
                for s in sorted(places, key=lambda s: s[0]):
                    if cols and abs(cols[-1][0] - s[0]) < 5:
                        cols[-1][1].append(s)
                    else:
                        cols.append([s[0], [s]])
                my_wds = [w for w in wds if lo - 12 <= (w[0] + w[2]) / 2 < hi - 12]
                assert len(cols) == len(my_wds), f'{vg} S.{pno + 1} {t[4]}: {len(cols)} Ortsspalten, {len(my_wds)} Wochentage'
                for (x, members), w in zip(cols, my_wds):
                    names = []
                    for s in sorted(members, key=lambda s: s[1]):
                        n = s[4].rstrip(',').strip()
                        names.append(FIX.get(n, n))
                    col_dates = []
                    for d in sorted(sp, key=lambda d: d[1]):
                        m = DATE.match(d[4])
                        if not m or not (wd_y < d[1] < y_bot) or not lo - 12 <= (d[0] + d[2]) / 2 < hi - 12:
                            continue
                        # nächste Wochentagsspalte dieser Tabelle
                        near = min(my_wds, key=lambda v: abs((v[0] + v[2]) / 2 - (d[0] + d[2]) / 2))
                        if near is w:
                            col_dates.append((datetime.date(YEAR, int(m.group(2)), int(m.group(1))), d[5] == 0xFF0000))
                    diffs = sorted((b[0] - a[0]).days for a, b in zip(col_dates, col_dates[1:]) if not (a[1] or b[1]))
                    step = diffs[len(diffs) // 2] if diffs else 14
                    fixed = []
                    for i, (day, red) in enumerate(col_dates):
                        if not red and WEEKDAYS[day.weekday()] != w[4].lower():
                            # Tippfehler im Original: über den Rhythmus der Spalte auflösen
                            cand = fixed[-1][0] + datetime.timedelta(days=step) if fixed else None
                            nxt = next((c[0] for c in col_dates[i + 1:] if not c[1]), None)
                            ok = cand is not None and WEEKDAYS[cand.weekday()] == w[4].lower() and (
                                nxt is None or (nxt - cand).days == step)
                            if ok:
                                print(f'  [{vg}] Tippfehler im PDF: {day} ({", ".join(names)}, {w[4]}) gelesen als {cand}')
                                day = cand
                            else:
                                diff = abs(day.weekday() - WEEKDAYS.index(w[4].lower()))
                                if diff != 1:
                                    raise SystemExit(f'{vg}: {day} ist kein {w[4]} ({", ".join(names)})')
                                print(f'  [{vg}] Wochentag weicht ab, Datum wie gedruckt: {day} ({", ".join(names)}, {w[4]})')
                        fixed.append((day, red))
                    for n in names:
                        res.setdefault(n, {}).setdefault(_kind(t[4]), []).extend(fixed)
    return res


def run(refresh=False):
    import glob
    import os
    for old in glob.glob(os.path.join(common.OUT, 'rlk_*.json')):
        os.remove(old)  # Schlüssel hängen an der Gruppenbildung: veraltete Dateien nicht stehen lassen
    for slug, (title, fname) in VGS.items():
        pdf = common.fetch(BASE + fname, f'rlk_{slug}_{YEAR}.pdf', refresh=refresh)
        res = parse(pdf, title)
        arts = {'Restmüll', 'Biomüll', 'Altpapier', 'Gelbe Tonne'}
        for ort, d in sorted(res.items()):
            if set(d) != arts:
                print(f'  [{slug}] {ort}: Abfallarten {sorted(set(d))}')
        def plan(ort):
            ev = []
            for art, lst in res[ort].items():
                for day, red in lst:
                    ev.append((day, art, 'verschoben wegen Feiertag' if red else None))
            return ev
        # Gemeinden gleicher Plans bündeln
        groups = {}
        city_areas = {}
        for ort in sorted(res):
            m = BEZIRK.match(ort)
            if m:
                city = m.group(1) if m.group(1) else 'Lahnstein'
                city_areas.setdefault(city, []).append(ort)
                continue
            sig = repr(sorted((str(d), a, n or '') for d, a, n in plan(ort)))
            groups.setdefault(sig, []).append(ort)
        for orte in groups.values():
            first = common.slug(orte[0])
            key = f'rlk_{slug}_{first}'
            shown = ', '.join(orte[:3]) + (' u. a.' if len(orte) > 3 else '')
            common.write_output(key, f'{title} ({shown})', PAGE, [YEAR], [(first, ', '.join(orte), None, plan(orte[0]))],
                                step_title='Ort')
        for city, bez in city_areas.items():
            first = common.slug(city)
            key = f'rlk_{slug}_{first}'
            areas = [(common.slug(b), b, None, plan(b)) for b in bez]
            common.write_output(key, f'{title} ({city})', PAGE, [YEAR], areas, step_title='Abfuhrbezirk',
                                notice='Der Abfuhrbezirk steht im alphabetischen Straßenverzeichnis des Abfuhrkalenders.')
