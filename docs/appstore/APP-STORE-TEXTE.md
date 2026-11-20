# App Store Connect – Texte und Antworten für „Tonne & Torte“

Alles zum Hineinkopieren.

---

## 1. Version → Deutsch

### Beschreibung (Pflicht)

```
Nie wieder die Tonne vergessen – und keinen Geburtstag mehr verpassen.

Tonne & Torte holt die Abfuhrtermine direkt vom Portal deines Entsorgers und erinnert dich am Vorabend: „Gelber Sack und Restmüll – heute Abend rausstellen.“ Ein Tipp auf „Erledigt“, und die Sache ist abgehakt. Am Abholtag erinnert dich die App, die Tonnen wieder reinzuholen – Gelbe Säcke und Grünschnitt lässt sie dabei außen vor.

ABFUHRTERMINE FÜR FAST GANZ DEUTSCHLAND
• Über 380 Landkreise und kreisfreie Städte – von Hamburg bis München, von Aachen bis Görlitz
• Einfach Ort oder Landkreis suchen oder den Standort verwenden
• Termine werden wöchentlich automatisch abgeglichen; verschobene Termine meldet die App
• Dein Ort ist noch nicht dabei? Termine per ICS-Link, ICS- oder CSV-Datei laden (Vorlage für Excel und Numbers inklusive)
• Mehrere Standorte, z. B. Zuhause und Ferienwohnung

ERINNERUNGEN, DIE PASSEN
• Am Vorabend, zweite Erinnerung falls nicht erledigt, auf Wunsch morgens am Abholtag
• „Tonne wieder reinholen“ am Abholtag – nur für Tonnen, nicht für Säcke
• Live-Aktivität auf dem Sperrbildschirm und in der Dynamic Island
• Widgets für Home- und Sperrbildschirm mit „Erledigt“-Knopf
• Apple Watch mit App und Komplikationen
• Siri und Kurzbefehle: „Wann kommt der Müll in Tonne und Torte?“

GEBURTSTAGE UND EIGENE TERMINE
• Geburtstage aus den Kontakten übernehmen – nur die, die du auswählst
• Erinnerung am Tag und auf Wunsch einige Tage vorher, mit Alter und runden Geburtstagen
• Geschenkideen notieren, Liste als CSV oder PDF exportieren
• Eigene wiederkehrende Termine

CLEAN. OHNE MIST.
Keine Werbung, kein Tracking, kein Konto. Deine Daten bleiben auf deinen Geräten und in deiner eigenen iCloud.

Die Termine stammen von den Portalen der Entsorger. Alle Angaben ohne Gewähr – im Zweifel gilt der Abfuhrkalender deines Entsorgers.
```

Geändert am 14.11.2026 (in 2.0.11 während „Warten auf Prüfung“ gesichert): Das Zitat am Vorabend ist jetzt der echte Mitteilungstext (`ReminderPlanner.eveningText`, Titel „Morgen wird abgeholt“), und der Siri-Satz enthält den App-Namen, ohne den Siri ihn nicht erkennt (`ShortcutsProvider.swift`). Beide Sätze bei jeder neuen Version so lassen.

### Neu in Version 2.1.1 (Build 19, eingereicht und freigegeben 20.11.2026; Apple lehnt Emojis in „Neues in dieser Version“ ab – „ungültiges Zeichen“)

```
Ein Wunsch aus der Community
Kalender ohne Emojis: Unter Mehr → Kalender-Abgleich lassen sich die Emojis in den Kalendereinträgen abschalten. Dann steht dort nur „Restmüll“, ohne Symbol davor.

Zwei Standorte
„Erledigt“ gilt jetzt nur für den Standort, den du gerade siehst – in der gefilterten Übersicht und im Widget mit Standort. Der andere Standort behält seine Erinnerung.

Verschobene Termine bleiben
Einen Termin wegen eines Feiertags verschoben oder selbst eingetragen? Er bleibt jetzt auch nach dem Abgleich mit dem Entsorger stehen.

Außerdem
• Die Schriftwahl unter Mehr → Schrift wirkt sofort, ohne die App neu zu starten
• Auf Reisen in eine andere Zeitzone stehen die Termine weiter am richtigen Tag
• Rhythmus nachträglich einstellen erzeugt sofort die Termine
• Eine getippte Geschenkidee geht beim Sichern nicht mehr verloren
• „Zurück“ beim Einrichten funktioniert wieder in jedem Schritt
• Der Standortfilter hängt nach dem Löschen eines Standorts nicht mehr fest
• Die Live-Aktivität achtet auf ausgeschaltete Erinnerungen
• Die englische Oberfläche ist vollständig übersetzt
• Saarbrücken: Die Suche führt direkt zum ZKE
```

Werbetext 2.1.1 (143 Zeichen): „Neu: Kalender ohne Emojis und „Erledigt“ je Standort. Über 800 Entsorger geprüft, Erinnerung am Vorabend, Geburtstage gleich mit. Ohne Werbung.“

### Neu in Version 2.1.0 (Build 17, hochgeladen 19.11.2026)

```
Ihr habt es euch gewünscht
Die zwei größten Neuerungen kamen aus euren Mails. Danke dafür!

Leerungs-Statistik
Wie oft war welche Tonne draußen, und wie viele Leerungen sind noch frei? „Erledigt“ zählt als Leerung, vergessene Termine trägst du mit „Raus“ oder „Nicht raus“ nach. Trag ein, wie viele Leerungen deine Gebühr enthält, etwa 12 im Jahr – dann steht bei jedem Abholtermin „noch 10 frei“. Du findest es in jeder Müllart unter „Leerungen & Kontingent“.
• Prognose bis zum Jahresende und Vergleich mit dem Vorjahr bis zum gleichen Tag
• Zählung ab eigenem Starttag (z. B. ab Einzug), Preis je Zusatzleerung, Export als CSV
• „Kein Kontingent“ blendet Müllarten wie das Schadstoffmobil aus der Statistik aus

Schrift nach Wahl
Abgerundet, SF Pro oder Serif – in der ganzen App und in den Widgets. Bei sehr großer Textgröße werden lange Wörter sauber getrennt.

Wecker am Vorabend (ab iOS 26)
Auf Wunsch klingelt am Vorabend ein Wecker – auch wenn das iPhone stumm ist oder ein Fokus läuft. Standard aus, einschalten unter Mehr → Einstellungen → Wecker. Er klingelt nur, wenn etwas rausgestellt werden muss, und fällt nach „Erledigt“ weg. Braucht iOS 26 und deine Erlaubnis; gilt nur auf diesem iPhone.

Außerdem
• Riedstadt und Trebur (Kreis Groß-Gerau): Die App fragt den Ortsteil ab und findet die Termine direkt
• Neu: Stadt Aschaffenburg und der digitale Abfallkalender der Stadt Bühl
• Weitere Orte mit den richtigen Straßen und dem richtigen Entsorger
• Beim Einrichten erkennt die App Ortsnamen mit Zusätzen wie „an der“ oder „St.“ und den Ortsteil; ist es nicht eindeutig, zeigt sie die Auswahl
• Zuverlässigerer Start, wenn iOS die App im Hintergrund weckt
• Vor dem Senden eines Absturzberichts schaut die App, ob es schon ein Update gibt
• Liefert ein Portal nur wenige Wochen voraus, gleicht die App alle zwei Tage ab
• Beim Umzug bleiben abgehakte Leerungen in der Statistik erhalten
• Hilfe und Kontakt unter „Mehr“ führen auf die neue Webseite tonne.kant.ovh
```

### Neu in dieser Version – 2.0.11 (eingereicht 14.11.2026, Build 15)

```
Ortsteile finden
Die Suche kennt jetzt rund 60.000 Ortsteile. Gib einfach „Erfelden“, „Riedstadt-Erfelden“ oder „Bonn-Beuel“ ein – die App zeigt, zu welcher Gemeinde der Ort gehört, und führt dich zum passenden Entsorger. Wo möglich wählt sie den Ort im nächsten Schritt gleich vor.
• In der Trefferliste steht jetzt, ob ein Entsorger deinen Ort führt, zum Beispiel „Führt Karlsruhe · auch 14 Orte im Landkreis Konstanz“
• Suche nach dem Kreis, etwa „Landkreis Konstanz“, zeigt alle Entsorger, die dort Orte führen
• Neu: Bischofsheim (Kreis Groß-Gerau) mit eigenem Abfallkalender
```

### Neu in Version 2.0.10 (freigegeben, Build 14)

```
Tonnendienst im Rhythmus
Wechselt ihr euch im Haus mit den Tonnen ab? Stell einfach deinen Rhythmus ein, zum Beispiel „jede 2. Woche“, „jede 4. Woche, je 2 Wochen“ oder „jeden 3. Monat“. Die App rechnet deine Dienste selbst aus, zeigt dir die nächsten Termine und erinnert dich nur, wenn du dran bist. Unregelmäßige Pläne trägst du weiter als feste Zeiträume ein.
• Ein Hinweis in der Müll-Liste führt direkt zu „Mein Tonnendienst“
• Nutzt du die App auf mehreren Geräten, aktualisiere alle: Ältere Versionen kennen den Rhythmus nicht und erinnern dort weiter an jede Abfuhr

Jeder Entsorger geprüft
Wir haben alle über 800 Entsorger einzeln durchgespielt, von der Adresse bis zu den Terminen, und die gefundenen Fehler behoben.
• Rhein-Lahn-Kreis wieder dabei: Das Portal ist abgeschaltet, die Termine kommen jetzt aus den Kalendern der Verbandsgemeinden
• Neu oder wieder da: Rheingau (Eltville, Geisenheim, Rüdesheim …), Pirmasens, Gladbeck, Wetterau-Gemeinden wie Florstadt, Niddatal, Ortenberg und Wölfersheim
• Bei über 70 Städten und Gemeinden mit „Mein-Abfallkalender“ (zum Beispiel Marburg, Erlangen, Bad Nauheim) wählst du jetzt einfach deine Straße – kein Link mehr zum Kopieren
• Bremen, Bayreuth, Arnsberg, Landau, Köln und weitere: Straßen zum Antippen statt genauer Schreibweise
• Repariert unter anderem: Lübeck, Kassel, Offenbach, Wuppertal, Düsseldorf, Velbert, Göttingen, Aurich, Kreis Verden
• Liefert ein Portal keine kommenden Termine mehr, sagt die App das jetzt klar und hilft beim Wechsel

Zuverlässiger
• Findet Müllmax (zum Beispiel Bochum, Mainz) bei der Straßensuche genau eine Straße, heißt der Standort wieder nach der Straße und nicht nur nach der Hausnummer
```

### Neu in Version 2.0.9

```
Jede Müllart einzeln wählen
Beim Einrichten siehst du jetzt jede Müllart deines Entsorgers mit eigenem Schalter. Alle sind vorab eingeschaltet, abwählen entscheidest du selbst. So fehlt zum Beispiel der Grünschnitt nicht mehr im Kalender.

Neu dabei
• Frechen liefert Termine je Straße, auch für die Leerung alle vier Wochen
• Viele weitere Städte und Gemeinden, zum Beispiel Neuss, Göttingen, Gießen, Wetzlar, Hürth und Saarbrücken

Jede Gemeinde einzeln geprüft
• Wir haben nicht nur die Landkreise abgefragt, sondern alle 10.751 Städte und Gemeinden in Deutschland einzeln gegen die Entsorger geprüft
• Für 10.596 davon findet die App den zuständigen Entsorger direkt über die Suche

Ort nicht dabei?
• Gibt es für deinen Ort keinen abrufbaren Online-Kalender, sagt die App jetzt klar, warum: mit Entsorger, Webseite und Tag unserer Prüfung
• Von dort fügst du direkt einen Kalender-Link ein, lädst Termine aus einer Datei oder meldest uns den Ort

Wieder da
• Leipzig liefert wieder Termine

Zuverlässiger
• Die App stürzt nicht mehr ab, wenn du in der Erinnerung auf „Erledigt“ oder „In 1 Stunde nochmal“ tippst
• Antwortet ein Portal einmal nicht vollständig, bleiben deine kommenden Termine stehen
• Nach der Straßensuche trägt der Standort nur noch die Adresse im Namen, nicht mehr den eingetippten Suchtext
• Findet die Suche genau eine Straße, zeigt die App sie dir zum Antippen, statt sie still zu übernehmen
• Rückfragen vor dem Löschen erscheinen direkt am Knopf
```

### Werbetext (optional, max. 170 Zeichen)

```
Neu: Jede Müllart mit eigenem Schalter, damit keine Abfuhr fehlt. Abfuhrtermine für über 380 Landkreise, Erinnerung am Vorabend, Geburtstage gleich mit. Ohne Werbung.
```

(Seit 2.0.11: „Neu: Ortsteile finden – „Erfelden“ führt zu Riedstadt. Über 800 Entsorger geprüft, Erinnerung am Vorabend, Geburtstage gleich mit. Ohne Werbung.“ (144 Zeichen). 2.0.10: „Neu: Tonnendienst im Rhythmus – erinnert nur, wenn du dran bist. Über 800 Entsorger geprüft, Erinnerung am Vorabend, Geburtstage gleich mit. Ohne Werbung.“ Davor 166 Zeichen, seit 2.0.9. Vorher: „Neu: Mein Tonnendienst – Erinnerungen nur, wenn du dran bist. Abfuhrtermine für über 380 Landkreise, Erinnerung am Vorabend, Geburtstage gleich mit. Ohne Werbung.“ Eine neue Version übernimmt den Werbetext nicht, er muss jedes Mal neu eingetragen werden. Der Werbetext lässt sich jederzeit ohne neue Version ändern.)

### Schlüsselwörter (Pflicht, max. 100 Zeichen, ohne Leerzeichen nach Kommas)

```
Müllabfuhr,Abfallkalender,Müll,Gelber Sack,Abfall,Mülltonne,Biotonne,Geburtstag,Erinnerung,Widget
```

(97 Zeichen. Wörter aus dem App-Namen wie „Tonne“ und „Torte“ nicht wiederholen – die durchsucht Apple ohnehin.)

### Support-URL (Pflicht)

`https://tonne.kant.ovh/support.html`
(eigene Webseite, Quelltext in `website/`; seit 14.11.2026 in 2.0.11 eingetragen, vorher GitHub Pages)

### Marketing-URL (optional)

`https://tonne.kant.ovh/`

---

## 2. App-Informationen

### Kategorie

- **Primär:** Dienstprogramme
- **Sekundär:** Lifestyle

### Inhaltsrechte

Frage: „Enthält, zeigt oder greift deine App auf Inhalte Dritter zu?“
→ **Ja.** Die App ruft Abfuhrtermine von öffentlichen Portalen der Entsorger ab und zeigt sie an.
Danach fragt Apple, ob du die nötigen Rechte hast. Die Termine sind öffentlich zugängliche Informationen der Kommunen und Entsorger, die App gibt sie nur für die eigene Adresse des Nutzers wieder und nennt die Quelle. Ob du das bestätigst, entscheidest du – im Zweifel vorher kurz rechtlich prüfen lassen.

### Altersfreigabe (Fragebogen)

Überall **„Keine“ / „Nein“**:
- Gewalt, Horror, Sexualität, Nacktheit, Drogen, Alkohol, Tabak, Glücksspiel, Wettbewerbe, Schimpfwörter, medizinische Infos: **Keine**
- Unbeschränkter Webzugriff (eingebauter Browser): **Nein** – Links öffnen in Safari
- Nutzergenerierte Inhalte, Chat, Nachrichten: **Nein**
- Werbung: **Nein**
- Kontrollen für Eltern / Altersverifikation: **Nein**

Ergebnis: **4+**

---

## 3. App-Datenschutz

### Datenschutzrichtlinien-URL (Pflicht)

`https://tonne.kant.ovh/datenschutz.html`
(seit 14.11.2026 unter App-Datenschutz eingetragen, wird mit 2.0.11 veröffentlicht; vorher GitHub Pages)

### Datenerfassung

Frage: „Erfassen du oder deine Drittanbieter Daten aus dieser App?“
→ **Nein, wir erfassen keine Daten aus dieser App.**

Begründung (für dich, falls Apple nachfragt):
- Kein Konto, keine Werbung, keine Analyse, kein Tracking, kein eigener Server.
- Daten liegen auf dem Gerät und in der privaten iCloud des Nutzers (CloudKit) – der Entwickler hat keinen Zugriff.
- Standort wird nur auf Wunsch einmalig auf dem Gerät genutzt, um den Landkreis vorzuschlagen.
- Für die Termine fragt die App direkt beim Portal des Entsorgers an (Straße/Ort). Das dient nur der Beantwortung dieser Anfrage in Echtzeit – nach Apples Definition ist das keine „Erfassung“.
- Kontakte: nur ausgewählte Geburtstage werden lokal übernommen.
- Absturzberichte: gehen nur als Mail raus, die der Nutzer im Einzelfall selbst absendet. Optional, selten, nicht Kernfunktion: fällt unter Apples „Optional Disclosure“, Angabe bleibt „keine Daten erfasst“.

### Tracking

Frage: „Werden Daten zum Tracking verwendet?“ → **Nein**

---

## 4. Seiten auf GitHub veröffentlichen (alt, nur noch bis 2.0.11 im Store ist; danach siehe `website/ABLAUF-REPO-PRIVAT.md`)

1. Repo öffentlich machen: GitHub → `ios_github` → **Settings → General → Danger Zone → Change visibility → Public**
   (GitHub Pages gibt es bei privaten Repos nur mit einem Bezahl-Tarif).
2. **Settings → Pages** → *Build and deployment* → Source **Deploy from a branch** →
   Branch **claude/adoring-ride-nxgrwn**, Ordner **/docs** → **Save**.
3. Nach 1–2 Minuten sind die Seiten erreichbar:
   - https://manfahrer-gf.github.io/ios_github/appstore/datenschutz.html
   - https://manfahrer-gf.github.io/ios_github/appstore/support.html

---

## 5. Screenshots

Liegen in `docs/appstore/screenshots/` – je Gerätegröße ein Ordner, Reihenfolge nach Nummer im Dateinamen:

| App Store Connect | Ordner | Pixel |
|---|---|---|
| iPhone Duo (innen, aufgeklappt) | `iPhone-Duo-innen` | 2007 × 2853 |
| iPhone 6,9" | `iPhone-6.9` | 1320 × 2868 |
| iPhone 6,7"/6,5" | `iPhone-6.7` | 1290 × 2796 |
| iPhone 6,3" (Dynamic Island, mittel) | `iPhone-6.3` | 1206 × 2622 |
| iPhone 6,1" | `iPhone-6.1` | 1179 × 2556 |
| iPad 13" | `iPad-13` | 2064 × 2752 (PNG und JPG) |
| iPad 12,9" | `iPad-12.9` | 2048 × 2732 (PNG und JPG) |
| Apple Watch Ultra 3 | `Watch-Ultra-422x514` | 422 × 514 |
| Apple Watch Series 10/11 (46 mm) | `Watch-46mm-416x496` | 416 × 496 |
| Apple Watch Ultra/Ultra 2 | `Watch-Ultra-410x502` | 410 × 502 |
| Apple Watch Series 7–9 (45 mm) | `Watch-45mm-396x484` | 396 × 484 |

Es reicht jeweils die größte verlangte Größe; App Store Connect skaliert für kleinere Geräte.
