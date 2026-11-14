# Umzug der Webseite und Repo auf privat – sicherer Ablauf

Stand 14.11.2026. Neue Seite: **https://tonne.kant.ovh** (IONOS-Server, Plesk-Abo `tonne.kant.ovh`, HTTPS per Let's Encrypt).
Alte Seite: `https://manfahrer-gf.github.io/ios_github/` (GitHub Pages aus `main/docs`, geht nur bei öffentlichem Repo ohne GitHub Pro).

## Was wo auf GitHub Pages zeigt

| Angabe | Wo | Heute | Änderbar |
|---|---|---|---|
| Datenschutz-URL | App Store Connect › App-Informationen | `…github.io/ios_github/appstore/datenschutz.html` | jederzeit, ohne neue Version |
| Support-URL | App Store Connect › Version (2.0.11 eingereicht) | `…github.io/ios_github/appstore/support.html` | nur mit einer neuen Version |
| Marketing-URL | Version | leer | mit neuer Version |
| Die App selbst | Code | verlinkt **nicht** auf GitHub Pages (geprüft mit `git grep`) | – |

Die neue Seite leitet die alten Pfade schon um: `tonne.kant.ovh/appstore/support.html` → `/support.html`, ebenso `datenschutz.html`.

## Reihenfolge

1. **Jetzt möglich (nach Thomas' Okay):** In App Store Connect › App-Informationen die Datenschutz-URL auf
   `https://tonne.kant.ovh/datenschutz.html` stellen und sichern.
2. **Mit der nächsten Version (2.0.12):** In der Version die Support-URL auf `https://tonne.kant.ovh/support.html` setzen,
   optional Marketing-URL `https://tonne.kant.ovh/`. `docs/appstore/APP-STORE-TEXTE.md` im selben Zug auf die neuen Adressen ändern.
3. **Warten, bis 2.0.12 im Store ist** („Bereit für Vertrieb“) und keine ältere Version mehr in Prüfung hängt. Solange
   2.0.11 (Support-URL GitHub) noch geprüft wird oder die aktuelle Store-Version ist, bleibt GitHub Pages an.
4. **Gegenprobe:** In App Store Connect alle drei URL-Felder ansehen, keine darf mehr `github.io` enthalten.
   Die Store-Seite im Browser öffnen und die Links „Support“ und „Datenschutz“ anklicken.
5. **Dann (nach Thomas' Okay) Repo auf privat:** GitHub › `MANFahrer-GF/ios_github` › Settings › General › Danger Zone ›
   Change visibility › Private. GitHub Pages geht damit aus. Xcode Cloud arbeitet über die installierte GitHub-App und
   läuft mit privaten Repos weiter; danach einen Build anstoßen und prüfen.

Nicht vorher privat stellen: Apple prüft die Support-URL der eingereichten Version, und eine tote Datenschutz-URL kann
zur Ablehnung führen.

## Betrieb der neuen Seite

- Quelltext: `website/` (dieses Repo). Ausliefern: `website/deploy.sh`, Abgleich: `website/deploy.sh --check` (Ziel: 0 Abweichungen).
- Kontaktformular `api/kontakt.php` schickt an `thomas@kant.ovh`, Absender `noreply@tonne.kant.ovh`.
  Braucht bei OVH SPF (`tonne` TXT `v=spf1 +a -all`) und DKIM (`default._domainkey.tonne`), weil `kant.ovh` DMARC `p=reject` hat.
  Testmodus ohne Versand: Datei `/var/www/vhosts/tonne.kant.ovh/private/kontakt-testmodus` anlegen.
- Bewertungen `api/bewertungen.php`: Rezensionen samt Antworten über die App Store Connect API (Rückfall: Store-Seite, RSS), Sterne über iTunes-Lookup, Zwischenspeicher 6 h in `private/`.
- Downloads/Updates `api/zahlen.php`: Verkaufsberichte (Anbieter-Nr. 94916679), Berichte dauerhaft in `private/berichte/`.
- API-Schlüssel: Teamschlüssel „tonne.kant.ovh Webseite“ (`LY864RT3RF`, Rollen Verkauf und Berichte + Kundendienst), Datei nur in `private/` (600), Konfiguration `private/asc.json`. Der erste Schlüssel `R4T3M8BD83` ist widerrufen.
- DNS bei OVH: A `tonne` → 217.154.70.243, AAAA `tonne` → 2a01:239:385:900::1, TXT SPF und DKIM (siehe oben). Plesk-Abo hat beide IPs.
- Logs: täglich rotiert, 14 Dateien (DSGVO-Angabe „spätestens nach 15 Tagen“). Webstatistik aus.
- Nach Freigabe von 2.0.11: Startseite „Bis in die Gemeinde.“ wieder auf „Bis in den Ortsteil.“, Ortsteil-Kachel ohne „mit dem nächsten Update“, Hinweis unter der Ortssuche kürzen.
- Ortsdaten für die Live-Suche nach Katalog-Änderungen neu erzeugen: `python3 website/tools/orte_export.py`, dann ausliefern.
- nginx-Zusatz (Gzip, Sicherheits-Header) liegt in `/var/www/vhosts/system/tonne.kant.ovh/conf/vhost_nginx.conf`.
