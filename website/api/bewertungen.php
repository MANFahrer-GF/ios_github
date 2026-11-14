<?php
// Bewertungen aus dem App Store (öffentliche Apple-Schnittstellen), serverseitig zwischengespeichert.
// Besucher fragen nie selbst bei Apple an; der Server holt höchstens alle 6 Stunden neu.
declare(strict_types=1);

const APP_ID = '6820155038';
const TTL = 6 * 3600;

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: public, max-age=300');

$dir = dirname(__DIR__, 2) . '/private';
$cache = $dir . '/bewertungen.json';

// Spam-Sperre des Kontaktformulars: Einträge leben höchstens 24 Stunden. Wurde die Datei so lange nicht
// mehr geschrieben, sind alle Einträge abgelaufen; jeder Seitenaufruf räumt sie dann weg.
$limitDatei = $dir . '/kontakt-limit.json';
if (is_file($limitDatei) && time() - filemtime($limitDatei) >= 86400) @unlink($limitDatei);

if (is_file($cache) && time() - filemtime($cache) < TTL) {
    readfile($cache);
    exit;
}

function holen(string $url): ?array {
    $ctx = stream_context_create(['http' => ['timeout' => 5, 'header' => "User-Agent: tonne.kant.ovh\r\n"]]);
    $raw = @file_get_contents($url, false, $ctx);
    if ($raw === false) return null;
    $data = json_decode($raw, true);
    return is_array($data) ? $data : null;
}

$lookup = holen('https://itunes.apple.com/lookup?id=' . APP_ID . '&country=de');
$feed = holen('https://itunes.apple.com/de/rss/customerreviews/page=1/id=' . APP_ID . '/sortby=mostrecent/json');
$app = $lookup['results'][0] ?? null;

if (!$app) {
    // Apple nicht erreichbar: letzten Stand weiter ausliefern, sonst leer.
    if (is_file($cache)) { readfile($cache); } else { header('Cache-Control: no-store'); http_response_code(503); echo '{"ok":false}'; }
    exit;
}

// 1. Quelle: Store-Webseite (enthält auch die Antworten des Entwicklers), eingebettete Seitendaten.
$rezensionen = [];
$ctx = stream_context_create(['http' => ['timeout' => 5, 'header' => "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15\r\nAccept-Language: de-DE\r\n"]]);
$seite = @file_get_contents('https://apps.apple.com/de/app/tonne-torte/id' . APP_ID . '?see-all=reviews', false, $ctx);
if ($seite !== false && preg_match('~<script[^>]*id="serialized-server-data"[^>]*>(.*?)</script>~s', $seite, $m)) {
    $daten = json_decode($m[1], true);
    $gefunden = [];
    $suche = function ($o) use (&$suche, &$gefunden) {
        if (!is_array($o)) return;
        if (isset($o['reviewerName'], $o['rating'])) { $gefunden[(string)($o['id'] ?? count($gefunden))] = $o; }
        foreach ($o as $v) $suche($v);
    };
    $suche($daten);
    foreach ($gefunden as $r) {
        $antwort = null;
        if (!empty($r['response']['contents'])) {
            $antwort = ['text' => (string)$r['response']['contents'], 'datum' => substr((string)($r['response']['date'] ?? ''), 0, 10)];
        }
        $rezensionen[] = [
            'sterne' => (int)$r['rating'],
            'titel' => (string)($r['title'] ?? ''),
            'text' => (string)($r['contents'] ?? ''),
            'autor' => (string)$r['reviewerName'],
            'datum' => substr((string)($r['date'] ?? ''), 0, 10),
            'antwort' => $antwort,
        ];
    }
}

// 2. Rückfall: RSS-Feed (ohne Antworten), falls die Webseite nichts liefert.
if (!$rezensionen) {
    $eintraege = $feed['feed']['entry'] ?? [];
    if (isset($eintraege['id'])) $eintraege = [$eintraege];
    foreach ($eintraege as $e) {
        $sterne = (int)($e['im:rating']['label'] ?? 0);
        if ($sterne < 1) continue;
        $rezensionen[] = [
            'sterne' => $sterne,
            'titel' => (string)($e['title']['label'] ?? ''),
            'text' => (string)($e['content']['label'] ?? ''),
            'autor' => (string)($e['author']['name']['label'] ?? ''),
            'datum' => substr((string)($e['updated']['label'] ?? ''), 0, 10),
            'antwort' => null,
        ];
    }
}
// Beide Quellen leer (Apple kurz nicht erreichbar): die zuletzt gespeicherten Rezensionen behalten.
if (!$rezensionen && is_file($cache)) {
    $alt = json_decode((string)file_get_contents($cache), true);
    $rezensionen = is_array($alt['rezensionen'] ?? null) ? $alt['rezensionen'] : [];
}
usort($rezensionen, fn($a, $b) => strcmp($b['datum'], $a['datum']));

$out = json_encode([
    'ok' => true,
    'schnitt' => round((float)($app['averageUserRating'] ?? 0), 1),
    'anzahl' => (int)($app['userRatingCount'] ?? 0),
    'version' => (string)($app['version'] ?? ''),
    'rezensionen' => $rezensionen,
    'stand' => gmdate('c'),
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

if (is_dir($dir)) @file_put_contents($cache, $out, LOCK_EX);
echo $out;
