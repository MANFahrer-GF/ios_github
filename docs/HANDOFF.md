# Übergabe: Stand des Projekts „Tonne & Torte“

Stand: 7. Oktober 2026, Branch `claude/adoring-ride-nxgrwn`, letzter Commit „Xcode Cloud: geteiltes Schema und Anleitung ohne Xcode-Einstellungen“.

## Was das Projekt ist

Native iOS-App (iPhone, iPad, Apple Watch) für Abfuhrtermine und Geburtstage mit Erinnerungen, Widgets, Live-Aktivität, Siri und iCloud-Sync. Repo: `MANFahrer-GF/ios_github`. Die ältere Web-App liegt weiterhin unter `web/`.

## Was fertig ist

- **Code komplett**: App, Widget-Erweiterung, Watch-App, Watch-Komplikationen, Swift-Package `TonneCore` mit 189 Entsorgern im Katalog (AWIDO, AbfallPlus neu/alt, Jumomind, Abfallnavi, abfall-app.net, C-Trace, Müllmax, Köln, Leipzig, Hannover, ICS-Link/Datei).
- **Tests**: `cd TonneCore && swift test` läuft unter Linux grün (16 Tests). Mit `TONNE_LIVE=1` zusätzlich 15 Live-Tests gegen die echten Portale, zuletzt alle grün.
- **Xcode-Projekt**: `TonneUndTorte.xcodeproj`, vier Targets, App-Target heißt „Tonne & Torte“. Geteiltes Schema `Tonne & Torte` für Xcode Cloud ist angelegt.
- **Beim Nutzer in Xcode**: Projekt ist geklont, Team „Thomas Kant“ ist gesetzt, der Build lief im letzten Screenshot fast durch (788/816). Die beiden Warnungen in `CTraceProvider.swift` sind behoben. Der Klon beim Nutzer ist aber älter als die letzten drei Commits (Umbenennung, Warnungs-Fix, Xcode-Cloud-Schema).
- **Anleitungen**: `docs/ANLEITUNG-XCODE-TESTFLIGHT.md` (klassisch mit Xcode) und `docs/ANLEITUNG-XCODE-CLOUD.md` (ohne Xcode-Einstellungen, Apple baut in der Cloud).

## Was als Nächstes ansteht

1. **App nach TestFlight bringen.** Empfohlener Weg: Xcode Cloud nach `docs/ANLEITUNG-XCODE-CLOUD.md`. Der Nutzer tut sich mit der Xcode-Oberfläche schwer, deshalb nur Webseiten-Schritte vorgeben und bei Fragen um Screenshots bitten.
2. **Bundle-IDs prüfen.** Im Developer-Portal müssen vorhanden sein: `de.manfahrer.TonneUndTorte` (App Groups, iCloud/CloudKit, Push), `…TonneUndTorte.TonneWidget`, `…TonneUndTorte.watchkitapp`, `…watchkitapp.TonneWatchWidget` (jeweils App Groups), App-Gruppe `group.de.manfahrer.TonneUndTorte`, iCloud-Container `iCloud.de.manfahrer.TonneUndTorte`. Xcode hat sie beim Setzen des Teams vermutlich schon angelegt.
3. **Branch `main`.** Existiert noch nicht. Das Anlegen über diese Sitzung wurde zweimal blockiert, der Nutzer hatte „ja anlegen“ gesagt. Der Nutzer kann `main` auf GitHub selbst anlegen (Branch-Menü, `main` eintippen, „Create branch from claude/adoring-ride-nxgrwn“). Danach wäre ein Pull Request von `claude/adoring-ride-nxgrwn` nach `main` sinnvoll.
4. **iCloud-Sync in TestFlight.** Das CloudKit-Schema entsteht erst beim ersten Debug-Start aus Xcode auf einem Gerät. Danach auf icloud.developer.apple.com „Deploy Schema Changes“ ausführen. Ohne diesen Schritt läuft die App lokal, aber ohne Abgleich zwischen Geräten.
5. **Offene Ideen** (nicht begonnen): Berlin (BSR) und München als Entsorger, Haushalt mit Familie teilen (CloudKit Sharing), Watch-App auf echter Uhr testen.

## Stolpersteine aus dieser Sitzung

- `git push` zum Repo bekam zuletzt mehrfach „Internal Server Error“ von GitHub, obwohl der Status „All Systems Operational“ meldete. Ausweg: Dateien über die GitHub-API (push_files) committen und den lokalen Branch danach auf `origin` zurücksetzen. Vorher prüfen, ob der normale Push wieder geht.
- Das Anlegen neuer Branches oder Force-Pushes wird von der Sitzungs-Richtlinie blockiert. Nicht wiederholen, sondern dem Nutzer den Weg über GitHub zeigen.
- Beim Bash-Werkzeug wird `\\` in Heredocs zu `\` verkürzt. Für Swift-Strings mit Backslash lieber ein kleines Python-Skript schreiben und ausführen.
- Die Swift-6-Toolchain für Linux liegt im Scratchpad der Sitzung und ist nach einem Neustart weg. Neu laden: swift.org, Toolchain 6.1.2 für Ubuntu, entpacken, `usr/bin` vorn in den PATH.

## Wichtige Dateien

- `TonneUndTorte/App/AppModel.swift`: zentrale Logik der App (Daten, Abgleich, Erinnerungen, Snapshot für Widgets und Watch).
- `TonneCore/Sources/TonneCore/Providers/`: ein Provider pro Plattform, `Catalog.swift` ist die Liste aller Entsorger.
- `Shared/`: Code, der in App, Widget und Watch gleichzeitig steckt (Snapshot, Intents, WatchSync).
- `Config/`: Entitlements und Info.plists aller vier Targets.
- `TonneCore/Tests/TonneCoreTests/LiveProviderTests.swift`: Live-Tests, nur mit `TONNE_LIVE=1`.

## Wie der Nutzer arbeitet

Hobby-Entwickler, arbeitet sonst mit phpVMS 7, Deutsch, schickt gern Screenshots. Will nichts im App Store veröffentlichen, nur TestFlight für sich und Familie. Wünscht einfache, schrittweise Anleitungen ohne Fachjargon. Nie nach Passwörtern oder Tokens im Chat fragen, dafür Umgebungsvariablen in den Sitzungs-Einstellungen vorschlagen.
