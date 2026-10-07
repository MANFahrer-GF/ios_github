// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-blue; icon-glyph: trash-alt;
/*
 * Tonne & Torte – Widget für Scriptable (https://scriptable.app)
 *
 * Einrichtung:
 * 1. Scriptable aus dem App Store laden (kostenlos).
 * 2. Dieses Skript als neues Skript einfügen und „TonneUndTorte“ nennen.
 * 3. Widget-URL aus den Einstellungen der Web-App (Abschnitt „Widget“) unten bei
 *    WIDGET_URL eintragen – oder beim Widget als „Parameter“ hinterlegen.
 * 4. Home-Bildschirm lange drücken → „+“ → Scriptable → Größe wählen → Widget bearbeiten →
 *    Script: TonneUndTorte, When Interacting: Open URL.
 *
 * Unterstützt: klein, mittel, groß sowie Sperrbildschirm (rechteckig, rund, inline).
 */

const WIDGET_URL = ""; // z. B. "https://tonne.deine-domain.de/widget.php?token=ABC123"

// ------------------------------------------------------------------ Daten
const url = (args.widgetParameter || WIDGET_URL || "").trim();
const fm = FileManager.local();
const cachePath = fm.joinPath(fm.cacheDirectory(), "tonne-und-torte-widget.json");

async function loadData() {
  if (!url) throw new Error("Keine Widget-URL eingetragen.");
  try {
    const req = new Request(url);
    req.timeoutInterval = 15;
    const json = await req.loadJSON();
    if (!json || !json.ok) throw new Error((json && json.error) || "Ungültige Antwort");
    fm.writeString(cachePath, JSON.stringify(json));
    return json;
  } catch (e) {
    if (fm.fileExists(cachePath)) {
      const cached = JSON.parse(fm.readString(cachePath));
      cached.offline = true;
      return cached;
    }
    throw e;
  }
}

// ------------------------------------------------------------------ Darstellung
const family = config.widgetFamily || "medium";
const isAccessory = family.startsWith("accessory");
const white = Color.white();
const dim = new Color("#FFFFFF", 0.78);
const faint = new Color("#FFFFFF", 0.55);

function hexColor(hex, alpha) {
  try { return new Color(hex, alpha === undefined ? 1 : alpha); } catch (e) { return new Color("#2F6FED", alpha === undefined ? 1 : alpha); }
}
function darker(hex) {
  const c = hexColor(hex);
  return new Color(`#${Math.round(c.red * 255 * 0.6).toString(16).padStart(2, "0")}${Math.round(c.green * 255 * 0.6).toString(16).padStart(2, "0")}${Math.round(c.blue * 255 * 0.6).toString(16).padStart(2, "0")}`);
}
function shortDate(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(y, m - 1, d);
  const wd = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][dt.getDay()];
  return `${wd}, ${d}.${m}.`;
}
function itemLine(items, max) {
  const names = items.map((i) => `${i.icon} ${i.title}`);
  const shown = names.slice(0, max);
  const rest = names.length - shown.length;
  return shown.join(", ") + (rest > 0 ? ` +${rest}` : "");
}

function buildWidget(data) {
  const w = new ListWidget();
  w.url = data.url || url;
  w.refreshAfterDate = new Date(Date.now() + 30 * 60 * 1000);
  const next = data.pickups[0];
  const heroColor = next ? next.items[0].color : "#2F6FED";

  if (isAccessory) return buildAccessory(w, data, next);

  const grad = new LinearGradient();
  grad.colors = [hexColor(heroColor), darker(heroColor)];
  grad.locations = [0, 1];
  w.backgroundGradient = grad;
  w.setPadding(14, 14, 12, 14);

  // Kopfzeile
  const head = w.addStack();
  head.centerAlignContent();
  const eyebrow = head.addText(!next ? "ALLES RUHIG" : next.days === 0 ? "HEUTE" : next.days === 1 ? "MORGEN" : "NÄCHSTE ABHOLUNG");
  eyebrow.font = Font.semiboldSystemFont(10);
  eyebrow.textColor = dim;
  head.addSpacer();
  if (data.offline) { const o = head.addText("offline"); o.font = Font.systemFont(9); o.textColor = faint; }
  const ico = head.addText(next ? next.items[0].icon : "✅");
  ico.font = Font.systemFont(family === "small" ? 14 : 16);

  w.addSpacer(2);
  const title = w.addText(!next ? "Keine Abholung" : next.days === 0 ? "Heute wird abgeholt" : next.days === 1 ? "Heute Abend rausstellen!" : `In ${next.days} Tagen`);
  title.font = Font.boldSystemFont(family === "small" ? 15 : 18);
  title.textColor = white;
  title.minimumScaleFactor = 0.7;
  title.lineLimit = 1;

  if (next) {
    const chips = w.addText(itemLine(next.items, family === "small" ? 2 : 4));
    chips.font = Font.semiboldSystemFont(family === "small" ? 11 : 13);
    chips.textColor = white;
    chips.lineLimit = family === "small" ? 2 : 1;
    chips.minimumScaleFactor = 0.8;
    if (next.items[0].location && family !== "small") {
      const loc = w.addText([...new Set(next.items.map((i) => i.location).filter(Boolean))].join(" · "));
      loc.font = Font.systemFont(11); loc.textColor = dim;
    }
    const dateText = w.addText(shortDate(next.date));
    dateText.font = Font.systemFont(11);
    dateText.textColor = dim;
  }

  // Weitere Tage (mittel/groß)
  const more = data.pickups.slice(1, family === "large" ? 7 : 2);
  if (family !== "small" && more.length) {
    w.addSpacer(8);
    const box = w.addStack();
    box.layoutVertically();
    box.backgroundColor = new Color("#000000", 0.18);
    box.cornerRadius = 10;
    box.setPadding(8, 10, 8, 10);
    more.forEach((day, i) => {
      if (i > 0) box.addSpacer(4);
      const row = box.addStack();
      row.centerAlignContent();
      const when = row.addText(day.label);
      when.font = Font.semiboldSystemFont(11); when.textColor = white;
      when.lineLimit = 1;
      row.addSpacer(6);
      const what = row.addText(itemLine(day.items, 3));
      what.font = Font.systemFont(11); what.textColor = dim; what.lineLimit = 1; what.minimumScaleFactor = 0.8;
      row.addSpacer();
      const d = row.addText(shortDate(day.date));
      d.font = Font.systemFont(10); d.textColor = faint;
    });
  }

  // Geburtstage (groß)
  if (family === "large" && data.birthdays.length) {
    w.addSpacer(8);
    const bh = w.addText("🎂 GEBURTSTAGE");
    bh.font = Font.semiboldSystemFont(10); bh.textColor = dim;
    data.birthdays.slice(0, 3).forEach((b) => {
      const row = w.addStack();
      row.centerAlignContent();
      const n = row.addText(`${b.name}${b.age !== null && b.age !== undefined ? ` (${b.age})` : ""}`);
      n.font = Font.semiboldSystemFont(12); n.textColor = white; n.lineLimit = 1;
      row.addSpacer();
      const c = row.addText(b.days === 0 ? "🎉 Heute" : b.days === 1 ? "Morgen" : `in ${b.days} Tagen · ${shortDate(b.date)}`);
      c.font = Font.systemFont(11); c.textColor = dim;
    });
  }
  w.addSpacer();
  return w;
}

function buildAccessory(w, data, next) {
  if (family === "accessoryInline") {
    w.addText(!next ? "🗑️ Keine Abholung" : `${next.items[0].icon} ${next.label}: ${next.items.map((i) => i.title).join(", ")}`);
    return w;
  }
  if (family === "accessoryCircular") {
    w.addAccessoryWidgetBackground = true;
    const t = w.addText(next ? next.items[0].icon : "🗑️");
    t.font = Font.systemFont(22); t.centerAlignText();
    const n = w.addText(!next ? "–" : next.days === 0 ? "heute" : next.days === 1 ? "morgen" : `${next.days} T.`);
    n.font = Font.semiboldSystemFont(10); n.centerAlignText();
    return w;
  }
  // accessoryRectangular
  w.addAccessoryWidgetBackground = true;
  w.setPadding(4, 6, 4, 6);
  const t = w.addText(!next ? "Keine Abholung" : `${next.label}: ${next.items.map((i) => i.icon + " " + i.title).join(", ")}`);
  t.font = Font.semiboldSystemFont(13); t.lineLimit = 2; t.minimumScaleFactor = 0.8;
  const second = data.pickups[1];
  if (second) {
    const s = w.addText(`${second.label}: ${second.items.map((i) => i.title).join(", ")}`);
    s.font = Font.systemFont(11); s.lineLimit = 1; s.textOpacity = 0.7;
  }
  return w;
}

function errorWidget(message) {
  const w = new ListWidget();
  w.backgroundColor = new Color("#DC2626");
  const t = w.addText("Tonne & Torte");
  t.font = Font.boldSystemFont(14); t.textColor = white;
  const m = w.addText(message);
  m.font = Font.systemFont(11); m.textColor = white;
  return w;
}

// ------------------------------------------------------------------ Start
let widget;
try {
  widget = buildWidget(await loadData());
} catch (e) {
  widget = errorWidget(String(e.message || e));
}
if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}
Script.complete();
