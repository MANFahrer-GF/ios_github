"""Gemeinsame Helfer: Abruf mit Cache, PyMuPDF-Import, Raster-Parser, Ausgabe im Format von FORMAT.md.

Aufruf immer mit dem System-Python ohne Umgebung: `/usr/bin/python3 -I tools/pdfkalender/extract.py <key>`.
`-I` schaltet das User-Site-Verzeichnis ab; PyMuPDF wird deshalb hier ausdrücklich von dort geladen.
"""
import datetime
import json
import os
import re
import site
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'cache')
OUT = os.path.join(HERE, 'out')

_user_site = site.getusersitepackages()
if _user_site not in sys.path:
    sys.path.append(_user_site)
try:
    import fitz  # PyMuPDF
except ImportError:  # pragma: no cover
    sys.exit('PyMuPDF fehlt: /usr/bin/python3 -m pip install --user "pymupdf==1.26.5" (siehe README.md)')

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15'
_last = {}


def fetch(url, name=None, encoding='utf-8', refresh=False):
    """Lädt `url` (höchstens 1 Anfrage/s je Host) in den Cache und gibt den Pfad zurück.
    `encoding` bestimmt die Kodierung von Umlauten in Pfad und Query (p-42.net erwartet Latin-1)."""
    os.makedirs(CACHE, exist_ok=True)
    p = urllib.parse.urlsplit(url)
    path = urllib.parse.quote(p.path.encode(encoding), safe='/%:@,')
    query = urllib.parse.quote(p.query.encode(encoding), safe='=&%+')
    url = urllib.parse.urlunsplit((p.scheme, p.netloc, path, query, ''))
    name = name or re.sub(r'[^A-Za-z0-9._-]+', '_', p.netloc + p.path + ('_' + p.query if p.query else ''))[-150:]
    target = os.path.join(CACHE, name)
    if os.path.exists(target) and not refresh:
        return target
    wait = 1.05 - (time.time() - _last.get(p.netloc, 0))
    if wait > 0:
        time.sleep(wait)
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'de'})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            break
        except (urllib.error.URLError, ConnectionError) as e:
            if isinstance(e, urllib.error.HTTPError) or attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))  # Verbindung zurückgesetzt: kurz warten, erneut versuchen
    _last[p.netloc] = time.time()
    with open(target, 'wb') as f:
        f.write(data)
    return target


def slug(text):
    t = text.lower().replace('ß', 'ss').replace('ä', 'ae').replace('ö', 'oe').replace('ü', 'ue')
    t = unicodedata.normalize('NFKD', t).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '_', t).strip('_')


# ---------------------------------------------------------------- Raster-Parser

MONTH_WD = {'mo': 0, 'di': 1, 'mi': 2, 'do': 3, 'fr': 4, 'sa': 5, 'so': 6}


def _norm(t):
    return t.strip().lower().strip('.:,')


def page_words(page):
    """Wörter (x0, y0, x1, y1, text) im angezeigten (gedrehten) Seitenraum."""
    m = page.rotation_matrix
    out = []
    for w in page.get_text('words'):
        r = fitz.Rect(w[:4]) * m
        out.append((r.x0, r.y0, r.x1, r.y1, w[4]))
    return out


def page_fills(page, max_height=25):
    """Gefüllte Vektorflächen (Rect, (r, g, b)) im angezeigten Seitenraum."""
    m = page.rotation_matrix
    out = []
    for dr in page.get_drawings():
        if dr.get('fill') is None:
            continue
        r = dr['rect'] * m
        if r.height < max_height:
            out.append((r, tuple(dr['fill'])))
    return out


def parse_grid(path, year, pages=None):
    """Jahres-Rasterkalender: Zelle = Tageszahl + Wochentag, danach der Inhalt.
    Monate werden über Spalten/Bänder gefunden und über die Wochentage bestätigt (Wochentag-Probe).
    Gibt (zellen, meldungen) zurück; jede Zelle: date, page, x0, y0, y1, right, words=[(x relativ, text)].
    Meldungen: 'Tippfehler im PDF' / 'Wochentag falsch im PDF' (aufgelöst) oder 'unlesbar' (Fehler)."""
    doc = fitz.open(path)
    groups, notes = [], []
    meta = {}
    for pno in (pages or range(len(doc))):
        page = doc[pno]
        words = page_words(page)
        cells = []
        for w in words:
            if not re.fullmatch(r'\d{1,2}', w[4]) or not 1 <= int(w[4]) <= 31:
                continue
            yc = (w[1] + w[3]) / 2
            right_of = sorted([v for v in words if abs((v[1] + v[3]) / 2 - yc) < 3 and v[0] >= w[2] - 0.5 and v is not w],
                              key=lambda v: v[0])
            if right_of and right_of[0][0] - w[2] < 14 and _norm(right_of[0][4]) in MONTH_WD:
                cells.append((w, right_of[0]))
        meta[pno] = (words, page.rect.width, cells)
        cells.sort(key=lambda c: c[0][0])
        cols = []
        for c in cells:
            if cols and c[0][0] - cols[-1][-1][0][0] < 25:
                cols[-1].append(c)
            else:
                cols.append([c])
        for col in cols:
            col.sort(key=lambda c: c[0][1])
            band = [col[0]]
            for c in col[1:]:
                if int(c[0][4]) < int(band[-1][0][4]) - 20:
                    groups.append((pno, band))
                    band = [c]
                else:
                    band.append(c)
            groups.append((pno, band))
    groups.sort(key=lambda g: (g[0], round(g[1][0][0][1] / 60), g[1][0][0][0]))
    out, month = [], 1
    for pno, band in groups:
        words, page_w, cells = meta[pno]

        def score(m):
            ok = 0
            for w, wd in band:
                try:
                    ok += datetime.date(year, m, int(w[4])).weekday() == MONTH_WD[_norm(wd[4])]
                except ValueError:
                    pass
            return ok
        m = month
        while m <= 12 and score(m) < 0.9 * len(band):
            m += 1
        if m > 12:
            notes.append(('unlesbar', 'kein Monat passt', pno, [w[4] for w, _ in band][:5]))
            continue
        if m != month:
            notes.append(('unlesbar', 'Monat übersprungen', month, m))
        month = m + 1
        prev = None
        for w, wd in band:
            want = MONTH_WD[_norm(wd[4])]
            try:
                d = datetime.date(year, m, int(w[4]))
                good = d.weekday() == want
            except ValueError:
                good = False
            if not good:
                guess = prev + datetime.timedelta(days=1) if prev else None
                if guess and guess.weekday() == want:
                    notes.append(('Tippfehler im PDF', f'Tag „{w[4]} {wd[4]}“ steht an der Stelle von {guess}'))
                    d = guess
                elif guess and guess.day == int(w[4]):
                    notes.append(('Wochentag falsch im PDF', f'{guess} ist mit „{wd[4]}“ beschriftet'))
                    d = guess
                else:
                    notes.append(('unlesbar', m, w[4], wd[4]))
                    continue
            prev = d
            yc = (w[1] + w[3]) / 2
            right = min([c[0][0] for c in cells if abs((c[0][1] + c[0][3]) / 2 - yc) < 3 and c[0][0] > w[0] + 5] + [page_w])
            cont = [v for v in words if abs((v[1] + v[3]) / 2 - yc) < 3 and v[0] >= wd[2] - 0.5 and v[2] <= right - 1
                    and v is not wd]
            out.append(dict(date=d, page=pno, x0=w[0], y0=w[1], y1=w[3], right=right,
                            words=[(round(v[0] - w[0], 1), v[4]) for v in sorted(cont, key=lambda v: v[0])]))
    days = {c['date'] for c in out}
    expected = (datetime.date(year, 12, 31) - datetime.date(year, 1, 1)).days + 1
    if len(days) != expected or len(out) != expected:
        notes.append(('unlesbar', f'{len(out)} Zellen / {len(days)} Tage statt {expected}'))
    return out, notes


def assert_grid_ok(notes, key):
    bad = [n for n in notes if n[0] == 'unlesbar']
    for n in notes:
        print(f'  [{key}] {n[0]}: {" ".join(str(x) for x in n[1:])}')
    if bad:
        sys.exit(f'{key}: Wochentag-Probe nicht bestanden – Layout prüfen.')


def near(col, ref, tol=0.04):
    return all(abs(a - b) <= tol for a, b in zip(col, ref))


# ---------------------------------------------------------------- Ausgabe

def write_output(key, title, source, years, areas, step_title, group_title=None, notice=None):
    """areas: Liste (id, title, group, termine) mit termine = Menge/Liste von (date, art[, notiz]).
    Gleiche Terminlisten werden zu einem Plan zusammengefasst."""
    plans, plan_of = {}, {}
    out_areas = []
    seen = set()
    for aid, atitle, group, events in areas:
        if aid in seen:
            raise SystemExit(f'{key}: doppelte id {aid}')
        seen.add(aid)
        # gleicher Tag + gleiche Art (z. B. Schadstoffmobil an mehreren Standplätzen): ein Eintrag, Notizen verbunden
        merged = {}
        for e in sorted({tuple(e) for e in events}, key=lambda e: (e[0], e[1], (e[2] or '') if len(e) > 2 else '')):
            note = e[2] if len(e) > 2 and e[2] else None
            notes = merged.setdefault((e[0], e[1]), [])
            if note and note not in notes:
                notes.append(note)
        rows = [[d.isoformat(), a] + (['; '.join(n)] if n else []) for (d, a), n in sorted(merged.items())]
        sig = json.dumps(rows, ensure_ascii=False)
        if sig not in plan_of:
            pid = f'p{len(plans) + 1}'
            plan_of[sig] = pid
            plans[pid] = rows
        out_areas.append({'id': aid, 'title': atitle, 'group': group, 'plan': plan_of[sig]})
    data = {
        'key': key, 'title': title, 'source': source, 'stand': datetime.date.today().isoformat(), 'years': years,
        'groupTitle': group_title, 'stepTitle': step_title, 'notice': notice, 'areas': out_areas, 'plans': plans,
    }
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f'{key}.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    n = sum(len(v) for v in plans.values())
    print(f'{key}: {len(out_areas)} areas, {len(plans)} Pläne, {n} Termine -> {os.path.relpath(path, HERE)}')
    return data
