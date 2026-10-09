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

Von 400 Kreisen und kreisfreien Städten sind 385 voll abgedeckt, 7 teilweise und 8 fehlen. In der App zeigt das der Bereich **Müll → Abdeckung** („Noch nicht dabei“). Für fehlende Orte gibt es Import per ICS-Link oder CSV mit Vorlage.

| Kreis | Status | Grund / nächster Schritt |
|---|---|---|
| **Heidekreis** (NI) | fehlt | **Geoblock**, siehe Abschnitt 5. Anbindung als Patch fertig. |
| **Bamberg (Stadt)** | fehlt | Anbieter ist gebaut (`wasteManagementServlet`, Schlüssel `bamberg`, `ebbweb.stadt.bamberg.de`), aber vom Cloud-Server nicht erreichbar → **von deutschem Server live testen**, dann Katalogeintrag |
| **Teltow-Fläming** | fehlt | Ebenso: `wasteManagementServlet`, Schlüssel `suedbrandenburg` (SBAZV, `fahrzeuge.sbazv.de`) → **live testen** |
| Konstanz | fehlt | Müllmann-App hinter Cloudflare |
| Ansbach (Stadt) | fehlt | nur PDF je Straße |
| Donnersbergkreis | fehlt | nur eigene App ohne offene Schnittstelle |
| Weimar | fehlt | kein maschinenlesbarer Kalender gefunden |
| Saale-Holzland-Kreis | fehlt | nur PDF |
| Hochtaunus, Main-Taunus, Kreis Offenbach, Vogelsberg, Werra-Meißner, Minden-Lübbecke, Amberg-Sulzbach | teilweise | nur einzelne Gemeinden angebunden (`cov.py -v` listet welche) |

Ein ähnlicher Fall ist **Heinz Entsorgung (LK Freising, `portalsBayern`/`heinz`)**. Er ist im Katalog und wurde früher live geprüft, setzte aber zuletzt die Verbindung vom Cloud-Server zurück. Wenn möglich, von Deutschland aus nochmal prüfen.

## 5. Aktuelle Aufgabe: Heidekreis

**Befund:**
- `www.ahk-heidekreis.de` ist erreichbar.
- Die Termine liefert das Portal **ahkweb.heidekreis.de** mit der API **ahkwebapi.heidekreis.de**. Beide brechen Verbindungen vom Cloud-Server sofort ab („Connection reset by peer“).
- Vom iPhone des Nutzers aus lädt `https://ahkweb.heidekreis.de/home`, wenn auch langsam. Das spricht für einen Geoblock bzw. eine Sperre für Rechenzentren und nicht für eine Störung.

**API** (Bauplan aus Home-Assistant `waste_collection_schedule`, Datei `source/ahk_heidekreis_de.py`):
- Header immer mitsenden: `Referer: https://ahkweb.heidekreis.de/` und `Origin: https://ahkweb.heidekreis.de`
- Straßensuche: `GET /api/QMasterData/QStreetByPartialName?PartialName=<Text>`
  → `[{arStrasse, strassenname, plz, ort, ortOrtsteil}]`
- Hausnummern: `POST /api/QMasterData/QHouseNrEkal` mit JSON-Body `[<arStrasse>]`
  → `[{arObjekt, hausNrHausNrZ}]`
- Abfuhrtage: `GET /api/QDisposalCalendar/QDisposaldays?idObject=<arObjekt>&from=MM/dd/yyyy&to=MM/dd/yyyy`
  → `[{date: "2026-10-12T00:00:00", idIcon, idDisposalType}]`
- Namen der Abfallarten:
  - `GET /api/QDisposalCalendar/QDisposalDayIcons?idObject=…&from=…&to=…` → `[{id, description}]`. `description` ist zum Beispiel „Restabfalltonne 120 L“ und wird über `idIcon` zugeordnet.
  - Rückfall: `GET /api/QDisposalCalendar/QDisposalTypes` → `[{id, name}]`, zugeordnet über `idDisposalType`.
- Testadressen:
  - Munster, Wagnerstr. 10-18 (PLZ 29633)
  - Bad Fallingbostel, Konrad-Zuse-Str. 4 (PLZ 29683)

**Stand des Codes:** Der Patch `docs/handoff/heidekreis-wip.patch` ist **noch nie kompiliert worden**.
- In `NordPortalsProvider.swift` kommt der Betreiber `heidekreis` dazu. Ablauf: Straßensuche (Text) → Straße (Liste mit Untertitel „PLZ Ort“) → Hausnummer → Termine.
- Hilfsfunktionen: `ahkStreets`, `ahkHouseNumbers` und `ahkPickups`. Die Behältergröße wird aus dem Namen entfernt.
- Label: „Munster, Wagnerstr. 10-18“.
- Dazu `Tests/TonneCoreTests/HeidekreisTests.swift`:
  - Parser-Tests
  - kompletter Ablauf gegen einen URLProtocol-Stub (prüft URLs, Header und POST-Body)
  - Live-Test `testLiveHeidekreis` (nur mit `TONNE_LIVE=1`)

**Nächste Schritte (auf einem Rechner mit deutscher IP):**
1. Erst die API roh prüfen. So sieht man die echten Feldnamen und Typen:
   ```bash
   H=(-H 'Referer: https://ahkweb.heidekreis.de/' -H 'Origin: https://ahkweb.heidekreis.de' -H 'Accept: application/json')
   curl -s "${H[@]}" 'https://ahkwebapi.heidekreis.de/api/QMasterData/QStreetByPartialName?PartialName=Wagnerstr' | head -c 600
   curl -s "${H[@]}" -H 'Content-Type: application/json' -d '[<arStrasse>]' 'https://ahkwebapi.heidekreis.de/api/QMasterData/QHouseNrEkal' | head -c 600
   curl -s "${H[@]}" 'https://ahkwebapi.heidekreis.de/api/QDisposalCalendar/QDisposaldays?idObject=<arObjekt>&from=10%2F01%2F2026&to=12%2F31%2F2026' | head -c 600
   curl -s "${H[@]}" 'https://ahkwebapi.heidekreis.de/api/QDisposalCalendar/QDisposalDayIcons?idObject=<arObjekt>&from=10%2F01%2F2026&to=12%2F31%2F2026'
   curl -s "${H[@]}" 'https://ahkwebapi.heidekreis.de/api/QDisposalCalendar/QDisposalTypes'
   ```
2. Patch anwenden, bauen und testen:
   ```bash
   git apply docs/handoff/heidekreis-wip.patch
   cd TonneCore && swift build && swift test --filter HeidekreisTests
   TONNE_LIVE=1 swift test --filter HeidekreisTests/testLiveHeidekreis
   ```
   Weichen die echten Antworten von den Annahmen ab (Feldnamen, Datumsformat, Zahl oder Text), müssen Parser und Testdaten angepasst werden. Am besten echte Antworten als Testdaten übernehmen.
3. Ortsliste der 23 Gemeinden des Heidekreises (`gemeinden.csv`):
   Ahlden (Aller), Bad Fallingbostel, Bispingen, Buchholz (Aller), Böhme, Eickeloh, Essel, Frankenfeld, Gilten, Grethem, Hademstorf, Hodenhagen, Häuslingen, Lindwedel, Munster, Neuenkirchen, Osterheide, Rethem (Aller), Schneverdingen, Schwarmstedt, Soltau, Walsrode, Wietzendorf.
   Prüfen, ob alle über die Straßensuche erreichbar sind. Dann `tools/catalog/data/catalog_additions/NordPortalsProvider.json` anlegen bzw. ergänzen (kind `portalsNord`, key `heidekreis`, districts `["Landkreis Heidekreis"]`), den Generator laufen lassen und `cov.py -v` prüfen.
4. `swift test` komplett grün, dann committen und pushen. Der Nutzer testet anschließend in Xcode auf dem iPhone mit einer echten Heidekreis-Adresse (z. B. Soltau). **Erst danach** kommt ein App-Store-Update.
5. Dasselbe für Bamberg (`bamberg`) und Teltow-Fläming (`suedbrandenburg`): live testen, Katalogeintrag anlegen.

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
