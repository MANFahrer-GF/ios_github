# Übergabe „Tonne & Torte“

Stand: 9. Oktober 2026. Repo `MANFahrer-GF/ios_github` (öffentlich), Branch **`claude/adoring-ride-nxgrwn`**.
Das ist der einzige Branch und zugleich der Standard-Branch.

> **Nicht löschen oder umbenennen:** GitHub Pages veröffentlicht aus diesem Branch (Ordner `/docs`) die
> Datenschutz- und Support-Seite, die in App Store Connect eingetragen sind.

---

## 1. Projekt in Kürze

- Native App für iPhone, iPad und Apple Watch: Abfuhrtermine und Geburtstage mit Erinnerungen, Widgets, Live-Aktivität, Siri und iCloud-Sync.
- Entwickler ist Thomas Kant aus Gifhorn, Kontakt `thomas@kant.ovh`. Es ist ein Hobbyprojekt.
- Kommunikation mit dem Nutzer auf Deutsch, knapp und ohne Fachjargon.
- **Regeln des Nutzers:**
  - Nichts erfinden: Entsorger-Anbindungen kommen nur in den Katalog, wenn sie live echte Termine geliefert haben.
  - Vor dem Veröffentlichen testen.
  - „Familie teilen“ vorerst weglassen.
  - Passwörter und Tokens nie im Chat erfragen.

## 2. App Store

| | |
|---|---|
| App-ID | `6820155038` → https://apps.apple.com/de/app/id6820155038 |
| Preis | kostenlos, ohne In-App-Käufe, nur deutscher App Store |
| Status | eingereicht/veröffentlicht (9. Okt. 2026) |
| Datenschutz-URL | https://manfahrer-gf.github.io/ios_github/appstore/datenschutz.html |
| Support-URL | https://manfahrer-gf.github.io/ios_github/appstore/support.html |
| Texte & Antworten | `docs/appstore/APP-STORE-TEXTE.md` |
| Screenshots | `docs/appstore/screenshots/<Gerät>/` (iPhone 6,9/6,7/6,3/6,1″, iPad 13/12,9″, 4 Watch-Größen). Aus dem Code nachgebaut; Generator in `docs/appstore/screenshots/generator/` (`python3 gen.py && node render.js`, braucht Playwright) |
| Presse | Mail an iFun (`ifun.de@gmail.com`) ist verschickt |

**Noch offen beim Nutzer:** Im CloudKit-Container `iCloud.de.manfahrer.TonneUndTorte` einmal „Deploy Schema Changes“ nach Production ausführen. Ob das schon passiert ist, ist unbekannt. Ohne diesen Schritt funktioniert der iCloud-Sync in der App-Store-Version nicht.

## 3. Aufbau

- `TonneCore/`: Swift-Paket mit der ganzen Logik (Anbieter, Katalog, Erinnerungsplanung, CSV/ICS). Läuft auch unter Linux.
- `Shared/`: in alle vier Targets kompiliert (App, iOS-Widget, Watch-App, Watch-Widget). Darin `TonneDesign.swift`, `SnapshotStore.swift`, `SharedIntents.swift` und `WatchSync.swift`.
- `TonneUndTorte/`: die App (SwiftUI, SwiftData + CloudKit).
- `TonneWidget/` und `TonneWatchWidget/`: Widgets.
- `TonneWatch/`: Watch-App.
- Zielplattform iOS 17, Swift-5-Sprachmodus. Gebaut wird mit Xcode 27.
- CI `.github/workflows/ios-build.yml`: blockiert, weil das GitHub-Ausgabenlimit erreicht ist bzw. Zahlungen fehlgeschlagen sind. Lokal bauen.

### Tests

```bash
cd TonneCore
swift test                                                  # offline, alles grün (251 Tests, davon 153 live → übersprungen)
TONNE_LIVE=1 swift test --filter LiveProviderTests          # Live-Adressen bis zu echten Terminen
TONNE_LIVE=1 swift test --filter <Name>Tests                # Live-Tests einer Anbieter-Familie
TONNE_SWEEP=1 swift test --filter CatalogSweepTests         # jeden Katalogeintrag live prüfen (dauert)
```

### Katalog (welcher Entsorger für welchen Ort)

- Generiert werden `Providers/Catalog.swift` (Abschnitt GENERATED) und `Providers/CatalogRegions.swift`. **Diese beiden Dateien nicht von Hand ändern.**
- Der Generator liegt in `tools/catalog/`:
  ```bash
  python3 tools/catalog/gen_catalog.py > /tmp/gen.log 2>&1   # nie in head pipen
  python3 tools/catalog/cov.py -v                            # Abdeckung je Landkreis
  ```
- Neue Betreiber werden als JSON in `tools/catalog/data/catalog_additions/<ProviderDatei>.json` eingetragen:
  ```json
  [{"kind": "portalsNord", "key": "heidekreis", "title": "…", "website": "…", "places": ["Soltau", "…"], "districts": ["Landkreis Heidekreis"]}]
  ```
  `districts` muss exakt der Spalte `krs_name` in `tools/catalog/data/geo/gemeinden.csv` entsprechen. Der Generator übernimmt nur Dateien, zu denen eine Provider-Datei `Providers/<Name>.swift` existiert.
- Getestet am 9. Okt.: Der Generator erzeugt aus dem Repo heraus exakt den aktuellen Katalog.

## 4. Abdeckung

Von 400 Kreisen und kreisfreien Städten sind 388 voll abgedeckt, 7 teilweise und 5 fehlen (Stand 9. Okt. nach Heidekreis, Bamberg, Teltow-Fläming). In der App zeigt das der Bereich **Müll → Abdeckung** („Noch nicht dabei“). Für fehlende Orte gibt es Import per ICS-Link oder CSV mit Vorlage.

| Kreis | Status | Grund / nächster Schritt |
|---|---|---|
| Konstanz | fehlt | Müllmann-App hinter Cloudflare |
| Ansbach (Stadt) | fehlt | nur PDF je Straße |
| Donnersbergkreis | fehlt | nur eigene App ohne offene Schnittstelle |
| Weimar | fehlt | kein maschinenlesbarer Kalender gefunden |
| Saale-Holzland-Kreis | fehlt | nur PDF |
| Hochtaunus, Main-Taunus, Kreis Offenbach, Vogelsberg, Werra-Meißner, Minden-Lübbecke, Amberg-Sulzbach | teilweise | nur einzelne Gemeinden angebunden (`cov.py -v` listet welche) |

**Erledigt am 9. Okt. (vom Mac mit deutscher IP live geprüft):** Heidekreis (`portalsNord`/`heidekreis`, alle 23 Gemeinden), Bamberg-Stadt (`bamberg`) und SBAZV (`suedbrandenburg`: Teltow-Fläming komplett plus Nord-Dahme-Spreewald, das KAEV nicht bedient). Heinz Entsorgung (Freising) liefert von Deutschland aus wieder Termine. Die Sperren gelten nur für Rechenzentren außerhalb Deutschlands – Live-Tests dieser Portale also vom Mac oder einem deutschen Server laufen lassen.

Neu im Generator: `"onlyDistricts": true` in `catalog_additions` verhindert, dass ein Eintrag über gleichnamige Orte oder den Titel weiteren Kreisen zugeordnet wird (sonst landete SBAZV über „Schwerin“ in Mecklenburg und Bamberg-Stadt im Landkreis Bamberg).

## 5. Heidekreis (erledigt 9. Okt.)

Eingebaut in `NordPortalsProvider.swift` (Betreiber `heidekreis`), Tests in `HeidekreisTests.swift` mit echten API-Antworten.
Ablauf: Straßensuche (Text) → Straße (Untertitel „PLZ Ort“) → Hausnummer → Termine. Die API (`ahkwebapi.heidekreis.de`) braucht `Referer`/`Origin` von `ahkweb.heidekreis.de` und sperrt Rechenzentren außerhalb Deutschlands.

Eigenheiten der echten API:
- IDs kommen teils als Kommazahl (`QDisposalTypes`: `2.0`, Strauchschnitt-Tage: `idDisposalType: 13.0`) – werden zu „2“/„13“ normalisiert.
- Abfallart-Name aus `QDisposalDayIcons` („Bioenergietonne 60 L“ → „Bioenergietonne“). Gewerbe-Container heißen dort kryptisch („AHS RM 1100 L“); ist der Name keiner Tonnenart zuzuordnen, gilt der Name aus `QDisposalTypes` („Restabfall“).
- Live geprüft: Munster Wagnerstr. 10-18, Bad Fallingbostel Konrad-Zuse-Str. 4, Bispingen Lerchenweg 5.

**Offen beim Nutzer:** In Xcode auf dem iPhone mit einer echten Heidekreis-Adresse testen (z. B. Soltau). Erst danach App-Store-Update.

## 6. Zuletzt umgesetzt (zum Einordnen)

- **„Tonne wieder reinholen“:**
  - Erinnerung am Abholtag, Standard 17 Uhr, einstellbar. Gilt nur für Tonnen, nicht für Säcke oder Grünschnitt (`WasteReturn.isBin`).
  - Abhaken mit „Ist drin“ in Mitteilung, Widget und Übersicht.
  - Nach „Erledigt“ springen Widget, Übersicht, Watch und Siri zur nächsten Abholung. Ab 17 Uhr ist die heutige Abholung vorbei. Innerhalb von 15 Minuten lässt sich „Erledigt“ zurücknehmen (`PickupTiming`).
  - Fünf Runden Qualitätssicherung, zuletzt alles grün.
- **Abdeckung:** Ansicht „Noch nicht dabei / Verfügbar“ mit Teilabdeckung, CSV-Import/-Export samt Vorlage und ICS-Import.
- **Dutzende neue Entsorger** in den Provider-Familien `portals*`, `hausmuellInfo`, `wasteManagementServlet` und `awmMuenchen`.

## 7. Hinweise

- Die Live-Tests hängen an fremden Portalen. Schlägt einer fehl, zuerst im Browser prüfen, ob das Portal selbst geht.
- Pro Host höchstens etwa eine Anfrage pro Sekunde, keine Massenabfragen.
- Commit-Nachrichten auf Deutsch.
- Die Web-App unter `web/` ruht.
