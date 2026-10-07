<?php
declare(strict_types=1);

namespace TonneTorte;

/** Erzeugt den ICS-Abo-Feed für den iOS-/macOS-Kalender – inklusive Alarmen. */
final class Feed
{
    public static function token(): string
    {
        $token = Db::setting('feed_token');
        if ($token === null) {
            $token = Db::randomToken(18);
            Db::setSetting('feed_token', $token);
        }
        return $token;
    }

    public static function regenerateToken(): string
    {
        $token = Db::randomToken(18);
        Db::setSetting('feed_token', $token);
        return $token;
    }

    public static function build(): string
    {
        $settings = Db::reminderSettings();
        $from = (new \DateTimeImmutable('-30 days'))->format('Y-m-d');
        $to = (new \DateTimeImmutable('+400 days'))->format('Y-m-d');
        $locationCount = (int) Db::pdo()->query('SELECT COUNT(*) FROM locations')->fetchColumn();

        $wasteAlarms = [];
        if ($settings['evening_enabled']) {
            $wasteAlarms[] = Ics::trigger(self::minutes($settings['evening_time']) - 1440);
        }
        if ($settings['morning_enabled']) {
            $wasteAlarms[] = Ics::trigger(self::minutes($settings['morning_time']));
        }
        $birthdayMinutes = self::minutes($settings['birthday_time']);
        $people = [];
        foreach (Events::people() as $person) {
            $people[$person['id']] = $person;
        }

        $events = [];
        foreach (Events::range($from, $to) as $event) {
            if ($event['kind'] === 'waste') {
                $summary = $event['icon'] . ' ' . $event['title'];
                if ($locationCount > 1 && $event['location']) {
                    $summary .= ' (' . $event['location'] . ')';
                }
                $events[] = [
                    'uid' => $event['id'] . '@tonneundtorte',
                    'date' => $event['date'],
                    'summary' => $summary,
                    'description' => 'Abholung' . ($event['location'] ? ' in ' . $event['location'] : ''),
                    'alarms' => $event['reminders'] ? $wasteAlarms : [],
                ];
            } else {
                $person = $people[$event['person_id']] ?? null;
                $alarms = [];
                if ($event['reminders']) {
                    $alarms[] = Ics::trigger($birthdayMinutes);
                    if ($person && $person['remind_days_before'] > 0) {
                        $alarms[] = Ics::trigger($birthdayMinutes - $person['remind_days_before'] * 1440);
                    }
                }
                $events[] = [
                    'uid' => $event['id'] . '@tonneundtorte',
                    'date' => $event['date'],
                    'summary' => '🎂 ' . $event['title'] . ($event['age'] !== null ? " ({$event['age']})" : ''),
                    'description' => $person['notes'] ?? '',
                    'alarms' => $alarms,
                ];
            }
        }
        return Ics::build('Tonne & Torte', $events);
    }

    private static function minutes(string $time): int
    {
        [$h, $m] = array_map('intval', explode(':', $time . ':0'));
        return $h * 60 + $m;
    }
}
