<?php
declare(strict_types=1);

namespace TonneTorte;

/**
 * Lädt config.php (falls vorhanden) und ergänzt Standardwerte.
 * Ohne config.php läuft alles mit SQLite in data/ – ideal für Shared Hosting.
 */
final class Config
{
    private static ?array $config = null;

    public static function get(): array
    {
        if (self::$config === null) {
            $root = dirname(__DIR__);
            $defaults = [
                'db_dsn' => 'sqlite:' . $root . '/data/tonne.sqlite',
                'db_user' => null,
                'db_pass' => null,
                'app_name' => 'Tonne & Torte',
                'base_url' => null, // z. B. https://example.de/tonne – wird sonst automatisch ermittelt
                'session_name' => 'tonnetorte',
            ];
            $file = $root . '/config.php';
            $custom = is_file($file) ? (require $file) : [];
            self::$config = array_merge($defaults, is_array($custom) ? $custom : []);
        }
        return self::$config;
    }

    /** Öffentliche Basis-URL der App (ohne abschließenden Slash). */
    public static function baseUrl(): string
    {
        $configured = self::get()['base_url'];
        if (is_string($configured) && $configured !== '') {
            return rtrim($configured, '/');
        }
        $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
        $host = $_SERVER['HTTP_HOST'] ?? 'localhost';
        $dir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
        return ($https ? 'https' : 'http') . '://' . $host . $dir;
    }
}
