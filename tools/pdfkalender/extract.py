"""Jahresdaten aus PDF-Abfallkalendern erzeugen.

    /usr/bin/python3 -I tools/pdfkalender/extract.py <key> [<key> …]   # oder: all
    /usr/bin/python3 -I tools/pdfkalender/extract.py <key> --refresh   # Cache verwerfen, neu laden

Ergebnis: tools/pdfkalender/out/<key>.json (Format: FORMAT.md). Danach check.py laufen lassen.
"""
import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

KEYS = ['ansbach', 'saaleholzland', 'rahden', 'stemwede', 'mainhausen', 'sontra', 'liederbach', 'gaienhofen', 'oehningen',
        'huellhorst', 'buesingen']


def main(argv):
    refresh = '--refresh' in argv
    keys = [a for a in argv if not a.startswith('--')]
    if not keys or keys == ['all']:
        keys = KEYS
    for key in keys:
        if key not in KEYS:
            sys.exit(f'Unbekannter Ort: {key} (bekannt: {", ".join(KEYS)})')
        mod = importlib.import_module(f'orte.{key}')
        mod.run(refresh=refresh)


if __name__ == '__main__':
    main(sys.argv[1:])
