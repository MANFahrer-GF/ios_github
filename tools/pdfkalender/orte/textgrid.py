"""Rasterkalender, in denen die Abfallart als Wort in der Tageszelle steht (Gaienhofen, Öhningen).
Zelleninhalt wird an „/“ und „+“ geteilt; jedes Stück muss im Vokabular stehen oder ausdrücklich
ignoriert werden (Feiertage, Wertstoffhof-Öffnung …). Unbekanntes bricht ab, damit nichts verloren geht."""
import re

import common


def extract(pdf, year, vocab, ignore, key):
    cells, notes = common.parse_grid(pdf, year)
    common.assert_grid_ok(notes, key)
    events, unknown = [], set()
    for c in cells:
        text = ' '.join(t for _, t in c['words'])
        text = re.sub(r'(^|\s)\d{1,2}(?=\s|$)', ' ', text).strip()  # KW-Nummern in der Zelle
        for part in re.split(r'\s*[/+]\s*', text):
            p = part.strip()
            if not p:
                continue
            low = p.lower()
            hit = next((v for k, v in vocab if low == k or low.startswith(k + ' ')), None)
            if hit:
                events.append((c['date'],) + hit)
            elif not any(low.startswith(i) for i in ignore):
                unknown.add((str(c['date']), p))
    if unknown:
        raise SystemExit(f'{key}: nicht zugeordnete Einträge {sorted(unknown)}')
    return events
