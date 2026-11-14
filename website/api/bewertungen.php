<?php
// Bewertungen aus dem App Store (öffentliche Apple-Schnittstellen), serverseitig zwischengespeichert.
// Besucher fragen nie selbst bei Apple an; der Server holt höchstens alle 6 Stunden neu.
declare(strict_types=1);

const APP_ID = '6820155038';
const TTL = 6 * 3600;

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: public, max-age=900');

$dir = dirname(__DIR__, 2) . '/private';
$cache = $dir . '/bewertungen.json';

if (is_file($cache) && time() - filemtime($cache) < TTL) {
    readfile($cache);
    exit;
}

function holen(string $url): ?array {
    $ctx = stream_context_create(['http' => ['timeout' => 8, 'header' => "User-Agent: tonne.kant.ovh\r\n"]]);
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
    if (is_file($cache)) { readfile($cache); } else { http_response_code(503); echo '{"ok":false}'; }
    exit;
}

$eintraege = $feed['feed']['entry'] ?? [];
if (isset($eintraege['id'])) $eintraege = [$eintraege];
$rezensionen = [];
foreach ($eintraege as $e) {
    $sterne = (int)($e['im:rating']['label'] ?? 0);
    if ($sterne < 1) continue;
    $rezensionen[] = [
        'sterne' => $sterne,
        'titel' => (string)($e['title']['label'] ?? ''),
        'text' => (string)($e['content']['label'] ?? ''),
        'autor' => (string)($e['author']['name']['label'] ?? ''),
        'datum' => substr((string)($e['updated']['label'] ?? ''), 0, 10),
        'version' => (string)($e['im:version']['label'] ?? ''),
    ];
}

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
