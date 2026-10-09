"""Prüft alle tools/pdfkalender/out/*.json gegen FORMAT.md.

    /usr/bin/python3 -I tools/pdfkalender/check.py [--today JJJJ-MM-TT]

Geprüft: Schema und Typen, key = Dateiname, ISO-Daten, Jahre passen zu `years`, eindeutige Area-ids,
jede Area verweist auf einen vorhandenen Plan, keine verwaisten Pläne, keine doppelten Einträge,
jede Abfallart wird von WasteCategory.classify erkannt (nicht „Sonstiges“), mindestens ein künftiger Termin
je Datei und je Plan (sonst wäre die Jahrespflege fällig). Exit-Code 1 bei Fehlern.
"""
import datetime
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WASTE_SWIFT = os.path.join(HERE, '..', '..', 'TonneCore', 'Sources', 'TonneCore', 'WasteCategory.swift')


def load_keywords():
    """Schlüsselwörter direkt aus WasteCategory.swift lesen (gleiche Reihenfolge wie classify)."""
    src = open(WASTE_SWIFT, encoding='utf-8').read()
    block = src[src.index('static let keywords'):]
    block = block[:block.index('\n    ]\n')]
    res = []
    for cat, words in re.findall(r'\(\.(\w+),\s*\[([^\]]*)\]\)', block):
        res.append((cat, re.findall(r'"([^"]+)"', words)))
    if len(res) < 8:
        raise SystemExit('check: Schlüsselwörter in WasteCategory.swift nicht gefunden')
    return res


def classify(title, keywords):
    low = title.lower()
    for cat, words in keywords:
        if any(w in low for w in words):
            return cat
    return 'other'


def check_file(path, keywords, today):
    errors = []
    err = errors.append
    try:
        d = json.load(open(path, encoding='utf-8'))
    except Exception as e:  # noqa: BLE001
        return [f'kein gültiges JSON: {e}'], None
    fields = {'key': str, 'title': str, 'source': str, 'stand': str, 'years': list, 'groupTitle': (str, type(None)),
              'stepTitle': str, 'notice': (str, type(None)), 'areas': list, 'plans': dict}
    for f, t in fields.items():
        if f not in d:
            err(f'Feld fehlt: {f}')
        elif not isinstance(d[f], t):
            err(f'Feld {f} hat falschen Typ')
    extra = set(d) - set(fields)
    if extra:
        err(f'unbekannte Felder {sorted(extra)}')
    if errors:
        return errors, None
    key = os.path.basename(path)[:-5]
    if d['key'] != key or not re.fullmatch(r'[a-z0-9_]+', key):
        err(f'key {d["key"]!r} passt nicht zum Dateinamen / Zeichensatz')
    if not re.match(r'https?://', d['source']):
        err('source ist keine URL')
    try:
        datetime.date.fromisoformat(d['stand'])
    except ValueError:
        err(f'stand {d["stand"]!r} ist kein ISO-Datum')
    years = d['years']
    if not years or not all(isinstance(y, int) for y in years) or years != sorted(set(years)):
        err(f'years ungültig {years}')
    ids, used = set(), set()
    bad = [a for a in d['areas'] if not isinstance(a, dict)]
    if bad:
        err(f'{len(bad)} areas sind keine Objekte')
        d['areas'] = [a for a in d['areas'] if isinstance(a, dict)]
    grouped = [a.get('group') is not None for a in d['areas']]
    if any(grouped) and not d['groupTitle']:
        err('Areas mit group, aber groupTitle fehlt')
    if any(grouped) and not all(grouped):
        err('group muss bei allen Areas gesetzt sein oder bei keiner')
    if not d['areas']:
        err('keine areas')
    for a in d['areas']:
        if set(a) != {'id', 'title', 'group', 'plan'}:
            err(f'Area mit falschen Feldern {a}')
            continue
        if not re.fullmatch(r'[a-z0-9_]+', a['id']):
            err(f'Area-id {a["id"]!r} ungültig')
        if a['id'] in ids:
            err(f'doppelte Area-id {a["id"]}')
        ids.add(a['id'])
        if not a['title'] or not isinstance(a['title'], str):
            err(f'Area {a["id"]} ohne Titel')
        if a['plan'] not in d['plans']:
            err(f'Area {a["id"]} verweist auf fehlenden Plan {a["plan"]}')
        used.add(a['plan'])
    orphans = set(d['plans']) - used
    if orphans:
        err(f'verwaiste Pläne {sorted(orphans)}')
    kinds, total, future_file = {}, 0, False
    for pid, rows in d['plans'].items():
        if not rows:
            err(f'Plan {pid} leer')
            continue
        seen, future = set(), False
        for r in rows:
            if not isinstance(r, list) or len(r) not in (2, 3) or not all(isinstance(x, str) and x for x in r):
                err(f'Plan {pid}: ungültiger Eintrag {r}')
                continue
            try:
                day = datetime.date.fromisoformat(r[0])
            except ValueError:
                err(f'Plan {pid}: Datum {r[0]!r} ungültig')
                continue
            if day.year not in years:
                err(f'Plan {pid}: {r[0]} liegt nicht in years {years}')
            if tuple(r[:2]) in seen:
                err(f'Plan {pid}: doppelter Eintrag {r[:2]}')
            seen.add(tuple(r[:2]))
            future |= day >= today
            cat = classify(r[1], keywords)
            kinds[r[1]] = cat
            if cat == 'other':
                err(f'Abfallart {r[1]!r} wird nicht erkannt (Sonstiges)')
            total += 1
        if rows != sorted(rows, key=lambda r: (r[0], r[1], r[2] if len(r) > 2 else '')):
            err(f'Plan {pid} nicht sortiert')
        if not future:
            err(f'Plan {pid}: kein Termin ab {today}')
        future_file |= future
    if not future_file:
        err(f'kein künftiger Termin ab {today}')
    summary = (len(d['areas']), len(d['plans']), total, kinds)
    return errors, summary


def main(argv):
    today = datetime.date.today()
    if '--today' in argv:
        today = datetime.date.fromisoformat(argv[argv.index('--today') + 1])
    keywords = load_keywords()
    files = sorted(glob.glob(os.path.join(HERE, 'out', '*.json')))
    if not files:
        sys.exit('check: keine Dateien in out/')
    failed = False
    for path in files:
        errors, summary = check_file(path, keywords, today)
        name = os.path.basename(path)
        if errors:
            failed = True
            print(f'FEHLER {name}:')
            for e in errors[:20]:
                print('   ', e)
            if len(errors) > 20:
                print(f'    … {len(errors) - 20} weitere')
        else:
            areas, plans, total, kinds = summary
            arten = ', '.join(f'{k}→{v}' for k, v in sorted(kinds.items()))
            print(f'ok     {name}: {areas} areas, {plans} Pläne, {total} Termine | {arten}')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main(sys.argv[1:])
