<?php
declare(strict_types=1);

namespace TonneTorte;

use PDO;

/**
 * SQLite-Datenbank (Standard) oder beliebige PDO-DSN aus config.php.
 * Legt beim ersten Zugriff alle Tabellen an.
 */
final class Db
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo === null) {
            $config = Config::get();
            $dsn = $config['db_dsn'];
            if (str_starts_with($dsn, 'sqlite:')) {
                $file = substr($dsn, 7);
                $dir = dirname($file);
                if (!is_dir($dir)) {
                    mkdir($dir, 0775, true);
                }
            }
            $pdo = new PDO($dsn, $config['db_user'] ?? null, $config['db_pass'] ?? null, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
            if (str_starts_with($dsn, 'sqlite:')) {
                $pdo->exec('PRAGMA journal_mode = WAL');
                $pdo->exec('PRAGMA foreign_keys = ON');
            }
            self::$pdo = $pdo;
            self::migrate($pdo);
        }
        return self::$pdo;
    }

    private static function migrate(PDO $pdo): void
    {
        $pdo->exec('CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            address TEXT NOT NULL DEFAULT "",
            color TEXT NOT NULL DEFAULT "#2E9E6B",
            icon TEXT NOT NULL DEFAULT "🏠",
            sort_order INTEGER NOT NULL DEFAULT 0,
            source_kind TEXT NOT NULL DEFAULT "manual",
            awido_customer TEXT,
            awido_oid TEXT,
            awido_label TEXT,
            ics_url TEXT,
            last_sync_at TEXT,
            last_sync_message TEXT
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS waste_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            location_id INTEGER REFERENCES locations(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            color TEXT NOT NULL DEFAULT "#5B6470",
            icon TEXT NOT NULL DEFAULT "🗑️",
            sort_order INTEGER NOT NULL DEFAULT 0,
            active INTEGER NOT NULL DEFAULT 1,
            reminders INTEGER NOT NULL DEFAULT 1,
            interval_weeks INTEGER NOT NULL DEFAULT 0,
            anchor_date TEXT,
            source_key TEXT
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS pickup_dates (
            waste_type_id INTEGER NOT NULL REFERENCES waste_types(id) ON DELETE CASCADE,
            date TEXT NOT NULL,
            PRIMARY KEY (waste_type_id, date)
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS skipped_dates (
            waste_type_id INTEGER NOT NULL REFERENCES waste_types(id) ON DELETE CASCADE,
            date TEXT NOT NULL,
            PRIMARY KEY (waste_type_id, date)
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS people (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            day INTEGER NOT NULL,
            month INTEGER NOT NULL,
            year INTEGER,
            notes TEXT NOT NULL DEFAULT "",
            color TEXT NOT NULL DEFAULT "#EC4899",
            reminders INTEGER NOT NULL DEFAULT 1,
            remind_days_before INTEGER NOT NULL DEFAULT 1
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS push_subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            endpoint TEXT NOT NULL UNIQUE,
            p256dh TEXT NOT NULL,
            auth TEXT NOT NULL,
            content_encoding TEXT NOT NULL DEFAULT "aes128gcm",
            user_agent TEXT NOT NULL DEFAULT "",
            created_at TEXT NOT NULL,
            last_success_at TEXT,
            failures INTEGER NOT NULL DEFAULT 0
        )');
        $pdo->exec('CREATE TABLE IF NOT EXISTS sent_reminders (
            key TEXT PRIMARY KEY,
            sent_at TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT "",
            body TEXT NOT NULL DEFAULT ""
        )');
    }

    // ----- Einstellungen -----------------------------------------------------

    public static function setting(string $key, ?string $default = null): ?string
    {
        $stmt = self::pdo()->prepare('SELECT value FROM settings WHERE key = ?');
        $stmt->execute([$key]);
        $value = $stmt->fetchColumn();
        return $value === false ? $default : (string) $value;
    }

    public static function setSetting(string $key, string $value): void
    {
        $stmt = self::pdo()->prepare('INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value');
        $stmt->execute([$key, $value]);
    }

    /** Alle Erinnerungs-Einstellungen mit Standardwerten. */
    public static function reminderSettings(): array
    {
        return [
            'evening_enabled' => self::setting('evening_enabled', '1') === '1',
            'evening_time' => self::setting('evening_time', '19:00'),
            'morning_enabled' => self::setting('morning_enabled', '0') === '1',
            'morning_time' => self::setting('morning_time', '07:00'),
            'birthday_time' => self::setting('birthday_time', '09:00'),
            'timezone' => self::setting('timezone', 'Europe/Berlin'),
        ];
    }

    public static function now(): string
    {
        return (new \DateTimeImmutable('now'))->format('Y-m-d H:i:s');
    }

    public static function randomToken(int $bytes = 24): string
    {
        return rtrim(strtr(base64_encode(random_bytes($bytes)), '+/', '-_'), '=');
    }
}
