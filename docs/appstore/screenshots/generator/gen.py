"""App-Store-Screenshots für „Tonne & Torte“: baut die App-Ansichten nach dem SwiftUI-Code als HTML nach.
Farben, Texte, Abstände und Tonnen-Symbole stammen aus Shared/TonneDesign.swift, OverviewView.swift,
CoverageView.swift, BirthdayListView.swift, WatchContentView.swift und Shared/Waste.xcassets."""
import json, os, html

HERE = os.path.dirname(os.path.abspath(__file__))
GLYPHS = json.load(open(os.path.join(HERE, "glyphs.json")))
NDS = json.load(open(os.path.join(HERE, "nds.json")))
OUT = os.path.join(HERE, "html")  # Zwischenstand, nicht einchecken
os.makedirs(OUT, exist_ok=True)

E = html.escape

# Farben aus WasteCategory.colorHex
YELLOW, REST, BIO, PAPER = "#F2C230", "#5B6470", "#8B5E34", "#2F6FED"
ACCENT = "#2E6BC7"  # AccentColor
DONE = "#34C759"


def is_light(hexs):
    v = int(hexs[1:7], 16)
    r, g, b = (v >> 16 & 255) / 255, (v >> 8 & 255) / 255, (v & 255) / 255
    return 0.299 * r + 0.587 * g + 0.114 * b > 0.62


def scaled(hexs, f):
    v = int(hexs[1:7], 16)
    return "#%02X%02X%02X" % tuple(int(c * f) for c in ((v >> 16) & 255, (v >> 8) & 255, v & 255))


def ink(hexs, dark):
    if not dark and is_light(hexs):
        return scaled(hexs, 0.72)
    if dark and hexs.upper() == "#8B5E34":
        return "#D9A066"
    return hexs


def glyph_color(hexs):
    return "#2A2210" if is_light(hexs) else "#FFFFFF"


def glyph(name, size, color):
    g = GLYPHS[name]
    paths = "".join(f'<path d="{d}"/>' for d in g["d"])
    return f'<svg class="g" width="{size}" height="{size}" viewBox="{g["vb"]}" fill="{color}" fill-rule="nonzero">{paths}</svg>'


# SF-Symbol-Ersatz (einfache Nachzeichnungen)
def sf(name, size, color):
    s = size
    icons = {
        "checkmark": '<path d="M4 12.5l5 5L20 6.5" fill="none" stroke="C" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>',
        "house": '<path d="M12 3.2l9 7.6v9.4a1.3 1.3 0 0 1-1.3 1.3h-4.9v-6.2H9.2v6.2H4.3A1.3 1.3 0 0 1 3 20.2v-9.4z" fill="C"/>',
        "calendar": '<rect x="3" y="4.5" width="18" height="16.5" rx="3.2" fill="C"/><rect x="5" y="9.5" width="14" height="9.5" rx="1.2" fill="#fff" opacity=".0"/><rect x="5.2" y="9.6" width="13.6" height="9.2" rx="1.4" fill="BG"/><circle cx="8.5" cy="12.6" r="1.1" fill="C"/><circle cx="12" cy="12.6" r="1.1" fill="C"/><circle cx="15.5" cy="12.6" r="1.1" fill="C"/><circle cx="8.5" cy="16" r="1.1" fill="C"/><circle cx="12" cy="16" r="1.1" fill="C"/>',
        "trash": '<path d="M9 3.5h6l.7 1.8H20a1 1 0 0 1 0 2H4a1 1 0 0 1 0-2h4.3z" fill="C"/><path d="M5.6 8.4h12.8l-1 11.6a2 2 0 0 1-2 1.8H8.6a2 2 0 0 1-2-1.8z" fill="C"/>',
        "cake": '<path d="M12 2.6c1.2 1.4 1.6 2.4 1.2 3.3a1.3 1.3 0 0 1-2.4 0c-.4-.9 0-1.9 1.2-3.3z" fill="C"/><rect x="11.1" y="6.8" width="1.8" height="3.4" fill="C"/><path d="M4.5 12a2.4 2.4 0 0 1 2.4-2.4h10.2a2.4 2.4 0 0 1 2.4 2.4v2.3c-1.4 1.1-2.8 1.1-4.2 0-1.4 1.1-2.8 1.1-4.2 0-1.4 1.1-2.8 1.1-4.2 0-.8.6-1.6.9-2.4.9z" fill="C"/><path d="M4 16.4c1 .3 2 .1 3-.5 1.6 1 3.4 1 5 0 1.6 1 3.4 1 5 0 1 .6 2 .8 3 .5V20a1.4 1.4 0 0 1-1.4 1.4H5.4A1.4 1.4 0 0 1 4 20z" fill="C"/>',
        "ellipsis": '<circle cx="12" cy="12" r="9.5" fill="C"/><circle cx="7.6" cy="12" r="1.5" fill="BG"/><circle cx="12" cy="12" r="1.5" fill="BG"/><circle cx="16.4" cy="12" r="1.5" fill="BG"/>',
        "search": '<circle cx="10.5" cy="10.5" r="6.2" fill="none" stroke="C" stroke-width="2.3"/><path d="M15.2 15.2l5 5" stroke="C" stroke-width="2.5" stroke-linecap="round"/>',
        "mic": '<rect x="9" y="3" width="6" height="11" rx="3" fill="C"/><path d="M6 11a6 6 0 0 0 12 0M12 17v3.5" fill="none" stroke="C" stroke-width="1.8" stroke-linecap="round"/>',
        "checkcircle": '<circle cx="12" cy="12" r="10" fill="C"/><path d="M7.3 12.3l3.1 3.1 6.3-6.6" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
        "filter": '<circle cx="12" cy="12" r="9.6" fill="none" stroke="C" stroke-width="1.7"/><path d="M7.5 9h9M9 12.2h6M10.6 15.4h2.8" stroke="C" stroke-width="1.8" stroke-linecap="round"/>',
        "plus": '<path d="M12 5v14M5 12h14" stroke="C" stroke-width="2.3" stroke-linecap="round"/>',
        "flame": '<path d="M12 2.5c.6 3.2 4.2 5 5.6 8.6 1.7 4.4-1.1 10.4-5.6 10.4s-7.3-3.7-6.3-8c.5-2.1 1.8-3.4 2.6-3.6-.2 1.8.4 3 1.6 3.6-.4-4.2 1.1-7.5 2.1-11z" fill="C"/>',
        "lock": '<rect x="5" y="10.5" width="14" height="10.5" rx="2.4" fill="C"/><path d="M8.2 10.5V8a3.8 3.8 0 0 1 7.6 0v2.5" fill="none" stroke="C" stroke-width="2"/>',
        "torch": '<path d="M8 3h8v4l-2 3v10.5a1.5 1.5 0 0 1-1.5 1.5h-1A1.5 1.5 0 0 1 10 20.5V10L8 7z" fill="C"/>',
        "camera": '<path d="M4 8.5A2 2 0 0 1 6 6.5h2l1.4-2h5.2l1.4 2h2a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" fill="C"/><circle cx="12" cy="13" r="3.6" fill="BG"/>',
        "chev": '<path d="M9 5l7 7-7 7" fill="none" stroke="C" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
    }
    body = icons[name].replace("C", color).replace("BG", "var(--bgicon,#fff)")
    return f'<svg class="g" width="{s}" height="{s}" viewBox="0 0 24 24">{body}</svg>'


def status_icons(color, scale=1.0):
    w = 1 * scale
    return (f'<svg width="{18*w}" height="{12*w}" viewBox="0 0 18 12"><g fill="{color}">'
            '<rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/>'
            '<rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></g></svg>'
            f'<svg width="{17*w}" height="{12*w}" viewBox="0 0 17 12"><g fill="{color}">'
            '<path d="M8.5 2.3c2.5 0 4.8 1 6.5 2.6l1.3-1.4A11 11 0 0 0 8.5.4 11 11 0 0 0 .7 3.5L2 4.9a9.2 9.2 0 0 1 6.5-2.6z"/>'
            '<path d="M8.5 6c1.5 0 2.9.6 3.9 1.6l1.3-1.4A7.4 7.4 0 0 0 8.5 4a7.4 7.4 0 0 0-5.2 2.2l1.3 1.4c1-1 2.4-1.6 3.9-1.6z"/>'
            '<path d="M8.5 9.7c.6 0 1.1.2 1.5.6L8.5 12 7 10.3c.4-.4.9-.6 1.5-.6z"/></g></svg>'
            f'<svg width="{27*w}" height="{13*w}" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="{color}" opacity=".4"/>'
            f'<rect x="2" y="2" width="17" height="9" rx="2.5" fill="{color}"/><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2z" fill="{color}" opacity=".45"/></svg>')


CSS = """
@font-face { font-family: 'Rounded'; src: url('../fonts/nunito-latin.woff2') format('woff2'); font-weight: 200 1000; }
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { background: #000; }
body { font-family: 'Inter', sans-serif; -webkit-font-smoothing: antialiased; }
.g { display: block; flex: none; }
.rd { font-family: 'Rounded', 'Inter', sans-serif; }
.canvas { position: relative; overflow: hidden; }
.screen { position: relative; overflow: hidden; font-family: 'Inter', sans-serif; letter-spacing: -0.012em; }
.light { background: #F2F2F7; color: #000; --bgicon: #fff; }
.sb { position: absolute; left: 0; right: 0; top: 0; height: 54px; display: flex; align-items: center; justify-content: space-between; padding: 0 28px 0 48px; z-index: 5; font-weight: 600; font-size: 17px; }
.sb .icons { display: flex; gap: 6px; align-items: center; }
.island { position: absolute; top: 11px; left: 50%; transform: translateX(-50%); width: 125px; height: 37px; border-radius: 20px; background: #000; z-index: 6; }
.card { background: #fff; border-radius: 22px; padding: 16px; box-shadow: 0 4px 10px rgba(0,0,0,.06); }
.navbar { display: flex; justify-content: flex-end; align-items: center; height: 44px; padding: 0 16px; }
.roundbtn { width: 36px; height: 36px; border-radius: 18px; background: rgba(255,255,255,.75); box-shadow: 0 2px 10px rgba(0,0,0,.08); display: flex; align-items: center; justify-content: center; }
.largetitle { font-size: 34px; font-weight: 700; letter-spacing: -0.02em; padding: 2px 16px 8px; }
.sechead { display: flex; align-items: center; gap: 8px; font-size: 17px; font-weight: 600; padding-left: 4px; margin-bottom: 12px; }
.tabbar { position: absolute; left: 20px; right: 20px; bottom: 26px; height: 64px; border-radius: 32px; background: rgba(250,250,252,.82);
          box-shadow: 0 8px 30px rgba(0,0,0,.12), inset 0 0 0 .5px rgba(0,0,0,.06); display: flex; align-items: center; padding: 0 4px; backdrop-filter: blur(20px); }
.tab { flex: 1; height: 56px; border-radius: 28px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; font-size: 10px; font-weight: 600; color: #1c1c1e; }
.tab.sel { background: rgba(0,0,0,.06); color: """ + ACCENT + """; }
.homeind { position: absolute; bottom: 8px; left: 50%; transform: translateX(-50%); width: 140px; height: 5px; border-radius: 3px; background: #000; z-index: 7; }
.chip { display: inline-flex; align-items: center; gap: 6px; border-radius: 99px; padding: 6px 10px; font-size: 12px; font-weight: 600; }
.divider { height: .5px; background: #C6C6C8; }
.avatar { border-radius: 50%; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 700; flex: none; }
.secondary { color: #8A8A8E; }
"""


def statusbar(color="#000", time="19:00", island=True, ipad=False):
    if ipad:
        return (f'<div class="sb" style="height:32px;font-size:14px;padding:0 24px;color:{color}"><span>{time}&nbsp;&nbsp;Do. 8. Okt.</span>'
                f'<span class="icons">{status_icons(color, 0.9)}</span></div>')
    isl = '<div class="island"></div>' if island else ''
    return f'{isl}<div class="sb" style="color:{color}"><span style="width:54px;text-align:center">{time}</span><span class="icons">{status_icons(color)}</span></div>'


def tabbar(selected, ipad=False):
    items = [("house", "Übersicht"), ("calendar", "Kalender"), ("trash", "Müll"), ("cake", "Geburtstage"), ("ellipsis", "Mehr")]
    if ipad:
        tabs = "".join(
            f'<div style="padding:9px 18px;border-radius:20px;font-size:15px;font-weight:600;{"background:rgba(0,0,0,.07);color:" + ACCENT if i == selected else "color:#1c1c1e"}">{label}</div>'
            for i, (_, label) in enumerate(items))
        return (f'<div style="position:absolute;top:40px;left:50%;transform:translateX(-50%);display:flex;gap:2px;padding:4px;border-radius:24px;'
                f'background:rgba(250,250,252,.85);box-shadow:0 6px 24px rgba(0,0,0,.1), inset 0 0 0 .5px rgba(0,0,0,.06);z-index:4">{tabs}</div>')
    tabs = "".join(
        f'<div class="tab{" sel" if i == selected else ""}">{sf(icon, 24, ACCENT if i == selected else "#1c1c1e")}<span>{label}</span></div>'
        for i, (icon, label) in enumerate(items))
    return f'<div class="tabbar">{tabs}</div><div class="homeind"></div>'


# ---------------------------------------------------------------- Beispieldaten
NEXT = [("Gelber Sack", "tt.sack", YELLOW), ("Restmüll", "tt.bin", REST)]
PICKUPS = [
    ("Morgen", "Fr., 9. Okt.", [("Gelber Sack", "tt.sack", YELLOW), ("Restmüll", "tt.bin", REST)]),
    ("in 6 Tagen", "Mi., 14. Okt.", [("Bioabfall", "tt.bin.bio", BIO), ("Papier", "tt.bin.paper", PAPER)]),
    ("in 15 Tagen", "Fr., 23. Okt.", [("Gelber Sack", "tt.sack", YELLOW), ("Restmüll", "tt.bin", REST)]),
    ("in 20 Tagen", "Mi., 28. Okt.", [("Bioabfall", "tt.bin.bio", BIO)]),
    ("in 29 Tagen", "Fr., 6. Nov.", [("Gelber Sack", "tt.sack", YELLOW), ("Restmüll", "tt.bin", REST)]),
    ("in 34 Tagen", "Mi., 11. Nov.", [("Bioabfall", "tt.bin.bio", BIO), ("Papier", "tt.bin.paper", PAPER)]),
]
BIRTHDAYS = [  # Name, Initialen, Farbe, Alter, Datum, Countdown, Geschenkideen
    ("Oma Erika", "OE", "#EC4899", 70, "So., 11. Okt.", "in 3 Tagen", 2),
    ("Paul", "P", "#3B82F6", 9, "Do., 22. Okt.", "in 14 Tagen", 1),
    ("Lena", "L", "#F59E0B", 34, "Di., 3. Nov.", "in 26 Tagen", 0),
    ("Jonas", "J", "#10B981", 41, "Sa., 14. Nov.", "in 37 Tagen", 0),
    ("Tante Gabi", "TG", "#8B5CF6", 60, "Fr., 27. Nov.", "in 50 Tagen", 1),
    ("Max", "M", "#EF4444", 27, "Mo., 7. Dez.", "in 60 Tagen", 0),
    ("Sophie", "S", "#06B6D4", 18, "Mi., 23. Dez.", "in 76 Tagen", 3),
    ("Opa Heinz", "OH", "#64748B", 76, "Do., 14. Jan.", "in 98 Tagen", 0),
]
MILESTONES = {18, 21, 30, 40, 50, 60, 70, 80, 90, 100}


def bin_line(name, g, color, dot, font, dark=False):
    text = "#F5F5F7" if dark else "#111114"
    return (f'<div style="display:flex;align-items:center;gap:{dot*0.36}px">'
            f'<div style="width:{dot}px;height:{dot}px;border-radius:50%;background:{color};display:flex;align-items:center;justify-content:center">'
            f'{glyph(g, dot*0.62, glyph_color(color))}</div>'
            f'<span class="rd" style="font-size:{font}px;font-weight:900;color:{text};white-space:nowrap">{E(name)}</span></div>')


def chip(name, g, color):
    return (f'<span class="chip" style="background:{color}26;color:{color}">{glyph(g, 15, color)}{E(name)}</span>')


# ---------------------------------------------------------------- Ansichten
def hero_card():
    tint = YELLOW
    lines = "".join(bin_line(n, g, c, 32, 18) for n, g, c in NEXT)
    return f'''
<div style="position:relative;border-radius:26px;padding:20px;background:#fff;overflow:hidden;box-shadow:0 6px 16px rgba(0,0,0,.08)">
  <div style="position:absolute;inset:0;background:linear-gradient(to bottom, {tint}29 0%, {tint}00 58%)"></div>
  <div style="position:relative">
    <div class="rd" style="font-size:12px;font-weight:900;letter-spacing:.8px;color:{ink(tint, False)}">FR 9. OKT</div>
    <div class="rd" style="font-size:40px;font-weight:1000;color:#111114;line-height:1.15;margin-top:2px">Morgen</div>
    <div class="rd" style="font-size:15px;font-weight:800;color:#8A8A92;margin-top:1px">abends rausstellen</div>
    <div style="display:flex;align-items:flex-end;margin-top:18px;gap:10px">
      <div style="display:flex;flex-direction:column;gap:10px">{lines}</div>
      <div style="flex:1"></div>
      <div class="rd" style="display:flex;align-items:center;gap:7px;background:#111114;color:#fff;border-radius:99px;padding:10px 14px;font-size:15px;font-weight:900">{sf("checkmark", 15, "#fff")}Erledigt</div>
    </div>
    <div style="display:flex;align-items:center;gap:8px;margin-top:14px" class="rd">
      <span style="font-size:12px;font-weight:900;color:#8A8A92">Danach</span>
      <span style="display:flex"><span style="width:11px;height:11px;border-radius:50%;background:{BIO};box-shadow:0 0 0 1.8px #fff"></span><span style="width:11px;height:11px;border-radius:50%;background:{PAPER};margin-left:-3px;box-shadow:0 0 0 1.8px #fff"></span></span>
      <span style="font-size:12px;font-weight:800;color:#8A8A92">in 6 Tagen · Bioabfall, Papier</span>
    </div>
  </div>
</div>'''


def pickups_card(count):
    rows = []
    for i, (cd, date, items) in enumerate(PICKUPS[:count]):
        chips = "".join(chip(n, g, c) for n, g, c in items)
        rows.append(f'''<div style="display:flex;gap:12px;padding:10px 0;align-items:flex-start">
  <div style="width:92px;flex:none"><div style="font-size:15px;font-weight:600">{cd}</div><div class="secondary" style="font-size:12px;margin-top:2px">{date}</div></div>
  <div style="display:flex;flex-wrap:wrap;gap:6px">{chips}</div></div>''')
        if i < count - 1:
            rows.append('<div class="divider"></div>')
    return f'''<div><div class="sechead">{sf("trash", 18, ACCENT)}Nächste Abholungen</div><div class="card" style="padding:6px 16px">{"".join(rows)}</div></div>'''


def avatar(initials, color, size):
    return (f'<div class="avatar" style="width:{size}px;height:{size}px;font-size:{size*0.36}px;'
            f'background:linear-gradient(135deg,{color},{color}B3)">{initials}</div>')


def birthdays_card(count):
    rows = []
    for i, (name, ini, color, years, date, cd, _) in enumerate(BIRTHDAYS[:count]):
        emoji = "🎉" if years in MILESTONES else "🎂"
        rows.append(f'''<div style="display:flex;align-items:center;gap:12px;padding:8px 0">
  {avatar(ini, color, 38)}
  <div style="flex:1;min-width:0"><div style="font-size:17px;font-weight:600">{E(name)}</div><div class="secondary" style="font-size:12px;margin-top:2px">wird {years} · {date}</div></div>
  <span style="font-size:17px">{emoji}</span>
  <span class="secondary" style="font-size:15px;font-weight:600">{cd}</span></div>''')
        if i < count - 1:
            rows.append('<div class="divider"></div>')
    return f'''<div><div class="sechead">{sf("cake", 18, ACCENT)}Geburtstage &amp; Termine</div><div class="card" style="padding:6px 16px">{"".join(rows)}</div></div>'''


def overview(w, h, ipad=False):
    pad = 16
    top = 76 if ipad else 54
    content = f'''
<div style="position:absolute;top:{top}px;left:0;right:0">
  <div class="navbar" style="{'height:56px' if ipad else ''}"><div class="roundbtn">{sf("filter", 22, "#1c1c1e")}</div></div>
  <div class="largetitle">Übersicht</div>
  <div style="padding:6px {pad}px 0;display:flex;flex-direction:column;gap:20px">
    {hero_card()}
    {pickups_card(6) + birthdays_card(5) if ipad else pickups_card(5) + birthdays_card(3)}
  </div>
</div>'''
    return f'<div class="screen light" style="width:{w}px;height:{h}px">{statusbar(ipad=ipad)}{content}{tabbar(0, ipad)}</div>'


def coverage(w, h, ipad=False):
    top = 76 if ipad else 54
    rows = []
    items = NDS
    for d in items:
        name = d["district"]
        if name.startswith("Kreisfreie Stadt "):
            disp = name[len("Kreisfreie Stadt "):] + " (Stadt)"
        else:
            rest = name.split(" ", 1)[1]
            low = rest.lower()
            disp = rest if (low.endswith("kreis") or low.startswith("region ")) else name
        d["disp"] = disp
    items = sorted(items, key=lambda x: x["disp"])
    covered = [d for d in items if d["regional"] > 0]
    show = covered[: (14 if ipad else 11)]
    for i, d in enumerate(show):
        n = d["regional"] + d["local"]
        mun = d["mun"]
        sub = f'{n} Entsorger · {mun} {"Gemeinde" if mun == 1 else "Gemeinden"}'
        rows.append(f'''<div style="display:flex;align-items:center;gap:12px;padding:11px 16px">
  {sf("checkcircle", 24, DONE)}
  <div style="flex:1;min-width:0"><div style="font-size:17px">{E(d["disp"])}</div><div class="secondary" style="font-size:12px;margin-top:2px">{sub}</div></div>
  {sf("chev", 14, "#C4C4C7")}</div>''')
        if i < len(show) - 1:
            rows.append('<div class="divider" style="margin-left:52px"></div>')
    width_style = "max-width:760px;margin:0 auto;" if ipad else ""
    content = f'''
<div style="position:absolute;top:{top}px;left:0;right:0;{width_style}">
  <div class="navbar" style="justify-content:flex-start"><div class="roundbtn">{sf("chev", 18, "#1c1c1e").replace('M9 5l7 7-7 7', 'M15 5l-7 7 7 7')}</div></div>
  <div class="largetitle">Abdeckung</div>
  <div style="margin:4px 16px 0;height:38px;border-radius:12px;background:rgba(118,118,128,.12);display:flex;align-items:center;gap:6px;padding:0 9px;font-size:17px">
     {sf("search", 18, "#8A8A8E")}<span>Niedersachsen</span><span style="width:2px;height:20px;background:{ACCENT};border-radius:1px"></span><span style="flex:1"></span>{sf("mic", 18, "#8A8A8E")}</div>
  <div style="margin:18px 16px 0;height:34px;border-radius:9px;background:rgba(118,118,128,.12);display:flex;padding:2px;font-size:13px;font-weight:500">
     <div style="flex:1;display:flex;align-items:center;justify-content:center">Noch nicht dabei (15)</div>
     <div style="flex:1;display:flex;align-items:center;justify-content:center;background:#fff;border-radius:7px;box-shadow:0 3px 8px rgba(0,0,0,.12);font-weight:600">Verfügbar (385)</div></div>
  <div class="secondary" style="font-size:13px;line-height:1.35;padding:8px 32px 0">385 von 400 Landkreisen und kreisfreien Städten sind angebunden. Halb gefüllter Kreis: nur einzelne Gemeinden sind dabei.</div>
  <div class="secondary" style="font-size:13px;padding:22px 32px 7px;text-transform:uppercase">Niedersachsen</div>
  <div style="margin:0 16px;background:#fff;border-radius:22px;overflow:hidden">{"".join(rows)}</div>
</div>'''
    return f'<div class="screen light" style="width:{w}px;height:{h}px">{statusbar(ipad=ipad)}{content}{tabbar(2, ipad)}</div>'


def birthdays(w, h, ipad=False):
    top = 76 if ipad else 54
    rows = []
    show = BIRTHDAYS[: (8 if ipad else 7)]
    for i, (name, ini, color, years, date, cd, gifts) in enumerate(show):
        badge = (f'<span style="font-size:12px;font-weight:700;padding:2px 6px;border-radius:99px;background:rgba(255,45,85,.15);color:#FF2D55">🎉 {years}</span>'
                 if years in MILESTONES else "")
        sub = f'wird {years} · {date}' + (f' · 🎁 {gifts}' if gifts else "")
        rows.append(f'''<div style="display:flex;align-items:center;gap:12px;padding:10px 16px">
  {avatar(ini, color, 44)}
  <div style="flex:1;min-width:0"><div style="display:flex;align-items:center;gap:6px;font-size:17px;font-weight:600">{E(name)}{badge}</div>
  <div class="secondary" style="font-size:12px;margin-top:2px">{sub}</div></div>
  <span style="font-size:15px;font-weight:600">{cd}</span></div>''')
        if i < len(show) - 1:
            rows.append('<div class="divider" style="margin-left:72px"></div>')
    width_style = "max-width:760px;margin:0 auto;" if ipad else ""
    content = f'''
<div style="position:absolute;top:{top}px;left:0;right:0;{width_style}">
  <div class="navbar"><div class="roundbtn">{sf("plus", 20, "#1c1c1e")}</div></div>
  <div class="largetitle">Geburtstage</div>
  <div style="margin:10px 16px 0;background:#fff;border-radius:22px;overflow:hidden">{"".join(rows)}</div>
</div>'''
    return f'<div class="screen light" style="width:{w}px;height:{h}px">{statusbar(ipad=ipad)}{content}{tabbar(3, ipad)}</div>'


def lockscreen(w, h, ipad=False):
    icon = '<img src="../appicon.png" style="width:38px;height:38px;border-radius:9px;flex:none">'
    note = f'''
<div style="display:flex;gap:10px;align-items:flex-start;padding:12px 14px;border-radius:24px;background:rgba(245,245,247,.72);backdrop-filter:blur(30px);color:#000">
  {icon}
  <div style="flex:1;min-width:0">
    <div style="display:flex;justify-content:space-between;font-size:15px"><b>Morgen wird abgeholt</b><span style="color:rgba(60,60,67,.6);font-size:14px">jetzt</span></div>
    <div style="font-size:15px;line-height:1.3;margin-top:1px">Gelber Sack und Restmüll – heute Abend rausstellen.</div>
  </div>
</div>'''
    actions = '''
<div style="margin-top:8px;border-radius:16px;overflow:hidden;background:rgba(245,245,247,.72);backdrop-filter:blur(30px);color:#000;font-size:17px">
  <div style="padding:13px 16px">✅ Erledigt – steht draußen</div><div class="divider" style="background:rgba(60,60,67,.3)"></div>
  <div style="padding:13px 16px">⏰ In 1 Stunde nochmal</div>
</div>'''
    note2 = f'''
<div style="display:flex;gap:10px;align-items:flex-start;padding:12px 14px;border-radius:24px;background:rgba(245,245,247,.6);backdrop-filter:blur(30px);color:#000;margin-top:10px">
  {icon}
  <div style="flex:1;min-width:0">
    <div style="display:flex;justify-content:space-between;font-size:15px"><b>🎁 Oma Erika hat in 3 Tagen Geburtstag</b><span style="color:rgba(60,60,67,.6);font-size:14px">18:00</span></div>
    <div style="font-size:15px;line-height:1.3;margin-top:1px">Wird 70 – runder Geburtstag! Noch ein Geschenk besorgen?</div>
  </div>
</div>'''
    # Sperrbildschirm-Widgets (accessoryRectangular aus PickupWidget.swift / BirthdayWidget.swift: Text ohne Hintergrund)
    gl = lambda g: glyph(g, 13, "#fff").replace('class="g"', 'class="g" style="display:inline-block;vertical-align:-2px"')
    widget = f'''
<div style="display:flex;justify-content:center;margin-top:12px"><div style="display:flex;gap:26px;text-align:left;color:#fff">
  <div style="width:150px"><div style="font-size:17px;font-weight:600">Morgen</div>
    <div style="font-size:12px;margin-top:2px">{gl("tt.sack")} Gelber Sack</div><div style="font-size:12px;margin-top:1px">{gl("tt.bin")} Restmüll</div></div>
  <div style="width:150px"><div style="font-size:17px;font-weight:600">🎂 Oma Erika</div>
    <div style="font-size:12px;margin-top:2px">wird 70 · So., 11. Okt.</div><div style="font-size:11px;opacity:.8;margin-top:1px">in 3 Tagen</div></div>
</div></div>'''
    col = "max-width:520px;margin:0 auto;" if ipad else ""
    clock_top = 110 if ipad else 76
    return f'''<div class="screen" style="width:{w}px;height:{h}px;background:
 radial-gradient(circle at 15% 8%, {YELLOW}CC 0, transparent 46%), radial-gradient(circle at 95% 62%, {PAPER}B0 0, transparent 50%),
 radial-gradient(circle at 10% 100%, {BIO}D0 0, transparent 50%), #10131A">
  {statusbar("#fff", ipad=ipad) if ipad else statusbar("#fff", time="", island=True).replace('<span style="width:54px;text-align:center"></span>', '<span></span>')}
  <div style="position:absolute;top:{clock_top}px;left:0;right:0;text-align:center;color:rgba(255,255,255,.92)">
    <div style="display:flex;justify-content:center;margin-bottom:6px">{sf("lock", 18, "rgba(255,255,255,.9)")}</div>
    <div style="font-size:21px;font-weight:600">Donnerstag, 8. Oktober</div>
    <div class="rd" style="font-size:{130 if ipad else 104}px;font-weight:700;line-height:1;margin-top:2px;letter-spacing:-2px">19:00</div>
    {widget}
  </div>
  <div style="position:absolute;left:12px;right:12px;bottom:{260 if ipad else 150}px;{col}">{note}{actions}{note2}</div>
  <div style="position:absolute;bottom:52px;left:46px;width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.3);display:flex;align-items:center;justify-content:center">{sf("torch", 22, "#fff")}</div>
  <div style="position:absolute;bottom:52px;right:46px;width:50px;height:50px;border-radius:25px;background:rgba(0,0,0,.3);display:flex;align-items:center;justify-content:center">{sf("camera", 22, "#fff")}</div>
  <div class="homeind" style="background:#fff"></div>
</div>'''


# ---------------------------------------------------------------- Watch
def watch_page(kind, w, h):
    base = f'width:{w}px;height:{h}px;position:relative;overflow:hidden;color:#F5F5F7;font-family:Inter,sans-serif'
    timebar = f'<div style="position:absolute;top:{h*0.035}px;right:{w*0.09}px;font-size:{w*0.075}px;font-weight:600;color:#fff">19:00</div>'
    s = w / 205  # Inhalte relativ zur 46-mm-Größe skalieren
    if kind == "pickup":
        lines = "".join(f'<div style="margin-top:{8*s}px">{bin_line(n, g, c, 26*s, 16*s, dark=True)}</div>' for n, g, c in NEXT)
        body = f'''
<div style="position:absolute;inset:0;background:linear-gradient(to bottom, {YELLOW}73 0%, #000 50%)"></div>
{timebar}
<div style="position:absolute;left:{w*0.075}px;right:{w*0.075}px;top:{h*0.13}px">
  <div class="rd" style="font-size:{12*s}px;font-weight:900;letter-spacing:.6px;color:{YELLOW}">FR 9. OKT</div>
  <div class="rd" style="font-size:{30*s}px;font-weight:1000;line-height:1.1">Morgen</div>
  <div class="rd" style="font-size:{13*s}px;font-weight:800;color:#9A9AA4">abends rausstellen</div>
  <div style="margin-top:{4*s}px">{lines}</div>
  <div class="rd" style="margin-top:{14*s}px;height:{40*s}px;border-radius:{20*s}px;background:rgba(245,245,247,.92);color:#111114;display:flex;align-items:center;justify-content:center;gap:{6*s}px;font-size:{16*s}px;font-weight:900">{sf("checkmark", 16*s, "#111114")}Erledigt</div>
</div>'''
    elif kind == "upcoming":
        cards = ""
        for cd, date, items in PICKUPS[1:3]:
            ls = "".join(f'<div style="margin-top:{5*s}px">{bin_line(n, g, c, 18*s, 13*s, dark=True)}</div>' for n, g, c in items)
            short = date.replace(".,", "").replace(".", "")
            cards += f'''<div style="margin-top:{12*s}px;padding:{10*s}px;border-radius:{14*s}px;background:#1C1C20">
  <div class="rd" style="display:flex;justify-content:space-between;align-items:baseline"><span style="font-size:{15*s}px;font-weight:900">{cd}</span><span style="font-size:{12*s}px;font-weight:800;color:#9A9AA4">{date}</span></div>{ls}</div>'''
        body = f'''<div style="position:absolute;inset:0;background:#000"></div>{timebar}
<div style="position:absolute;left:{w*0.06}px;right:{w*0.06}px;top:{h*0.11}px">
  <div class="rd" style="font-size:{11*s}px;font-weight:900;letter-spacing:1px;color:#9A9AA4">DANACH</div>{cards}</div>'''
    else:
        rows = ""
        for name, ini, color, years, date, cd, _ in BIRTHDAYS[:4]:
            rows += f'''<div style="display:flex;align-items:center;gap:{10*s}px;margin-top:{10*s}px">
  <div class="avatar rd" style="width:{32*s}px;height:{32*s}px;font-size:{12*s}px;font-weight:1000;background:linear-gradient(135deg,{color},{color}BF)">{ini}</div>
  <div class="rd" style="min-width:0"><div style="font-size:{15*s}px;font-weight:900;white-space:nowrap">{E(name)}</div>
  <div style="font-size:{12*s}px;font-weight:900;white-space:nowrap"><span style="color:#9A9AA4">wird {years} ·</span> <span style="color:#FF6AA8">{cd}</span></div></div></div>'''
        body = f'''<div style="position:absolute;inset:0;background:linear-gradient(to bottom, #FF5FA259 0%, #000 50%)"></div>{timebar}
<div style="position:absolute;left:{w*0.06}px;right:{w*0.06}px;top:{h*0.11}px">
  <div class="rd" style="display:flex;justify-content:space-between;font-size:{11*s}px;font-weight:900;letter-spacing:1px;color:#FF6AA8"><span>GEBURTSTAGE</span><span>🎂</span></div>{rows}</div>'''
    return f'<div style="{base}">{body}</div>'


# ---------------------------------------------------------------- Marketing-Rahmen
SLIDES = [
    ("overview", "Nie wieder die Tonne vergessen", "Alle Abfuhrtermine auf einen Blick", YELLOW, REST),
    ("lock", "Erinnert dich am Vorabend", "„Erledigt“ direkt aus der Mitteilung", PAPER, YELLOW),
    ("coverage", "Über 380 Landkreise", "Termine direkt vom Entsorger", DONE, PAPER),
    ("birthdays", "Geburtstage gleich mit", "Mit Alter und runden Geburtstagen", "#FF5FA2", "#FF9A4A"),
]
SCREENS = {"overview": overview, "coverage": coverage, "birthdays": birthdays, "lock": lockscreen}


def marketing(kind, title, sub, c1, c2, W, H, sw, sh, ipad):
    screen = SCREENS[kind](sw, sh, ipad)
    k = (W * (0.80 if ipad else 0.80)) / sw
    radius = 40 if ipad else 56
    bezel = 14 if ipad else 12
    top = H * (0.19 if ipad else 0.215)
    tsize = W * (0.054 if ipad else 0.083)
    return f'''<div class="canvas" style="width:{W}px;height:{H}px;background:
 radial-gradient(circle at 12% 0%, {c1}E6 0, transparent 55%), radial-gradient(circle at 100% 100%, {c2}CC 0, transparent 55%), #0F1218">
  <div style="position:absolute;top:{H*0.055}px;left:{W*0.07}px;right:{W*0.07}px;text-align:center;color:#fff">
    <div class="rd" style="font-size:{tsize}px;font-weight:1000;line-height:1.08;letter-spacing:-.5px">{E(title)}</div>
    <div class="rd" style="font-size:{tsize*0.46}px;font-weight:800;opacity:.82;margin-top:{H*0.012}px">{E(sub)}</div>
  </div>
  <div style="position:absolute;top:{top}px;left:50%;width:{sw}px;height:{sh}px;transform:translateX(-50%) scale({k});transform-origin:top center;
       border-radius:{radius}px;box-shadow:0 0 0 {bezel}px #1B1D22, 0 0 0 {bezel+2}px #3A3D44, 0 40px 80px rgba(0,0,0,.55);overflow:hidden">{screen}</div>
</div>'''


def page(body, W, H):
    return f'<!doctype html><html lang="de"><head><meta charset="utf-8"><style>{CSS} html,body{{width:{W}px;height:{H}px;overflow:hidden}}</style></head><body>{body}</body></html>'


DEVICES = {
    # Name: (Pixel B×H, Skalierung, Punkte des Bildschirms im Rahmen, iPad?)
    "iPhone-6.3": (1206, 2622, 3, (402, 874), False),
    "iPhone-6.1": (1179, 2556, 3, (393, 852), False),
    "iPhone-6.9": (1320, 2868, 3, (440, 956), False),
    "iPhone-6.7": (1290, 2796, 3, (430, 932), False),
    "iPad-13": (2064, 2752, 2, (1032, 1376), True),
}
WATCHES = {
    "Watch-Ultra-422x514": (422, 514),
    "Watch-46mm-416x496": (416, 496),
    "Watch-Ultra-410x502": (410, 502),
    "Watch-45mm-396x484": (396, 484),
}

jobs = []
for dev, (pw, ph, scale, (sw, sh), ipad) in DEVICES.items():
    W, H = pw // scale, ph // scale
    for i, (kind, title, sub, c1, c2) in enumerate(SLIDES, 1):
        name = f"{dev}_{i}_{kind}"
        open(os.path.join(OUT, name + ".html"), "w").write(page(marketing(kind, title, sub, c1, c2, W, H, sw, sh, ipad), W, H))
        jobs.append(dict(name=name, dev=dev, w=W, h=H, scale=scale))
for dev, (pw, ph) in WATCHES.items():
    W, H = pw / 2, ph / 2
    for i, kind in enumerate(["pickup", "upcoming", "birthdays"], 1):
        name = f"{dev}_{i}_{kind}"
        open(os.path.join(OUT, name + ".html"), "w").write(page(watch_page(kind, W, H), W, H))
        jobs.append(dict(name=name, dev=dev, w=W, h=H, scale=2))
json.dump(jobs, open(os.path.join(HERE, "jobs.json"), "w"))
print(len(jobs), "Seiten")
