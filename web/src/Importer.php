<?php
declare(strict_types=1);

namespace TonneTorte;

/** Übernimmt Termine aus ICS/AWIDO in die Müllarten eines Standorts. */
final class Importer
{
    /** Vorlagen für gängige Müllarten: Schlüssel => [Name, Farbe, Icon, Suchwörter] */
    public const PRESETS = [
        // Grünschnitt zuerst prüfen, damit „Grünrückstände“ nicht bei „grün“ (Bio) landet
        'gruen' => ['Grünschnitt', '#16A34A', '🌳', ['grünschnitt', 'gruenschnitt', 'grünrück', 'gruenrueck', 'baum', 'weihnacht']],
        'restmuell' => ['Restmüll', '#5B6470', '🗑️', ['rest', 'hausmüll', 'hausmuell', 'grau', 'schwarz']],
        'bio' => ['Biotonne', '#8B5E34', '🍂', ['bio', 'grün', 'gruen', 'kompost', 'organ']],
        'papier' => ['Papier', '#2F6FED', '📰', ['papier', 'pappe', 'karton', 'blau']],
        'gelberSack' => ['Gelber Sack', '#F2C230', '🛍️', ['gelb', 'wertstoff', 'leichtverpack', 'lvp', 'plastik']],
        'glas' => ['Glas', '#2E9E6B', '🍾', ['glas']],
        'sperrmuell' => ['Sperrmüll', '#B45309', '🛋️', ['sperr']],
        'schadstoff' => ['Schadstoffmobil', '#DC2626', '☣️', ['schadstoff', 'problem']],
        'sonstiges' => ['Sonstiges', '#7C3AED', '📦', []],
    ];

    private const IGNORED = ['repair', 'café', 'cafe', 'feiertag', 'sprechstunde'];

    public static function guessPreset(string $summary): string
    {
        $lower = mb_strtolower($summary);
        foreach (self::PRESETS as $key => $preset) {
            foreach ($preset[3] as $word) {
                if (str_contains($lower, $word)) {
                    return $key;
                }
            }
        }
        return 'sonstiges';
    }

    /**
     * Schlägt pro Titel ein Ziel vor: ['summary', 'count', 'target' => 'ignore' | 'existing:<id>' | 'new:<preset>']
     * @param array<int, array{summary: string, date: string}> $events
     */
    public static function suggestMappings(array $events, ?int $locationId): array
    {
        $existing = $locationId === null ? [] : Events::wasteTypes($locationId);
        $counts = [];
        foreach ($events as $event) {
            $counts[$event['summary']] = ($counts[$event['summary']] ?? 0) + 1;
        }
        ksort($counts);
        $mappings = [];
        foreach ($counts as $summary => $count) {
            $lower = mb_strtolower($summary);
            $target = null;
            foreach (self::IGNORED as $word) {
                if (str_contains($lower, $word)) {
                    $target = 'ignore';
                    break;
                }
            }
            if ($target === null) {
                foreach ($existing as $type) {
                    if ($type['source_key'] === $summary) {
                        $target = 'existing:' . $type['id'];
                        break;
                    }
                }
            }
            if ($target === null) {
                foreach ($existing as $type) {
                    if (mb_strtolower($type['name']) === $lower) {
                        $target = 'existing:' . $type['id'];
                        break;
                    }
                }
            }
            if ($target === null) {
                $preset = self::guessPreset($summary);
                foreach ($existing as $type) {
                    if ($type['source_key'] === null && $preset !== 'sonstiges'
                        && mb_strtolower($type['name']) === mb_strtolower(self::PRESETS[$preset][0])) {
                        $target = 'existing:' . $type['id'];
                        break;
                    }
                }
                $target ??= 'new:' . $preset;
            }
            $mappings[] = ['summary' => $summary, 'count' => $count, 'target' => $target];
        }
        return $mappings;
    }

    /**
     * Schreibt die Termine laut Zuordnung. $replace = true ersetzt bisherige Einzeltermine (Abgleich).
     * @return int Anzahl übernommener Termine
     */
    public static function apply(array $events, array $mappings, ?int $locationId, bool $replace): int
    {
        $pdo = Db::pdo();
        $grouped = [];
        foreach ($events as $event) {
            $grouped[$event['summary']][$event['date']] = true;
        }
        $maxOrder = (int) $pdo->query('SELECT COALESCE(MAX(sort_order), -1) FROM waste_types' .
            ($locationId === null ? ' WHERE location_id IS NULL' : ' WHERE location_id = ' . (int) $locationId))->fetchColumn();
        $count = 0;

        $pdo->beginTransaction();
        try {
            foreach ($mappings as $mapping) {
                $summary = (string) $mapping['summary'];
                $target = (string) $mapping['target'];
                $dates = array_keys($grouped[$summary] ?? []);
                if ($dates === [] || $target === 'ignore') {
                    continue;
                }
                if (str_starts_with($target, 'existing:')) {
                    $typeId = (int) substr($target, 9);
                } else {
                    $presetKey = substr($target, 4);
                    $preset = self::PRESETS[$presetKey] ?? self::PRESETS['sonstiges'];
                    $stmt = $pdo->prepare('INSERT INTO waste_types (location_id, name, color, icon, sort_order, source_key)
                        VALUES (?, ?, ?, ?, ?, ?)');
                    $stmt->execute([$locationId, $summary, $preset[1], $preset[2], ++$maxOrder, $summary]);
                    $typeId = (int) $pdo->lastInsertId();
                }
                $pdo->prepare('UPDATE waste_types SET source_key = COALESCE(source_key, ?) WHERE id = ?')->execute([$summary, $typeId]);
                if ($replace) {
                    $pdo->prepare('UPDATE waste_types SET interval_weeks = 0 WHERE id = ?')->execute([$typeId]);
                    // Ausgesetzte Termine bleiben erhalten, damit ein wöchentlicher Abgleich
                    // manuelle Feiertagsregelungen nicht wieder überschreibt.
                    $pdo->prepare('DELETE FROM pickup_dates WHERE waste_type_id = ?')->execute([$typeId]);
                }
                $insert = $pdo->prepare('INSERT OR IGNORE INTO pickup_dates (waste_type_id, date) VALUES (?, ?)');
                foreach ($dates as $date) {
                    $insert->execute([$typeId, $date]);
                    $count++;
                }
            }
            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
        return $count;
    }

    /** Lädt die Termine eines Standorts aus seiner Online-Quelle und ersetzt sie. */
    public static function sync(array $location): int
    {
        $events = match ($location['source_kind']) {
            'awido' => Awido::pickups((string) $location['awido_customer'], (string) $location['awido_oid']),
            'icsurl' => Ics::parse(Http::get((string) $location['ics_url'])),
            default => [],
        };
        if ($location['source_kind'] === 'manual') {
            return 0;
        }
        if ($events === []) {
            throw new \RuntimeException('Die Quelle hat keine Termine geliefert.');
        }
        $mappings = self::suggestMappings($events, (int) $location['id']);
        $count = self::apply($events, $mappings, (int) $location['id'], true);
        Db::pdo()->prepare('UPDATE locations SET last_sync_at = ?, last_sync_message = ? WHERE id = ?')
            ->execute([Db::now(), "{$count} Termine übernommen", $location['id']]);
        return $count;
    }

    public static function canSync(array $location): bool
    {
        return match ($location['source_kind']) {
            'awido' => !empty($location['awido_customer']) && !empty($location['awido_oid']),
            'icsurl' => !empty($location['ics_url']) && filter_var($location['ics_url'], FILTER_VALIDATE_URL) !== false,
            default => false,
        };
    }
}
