# Ohne Xcode-Gefummel: Xcode Cloud baut die App und liefert sie in TestFlight

Xcode Cloud ist Apples Bau-Dienst. Er holt den Code von GitHub, baut die App auf Apple-Rechnern, kümmert sich **selbst um Zertifikate und Signierung** und legt das Ergebnis direkt in TestFlight. Du musst dafür nichts in Xcode einstellen. Alles passiert im Browser auf den Apple-Webseiten, und auf dem iPhone brauchst du nur die App **TestFlight**.

Im Entwickler-Programm sind 25 Bau-Stunden pro Monat enthalten. Ein Build von Tonne & Torte dauert etwa 15 bis 25 Minuten, das reicht also für viele Updates.

Du brauchst: deinen Apple-Entwickler-Account, dein GitHub-Konto, dein iPhone.

---

## Schritt 1: Bundle-IDs prüfen (Developer-Portal)

Beim Signieren in Xcode hat Xcode die IDs vermutlich schon angelegt. Einmal nachsehen:

1. Browser: <https://developer.apple.com/account/resources/identifiers/list> und anmelden.
2. In der Liste **Identifiers** sollten diese vier App-IDs stehen:
   - `de.manfahrer.TonneUndTorte`
   - `de.manfahrer.TonneUndTorte.TonneWidget`
   - `de.manfahrer.TonneUndTorte.watchkitapp`
   - `de.manfahrer.TonneUndTorte.watchkitapp.TonneWatchWidget`
3. Oben rechts im Filter auf **App Groups** umstellen: dort muss `group.de.manfahrer.TonneUndTorte` stehen.
4. Filter auf **iCloud Containers**: dort muss `iCloud.de.manfahrer.TonneUndTorte` stehen.

**Fehlt etwas**, legst du es mit dem blauen **+** neben „Identifiers“ an:

- App-ID anlegen: *App IDs → App → Continue*. Description frei (z. B. „Tonne und Torte“), **Bundle ID: Explicit** und die ID exakt wie oben eintippen. Haken bei den Capabilities:
  - Haupt-App `de.manfahrer.TonneUndTorte`: **App Groups**, **iCloud** (Include CloudKit support), **Push Notifications**
  - die drei anderen: nur **App Groups**
  - Dann *Continue → Register*.
- App Group anlegen: *App Groups → Continue*, Description „Tonne und Torte“, Identifier `group.de.manfahrer.TonneUndTorte`, *Register*.
- iCloud Container anlegen: *iCloud Containers → Continue*, Description „Tonne und Torte“, Identifier `iCloud.de.manfahrer.TonneUndTorte`, *Register*.
- Danach bei jeder der vier App-IDs einmal anklicken, bei **App Groups** auf *Configure/Edit* und die Gruppe `group.de.manfahrer.TonneUndTorte` anhaken, *Save*. Bei der Haupt-App zusätzlich bei **iCloud** auf *Configure/Edit* und den Container `iCloud.de.manfahrer.TonneUndTorte` anhaken, *Save*.

---

## Schritt 2: App in App Store Connect anlegen

1. Browser: <https://appstoreconnect.apple.com> und anmelden.
2. **Apps** → oben links das blaue **+** → **Neue App**.
3. Ausfüllen:
   - Plattformen: **iOS** anhaken
   - Name: **Tonne & Torte**
   - Primäre Sprache: **Deutsch**
   - Bundle-ID: **de.manfahrer.TonneUndTorte** aus der Liste wählen
   - SKU: `tonneundtorte`
   - Benutzerzugriff: **Vollzugriff**
4. **Erstellen**.

Die App ist damit nur bei dir angelegt, nichts ist veröffentlicht. Alles Weitere (Screenshots, Beschreibung) brauchst du für TestFlight nicht.

---

## Schritt 3: Xcode Cloud einrichten

1. In App Store Connect bei deiner App auf den Reiter **Xcode Cloud** (oben, neben TestFlight).
2. **Get Started** / „Erste Schritte“.
3. **Quellcode verbinden**: *GitHub* auswählen. Apple leitet zu GitHub weiter. Dort die „Xcode Cloud“-App für dein Konto **MANFahrer-GF** installieren und bei „Repository access“ **Only select repositories → ios_github** wählen → *Install / Authorize*.
4. Zurück bei Apple: Repository **MANFahrer-GF/ios_github** auswählen.
5. Projekt wählen: **TonneUndTorte.xcodeproj**.
6. Schema wählen: **Tonne & Torte**. (Steht es nicht in der Liste, ist der Code noch nicht auf dem neuesten Stand: in GitHub muss die Datei `TonneUndTorte.xcodeproj/xcshareddata/xcschemes/Tonne & Torte.xcscheme` vorhanden sein.)
7. Apple legt einen Standard-Workflow an und zeigt ihn dir. Auf **Edit Workflow** / „Bearbeiten“ klicken:
   - **Start Conditions / Startbedingungen**: *Branch Changes*, Branch **claude/adoring-ride-nxgrwn** (oder `main`, falls du diesen angelegt hast).
   - **Actions / Aktionen**: nur **Archive – iOS** behalten. Bei „Deployment Preparation“ **TestFlight (Internal Testing Only)** wählen. Eine Aktion „Test“ oder „Build“ kannst du mit dem Minus entfernen.
   - **Post-Actions**: **+ → TestFlight Internal Testing** → bei „Groups“ deine Gruppe wählen. Gibt es noch keine Gruppe, erst Schritt 4 machen und dann hierher zurück.
   - **Save**.
8. Oben rechts **Start Build** / „Build starten“. Xcode Cloud holt jetzt den Code, erzeugt die Zertifikate selbst und baut. Fortschritt siehst du auf der Xcode-Cloud-Seite, ca. 15 bis 25 Minuten.

Ab jetzt läuft das automatisch: **Jeder Push auf den Branch löst einen neuen Build aus**, und die fertige Version landet in TestFlight. Die Build-Nummer vergibt Xcode Cloud selbst.

---

## Schritt 4: TestFlight auf dem iPhone

1. In App Store Connect bei der App auf den Reiter **TestFlight**.
2. Links unter **Interne Tests** auf **+** → Gruppenname z. B. „Familie“ → *Erstellen*. Haken bei „Builds automatisch verteilen“ lassen.
3. In der Gruppe auf **+** bei Tester → dich selbst (deine Apple-ID) auswählen → *Hinzufügen*. Weitere Personen müssen vorher unter *Benutzer und Zugriff* eingeladen sein.
4. Auf dem iPhone die App **TestFlight** aus dem App Store laden und mit derselben Apple-ID anmelden.
5. Sobald der Build fertig ist, bekommst du eine E-Mail und TestFlight zeigt **Tonne & Torte** mit **Installieren**. Fertig.

Bei jedem neuen Build meldet sich TestFlight mit „Update“. Die App läuft 90 Tage, danach einfach den nächsten Build installieren.

---

## Wenn der Build rot wird

1. App Store Connect → Xcode Cloud → den Build anklicken.
2. Links **Issues** / „Probleme“ zeigt die Fehlermeldungen mit Datei und Zeile. Davon einen Screenshot machen und mir schicken, ich behebe es und pushe. Der nächste Build startet dann von selbst.

Typische Meldungen:

- **„No profiles for … were found“ / Signing-Fehler**: In Schritt 1 fehlt eine App-ID, die App-Gruppe oder der iCloud-Container, oder bei einer App-ID ist eine Capability nicht angehakt.
- **„Scheme … not found“**: Code in GitHub ist älter als diese Anleitung, Branch prüfen.
- **„Missing Compliance“ in TestFlight**: Sollte nicht kommen, die Info.plist enthält bereits `ITSAppUsesNonExemptEncryption = false`. Falls doch: im Build auf „Verwalten“ → „Keine der Algorithmen“ wählen.

---

## Später, optional: iCloud-Sync zwischen iPhone und iPad

Damit die Daten über iCloud zwischen Geräten abgeglichen werden, muss das CloudKit-Schema einmal von der Entwicklungs- in die Produktions-Umgebung übernommen werden. Das Schema entsteht beim ersten Start einer Debug-Version aus Xcode auf einem Gerät. Ohne diesen Schritt läuft die App trotzdem, nur lokal auf jedem Gerät für sich.

Wenn du das möchtest: einmal die App aus Xcode auf dem iPhone starten (Anleitung `ANLEITUNG-XCODE-TESTFLIGHT.md`, Schritt 5), dann <https://icloud.developer.apple.com> → Container `iCloud.de.manfahrer.TonneUndTorte` → **Deploy Schema Changes…** → *Deploy*.
