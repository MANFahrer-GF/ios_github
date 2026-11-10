#!/usr/bin/env python3
"""Abdeckung je Gemeinde statt je Kreis.

Die Kreiszuordnung in CatalogRegions.swift sagt nur, in welchem Kreis ein Entsorger tätig ist – nicht, ob er jede
Gemeinde des Kreises führt (Schönmackers im Rhein-Kreis Neuss: sechs von acht Gemeinden, die Stadt Neuss nicht).
Dieses Skript gleicht die echte erste Auswahlliste jedes Eintrags (aus PlaceCoverageSweepTests, TONNE_PLACE_SWEEP)
gegen das Gemeindeverzeichnis ab.

    python3 tools/catalog/place_coverage.py <erste-auswahl.jsonl> [<sondierung.jsonl> …] [--probes <datei>] [--out <datei>]

Klassen je Gemeinde:
  lokal      eigener Gemeinde-Eintrag (localEntries)
  liste      ein Kreis-Eintrag führt die Gemeinde in seiner Ortsliste
  sonde      ein Kreis-Eintrag mit Suchfeld findet die Gemeinde
  stadt      Kreis mit genau einer Gemeinde, Eintrag trägt ihren Namen und beginnt mit der Straße (Stadtportal)
  verband    die Ortsliste führt die Verbandsgemeinde, Samtgemeinde oder das Amt der Gemeinde (amtliche Zugehörigkeit)
  schwach    nur der Grundname steht in einer Ortsliste („Neustadt“ für „Neustadt an der Aisch“) – kein Beleg
  unklar     nur Einträge, deren erste Auswahl keine Gemeinden zeigt (Straße, Bezirk, Suchfeld ohne Sondierung)
  fehlt      Kreis-Einträge mit Ortsliste vorhanden, keiner führt die Gemeinde
  ohne       kein Eintrag für den Kreis
"""
import csv, functools, json, os, re, sys, unicodedata, collections

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(REPO, 'tools', 'catalog', 'data')
SRC = open(os.path.join(REPO, 'TonneCore/Sources/TonneCore/Providers/CatalogRegions.swift'), encoding='utf-8').read()

PLACE_STEPS = {'Ort', 'Gemeinde', 'Stadt / Gemeinde', 'Gemeinde / Ortsteil', 'Ortsgemeinde', 'Ortschaft',
               'Stadt / Verbandsgemeinde', 'Verbandsgemeinde / Stadt', 'Ortsteil', 'Ort / Tour', 'Ort / Stadttour'}
STREET_STEPS = {'Straße', 'Anfangsbuchstabe der Straße', 'Straße / Ortsteil', 'Stadtteil', 'Restmüllbehälter',
                'Abfuhrbezirk', 'Abfuhrbezirk (siehe Straßenverzeichnis)'}


def block(name, end):
    text = SRC[SRC.index(name):SRC.index(end)]
    out = {}
    for line in text.split('\n'):
        m = re.match(r'\s*"((?:[^"\\]|\\.)*)": \[(.*)\],', line)
        if m:
            out[m.group(1)] = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))
    return out


ABBREV = [(r'\ba\.\s*d\.\s*', 'an der '), (r'\bi\.\s*d\.\s*', 'in der '), (r'\bv\.\s*d\.\s*', 'vor der '),
          (r'\bb\.\s*', 'bei '), (r'\bb\s+(?=\w)', 'bei '), (r'\bi\.\s*', 'im '), (r'\ba\.\s*', 'am '), (r'\bst\.\s*', 'sankt '),
          (r'\bopf\b\.?', 'oberpfalz'), (r'\bofr\b\.?', 'oberfranken'), (r'\bufr\b\.?', 'unterfranken')]
TITLES = r'\b(stadt|gemeinde|markt|flecken|hansestadt|kreisstadt|universitatsstadt|grosse kreisstadt|landeshauptstadt|' \
         r'verbandsgemeinde|vg|samtgemeinde|sg|amt|einheitsgemeinde|ortsgemeinde|og|kurort|bergstadt|lutherstadt|' \
         r'barlachstadt|reuterstadt|inselgemeinde|ostseebad|nordseebad|seebad|bad|luftkurort|gemeinden|hallig|insel)\b'
# Schreibweise im Portal weicht vom amtlichen Namen ab (einzeln nachgesehen)
ALIAS = {'kuckssee': 'kucksee'}
STOP = {'an', 'am', 'der', 'bei', 'im', 'in', 'vor', 'vorm', 'ob', 'unter', 'den', 'dem', 'auf', 'zu', 'zur',
        'a', 'b', 'd', 'i', 'o', 'u', 'v'}


def fold(s):
    s = s.lower().replace('ß', 'ss').replace('ä', 'ae').replace('ö', 'oe').replace('ü', 'ue')
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    for pat, rep in ABBREV:
        s = re.sub(pat, rep, s)
    s = re.sub(r'[^a-z0-9 ]+', ' ', s)
    return re.sub(r'\s+', ' ', s).strip()


@functools.lru_cache(maxsize=None)
def weak(name):
    return _weak(name)


@functools.lru_cache(maxsize=None)
def keys(name):
    """Schreibweisen, unter denen eine Gemeinde in einer Ortsliste stehen kann."""
    full = fold(name)
    out = {full}
    head = fold(re.split(r'[,(/]', name)[0])
    out.add(head)
    stripped = re.sub(r'\s+', ' ', re.sub(TITLES, ' ', head)).strip()
    if stripped:
        out.add(stripped)
    # „Nieder Kostenz“ / „Niederkostenz“, „Hattstedtermarsch“ / „Hattstedter Marsch“
    out |= {k.replace(' ', '') for k in out}
    out |= {ALIAS[k] for k in out if k in ALIAS}
    # „Neustadt an der Aisch“ → „neustadt“ nur als schwacher Schlüssel (siehe weak)
    return frozenset(k for k in out if k)


def _weak(name):
    head = fold(re.split(r'[,(/]', name)[0])
    base = re.split(r' (an der|am|im|in der|in|bei|vor der|ob der|ob|auf|unter|uber) ', head)[0]
    base = re.sub(r'\s+', ' ', re.sub(TITLES, ' ', base)).strip()
    return base


def district_key(name):
    return re.sub(r'^(landkreis|kreis|kreisfreie stadt|stadtkreis) ', '', fold(name))


def option_keys(title):
    """Schlüssel einer Auswahlzeile; „Ort – Ortsteil“, „Ort (Ortsteil)“, „Ort, OT …“ zählen für den Ort."""
    # Kreiskürzel vorweg („SLF-RU-Allendorf“ beim ZASO) gehört nicht zum Ortsnamen
    title = re.sub(r'^[A-ZÄÖÜ]{2,4}(-[A-ZÄÖÜ]{2,3})?-(?=[A-ZÄÖÜ][a-zäöü])', '', title)
    out = set(keys(title))
    for part in re.split(r'\s[–-]\s|,|\(|\)|/|;|\s(?:und|mit|sowie|inkl\.?)\s|\sOT\s|\s\+\s'
                         r'|\su\.\s(?=[A-ZÄÖÜ][a-zäöü]{2})', title):
        part = part.strip()
        if part:
            out |= keys(part)
            # „Esens Ost“, „Esens West“: Abfuhrbezirke derselben Gemeinde
            bare = re.sub(r'\s(Nord|Süd|Ost|West|Mitte)$', '', part)
            if bare != part:
                out |= keys(bare)
    # „Britz-Britz“, „Lunow-Stolzenhagen-Lunow“: Gemeinde-Ortsteil, der Ortsteil heißt wie die Gemeinde oder ein Teil von ihr
    ps = title.split('-')
    for i in range(1, len(ps)):
        if '-'.join(ps[i:]) == '-'.join(ps[:i]) or '-'.join(ps[i:]) in ps[:i]:
            out |= keys('-'.join(ps[:i]))
    return out


def strip_prefix(title):
    return re.sub(r'^[A-ZÄÖÜ]{2,4}(-[A-ZÄÖÜ]{2,3})?-(?=[A-ZÄÖÜ][a-zäöü])', '', title)


@functools.lru_cache(maxsize=None)
def tokens(name):
    """Wortfolge ohne Abkürzungsauflösung: „Zell u. A.“ → zell, u, a."""
    s = name.lower().replace('ß', 'ss').replace('ä', 'ae').replace('ö', 'oe').replace('ü', 'ue')
    s = ''.join(c for c in unicodedata.normalize('NFKD', s) if not unicodedata.combining(c))
    return tuple(t for t in re.split(r'[^a-z0-9]+', s) if t)


def short_form(tt, nt):
    """Die Zeile ist eine Kurzform des Gemeindenamens: „Zell u. A.“, „Bayer. Eisenstein“, „Rutsweiler/Glan“,
    „Lausnitz bei Neustadt“ für „Lausnitz b.Neustadt an der Orla“."""
    if tt == nt or len(tt) < 2 or tt[0][:4] != nt[0][:4]:
        return False
    if len(tt) == len(nt) and all(n.startswith(t) for t, n in zip(tt, nt)) and any(t == n and len(t) >= 4 for t, n in zip(tt, nt)):
        return True
    ct, cn = [t for t in tt if t not in STOP], [n for n in nt if n not in STOP]
    return len(ct) >= 2 and cn[:len(ct)] == ct


def main():
    args = sys.argv[1:]
    out_path = probes_path = map_path = None
    files = []
    while args:
        a = args.pop(0)
        if a == '--out':
            out_path = args.pop(0)
        elif a == '--map':
            map_path = args.pop(0)
        elif a == '--probes':
            probes_path = args.pop(0)
        else:
            files.append(a)
    sweep = {}
    for f in files:
        for line in open(f, encoding='utf-8'):
            row = json.loads(line)
            old = sweep.get(row['id'])
            if old:
                # Spätere Läufe ergänzen: Sondierungen und zweite Ebene sammeln sich, ein Fehler überschreibt nichts
                if row.get('input') == 'fehler' and old.get('input') != 'fehler':
                    continue
                row['probes'] = old.get('probes', []) + row.get('probes', [])
                sub = dict(old.get('sub') or {})
                sub.update(row.get('sub') or {})
                row['sub'] = sub
                row['subStep'] = row.get('subStep') or old.get('subStep')
                deep = dict(old.get('deep') or {})
                deep.update(row.get('deep') or {})
                row['deep'] = deep
            sweep[row['id']] = row

    regional = block('entryDistricts', 'localEntries')
    local = block('localEntries', 'districtStates')
    rows = list(csv.DictReader(open(os.path.join(DATA, 'geo/gemeinden.csv'), encoding='utf-8-sig'), delimiter=';'))
    land, gems = {}, collections.defaultdict(set)
    for r in rows:
        land[r['krs_name']] = r['lan_name']
        if r['gem_type'] != 'Gemeindefreies Gebiet':
            gems[r['krs_name']].add((r['gem_code'], r['gem_name_short']))

    by_district = collections.defaultdict(list)
    named_by_district = collections.defaultdict(list)
    for entry, districts in regional.items():
        if entry.startswith(('heimatInfo:', 'icsURL:')):
            # Gemeinde-Kalender ohne Ortsliste: zählen nur für die Gemeinde, die ihr Titel nennt (Beleg „titel“)
            for d in districts:
                named_by_district[d].append(entry)
            continue
        for d in districts:
            by_district[d].append(entry)
    local_places = collections.defaultdict(lambda: collections.defaultdict(list))
    for entry, places in local.items():
        for p in places:
            d, g = p.split('|', 1)
            local_places[d][g].append(entry)

    entry_states = collections.defaultdict(set)
    for entry, districts in list(regional.items()) + [(e, [p.split('|', 1)[0] for p in ps]) for e, ps in local.items()]:
        for d in districts:
            if d in land:
                entry_states[entry].add(land[d])
    option_index, weak_index, prefix_index, title_keys = {}, {}, {}, {}
    token_index, combo_index, weak_count = {}, {}, {}
    def index_titles(entry, titles):
        """Namensindex einer Ortsliste; `entry` ist die Eintrags-ID oder (ID, Kreis) für die Kreisliste der dritten Ebene."""
        ks, ws = set(), set()
        title_keys[entry] = [option_keys(t) for t in titles]
        token_index[entry] = collections.defaultdict(set)
        combo_index[entry] = [tuple(fold(x) for x in t.split('-')) for t in titles if re.search(r'\w-\w', t)]
        weak_count[entry] = collections.Counter(weak(strip_prefix(t)) for t in titles)
        for t in titles:
            ks |= option_keys(t)
            ws.add(weak(strip_prefix(t)))
            tt = tokens(strip_prefix(t))
            if tt:
                token_index[entry][tt[0][:4]].add(tt)
            # „Königslutter Stadtgebiet“, „Helmstedt und Ortsteile“: der Zusatz gehört nicht zum Ortsnamen
            for part in re.split(r'\s(?:und|mit)\s', t):
                bare = re.sub(r'\s+(Stadtgebiet|Kernstadt|Ortsteile)$', '', part.strip())
                if bare != part.strip():
                    ws.add(weak(bare))
        option_index[entry], weak_index[entry] = ks, ws
        # „Ahrensfelde-Blumberg“, „Ahrensfelde-Eiche“: Ort-Ortsteil, wenn derselbe Vorsatz mehrfach vorkommt
        heads = collections.Counter(fold(t.split('-')[0]) for t in titles if '-' in t and ' - ' not in t)
        prefix_index[entry] = {h for h, n in heads.items() if n >= 2}

    for entry, row in sweep.items():
        if row.get('input') == 'liste':
            titles = list(row.get('options', []))
            # Zweite Ebene: Portale, die erst Verbandsgemeinde, Amt oder Landkreis abfragen
            if row.get('subStep') not in STREET_STEPS:
                for subs in row.get('sub', {}).values():
                    titles += subs
            else:
                # Zeile heißt wie der Kreis selbst („Ostprignitz-Ruppin“ neben den Städten): darunter stehen die
                # Orte des übrigen Kreisgebiets, auch wenn der Schritt wie bei den Städten „Straße“ heißt
                own = {district_key(d) for d in regional.get(entry, [])}
                for key, subs in row.get('sub', {}).items():
                    if fold(key) in own:
                        titles += subs
            index_titles(entry, titles)

    result, probes, plain_cache = [], collections.defaultdict(list), {}
    # Rangfolge der Belege: der stärkste bestimmt die Klasse, alle zusammen ergeben die Zuordnung Gemeinde → Einträge.
    rank = ['lokal', 'liste', 'sonde', 'stadt', 'titel', 'kurzform', 'verband', 'ortsteile', 'grundname', 'schwach']
    verband = {r['verband_code']: r['verband_name'] for r in
               csv.DictReader(open(os.path.join(DATA, 'geo/verbaende.csv'), encoding='utf-8'), delimiter=';')}
    # Ortsteile je Gemeinde (Wikidata, P131 unter dem amtlichen Gemeindeschlüssel; nur für Gemeinden, die eine
    # Ortsliste nicht beim eigenen Namen nennt). Schlüssel: achtstelliger AGS.
    ortsteile = collections.defaultdict(set)
    for r in csv.DictReader(open(os.path.join(DATA, 'geo/ortsteile.csv'), encoding='utf-8'), delimiter=';'):
        # „Hollen (Hollnseth)“: der Klammerzusatz unterscheidet nur gleichnamige Orte, die Ortsliste führt „Hollen“
        ortsteile[r['ags']].add(fold(re.sub(r'\s*\([^)]*\)$', '', r['ortsteil'])))

    def ags(code):
        return code[:5] + code[9:12]

    @functools.lru_cache(maxsize=None)
    def ot_hits(e, code):
        return len(ortsteile[ags(code)] & option_index[e])

    members = collections.defaultdict(list)
    for d in gems:
        for code, g in gems[d]:
            members[code[:9]].append(g)
    for district in sorted(land, key=lambda k: (land[k], k)):
        entries = by_district.get(district, [])
        single = len(gems[district]) == 1
        base_count = collections.Counter(weak(g) for _, g in gems[district])
        folded_names = {fold(n) for _, n in gems[district]}
        key_count = collections.Counter(k for _, n in gems[district] for k in keys(n))
        for code, g in sorted(gems[district], key=lambda x: (x[1], x[0])):
            proofs, unclear, listed, note = [], [], [], None
            for e in local_places[district].get(g, []):
                proofs.append((e, 'lokal'))
            gk, gw = keys(g), weak(g)
            parts = [p for p in re.split(r'[-/]', g) if len(p.strip()) >= 3] if re.search(r'\w[-/]\w', g) else []
            for e in entries:
                row = sweep.get(e)
                if row is None:
                    unclear.append((e, 'nicht im Durchlauf'))
                    continue
                step, kind = row.get('step'), row.get('input')
                # Stadtportal: der Eintrag trägt den Namen der Stadt als ganzes Wort („AWM München“, „Stadtreinigung Hamburg“)
                label = ' ' + fold(e.split(':', 2)[2]) + ' '
                name_fits = any(' ' + k + ' ' in label for k in gk | {gw} if len(k) >= 4)
                # Stadtportal im Kreis („Kreisstadt Friedberg (Hessen)“, „ENNI Moers“): der Eintrag nennt die Gemeinde
                # mit vollem Namen und fragt gleich nach der Straße. Ein Kreisportal zählt so nie.
                town_portal = (kind == 'text' or step in STREET_STEPS) and not re.search(r' (land)?kreis ', label) \
                    and any(' ' + k + ' ' in label for k in gk if len(k) >= 4)
                # Eintrag nur für diese eine kreisfreie Stadt, erste Auswahl Straße („Bremer Stadtreinigung“, „AZV Hof – Stadt Hof“)
                own_city = single and regional[e] == [district] and (kind == 'text' or step in STREET_STEPS)
                # Erste Auswahl Bundesland, zweite der Ort (Lobbe): die Ortsliste steht in der zweiten Ebene
                # und zählt nur unter dem Bundesland des Kreises.
                ix = e
                if kind == 'liste' and row.get('deep'):
                    # Bundesland → Landkreis → Ort (Abfall+ Wecker): es zählt nur die Ortsliste des eigenen Kreises,
                    # mit denselben Namensregeln wie eine Ortsliste der ersten Auswahl („Hausen o.V.“, „Seitingen“ +
                    # „Oberflacht“, Amtszeile „Bad Wilsnack/Weisen“ für Rühstädt).
                    if (e, district) not in plain_cache:
                        own = [t for k, ts in row['deep'].items() if k.split('|')[0] == land[district]
                               and district_key(k.split('|')[1]) == district_key(district) for t in ts]
                        plain_cache[(e, district)] = bool(own)
                        if own:
                            index_titles((e, district), own)
                    if not plain_cache[(e, district)]:
                        unclear.append((e, 'Kreis nicht in der Auswahl'))
                        continue
                    ix = (e, district)
                if kind == 'liste' and ix == e and step not in PLACE_STEPS and row.get('subStep') in PLACE_STEPS:
                    if (e, land[district]) not in plain_cache:
                        plain_cache[(e, land[district])] = set().union(
                            *[option_keys(t) for t in row['sub'].get(land[district], [])])
                    listed.append(e)
                    if gk & plain_cache[(e, land[district])]:
                        proofs.append((e, 'liste'))
                elif kind == 'liste' and (ix != e or step in PLACE_STEPS):
                    listed.append(e)
                    vname = verband.get(code[:9], '')
                    vk = keys(vname) | {weak(vname)} if len(members[code[:9]]) > 1 else set()
                    # Mitglieder, die eine Zeile nennt, die nicht schon die Verbandszeile ist („VG Altenkirchen - Flammersfeld“)
                    if (e, code[:9]) not in plain_cache:
                        plain_cache[(ix, code[:9])] = set().union(*[tk for tk in title_keys[ix] if not vk & tk])
                    plain = plain_cache[(ix, code[:9])]
                    # Die Gemeinde, die wie ihr Verband heißt (Grasleben in der Samtgemeinde Grasleben), ist keine einzeln
                    # aufgeführte Mitgliedsgemeinde: die Zeile „Grasleben und Velpke“ meint die Samtgemeinden.
                    siblings = [m for m in members[code[:9]] if m != g and keys(m) & plain and not keys(m) & vk]
                    if gk & option_index[ix] or gk & prefix_index[ix]:
                        proofs.append((e, 'liste'))
                    elif any(short_form(tt, tokens(g)) for tt in token_index[ix].get(tokens(g)[0][:4], ())):
                        proofs.append((e, 'kurzform'))
                    elif any(fold(g) in c and all(x in folded_names for x in c) for c in combo_index[ix]):
                        # „Reichsthal-Seelen“: eine Zeile für zwei Gemeinden des Kreises
                        proofs.append((e, 'liste'))
                    elif vk & option_index[ix] and not siblings and row.get('subStep') not in PLACE_STEPS:
                        # Portal fragt zuerst Verbandsgemeinde, Samtgemeinde oder Amt (amtliche Zugehörigkeit aus
                        # dem Gemeindeverzeichnis); zählt nur, wenn es keine Mitgliedsgemeinde einzeln aufführt.
                        proofs.append((e, 'verband'))
                    elif len(parts) >= 2 and all(keys(p) & option_index[ix] for p in parts):
                        # Fusionsname „Dalberg-Wendelstorf“: die Liste führt beide Ortsteile einzeln
                        proofs.append((e, 'ortsteile'))
                    elif ot_hits(ix, code) >= 2 or (ot_hits(ix, code) and ot_hits(ix, code) == len(ortsteile[ags(code)])):
                        # Fusionsgemeinde („Hohe Börde“): die Liste führt mindestens zwei ihrer Ortsteile (oder alle)
                        proofs.append((e, 'ortsteile'))
                    elif gw and gw in weak_index[ix]:
                        # „Neustadt“ für „Neustadt an der Aisch“: Beleg nur, wenn im Kreis keine zweite Gemeinde
                        # denselben Grundnamen trägt; sonst bleibt es unbewiesen.
                        # … oder die Liste führt so viele Zeilen mit diesem Grundnamen wie der Kreis Gemeinden
                        # („Oberhausen“ und „Oberhausen/Nahe“ für Oberhausen bei Kirn und Oberhausen an der Nahe).
                        proofs.append((e, 'grundname' if base_count[gw] <= max(1, weak_count[ix][gw]) else 'schwach'))
                    elif len(parts) >= 2 and keys(parts[0]) & option_index[ix] and \
                            all(key_count[k] == 0 for k in keys(parts[0])):
                        # „Hilgertshausen“ für Hilgertshausen-Tandern: die Liste führt den Hauptort des Doppelnamens,
                        # und keine andere Gemeinde des Kreises heißt so
                        proofs.append((e, 'ortsteile'))
                    elif single and name_fits and regional[e] == [district]:
                        # Eintrag nur für diese kreisfreie Stadt, trägt ihren Namen, Liste zeigt Stadtteile („Dortmund (EDG)“)
                        proofs.append((e, 'stadt'))
                elif kind == 'text':
                    hits = [p for p in row.get('probes', []) if fold(p['text']) in (fold(g), weak(g))]
                    # Treffer nur, wenn die Antwort den Ort selbst nennt: ein Straßen-Suchfeld liefert auf „Neuss“
                    # auch „Neusser Straße“, und „kein Folgeschritt“ (-1/-2) belegt nichts.
                    found = [p for p in hits if not p.get('error')
                             and any(gk & option_keys(t) for t in p.get('sample', []))]
                    # Straßen-Sonde: das Suchfeld des Kreises antwortet auf „Haupt“ mit „Ort / Straße“ (Heidekreis)
                    found += [p for p in row.get('probes', []) if not p.get('error')
                              and any(' / ' in t and gk & keys(t.split(' / ')[0]) for t in p.get('sample', []))]
                    if found:
                        proofs.append((e, 'sonde'))
                    elif (single and name_fits) or own_city:
                        proofs.append((e, 'stadt'))
                    elif town_portal:
                        proofs.append((e, 'titel'))
                    elif hits:
                        listed.append(e)
                        note = 'Sondierung ohne Treffer'
                    else:
                        unclear.append((e, 'Suchfeld ' + str(step)))
                        probes[e].append(g)
                elif kind == 'fehler':
                    unclear.append((e, 'Fehler: ' + str(row.get('error'))))
                elif (single and name_fits) or own_city:
                    # Kreisfreie Stadt: ihr eigenes Portal fragt nach Stadtteil oder Straße, nicht nach dem Ort
                    proofs.append((e, 'stadt'))
                elif town_portal:
                    proofs.append((e, 'titel'))
                else:
                    unclear.append((e, 'erste Auswahl: ' + str(step)))
            for e in named_by_district.get(district, []):
                label = ' ' + fold(e.split(':', 2)[2]) + ' '
                if any(' ' + k + ' ' in label for k in gk if len(k) >= 4):
                    proofs.append((e, 'titel'))
            proofs.sort(key=lambda p: rank.index(p[1]))
            status = proofs[0][1] if proofs else None
            if status is None:
                elsewhere = [e for e, ks in option_index.items() if isinstance(e, str) and e not in entries and gk & ks
                             and sweep[e].get('step') in PLACE_STEPS and land[district] in entry_states.get(e, ())]
                if elsewhere:
                    note = 'steht bei: ' + ' | '.join(sorted(elsewhere)[:3])
                if unclear:
                    status = 'unklar'
                    note = '; '.join(filter(None, [note] + sorted({u[1] for u in unclear})))
                elif listed:
                    status = 'fehlt'
                else:
                    status = 'ohne'
            result.append({'land': land[district], 'kreis': district, 'gemeinde': g, 'code': code, 'status': status,
                           'via': proofs[0][0] if proofs else None, 'belege': [list(p) for p in proofs],
                           'hinweis': note, 'eintraege': entries})

    count = collections.Counter(r['status'] for r in result)
    print('Gemeinden', len(result), dict(count))
    if out_path:
        json.dump(result, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    if map_path:
        # Belegte Zuordnung Gemeinde → Einträge für gen_place_map.py; „schwach“ ist kein Beleg.
        rows = [{'code': r['code'], 'kreis': r['kreis'], 'gemeinde': r['gemeinde'], 'art': r['status'],
                 'eintraege': sorted({e for e, kind in r['belege'] if kind != 'schwach'})}
                for r in sorted(result, key=lambda r: r['code'])]
        json.dump(rows, open(map_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    if probes_path:
        json.dump({k: sorted(set(v)) for k, v in probes.items()}, open(probes_path, 'w', encoding='utf-8'), ensure_ascii=False)
        print('Sondierungen', len(probes), 'Einträge,', sum(len(set(v)) for v in probes.values()), 'Suchtexte')
    return result


if __name__ == '__main__':
    main()
