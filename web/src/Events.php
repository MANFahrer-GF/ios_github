<?php
declare(strict_types=1);

namespace TonneTorte;

use PDO;

/** Berechnet Abholtermine und Geburtstage aus der Datenbank. Datumsangaben als Y-m-d. */
final class Events
{
    /** @return array<int, array<string, mixed>> Müllarten inkl. Standortname */
    public static function wasteTypes(?int $locationId = null, bool $onlyActive = false): array
    {
        $sql = 'SELECT w.*, l.name AS location_name, l.color AS location_color
                FROM waste_types w LEFT JOIN locations l ON l.id = w.location_id';
        $where = [];
        $params = [];
        if ($locationId !== null) {
            $where[] = 'w.location_id = ?';
            $params[] = $locationId;
        }
        if ($onlyActive) {
            $where[] = 'w.active = 1';
        }
        if ($where !== []) {
            $sql .= ' WHERE ' . implode(' AND ', $where);
        }
        $sql .= ' ORDER BY l.sort_order, w.sort_order, w.name';
        $stmt = Db::pdo()->prepare($sql);
        $stmt->execute($params);
        $types = $stmt->fetchAll();
        foreach ($types as &$type) {
            $type['id'] = (int) $type['id'];
            $type['location_id'] = $type['location_id'] === null ? null : (int) $type['location_id'];
            $type['active'] = (bool) $type['active'];
            $type['reminders'] = (bool) $type['reminders'];
            $type['interval_weeks'] = (int) $type['interval_weeks'];
            $type['sort_order'] = (int) $type['sort_order'];
            $type['explicit_dates'] = self::dates('pickup_dates', $type['id']);
            $type['skipped_dates'] = self::dates('skipped_dates', $type['id']);
        }
        return $types;
    }

    /** @return string[] */
    public static function dates(string $table, int $wasteTypeId): array
    {
        $stmt = Db::pdo()->prepare("SELECT date FROM {$table} WHERE waste_type_id = ? ORDER BY date");
        $stmt->execute([$wasteTypeId]);
        return array_map('strval', $stmt->fetchAll(PDO::FETCH_COLUMN));
    }

    /** Alle Abholtermine einer Müllart zwischen $from und $to (inklusive). @return string[] */
    public static function pickupDates(array $type, string $from, string $to): array
    {
        if ($from > $to) {
            return [];
        }
        $days = [];
        if ($type['interval_weeks'] > 0 && !empty($type['anchor_date'])) {
            $stepDays = $type['interval_weeks'] * 7;
            $anchor = new \DateTimeImmutable($type['anchor_date']);
            $start = new \DateTimeImmutable($from);
            $diff = (int) $anchor->diff($start)->format('%r%a');
            $firstStep = $diff <= 0 ? 0 : (int) ceil($diff / $stepDays);
            $current = $anchor->modify('+' . ($firstStep * $stepDays) . ' days');
            $guard = 0;
            while ($current->format('Y-m-d') <= $to && $guard++ < 1000) {
                $days[$current->format('Y-m-d')] = true;
                $current = $current->modify("+{$stepDays} days");
            }
        }
        foreach ($type['explicit_dates'] as $date) {
            if ($date >= $from && $date <= $to) {
                $days[$date] = true;
            }
        }
        foreach ($type['skipped_dates'] as $date) {
            unset($days[$date]);
        }
        $result = array_keys($days);
        sort($result);
        return $result;
    }

    public static function nextPickup(array $type, ?string $from = null): ?string
    {
        $from ??= date('Y-m-d');
        $to = (new \DateTimeImmutable($from))->modify('+2 years')->format('Y-m-d');
        $dates = self::pickupDates($type, $from, $to);
        return $dates[0] ?? null;
    }

    // ----- Geburtstage --------------------------------------------------------

    public static function people(): array
    {
        $people = Db::pdo()->query('SELECT * FROM people ORDER BY name')->fetchAll();
        foreach ($people as &$person) {
            $person['id'] = (int) $person['id'];
            $person['day'] = (int) $person['day'];
            $person['month'] = (int) $person['month'];
            $person['year'] = $person['year'] === null ? null : (int) $person['year'];
            $person['reminders'] = (bool) $person['reminders'];
            $person['remind_days_before'] = (int) $person['remind_days_before'];
            $person['initials'] = self::initials($person['name']);
        }
        return $people;
    }

    public static function initials(string $name): string
    {
        $parts = array_slice(preg_split('/\s+/', trim($name)) ?: [], 0, 2);
        $letters = '';
        foreach ($parts as $part) {
            if ($part !== '') {
                $letters .= mb_strtoupper(mb_substr($part, 0, 1));
            }
        }
        return $letters === '' ? '?' : $letters;
    }

    /** Geburtstag im Jahr $year; 29.2. wird in Nicht-Schaltjahren am 28.2. gefeiert. */
    public static function birthdayInYear(array $person, int $year): string
    {
        $day = $person['day'];
        if ($person['month'] === 2 && $day === 29 && !checkdate(2, 29, $year)) {
            $day = 28;
        }
        return sprintf('%04d-%02d-%02d', $year, $person['month'], $day);
    }

    public static function nextBirthday(array $person, ?string $from = null): string
    {
        $from ??= date('Y-m-d');
        $year = (int) substr($from, 0, 4);
        $thisYear = self::birthdayInYear($person, $year);
        return $thisYear >= $from ? $thisYear : self::birthdayInYear($person, $year + 1);
    }

    public static function age(array $person, string $date): ?int
    {
        if ($person['year'] === null) {
            return null;
        }
        $age = (int) substr($date, 0, 4) - $person['year'];
        return $age >= 0 ? $age : null;
    }

    // ----- Kombiniert ---------------------------------------------------------

    /**
     * Alle Termine (Müll + Geburtstage) im Zeitraum, sortiert.
     * @return array<int, array<string, mixed>>
     */
    public static function range(string $from, string $to, ?int $locationId = null): array
    {
        $events = [];
        foreach (self::wasteTypes($locationId, true) as $type) {
            foreach (self::pickupDates($type, $from, $to) as $date) {
                $events[] = [
                    'id' => 'waste-' . $type['id'] . '-' . $date,
                    'kind' => 'waste',
                    'date' => $date,
                    'title' => $type['name'],
                    'subtitle' => $type['location_name'] ?? 'Abholung',
                    'color' => $type['color'],
                    'icon' => $type['icon'],
                    'location' => $type['location_name'],
                    'location_id' => $type['location_id'],
                    'waste_type_id' => $type['id'],
                    'reminders' => $type['reminders'],
                ];
            }
        }
        $fromYear = (int) substr($from, 0, 4);
        $toYear = (int) substr($to, 0, 4);
        foreach (self::people() as $person) {
            for ($year = $fromYear; $year <= $toYear; $year++) {
                $date = self::birthdayInYear($person, $year);
                if ($date >= $from && $date <= $to) {
                    $age = self::age($person, $date);
                    $events[] = [
                        'id' => 'bday-' . $person['id'] . '-' . $date,
                        'kind' => 'birthday',
                        'date' => $date,
                        'title' => $person['name'],
                        'subtitle' => $age === null ? 'Geburtstag' : "wird {$age}",
                        'color' => $person['color'],
                        'icon' => '🎂',
                        'age' => $age,
                        'person_id' => $person['id'],
                        'initials' => $person['initials'],
                        'reminders' => $person['reminders'],
                    ];
                }
            }
        }
        usort($events, function ($a, $b) {
            return strcmp($a['date'], $b['date'])
                ?: strcmp($a['kind'], $b['kind']) * -1
                ?: strcmp($a['title'], $b['title']);
        });
        return $events;
    }

    /** Termine der nächsten $days Tage, gruppiert nach Tag. */
    public static function upcomingByDay(int $days, ?int $locationId = null): array
    {
        $from = date('Y-m-d');
        $to = (new \DateTimeImmutable($from))->modify("+{$days} days")->format('Y-m-d');
        $grouped = [];
        foreach (self::range($from, $to, $locationId) as $event) {
            $grouped[$event['date']][] = $event;
        }
        $result = [];
        foreach ($grouped as $date => $events) {
            $result[] = ['date' => $date, 'events' => $events];
        }
        return $result;
    }
}
