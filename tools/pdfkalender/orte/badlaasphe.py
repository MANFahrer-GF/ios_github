"""Stadt Bad Laasphe (Kreis Siegen-Wittgenstein): Jahresraster (PreZero). In der Tageszelle steht ein Buchstabe A–E
(Abfuhrbezirk Rest-, Bio- und Papiertonne) auf einer Fläche, deren Farbe die Tonne angibt: grau Restmüll, braun
Biomüll, blau Altpapier. Eine gelbe Fläche mit Ziffer 1–7 ist der Bezirk der Gelben Tonne, rot I/II/III eine
Schadstoffsammlung. Im Januar liegen die Farben nicht als Vektorflächen vor – darum werden alle Farben aus dem
gerenderten Bild gelesen (PixelSampler).

Ort/Straße → Bezirk steht auf Seite 2. In der PDF 2027 fehlen dort die Buchstaben vor den fünf Absätzen; die
PDF 2026 hat dieselben Absätze mit „A“ bis „E“ in dieser Reihenfolge (geprüft 21.11.2026). Manche Orte haben für
Papier einen anderen Bezirk als für Rest- und Biomüll („Nur Papiermüll: …“). Nur im Teil Gelbe Tonne genannt:
Welschengeheu (5) und „Rüppershäuser Straße 1-5, Im Gründchen“ (1) – aufgenommen mit Gelber Tonne und Schadstoff, ohne
Rest/Bio/Papier (Prüfbefund 21.11.2026: sonst fänden Nutzer dort gar keine Auswahl).
Nutzerwunsch Roman Schössler, 21.11.2026."""
import re

import common
from orte import colorgrid

PAGE = 'https://www.stadt-badlaasphe.de/abfallentsorgung/'
# Die Seite blockt einfache Abrufe (403): PDF von Hand nach cache/badlaasphe_<Jahr>.pdf legen.
PDF = {2027: 'https://www.stadt-badlaasphe.de/wp-content/uploads/2026/11/Abfallkalender_2027.pdf'}
PALETTE = [((0.75, 0.75, 0.75), 'Restmüll'), ((0.59, 0.28, 0.02), 'Biomüll'), ((0.31, 0.51, 0.74), 'Altpapier'),
           ((1.0, 1.0, 0.0), 'Gelbe Tonne'), ((1.0, 0.0, 0.0), 'Schadstoff')]
SCHADSTOFF = {'l': 'Kernstadt, Parkplatz Wabachpark / Gennernbach 38', 'll': 'Banfe, Feuerwehrgerätehaus',
              'lll': 'Feudingen, Parkplatz Schulgelände Tannenwald'}

# (Rest/Bio, Papier, Gelbe Tonne)
ORTE = {
    'Bermershausen': ('A', 'A', 1), 'Bernshausen': ('A', 'A', 2), 'Feudingen': ('A', 'A', 3), 'Glashütte': ('A', 'A', 5),
    'Großenbach': ('A', 'A', 5), 'Heiligenborn': ('A', 'A', 5), 'Lindenfeld': ('A', 'A', 5), 'Volkholz': ('A', 'A', 5),
    'Weide': ('A', 'A', 5), 'Fischelbach': ('A', 'B', 2), 'Sohl': ('A', 'B', 2), 'Banfe': ('B', 'A', 6),
    'Oberndorf': ('C', 'A', 5), 'Rückershausen': ('C', 'A', 1), 'Industriegebiet „In den Espen“': ('C', 'A', 1),
    'Rüppershausen': ('C', 'A', 5), 'Herbertshausen': ('B', 'B', 6), 'Hesselbach': ('B', 'B', 2),
    'Laaspherhütte': ('B', 'B', 6), 'Amtshausen': ('C', 'C', 5), 'Holzhausen': ('C', 'C', 5),
    'Kunst-Wittgenstein': ('C', 'C', 6), 'Puderbach': ('C', 'E', 1), 'Saßmannshausen': ('C', 'C', 1),
    'Steinbach': ('C', 'C', 5), 'Niederlaasphe': ('E', 'E', 1),
    # Nur Gelbe Tonne (Rest/Bio/Papier nennt der Kalender dort nicht)
    'Welschengeheu': (None, None, 5),
}
NUR_GELB_KERNSTADT = {'Rüppershäuser Straße 1-5': 1, 'Im Gründchen': 1}
KERNSTADT = {
    'C': 'Am Dillstein, Am Lärchenwäldchen, Buchwiesenstraße, Dammstraße, Ditzroder Weg, Friedrichshütte, Gartenstraße, '
         'Gennernbach, Hof Breitenbach, Hof Breitenbach – Herbertshausen, Im Wabach, In der Hohl, Kastanienweg, '
         'Kneebuschweg, Max-Präger-Weg, Mühlenstraße, Mühlfeld, Obere Bienhecke, Obere Wallachei, Oberer Buhlschlag, '
         'Oberer Schuleborn, Schloß Wittgenstein, Schloßberg, Schloßstraße, Untere Bienhecke, Unterer Buhlschlag, '
         'Unterer Schuleborn, Vor den Hasseln, Wiesenbacher Weg, Wilhelmstraße, Zum Winterkasten',
    'D': 'Am Eichelkamp, Am Waldrand, An der Hahler, Bahnhofstraße, Bergstraße, Brückenstraße, Brunnenstraße, Butzebach, '
         'Feldstraße, Forsthaus Hirtsgrund, Friedrichstraße, Hahlerweg, Hinterfang, Höhenweg, Hubertusweg, Im Laasphetal, '
         'Kalteborn, Kirchplatz, Königstraße, Kurstraße, Lahnstraße, Mauerstraße, Mozartweg, Ostplatz, Ostpreußenstraße, '
         'Puderbacher Weg, Sebastian-Kneipp-Straße, Steinackerstraße, Steinweg, Turnerstraße, Unterm Hombach, '
         'Vor dem Fang, Waldweg, Wallstraße, Wasserstraße einschl. Bracht, Wehrstraße, Wilhelmsplatz, Zum Lehrberg, '
         'Zwischen Landwehr',
    'E': 'Am Birkenstrauch, Am Feldberg, Am Galgenberg, Auf der Pfingstweide, Bäderborn, Brandenburger Weg, '
         'Forsthaus Litzelbach, Hirtsgrund, Hirtsgrunder Weg, In der Aue, In der Grube, In der Stockwiese, '
         'Industriestraße, Kanarienweg, Lahnuferstraße, Ludwig-Koch-Straße, Mecklenburger Weg, Niederlaaspher Weg, '
         'Obere Rote Hardt, Pommernweg, Sachsenweg, Schlesische Straße, Sudetenweg, Thüringer Weg, Untere Rote Hardt, '
         'Zum Litzelbach',
}
# Gelbe Tonne der Kernstadt: Bezirk 4 und 7 (Seite 2, rechte Spalte); „Hof Breitenbach – Herbertshausen“ steht bei 6
GELB_KERNSTADT_4 = set(KERNSTADT['C'].split(', ')) | set(KERNSTADT['E'].split(', '))
GELB_KERNSTADT_4 -= {'Hof Breitenbach', 'Hof Breitenbach – Herbertshausen'}
GELB_KERNSTADT_7 = set(KERNSTADT['D'].split(', '))
GELB_SONDER = {'Hof Breitenbach – Herbertshausen': 6}
NOTICE = ('Schadstoffsammlung jeweils 9–12 Uhr. „Hof Breitenbach“ ist bei der Gelben Tonne keinem Bezirk zugeordnet. '
          'Für Welschengeheu, Rüppershäuser Straße 1-5 und Im Gründchen nennt der Kalender nur die Gelbe Tonne – Rest-, Bio- und '
          'Papiertonne bitte beim Entsorger erfragen. Sperrmüll auf Abruf (Anforderungskarte oder Homepage der Stadt).')


def _norm(text):
    return re.sub(r'[\s ]+', ' ', text.replace('–', '-').replace('"', '').replace('„', '').replace('“', '')).strip()


def check_names(pdf):
    """Jeder Ort und jede Straße muss so auf Seite 2 stehen – Schutz gegen Tippfehler in den Listen oben."""
    page2 = _norm(common.fitz.open(pdf)[1].get_text())
    names = list(ORTE) + list(NUR_GELB_KERNSTADT) + [s for v in KERNSTADT.values() for s in v.split(', ')]
    missing = [n for n in names if _norm(n) not in page2]
    if missing:
        raise SystemExit(f'badlaasphe: nicht auf Seite 2 gefunden: {missing}')


def calendar(pdf, year):
    cells, notes = common.parse_grid(pdf, year, pages=[0])
    common.assert_grid_ok(notes, 'badlaasphe')
    if len(cells) != (366 if year % 4 == 0 else 365):
        raise SystemExit(f'badlaasphe {year}: {len(cells)} Tage gelesen')
    sampler = colorgrid.PixelSampler(common.fitz.open(pdf))
    letters, yellow, hazard = [], [], []
    for c in cells:
        yc = (c['y0'] + c['y1']) / 2
        for x, t in c['words']:
            if t not in {'A', 'B', 'C', 'D', 'E', '1', '2', '3', '4', '5', '6', '7', 'l', 'll', 'lll'}:
                continue
            kind = colorgrid.classify(sampler.color(c['page'], c['x0'] + x - 1.2, yc), PALETTE, tol=0.1)
            if t in 'ABCDE' and kind in ('Restmüll', 'Biomüll', 'Altpapier'):
                letters.append((c['date'], t, kind))
            elif t.isdigit() and kind == 'Gelbe Tonne':
                yellow.append((c['date'], int(t)))
            elif t in SCHADSTOFF and kind == 'Schadstoff':
                hazard.append((c['date'], t))
            else:
                raise SystemExit(f'badlaasphe {c["date"]}: „{t}“ mit unbekannter Farbe ({kind})')
    return letters, yellow, hazard


def run(refresh=False):
    areas = {}
    for name, (rb, pap, gelb) in ORTE.items():
        areas[name] = (None, rb, pap, gelb)
    for letter, streets in KERNSTADT.items():
        for s in streets.split(', '):
            gelb = GELB_SONDER.get(s) or (4 if s in GELB_KERNSTADT_4 else 7 if s in GELB_KERNSTADT_7 else None)
            areas[s] = ('Kernstadt', letter, letter, gelb)
    for s, gelb in NUR_GELB_KERNSTADT.items():
        areas[s] = ('Kernstadt', None, None, gelb)
    per = {name: [] for name in areas}
    for year, url in PDF.items():
        pdf = common.fetch(url, f'badlaasphe_{year}.pdf', refresh=refresh)
        check_names(pdf)
        letters, yellow, hazard = calendar(pdf, year)
        for name, (_, rb, pap, gelb) in areas.items():
            for d, letter, kind in letters:
                if (kind == 'Altpapier' and letter == pap) or (kind != 'Altpapier' and letter == rb):
                    per[name].append((d, kind, None))
            per[name] += [(d, 'Gelbe Tonne', None) for d, n in yellow if n == gelb]
            per[name] += [(d, 'Schadstoffsammlung', SCHADSTOFF[t]) for d, t in hazard]
    # Zweistufig: erst „Ortsteile“ oder „Kernstadt“, dann Ort bzw. Straße (check.py: Gruppe bei allen oder keiner)
    out = [(common.slug(f'{group or ""} {name}'), name, group or 'Ortsteile', per[name])
           for name, (group, *_rest) in sorted(areas.items(), key=lambda kv: (kv[1][0] or '', kv[0]))]
    common.write_output('badlaasphe', 'Stadt Bad Laasphe', PDF[max(PDF)], sorted(PDF), out,
                        step_title='Ort oder Straße', group_title='Ortsteile oder Kernstadt', notice=NOTICE)
