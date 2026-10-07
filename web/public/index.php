<?php
declare(strict_types=1);

require dirname(__DIR__) . '/src/bootstrap.php';

$version = (string) max(
    @filemtime(__DIR__ . '/assets/app.js') ?: 0,
    @filemtime(__DIR__ . '/assets/app.css') ?: 0,
    @filemtime(__DIR__ . '/sw.js') ?: 0
);
$appName = \TonneTorte\Config::get()['app_name'];
?>
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title><?= htmlspecialchars($appName) ?></title>
<meta name="description" content="Müll- und Geburtstagskalender mit Erinnerungen">
<meta name="theme-color" content="#2F6FED" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0F172A" media="(prefers-color-scheme: dark)">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Tonne & Torte">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" href="assets/icons/icon-192.png" sizes="192x192">
<link rel="apple-touch-icon" href="assets/icons/apple-touch-icon.png">
<link rel="stylesheet" href="assets/app.css?v=<?= $version ?>">
</head>
<body>
<div id="app" aria-live="polite">
  <div class="splash"><div class="splash-icon">🗑️</div><p>Lade …</p></div>
</div>
<div id="modal-root"></div>
<div id="toast-root"></div>
<script>window.TT_VERSION = <?= json_encode($version) ?>;</script>
<script src="assets/app.js?v=<?= $version ?>" defer></script>
</body>
</html>
