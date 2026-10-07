<?php
declare(strict_types=1);

namespace TonneTorte;

use Minishlink\WebPush\Subscription;
use Minishlink\WebPush\VAPID;
use Minishlink\WebPush\WebPush;

/** Web-Push: VAPID-Schlüssel, Abonnements und Versand. */
final class Push
{
    /** @return array{publicKey: string, privateKey: string} */
    public static function vapidKeys(): array
    {
        $public = Db::setting('vapid_public');
        $private = Db::setting('vapid_private');
        if ($public === null || $private === null) {
            $keys = VAPID::createVapidKeys();
            Db::setSetting('vapid_public', $keys['publicKey']);
            Db::setSetting('vapid_private', $keys['privateKey']);
            return $keys;
        }
        return ['publicKey' => $public, 'privateKey' => $private];
    }

    public static function subscribe(array $subscription, string $userAgent): void
    {
        $endpoint = (string) ($subscription['endpoint'] ?? '');
        $p256dh = (string) ($subscription['keys']['p256dh'] ?? '');
        $auth = (string) ($subscription['keys']['auth'] ?? '');
        if ($endpoint === '' || $p256dh === '' || $auth === '') {
            throw new \InvalidArgumentException('Unvollständiges Push-Abonnement.');
        }
        $stmt = Db::pdo()->prepare('INSERT INTO push_subscriptions (endpoint, p256dh, auth, content_encoding, user_agent, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(endpoint) DO UPDATE SET p256dh = excluded.p256dh, auth = excluded.auth, user_agent = excluded.user_agent, failures = 0');
        $stmt->execute([$endpoint, $p256dh, $auth, 'aes128gcm', mb_substr($userAgent, 0, 200), Db::now()]);
    }

    public static function unsubscribe(string $endpoint): void
    {
        Db::pdo()->prepare('DELETE FROM push_subscriptions WHERE endpoint = ?')->execute([$endpoint]);
    }

    public static function subscriptions(): array
    {
        return Db::pdo()->query('SELECT id, endpoint, user_agent, created_at, last_success_at, failures FROM push_subscriptions ORDER BY id')->fetchAll();
    }

    /**
     * Sendet eine Mitteilung an alle Abonnenten.
     * @return array{sent: int, failed: int, removed: int, errors: string[]}
     */
    public static function send(string $title, string $body, string $tag = '', string $url = ''): array
    {
        $subs = Db::pdo()->query('SELECT * FROM push_subscriptions')->fetchAll();
        $stats = ['sent' => 0, 'failed' => 0, 'removed' => 0, 'errors' => []];
        if ($subs === []) {
            return $stats;
        }
        $keys = self::vapidKeys();
        $subject = Db::setting('base_url') ?: 'mailto:tonne@example.org';
        $webPush = new WebPush([
            'VAPID' => [
                'subject' => $subject,
                'publicKey' => $keys['publicKey'],
                'privateKey' => $keys['privateKey'],
            ],
        ], ['TTL' => 6 * 3600, 'urgency' => 'high']);
        $webPush->setReuseVAPIDHeaders(true);

        $payload = json_encode([
            'title' => $title,
            'body' => $body,
            'tag' => $tag,
            'url' => $url,
        ], JSON_UNESCAPED_UNICODE);

        foreach ($subs as $sub) {
            $webPush->queueNotification(Subscription::create([
                'endpoint' => $sub['endpoint'],
                'publicKey' => $sub['p256dh'],
                'authToken' => $sub['auth'],
                'contentEncoding' => $sub['content_encoding'] ?: 'aes128gcm',
            ]), (string) $payload);
        }

        $pdo = Db::pdo();
        foreach ($webPush->flush() as $report) {
            $endpoint = $report->getRequest()->getUri()->__toString();
            if ($report->isSuccess()) {
                $stats['sent']++;
                $pdo->prepare('UPDATE push_subscriptions SET last_success_at = ?, failures = 0 WHERE endpoint = ?')
                    ->execute([Db::now(), $endpoint]);
            } elseif ($report->isSubscriptionExpired()) {
                $stats['removed']++;
                $pdo->prepare('DELETE FROM push_subscriptions WHERE endpoint = ?')->execute([$endpoint]);
            } else {
                $stats['failed']++;
                $stats['errors'][] = $report->getReason();
                $pdo->prepare('UPDATE push_subscriptions SET failures = failures + 1 WHERE endpoint = ?')->execute([$endpoint]);
            }
        }
        $pdo->exec('DELETE FROM push_subscriptions WHERE failures >= 10');
        return $stats;
    }
}
