# Von GitHub bis TestFlight – Schritt für Schritt

Diese Anleitung führt vom leeren Mac bis zur App auf deinem iPhone und in TestFlight. Du brauchst: einen Mac mit macOS 14 oder neuer, deine Apple-ID mit Entwickler-Account, dein iPhone mit Kabel oder im selben WLAN.

## 1. Xcode installieren

1. Mac App Store öffnen, nach **Xcode** suchen, laden (ca. 10 GB, dauert).
2. Xcode einmal starten. Beim ersten Start „Install additional components“ bestätigen.
3. Xcode → Settings (⌘,) → **Accounts** → „+“ → Apple ID → mit deiner Entwickler-Apple-ID anmelden. Danach erscheint dein Team in der Liste.

## 2. Repo klonen (ohne Terminal)

1. Xcode starten. Im Startfenster **„Clone Git Repository…“** wählen (oder Menü *Source Control → Clone…*).
2. Oben die Adresse eintragen: `https://github.com/MANFahrer-GF/ios_github.git` → **Clone**.
3. Xcode fragt nach GitHub-Zugang: mit deinem GitHub-Konto anmelden (Xcode → Settings → Accounts → „+“ → GitHub, dort ein Personal Access Token hinterlegen, das du auf github.com unter *Settings → Developer settings → Personal access tokens* erzeugst, Berechtigung „repo“).
4. Speicherort wählen, z. B. `Dokumente/TonneUndTorte`. Xcode öffnet das Projekt danach automatisch.
5. Branch wechseln: Links im Navigator auf das Symbol **Source Control** (Verzweigungs-Icon, zweites von links) klicken → *Branches* aufklappen → **origin/claude/adoring-ride-nxgrwn** → Rechtsklick → **Switch to „claude/adoring-ride-nxgrwn“**. (Falls du den Branch bereits als `main` angelegt hast, bleibt `main`.)

Alternative mit Terminal:

```bash
cd ~/Documents
git clone https://github.com/MANFahrer-GF/ios_github.git TonneUndTorte
cd TonneUndTorte
git checkout claude/adoring-ride-nxgrwn
open TonneUndTorte.xcodeproj
```

## 3. Projekt in Xcode verstehen

Links im Navigator siehst du:

- **Tonne & Torte** (Ordner TonneUndTorte) – die iPhone/iPad-App
- **TonneWidget** – Widgets und Live-Aktivität
- **TonneWatch** / **TonneWatchWidget** – Apple-Watch-App und Komplikationen
- **Shared** – Code für alle
- **Config** – Entitlements und Info.plists
- **Packages → TonneCore** – die Logik (wird beim ersten Öffnen aufgelöst, kurz warten)

Oben in der Leiste wählst du das **Schema** (links, „Tonne & Torte“) und das **Zielgerät** (rechts daneben).

## 4. Signieren (einmalig)

1. Ganz oben im Navigator den blauen Projekteintrag **TonneUndTorte** anklicken.
2. In der Mitte unter **TARGETS** nacheinander jedes der vier Targets (Tonne & Torte, TonneWidget, TonneWatch, TonneWatchWidget) wählen und den Reiter **Signing & Capabilities** öffnen.
3. Bei jedem Target: **Automatically manage signing** anhaken, bei **Team** dein Team wählen.
4. Xcode registriert jetzt Bundle-IDs, App-Gruppe, iCloud-Container und Push im Developer-Portal. Rote Meldungen → **Try Again**. Das kann zwei, drei Anläufe brauchen, ist normal.
5. Wenn eine Bundle-ID schon vergeben ist (unwahrscheinlich), unter **Bundle Identifier** eine eigene wählen, z. B. `de.deinname.TonneUndTorte`, und die Erweiterungen entsprechend anpassen (`…TonneUndTorte.TonneWidget`, `…TonneUndTorte.watchkitapp`, `…watchkitapp.TonneWatchWidget`). Dann auch in `Config/TonneUndTorte-Info.plist` (BGTaskScheduler-ID, URL-Schema) und `TonneCore/Sources/TonneCore/WidgetSnapshot.swift` (App-Gruppe `group.…`) nachziehen.

## 5. Auf dem iPhone starten

1. iPhone per Kabel anschließen, „Diesem Computer vertrauen“ bestätigen.
2. Auf dem iPhone: *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* einschalten (iPhone startet neu).
3. In Xcode oben als Zielgerät dein iPhone wählen, Schema **Tonne & Torte**.
4. **▶︎ Run** (⌘R). Beim ersten Mal baut Xcode ein paar Minuten.
5. Auf dem iPhone: *Einstellungen → Allgemein → VPN & Geräteverwaltung* → deinem Entwicklerprofil vertrauen. Dann die App vom Home-Bildschirm starten.
6. Für die Watch-App: Schema **TonneWatch**, Ziel „Apple Watch via iPhone“, ▶︎ Run. Oder einfach warten: Nach der Installation der iPhone-App erscheint die Watch-App auf der Uhr unter „Verfügbare Apps“.

Baut Xcode nicht und zeigt rote Fehler: Reiter **Issue Navigator** (⚠️-Symbol links) öffnen, Fehler kopieren und mir schicken.

## 6. iCloud-Schema für TestFlight freischalten

TestFlight nutzt die Produktionsumgebung von CloudKit. Nach dem ersten Lauf auf dem Gerät:

1. [icloud.developer.apple.com](https://icloud.developer.apple.com) öffnen, Container **iCloud.de.manfahrer.TonneUndTorte** wählen.
2. Links **Schema** → unten **Deploy Schema Changes…** → bestätigen.

Ohne diesen Schritt synchronisiert die TestFlight-Version nicht.

## 7. App in App Store Connect anlegen

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → „+“ → **Neue App**.
2. Plattform iOS, Name „Tonne & Torte“, Primärsprache Deutsch, Bundle-ID `de.manfahrer.TonneUndTorte` (aus der Liste), SKU z. B. `tonneundtorte`.

## 8. Archivieren und hochladen

1. In Xcode oben als Zielgerät **Any iOS Device (arm64)** wählen.
2. Menü **Product → Archive**. Nach dem Build öffnet sich der **Organizer**.
3. **Distribute App → App Store Connect → Upload**, alle Dialoge mit Standardwerten bestätigen (Xcode signiert automatisch).
4. Vor jedem weiteren Upload die Build-Nummer erhöhen: Projekt → jedes Target → Reiter **General** → **Build** (z. B. 2). Alle vier Targets müssen dieselbe Nummer haben.

## 9. TestFlight

1. App Store Connect → deine App → Reiter **TestFlight**. Der Build erscheint nach einigen Minuten („Processing“ abwarten).
2. **Interne Tests**: Gruppe „App Store Connect Users“ → dich selbst hinzufügen. Sofort verfügbar.
3. **Externe Tests** (Familie, Freunde): neue Gruppe anlegen, Build hinzufügen, kurze Testbeschreibung eintragen, „Zur Prüfung einreichen“. Apple prüft den ersten Build, meist innerhalb eines Tages. Danach Tester per E-Mail oder öffentlichem Link einladen.
4. Auf dem iPhone die App **TestFlight** aus dem App Store laden, Einladung annehmen, installieren. Updates kommen dann automatisch über TestFlight.

## Typische Stolperstellen

- **„Signing for TonneWatch requires a development team“** → Schritt 4 für alle vier Targets wiederholen.
- **„No such module TonneCore“** → *File → Packages → Resolve Package Versions*, dann *Product → Clean Build Folder* (⇧⌘K) und neu bauen.
- **„Untrusted Developer“ auf dem iPhone** → Schritt 5, Punkt 5.
- **Mitteilungen kommen nicht** → in der App unter *Mehr → Einstellungen* prüfen, ob Mitteilungen erlaubt sind; Testmitteilung senden.
- **Push/Live-Aktivität auf dem Simulator** → nur eingeschränkt, immer auf dem echten Gerät testen.
