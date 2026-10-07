<?php
declare(strict_types=1);

namespace TonneTorte;

/** Kleiner HTTP-Helfer auf cURL-Basis. */
final class Http
{
    public static function get(string $url, array $headers = []): string
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS => 5,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_CONNECTTIMEOUT => 15,
            CURLOPT_USERAGENT => 'TonneUndTorte/1.0 (+https://github.com/MANFahrer-GF/ios_github)',
            CURLOPT_HTTPHEADER => $headers,
        ]);
        $body = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $error = curl_error($ch);
        curl_close($ch);
        if ($body === false) {
            throw new \RuntimeException('Verbindung fehlgeschlagen: ' . $error);
        }
        if ($status < 200 || $status >= 300) {
            throw new \RuntimeException('Server antwortete mit HTTP ' . $status);
        }
        return (string) $body;
    }

    public static function json(string $url): mixed
    {
        $body = self::get($url, ['Accept: application/json']);
        $data = json_decode($body, true);
        if ($data === null && json_last_error() !== JSON_ERROR_NONE) {
            throw new \RuntimeException('Antwort ist kein gültiges JSON.');
        }
        return $data;
    }
}
