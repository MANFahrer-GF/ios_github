<?php
declare(strict_types=1);

/** Gemeinsamer Einstieg: Autoloader, Fehlerbehandlung, Zeitzone. */
error_reporting(E_ALL);
ini_set('display_errors', '0');
mb_internal_encoding('UTF-8');

$autoload = dirname(__DIR__) . '/vendor/autoload.php';
if (!is_file($autoload)) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "vendor/ fehlt. Bitte im Projektordner `composer install --no-dev` ausführen und den Ordner mit hochladen.\n";
    exit;
}
require $autoload;

date_default_timezone_set('Europe/Berlin');
try {
    date_default_timezone_set(\TonneTorte\Db::reminderSettings()['timezone']);
} catch (\Throwable) {
    // Datenbank noch nicht erreichbar – Standardzeitzone bleibt.
}
