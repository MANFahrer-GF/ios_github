<?php
declare(strict_types=1);

namespace TonneTorte;

/**
 * Minimaler iCalendar-Parser (DTSTART als DATE/DATE-TIME, einfache RRULE) und
 * Generator für den Abo-Feed mit Alarmen.
 */
final class Ics
{
    /** @return array<int, array{summary: string, date: string}> Datum als Y-m-d */
    public static function parse(string $text): array
    {
        $lines = self::unfold($text);
        $events = [];
        $inEvent = false;
        $summary = '';
        $dtstart = null;
        $rrule = null;

        foreach ($lines as $line) {
            if (str_starts_with($line, 'BEGIN:VEVENT')) {
                $inEvent = true;
                $summary = '';
                $dtstart = null;
                $rrule = null;
                continue;
            }
            if (str_starts_with($line, 'END:VEVENT')) {
                if ($inEvent && $dtstart !== null) {
                    $name = $summary === '' ? 'Unbenannt' : $summary;
                    foreach (self::expand($dtstart, $rrule) as $date) {
                        $events[$name . '|' . $date] = ['summary' => $name, 'date' => $date];
                    }
                }
                $inEvent = false;
                continue;
            }
            if (!$inEvent) {
                continue;
            }
            [$key, $params, $value] = self::split($line);
            switch ($key) {
                case 'SUMMARY':
                    $summary = self::unescape($value);
                    break;
                case 'DTSTART':
                    $dtstart = self::parseDate($value, $params);
                    break;
                case 'RRULE':
                    $rrule = $value;
                    break;
            }
        }

        $events = array_values($events);
        usort($events, fn($a, $b) => strcmp($a['date'], $b['date']) ?: strcmp($a['summary'], $b['summary']));
        return $events;
    }

    /** @return string[] */
    private static function unfold(string $text): array
    {
        $raw = explode("\n", str_replace("\r\n", "\n", $text));
        $result = [];
        foreach ($raw as $line) {
            if ($line !== '' && ($line[0] === ' ' || $line[0] === "\t") && $result !== []) {
                $result[count($result) - 1] .= substr($line, 1);
            } else {
                $result[] = $line;
            }
        }
        return $result;
    }

    /** @return array{0: string, 1: array<string, string>, 2: string} */
    private static function split(string $line): array
    {
        $colon = strpos($line, ':');
        if ($colon === false) {
            return [strtoupper($line), [], ''];
        }
        $head = substr($line, 0, $colon);
        $value = substr($line, $colon + 1);
        $parts = explode(';', $head);
        $key = strtoupper(array_shift($parts));
        $params = [];
        foreach ($parts as $part) {
            $kv = explode('=', $part, 2);
            if (count($kv) === 2) {
                $params[strtoupper($kv[0])] = $kv[1];
            }
        }
        return [$key, $params, $value];
    }

    private static function unescape(string $value): string
    {
        return trim(str_replace(['\\n', '\\N', '\\,', '\;', '\\\\'], [' ', ' ', ',', ';', '\\'], $value));
    }

    /** Wandelt 20260107 / 20260107T060000 / 20260106T230000Z in ein lokales Y-m-d um. */
    public static function parseDate(string $value, array $params = []): ?string
    {
        $value = trim($value);
        if (strlen($value) < 8 || !ctype_digit(substr($value, 0, 8))) {
            return null;
        }
        $y = (int) substr($value, 0, 4);
        $m = (int) substr($value, 4, 2);
        $d = (int) substr($value, 6, 2);
        if (!checkdate($m, $d, $y)) {
            return null;
        }
        if (strlen($value) >= 15 && $value[8] === 'T') {
            $h = (int) substr($value, 9, 2);
            $i = (int) substr($value, 11, 2);
            $s = (int) substr($value, 13, 2);
            $isUtc = str_ends_with($value, 'Z');
            $tz = $isUtc ? new \DateTimeZone('UTC') : null;
            if (!$isUtc && isset($params['TZID'])) {
                try {
                    $tz = new \DateTimeZone($params['TZID']);
                } catch (\Throwable) {
                    $tz = null;
                }
            }
            $dt = new \DateTimeImmutable(sprintf('%04d-%02d-%02d %02d:%02d:%02d', $y, $m, $d, $h, $i, $s), $tz);
            return $dt->setTimezone(new \DateTimeZone(date_default_timezone_get()))->format('Y-m-d');
        }
        return sprintf('%04d-%02d-%02d', $y, $m, $d);
    }

    /** @return string[] */
    private static function expand(string $start, ?string $rrule): array
    {
        if ($rrule === null || $rrule === '') {
            return [$start];
        }
        $fields = [];
        foreach (explode(';', $rrule) as $part) {
            $kv = explode('=', $part, 2);
            if (count($kv) === 2) {
                $fields[strtoupper($kv[0])] = $kv[1];
            }
        }
        $interval = max(1, (int) ($fields['INTERVAL'] ?? 1));
        $stepDays = match (strtoupper($fields['FREQ'] ?? '')) {
            'DAILY' => $interval,
            'WEEKLY' => 7 * $interval,
            default => null,
        };
        if ($stepDays === null) {
            return [$start];
        }
        $maxCount = min((int) ($fields['COUNT'] ?? 200) ?: 200, 400);
        $until = isset($fields['UNTIL']) ? self::parseDate($fields['UNTIL']) : null;
        $untilDate = new \DateTimeImmutable($until ?? (new \DateTimeImmutable($start))->modify('+2 years')->format('Y-m-d'));

        $dates = [];
        $current = new \DateTimeImmutable($start);
        while (count($dates) < $maxCount && $current <= $untilDate) {
            $dates[] = $current->format('Y-m-d');
            $current = $current->modify("+{$stepDays} days");
        }
        return $dates;
    }

    // ----- Feed-Erzeugung -------------------------------------------------------

    /**
     * @param array<int, array{uid: string, date: string, summary: string, description?: string, alarms?: string[]}> $events
     *        alarms = ISO-8601-Dauern relativ zum Tagesbeginn, z. B. "-PT5H" (19 Uhr am Vortag), "PT7H"
     */
    public static function build(string $name, array $events): string
    {
        $out = [
            'BEGIN:VCALENDAR',
            'VERSION:2.0',
            'PRODID:-//Tonne und Torte//Web//DE',
            'CALSCALE:GREGORIAN',
            'METHOD:PUBLISH',
            'X-WR-CALNAME:' . self::escape($name),
            'X-PUBLISHED-TTL:PT6H',
            'REFRESH-INTERVAL;VALUE=DURATION:PT6H',
        ];
        $stamp = gmdate('Ymd\THis\Z');
        foreach ($events as $event) {
            $date = str_replace('-', '', $event['date']);
            $next = (new \DateTimeImmutable($event['date']))->modify('+1 day')->format('Ymd');
            $out[] = 'BEGIN:VEVENT';
            $out[] = 'UID:' . $event['uid'];
            $out[] = 'DTSTAMP:' . $stamp;
            $out[] = 'DTSTART;VALUE=DATE:' . $date;
            $out[] = 'DTEND;VALUE=DATE:' . $next;
            $out[] = 'SUMMARY:' . self::escape($event['summary']);
            if (!empty($event['description'])) {
                $out[] = 'DESCRIPTION:' . self::escape($event['description']);
            }
            $out[] = 'TRANSP:TRANSPARENT';
            foreach ($event['alarms'] ?? [] as $trigger) {
                $out[] = 'BEGIN:VALARM';
                $out[] = 'ACTION:DISPLAY';
                $out[] = 'DESCRIPTION:' . self::escape($event['summary']);
                $out[] = 'TRIGGER:' . $trigger;
                $out[] = 'END:VALARM';
            }
            $out[] = 'END:VEVENT';
        }
        $out[] = 'END:VCALENDAR';
        return implode("\r\n", array_map([self::class, 'fold'], $out)) . "\r\n";
    }

    private static function escape(string $value): string
    {
        return str_replace(["\\", ";", ",", "\n"], ["\\\\", "\;", "\\,", "\\n"], $value);
    }

    /** Zeilen länger als 75 Oktette falten (RFC 5545). */
    private static function fold(string $line): string
    {
        if (strlen($line) <= 75) {
            return $line;
        }
        $pieces = [];
        $current = '';
        foreach (mb_str_split($line) as $char) {
            if (strlen($current) + strlen($char) > ($pieces === [] ? 75 : 74)) {
                $pieces[] = $current;
                $current = '';
            }
            $current .= $char;
        }
        $pieces[] = $current;
        return implode("\r\n ", $pieces);
    }

    /** Dauer-String für „x Stunden vor/nach Tagesbeginn“, z. B. hoursOffset(-5) = -PT5H. */
    public static function trigger(int $minutesFromMidnight): string
    {
        $sign = $minutesFromMidnight < 0 ? '-' : '';
        $abs = abs($minutesFromMidnight);
        $days = intdiv($abs, 1440);
        $hours = intdiv($abs % 1440, 60);
        $minutes = $abs % 60;
        $out = $sign . 'P';
        if ($days > 0) {
            $out .= $days . 'D';
        }
        if ($hours > 0 || $minutes > 0 || $days === 0) {
            $out .= 'T';
            if ($hours > 0) {
                $out .= $hours . 'H';
            }
            if ($minutes > 0 || ($hours === 0 && $days === 0)) {
                $out .= $minutes . 'M';
            }
        }
        return $out;
    }
}
