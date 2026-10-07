<?php
declare(strict_types=1);

/**
 * JSON für das Scriptable-Widget: widget.php?token=<Feed-Token>[&location=<ID>]
 */
require dirname(__DIR__) . '/src/bootstrap.php';

use TonneTorte\Db;
use TonneTorte\Widget;

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: private, max-age=300');

$token = (string) ($_GET['token'] ?? '');
$expected = Db::setting('feed_token');
if ($expected === null || $token === '' || !hash_equals($expected, $token)) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'error' => 'Ungültiger Token.']);
    exit;
}
$location = isset($_GET['location']) && $_GET['location'] !== '' ? (int) $_GET['location'] : null;
echo json_encode(['ok' => true] + Widget::data($location), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
