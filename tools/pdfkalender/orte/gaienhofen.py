"""Gemeinde Gaienhofen (Landkreis Konstanz): ein Jahreskalender für die ganze Gemeinde, Abfallart als Text."""
import common
from orte import textgrid
from orte._holidays import HOLIDAYS

PAGE = 'https://www.gaienhofen.de/de/rathaus/entsorgung-umwelt/abfall'
PDF = {2026: 'https://www.gaienhofen.de/_Resources/Persistent/72f24706f7f3467365476ec13c83578a460e861f/Abfallkalender_Gaienhofen_2026.pdf'}
VOCAB = [('biomüll', ('Biomüll',)), ('bio', ('Biomüll',)), ('restmüll', ('Restmüll',)),
         ('gelber sack', ('Gelber Sack',)), ('blaue tonne', ('Altpapier (Blaue Tonne)',)),
         ('altholz', ('Altholz',)), ('sperrmüll', ('Sperrmüll',)), ('elektroschrott', ('Elektroschrott',)),
         ('problemstoff', ('Problemstoffsammlung',)), ('problemstoffe', ('Problemstoffsammlung',))]
IGNORE = HOLIDAYS + ['wertstoffhof']


def run(refresh=False):
    events = []
    for year, url in PDF.items():
        pdf = common.fetch(url, f'gaienhofen_{year}.pdf', refresh=refresh)
        events += textgrid.extract(pdf, year, VOCAB, IGNORE, 'gaienhofen')
    common.write_output('gaienhofen', 'Gemeinde Gaienhofen', PDF[max(PDF)], sorted(PDF),
                        [('gaienhofen', 'Gaienhofen', None, events)], step_title='Ort')
