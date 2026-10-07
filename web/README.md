# Tonne & Torte – Web-App (PWA)

Müll- und Geburtstagskalender für iPhone, iPad und Desktop – **ohne App Store**. Läuft auf jedem PHP-Webspace (z. B. IONOS), wird wie eine App auf den Home-Bildschirm gelegt und erinnert per **Push** und/oder **Kalender-Abo**.

## Funktionen

- Übersicht mit „Heute Abend rausstellen!“, nächste Abholungen, Geburtstage
- Monatskalender mit farbigen Punkten je Müllart
- Standorte **Gifhorn (Steinstraße 1)** und **Kuhlhausen (Havelberger Str. 18)** sind vorkonfiguriert:
  - Gifhorn lädt live aus dem AWIDO-Portal des Landkreises
  - Kuhlhausen lädt den ICS-Export der Abfall-App Landkreis Stendal
  - wöchentlicher automatischer Abgleich, manuell per Button
- Weitere Standorte per AWIDO-Assistent (~50 Entsorger), ICS-Link oder ICS-Datei; Rhythmus auch von Hand
- Termine verschieben / ausfallen lassen (Feiertage)
- Geburtstage mit Alter, Notizen, Vorab-Erinnerung
- **Push-Mitteilungen** (Web Push, VAPID) am Vorabend und/oder morgens, Geburtstage am Tag und x Tage vorher
- **Kalender-Abo** (ICS-Feed mit Alarmen) – funktioniert sofort, ganz ohne Installation
- Passwortschutz, Dark Mode, offline-fähige Oberfläche

## Voraussetzungen

- PHP 8.1 oder neuer mit `pdo_sqlite` (Standard bei IONOS), `curl`, `openssl`, `mbstring`
- HTTPS (für Push und Home-Bildschirm-Installation Pflicht; bei IONOS inklusive)
- Ein Cronjob oder ein externer Dienst, der alle 10 Minuten eine URL aufruft (nur für Push nötig)

## Installation auf IONOS (oder anderem Webspace)

1. **Lokal vorbereiten** (einmalig, auf deinem Rechner):
   ```bash
   cd web
   composer install --no-dev
   ```
   Dadurch wird der Ordner `vendor/` (Web-Push-Bibliothek) aktualisiert. Er ist bereits im Repo enthalten, dieser Schritt ist also optional.
2. **Hochladen** per SFTP/FTP den kompletten Ordner `web/` z. B. nach `/tonne/` auf dem Webspace.
3. **Document-Root**: Im IONOS-Kundencenter die Domain/Subdomain (z. B. `tonne.deine-domain.de`) auf `/tonne/public` zeigen lassen.
   Geht das nicht, Domain auf `/tonne` zeigen lassen – die mitgelieferte `.htaccess` leitet automatisch nach `public/` weiter.
4. **Schreibrechte**: Der Ordner `web/data/` muss für PHP beschreibbar sein (bei IONOS standardmäßig der Fall).
5. **Aufrufen**: `https://tonne.deine-domain.de/` – beim ersten Start legst du ein Passwort fest, danach sind Gifhorn und Kuhlhausen mit allen Terminen da.
6. **Cronjob** (für Push): In den Einstellungen der App steht die Cron-URL mit Token. Diese alle 10 Minuten aufrufen:
   - IONOS: Kundencenter → Hosting → Cronjobs → neue Aufgabe mit der URL, Intervall 10 Minuten, oder
   - kostenlos über https://cron-job.org (URL eintragen, alle 10 Minuten), oder
   - per SSH: `*/10 * * * * php /pfad/zu/tonne/bin/cron.php`

Optional: `config.example.php` nach `config.php` kopieren, um MySQL statt SQLite oder eine feste Basis-URL zu nutzen.

## Auf dem iPhone/iPad einrichten

**Push (wie eine echte App):**
1. Seite in Safari öffnen → Teilen → **„Zum Home-Bildschirm“**.
2. Die App vom Home-Bildschirm starten → Einstellungen → **„Auf diesem Gerät aktivieren“** → Mitteilungen erlauben.
3. „Test senden“ – die Mitteilung kommt in wenigen Sekunden (iOS 16.4 oder neuer).

**Kalender-Abo (ohne Installation):**
Einstellungen → Kalender-Abo → **„Im Kalender abonnieren“** (oder Link kopieren und unter iOS-Einstellungen → Kalender → Accounts → Account hinzufügen → Andere → Kalenderabo einfügen). Die Alarme (abends vorher, Geburtstage) stecken im Feed; iOS aktualisiert das Abo selbst.

Beides zusammen geht natürlich auch.

## Aufbau

```
web/
├── public/            Document-Root: index.php (PWA-Shell), api.php, feed.php, cron.php, sw.js, manifest, assets/
├── src/               PHP-Klassen (Api, Events, Importer, Awido, Ics, Feed, Reminders, Push, Db, Auth, Seed)
├── seed/              Gebündelte Abfuhrkalender (ICS) für den ersten Start
├── bin/cron.php       Cron per Kommandozeile
├── data/              SQLite-Datenbank (wird automatisch angelegt, per .htaccess geschützt)
├── composer.json      Abhängigkeit: minishlink/web-push
└── config.example.php optionale Konfiguration
```

Die Termin-Logik entspricht der iOS-App im Ordner `TonneUndTorte/` (gleiche Datenquellen, gleiche Erinnerungsregeln).

## Lokal testen

```bash
cd web && composer install && php -S 127.0.0.1:8088 -t public
```
Dann http://127.0.0.1:8088 öffnen. Push braucht HTTPS, der Rest läuft auch lokal.
