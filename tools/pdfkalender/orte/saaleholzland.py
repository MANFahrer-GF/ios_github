"""Saale-Holzland-Kreis: 48-seitige Broschüre mit Regeln statt Terminen.
Jede Tonne hat einen Wochentag und „(g)“/„(u)“ = gerade/ungerade Kalenderwoche (ISO), Leerung 14-täglich.
Quellen in der PDF (Seitenzahlen 2026):
- S. 23 Feiertagstabelle: Fußnote (2) = Leerung 6 Tage vorher am Samstag (Ersatztermin),
  Fußnote (1) = Behälter am regulären Tag bereitstellen, Leerung „spätestens mit einem Tag Verzögerung“
  → Termin bleibt am Feiertag, Notiz „Leerung am Feiertag oder einen Tag später“.
- S. 24 Engstellentour, S. 25 oben Sonderstraßen Tautenhain/Weißenborn: eigene Regeln je Straße.
- S. 26–27 Städte Eisenberg, Hermsdorf, Kahla, Stadtroda: Restmüll-Regel und Schadstoffmobil-Standplätze.
- S. 28–35 Tourenpläne der Städte: Blaue/Gelbe Tonne je Straße.
- S. 36–47 Orte des Landkreises: Restmüll/Blaue/Gelbe Tonne + Schadstoffmobil (2 Termine, Uhrzeit, Standplatz).
  Rot gedruckte Korrekturen (z. B. Gösen „Fr“ → „Mi“) haben Vorrang vor dem durchgestrichenen Wert.
Nicht übernommen: Gewerbegebiete (S. 23) und Großwohnanlagen mit 1.100-l-Containern (S. 25).
Feiertagsverschiebungen stehen als Notiz am jeweiligen Termin."""
import collections
import datetime
import re

import common

PAGE = 'https://www.saaleholzlandkreis.de/de/abfallkalender.html'
PDF = {2026: 'https://www.saaleholzlandkreis.de/datei/anzeigen/id/6210/2026_abfallkalender_shk.pdf'}
WD = {'Mo': 0, 'Di': 1, 'Mi': 2, 'Do': 3, 'Fr': 4, 'Sa': 5, 'So': 6}
WD_LONG = {'Montag': 0, 'Dienstag': 1, 'Mittwoch': 2, 'Donnerstag': 3, 'Freitag': 4}
KINDS = ['Restmüll', 'Blaue Tonne', 'Gelbe Tonne']
NOTE_1 = 'Leerung am Feiertag oder einen Tag später'
NOTE_2 = 'vorgezogen wegen Feiertag'
CITIES = ['Eisenberg', 'Hermsdorf', 'Kahla', 'Stadtroda']


# ---------------------------------------------------------------- Wörter mit Farbe, gedrehte Seiten

def words_colored(page):
    """Wörter (x0, y0, x1, y1, text, rot?) – Seiten mit quer gesetzter Tabelle werden ins Querformat gedreht."""
    spans, up = [], 0
    for b in page.get_text('dict')['blocks']:
        for line in b.get('lines', []):
            up += 1 if round(line['dir'][1]) == -1 else -1
            for s in line['spans']:
                spans.append((common.fitz.Rect(s['bbox']), s['color']))
    raw = page.get_text('words')
    rotated = up > 0  # überwiegend von unten nach oben laufender Text
    h = page.rect.height
    out = []
    for w in raw:
        cx, cy = (w[0] + w[2]) / 2, (w[1] + w[3]) / 2
        col = next((c for r, c in spans if r.x0 - 0.5 <= cx <= r.x1 + 0.5 and r.y0 - 0.5 <= cy <= r.y1 + 0.5), 0)
        red = ((col >> 16) & 255) > 180 and ((col >> 8) & 255) < 90 and (col & 255) < 90
        if rotated:  # Text läuft von unten nach oben
            out.append((h - w[3], w[0], h - w[1], w[2], w[4], red))
        else:
            out.append((w[0], w[1], w[2], w[3], w[4], red))
    return out


def dehyph(text):
    """Zeilenumbruch-Trennungen auflösen: „Kaiser- quelle“ → „Kaiserquelle“, „Ossietzky- Straße“ → „Ossietzky-Straße“."""
    text = re.sub(r'\s+', ' ', text)
    text = re.sub(r'(\w)- ([a-zäöüß])', r'\1\2', text)
    return re.sub(r'(\w)- ([A-ZÄÖÜ0-9])', r'\1-\2', text).strip()


def rule_from(tokens):
    """[(text, rot?)] einer Tabellenzelle → (Wochentag, 'g'|'u') oder None. Rote Korrektur gewinnt."""
    days = [(t, red) for t, red in tokens if t in WD]
    pars = [(t, red) for t, red in tokens if t in ('(g)', '(u)')]
    red_days = [t for t, r in days if r]
    red_pars = [t for t, r in pars if r]
    day = red_days or [t for t, r in days if not r]
    par = red_pars or [t for t, r in pars if not r]
    if len(day) != 1 or len(par) != 1:
        return None
    return (WD[day[0]], par[0][1])


def rows_by_anchor(words, value_cols, top):
    """Zeilen über die „(g)/(u)“-Marken bilden; alle übrigen Wörter zur nächstgelegenen Zeile."""
    anchors = sorted({round((w[1] + w[3]) / 2, 1) for w in words if w[4] in ('(g)', '(u)') and w[1] > top
                      and any(a <= w[0] < b for a, b in value_cols)})
    rows = []
    for a in anchors:
        if rows and a - rows[-1] < 4:
            continue
        rows.append(a)
    groups = collections.defaultdict(list)
    for w in words:
        if w[1] <= top:
            continue
        yc = (w[1] + w[3]) / 2
        best = min(rows, key=lambda r: abs(r - yc)) if rows else None
        if best is not None and abs(best - yc) < 16:
            groups[best].append(w)
    return [sorted(groups[r], key=lambda w: (round((w[1] + w[3]) / 2 / 3), w[0])) for r in rows]


# ---------------------------------------------------------------- Abschnitte der Broschüre

def holidays(doc):
    text = doc[22].get_text()
    res = {}
    for d, name, fn, ers in re.findall(r'(\d\d\.\d\d\.\d{4})\s+(.+?)\s*\((\d)\)\s+(\d\d\.\d\d\.\d{4})', text):
        res[datetime.datetime.strptime(d, '%d.%m.%Y').date()] = (int(fn), datetime.datetime.strptime(ers, '%d.%m.%Y').date(), name)
    if len(res) != 7:
        raise SystemExit(f'saaleholzland: Feiertagstabelle hat {len(res)} statt 7 Einträge: {res}')
    return res


def landkreis_table(doc):
    """S. 37–47: Ort | Rest | Blau | Gelb | Tag | Uhrzeit | Tag | Uhrzeit | Standplatz."""
    out = []
    for pno in range(35, 47):  # S. 36–47
        ws = words_colored(doc[pno])
        foot = min([w[1] for w in ws if w[4] in ('Abfallkalender', 'Herausgeber:')] + [9999])
        ws = [w for w in ws if w[1] < foot - 1]
        x = {}
        for key, txt in (('rest', 'REST-'), ('blau', 'BLAUE'), ('gelb', 'GELBE'), ('stand', 'Standplatz')):
            x[key] = min(w[0] for w in ws if w[4] == txt)
        tags = sorted(w[0] for w in ws if w[4] == 'Tag')
        top = max(w[3] for w in ws if w[4] in ('TONNE', 'zirke', 'Uhrzeit'))
        bounds = [('name', -1, x['rest'] - 3), ('rest', x['rest'] - 3, x['blau'] - 3), ('blau', x['blau'] - 3, x['gelb'] - 3),
                  ('gelb', x['gelb'] - 3, tags[0] - 15), ('sch', tags[0] - 15, x['stand'] - 4), ('stand', x['stand'] - 4, 9999)]
        vcols = [(a, b) for k, a, b in bounds if k in ('rest', 'blau', 'gelb')]
        for row in rows_by_anchor([w for w in ws if w[1] < 9999], vcols, top):
            cell = collections.defaultdict(list)
            for w in row:
                k = next(k for k, a, b in bounds if a <= (w[0] + w[2]) / 2 < b)  # Mitte: rote Korrekturen stehen leicht links
                cell[k].append((w[4], w[5]))
                if k == 'sch':
                    cell['sch_x'].append((w[0], w[4]))
            name = dehyph(' '.join(t for t, _ in cell['name'])).replace(' /', '/')
            if not name or name.startswith('Abfallkalender'):
                continue
            rules = [rule_from(cell[k]) for k in ('rest', 'blau', 'gelb')]
            joined = ' '.join(t for _, t in sorted(cell['sch_x']))  # einzeilig: nach x ordnen
            sch = re.findall(r'(\d\d\.\d\d\.\d\d)\s+(\d\d[:.]\d\d\s*-\s*\d\d[:.]\d\d)', joined)  # 2026: Tissa „13.25“
            if re.sub(r'(\d\d\.\d\d\.\d\d)\s+(\d\d[:.]\d\d\s*-\s*\d\d[:.]\d\d)', '', joined).strip():
                raise SystemExit(f'saaleholzland: {name}: Schadstofftermine unklar {joined!r}')
            stand = dehyph(' '.join(x for x, _ in cell['stand']))
            out.append(dict(name=name, rules=rules, schadstoff=sch, stand=stand, page=pno + 1))
    return out


def street_lines(doc, pno, stop=None):
    """Zeilenweise Tabellen (S. 24, 25 oben): Ortsüberschrift ohne Werte, darunter Straßen mit 3 Regeln."""
    ws = words_colored(doc[pno])
    bottom = min([w[1] for w in ws if stop and w[4] == stop] + [9999])
    ws = [w for w in ws if w[1] < bottom]
    x_rest = min(w[0] for w in ws if w[4] == 'REST-')
    x_blau = min(w[0] for w in ws if w[4] == 'BLAUE')
    x_gelb = min(w[0] for w in ws if w[4] == 'GELBE')
    top = min(w[3] for w in ws if w[4] == 'MÜLL')
    lines = []
    for w in sorted((w for w in ws if top < w[1] < bottom), key=lambda w: (w[1] + w[3]) / 2):
        yc = (w[1] + w[3]) / 2
        if lines and yc - lines[-1][0] < 3:
            lines[-1][1].append(w)
        else:
            lines.append([yc, [w]])
    res, ort = [], None
    for _, lw in lines:
        lw.sort(key=lambda w: w[0])
        name = ' '.join(w[4] for w in lw if w[0] < x_rest - 3)
        cols = [[(w[4], w[5]) for w in lw if a <= w[0] < b] for a, b in
                ((x_rest - 3, x_blau - 3), (x_blau - 3, x_gelb - 3), (x_gelb - 3, 9999))]
        rules = [rule_from(c) for c in cols]
        if all(r is None for r in rules):
            if name and not name.startswith(('Abfallkalender', '(u)', '-')):
                ort = name
            continue
        if None in rules or not ort:
            raise SystemExit(f'saaleholzland: S. {pno + 1}: unklare Zeile {name!r} {cols}')
        res.append((ort, name, rules))
    return res


def city_sections(doc):
    """S. 26–27: je Stadt Restmüll-Regel und Schadstoffmobil-Standplätze."""
    out = {}
    for pno in (25, 26):
        ws = words_colored(doc[pno])
        text = doc[pno].get_text()
        heads = sorted((w[1], ' '.join(v[4] for v in ws if abs(v[1] - w[1]) < 2 and v[0] > w[0])) for w in ws
                       if w[4] == 'Entsorgungstermine')
        rules = re.findall(r'Termin Restmüll:\s*(\w+)\s*-\s*(gerade|ungerade) Kalenderwoche', text)
        if len(rules) != len(heads):
            raise SystemExit('saaleholzland: Städte-Abschnitt unklar')
        for i, (y, head) in enumerate(heads):
            city = head.split()[0]
            y_end = heads[i + 1][0] if i + 1 < len(heads) else 9999
            sec = [w for w in ws if y < w[1] < y_end - 2]
            stand_x = min(w[0] for w in sec if w[4] == 'Standplatz')
            top = max(w[3] for w in sec if w[4] in ('Uhrzeit', 'Standplatz'))
            dates = [w for w in sec if re.fullmatch(r'\d\d\.\d\d\.\d\d', w[4]) and w[1] > top]
            anchors = sorted({round((w[1] + w[3]) / 2) for w in dates})
            rows = collections.defaultdict(list)
            for w in sec:
                if w[1] <= top:
                    continue
                yc = (w[1] + w[3]) / 2
                a = min(anchors, key=lambda r: abs(r - yc))
                if abs(a - yc) < 14:
                    rows[a].append(w)
            sch = []
            for a in anchors:
                rw = sorted(rows[a], key=lambda w: (round((w[1] + w[3]) / 2 / 3), w[0]))
                left = ' '.join(w[4] for w in rw if w[0] < stand_x - 4)
                stand = dehyph(' '.join(w[4] for w in rw if w[0] >= stand_x - 4))
                # Randvermerk „neuer Standplatz in 2026“ gehört nicht zum Namen des Standplatzes
                stand = re.sub(r'^(neuer\s+)?(Stand-?\s*)?platz in \d{4}\s*', '', stand)
                m = re.fullmatch(r'(\S+) (\d\d:\d\d - \d\d:\d\d) (\S+) (\d\d:\d\d - \d\d:\d\d)', left)
                if not m:
                    raise SystemExit(f'saaleholzland: {city}: Schadstoffzeile unklar {left!r}')
                sch.append(((m.group(1), m.group(2)), (m.group(3), m.group(4)), stand))
            wd, par = rules[i]
            out[city] = dict(rest=(WD_LONG[wd], 'g' if par == 'gerade' else 'u'), schadstoff=sch)
    if sorted(out) != sorted(CITIES):
        raise SystemExit(f'saaleholzland: Städte {sorted(out)}')
    return out


def tourenplan(doc):
    """S. 28–35: Tabellen „Straße | Blaue Tonne | Gelbe Tonne“ (zwei nebeneinander, teils untereinander).
    „Tourenplan <Stadt>“ gilt für alle folgenden Tabellen (Lesereihenfolge: Seite, links/rechts, oben/unten)."""
    items = []  # (sortierschlüssel, art, daten)
    for pno in range(27, 35):
        ws = words_colored(doc[pno])
        width = doc[pno].rect.width
        foot = min([w[1] for w in ws if w[4] == 'Abfallkalender'] + [9999])
        heads = [w for w in ws if w[4] == 'Blaue']
        for w in ws:
            if w[4] == 'Tourenplan':
                city = ' '.join(v[4] for v in ws if abs(v[1] - w[1]) < 2 and v[0] > w[0]).split()[0]
                items.append(((pno, w[0] > width / 2, w[1]), 'city', city))
        sxs = {h: max(w[0] for w in ws if w[4] == 'Straße' and abs(w[1] - h[1]) < 12 and w[0] < h[0]) for h in heads}
        for h in heads:
            same = [w for w in ws if abs(w[1] - h[1]) < 3]
            sx = sxs[h]
            gx = min(w[0] for w in same if w[4] == 'Gelbe' and w[0] > h[0])
            below = [o[1] for o in heads if o[1] > h[1] + 5 and abs(o[0] - h[0]) < 30]
            y_end = min(below + [foot])
            right = min([x - 4 for x in sxs.values() if x > gx] + [width])
            top = max(w[3] for w in ws if w[4] == 'Tonne' and abs(w[1] - h[1]) < 20 and sx - 4 <= w[0] < right)
            tw = [w for w in ws if sx - 4 <= w[0] < right and top < w[1] < y_end - 1]
            rows = []
            for row in rows_by_anchor(tw, [(h[0] - 3, gx - 3), (gx - 3, right)], top):
                name = ' '.join(w[4] for w in row if w[0] < h[0] - 3)
                name = dehyph(name)
                rb = rule_from([(w[4], w[5]) for w in row if h[0] - 3 <= w[0] < gx - 3])
                rg = rule_from([(w[4], w[5]) for w in row if gx - 3 <= w[0]])
                if not name or not rb or not rg:
                    raise SystemExit(f'saaleholzland: Tourenplan S. {pno + 1}: unklar {name!r} {rb} {rg}')
                rows.append((name, rb, rg))
            items.append(((pno, sx > width / 2, h[1]), 'table', rows))
    res, city = [], None
    for _, kind, data in sorted(items, key=lambda i: i[0]):
        if kind == 'city':
            city = data
        else:
            if city not in CITIES:
                raise SystemExit(f'saaleholzland: Tourenplan ohne Stadt ({city})')
            res += [(city,) + r for r in data]
    return res


# ---------------------------------------------------------------- Termine

def dates_for(rule, kind, year, hol):
    wd, par = rule
    d = datetime.date(year, 1, 1)
    out = []
    while d.year == year:
        if d.weekday() == wd and (d.isocalendar()[1] % 2 == 0) == (par == 'g'):
            if d in hol and hol[d][0] == 2:
                out.append((hol[d][1], kind, f'{NOTE_2} ({hol[d][2]})'))
            elif d in hol:
                out.append((d, kind, NOTE_1))
            else:
                out.append((d, kind, None))
        d += datetime.timedelta(days=1)
    return out


def schadstoff_events(entries):
    out = []
    for (d1, t1), (d2, t2), stand in entries:
        for d, t in ((d1, t1), (d2, t2)):
            if d:
                day = datetime.datetime.strptime(d, '%d.%m.%y').date()
                note = re.sub(r'(\d\d)\.(\d\d)', r'\1:\2', t).replace(' - ', '–') + ' Uhr' + (f', {stand}' if stand else '')
                out.append((day, 'Schadstoffmobil', note))
    return out


def norm(name):
    return re.sub(r'[\s.]', '', name).lower()


def run(refresh=False):
    year = max(PDF)
    doc = common.fitz.open(common.fetch(PDF[year], f'saaleholzland_{year}.pdf', refresh=refresh))
    hol = holidays(doc)
    orte = landkreis_table(doc)
    special = [s + ('Engstellentour',) for s in street_lines(doc, 23)] + \
        [s + ('eigene Abfuhrtage',) for s in street_lines(doc, 24, stop='Großwohnanlagen')]
    cities = city_sections(doc)
    tour = tourenplan(doc)

    def events(rules):
        ev = []
        for rule, kind in zip(rules, KINDS):
            if rule:
                ev += dates_for(rule, kind, year, hol)
        return ev

    areas = []
    by_ort = {norm(o['name']): o for o in orte}
    special_by = collections.defaultdict(list)
    for ort, street, rules, label in special:
        special_by[norm(ort)].append((ort, street, rules, label))
    # Orte des Landkreises (ein Ort kann mehrere Zeilen haben, je Schadstoff-Standplatz eine – z. B. Orlamünde)
    merged = {}
    for o in orte:
        if any(r is None for r in o['rules']):
            raise SystemExit(f'saaleholzland: {o["name"]} (S. {o["page"]}): Regel fehlt {o["rules"]}')
        pairs = list(o['schadstoff']) + [('', '')] * (2 - len(o['schadstoff']))
        entry = [(pairs[0], pairs[1], o['stand'])] if o['schadstoff'] else []
        key = norm(o['name'])
        if key in merged:
            if merged[key]['rules'] != o['rules']:
                raise SystemExit(f'saaleholzland: {o["name"]} doppelt mit verschiedenen Regeln')
            merged[key]['sch'] += entry
        else:
            merged[key] = dict(name=o['name'], rules=o['rules'], sch=entry)
    for key, o in merged.items():
        sch = schadstoff_events(o['sch'])
        extra = special_by.pop(key, [])
        gid = common.slug(o['name'])
        areas.append((gid, 'alle übrigen Straßen' if extra else 'alle Straßen', o['name'], events(o['rules']) + sch))
        for _, street, rules, label in extra:
            areas.append((f'{gid}__{common.slug(street)}', f'{street} ({label})', o['name'], events(rules) + sch))
    # Städte mit Tourenplan
    for city in CITIES:
        c = cities[city]
        sch = schadstoff_events(c['schadstoff'])
        gid = common.slug(city)
        for cc, street, rb, rg in tour:
            if cc == city:
                areas.append((f'{gid}__{common.slug(street)}', street, city, events([c['rest'], rb, rg]) + sch))
        for _, street, rules, label in special_by.pop(norm(city), []):
            areas.append((f'{gid}__eng_{common.slug(street)}', f'{street} ({label})', city, events(rules) + sch))
    # Übrig: Orte nur mit Sonderstraßen (Bad Klosterlausnitz, ggf. abweichende Schreibweise)
    for key, items in special_by.items():
        for ort, street, rules, label in items:
            gid = common.slug(ort)
            areas.append((f'{gid}__eng_{common.slug(street)}', f'{street} ({label})', ort, events(rules)))
        print(f'  [saaleholzland] nur Sonderstraßen: {items[0][0]} ({len(items)})')
    print(f'saaleholzland: {len(merged)} Orte ({len(orte)} Zeilen), {len(tour)} Stadtstraßen, {len(special)} Sonderstraßen')
    common.write_output('saaleholzland', 'Saale-Holzland-Kreis', PDF[year], [year], areas,
                        step_title='Straße', group_title='Ort')
