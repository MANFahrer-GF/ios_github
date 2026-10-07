<?php
declare(strict_types=1);

namespace TonneTorte;

/** Einfache Ein-Benutzer-Anmeldung mit Passwort und PHP-Session. */
final class Auth
{
    public static function start(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }
        $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
        session_name(Config::get()['session_name']);
        session_set_cookie_params([
            'lifetime' => 60 * 60 * 24 * 90,
            'path' => '/',
            'secure' => $secure,
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
        session_start();
    }

    public static function isConfigured(): bool
    {
        return Db::setting('password_hash') !== null;
    }

    public static function isLoggedIn(): bool
    {
        self::start();
        return !empty($_SESSION['logged_in']);
    }

    public static function setPassword(string $password): void
    {
        Db::setSetting('password_hash', password_hash($password, PASSWORD_DEFAULT));
    }

    public static function login(string $password): bool
    {
        self::start();
        $hash = Db::setting('password_hash');
        if ($hash === null || !password_verify($password, $hash)) {
            usleep(300000);
            return false;
        }
        session_regenerate_id(true);
        $_SESSION['logged_in'] = true;
        return true;
    }

    public static function logout(): void
    {
        self::start();
        $_SESSION = [];
        session_destroy();
    }
}
