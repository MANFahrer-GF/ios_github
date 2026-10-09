# Übergabe „Tonne & Torte“

Stand: 9. Oktober 2026. Repo `MANFahrer-GF/ios_github` (öffentlich), Standard-Branch **`main`** (seit 9. Okt.).
Der frühere Branch `claude/adoring-ride-nxgrwn` ist veraltet (Stand 936b145) und kann gelöscht werden, sobald sicher nichts mehr darauf verweist.

> **GitHub Pages veröffentlicht aus `main`, Ordner `/docs`** – die Datenschutz- und Support-Seite, die in App Store Connect
> eingetragen sind. Die Adressen sind unverändert (https://manfahrer-gf.github.io/ios_github/…).

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

**Stand 9. Okt. abends: alle 400 Kreise und kreisfreien Städte abgedeckt** (`cov.py -v` meldet 0 fehlend). In der App zeigt das **Mehr → Abdeckung**; „teilweise“ nennt dort die noch fehlenden Gemeinden. Für fehlende Orte gibt es ICS-/CSV-Import und den Knopf „PDF-Kalender schicken“ (Mail an thomas@kant.ovh).

| Neu am 9. Okt. | Weg |
|---|---|
| Konstanz | Müllmann-API (`portalsSuedwest/muellmann`, auch Stadt Karlsruhe), MZV Hegau + Tengen/Steißlingen/Eigeltingen (ICS), Volkertshausen (HTML), Gaienhofen/Öhningen/Büsingen (Jahresdaten) |
| Donnersbergkreis | Web-App Softwareentwicklung Roth (`portalsRP/donnersberg`, braucht `Accept: text/html`) |
| Amberg-Sulzbach | Portal Landratsamt (`portalsBayern/landkreis_as`, nur Restmüll/Papier) |
| Werra-Meißner | ZVA (`portalsSuedwest/zvawmk`), Sontra als Jahresdaten (ohne Gelbe Tonne) |
| Main-Taunus, Hochtaunus | Kelkheim, Flörsheim (Portale), Kriftel, Schwalbach, Wehrheim, Steinbach (ICS), Liederbach (Jahresdaten) |
| Minden-Lübbecke | Espelkamp (iKISS), Bad Oeynhausen (PreZero), Hille/Hüllhorst (ICS), Rahden/Stemwede (Jahresdaten) |
| Weimar | Straßentabelle, Termine berechnet (`portalsMitte/weimar`) – ohne Feiertags-/Jahreswechselverschiebung, App zeigt Hinweis |
| Ansbach (Stadt), Saale-Holzland, Mainhausen | Jahresdaten aus PDF |

**Jahresdaten (PDF-Orte) brauchen jährliche Pflege:** `tools/pdfkalender/README.md` (neue PDFs meist Nov.–Jan., ca. 5–7 h/Jahr). Derzeit nur 2026 enthalten – ab 1.1.2027 melden diese Orte „Kalender 2027 noch nicht eingepflegt“, bis die neuen Daten mit einem App-Update kommen.

**ICS-Links im Katalog** können `{%Y}` (Jahr), `#link=<Text>` (aktuellen Link auf der Gemeindeseite suchen) und `#ohne=<Text>|…` (Termine ausfiltern) enthalten. Der Live-Test `ICSURLProviderTests/testLiveAllDirectCatalogLinks` prüft alle direkten Links.

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

## 5a. Version 2.0.1 (Build 2) – bereit zum Test, noch nicht im App Store

QS am 9. Okt.: 330 Offline-Tests grün, alle Live-Tests (328) und Katalog-Sweep grün, App- und Watch-Build grün, zwei unabhängige Reviews (Claude + Codex) ohne offene Befunde. Wichtigste Korrekturen neben den neuen Orten:
- Abgleich: bereinigte ICS-Titel („Abholung: Biomüll“ → „Biomüll“) und aufgeteilte Sammeltermine führen bestehende Müllarten weiter (keine Doppelten); mehrere Titel auf einer Müllart werden vereinigt.
- Monatskalender zeigte nur 4 von 7 Wochentagsbuchstaben; Siri-Hinweis lud verzögert; viele Texte (Plural, Übersetzung, „Rückgängig“).
- Bei jedem Update Version erhöhen (alle 8 Stellen in project.pbxproj).

**Offen beim Nutzer:** in Xcode auf dem iPhone testen (Heidekreis/Soltau, Ansbach, Widgets – im Simulator ohne Signatur nur Platzhalter), CloudKit-Schema nach Production, dann App-Store-Update. Berechtigungsdialoge sind nur deutsch (InfoPlist-Übersetzung fehlt). Die alte Arbeitskopie in `~/Documents/ios_github` (iCloud) ist veraltet – in `~/Claude/tonne` arbeiten.

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
