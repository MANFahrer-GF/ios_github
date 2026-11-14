"""Gemeinde Bischofsheim (Landkreis Groß-Gerau): eigene Abfuhr, nicht im c-trace-Portal des AWV Groß-Gerau.

Quellseite: https://www.bischofsheim.de/rathaus-und-politik/uebersicht-der-verwaltung/fachbereich-bauen-und-bauhof/fachdienst-bauen/abfall/abfallkalender.html
- Abfallkalender_2026.pdf ist nur ein Bild (keine Textebene). Die Termine wurden am 14.11.2026 vom Bild (300/600 dpi)
  abgelesen und stehen hier von Hand. Jede Zeile wird gegen den Wochentag im Bild geprüft, dazu Bezirk und Takt (unten).
- abfuhrbezirke.pdf hat Text: Straßen je Bezirk (Bezirk 1 Montag, Bezirk 2 Dienstag), Wortlaut übernommen, Tippfehler
  geglättet (Beethofen-, Franz-Schuber-, „Dr.-Hans Böckler- Platz“).

Kalender: Bio + Restmüll bzw. Bio + Papier je Bezirk (Bez. I / Bez. II), Gelbe Tonne, Grünabfälle und Sondermüll für die
ganze Gemeinde. Sperrmüll steht im Kalender, wird laut Legende aber nur auf Abruf (Sperrkarte) abgefahren: nicht übernommen.
"""
import datetime

import common

PAGE = ('https://www.bischofsheim.de/rathaus-und-politik/uebersicht-der-verwaltung/fachbereich-bauen-und-bauhof/'
        'fachdienst-bauen/abfall/abfallkalender.html')
WD = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
# Kürzel: R1/R2 = „Bio / Restmüll Bez. I/II“, P1/P2 = „Bio / Papier Bez. I/II“, GT Gelbe Tonne, GR Grünabfälle,
# SM Sondermüll (mobile Sammlung), WB Christbäume. Sperrmüll-Zellen sind weggelassen (siehe oben).
TEXT = """
01-02 Fr GT | 01-05 Mo R1 | 01-06 Di R2 | 01-07 Mi SM | 01-09 Fr WB | 01-12 Mo P1 | 01-13 Di P2 | 01-15 Do GT
01-19 Mo R1 | 01-20 Di R2 | 01-26 Mo P1 | 01-27 Di P2 | 01-29 Do GT | 01-31 Sa SM
02-02 Mo R1 | 02-03 Di R2 | 02-09 Mo P1 | 02-10 Di P2 | 02-12 Do GT | 02-16 Mo R1 | 02-17 Di R2 | 02-23 Mo P1
02-24 Di P2 | 02-26 Do GT
03-02 Mo R1 | 03-03 Di R2 | 03-04 Mi SM | 03-05 Do GR | 03-09 Mo P1 | 03-10 Di P2 | 03-12 Do GT | 03-16 Mo R1
03-17 Di R2 | 03-23 Mo P1 | 03-24 Di P2 | 03-26 Do GT | 03-28 Sa R1 | 03-30 Mo R2
04-07 Di P1 | 04-08 Mi P2 SM | 04-10 Fr GT | 04-13 Mo R1 | 04-14 Di R2 | 04-20 Mo P1 | 04-21 Di P2 | 04-23 Do GT
04-27 Mo R1 | 04-28 Di R2
05-02 Sa SM | 05-04 Mo P1 | 05-05 Di P2 | 05-06 Mi GR | 05-07 Do GT | 05-11 Mo R1 | 05-12 Di R2 | 05-18 Mo P1
05-19 Di P2 | 05-20 Mi SM | 05-21 Do GT | 05-26 Di R1 | 05-27 Mi R2
06-01 Mo P1 | 06-02 Di P2 | 06-05 Fr GT | 06-08 Mo R1 | 06-09 Di R2 | 06-15 Mo P1 | 06-16 Di P2 | 06-18 Do GT
06-22 Mo R1 | 06-23 Di R2 | 06-29 Mo P1 | 06-30 Di P2
07-01 Mi SM | 07-02 Do GT | 07-06 Mo R1 | 07-07 Di R2 | 07-13 Mo P1 | 07-14 Di P2 | 07-16 Do GT | 07-20 Mo R1
07-21 Di R2 | 07-27 Mo P1 | 07-28 Di P2 | 07-30 Do GT
08-03 Mo R1 | 08-04 Di R2 | 08-10 Mo P1 | 08-11 Di P2 | 08-13 Do GT | 08-15 Sa SM | 08-17 Mo R1 | 08-18 Di R2
08-24 Mo P1 | 08-25 Di P2 | 08-27 Do GT | 08-31 Mo R1
09-01 Di R2 | 09-02 Mi SM | 09-03 Do GR | 09-09 Mi P1 | 09-10 Do P2 | 09-11 Fr GT | 09-14 Mo R1 | 09-15 Di R2
09-21 Mo P1 | 09-22 Di P2 | 09-24 Do GT | 09-28 Mo R1 | 09-29 Di R2 | 09-30 Mi SM
10-05 Mo P1 | 10-06 Di P2 | 10-08 Do GT | 10-12 Mo R1 | 10-13 Di R2 | 10-19 Mo P1 | 10-20 Di P2 | 10-22 Do GT
10-26 Mo R1 | 10-27 Di R2 | 10-29 Do GR | 10-31 Sa SM
11-02 Mo P1 | 11-03 Di P2 | 11-05 Do GT | 11-09 Mo R1 | 11-10 Di R2 | 11-16 Mo P1 | 11-17 Di P2 | 11-18 Mi SM
11-19 Do GT | 11-23 Mo R1 | 11-24 Di R2 | 11-30 Mo P1
12-01 Di P2 | 12-03 Do GT | 12-07 Mo R1 | 12-08 Di R2 | 12-14 Mo P1 | 12-15 Di P2 | 12-17 Do GT | 12-19 Sa R1
12-21 Mo R2 | 12-28 Mo P1 | 12-29 Di P2 | 12-31 Do GT
"""
# Vom Regel-Wochentag abweichende Termine, so im Bild gedruckt (Ostern, Pfingsten, Fronleichnam, Neujahr, Weihnachten;
# die Woche 07.–11.09. ohne Feiertag, vermutlich Kerb). Alles andere außerhalb der Regel bricht ab.
RULE = {'1': 0, '2': 1, 'GT': 3}
SHIFTED = {'1': {'03-28', '04-07', '05-26', '09-09', '12-19'}, '2': {'03-30', '04-08', '05-27', '09-10', '12-21'},
           'GT': {'01-02', '04-10', '06-05', '09-11'}}
SM_NOTE = {2: 'Parkplatz Berliner Straße (hinter dem Friedhof), 16.00–18.30 Uhr',
           5: 'Parkplatz Berliner Straße (hinter dem Friedhof), 12.00–13.30 Uhr'}

# Straßen laut abfuhrbezirke.pdf. „August-Bebel-Straße bis Rheinstraße“ steht dort in beiden Bezirken; die Karte derselben
# Datei färbt den Abschnitt nördlich der Rheinstraße als Bezirk 2 (wie Darmstädter Straße und Am Alten Gerauer Weg), daher
# nur dort. Römerstraße und Friedrich-Ebert-Straße fehlen in beiden Listen (nur als Grenze genannt); die Karte zeigt die
# Römerstraße in Bezirk 1, die Friedrich-Ebert-Straße in Bezirk 2.
BEZIRK_1 = """Alemannenweg; Am Alten Gerauer Weg (von Beethovenstraße bis Im Attich); Am Bauschheimer Weg; Am Flurgraben;
Am Himmelspfad; An den Sportstätten; Auf dem Bügen; Auf dem Goern; Auf dem Farrweg; Auf dem Wörth;
August-Bebel-Straße (von Rheinstraße bis Ginsheimer Straße); Am Kirschbaum; Beethovenstraße; Berliner Straße;
Breslauer Straße; Darmstädter Straße (ab Rheinstraße bis Friedhof); Danziger Straße; Dresdner Straße; Eifelweg;
Feldbergstraße; Frankenweg; Freiligrathstraße; Frohnseestraße (bis Friedrich-Ebert-Straße);
Frohnseestraße (ab Friedrich-Ebert-Straße bis Im Attich); Geibelstraße; Georg-Fischer-Straße; Ginsheimer Landstraße;
Ginsheimer Straße (bis Römerstraße); Goethestraße; Hans-Dorr-Allee; Heinrich-Hünerkopf-Weg; Hessenring;
Hinterm Eulensee; Hunsrückweg; In den Sternäckern; In der Nachtweide; Im Attich; Im Dornbusch; Im Espital; Im Griesböhl;
Im Mönchbruch; Im Pfeiffersgrund; Karlsbader Straße; Kantstraße; Keltenweg; Königsberger Straße;
Mainzer Straße (gerade Hausnummern); Mozartstraße; Odenwaldweg; Pfälzerweg; Rheingauweg; Rhönweg; Riedweg; Ringstraße;
Römerstraße; Röntgenstraße; Schulstraße (ab Friedrich-Ebert-Straße bis Darmstädter Straße); Schwarzwaldweg; Spessartweg;
Treburer Straße; Vogelsbergweg; Wiesenecker Straße; Wingertspfad"""
BEZIRK_2 = """An der Kreuzlache; An der Steinlach; Am Schindberg; Dörrwiese; Im Forst; Im Schlanken; Im Wüsten Forst;
Mittelgewann; Neben dem Mühlweg; Birkenhof; Margarethenhof; Tannenhof; Wielandhof; Peking; Birkenweg;
Dr.-Hans-Böckler-Platz; Dr.-Hans-Böckler-Straße; Erlenweg; Flörsheimer Straße; In der Hochgewann; Lindenweg;
Platanenstraße; Raunheimer Straße; Rüsselsheimer Straße; Ulmenstraße; Zur Pappelallee; An der Bahn;
Am Alten Gerauer Weg (bis Beethovenstraße); Am Alten Kostheimer Weg; Am Mainweg; Am Rampen (Bahnhof);
August-Bebel-Straße (bis Rheinstraße); Bahnhofstraße; Bismarckstraße; Dammstraße; Darmstädter Straße (bis Rheinstraße);
Dreihäusergasse; Eleonorenstraße; Frankfurter Straße; Franz-Schubert-Straße; Friedrich-Ebert-Straße; Friedrichstraße;
Frohnseestraße (bis Bismarckstraße); Gabelsberger Straße; Gartenstraße; Ginsheimer Straße (übriger Teil);
Gustavsburger Straße; Gutenbergstraße; Hochheimer Straße; Im Apfelgarten; Im Kappesgarten; Im Klinker; Kasteler Straße;
Ludwigstraße; Mainstraße; Mainzer Straße (ungerade Hausnummern); Mittelgasse; Parkweg; Rheinstraße; Sackgasse;
Schillerstraße; Schlichtergasse; Schulstraße (bis Friedrich-Ebert-Straße); Spelzengasse; Taunusstraße; Untergasse;
Vor der Pforte; Weisenauer Gasse; Wiesbadener Straße; Wilhelmstraße"""


def events(year=2026):
    ev = {'1': [], '2': []}
    seen = {'1': [], '2': [], 'GT': []}
    for item in TEXT.replace('\n', '|').split('|'):
        parts = item.split()
        if not parts:
            continue
        mm, dd = parts[0].split('-')
        day = datetime.date(year, int(mm), int(dd))
        if WD[day.weekday()] != parts[1]:
            raise SystemExit(f'bischofsheim: {day} ist kein {parts[1]}')
        for code in parts[2:]:
            if code in ('R1', 'R2', 'P1', 'P2'):
                bez = code[1]
                ev[bez] += [(day, 'Biomüll'), (day, 'Restmüll' if code[0] == 'R' else 'Altpapier')]
                seen[bez].append((day, code[0]))
                rule = bez
            elif code == 'GT':
                for b in ev:
                    ev[b].append((day, 'Gelbe Tonne'))
                seen['GT'].append((day, 'GT'))
                rule = 'GT'
            elif code in ('GR', 'SM', 'WB'):
                name = {'GR': 'Grünschnitt', 'SM': 'Schadstoffmobil', 'WB': 'Weihnachtsbäume'}[code]
                note = SM_NOTE[day.weekday()] if code == 'SM' else None
                for b in ev:
                    ev[b].append((day, name, note) if note else (day, name))
                continue
            else:
                raise SystemExit(f'bischofsheim: unbekanntes Kürzel {code} am {day}')
            regular = day.weekday() == RULE[rule]
            if regular == (parts[0] in SHIFTED[rule]):
                raise SystemExit(f'bischofsheim: {day} {code} passt nicht zur Wochentagsregel/Ausnahmeliste')
    check_rhythm(seen)
    return ev


def check_rhythm(seen):
    """Bio jede Woche, Restmüll und Papier streng im Wechsel, Gelbe Tonne alle zwei Wochen, Bez. II am nächsten Werktag."""
    for bez in ('1', '2'):
        rows = sorted(seen[bez])
        # vorgezogen auf Samstag (28.03., 19.12.) zählt zur folgenden Woche
        weeks = [(d + datetime.timedelta(days=2 if d.weekday() == 5 else 0)).isocalendar()[1] for d, _ in rows]
        if weeks != list(range(weeks[0], weeks[0] + len(weeks))):
            raise SystemExit(f'bischofsheim: Bezirk {bez} nicht jede Woche: {weeks}')
        kinds = [k for _, k in rows]
        if any(a == b for a, b in zip(kinds, kinds[1:])):
            raise SystemExit(f'bischofsheim: Bezirk {bez} Restmüll/Papier nicht im Wechsel')
    for (d1, k1), (d2, k2) in zip(sorted(seen['1']), sorted(seen['2'])):
        nxt = d1 + datetime.timedelta(days=2 if d1.weekday() == 5 else 1)
        if k1 != k2 or d2 != nxt:
            raise SystemExit(f'bischofsheim: Bez. II {d2} folgt nicht auf Bez. I {d1}')
    gt = sorted(d for d, _ in seen['GT'])
    weeks = [d.isocalendar()[1] for d in gt]
    if any(b - a != 2 for a, b in zip(weeks, weeks[1:])):
        raise SystemExit(f'bischofsheim: Gelbe Tonne nicht 14-täglich: {weeks}')


def streets(text):
    return [s.strip() for s in text.replace('\n', ' ').split(';') if s.strip()]


def run(refresh=False):
    ev = events()
    areas = [(common.slug(s), s, None, ev[bez]) for bez, text in (('1', BEZIRK_1), ('2', BEZIRK_2)) for s in streets(text)]
    areas.sort(key=lambda a: a[1])
    common.write_output('bischofsheim', 'Gemeinde Bischofsheim', PAGE, [2026], areas, step_title='Straße',
                        notice='Sperrmüll nicht enthalten – er wird nur auf Abruf mit der Sperrkarte abgefahren.')
