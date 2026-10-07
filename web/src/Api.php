<?php
declare(strict_types=1);

namespace TonneTorte;

/** JSON-API für die Web-App. Aufruf: api.php?action=… (GET) bzw. POST mit JSON-Body. */
final class Api
{
    public static function handle(): void
    {
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        Auth::start();

        $action = (string) ($_GET['action'] ?? '');
        $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
        $input = [];
        if ($method === 'POST') {
            if (($_SERVER['HTTP_X_REQUESTED_WITH'] ?? '') !== 'TonneTorte') {
                self::fail('Ungültige Anfrage.', 400);
            }
            $raw = file_get_contents('php://input') ?: '';
            $input = $raw !== '' ? (json_decode($raw, true) ?? []) : [];
        }

        try {
            if (!Auth::isConfigured()) {
                if ($action === 'setup' && $method === 'POST') {
                    self::setup($input);
                    return;
                }
                self::fail('Bitte zuerst ein Passwort festlegen.', 428, ['setup' => true]);
            }
            if (!Auth::isLoggedIn()) {
                if ($action === 'login' && $method === 'POST') {
                    if (!Auth::login((string) ($input['password'] ?? ''))) {
                        self::fail('Falsches Passwort.', 401);
                    }
                    self::ok(['ok' => true]);
                    return;
                }
                self::fail('Nicht angemeldet.', 401, ['login' => true]);
            }

            Db::setSetting('base_url', Config::baseUrl());
            date_default_timezone_set(Db::reminderSettings()['timezone']);

            $result = self::dispatch($action, $method, $input);
            self::ok($result);
        } catch (\InvalidArgumentException $e) {
            self::fail($e->getMessage(), 400);
        } catch (\Throwable $e) {
            self::fail($e->getMessage(), 500);
        }
    }

    private static function dispatch(string $action, string $method, array $input): mixed
    {
        $pdo = Db::pdo();
        switch ($action) {
            // ----- Lesen -----------------------------------------------------
            case 'bootstrap':
                return self::bootstrap();
            case 'upcoming':
                return Events::upcomingByDay(max(1, min(400, (int) ($_GET['days'] ?? 60))), self::locationFilter());
            case 'range':
                return Events::range(self::date($_GET['from'] ?? ''), self::date($_GET['to'] ?? ''), self::locationFilter());
            case 'wastetype':
                return self::wasteTypeDetail((int) ($_GET['id'] ?? 0));
            case 'reminders.planned':
                return Reminders::planned(30);

            // ----- Standorte -------------------------------------------------
            case 'location.save':
                return self::saveLocation($input);
            case 'location.delete':
                $pdo->prepare('DELETE FROM locations WHERE id = ?')->execute([(int) ($input['id'] ?? 0)]);
                return ['ok' => true];
            case 'location.sync':
                $location = self::location((int) ($input['id'] ?? 0));
                $count = Importer::sync($location);
                return ['count' => $count, 'location' => self::location((int) $location['id'])];
            case 'sync.all':
                $messages = [];
                foreach ($pdo->query('SELECT * FROM locations')->fetchAll() as $location) {
                    if (Importer::canSync($location)) {
                        try {
                            $messages[] = $location['name'] . ': ' . Importer::sync($location) . ' Termine';
                        } catch (\Throwable $e) {
                            $messages[] = $location['name'] . ': Fehler – ' . $e->getMessage();
                        }
                    }
                }
                return ['messages' => $messages];

            // ----- Müllarten ------------------------------------------------
            case 'wastetype.save':
                return self::saveWasteType($input);
            case 'wastetype.delete':
                $pdo->prepare('DELETE FROM waste_types WHERE id = ?')->execute([(int) ($input['id'] ?? 0)]);
                return ['ok' => true];
            case 'pickup.add':
                $pdo->prepare('INSERT OR IGNORE INTO pickup_dates (waste_type_id, date) VALUES (?, ?)')
                    ->execute([(int) $input['id'], self::date($input['date'] ?? '')]);
                $pdo->prepare('DELETE FROM skipped_dates WHERE waste_type_id = ? AND date = ?')
                    ->execute([(int) $input['id'], self::date($input['date'] ?? '')]);
                return self::wasteTypeDetail((int) $input['id']);
            case 'pickup.skip':
                self::skipDate((int) $input['id'], self::date($input['date'] ?? ''));
                return self::wasteTypeDetail((int) $input['id']);
            case 'pickup.unskip':
                $pdo->prepare('DELETE FROM skipped_dates WHERE waste_type_id = ? AND date = ?')
                    ->execute([(int) $input['id'], self::date($input['date'] ?? '')]);
                return self::wasteTypeDetail((int) $input['id']);
            case 'pickup.move':
                self::skipDate((int) $input['id'], self::date($input['from'] ?? ''));
                $pdo->prepare('INSERT OR IGNORE INTO pickup_dates (waste_type_id, date) VALUES (?, ?)')
                    ->execute([(int) $input['id'], self::date($input['to'] ?? '')]);
                $pdo->prepare('DELETE FROM skipped_dates WHERE waste_type_id = ? AND date = ?')
                    ->execute([(int) $input['id'], self::date($input['to'] ?? '')]);
                return self::wasteTypeDetail((int) $input['id']);

            // ----- Geburtstage ---------------------------------------------
            case 'person.save':
                return self::savePerson($input);
            case 'person.delete':
                $pdo->prepare('DELETE FROM people WHERE id = ?')->execute([(int) ($input['id'] ?? 0)]);
                return ['ok' => true];

            // ----- Einstellungen --------------------------------------------
            case 'settings.save':
                foreach (['evening_enabled', 'morning_enabled'] as $key) {
                    if (array_key_exists($key, $input)) {
                        Db::setSetting($key, !empty($input[$key]) ? '1' : '0');
                    }
                }
                foreach (['evening_time', 'morning_time', 'birthday_time'] as $key) {
                    if (isset($input[$key]) && preg_match('/^\d{2}:\d{2}$/', (string) $input[$key])) {
                        Db::setSetting($key, (string) $input[$key]);
                    }
                }
                if (isset($input['timezone']) && in_array($input['timezone'], \DateTimeZone::listIdentifiers(), true)) {
                    Db::setSetting('timezone', (string) $input['timezone']);
                }
                return Db::reminderSettings();
            case 'password.change':
                $hash = Db::setting('password_hash') ?? '';
                if (!password_verify((string) ($input['current'] ?? ''), $hash)) {
                    throw new \InvalidArgumentException('Aktuelles Passwort ist falsch.');
                }
                if (strlen((string) ($input['new'] ?? '')) < 6) {
                    throw new \InvalidArgumentException('Neues Passwort: mindestens 6 Zeichen.');
                }
                Auth::setPassword((string) $input['new']);
                return ['ok' => true];
            case 'feed.regenerate':
                return ['feed_url' => self::feedUrl(Feed::regenerateToken())];
            case 'logout':
                Auth::logout();
                return ['ok' => true];

            // ----- AWIDO-Assistent -----------------------------------------
            case 'awido.places':
                return Awido::places(self::customer($_GET['customer'] ?? ''));
            case 'awido.streets':
                return Awido::streets(self::customer($_GET['customer'] ?? ''), (string) ($_GET['oid'] ?? ''));
            case 'awido.housenumbers':
                return Awido::houseNumbers(self::customer($_GET['customer'] ?? ''), (string) ($_GET['oid'] ?? ''));

            // ----- ICS-Import ----------------------------------------------
            case 'ics.preview':
                $text = (string) ($input['text'] ?? '');
                if (strlen($text) > 5 * 1024 * 1024) {
                    throw new \InvalidArgumentException('Datei ist zu groß.');
                }
                $events = Ics::parse($text);
                if ($events === []) {
                    throw new \InvalidArgumentException('In der Datei wurden keine Termine gefunden.');
                }
                $_SESSION['ics_import'] = $events;
                return [
                    'count' => count($events),
                    'from' => $events[0]['date'],
                    'to' => $events[count($events) - 1]['date'],
                    'mappings' => Importer::suggestMappings($events, isset($input['location_id']) ? (int) $input['location_id'] : null),
                ];
            case 'ics.apply':
                $events = $_SESSION['ics_import'] ?? null;
                if (!is_array($events)) {
                    throw new \InvalidArgumentException('Bitte zuerst eine Datei auswählen.');
                }
                $locationId = isset($input['location_id']) && $input['location_id'] !== null ? (int) $input['location_id'] : null;
                $count = Importer::apply($events, (array) ($input['mappings'] ?? []), $locationId, !empty($input['replace']));
                if ($locationId !== null) {
                    $pdo->prepare('UPDATE locations SET last_sync_message = ? WHERE id = ?')->execute(['ICS-Datei importiert', $locationId]);
                }
                unset($_SESSION['ics_import']);
                return ['count' => $count];

            // ----- Push ----------------------------------------------------
            case 'push.subscribe':
                Push::subscribe((array) ($input['subscription'] ?? []), $_SERVER['HTTP_USER_AGENT'] ?? '');
                return ['subscriptions' => count(Push::subscriptions())];
            case 'push.unsubscribe':
                Push::unsubscribe((string) ($input['endpoint'] ?? ''));
                return ['subscriptions' => count(Push::subscriptions())];
            case 'push.test':
                return Push::send('Morgen: Gelber Sack', 'So sieht eine Erinnerung von Tonne & Torte aus. 🎉', 'test', Config::baseUrl());
            case 'cron.run':
                return Reminders::runCron();

            // ----- Daten ---------------------------------------------------
            case 'seed.defaults':
                return ['created' => Seed::insertDefaults()];
            case 'seed.demo':
                Seed::insertDemoBirthdays();
                return ['ok' => true];
            case 'data.reset':
                foreach (['pickup_dates', 'skipped_dates', 'waste_types', 'locations', 'people', 'sent_reminders'] as $table) {
                    $pdo->exec("DELETE FROM {$table}");
                }
                return ['ok' => true];
        }
        throw new \InvalidArgumentException('Unbekannte Aktion: ' . $action);
    }

    // ----- Helfer --------------------------------------------------------------

    private static function bootstrap(): array
    {
        $pdo = Db::pdo();
        $locations = $pdo->query('SELECT * FROM locations ORDER BY sort_order, name')->fetchAll();
        $types = Events::wasteTypes();
        foreach ($locations as &$location) {
            $location = self::decorateLocation($location);
            $location['waste_types'] = [];
        }
        unset($location);
        $byLocation = [];
        foreach ($locations as $index => $location) {
            $byLocation[$location['id']] = $index;
        }
        $orphans = [];
        foreach ($types as $type) {
            $type['next'] = Events::nextPickup($type);
            unset($type['explicit_dates'], $type['skipped_dates']);
            if ($type['location_id'] !== null && isset($byLocation[$type['location_id']])) {
                $locations[$byLocation[$type['location_id']]]['waste_types'][] = $type;
            } else {
                $orphans[] = $type;
            }
        }
        $people = Events::people();
        foreach ($people as &$person) {
            $person['next'] = Events::nextBirthday($person);
            $person['age_next'] = Events::age($person, $person['next']);
        }
        unset($person);
        usort($people, fn($a, $b) => strcmp($a['next'], $b['next']));

        $presets = [];
        foreach (Importer::PRESETS as $key => $preset) {
            $presets[] = ['key' => $key, 'name' => $preset[0], 'color' => $preset[1], 'icon' => $preset[2]];
        }

        return [
            'app' => Config::get()['app_name'],
            'base_url' => Config::baseUrl(),
            'today' => date('Y-m-d'),
            'locations' => $locations,
            'orphan_types' => $orphans,
            'people' => $people,
            'settings' => Db::reminderSettings(),
            'feed_url' => self::feedUrl(Feed::token()),
            'push' => [
                'public_key' => Push::vapidKeys()['publicKey'],
                'subscriptions' => count(Push::subscriptions()),
            ],
            'cron' => [
                'last_run' => Db::setting('last_cron_at'),
                'url' => Config::baseUrl() . '/cron.php?token=' . self::cronToken(),
            ],
            'awido_providers' => Awido::PROVIDERS,
            'presets' => $presets,
        ];
    }

    private static function decorateLocation(array $location): array
    {
        $location['id'] = (int) $location['id'];
        $location['sort_order'] = (int) $location['sort_order'];
        $location['can_sync'] = Importer::canSync($location);
        return $location;
    }

    private static function location(int $id): array
    {
        $stmt = Db::pdo()->prepare('SELECT * FROM locations WHERE id = ?');
        $stmt->execute([$id]);
        $location = $stmt->fetch();
        if (!$location) {
            throw new \InvalidArgumentException('Standort nicht gefunden.');
        }
        return self::decorateLocation($location);
    }

    private static function saveLocation(array $input): array
    {
        $pdo = Db::pdo();
        $name = trim((string) ($input['name'] ?? ''));
        if ($name === '') {
            throw new \InvalidArgumentException('Bitte einen Namen angeben.');
        }
        $kind = in_array($input['source_kind'] ?? '', ['manual', 'awido', 'icsurl'], true) ? $input['source_kind'] : 'manual';
        $icsUrl = trim((string) ($input['ics_url'] ?? ''));
        if ($kind === 'icsurl' && $icsUrl !== '' && !filter_var($icsUrl, FILTER_VALIDATE_URL)) {
            throw new \InvalidArgumentException('Der ICS-Link ist keine gültige URL.');
        }
        $fields = [
            'name' => $name,
            'address' => trim((string) ($input['address'] ?? '')),
            'color' => self::color($input['color'] ?? '#2E9E6B'),
            'icon' => mb_substr((string) ($input['icon'] ?? '🏠'), 0, 4) ?: '🏠',
            'source_kind' => $kind,
            'awido_customer' => $kind === 'awido' ? ($input['awido_customer'] ?? null) : null,
            'awido_oid' => $kind === 'awido' ? ($input['awido_oid'] ?? null) : null,
            'awido_label' => $kind === 'awido' ? ($input['awido_label'] ?? null) : null,
            'ics_url' => $kind === 'icsurl' ? ($icsUrl ?: null) : null,
        ];
        $id = (int) ($input['id'] ?? 0);
        if ($id > 0) {
            $sets = implode(', ', array_map(fn($k) => "{$k} = :{$k}", array_keys($fields)));
            $pdo->prepare("UPDATE locations SET {$sets} WHERE id = :id")->execute($fields + ['id' => $id]);
        } else {
            $fields['sort_order'] = (int) $pdo->query('SELECT COALESCE(MAX(sort_order), -1) + 1 FROM locations')->fetchColumn();
            $cols = implode(', ', array_keys($fields));
            $vals = ':' . implode(', :', array_keys($fields));
            $pdo->prepare("INSERT INTO locations ({$cols}) VALUES ({$vals})")->execute($fields);
            $id = (int) $pdo->lastInsertId();
        }
        return self::location($id);
    }

    private static function saveWasteType(array $input): array
    {
        $pdo = Db::pdo();
        $name = trim((string) ($input['name'] ?? ''));
        if ($name === '') {
            throw new \InvalidArgumentException('Bitte einen Namen angeben.');
        }
        $anchor = isset($input['anchor_date']) && $input['anchor_date'] !== '' ? self::date($input['anchor_date']) : null;
        $fields = [
            'location_id' => isset($input['location_id']) && $input['location_id'] !== null && $input['location_id'] !== '' ? (int) $input['location_id'] : null,
            'name' => $name,
            'color' => self::color($input['color'] ?? '#5B6470'),
            'icon' => mb_substr((string) ($input['icon'] ?? '🗑️'), 0, 4) ?: '🗑️',
            'active' => !empty($input['active']) ? 1 : 0,
            'reminders' => !empty($input['reminders']) ? 1 : 0,
            'interval_weeks' => max(0, min(52, (int) ($input['interval_weeks'] ?? 0))),
            'anchor_date' => $anchor,
        ];
        $id = (int) ($input['id'] ?? 0);
        if ($id > 0) {
            $sets = implode(', ', array_map(fn($k) => "{$k} = :{$k}", array_keys($fields)));
            $pdo->prepare("UPDATE waste_types SET {$sets} WHERE id = :id")->execute($fields + ['id' => $id]);
        } else {
            $fields['active'] = 1;
            $fields['reminders'] = 1;
            $fields['sort_order'] = (int) $pdo->query('SELECT COALESCE(MAX(sort_order), -1) + 1 FROM waste_types')->fetchColumn();
            $cols = implode(', ', array_keys($fields));
            $vals = ':' . implode(', :', array_keys($fields));
            $pdo->prepare("INSERT INTO waste_types ({$cols}) VALUES ({$vals})")->execute($fields);
            $id = (int) $pdo->lastInsertId();
        }
        return self::wasteTypeDetail($id);
    }

    private static function wasteTypeDetail(int $id): array
    {
        $stmt = Db::pdo()->prepare('SELECT w.*, l.name AS location_name FROM waste_types w LEFT JOIN locations l ON l.id = w.location_id WHERE w.id = ?');
        $stmt->execute([$id]);
        $type = $stmt->fetch();
        if (!$type) {
            throw new \InvalidArgumentException('Müllart nicht gefunden.');
        }
        $type['id'] = (int) $type['id'];
        $type['location_id'] = $type['location_id'] === null ? null : (int) $type['location_id'];
        $type['active'] = (bool) $type['active'];
        $type['reminders'] = (bool) $type['reminders'];
        $type['interval_weeks'] = (int) $type['interval_weeks'];
        $type['explicit_dates'] = Events::dates('pickup_dates', $id);
        $type['skipped_dates'] = Events::dates('skipped_dates', $id);
        $today = date('Y-m-d');
        $type['upcoming'] = Events::pickupDates($type, $today, (new \DateTimeImmutable('+6 months'))->format('Y-m-d'));
        $type['upcoming_skipped'] = array_values(array_filter($type['skipped_dates'], fn($d) => $d >= $today));
        $type['next'] = $type['upcoming'][0] ?? null;
        return $type;
    }

    /** Termin aussetzen – der Einzeltermin bleibt gespeichert, damit „Wiederherstellen“ funktioniert. */
    private static function skipDate(int $typeId, string $date): void
    {
        Db::pdo()->prepare('INSERT OR IGNORE INTO skipped_dates (waste_type_id, date) VALUES (?, ?)')->execute([$typeId, $date]);
    }

    private static function savePerson(array $input): array
    {
        $pdo = Db::pdo();
        $name = trim((string) ($input['name'] ?? ''));
        if ($name === '') {
            throw new \InvalidArgumentException('Bitte einen Namen angeben.');
        }
        $day = (int) ($input['day'] ?? 0);
        $month = (int) ($input['month'] ?? 0);
        $year = isset($input['year']) && $input['year'] !== null && $input['year'] !== '' ? (int) $input['year'] : null;
        if (!checkdate($month, $day, $year ?? 2000)) {
            throw new \InvalidArgumentException('Das Datum ist ungültig.');
        }
        $fields = [
            'name' => $name,
            'day' => $day,
            'month' => $month,
            'year' => $year,
            'notes' => trim((string) ($input['notes'] ?? '')),
            'color' => self::color($input['color'] ?? '#EC4899'),
            'reminders' => !empty($input['reminders']) ? 1 : 0,
            'remind_days_before' => max(0, min(60, (int) ($input['remind_days_before'] ?? 1))),
        ];
        $id = (int) ($input['id'] ?? 0);
        if ($id > 0) {
            $sets = implode(', ', array_map(fn($k) => "{$k} = :{$k}", array_keys($fields)));
            $pdo->prepare("UPDATE people SET {$sets} WHERE id = :id")->execute($fields + ['id' => $id]);
        } else {
            $cols = implode(', ', array_keys($fields));
            $vals = ':' . implode(', :', array_keys($fields));
            $pdo->prepare("INSERT INTO people ({$cols}) VALUES ({$vals})")->execute($fields);
            $id = (int) $pdo->lastInsertId();
        }
        return ['id' => $id];
    }

    private static function setup(array $input): void
    {
        $password = (string) ($input['password'] ?? '');
        if (strlen($password) < 6) {
            self::fail('Das Passwort braucht mindestens 6 Zeichen.', 400);
        }
        Auth::setPassword($password);
        Auth::login($password);
        Seed::seedIfEmpty();
        self::ok(['ok' => true]);
    }

    private static function locationFilter(): ?int
    {
        $value = $_GET['location'] ?? '';
        return $value === '' || $value === null ? null : (int) $value;
    }

    private static function date(mixed $value): string
    {
        $value = (string) $value;
        if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $value) || !checkdate((int) substr($value, 5, 2), (int) substr($value, 8, 2), (int) substr($value, 0, 4))) {
            throw new \InvalidArgumentException('Ungültiges Datum: ' . $value);
        }
        return $value;
    }

    private static function color(mixed $value): string
    {
        $value = strtoupper((string) $value);
        return preg_match('/^#[0-9A-F]{6}$/', $value) ? $value : '#5B6470';
    }

    private static function customer(mixed $value): string
    {
        $value = (string) $value;
        if (!preg_match('/^[a-z0-9\-]{2,40}$/', $value)) {
            throw new \InvalidArgumentException('Ungültige AWIDO-Kennung.');
        }
        return $value;
    }

    public static function cronToken(): string
    {
        $token = Db::setting('cron_token');
        if ($token === null) {
            $token = Db::randomToken(18);
            Db::setSetting('cron_token', $token);
        }
        return $token;
    }

    private static function feedUrl(string $token): string
    {
        return Config::baseUrl() . '/feed.php?token=' . $token;
    }

    private static function ok(mixed $data): void
    {
        echo json_encode(['ok' => true, 'data' => $data], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    private static function fail(string $message, int $status, array $extra = []): never
    {
        http_response_code($status);
        echo json_encode(['ok' => false, 'error' => $message] + $extra, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}
