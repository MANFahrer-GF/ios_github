<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/bootstrap.php';

use TonneTorte\Db;
use TonneTorte\Feed;

$token = (string) ($_GET['token'] ?? '');
$expected = Db::setting('feed_token');
if ($expected === null || $token === '' || !hash_equals($expected, $token)) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Ungültiger Token.\n";
    exit;
}

header('Content-Type: text/calendar; charset=utf-8');
header('Content-Disposition: inline; filename="tonne-und-torte.ics"');
header('Cache-Control: private, max-age=600');
echo Feed::build();
