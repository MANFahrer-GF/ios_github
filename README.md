# Tonne & Torte 🗑️🎂

**Nie wieder den Gelben Sack verpassen. Nie wieder einen Geburtstag vergessen.**

Native iOS-App (iPhone & iPad) für Abfuhrtermine, Geburtstage und wiederkehrende Haushaltstermine – mit Erinnerungen, Widgets, Live-Aktivität, Siri und iCloud-Sync.

| Ordner | Inhalt |
|---|---|
| [`TonneUndTorte/`](TonneUndTorte/) | iOS-App (SwiftUI, SwiftData + CloudKit) |
| [`TonneWidget/`](TonneWidget/) | Widget-Erweiterung: Home-/Sperrbildschirm-Widgets und Live-Aktivität |
| [`TonneWatch/`](TonneWatch/), [`TonneWatchWidget/`](TonneWatchWidget/) | Apple-Watch-App mit „Erledigt“-Knopf und Komplikationen |
| [`Shared/`](Shared/) | Code für App **und** Widget: Snapshot-Speicher, App Intents, Live-Activity-Attribute |
| [`TonneCore/`](TonneCore/) | Swift-Package mit aller Logik und den Online-Anbietern – auf Linux getestet |
| [`Config/`](Config/) | Entitlements und Info.plists |
| [`web/`](web/) | Ältere Web-App (PWA mit Push) – weiterhin lauffähig, siehe `web/README.md` |

## Was die App kann

**Nichts verpassen**
- Mitteilung am Vorabend mit Knöpfen **„Erledigt – steht draußen“** und **„In 1 Stunde nochmal“**; ohne „Erledigt“ kommt eine zweite, zeitkritische Erinnerung
- Optional morgens am Abholtag
- **Live-Aktivität** „Tonne rausstellen“ auf Sperrbildschirm und Dynamic Island (startet, wenn die App am Vorabend geöffnet wird)
- **Widgets** klein/mittel/groß und Sperrbildschirm (rechteckig, rund, inline), Standort wählbar, „Erledigt“-Knopf direkt im Widget
- **Apple Watch**: eigene App (nächste Abholung mit „Erledigt“, weitere Tage, Geburtstage) und Komplikationen für alle Zifferblatt-Plätze; Daten kommen automatisch vom iPhone
- **Siri & Kurzbefehle**: „Wann kommt der Müll in Tonne & Torte?“, „Tonne steht draußen“
- Hinweis-Mitteilung, wenn der Entsorger Termine verschiebt (wird beim wöchentlichen Abgleich erkannt)
- Export in den Apple-Kalender (eigener Kalender mit Alarmen) oder als ICS-Datei

**Einfach**
- Einrichtung in drei Schritten: Standort erlauben oder Ort suchen → Straße wählen → Tonnen ankreuzen
- Katalog mit **159 Entsorgern** über die Plattformen AWIDO, AbfallPlus (neue und alte Schnittstelle), Jumomind/MyMüll, Abfallnavi und abfall-app.net; dazu beliebige ICS-Links und ICS-Dateien
- Mehrere Standorte (z. B. Zuhause und Ferienhaus) mit Filter in Übersicht und Kalender
- iCloud-Sync über CloudKit – kein Konto, kein Login
- Streak-Anzeige: Abholungen dieses Jahr und davon bestätigt

**Mehr als Müll**
- Geburtstage aus Kontakten importieren, runde Geburtstage hervorgehoben, Sternzeichen, Geschenkideen je Person, Glückwunsch per Nachricht
- Eigene wiederkehrende Termine mit Vorlagen (Hochzeitstag, TÜV, Rauchmelder, Reifenwechsel …)
- Abfall-ABC: „Pizzakarton“ eingeben, richtige Tonne sehen
- Feiertagsregelungen: Termine verschieben oder ausfallen lassen
- Dark Mode, Dynamic Type, Haptik

## Projekt öffnen und auf das Gerät bringen

1. `TonneUndTorte.xcodeproj` in Xcode 16 oder neuer öffnen.
2. Für **alle vier** Targets (TonneUndTorte, TonneWidget, TonneWatch, TonneWatchWidget) unter *Signing & Capabilities* dein Team wählen. Xcode legt App-Gruppe, iCloud-Container und Push-Berechtigung automatisch an (siehe `Config/*.entitlements`). Bundle-IDs bei Bedarf anpassen (`de.manfahrer.TonneUndTorte` und `…TonneUndTorte.TonneWidget`), dann auch in `Config/TonneUndTorte-Info.plist` (BGTaskScheduler-ID) und `TonneCore/Sources/TonneCore/WidgetSnapshot.swift` (App-Gruppe) nachziehen.
3. Auf iPhone/iPad starten. Für TestFlight: *Product → Archive* und über App Store Connect verteilen.

Beim ersten Start fragt die App nach dem Standort (optional) und schlägt Entsorger vor. Mitteilungen werden nach der Einrichtung angefragt.

## Architektur

```
TonneCore (Swift-Package, plattformunabhängig)
├── Schedule / Birthday / Recurrence     Terminberechnung inkl. Sommerzeit, Schaltjahr
├── ReminderPlanner                       Mitteilungsplan (rein funktional, getestet)
├── ICS                                   Parser (DATE, DATE-TIME, TZID, RRULE) + Feed-Generator mit Alarmen
├── WasteCategory / WasteABC / Palette    Zuordnung, Farben, Symbole, Abfall-ABC
├── WidgetSnapshot                        Datenstand für Widget, Live-Aktivität, Siri
└── Providers                             WasteProvider-Protokoll + AWIDO, AbfallPlus (GraphQL/Legacy),
                                          Jumomind, Abfallnavi, AbfallAppNet, ICS-URL, Katalog

App (SwiftData + CloudKit)                Location · WasteType · Person · CustomEvent
├── AppModel                              Datenzugriff, Abgleich, Erinnerungen, Snapshot, Statistik
├── NotificationManager                   Kategorien mit Aktionen, Delegate, Snooze
├── SyncService                           Zuordnung Quelle → Müllart, Diff für Verschiebungen
├── LiveActivityManager / CalendarExport / ContactsImport / RegionSuggest / BackgroundTasks
└── Views                                 Onboarding, Übersicht, Kalender, Müll (Assistent), Geburtstage, Mehr

Widget-Extension                          PickupWidget (konfigurierbar), PickupLiveActivity
Watch-App + Watch-Widget                  WatchContentView (3 Seiten), WatchPickupWidget (Komplikationen)
Shared                                    SnapshotStore (App-Gruppe), WatchSync (WatchConnectivity), Intents, Color+hex
```

## Tests

Der Kern lässt sich ohne Xcode testen (auch unter Linux):

```bash
cd TonneCore
swift test                    # Unit-Tests (Terminlogik, ICS, Planer, Katalog …)
TONNE_LIVE=1 swift test       # zusätzlich Live-Tests gegen die echten Portale
```

## Neue Entsorger hinzufügen

Die Plattform-Kennungen stehen in `TonneCore/Sources/TonneCore/Providers/Catalog.swift` (generiert aus den Quellen des Projekts [hacs_waste_collection_schedule](https://github.com/mampfes/hacs_waste_collection_schedule), MIT). Ein neuer Eintrag ist eine Zeile `CatalogEntry(kind:serviceKey:title:website:)`. Für eine neue Plattform wird `WasteProvider` implementiert (zwei Methoden: Auswahlschritte und Termine) und in `ProviderFactory` registriert.

## Geplant

- Haushalt mit Familie teilen (CloudKit Sharing) und „Wer ist dran?“
- Englische Oberfläche
- Weitere Plattformen (Abfall+ Apps von k4systems, AWBKoeln, Müllmax …)
