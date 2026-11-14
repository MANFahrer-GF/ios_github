<?php
// Downloads und Updates aus den Verkaufsberichten von App Store Connect (nur Summen, keine Personendaten).
// Monatsberichte und abgeschlossene Tagesberichte ändern sich nicht mehr und werden dauerhaft in private/ gespeichert.
declare(strict_types=1);
require __DIR__ . '/lib/asc.php';

const VENDOR = '94916679';
const APP = '6820155038';
const ERSTER_MONAT = '2026-10'; // erster Monat mit Verkäufen
const TTL = 6 * 3600;

header('Content-Type: application/json; charset=utf-8');
$dir = dirname(__DIR__, 2) . '/private';
$cache = $dir . '/zahlen.json';
if (is_file($cache) && time() - filemtime($cache) < TTL) { header('Cache-Control: public, max-age=1800'); readfile($cache); exit; }
@mkdir($dir . '/berichte', 0700);

/** Summen eines Berichts je Produktart und Gerät; null = (noch) nicht vorhanden. */
function bericht(string $art, string $datum, string $dir): ?array {
    $datei = "$dir/berichte/$art-$datum.json";
    if (is_file($datei)) return json_decode((string)file_get_contents($datei), true);
    [$code, $raw] = asc_get('/v1/salesReports?filter[frequency]=' . $art . '&filter[reportType]=SALES&filter[reportSubType]=SUMMARY'
        . '&filter[vendorNumber]=' . VENDOR . '&filter[reportDate]=' . $datum . '&filter[version]=1_0', 'application/a-gzip');
    $text = $code === 200 ? @gzdecode($raw) : false;
    if ($text === false) return null;
    $zeilen = array_map(fn($l) => explode("\t", $l), array_filter(explode("\n", $text)));
    $kopf = array_flip(array_shift($zeilen) ?: []);
    $summe = [];
    foreach ($zeilen as $z) {
        if (($z[$kopf['Apple Identifier']] ?? '') !== APP) continue;
        $k = ($z[$kopf['Product Type Identifier']] ?? '?') . '|' . ($z[$kopf['Device']] ?? '?');
        $summe[$k] = ($summe[$k] ?? 0) + (int)($z[$kopf['Units']] ?? 0);
    }
    @file_put_contents($datei, json_encode($summe), LOCK_EX);
    return $summe;
}

$gesamt = [];
$letzterTag = null;
$heute = new DateTimeImmutable('now', new DateTimeZone('America/Los_Angeles')); // Apple rechnet in Pacific Time
$monat = new DateTimeImmutable(ERSTER_MONAT . '-01');
$aktuell = $heute->format('Y-m');
while ($monat->format('Y-m') <= $aktuell) {
    $m = $monat->format('Y-m');
    $teil = $m < $aktuell ? bericht('MONTHLY', $m, $dir) : null;
    if ($teil === null) {
        // Laufender Monat (oder Monatsbericht noch nicht fertig): Tagesberichte bis gestern
        $teil = [];
        $tage = (int)$monat->format('t');
        for ($t = 1; $t <= $tage; $t++) {
            $tag = $monat->setDate((int)$monat->format('Y'), (int)$monat->format('m'), $t);
            if ($tag->format('Y-m-d') >= $heute->format('Y-m-d')) break;
            $d = bericht('DAILY', $tag->format('Y-m-d'), $dir);
            if ($d === null) continue;
            foreach ($d as $k => $v) $teil[$k] = ($teil[$k] ?? 0) + $v;
            $letzterTag = $tag->format('Y-m-d');
        }
    } else {
        $letzterTag = $monat->format('Y-m-t');
    }
    foreach ($teil as $k => $v) $gesamt[$k] = ($gesamt[$k] ?? 0) + $v;
    $monat = $monat->modify('+1 month');
}

// Produktart: 1… = Erst-Download, 7… = Update, 3… = erneuter Download (auch Apple-Watch-Apps)
$z = ['downloads' => 0, 'updates' => 0, 'erneut' => 0, 'geraete' => []];
foreach ($gesamt as $k => $v) {
    [$art, $geraet] = explode('|', $k) + [1 => ''];
    if ($art[0] === '1') { $z['downloads'] += $v; $z['geraete'][$geraet] = ($z['geraete'][$geraet] ?? 0) + $v; }
    elseif ($art[0] === '7') $z['updates'] += $v;
    elseif ($art[0] === '3') $z['erneut'] += $v;
}
arsort($z['geraete']);
$out = json_encode(['ok' => $z['downloads'] > 0] + $z + ['stand' => $letzterTag], JSON_UNESCAPED_UNICODE);
if ($z['downloads'] > 0) @file_put_contents($cache, $out, LOCK_EX);
header('Cache-Control: public, max-age=1800');
echo $out;
