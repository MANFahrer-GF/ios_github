"""Gemeinde Öhningen (Landkreis Konstanz): ein Jahreskalender für alle Ortsteile, Abfallart als Text."""
import common
from orte import textgrid
from orte._holidays import HOLIDAYS

PAGE = 'https://www.oehningen.de/buergerservice/wohnen/abfall'
PDF = {2026: 'https://www.oehningen.de/fileadmin/redakteur/Abfallkalender_%C3%96hningen_2026.pdf'}
VOCAB = [('bio zusätzliche abfuhr', ('Biomüll', 'zusätzliche Abfuhr')), ('bio', ('Biomüll',)),
         ('restmüll', ('Restmüll',)), ('gelber sack', ('Gelber Sack',)), ('papier', ('Altpapier',)),
         ('problemmüll', ('Problemmüll (Schadstoffsammlung)',)), ('altholz', ('Altholz',)),
         ('sperrmüll', ('Sperrmüll',)), ('elektroschrott', ('Elektroschrott',))]
# „Anmeldeschl. E-Schrott“ ist nur der Anmeldeschluss, keine Abfuhr.
IGNORE = HOLIDAYS + ['wertstoffhof', 'wertstofhof', 'anmeldeschl']


def run(refresh=False):
    events = []
    for year, url in PDF.items():
        pdf = common.fetch(url, f'oehningen_{year}.pdf', refresh=refresh)
        events += textgrid.extract(pdf, year, VOCAB, IGNORE, 'oehningen')
    common.write_output('oehningen', 'Gemeinde Öhningen', PDF[max(PDF)], sorted(PDF),
                        [('oehningen', 'Öhningen', None, events)], step_title='Ort')
