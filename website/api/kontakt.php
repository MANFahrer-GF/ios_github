<?php
// Kontaktformular: schickt die Nachricht per Mail an den Entwickler. Es wird nichts gespeichert,
// außer einem gekürzten Hash der IP-Adresse für höchstens 24 Stunden (Schutz vor Massen-Spam).
declare(strict_types=1);

const EMPFAENGER = 'thomas@kant.ovh';
const ABSENDER = 'noreply@tonne.kant.ovh'; // Plesk erzwingt die Abo-Domain; SPF + DKIM für tonne.kant.ovh nötig (DMARC p=reject auf kant.ovh)
const THEMEN = ['Frage', 'Fehler', 'Ort fehlt', 'Wunsch', 'Lob'];

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function antwort(int $code, array $daten): never {
    http_response_code($code);
    echo json_encode($daten, JSON_UNESCAPED_UNICODE);
    exit;
}
function feld(string $name, int $max): string {
    $v = trim((string)($_POST[$name] ?? ''));
    $v = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $v) ?? '';
    return mb_substr($v, 0, $max);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') antwort(405, ['ok' => false, 'fehler' => 'Nur POST.']);

// Honeypot und Mindestzeit: Bots füllen das versteckte Feld oder schicken sofort ab.
if (feld('website', 200) !== '') antwort(200, ['ok' => true]);
$start = (int)($_POST['t'] ?? 0);
if ($start <= 0 || (int)(microtime(true) * 1000) - $start < 3000) {
    antwort(422, ['ok' => false, 'fehler' => 'Bitte einen Moment warten und noch einmal senden.']);
}

$name = feld('name', 80);
$mail = feld('email', 160);
$thema = feld('thema', 20);
$ort = feld('ort', 160);
$text = feld('nachricht', 5000);

$fehler = [];
if (!filter_var($mail, FILTER_VALIDATE_EMAIL) || preg_match('/[\r\n]/', $mail)) $fehler['email'] = 'Bitte eine gültige E-Mail-Adresse angeben, damit ich antworten kann.';
if (!in_array($thema, THEMEN, true)) $fehler['thema'] = 'Bitte ein Thema wählen.';
if (mb_strlen($text) < 10) $fehler['nachricht'] = 'Bitte schreib ein paar Worte mehr (mindestens 10 Zeichen).';
if ($thema === 'Ort fehlt' && mb_strlen($ort) < 2) $fehler['ort'] = 'Welcher Ort fehlt? Landkreis und Gemeinde helfen.';
if ($fehler) antwort(422, ['ok' => false, 'fehler' => 'Bitte die markierten Felder prüfen.', 'felder' => $fehler]);

// Mengenbegrenzung je IP: 3 in 10 Minuten, 10 am Tag. Nur ein gekürzter Hash wird gemerkt.
$dir = dirname(__DIR__, 2) . '/private';
$datei = $dir . '/kontakt-limit.json';
$jetzt = time();
$ipHash = substr(hash('sha256', ($_SERVER['REMOTE_ADDR'] ?? '') . '|' . date('Y-m-d')), 0, 16);
$fh = @fopen($datei, 'c+');
if ($fh) {
    flock($fh, LOCK_EX);
    $limit = json_decode(stream_get_contents($fh) ?: '{}', true) ?: [];
    foreach ($limit as $k => $zeiten) {
        $limit[$k] = array_values(array_filter($zeiten, fn($z) => $jetzt - $z < 86400));
        if (!$limit[$k]) unset($limit[$k]);
    }
    $meine = $limit[$ipHash] ?? [];
    $kurz = count(array_filter($meine, fn($z) => $jetzt - $z < 600));
    if ($kurz >= 3 || count($meine) >= 10) {
        flock($fh, LOCK_UN); fclose($fh);
        antwort(429, ['ok' => false, 'fehler' => 'Danke, das reicht fürs Erste. Bitte später noch einmal versuchen oder direkt an ' . EMPFAENGER . ' schreiben.']);
    }
    $limit[$ipHash] = [...$meine, $jetzt];
    ftruncate($fh, 0); rewind($fh); fwrite($fh, json_encode($limit)); fflush($fh);
    flock($fh, LOCK_UN); fclose($fh);
}

$betreff = 'Tonne & Torte: ' . $thema . ($name !== '' ? ' von ' . $name : '');
$koerper = "Neue Nachricht über das Kontaktformular auf tonne.kant.ovh\n\n"
    . 'Thema:   ' . $thema . "\n"
    . 'Name:    ' . ($name !== '' ? $name : '(nicht angegeben)') . "\n"
    . 'E-Mail:  ' . $mail . "\n"
    . ($ort !== '' ? 'Ort:     ' . $ort . "\n" : '')
    . "\n" . $text . "\n\n-- \nAntworten geht direkt an den Absender (Reply-To).\n";

$kopf = [
    'From' => 'Tonne & Torte Kontaktformular <' . ABSENDER . '>',
    'Reply-To' => $name !== '' ? mb_encode_mimeheader($name, 'UTF-8') . ' <' . $mail . '>' : $mail,
    'MIME-Version' => '1.0',
    'Content-Type' => 'text/plain; charset=UTF-8',
    'Content-Transfer-Encoding' => '8bit',
    'X-Mailer' => 'tonne.kant.ovh',
];

// Testmodus (Datei private/kontakt-testmodus): alles prüfen, aber keine Mail verschicken.
if (is_file($dir . '/kontakt-testmodus')) antwort(200, ['ok' => true, 'test' => true]);

$gesendet = mail(EMPFAENGER, mb_encode_mimeheader($betreff, 'UTF-8'), $koerper, $kopf, '-f' . ABSENDER);
if (!$gesendet) antwort(500, ['ok' => false, 'fehler' => 'Die Nachricht konnte gerade nicht verschickt werden. Bitte direkt an ' . EMPFAENGER . ' schreiben.']);
antwort(200, ['ok' => true]);
