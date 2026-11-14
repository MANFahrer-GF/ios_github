#!/usr/bin/env python3
"""Ortsdaten für die Live-Suche auf tonne.kant.ovh aus dem App-Katalog erzeugen.

Liest die generierten Swift-Dateien in TonneCore/Providers (dieselben Daten wie die App)
und schreibt website/data/orte.json. Aufruf aus dem Repo: python3 website/tools/orte_export.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
P = ROOT / "TonneCore/Sources/TonneCore/Providers"
OUT = ROOT / "website/data/orte.json"


def raw_block(text, name):
    m = re.search(name + r': String = #"""\n(.*?)\n"""#', text, re.S)
    return [l for l in m.group(1).split("\n") if l.strip()] if m else []


def str_array(text, name):
    m = re.search(r"static let " + name + r": \[String\] = \[\n(.*?)\n    \]", text, re.S)
    return re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)) if m else []


catalog = (P / "Catalog.swift").read_text()
entries = []
ids = {}
for m in re.finditer(r'CatalogEntry\(kind: \.(\w+), serviceKey: "((?:[^"\\]|\\.)*)", title: "((?:[^"\\]|\\.)*)"(?:, website: "((?:[^"\\]|\\.)*)")?', catalog):
    kind, key, title, web = m.groups()
    ids[f"{kind}:{key}:{title}"] = len(entries)
    entries.append([title, web or ""])

regions = (P / "CatalogRegions.swift").read_text()
districts, gemeinden, gindex = [], [], {}
for line in raw_block(regions, "municipalities"):
    kreis, names = line.split("|", 1)
    k = len(districts)
    districts.append(kreis)
    for n in names.split(","):
        gindex[f"{kreis}|{n}"] = len(gemeinden)
        gemeinden.append([n, k, [], ""])

pm = (P / "CatalogPlaceMap.swift").read_text()
pm_ids = str_array(pm, "entryIDs")
for line in raw_block(pm, "places"):
    pair, _, pos = line.rpartition("=")
    g = gindex.get(pair)
    if g is None:
        continue
    for p in pos.split(","):
        if p.isdigit() and int(p) < len(pm_ids) and pm_ids[int(p)] in ids:
            gemeinden[g][2].append(ids[pm_ids[int(p)]])

reasons = str_array(pm, "gapReasons")
sources = str_array(pm, "gapSources")
for line in raw_block(pm, "gaps"):
    pair, _, rest = line.rpartition("=")
    g = gindex.get(pair)
    if g is None or gemeinden[g][2]:
        continue
    parts = rest.split(",")
    reason = reasons[int(parts[1])] if len(parts) > 1 and parts[1].isdigit() and int(parts[1]) < len(reasons) else ""
    src = sources[int(parts[2])] if len(parts) > 2 and parts[2].isdigit() and int(parts[2]) < len(sources) else ""
    gemeinden[g][3] = "|".join([parts[0], reason, src])

loc = (P / "CatalogLocalities.swift").read_text()
ortsteile = []
for line in raw_block(loc, "localities"):
    parts = line.split("|", 2)
    if len(parts) != 3:
        continue
    g = gindex.get(f"{parts[0]}|{parts[1]}")
    if g is None:
        continue
    for n in parts[2].split(","):
        ortsteile.append([n, g])

data = {"k": districts, "e": entries, "g": gemeinden, "o": ortsteile}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
abgedeckt = sum(1 for g in gemeinden if g[2])
print(f"{len(districts)} Kreise, {len(gemeinden)} Gemeinden ({abgedeckt} mit Entsorger), {len(ortsteile)} Ortsteile, {len(entries)} Entsorger -> {OUT} ({OUT.stat().st_size // 1024} KB)")
