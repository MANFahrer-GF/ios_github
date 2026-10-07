<?php
declare(strict_types=1);

namespace TonneTorte;

/** Standard-Standorte Gifhorn und Kuhlhausen mit gebündelten Kalendern. */
final class Seed
{
    public const GIFHORN_AWIDO_CUSTOMER = 'gifhorn';
    public const GIFHORN_AWIDO_OID = '968d9cf6-f840-4229-9b98-6fbcc09828a9';
    public const KUHLHAUSEN_ICS = 'https://landkreis-stendal.abfall-app.net/download?system=ical&period=2&district=1465&categories=&view=month';

    public static function seedIfEmpty(): void
    {
        $count = (int) Db::pdo()->query('SELECT COUNT(*) FROM locations')->fetchColumn();
        if ($count === 0) {
            self::insertDefaults();
        }
    }

    public static function insertDefaults(): array
    {
        $pdo = Db::pdo();
        $existing = array_map('strval', $pdo->query('SELECT name FROM locations')->fetchAll(\PDO::FETCH_COLUMN));
        $created = [];
        $seedDir = dirname(__DIR__) . '/seed';

        if (!in_array('Gifhorn', $existing, true)) {
            $stmt = $pdo->prepare('INSERT INTO locations (name, address, color, icon, sort_order, source_kind, awido_customer, awido_oid, awido_label, last_sync_message)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
            $stmt->execute(['Gifhorn', 'Steinstraße 1, 38518 Gifhorn', '#2F6FED', '🏠', 0, 'awido',
                self::GIFHORN_AWIDO_CUSTOMER, self::GIFHORN_AWIDO_OID, 'Gifhorn, Steinstraße',
                'Gebündelter Kalender 2026 – bitte online aktualisieren']);
            $id = (int) $pdo->lastInsertId();
            self::importSeed($id, $seedDir . '/seed_gifhorn.ics');
            $created[] = 'Gifhorn';
        }

        if (!in_array('Kuhlhausen', $existing, true)) {
            $stmt = $pdo->prepare('INSERT INTO locations (name, address, color, icon, sort_order, source_kind, ics_url, last_sync_message)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
            $stmt->execute(['Kuhlhausen', 'Havelberger Straße 18, 39539 Hansestadt Havelberg', '#2E9E6B', '🏡', 1, 'icsurl',
                self::KUHLHAUSEN_ICS, 'Gebündelter Kalender der Abfall-App Landkreis Stendal (Tour Garz/Jederitz/Kuhlhausen/Warnau)']);
            $id = (int) $pdo->lastInsertId();
            self::importSeed($id, $seedDir . '/seed_kuhlhausen.ics');
            $created[] = 'Kuhlhausen';
        }
        return $created;
    }

    private static function importSeed(int $locationId, string $file): void
    {
        if (!is_file($file)) {
            return;
        }
        $events = Ics::parse((string) file_get_contents($file));
        $mappings = Importer::suggestMappings($events, $locationId);
        Importer::apply($events, $mappings, $locationId, true);
    }

    public static function insertDemoBirthdays(): void
    {
        $pdo = Db::pdo();
        if ((int) $pdo->query('SELECT COUNT(*) FROM people')->fetchColumn() > 0) {
            return;
        }
        $tomorrow = new \DateTimeImmutable('tomorrow');
        $inTwoWeeks = new \DateTimeImmutable('+14 days');
        $stmt = $pdo->prepare('INSERT INTO people (name, day, month, year, color) VALUES (?, ?, ?, ?, ?)');
        $stmt->execute(['Oma Erika', (int) $tomorrow->format('j'), (int) $tomorrow->format('n'), 1948, '#EC4899']);
        $stmt->execute(['Max Mustermann', (int) $inTwoWeeks->format('j'), (int) $inTwoWeeks->format('n'), 1990, '#2F6FED']);
        $stmt->execute(['Lena', 24, 12, null, '#2E9E6B']);
    }
}
