<?php
declare(strict_types=1);

namespace TonneTorte;

/** Zugriff auf das AWIDO-Portal (awido.cubefour.de), u. a. Landkreis Gifhorn. */
final class Awido
{
    private const BASE = 'https://awido.cubefour.de/WebServices/Awido.Service.svc/secure';

    /** Bekannte AWIDO-Kunden: Kennung => Name */
    public const PROVIDERS = [
        'gifhorn' => 'Landkreis Gifhorn',
        'awb-altenburg' => 'Abfallwirtschaft Altenburger Land',
        'awv-isar-inn' => 'Abfallwirtschaft Isar-Inn',
        'awld' => 'Abfallwirtschaft Lahn-Dill-Kreis',
        'rmk' => 'Abfallwirtschaft Rems-Murr (AWRM)',
        'awv-nordschwaben' => 'Abfall-Wirtschafts-Verband Nordschwaben',
        'awb-ak' => 'Abfallwirtschaftsbetrieb Landkreis Altenkirchen',
        'azv-hef-rof' => 'AZV Landkreis Hersfeld-Rotenburg',
        'awb-duerkheim' => 'AWB Landkreis Bad Dürkheim',
        'ffb' => 'AWB Landkreis Fürstenfeldbruck',
        'ebu' => 'EBU Ulm',
        'unterhaching' => 'Gemeinde Unterhaching',
        'ansbach' => 'Landkreis Ansbach',
        'lra-ab' => 'Landkreis Aschaffenburg',
        'bgl' => 'Landkreis Berchtesgadener Land',
        'coburg' => 'Landkreis Coburg',
        'ebe' => 'Landkreis Ebersberg',
        'erding' => 'Landkreis Erding',
        'fulda' => 'Landkreis Fulda',
        'lkgi' => 'Landkreis Gießen',
        'gotha' => 'Landkreis Gotha',
        'kaw-guenzburg' => 'Landkreis Günzburg',
        'kelheim' => 'Landkreis Kelheim',
        'kronach' => 'Landkreis Kronach',
        'kulmbach' => 'Landkreis Kulmbach',
        'lichtenfels' => 'Landkreis Lichtenfels',
        'lra-mue' => 'Landkreis Mühldorf a. Inn',
        'rosenheim' => 'Landkreis Rosenheim',
        'roth' => 'Landkreis Roth',
        'lra-schweinfurt' => 'Landkreis Schweinfurt',
        'eww-suew' => 'Landkreis Südliche Weinstraße',
        'kreis-tir' => 'Landkreis Tirschenreuth',
        'tuebingen' => 'Landkreis Tübingen',
        'landkreisbetriebe' => 'Landkreisbetriebe Neuburg-Schrobenhausen',
        'aic-fdb' => 'Landratsamt Aichach-Friedberg',
        'lra-dah' => 'Landratsamt Dachau',
        'lra-regensburg' => 'Landratsamt Regensburg',
        'neustadt' => 'Neustadt a.d. Waldnaab',
        'pullach' => 'Pullach im Isartal',
        'fulda-stadt' => 'Stadt Fulda',
        'kaufbeuren' => 'Stadt Kaufbeuren',
        'koenigstein' => 'Stadt Königstein im Taunus',
        'memmingen' => 'Stadt Memmingen',
        'regensburg' => 'Stadt Regensburg',
        'unterschleissheim' => 'Stadt Unterschleißheim',
        'wgv' => 'WGV Recycling GmbH',
        'zaso' => 'Zweckverband Abfallwirtschaft Saale-Orla',
        'zv-muc-so' => 'Zweckverband München-Südost',
    ];

    /** @return array<int, array{key: string, value: string}> */
    public static function places(string $customer): array
    {
        return self::entries(self::BASE . '/getPlaces/client=' . rawurlencode($customer));
    }

    /** @return array<int, array{key: string, value: string}> */
    public static function streets(string $customer, string $placeOid): array
    {
        return self::entries(self::BASE . '/getGroupedStreets/' . rawurlencode($placeOid) . '?client=' . rawurlencode($customer));
    }

    /** Hausnummern; leer, wenn der Kunde keine Hausnummernauswahl kennt. */
    public static function houseNumbers(string $customer, string $streetOid): array
    {
        $entries = self::entries(self::BASE . '/getStreetAddons/' . rawurlencode($streetOid) . '?client=' . rawurlencode($customer));
        return array_values(array_filter($entries, fn($e) => trim($e['value']) !== ''));
    }

    /** @return array<int, array{summary: string, date: string}> */
    public static function pickups(string $customer, string $oid): array
    {
        $data = Http::json(self::BASE . '/getData/' . rawurlencode($oid) . '?fractions=&client=' . rawurlencode($customer));
        if (!is_array($data) || empty($data['calendar']) || empty($data['fracts'])) {
            throw new \RuntimeException('Das AWIDO-Portal hat keine Termine für diese Adresse geliefert.');
        }
        $names = [];
        foreach ($data['fracts'] as $fraction) {
            $names[$fraction['snm']] = self::clean((string) $fraction['nm']);
        }
        $events = [];
        foreach ($data['calendar'] as $item) {
            // Feiertage stehen ebenfalls im Kalender, dann ist "ad" leer.
            if (empty($item['fr']) || !isset($item['ad']) || $item['ad'] === null) {
                continue;
            }
            $date = Ics::parseDate((string) $item['dt']);
            if ($date === null) {
                continue;
            }
            foreach ($item['fr'] as $code) {
                $name = $names[$code] ?? (string) $code;
                $events[$name . '|' . $date] = ['summary' => $name, 'date' => $date];
            }
        }
        if ($events === []) {
            throw new \RuntimeException('Das AWIDO-Portal hat keine Termine für diese Adresse geliefert.');
        }
        $events = array_values($events);
        usort($events, fn($a, $b) => strcmp($a['date'], $b['date']));
        return $events;
    }

    public static function clean(string $name): string
    {
        return trim(str_replace(['&shy;', "\u{00AD}", '&amp;'], ['', '', '&'], $name));
    }

    private static function entries(string $url): array
    {
        $data = Http::json($url);
        if (!is_array($data)) {
            throw new \RuntimeException('Unerwartete Antwort vom AWIDO-Portal.');
        }
        return array_map(fn($e) => ['key' => (string) $e['key'], 'value' => (string) $e['value']], $data);
    }
}
