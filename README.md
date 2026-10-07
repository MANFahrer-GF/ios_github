# Tonne & Torte 🗑️🎂

Müll- und Geburtstagskalender für iPhone und iPad mit Erinnerungen – damit der Gelbe Sack nie wieder stehen bleibt.

Das Repo enthält zwei Varianten mit derselben Logik und denselben Datenquellen:

| Ordner | Was | Für wen |
|---|---|---|
| [`web/`](web/) | **Web-App (PWA)** mit Push und Kalender-Abo, läuft auf jedem PHP-Webspace (IONOS) | ohne App Store, sofort nutzbar auf iPhone/iPad/Desktop |
| [`TonneUndTorte/`](TonneUndTorte/) | **Native iOS-App** (SwiftUI, SwiftData) | später, wenn mehr native Funktionen gewünscht sind |

Die Anleitung zur Web-App steht in [`web/README.md`](web/README.md). Der Rest dieser Seite beschreibt die iOS-App.

![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue) ![SwiftUI](https://img.shields.io/badge/SwiftUI-SwiftData-orange) ![Xcode 16](https://img.shields.io/badge/Xcode-16%2B-lightgrey)

## Was die App kann

- **Übersicht** – große Karte „Heute Abend rausstellen!“, die nächsten Abholungen und Geburtstage auf einen Blick.
- **Kalender** – Monatsansicht mit farbigen Punkten je Müllart und 🎂 für Geburtstage, Wischen zwischen Monaten.
- **Mehrere Standorte** – z. B. Gifhorn und Kuhlhausen, jeweils mit eigenen Müllarten; Filter in Übersicht und Kalender.
- **Echte Abfuhrtermine**
  - **Gifhorn, Steinstraße 1** – direkt aus dem AWIDO-Portal des Landkreises Gifhorn (JSON-Schnittstelle), wöchentlicher automatischer Abgleich.
  - **Kuhlhausen, Havelberger Str. 18 (Havelberg)** – „Sync zu Kalender“-Link der Abfall-App Landkreis Stendal (ICS, Bezirk 1465), ebenfalls automatisch aktualisiert.
  - Beide Kalender liegen zusätzlich als ICS im App-Bundle, damit die App auch ohne Netz sofort Termine hat.
- **Weitere Quellen** – AWIDO-Assistent für ~50 Entsorger (Ort → Straße → Hausnummer), beliebige ICS-Links als Abo, ICS-Dateien importieren, oder Rhythmus von Hand („alle 2 Wochen ab …“).
- **Feiertagsregelungen** – einzelne Termine verschieben oder ausfallen lassen.
- **Erinnerungen** – am Vorabend (Standard 19:00 Uhr) und/oder am Abholtag morgens; mehrere Tonnen an einem Tag werden zu einer Mitteilung zusammengefasst. Geburtstage am Tag selbst plus wählbar 1–14 Tage vorher.
- **Geburtstage** – mit oder ohne Geburtsjahr, Alter-Anzeige, Notizen für Geschenkideen.

## Projekt öffnen

1. `TonneUndTorte.xcodeproj` in Xcode 16 oder neuer öffnen.
2. Unter *Signing & Capabilities* dein Team auswählen (Bundle-ID `de.manfahrer.TonneUndTorte` ggf. anpassen).
3. Auf iPhone/iPad oder Simulator starten. Beim ersten Start fragt die App nach der Erlaubnis für Mitteilungen.

Das Projekt nutzt Xcodes synchronisierte Ordner: Jede Datei im Ordner `TonneUndTorte/` wird automatisch Teil des Targets, es gibt keine Dateiliste zu pflegen.

## Aufbau

```
TonneUndTorte/
├── TonneUndTorteApp.swift      App-Einstieg, SwiftData-Container, Notification-Delegate
├── ContentView.swift           Tabs + automatischer Abgleich beim Start
├── Models/
│   ├── Location.swift          Standort mit Datenquelle (AWIDO / ICS-Link / manuell)
│   ├── WasteType.swift         Müllart: Rhythmus, Einzeltermine, Ausnahmen
│   ├── Person.swift            Geburtstag
│   └── CalendarEvent.swift     Berechneter Termin (nicht gespeichert)
├── Services/
│   ├── EventEngine.swift       Terminberechnung (Rhythmus, Schaltjahr, Zeiträume)
│   ├── NotificationManager.swift  Planung der lokalen Mitteilungen (max. 60)
│   ├── AwidoClient.swift       AWIDO-Portal (awido.cubefour.de)
│   ├── ICSParser.swift         Minimaler iCalendar-Parser inkl. einfacher RRULE
│   ├── CalendarImporter.swift  Zuordnung Titel → Müllart, Abgleich, Datei-Import
│   ├── SeedData.swift          Standard-Standorte Gifhorn & Kuhlhausen
│   ├── ReminderSettings.swift  Einstellungen (UserDefaults)
│   └── WastePreset.swift       Vorlagen, Farben, Symbole
├── Views/                      SwiftUI-Oberfläche (Übersicht, Kalender, Müll, Geburtstage, Einstellungen)
└── Resources/                  Gebündelte Abfuhrkalender (ICS)
```

## Datenquellen

| Standort | Quelle | Aktualisierung |
|---|---|---|
| Gifhorn, Steinstraße | AWIDO `getData` (Kunde `gifhorn`, Straßen-OID `968d9cf6-…`) | automatisch alle 7 Tage, manuell per Button |
| Kuhlhausen | `https://landkreis-stendal.abfall-app.net/download?system=ical&period=2&district=1465…` | automatisch alle 7 Tage, manuell per Button |

Hinweis: Die Portale sind Dienste der jeweiligen Landkreise; Termine ohne Gewähr.

## Ideen für später

- Home-Screen-Widget (WidgetKit) mit der nächsten Abholung
- iCloud-Sync der Daten über CloudKit
- Kontakte-Import für Geburtstage
