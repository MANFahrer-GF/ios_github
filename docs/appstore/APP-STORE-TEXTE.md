# App Store Connect – Texte und Antworten für „Tonne & Torte“

Alles zum Hineinkopieren.

---

## 1. Version → Deutsch

### Beschreibung (Pflicht)

```
Nie wieder die Tonne vergessen – und keinen Geburtstag mehr verpassen.

Tonne & Torte holt die Abfuhrtermine direkt vom Portal deines Entsorgers und erinnert dich am Vorabend: „Morgen: Gelber Sack und Restmüll“. Ein Tipp auf „Erledigt“, und die Sache ist abgehakt. Am Abholtag erinnert dich die App, die Tonnen wieder reinzuholen – Gelbe Säcke und Grünschnitt lässt sie dabei außen vor.

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
• Siri und Kurzbefehle: „Wann kommt die Müllabfuhr?“

GEBURTSTAGE UND EIGENE TERMINE
• Geburtstage aus den Kontakten übernehmen – nur die, die du auswählst
• Erinnerung am Tag und auf Wunsch einige Tage vorher, mit Alter und runden Geburtstagen
• Geschenkideen notieren, Liste als CSV oder PDF exportieren
• Eigene wiederkehrende Termine

CLEAN. OHNE MIST.
Keine Werbung, kein Tracking, kein Konto. Deine Daten bleiben auf deinen Geräten und in deiner eigenen iCloud.

Die Termine stammen von den Portalen der Entsorger. Alle Angaben ohne Gewähr – im Zweifel gilt der Abfuhrkalender deines Entsorgers.
```

### Werbetext (optional, max. 170 Zeichen)

```
Abfuhrtermine für über 380 Landkreise, Erinnerung am Vorabend, „Tonne wieder reinholen“ – und Geburtstage gleich mit. Ohne Werbung, ohne Tracking.
```

### Schlüsselwörter (Pflicht, max. 100 Zeichen, ohne Leerzeichen nach Kommas)

```
Müllabfuhr,Abfallkalender,Müll,Gelber Sack,Abfall,Mülltonne,Biotonne,Geburtstag,Erinnerung,Widget
```

(97 Zeichen. Wörter aus dem App-Namen wie „Tonne“ und „Torte“ nicht wiederholen – die durchsucht Apple ohnehin.)

### Support-URL (Pflicht)

`https://manfahrer-gf.github.io/ios_github/appstore/support.html`
(GitHub Pages, siehe unten „Seiten auf GitHub veröffentlichen“)

### Marketing-URL (optional)

leer lassen

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

`https://manfahrer-gf.github.io/ios_github/appstore/datenschutz.html`
(GitHub Pages, siehe unten „Seiten auf GitHub veröffentlichen“)

### Datenerfassung

Frage: „Erfassen du oder deine Drittanbieter Daten aus dieser App?“
→ **Nein, wir erfassen keine Daten aus dieser App.**

Begründung (für dich, falls Apple nachfragt):
- Kein Konto, keine Werbung, keine Analyse, kein Tracking, kein eigener Server.
- Daten liegen auf dem Gerät und in der privaten iCloud des Nutzers (CloudKit) – der Entwickler hat keinen Zugriff.
- Standort wird nur auf Wunsch einmalig auf dem Gerät genutzt, um den Landkreis vorzuschlagen.
- Für die Termine fragt die App direkt beim Portal des Entsorgers an (Straße/Ort). Das dient nur der Beantwortung dieser Anfrage in Echtzeit – nach Apples Definition ist das keine „Erfassung“.
- Kontakte: nur ausgewählte Geburtstage werden lokal übernommen.

### Tracking

Frage: „Werden Daten zum Tracking verwendet?“ → **Nein**

---

## 4. Seiten auf GitHub veröffentlichen (einmalig)

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
| iPhone 6,9" | `iPhone-6.9` | 1320 × 2868 |
| iPhone 6,7"/6,5" | `iPhone-6.7` | 1290 × 2796 |
| iPhone 6,3" (Dynamic Island, mittel) | `iPhone-6.3` | 1206 × 2622 |
| iPhone 6,1" | `iPhone-6.1` | 1179 × 2556 |
| iPad 13" | `iPad-13` | 2064 × 2752 |
| Apple Watch Ultra 3 | `Watch-Ultra-422x514` | 422 × 514 |
| Apple Watch Series 10/11 (46 mm) | `Watch-46mm-416x496` | 416 × 496 |
| Apple Watch Ultra/Ultra 2 | `Watch-Ultra-410x502` | 410 × 502 |
| Apple Watch Series 7–9 (45 mm) | `Watch-45mm-396x484` | 396 × 484 |

Es reicht jeweils die größte verlangte Größe; App Store Connect skaliert für kleinere Geräte.
