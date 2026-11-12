"""Gemeinde Rockenberg (Wetteraukreis): der Abfallkalender liegt nur als Bild vor (zwei WebP-Dateien mit je sechs Monaten,
Quelle: https://www.rockenberg.de/seite/828630/müllkalender.html). Es gibt keinen Text zum Auslesen; die Termine wurden
am 12.11.2026 vom Bild abgelesen und stehen hier von Hand. Die Wochentage im Bild werden gegen das Datum geprüft.
Ro = Rockenberg, Opp = Oppershofen; ohne Zusatz gilt der Eintrag für beide Ortsteile."""
import datetime

import common

PAGE = 'https://www.rockenberg.de/seite/828630/m%C3%BCllkalender.html'
WD = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
# Kürzel: RM Restmüll, BIO Biomüll, DSD Gelbe Tonne, PA Altpapier, GRÜN Grün- und Gartenabfall, SMH Sondermüll Haushalte,
# WB Weihnachtsbaum; Endung :Ro / :Opp = nur dieser Ortsteil
TEXT = """
01-08 Do RM:Ro | 01-09 Fr RM:Opp DSD:Opp | 01-12 Mo BIO DSD:Ro | 01-13 Di PA | 01-26 Mo BIO | 01-29 Do RM:Ro WB | 01-30 Fr RM:Opp DSD:Opp
02-02 Mo DSD:Ro | 02-09 Mo BIO | 02-10 Di PA | 02-19 Do RM:Ro | 02-20 Fr RM:Opp DSD:Opp | 02-23 Mo BIO DSD:Ro
03-09 Mo BIO | 03-10 Di PA | 03-12 Do RM:Ro | 03-13 Fr RM:Opp DSD:Opp | 03-16 Mo DSD:Ro | 03-23 Mo BIO | 03-30 Mo RM:Opp
04-01 Mi RM:Ro | 04-02 Do DSD:Opp | 04-07 Di PA DSD:Ro | 04-08 Mi BIO | 04-20 Mo GRÜN BIO | 04-23 Do RM:Ro SMH:Ro | 04-24 Fr RM:Opp DSD:Opp | 04-25 Sa DSD:Ro
05-04 Mo BIO | 05-05 Di PA | 05-11 Mo RM | 05-16 Sa DSD:Opp | 05-18 Mo BIO DSD:Ro | 05-28 Do GRÜN
06-01 Mo BIO | 06-02 Di PA RM:Ro | 06-05 Fr RM:Opp | 06-06 Sa DSD:Opp | 06-08 Mo BIO DSD:Ro | 06-15 Mo BIO | 06-22 Mo BIO | 06-25 Do RM:Ro | 06-26 Fr RM:Opp DSD:Opp | 06-29 Mo BIO DSD:Ro | 06-30 Di PA
07-06 Mo BIO | 07-13 Mo BIO | 07-16 Do RM:Ro | 07-17 Fr RM:Opp DSD:Opp | 07-20 Mo BIO DSD:Ro | 07-27 Mo BIO | 07-28 Di PA
08-03 Mo BIO | 08-06 Do RM:Ro | 08-07 Fr RM:Opp DSD:Opp | 08-08 Sa SMH:Ro | 08-10 Mo BIO DSD:Ro | 08-17 Mo BIO | 08-24 Mo BIO | 08-25 Di PA | 08-27 Do RM:Ro | 08-28 Fr RM:Opp DSD:Opp | 08-31 Mo BIO DSD:Ro
09-07 Mo BIO | 09-14 Mo BIO | 09-17 Do RM:Ro | 09-18 Fr RM:Opp DSD:Opp | 09-21 Mo BIO DSD:Ro | 09-22 Di PA | 09-30 Mi GRÜN
10-05 Mo BIO | 10-08 Do RM:Ro | 10-09 Fr RM:Opp DSD:Opp | 10-12 Mo DSD:Ro | 10-19 Mo BIO | 10-20 Di PA | 10-29 Do RM:Ro SMH | 10-30 Fr RM:Opp DSD:Opp
11-02 Mo BIO DSD:Ro | 11-11 Mi GRÜN | 11-16 Mo BIO | 11-17 Di PA | 11-19 Do RM:Ro | 11-20 Fr RM:Opp DSD:Opp | 11-23 Mo DSD:Ro | 11-30 Mo BIO
12-10 Do RM:Ro | 12-11 Fr RM:Opp DSD:Opp | 12-14 Mo BIO DSD:Ro | 12-15 Di PA | 12-28 Mo BIO | 12-31 Do RM:Ro
"""
NAMES = {'RM': 'Restmüll', 'BIO': 'Biomüll', 'DSD': 'Gelbe Tonne', 'PA': 'Altpapier', 'GRÜN': 'Grünschnitt',
         'SMH': 'Schadstoffmobil', 'WB': 'Weihnachtsbäume'}


def events(year=2026):
    ev = {'Ro': [], 'Opp': []}
    for item in TEXT.replace('\n', '|').split('|'):
        parts = item.split()
        if not parts:
            continue
        mm, dd = parts[0].split('-')
        day = datetime.date(year, int(mm), int(dd))
        if WD[day.weekday()] != parts[1]:
            raise SystemExit(f'rockenberg: {day} ist kein {parts[1]}')
        for code in parts[2:]:
            kind, _, where = code.partition(':')
            for ot in (where,) if where else ('Ro', 'Opp'):
                ev[ot].append((day, NAMES[kind]))
    return ev


def run(refresh=False):
    ev = events()
    common.write_output('rockenberg', 'Gemeinde Rockenberg', PAGE, [2026],
                        [('rockenberg', 'Rockenberg', None, ev['Ro']), ('oppershofen', 'Oppershofen', None, ev['Opp'])],
                        step_title='Ortsteil')
