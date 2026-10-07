<?php
declare(strict_types=1);

/**
 * Cron-Endpunkt: alle 10 Minuten aufrufen (IONOS Cronjob oder externer Dienst).
 * URL: https://…/cron.php?token=<Token aus den Einstellungen>
 */
require dirname(__DIR__) . '/src/bootstrap.php';

use TonneTorte\Api;
use TonneTorte\Reminders;

header('Content-Type: application/json; charset=utf-8');
$token = (string) ($_GET['token'] ?? '');
if ($token === '' || !hash_equals(Api::cronToken(), $token)) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Ungültiger Token.']);
    exit;
}
echo json_encode(['ok' => true, 'data' => Reminders::runCron()], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
