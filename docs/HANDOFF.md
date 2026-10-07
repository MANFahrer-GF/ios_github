# Übergabe: Stand des Projekts „Tonne & Torte“

Stand: 7. Oktober 2026, Branch `claude/adoring-ride-nxgrwn`.

## Was das Projekt ist

Native iOS-App (iPhone, iPad, Apple Watch) für Abfuhrtermine und Geburtstage mit Erinnerungen, Widgets, Live-Aktivität, Siri und iCloud-Sync. Repo: `MANFahrer-GF/ios_github`. Die ältere Web-App unter `web/` ruht.

## Was fertig ist

- **App, Widgets, Watch** im Design „Klar“ (Apple-Widget-Stil): jede Tonne als eigene Zeile mit Farbpunkt, große runde Schrift, Farbschleier in der Tonnenfarbe. Entwurf: `docs/widget-design-klar.png`, Bausteine in `Shared/TonneDesign.swift` (Abschnitt „Klar“).
- **Widgets:** Müll (klein, mittel, groß, Sperrbildschirm), Geburtstag (klein, mittel, Sperrbildschirm), Live-Aktivität. „Erledigt“ per Knopf, erneutes Tippen nimmt zurück.
- **Watch-App** mit drei Seiten (Abholung mit Erledigt/Zurück, Danach, Geburtstage) und Komplikationen.
- **Erledigt zurücknehmen** in App, Widget, Live-Aktivität, Watch und Siri (`UndoPickupDoneIntent`).
- **Apple-Kalender:** Mehr → „Kalender automatisch aktuell halten“. Legt einen Kalender „Tonne & Torte“ bevorzugt in iCloud an und schreibt nach jedem Abgleich nur Änderungen.
- **Über-Seite:** Einstellungen → „Über Tonne & Torte“, „Gebaut von Thomas Kant – mit Herz aus Gifhorn“.
- **Kontakte-Import:** iOS-18-Teilfreigabe („Weitere Kontakte freigeben“), Suche, Aktualisieren bereits importierter Personen.
- **Entsorger:** 315 Katalogeinträge, alle im Live-Gesamttest geprüft. Plattformen: AWIDO, AbfallPlus (Widget und App), Jumomind/MyMüll, Abfallnavi, abfall-app.net, C-Trace, Müllmax, Gemos WasteBox (Ludwigslust-Parchim), AWSH (Herzogtum Lauenburg, Stormarn), Lobbe, Nerdbridge (Northeim), BSR Berlin, Köln, Leipzig, Hannover, Mein-Abfallkalender (geführter iCal-Link).
- **Ortssuche:** alle rund 10.900 Gemeinden plus Ortsteile von Ludwigslust-Parchim; Treffer zeigen die Entsorger des Landkreises.
- **Automatischer Xcode-Build:** `.github/workflows/ios-build.yml` baut bei jedem Push App, Widgets und Watch auf einem Mac (ohne Signatur) und führt die Kerntests aus.

## Tests

```bash
cd TonneCore
swift test                                           # Offline-Tests
TONNE_LIVE=1 swift test --filter LiveProviderTests   # 22 Adressen bis zu echten Terminen
TONNE_SWEEP=1 swift test --filter CatalogSweepTests  # jeder Katalogeintrag live
```

## Was noch offen ist

1. **TestFlight:** In Xcode „Integrate → Pull“, mit „Any iOS Device“ archivieren und hochladen. Die App muss in App Store Connect angelegt sein.
2. **iCloud-Schema:** Einmal auf icloud.developer.apple.com im Container `iCloud.de.manfahrer.TonneUndTorte` „Deploy Schema Changes“ ausführen, damit iPhone und iPad ihre Daten abgleichen. Geht nur mit dem Apple-Konto des Nutzers.
3. **Branch `main`:** Muss auf GitHub vom Nutzer angelegt werden, das Anlegen aus der Sitzung wurde blockiert.
4. **Familie teilen:** Auf Wunsch des Nutzers vorerst zurückgestellt.

## Wichtige Dateien

- `Shared/TonneDesign.swift`: gemeinsame Gestaltung für App, Widgets und Watch.
- `TonneWidget/PickupWidget.swift`, `TonneWidget/BirthdayWidget.swift`: Widgets.
- `TonneWatch/WatchContentView.swift`, `TonneWatchWidget/WatchPickupWidget.swift`: Watch.
- `TonneCore/Sources/TonneCore/Providers/`: ein Provider pro Plattform; `Catalog.swift` und `CatalogRegions.swift` sind generiert, die Suche steht in `CatalogSearch.swift`.
- `TonneUndTorte/App/AppModel.swift`: zentrale App-Logik.

## Stolpersteine

- **AbfallPlus-App:** Der Server liefert bei zu schnellen Anfragen Platzhalter („Leni (39)“) statt Terminen. Der Provider hält deshalb gut eine Sekunde Abstand zwischen Anfragen, ein Assistentenschritt dauert dort einige Sekunden.
- **abfall.io-Widgets:** Viele Landkreise sind auf die AbfallPlus-App umgezogen, die alten Widget-Schlüssel antworten mit 401. Der Gesamttest findet solche Fälle.
- **Katalog neu erzeugen:** Der Generator setzt Marker `GENERATED-START/END` in `Catalog.swift` und ist wiederholbar.
- **Push:** GitHub antwortete zeitweise mit „Internal Server Error“. Dann über die GitHub-API committen und den lokalen Branch auf `origin` zurücksetzen.

## Wie der Nutzer arbeitet

Thomas Kant, Hobby-Entwickler aus Gifhorn, arbeitet sonst mit phpVMS 7. Deutsch, schickt Screenshots, wünscht einfache Schritt-für-Schritt-Anleitungen und ein „geiles, frisches“ Design ohne Überschneidungen. Nie nach Passwörtern oder Tokens im Chat fragen.
