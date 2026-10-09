"""Stadt Ansbach: je Straße eine PDF auf p-42.net (Kürzel R, GS, P, B in der Tageszelle).
Straßenliste: Formular index_str.php je Anfangsbuchstabe. Dateinamen/Parameter sind Latin-1-kodiert.
Feiertagsverlegungen sind laut PDF bereits eingearbeitet."""
import html
import re

import common

BASE = 'https://www.p-42.net/cal/sansb2/'
SOURCE = BASE + 'index_str.php'
LETTERS = 'A Ä B C D E F G H I J K L M N O P Q R S T U V W X Y Z'.split()
CODES = {'R': 'Restmüll', 'GS': 'Gelber Sack', 'P': 'Altpapier', 'B': 'Biomüll'}
YEAR = 2026  # p-42 nennt das Jahr nicht in der Adresse; die PDFs tragen „Abfuhrplan <Jahr>“ (wird geprüft)


def streets(refresh):
    names = []
    for letter in LETTERS:
        path = common.fetch(f'{SOURCE}?submit=Weiter&ortsauswahl={letter}', f'ansbach_list_{common.slug(letter) or "ae"}.html',
                            encoding='latin-1', refresh=refresh)
        text = open(path, encoding='latin-1').read()
        sel = text[text.find('selStras'):]
        sel = sel[:sel.find('</select>')]
        names += [html.unescape(n) for n in re.findall(r'<option\s+(?:selected\s+)?value ="([^"]+)"', sel)]
    return names


def run(refresh=False):
    areas = []
    names = streets(refresh)
    for name in names:
        pdf = common.fetch(f'{BASE}download.php?file=Stadt Ansbach-{name}.pdf', f'ansbach_{common.slug(name)}.pdf',
                           encoding='latin-1', refresh=refresh)
        doc = common.fitz.open(pdf)
        head = doc[0].get_text()
        m = re.search(r'Straße/Stadtteil:\s*(.+)', head)
        if f'Abfuhrplan {YEAR}' not in head or not m:
            raise SystemExit(f'ansbach: {name}: unerwarteter Kopf {head[-120:]!r}')
        # Titel wie in der Straßenauswahl der Stadt; „_“ steht dort für „/“ (PDF: „Promenade/Busbahnhof“)
        title = name.replace('_', '/')
        cells, notes = common.parse_grid(pdf, YEAR)
        common.assert_grid_ok(notes, f'ansbach/{name}')
        events = [(c['date'], CODES[t]) for c in cells for _, t in c['words'] if t in CODES]
        areas.append((common.slug(name), title, None, events))
    print(f'ansbach: {len(names)} Straßen gelesen')
    common.write_output('ansbach', 'Stadt Ansbach', SOURCE, [YEAR], areas, step_title='Straße')
