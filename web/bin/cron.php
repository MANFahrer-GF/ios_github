<?php
declare(strict_types=1);

/** Cron per Kommandozeile: php bin/cron.php (alle 10 Minuten). */
require dirname(__DIR__) . '/src/bootstrap.php';

$result = \TonneTorte\Reminders::runCron();
echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT), "\n";
