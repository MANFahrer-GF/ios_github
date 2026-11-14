<?php
// App Store Connect API: Anmeldung per JWT (ES256) mit dem Schlüssel aus private/ (nie im Webordner).
declare(strict_types=1);
if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) { http_response_code(404); exit; }

function asc_konfig(): ?array {
    $dir = dirname(__DIR__, 3) . '/private';
    $c = json_decode((string)@file_get_contents($dir . '/asc.json'), true);
    if (!is_array($c) || empty($c['key_id'])) return null;
    $c['pem'] = (string)@file_get_contents($dir . '/AuthKey_' . $c['key_id'] . '.p8');
    return $c['pem'] !== '' ? $c : null;
}

function asc_jwt(array $c): ?string {
    $b = fn(string $s): string => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
    $kopf = $b(json_encode(['alg' => 'ES256', 'kid' => $c['key_id'], 'typ' => 'JWT']));
    $last = $b(json_encode(['iss' => $c['issuer'], 'iat' => time(), 'exp' => time() + 900, 'aud' => 'appstoreconnect-v1']));
    $key = openssl_pkey_get_private($c['pem']);
    if (!$key || !openssl_sign("$kopf.$last", $der, $key, OPENSSL_ALGO_SHA256)) return null;
    // DER-Signatur (SEQUENCE von r und s) in das rohe 64-Byte-Format von JWT umwandeln
    $pos = 2;
    if (ord($der[1]) & 0x80) $pos += ord($der[1]) & 0x7f;
    $teile = [];
    for ($i = 0; $i < 2; $i++) {
        $len = ord($der[$pos + 1]);
        $teile[] = str_pad(ltrim(substr($der, $pos + 2, $len), "\0"), 32, "\0", STR_PAD_LEFT);
        $pos += 2 + $len;
    }
    return "$kopf.$last." . $b($teile[0] . $teile[1]);
}

/** GET gegen die API. Liefert [Statuscode, Rohdaten]. */
function asc_get(string $pfad, string $accept = 'application/json'): array {
    $c = asc_konfig();
    $jwt = $c ? asc_jwt($c) : null;
    if (!$jwt) return [0, ''];
    $ctx = stream_context_create(['http' => [
        'header' => "Authorization: Bearer $jwt\r\nAccept: $accept\r\n",
        'ignore_errors' => true, 'timeout' => 15,
    ]]);
    $raw = @file_get_contents('https://api.appstoreconnect.apple.com' . $pfad, false, $ctx);
    $code = 0;
    if (isset($http_response_header[0]) && preg_match('~\s(\d{3})\s~', $http_response_header[0], $m)) $code = (int)$m[1];
    return [$code, $raw === false ? '' : $raw];
}
