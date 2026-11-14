<?php
// Kontaktformular: schickt die Nachricht per Mail an den Entwickler. Es wird nichts gespeichert,
// außer einem gekürzten, geschlüsselten Hash der IP-Adresse für höchstens 24 Stunden (Schutz vor Massen-Spam).
declare(strict_types=1);

const EMPFAENGER = 'thomas@kant.ovh';
const ABSENDER = 'noreply@tonne.kant.ovh'; // Plesk erzwingt die Abo-Domain; SPF + DKIM für tonne.kant.ovh nötig (DMARC p=reject auf kant.ovh)
const THEMEN = ['Frage', 'Fehler', 'Ort fehlt', 'Wunsch', 'Lob'];

$perFetch = ($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '') === 'fetch';
header('Cache-Control: no-store');
if ($perFetch) header('Content-Type: application/json; charset=utf-8');

// Antwort für das Formular (fetch) als JSON; ohne JavaScript zurück zur Kontaktseite.
function antwort(int $code, array $daten): never {
    global $perFetch;
    if (!$perFetch) {
        header('Location: /kontakt.html?' . (!empty($daten['ok']) ? 'gesendet=1' : 'fehler=1'), true, 303);
        exit;
    }
    http_response_code($code);
    echo json_encode($daten, JSON_UNESCAPED_UNICODE);
    exit;
}
function roh(string $name): string {
    $v = $_POST[$name] ?? '';
    return is_string($v) ? $v : '';
}
// Einzeiliges Feld: Zeilenumbrüche und Steuerzeichen werden zu Leerzeichen.
function zeile(string $name, int $max): string {
    $v = preg_replace('/[\x00-\x1F\x7F]+/u', ' ', roh($name)) ?? '';
    return mb_substr(trim($v), 0, $max);
}
// Mehrzeiliger Text: Umbrüche vereinheitlicht, übrige Steuerzeichen entfernt.
function absatz(string $name, int $max): string {
    $v = str_replace(["\r\n", "\r"], "\n", roh($name));
    $v = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $v) ?? '';
    return mb_substr(trim($v), 0, $max);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') antwort(405, ['ok' => false, 'fehler' => 'Nur POST.']);

// Honeypot und Mindestzeit: Bots füllen das versteckte Feld oder schicken sofort ab.
// Die Dauer misst der Browser selbst (unabhängig davon, wie die Uhr des Geräts steht).
if (zeile('website', 200) !== '') antwort(200, ['ok' => true]);
if ((int)roh('dauer') < 3000) {
    antwort(422, ['ok' => false, 'fehler' => 'Bitte einen Moment warten und noch einmal senden.']);
}

$name = zeile('name', 80);
$mail = zeile('email', 160);
$thema = zeile('thema', 20);
$ort = zeile('ort', 160);
$text = absatz('nachricht', 5000);

$fehler = [];
if (!filter_var($mail, FILTER_VALIDATE_EMAIL)) $fehler['email'] = 'Bitte eine gültige E-Mail-Adresse angeben, damit ich antworten kann.';
if (!in_array($thema, THEMEN, true)) $fehler['thema'] = 'Bitte ein Thema wählen.';
if (mb_strlen($text) < 10) $fehler['nachricht'] = 'Bitte schreib ein paar Worte mehr (mindestens 10 Zeichen).';
if ($thema === 'Ort fehlt' && mb_strlen($ort) < 2) $fehler['ort'] = 'Welcher Ort fehlt? Landkreis und Gemeinde helfen.';
if ($fehler) antwort(422, ['ok' => false, 'fehler' => 'Bitte die markierten Felder prüfen.', 'felder' => $fehler]);

// Mengenbegrenzung je IP: 3 in 10 Minuten, 10 am Tag. Gemerkt wird nur ein gekürzter HMAC mit geheimem Schlüssel.
$dir = dirname(__DIR__, 2) . '/private';
if (!is_dir($dir) && !@mkdir($dir, 0700)) antwort(503, ['ok' => false, 'fehler' => 'Gerade nicht möglich. Bitte direkt an ' . EMPFAENGER . ' schreiben.']);
$schluesselDatei = $dir . '/kontakt-schluessel';
if (!is_file($schluesselDatei)) { @file_put_contents($schluesselDatei, bin2hex(random_bytes(32)), LOCK_EX); @chmod($schluesselDatei, 0600); }
$schluessel = (string)@file_get_contents($schluesselDatei);
$datei = $dir . '/kontakt-limit.json';
$jetzt = time();
$ipHash = substr(hash_hmac('sha256', (string)($_SERVER['REMOTE_ADDR'] ?? ''), $schluessel), 0, 16);
$fh = @fopen($datei, 'c+');
if (!$fh || $schluessel === '') antwort(503, ['ok' => false, 'fehler' => 'Gerade nicht möglich. Bitte direkt an ' . EMPFAENGER . ' schreiben.']);
flock($fh, LOCK_EX);
$limit = json_decode(stream_get_contents($fh) ?: '{}', true) ?: [];
foreach ($limit as $k => $zeiten) {
    $limit[$k] = array_values(array_filter((array)$zeiten, fn($z) => $jetzt - (int)$z < 86400));
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

$betreff = 'Tonne & Torte: ' . $thema . ($name !== '' ? ' von ' . $name : '');
$koerper = "Neue Nachricht über das Kontaktformular auf tonne.kant.ovh\n\n"
    . 'Thema:   ' . $thema . "\n"
    . 'Name:    ' . ($name !== '' ? $name : '(nicht angegeben)') . "\n"
    . 'E-Mail:  ' . $mail . "\n"
    . ($ort !== '' ? 'Ort:     ' . $ort . "\n" : '')
    . "\n" . $text . "\n\n-- \nAntworten geht direkt an den Absender (Reply-To).\n";

$kopf = [
    'From' => 'Tonne & Torte Kontaktformular <' . ABSENDER . '>',
    'Reply-To' => $mail,
    'MIME-Version' => '1.0',
    'Content-Type' => 'text/plain; charset=UTF-8',
    'Content-Transfer-Encoding' => 'base64',
    'X-Mailer' => 'tonne.kant.ovh',
];

// Testmodus (Datei private/kontakt-testmodus): alles prüfen, aber keine Mail verschicken.
if (is_file($dir . '/kontakt-testmodus')) antwort(200, ['ok' => true, 'test' => true]);

$gesendet = mail(EMPFAENGER, mb_encode_mimeheader($betreff, 'UTF-8'), chunk_split(base64_encode($koerper)), $kopf, '-f' . ABSENDER);
if (!$gesendet) antwort(500, ['ok' => false, 'fehler' => 'Die Nachricht konnte gerade nicht verschickt werden. Bitte direkt an ' . EMPFAENGER . ' schreiben.']);
antwort(200, ['ok' => true]);
