# Jahresdaten aus PDF-Abfallkalendern – Datenformat

Für Orte, die ihre Abfuhrtermine nur als PDF veröffentlichen, liest ein Skript die PDF einmal im Jahr aus.
Das Ergebnis liegt je Ort als `tools/pdfkalender/out/<key>.json`. `build_swift.py` macht daraus
`TonneCore/Sources/TonneCore/Providers/JahresdatenData.swift` (generiert, nicht von Hand ändern).
Die App liest diese Daten über `JahresdatenProvider` (ProviderKind `.jahresdaten`, serviceKey = `key`).

```json
{
  "key": "ansbach",
  "title": "Stadt Ansbach",
  "source": "https://www.p-42.net/cal/sansb2/index_str.php",
  "stand": "2026-10-09",
  "years": [2026],
  "groupTitle": null,
  "stepTitle": "Straße",
  "notice": null,
  "areas": [
    {"id": "markgrafenring", "title": "Markgrafenring", "group": null, "plan": "p1"}
  ],
  "plans": {
    "p1": [["2026-10-12", "Restmüll"], ["2026-10-19", "Altpapier", "verschoben wegen Feiertag"]]
  }
}
```

- `key`: Kleinbuchstaben, a–z, 0–9, `_`. Zugleich Dateiname und serviceKey.
- `source`: Seite oder PDF, aus der die Termine stammen (wird in der App als Quelle genannt).
- `stand`: Tag des Abrufs (ISO). `years`: Jahre, für die Termine enthalten sind.
- `areas`: Auswahl in der App. Gibt es genau einen Eintrag, entfällt die Auswahl.
  Mit `group` (z. B. Ort) wird zweistufig gewählt: erst `groupTitle`, dann `stepTitle`.
  `id` eindeutig je Datei und über die Jahre stabil (aus dem Namen gebildet, nicht laufende Nummer),
  damit gespeicherte Standorte nach der Jahrespflege weiter passen.
- `plans`: Termine je Plan; Areas mit gleichen Terminen teilen sich einen Plan.
  Eintrag `[Datum, Abfallart]` oder `[Datum, Abfallart, Notiz]`. Abfallart so benennen, dass
  `WasteCategory.classify` sie erkennt (Restmüll, Biomüll, Altpapier, Gelbe Tonne / Gelber Sack …).
  Notiz z. B. „Leerung am Feiertag oder einen Tag später“ für unsichere Feiertagstermine.
- `notice`: zusätzlicher Hinweis für die App, z. B. „Gelbe Tonne nicht enthalten (eigener Kalender)“.

Jährliche Pflege: siehe `README.md`.
