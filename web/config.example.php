<?php
/**
 * Optionale Konfiguration – als config.php speichern.
 * Ohne diese Datei nutzt die App SQLite in data/tonne.sqlite.
 */
return [
    // MySQL statt SQLite (z. B. IONOS-Datenbank):
    // 'db_dsn' => 'mysql:host=db5000000000.hosting-data.io;dbname=dbs000000;charset=utf8mb4',
    // 'db_user' => 'dbu000000',
    // 'db_pass' => 'geheim',

    // Feste Basis-URL, falls die automatische Erkennung hinter einem Proxy nicht passt:
    // 'base_url' => 'https://deine-domain.de/tonne',

    'app_name' => 'Tonne & Torte',
];
