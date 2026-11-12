"""Gemeinde Florstadt (Wetteraukreis): Die PDF ist reine Grafik, die Gemeindeseite zeigt die Termine aber aus einer
WordPress-Terminliste (JetEngine, Beitragstyp "abfallkalender", Filter = Taxonomie "abfallkalender-kategorie" = Ortsteil).
Dieselben Daten liefert die offene WordPress-REST-Schnittstelle: /wp-json/wp/v2/abfallkalender (Feld meta.datum_meta =
Tag als UTC-Mitternacht). Quelle: https://www.florstadt.de/abfallkalender
Gelesen werden Restmüll, Biomüll, Altpapier (Blaue Tonne) und Gelbe Tonne; Abfallsammelplatz und Grünabfälle
(Sammeltermine, keine Tonnenleerung) bleiben draußen. Abbruch bei unbekannter Art, Wochenende, abweichender Anzahl."""
import collections
import datetime
import json

import common

PAGE = 'https://www.florstadt.de/abfallkalender'
API = 'https://www.florstadt.de/wp-json/wp/v2/abfallkalender?per_page=100&_fields=id,title,meta,abfallkalender-kategorie&abfallkalender-kategorie='
OT = [(948, 'leidhecken', 'Leidhecken'), (946, 'nieder_florstadt', 'Nieder-Florstadt'),
      (950, 'nieder_mockstadt', 'Nieder-Mockstadt'), (947, 'ober_florstadt', 'Ober-Florstadt'),
      (949, 'staden', 'Staden'), (951, 'stammheim', 'Stammheim')]
ART = {'Restmüll': 'Restmüll', 'Restmülltonne': 'Restmüll', 'Kompost/Bioabfall': 'Biomüll', 'Blaue Tonne': 'Altpapier',
       'Gelbe Tonne': 'Gelbe Tonne'}
SKIP = {'Abfallsammelplatz', 'Grünabfälle'}


def events(tid, name, refresh):
    path = common.fetch(API + str(tid), name=f'florstadt_{tid}.json', refresh=refresh)
    with open(path, encoding='utf-8') as f:
        posts = json.load(f)
    if not 60 <= len(posts) < 100:  # 100 = Seitengrenze erreicht, weniger als 60 = Liste unvollständig
        raise SystemExit(f'florstadt {name}: {len(posts)} Einträge, erwartet 60–99')
    ev, wd = [], collections.defaultdict(collections.Counter)
    for p in posts:
        titel = p['title']['rendered']
        if titel in SKIP:
            continue
        if titel not in ART:
            raise SystemExit(f'florstadt {name}: unbekannte Art {titel!r}')
        ts = p['meta']['datum_meta']
        if ts % 86400:
            raise SystemExit(f'florstadt {name}: {ts} ist keine UTC-Mitternacht')
        day = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).date()
        if day.weekday() > 4:
            raise SystemExit(f'florstadt {name}: {titel} am Wochenende {day}')
        ev.append((day, ART[titel]))
        wd[ART[titel]][day.weekday()] += 1
    for art, c in wd.items():  # Wochentag-Probe: Regeltag muss klar überwiegen, Abweichung nur Feiertagsverschiebung
        regel, n = c.most_common(1)[0]
        if n < 0.8 * sum(c.values()):
            raise SystemExit(f'florstadt {name}: {art} ohne klaren Wochentag {dict(c)}')
    if len(ev) != len(set(ev)):
        raise SystemExit(f'florstadt {name}: doppelte Termine')
    return ev


def run(refresh=False):
    areas = [(key, title, None, events(tid, title, refresh)) for tid, key, title in OT]
    common.write_output('florstadt', 'Gemeinde Florstadt', PAGE, [2026], areas, step_title='Ortsteil',
                        notice='Die Gemeinde veröffentlicht die Termine bisher bis Dezember 2026; Sammelplatz- und '
                               'Grünabfalltermine sind nicht enthalten.')
