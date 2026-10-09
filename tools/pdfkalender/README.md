# Jahresdaten aus PDF-Abfallkalendern

Für Orte, die ihre Termine nur als PDF veröffentlichen, liest `extract.py` die PDF einmal im Jahr aus und
schreibt `out/<key>.json` (Format: `FORMAT.md`). `check.py` prüft alle Dateien. Daraus erzeugt
`build_swift.py` die Swift-Daten für den `JahresdatenProvider`.

## Einrichtung (einmalig)

- System-Python `/usr/bin/python3` (macOS, 3.9), immer mit `-I` aufrufen.
- PyMuPDF 1.26.5 im User-Verzeichnis: `/usr/bin/python3 -m pip install --user "pymupdf==1.26.5"`
  (`common.py` lädt es trotz `-I` ausdrücklich aus `site.getusersitepackages()`).
- Poppler (`pdftotext`, `pdftoppm`) über Homebrew: `brew install poppler` – gebraucht für Mainhausen
  (Straßenliste) und für die Sichtprüfung (`pdftoppm -r 80 -png …`).
- Downloads landen in `cache/` (nicht im Repo, siehe `.gitignore`). Höchstens 1 Anfrage/s je Host.

## Befehle

```sh
/usr/bin/python3 -I tools/pdfkalender/extract.py <key> [<key> …]   # oder: all
/usr/bin/python3 -I tools/pdfkalender/extract.py <key> --refresh   # Cache verwerfen (neue PDF)
/usr/bin/python3 -I tools/pdfkalender/check.py                     # muss „ok“ für alle Dateien melden
```

Jedes Skript bricht ab, statt zu raten: unbekannte Farben, nicht zugeordnete Zellinhalte, fehlende
Monate oder eine gescheiterte Wochentag-Probe (Tageszahl + Wochentag jeder Zelle gegen das Datum) führen
zum Abbruch. Bekannte Tippfehler im Original werden gemeldet und über die Nachbarzellen aufgelöst.

## Jährlicher Ablauf

Die neuen PDFs erscheinen meist Mitte November bis Januar. Je Ort:

1. Neue PDF-Adresse auf der Quellseite suchen und in `orte/<key>.py` eintragen (Jahr als Schlüssel; liegt
   das neue Jahr vor, das alte Jahr entfernen oder – solange es noch gilt – beide eintragen).
2. `extract.py <key> --refresh`, dann `check.py`.
3. Gegenprobe: 5–10 Termine (mindestens zwei Monate, verschiedene Abfallarten, ggf. zwei Bezirke) aus
   `out/<key>.json` gegen die gerenderte Seite vergleichen (`pdftoppm -r 80 -png -f 1 -l 1 cache/<datei>.pdf /tmp/x`).
   Bei Farb-Kalendern zuerst die Legende ansehen: neue Farbtöne müssen in die Palette.
4. `build_swift.py` laufen lassen, Swift-Tests, Commit (`Jahresdaten <Ort> <Jahr>`).

| key | Quelle (Seite → PDF) | Aufbau | Aufwand/Jahr |
|---|---|---|---|
| `ansbach` | p-42.net/cal/sansb2/index_str.php (Iframe der Stadt), je Straße eine PDF | Text-Kürzel R/GS/P/B; 397 Straßen → ~400 Anfragen, ~8 min | 30 min |
| `saaleholzland` | saaleholzlandkreis.de/de/abfallkalender.html → Broschüre (48 S.) | Regeln Wochentag + gerade/ungerade KW; Feiertagstabelle S. 23; Seitenzahlen in `orte/saaleholzland.py` prüfen | 1–2 h |
| `rahden` | rahden.de/wp-content/uploads/Abfall-Entsorgungskalender<Jahr>.pdf | Farbkästchen; Straßenverzeichnis S. 2; Sperrmüll-/Schadstofftermine im Infokasten | 30 min |
| `stemwede` | stemwede.de/bauen-wirtschaft-klimaschutz/abfall/ | Zellfarbe = Art, Text = Ortsteile | 20 min |
| `huellhorst` | serviceportal.huellhorst.de → Dienstleistung „Abfuhrkalender“ (PDF + ICS) | Farbkästchen; Gegenprobe gegen die ICS der Gemeinde läuft automatisch | 15 min |
| `mainhausen` | mainhausen.de/bauen-umwelt-abfall/abfallwirtschaft/abfallkalender | Balkenfarbe (aus dem Bild) + Bezirksnummern; Straßenliste eigene PDF | 30 min |
| `sontra` | sontra.de → „Bio-, Rest- und Papiermüll“ (verwaltungsportal.de) | Farbflächen + Bezirke; Straßenverzeichnis unten S. 1; ohne Gelbe Tonne | 30 min |
| `liederbach` | liederbach.eu → „Abfall & Entsorgung“ → „Liederbacher Müllkalender“ | Kürzel; „RM“ nach Kastenfarbe (14-tägl. / 1,1 m³) | 20 min |
| `gaienhofen` | gaienhofen.de/de/rathaus/entsorgung-umwelt/abfall | Text in der Zelle | 15 min |
| `oehningen` | oehningen.de/buergerservice/wohnen/abfall | Text in der Zelle | 15 min |
| `buesingen` | buesingen.de/de/Rathaus/Abfallentsorgung („Abholtermine“, 2 Halbjahres-PDFs) | Tage × Monate ohne Wochentag | 15 min |

Summe bei unverändertem Layout etwa 5–7 Stunden pro Jahr. Ändert ein Ort Layout oder Farben, kommen
1–2 Stunden für diesen Ort dazu (Palette/Spalten in `orte/<key>.py` anpassen).
Ohne Pflege laufen die Daten am 31.12. aus; `check.py` meldet dann „kein Termin ab heute“.
