#!/usr/bin/env python3
"""Baut aus den JSON-Zeilen des Prüflaufs (PortalHealthLiveTests) eine Bericht-Seite.

Aufruf: report.py <ergebnis.jsonl> <bericht.html>
"""
import html
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime


def load(path):
    rows = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                row = json.loads(line)
                rows[row["key"]] = row  # spätere Zeile gewinnt (Nachprüfung)
    return list(rows.values())


STATUS = {"ok": ("Antwortet richtig", "ok"), "warnung": ("Auffällig", "warn"), "fehler": ("Antwortet nicht", "err")}
ORDER = {"fehler": 0, "warnung": 1, "ok": 2}


def esc(text):
    return html.escape(str(text or ""))


def row_html(r):
    label, cls = STATUS.get(r["status"], (r["status"], "warn"))
    name = esc(r["title"])
    if r.get("website"):
        name = f'<a href="{esc(r["website"])}" target="_blank" rel="noopener">{name}</a>'
    place = esc(r.get("place") or "")
    if r.get("district"):
        place = f'{place}<div class="sub">{esc(r["district"])}</div>'
    reasons = "<br>".join(esc(x) for x in r.get("reasons", []))
    if r.get("error"):
        reasons += f'<div class="sub">{esc(r["error"])}</div>'
    types = ", ".join(esc(t) for t in r.get("types", [])[:8])
    if len(r.get("types", [])) > 8:
        types += f" … (+{len(r['types']) - 8})"
    path = " › ".join(esc(p) for p in r.get("path", []))
    dates = esc(r.get("next") or "–") + " bis " + esc(r.get("last") or "–") if r.get("next") else "–"
    search = esc(" ".join([r["title"], r.get("place") or "", r.get("district") or "", r["kind"], r["serviceKey"]]).lower())
    return (f'<tr class="{cls}" data-status="{r["status"]}" data-search="{search}">'
            f'<td><span class="pill {cls}">{label}</span></td><td>{name}<div class="sub">{esc(r["kind"])}</div></td>'
            f'<td>{place}</td><td class="num">{r.get("future", 0)}</td><td>{types}</td><td class="nowrap">{dates}</td>'
            f'<td class="path">{path}</td><td>{reasons}</td><td class="num">{r.get("seconds", 0)}</td></tr>')


def district_table(rows):
    by = defaultdict(Counter)
    for r in rows:
        if r.get("district"):
            by[r["district"]][r["status"]] += 1
    if not by:
        return ""
    out = ['<h2>Je Landkreis</h2><table class="small"><thead><tr><th>Landkreis</th><th class="num">richtig</th>'
           '<th class="num">auffällig</th><th class="num">antwortet nicht</th></tr></thead><tbody>']
    for district, c in sorted(by.items(), key=lambda kv: (-kv[1]["fehler"], -kv[1]["warnung"], kv[0])):
        cls = "err" if c["fehler"] else ("warn" if c["warnung"] else "ok")
        out.append(f'<tr class="{cls}"><td>{esc(district)}</td><td class="num">{c["ok"]}</td>'
                   f'<td class="num">{c["warnung"]}</td><td class="num">{c["fehler"]}</td></tr>')
    out.append("</tbody></table>")
    return "".join(out)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    rows = sorted(load(src), key=lambda r: (ORDER.get(r["status"], 1), r["title"], r.get("place") or ""))
    count = Counter(r["status"] for r in rows)
    mode = "Gemeinden" if any(r.get("mode") == "gemeinden" for r in rows) else "Entsorger"
    reasons = Counter(x.split(" (")[0].split(":")[0] for r in rows if r["status"] != "ok" for x in r.get("reasons", []))
    top = "".join(f"<li>{esc(k)}: <b>{v}</b></li>" for k, v in reasons.most_common(8))
    stamp = datetime.now().strftime("%d.%m.%Y %H:%M")
    page = f"""<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Portal-Prüfung</title>
<style>
:root {{ --bg:#f6f7f9; --card:#fff; --text:#1d1f23; --muted:#6b7280; --line:#e5e7eb;
  --ok:#15803d; --okbg:#dcfce7; --warn:#a16207; --warnbg:#fef3c7; --err:#b91c1c; --errbg:#fee2e2; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#111317; --card:#1a1d23; --text:#e8eaed; --muted:#9aa0a8; --line:#2b2f37;
  --okbg:#12341f; --warnbg:#3a2e0b; --errbg:#3d1414; --ok:#4ade80; --warn:#fbbf24; --err:#f87171; }} }}
body {{ margin:0; font:14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background:var(--bg); color:var(--text); }}
main {{ max-width:1400px; margin:0 auto; padding:24px 16px 48px; }}
h1 {{ font-size:24px; margin:0 0 4px; }} h2 {{ font-size:18px; margin:32px 0 8px; }}
.muted, .sub {{ color:var(--muted); }} .sub {{ font-size:12px; }}
.cards {{ display:flex; gap:12px; flex-wrap:wrap; margin:16px 0; }}
.card {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px 16px; min-width:150px; cursor:pointer; }}
.card b {{ display:block; font-size:28px; }} .card.ok b {{ color:var(--ok); }} .card.warn b {{ color:var(--warn); }} .card.err b {{ color:var(--err); }}
.card.active {{ outline:2px solid var(--text); }}
input[type=search] {{ width:100%; max-width:420px; padding:8px 10px; border-radius:8px; border:1px solid var(--line); background:var(--card); color:var(--text); font-size:14px; }}
.wrap {{ overflow-x:auto; background:var(--card); border:1px solid var(--line); border-radius:12px; margin-top:12px; }}
table {{ border-collapse:collapse; width:100%; }} th, td {{ text-align:left; padding:8px 10px; border-bottom:1px solid var(--line); vertical-align:top; }}
th {{ position:sticky; top:0; background:var(--card); font-size:12px; color:var(--muted); }}
td.num, th.num {{ text-align:right; }} .nowrap {{ white-space:nowrap; }} .path {{ font-size:12px; color:var(--muted); max-width:260px; }}
.pill {{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:12px; white-space:nowrap; }}
.pill.ok {{ background:var(--okbg); color:var(--ok); }} .pill.warn {{ background:var(--warnbg); color:var(--warn); }} .pill.err {{ background:var(--errbg); color:var(--err); }}
table.small {{ background:var(--card); border:1px solid var(--line); border-radius:12px; max-width:700px; }}
tr.err td:first-child {{ box-shadow: inset 3px 0 var(--err); }} tr.warn td:first-child {{ box-shadow: inset 3px 0 var(--warn); }}
a {{ color:inherit; }}
</style></head><body><main>
<h1>Portal-Prüfung: {mode}</h1>
<div class="muted">Stand {stamp} · {len(rows)} geprüft · Jede Zeile hat das Einrichten wie ein Nutzer bis zu den echten Terminen durchgespielt.</div>
<div class="cards">
  <div class="card ok" data-filter="ok">Antwortet richtig<b>{count['ok']}</b></div>
  <div class="card warn" data-filter="warnung">Auffällig<b>{count['warnung']}</b></div>
  <div class="card err" data-filter="fehler">Antwortet nicht<b>{count['fehler']}</b></div>
  <div class="card active" data-filter="">Alle<b>{len(rows)}</b></div>
</div>
<details><summary>Häufigste Gründe</summary><ul>{top or '<li>keine</li>'}</ul>
<p class="muted">„Auffällig“ heißt: Das Portal antwortet, aber etwas ist ungewöhnlich (z. B. nur eine Müllart, Termine enden bald,
nächste Abfuhr erst in über 4 Wochen). Das kann echt sein (Jahreswechsel, ländlicher Rhythmus) und lohnt einen Blick.</p></details>
<p><input type="search" id="q" placeholder="Suchen: Entsorger, Gemeinde, Landkreis …"></p>
<div class="wrap"><table><thead><tr><th>Status</th><th>Entsorger</th><th>Gemeinde</th><th class="num">Termine</th><th>Müllarten</th>
<th>Zeitraum</th><th>Gewählte Adresse</th><th>Grund</th><th class="num">Sek.</th></tr></thead><tbody id="rows">
{''.join(row_html(r) for r in rows)}
</tbody></table></div>
{district_table(rows)}
</main><script>
let filter = "";
const rows = [...document.querySelectorAll('#rows tr')];
function apply() {{
  const q = document.getElementById('q').value.trim().toLowerCase();
  rows.forEach(r => {{ r.style.display = (!filter || r.dataset.status === filter) && (!q || r.dataset.search.includes(q)) ? '' : 'none'; }});
}}
document.querySelectorAll('.card').forEach(c => c.addEventListener('click', () => {{
  filter = c.dataset.filter; document.querySelectorAll('.card').forEach(x => x.classList.toggle('active', x === c)); apply();
}}));
document.getElementById('q').addEventListener('input', apply);
</script></body></html>"""
    with open(dst, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"Bericht: {dst} – richtig {count['ok']}, auffällig {count['warnung']}, antwortet nicht {count['fehler']}")


if __name__ == "__main__":
    main()
