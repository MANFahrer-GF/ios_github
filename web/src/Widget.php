<?php
declare(strict_types=1);

namespace TonneTorte;

/** Kompakte JSON-Daten für Widgets (Scriptable) – nächste Abholungen und Geburtstage. */
final class Widget
{
    public static function data(?int $locationId = null, int $days = 30): array
    {
        $today = date('Y-m-d');
        $pickups = [];
        $birthdays = [];
        $locationCount = (int) Db::pdo()->query('SELECT COUNT(*) FROM locations')->fetchColumn();

        foreach (Events::upcomingByDay($days, $locationId) as $day) {
            $items = [];
            foreach ($day['events'] as $event) {
                if ($event['kind'] === 'birthday') {
                    $birthdays[] = [
                        'date' => $event['date'],
                        'days' => self::daysUntil($today, $event['date']),
                        'name' => $event['title'],
                        'age' => $event['age'],
                        'color' => $event['color'],
                        'initials' => $event['initials'],
                    ];
                    continue;
                }
                $items[] = [
                    'title' => $event['title'],
                    'icon' => $event['icon'],
                    'color' => $event['color'],
                    'location' => $locationCount > 1 ? $event['location'] : null,
                ];
            }
            if ($items !== []) {
                $pickups[] = [
                    'date' => $day['date'],
                    'days' => self::daysUntil($today, $day['date']),
                    'label' => self::countdown(self::daysUntil($today, $day['date'])),
                    'items' => $items,
                ];
            }
        }

        return [
            'app' => Config::get()['app_name'],
            'today' => $today,
            'generated_at' => Db::now(),
            'url' => Config::baseUrl() . '/',
            'pickups' => $pickups,
            'birthdays' => $birthdays,
        ];
    }

    private static function daysUntil(string $from, string $to): int
    {
        return (int) (new \DateTimeImmutable($from))->diff(new \DateTimeImmutable($to))->format('%r%a');
    }

    private static function countdown(int $days): string
    {
        return match (true) {
            $days === 0 => 'Heute',
            $days === 1 => 'Morgen',
            $days === 2 => 'Übermorgen',
            default => "in {$days} Tagen",
        };
    }
}
