<?php
declare(strict_types=1);

namespace TonneTorte;

/**
 * Berechnet, wann welche Erinnerung fällig ist, und versendet sie per Web-Push.
 * Der Cronjob ruft dispatchDue() z. B. alle 10 Minuten auf.
 */
final class Reminders
{
    /** Nachholfenster: Erinnerungen, die höchstens so lange überfällig sind, werden noch gesendet. */
    private const GRACE_SECONDS = 3 * 3600;

    /**
     * Alle Erinnerungen der nächsten $days Tage.
     * @return array<int, array{key: string, fire_at: string, title: string, body: string, tag: string}>
     */
    public static function planned(int $days = 45): array
    {
        $settings = Db::reminderSettings();
        $from = date('Y-m-d');
        $to = (new \DateTimeImmutable($from))->modify("+{$days} days")->format('Y-m-d');
        $locationCount = (int) Db::pdo()->query('SELECT COUNT(*) FROM locations')->fetchColumn();
        $items = [];

        // --- Müll: je Tag zusammenfassen ---
        $byDay = [];
        foreach (Events::wasteTypes(null, true) as $type) {
            if (!$type['reminders']) {
                continue;
            }
            foreach (Events::pickupDates($type, $from, $to) as $date) {
                $label = $type['name'];
                if ($locationCount > 1 && $type['location_name']) {
                    $label .= ' (' . $type['location_name'] . ')';
                }
                $byDay[$date][] = $label;
            }
        }
        ksort($byDay);
        foreach ($byDay as $date => $names) {
            $list = self::joinNames($names);
            if ($settings['evening_enabled']) {
                $fire = (new \DateTimeImmutable($date . ' ' . $settings['evening_time']))->modify('-1 day');
                $items[] = [
                    'key' => 'waste-evening-' . $date,
                    'fire_at' => $fire->format('Y-m-d H:i'),
                    'title' => count($names) === 1 ? 'Morgen: ' . $names[0] : 'Morgen wird abgeholt',
                    'body' => count($names) === 1 ? 'Heute Abend rausstellen – morgen kommt die Abfuhr.' : $list . ' – heute Abend rausstellen.',
                    'tag' => 'waste-' . $date,
                ];
            }
            if ($settings['morning_enabled']) {
                $fire = new \DateTimeImmutable($date . ' ' . $settings['morning_time']);
                $items[] = [
                    'key' => 'waste-morning-' . $date,
                    'fire_at' => $fire->format('Y-m-d H:i'),
                    'title' => count($names) === 1 ? 'Heute: ' . $names[0] : 'Heute wird abgeholt',
                    'body' => count($names) === 1 ? 'Steht die Tonne schon draußen?' : $list . ' – steht alles draußen?',
                    'tag' => 'waste-' . $date,
                ];
            }
        }

        // --- Geburtstage ---
        foreach (Events::people() as $person) {
            if (!$person['reminders']) {
                continue;
            }
            $next = Events::nextBirthday($person, $from);
            if ($next > $to) {
                continue;
            }
            $age = Events::age($person, $next);
            $items[] = [
                'key' => 'bday-' . $person['id'] . '-' . $next,
                'fire_at' => (new \DateTimeImmutable($next . ' ' . $settings['birthday_time']))->format('Y-m-d H:i'),
                'title' => '🎂 ' . $person['name'] . ' hat heute Geburtstag',
                'body' => $age === null ? 'Zeit zum Gratulieren!' : "{$person['name']} wird heute {$age}. Zeit zum Gratulieren!",
                'tag' => 'bday-' . $person['id'],
            ];
            $before = $person['remind_days_before'];
            if ($before > 0) {
                $fire = (new \DateTimeImmutable($next . ' ' . $settings['birthday_time']))->modify("-{$before} days");
                $when = $before === 1 ? 'morgen' : "in {$before} Tagen";
                $items[] = [
                    'key' => 'bday-pre-' . $person['id'] . '-' . $next,
                    'fire_at' => $fire->format('Y-m-d H:i'),
                    'title' => "🎁 {$person['name']} hat {$when} Geburtstag",
                    'body' => $age === null ? 'Noch ein Geschenk besorgen?' : "Wird {$age}. Noch ein Geschenk besorgen?",
                    'tag' => 'bday-' . $person['id'],
                ];
            }
        }

        usort($items, fn($a, $b) => strcmp($a['fire_at'], $b['fire_at']));
        return $items;
    }

    /** Versendet alle fälligen, noch nicht gesendeten Erinnerungen. @return array<int, array<string, mixed>> */
    public static function dispatchDue(): array
    {
        $pdo = Db::pdo();
        $now = new \DateTimeImmutable('now');
        $earliest = $now->modify('-' . self::GRACE_SECONDS . ' seconds')->format('Y-m-d H:i');
        $nowString = $now->format('Y-m-d H:i');
        $sent = [];

        foreach (self::planned(7) as $item) {
            if ($item['fire_at'] > $nowString || $item['fire_at'] < $earliest) {
                continue;
            }
            $check = $pdo->prepare('SELECT 1 FROM sent_reminders WHERE key = ?');
            $check->execute([$item['key']]);
            if ($check->fetchColumn()) {
                continue;
            }
            $stats = Push::send($item['title'], $item['body'], $item['tag'], Db::setting('base_url') ?? '');
            $pdo->prepare('INSERT INTO sent_reminders (key, sent_at, title, body) VALUES (?, ?, ?, ?)')
                ->execute([$item['key'], Db::now(), $item['title'], $item['body']]);
            $sent[] = $item + ['stats' => $stats];
        }
        $pdo->exec("DELETE FROM sent_reminders WHERE sent_at < '" . $now->modify('-60 days')->format('Y-m-d H:i:s') . "'");
        return $sent;
    }

    /** Wöchentlicher Abgleich aller Standorte mit Online-Quelle. @return string[] */
    public static function syncDueLocations(): array
    {
        $pdo = Db::pdo();
        $messages = [];
        foreach ($pdo->query('SELECT * FROM locations')->fetchAll() as $location) {
            if (!Importer::canSync($location)) {
                continue;
            }
            $last = $location['last_sync_at'] ? new \DateTimeImmutable($location['last_sync_at']) : null;
            if ($last !== null && $last > new \DateTimeImmutable('-7 days')) {
                continue;
            }
            try {
                $count = Importer::sync($location);
                $messages[] = "{$location['name']}: {$count} Termine";
            } catch (\Throwable $e) {
                $pdo->prepare('UPDATE locations SET last_sync_message = ? WHERE id = ?')
                    ->execute(['Automatischer Abgleich fehlgeschlagen: ' . $e->getMessage(), $location['id']]);
                $messages[] = "{$location['name']}: Fehler – " . $e->getMessage();
            }
        }
        return $messages;
    }

    /** Vollständiger Cron-Durchlauf. */
    public static function runCron(): array
    {
        $result = [
            'synced' => self::syncDueLocations(),
            'sent' => self::dispatchDue(),
            'ran_at' => Db::now(),
        ];
        Db::setSetting('last_cron_at', $result['ran_at']);
        return $result;
    }

    private static function joinNames(array $names): string
    {
        if (count($names) <= 1) {
            return $names[0] ?? '';
        }
        $last = array_pop($names);
        return implode(', ', $names) . ' und ' . $last;
    }
}
