/* Tonne & Torte – PWA-Frontend (Vanilla JS, kein Build-Schritt) */
(() => {
  'use strict';

  // ---------------------------------------------------------------- Helfer
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const el = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const pad = (n) => String(n).padStart(2, '0');
  const toDate = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
  const toStr = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const today = () => toStr(new Date());
  const addDays = (s, n) => { const d = toDate(s); d.setDate(d.getDate() + n); return toStr(d); };
  const daysUntil = (s) => Math.round((toDate(s) - toDate(today())) / 86400000);
  const fmt = {
    short: (s) => toDate(s).toLocaleDateString('de-DE', { weekday: 'short', day: 'numeric', month: 'short' }),
    long: (s) => toDate(s).toLocaleDateString('de-DE', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }),
    dayMonth: (s) => toDate(s).toLocaleDateString('de-DE', { day: 'numeric', month: 'long' }),
    monthYear: (d) => d.toLocaleDateString('de-DE', { month: 'long', year: 'numeric' }),
    countdown: (s) => {
      const n = daysUntil(s);
      if (n === 0) return 'Heute';
      if (n === 1) return 'Morgen';
      if (n === 2) return 'Übermorgen';
      if (n === -1) return 'Gestern';
      if (n < 0) return `vor ${-n} Tagen`;
      return `in ${n} Tagen`;
    },
    relative: (iso) => {
      if (!iso) return 'nie';
      const diff = (Date.now() - new Date(iso.replace(' ', 'T'))) / 60000;
      if (diff < 2) return 'gerade eben';
      if (diff < 60) return `vor ${Math.round(diff)} Min.`;
      if (diff < 60 * 36) return `vor ${Math.round(diff / 60)} Std.`;
      return `vor ${Math.round(diff / 1440)} Tagen`;
    },
  };
  const PALETTE = ['#5B6470', '#8B5E34', '#2F6FED', '#F2C230', '#2E9E6B', '#B45309', '#7C3AED', '#DC2626', '#EC4899', '#0D9488', '#F97316', '#0EA5E9'];
  const WASTE_ICONS = ['🗑️', '🍂', '📰', '🛍️', '🍾', '🛋️', '📦', '🌳', '☣️', '🎄', '👕', '🔋', '🪵', '♻️', '🧹', '🚛'];
  const HOME_ICONS = ['🏠', '🏡', '🏢', '🏘️', '🏕️', '🌲', '🚗', '🏛️', '🌊', '⛰️'];
  const INTERVALS = [[0, 'Kein fester Rhythmus'], [1, 'Jede Woche'], [2, 'Alle 2 Wochen'], [3, 'Alle 3 Wochen'], [4, 'Alle 4 Wochen'], [6, 'Alle 6 Wochen'], [8, 'Alle 8 Wochen']];
  const REMIND_BEFORE = [[0, 'Nur am Geburtstag'], [1, '1 Tag vorher'], [2, '2 Tage vorher'], [3, '3 Tage vorher'], [7, '1 Woche vorher'], [14, '2 Wochen vorher']];

  // ---------------------------------------------------------------- API
  async function api(action, { method = 'GET', body = null, params = {} } = {}) {
    const url = new URL('api.php', location.href);
    url.searchParams.set('action', action);
    Object.entries(params).forEach(([k, v]) => { if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, v); });
    const res = await fetch(url, {
      method,
      headers: { 'X-Requested-With': 'TonneTorte', ...(body ? { 'Content-Type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
      credentials: 'same-origin',
    });
    let json = null;
    try { json = await res.json(); } catch (e) { /* kein JSON */ }
    if (!res.ok || !json || !json.ok) {
      const err = new Error((json && json.error) || `HTTP ${res.status}`);
      err.status = res.status;
      err.data = json;
      throw err;
    }
    return json.data;
  }
  const post = (action, body = {}) => api(action, { method: 'POST', body });

  // ---------------------------------------------------------------- Zustand
  const state = {
    boot: null,
    filter: localStorage.getItem('tt.filter') || '',
    cal: { month: new Date(new Date().getFullYear(), new Date().getMonth(), 1), selected: today() },
  };
  const setFilter = (v) => { state.filter = v; localStorage.setItem('tt.filter', v); };

  // ---------------------------------------------------------------- Toast & Modal
  function toast(msg, type = '') {
    const t = el(`<div class="toast ${type}">${esc(msg)}</div>`);
    $('#toast-root').appendChild(t);
    setTimeout(() => t.remove(), type === 'error' ? 5000 : 2600);
  }
  const fail = (e) => toast(e && e.message ? e.message : 'Unbekannter Fehler', 'error');

  function openModal({ title, body, buttons = [], onClose = null }) {
    const root = $('#modal-root');
    const wrap = el(`<div class="modal-backdrop"><div class="modal" role="dialog" aria-modal="true">
      <div class="modal-head"><h3>${esc(title)}</h3><button class="btn ghost" data-close>Schließen</button></div>
      <div class="modal-body"></div>
      ${buttons.length ? '<div class="modal-foot"></div>' : ''}
    </div></div>`);
    const bodyEl = $('.modal-body', wrap);
    if (typeof body === 'string') bodyEl.innerHTML = body; else bodyEl.appendChild(body);
    const close = () => { wrap.remove(); if (onClose) onClose(); };
    $('[data-close]', wrap).onclick = close;
    wrap.addEventListener('click', (e) => { if (e.target === wrap) close(); });
    const foot = $('.modal-foot', wrap);
    buttons.forEach((b) => {
      const btn = el(`<button class="btn ${b.cls || ''}">${esc(b.label)}</button>`);
      btn.onclick = async () => {
        btn.disabled = true;
        try { const r = await b.onClick(bodyEl, close); if (r !== false && b.closeAfter !== false) close(); }
        catch (e) { fail(e); } finally { btn.disabled = false; }
      };
      foot.appendChild(btn);
    });
    root.appendChild(wrap);
    return { close, body: bodyEl, el: wrap };
  }
  const confirmDialog = (text, label = 'Löschen') => new Promise((resolve) => {
    openModal({
      title: 'Sicher?', body: `<p>${esc(text)}</p>`,
      buttons: [{ label: 'Abbrechen', cls: 'secondary', onClick: () => resolve(false) }, { label, cls: 'danger', onClick: () => resolve(true) }],
      onClose: () => resolve(false),
    });
  });

  // ---------------------------------------------------------------- Bausteine
  const badge = (icon, color, cls = '') => `<div class="badge ${cls}" style="--c:${esc(color)}">${esc(icon)}</div>`;
  const chip = (ev, withLoc = true) => `<span class="chip" style="--c:${esc(ev.color)}">${esc(ev.icon)} ${esc(ev.title)}${withLoc && ev.location && multiLocation() ? `<span class="loc">· ${esc(ev.location)}</span>` : ''}</span>`;
  const multiLocation = () => (state.boot?.locations?.length || 0) > 1;
  const empty = (icon, text) => `<div class="empty"><div class="ico">${icon}</div><p>${esc(text)}</p></div>`;
  const swatches = (name, current) => `<div class="swatches" data-swatches="${name}">
      ${PALETTE.map((c) => `<button type="button" class="swatch ${c === current.toUpperCase() ? 'active' : ''}" style="background:${c}" data-color="${c}"></button>`).join('')}
      <label class="swatch custom"><input type="color" value="${esc(current)}"></label>
      <input type="hidden" name="${name}" value="${esc(current)}">
    </div>`;
  const emojiGrid = (name, current, icons) => `<div class="emoji-grid" data-emoji="${name}">
      ${icons.map((i) => `<button type="button" class="${i === current ? 'active' : ''}" data-icon="${i}">${i}</button>`).join('')}
      <input type="hidden" name="${name}" value="${esc(current)}">
    </div>`;
  function wirePickers(root) {
    $$('[data-swatches]', root).forEach((box) => {
      const hidden = $('input[type=hidden]', box);
      $$('.swatch[data-color]', box).forEach((b) => b.onclick = () => { hidden.value = b.dataset.color; $$('.swatch', box).forEach((x) => x.classList.remove('active')); b.classList.add('active'); });
      $('input[type=color]', box).oninput = (e) => { hidden.value = e.target.value.toUpperCase(); $$('.swatch', box).forEach((x) => x.classList.remove('active')); };
    });
    $$('[data-emoji]', root).forEach((box) => {
      const hidden = $('input[type=hidden]', box);
      $$('button', box).forEach((b) => b.onclick = () => { hidden.value = b.dataset.icon; $$('button', box).forEach((x) => x.classList.remove('active')); b.classList.add('active'); });
    });
  }
  const formData = (form) => {
    const out = {};
    new FormData(form).forEach((v, k) => { out[k] = v; });
    $$('input[type=checkbox]', form).forEach((c) => { out[c.name] = c.checked; });
    return out;
  };
  const switchRow = (name, label, checked) => `<label class="switch"><span>${esc(label)}</span><input type="checkbox" name="${name}" ${checked ? 'checked' : ''}></label>`;
  const filterSelect = () => multiLocation() ? `<select class="filter-select" aria-label="Standort">
      <option value="">Alle Standorte</option>
      ${state.boot.locations.map((l) => `<option value="${l.id}" ${String(l.id) === state.filter ? 'selected' : ''}>${esc(l.icon)} ${esc(l.name)}</option>`).join('')}
    </select>` : '';
  function wireFilter(root, rerender) {
    const sel = $('.filter-select', root);
    if (sel) sel.onchange = () => { setFilter(sel.value); rerender(); };
  }

  // ---------------------------------------------------------------- Router
  const routes = {
    '': 'overview', 'kalender': 'calendar', 'muell': 'waste', 'geburtstage': 'birthdays', 'einstellungen': 'settings',
  };
  function parseHash() {
    const parts = location.hash.replace(/^#\/?/, '').split('/').filter(Boolean);
    return { route: routes[parts[0] || ''] || parts[0] || 'overview', param: parts[1] || null };
  }
  window.addEventListener('hashchange', () => render());

  async function reloadBoot() { state.boot = await api('bootstrap'); }

  async function start() {
    try {
      await reloadBoot();
      render();
      registerSW();
    } catch (e) {
      if (e.status === 428) renderAuth('setup');
      else if (e.status === 401) renderAuth('login');
      else { $('#app').innerHTML = `<div class="auth"><div class="card"><div class="logo">⚠️</div><h1>Fehler</h1><p>${esc(e.message)}</p></div></div>`; }
    }
  }

  function renderAuth(mode) {
    const setup = mode === 'setup';
    $('#app').innerHTML = `<div class="auth"><div class="card">
      <div class="logo">🗑️🎂</div>
      <h1>Tonne &amp; Torte</h1>
      <p>${setup ? 'Willkommen! Lege ein Passwort fest, um die App zu schützen.' : 'Bitte anmelden.'}</p>
      <form>
        <label class="field"><span>Passwort</span><input type="password" name="password" autocomplete="${setup ? 'new-password' : 'current-password'}" required minlength="6"></label>
        ${setup ? '<label class="field"><span>Passwort wiederholen</span><input type="password" name="password2" autocomplete="new-password" required minlength="6"></label>' : ''}
        <button class="btn block" type="submit">${setup ? 'Loslegen' : 'Anmelden'}</button>
      </form>
    </div></div>`;
    $('#app form').onsubmit = async (e) => {
      e.preventDefault();
      const d = formData(e.target);
      if (setup && d.password !== d.password2) return toast('Die Passwörter stimmen nicht überein.', 'error');
      try {
        await post(setup ? 'setup' : 'login', { password: d.password });
        await start();
      } catch (err) { fail(err); }
    };
  }

  function shell(content, activeRoute) {
    const tabs = [['', '🏠', 'Übersicht'], ['kalender', '📅', 'Kalender'], ['muell', '🗑️', 'Müll'], ['geburtstage', '🎂', 'Geburtstage'], ['einstellungen', '⚙️', 'Einstellungen']];
    const active = Object.entries(routes).find(([, v]) => v === activeRoute)?.[0] ?? '';
    $('#app').innerHTML = `<div class="shell">
      <nav class="tabbar"><span class="brand">🗑️ Tonne &amp; Torte</span>
        ${tabs.map(([r, i, l]) => `<a href="#/${r}" class="${r === active ? 'active' : ''}"><span class="ico">${i}</span><span>${l}</span></a>`).join('')}
      </nav>
      <main class="main"></main>
    </div>`;
    const main = $('.main');
    if (typeof content === 'string') main.innerHTML = content; else main.appendChild(content);
    return main;
  }

  async function render() {
    if (!state.boot) return;
    const { route, param } = parseHash();
    try {
      switch (route) {
        case 'overview': return await pageOverview();
        case 'calendar': return await pageCalendar();
        case 'waste': return param ? await pageWasteDetail(Number(param)) : pageWaste();
        case 'standort': return pageLocation(Number(param));
        case 'birthdays': return pageBirthdays();
        case 'settings': return pageSettings();
        default: location.hash = '#/';
      }
    } catch (e) {
      if (e.status === 401) return renderAuth('login');
      fail(e);
    }
  }

  // ---------------------------------------------------------------- Übersicht
  async function pageOverview() {
    const days = await api('upcoming', { params: { days: 60, location: state.filter } });
    const wasteDays = days.map((d) => ({ date: d.date, events: d.events.filter((e) => e.kind === 'waste') })).filter((d) => d.events.length);
    const birthdays = days.flatMap((d) => d.events.filter((e) => e.kind === 'birthday'));
    const next = wasteDays[0];
    const n = next ? daysUntil(next.date) : null;
    const heroColor = next ? next.events[0].color : '#2F6FED';
    const eyebrow = !next ? 'Alles ruhig' : n === 0 ? 'Heute' : n === 1 ? 'Morgen' : 'Nächste Abholung';
    const title = !next ? 'Keine Abholung geplant' : n === 0 ? 'Heute wird abgeholt' : n === 1 ? 'Heute Abend rausstellen!' : `In ${n} Tagen`;

    const main = shell(`
      <div class="page-head"><h1>Übersicht</h1><div class="actions">${filterSelect()}</div></div>
      ${pushBanner()}
      <section class="hero" style="--c:${esc(heroColor)}">
        <div class="row between"><div><div class="eyebrow">${eyebrow}</div><h2>${esc(title)}</h2></div><div class="big-ico">${next ? esc(next.events[0].icon) : '✅'}</div></div>
        ${next ? `<div class="chips">${next.events.map((e) => chip(e)).join('')}</div><div class="date">${esc(fmt.long(next.date))}</div>`
          : '<div class="date">Lege unter „Müll“ Standorte und Termine an oder aktualisiere deine Quellen.</div>'}
      </section>
      <div class="section-title"><span class="ico">🗑️</span>Nächste Abholungen</div>
      <div class="card">${wasteDays.length ? wasteDays.slice(0, 8).map((d) => `<div class="day-row">
            <div class="when"><b>${esc(fmt.countdown(d.date))}</b><span>${esc(fmt.short(d.date))}</span></div>
            <div class="chips">${d.events.map((e) => chip(e)).join('')}</div></div>`).join('')
        : empty('🧘', 'Keine Abholungen in den nächsten 60 Tagen.')}</div>
      <div class="section-title"><span class="ico">🎂</span>Geburtstage</div>
      <div class="card">${birthdays.length ? birthdays.slice(0, 6).map((e) => `<div class="list-item">
            ${badge(e.initials, e.color, 'initials')}
            <div class="grow"><div class="title">${esc(e.title)}</div><div class="subtitle">${esc(e.subtitle)} · ${esc(fmt.short(e.date))}</div></div>
            <b style="color:${daysUntil(e.date) === 0 ? 'var(--pink)' : 'var(--muted)'}">${daysUntil(e.date) === 0 ? '🎉 Heute' : esc(fmt.countdown(e.date))}</b></div>`).join('')
        : empty('🎈', state.boot.people.length ? 'In den nächsten 60 Tagen hat niemand Geburtstag.' : 'Noch keine Geburtstage eingetragen.')}</div>
    `, 'overview');
    wireFilter(main, pageOverview);
    wirePushBanner(main);
  }

  function pushBanner() {
    if (!('Notification' in window) || Notification.permission === 'granted' || localStorage.getItem('tt.pushBannerHidden')) return '';
    return `<div class="banner"><span class="ico">🔔</span><div class="grow"><b>Erinnerungen aktivieren</b><div class="small muted">Damit du den Gelben Sack nicht verpasst: Push einschalten oder Kalender abonnieren.</div></div><a class="btn sm" href="#/einstellungen">Einrichten</a></div>`;
  }
  function wirePushBanner() { /* Link reicht */ }

  // ---------------------------------------------------------------- Kalender
  async function pageCalendar() {
    const m = state.cal.month;
    const first = new Date(m.getFullYear(), m.getMonth(), 1);
    const last = new Date(m.getFullYear(), m.getMonth() + 1, 0);
    const offset = (first.getDay() + 6) % 7; // Montag = 0
    const gridStart = toStr(new Date(first.getFullYear(), first.getMonth(), 1 - offset));
    const gridEnd = addDays(gridStart, 41);
    const events = await api('range', { params: { from: gridStart, to: gridEnd, location: state.filter } });
    const byDay = {};
    events.forEach((e) => { (byDay[e.date] ||= []).push(e); });
    if (state.cal.selected < gridStart || state.cal.selected > gridEnd) state.cal.selected = toStr(first);

    const cells = [];
    for (let i = 0; i < 42; i++) {
      const d = addDays(gridStart, i);
      const inMonth = d >= toStr(first) && d <= toStr(last);
      const evs = byDay[d] || [];
      const dots = evs.filter((e) => e.kind === 'waste').slice(0, 4).map((e) => `<span class="dot" style="background:${esc(e.color)}"></span>`).join('');
      const cake = evs.some((e) => e.kind === 'birthday') ? '<span class="cake">🎂</span>' : '';
      cells.push(`<div class="cal-cell ${inMonth ? '' : 'other'} ${d === today() ? 'today' : ''} ${d === state.cal.selected ? 'selected' : ''}" data-date="${d}">
        <span class="num">${toDate(d).getDate()}</span><span class="dots">${dots}${cake}</span></div>`);
    }
    const sel = byDay[state.cal.selected] || [];
    const main = shell(`
      <div class="page-head"><h1>Kalender</h1><div class="actions">${filterSelect()}<button class="btn secondary sm" data-today>Heute</button></div></div>
      <div class="card">
        <div class="cal-head"><button class="btn icon" data-prev>‹</button><h2>${esc(fmt.monthYear(m))}</h2><button class="btn icon" data-next>›</button></div>
        <div class="cal-grid">${['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'].map((w) => `<div class="wd">${w}</div>`).join('')}${cells.join('')}</div>
      </div>
      <div class="section-title">${esc(fmt.long(state.cal.selected))}<span class="muted small" style="margin-left:auto">${esc(fmt.countdown(state.cal.selected))}</span></div>
      <div class="card">${sel.length ? sel.map((e) => `<div class="list-item">${badge(e.kind === 'birthday' ? e.initials : e.icon, e.color, e.kind === 'birthday' ? 'initials' : '')}
          <div class="grow"><div class="title">${esc(e.title)}</div><div class="subtitle">${esc(e.subtitle)}</div></div>${e.kind === 'birthday' ? '🎂' : ''}</div>`).join('')
        : empty('🌤️', 'Nichts geplant – freier Tag für die Tonne.')}</div>
    `, 'calendar');
    wireFilter(main, pageCalendar);
    $('[data-prev]', main).onclick = () => { state.cal.month = new Date(m.getFullYear(), m.getMonth() - 1, 1); pageCalendar(); };
    $('[data-next]', main).onclick = () => { state.cal.month = new Date(m.getFullYear(), m.getMonth() + 1, 1); pageCalendar(); };
    $('[data-today]', main).onclick = () => { state.cal.month = new Date(new Date().getFullYear(), new Date().getMonth(), 1); state.cal.selected = today(); pageCalendar(); };
    $$('.cal-cell', main).forEach((c) => c.onclick = () => { state.cal.selected = c.dataset.date; pageCalendar(); });
    let x0 = null;
    const grid = $('.cal-grid', main);
    grid.addEventListener('touchstart', (e) => { x0 = e.touches[0].clientX; }, { passive: true });
    grid.addEventListener('touchend', (e) => {
      if (x0 === null) return;
      const dx = e.changedTouches[0].clientX - x0; x0 = null;
      if (dx < -50) $('[data-next]', main).click(); else if (dx > 50) $('[data-prev]', main).click();
    });
  }

  // ---------------------------------------------------------------- Müll
  function typeRow(t) {
    const sub = !t.active ? 'Deaktiviert' : t.next ? `${fmt.countdown(t.next)} · ${fmt.short(t.next)}` : 'Noch keine Termine';
    return `<a class="list-item link" href="#/muell/${t.id}">${badge(t.icon, t.color, t.active ? '' : 'sm')}
      <div class="grow"><div class="title" style="${t.active ? '' : 'color:var(--muted)'}">${esc(t.name)}</div><div class="subtitle">${esc(sub)}</div></div>
      ${t.reminders ? '' : '<span class="tiny">🔕</span>'}<span class="chev">›</span></a>`;
  }
  function pageWaste() {
    const b = state.boot;
    const main = shell(`
      <div class="page-head"><h1>Müll</h1><div class="actions">
        <button class="btn secondary sm" data-sync-all ${b.locations.some((l) => l.can_sync) ? '' : 'disabled'}><span class="ico">🔄</span> Alle</button>
        <button class="btn sm" data-new-location>+ Standort</button></div></div>
      ${b.locations.length ? b.locations.map((l) => `<div class="card">
        <a class="list-item link" href="#/standort/${l.id}">${badge(l.icon, l.color, 'lg')}
          <div class="grow"><div class="title" style="font-size:17px">${esc(l.name)}</div>
            ${l.address ? `<div class="subtitle">${esc(l.address)}</div>` : ''}
            <div class="tiny">${l.can_sync ? `Aktualisiert ${esc(fmt.relative(l.last_sync_at))}` : 'Manuell gepflegt'}</div></div>
          ${l.can_sync ? `<button class="btn icon" data-sync="${l.id}" title="Aktualisieren">🔄</button>` : ''}<span class="chev">›</span></a>
        ${l.waste_types.map(typeRow).join('')}
        <button class="btn ghost" data-new-type="${l.id}">＋ Müllart hinzufügen</button>
      </div>`).join('') : `<div class="card">${empty('🏠', 'Noch keine Standorte. Lege einen an und hole dir die Abfuhrtermine online oder per ICS-Datei.')}</div>`}
      ${b.orphan_types.length ? `<div class="section-title">Ohne Standort</div><div class="card">${b.orphan_types.map(typeRow).join('')}</div>` : ''}
    `, 'waste');
    $('[data-new-location]', main).onclick = () => locationForm(null);
    $$('[data-new-type]', main).forEach((btn) => btn.onclick = () => wasteTypeForm(null, Number(btn.dataset.newType)));
    $$('[data-sync]', main).forEach((btn) => btn.onclick = async (e) => {
      e.preventDefault(); e.stopPropagation();
      btn.classList.add('spin'); btn.innerHTML = '<span class="ico">🔄</span>';
      try { const r = await post('location.sync', { id: Number(btn.dataset.sync) }); toast(`${r.count} Termine übernommen`); await reloadBoot(); pageWaste(); }
      catch (err) { fail(err); btn.classList.remove('spin'); }
    });
    $('[data-sync-all]', main).onclick = async (e) => {
      const btn = e.currentTarget; btn.classList.add('spin');
      try { const r = await post('sync.all'); toast(r.messages.join(' · ') || 'Nichts zu tun'); await reloadBoot(); pageWaste(); }
      catch (err) { fail(err); btn.classList.remove('spin'); }
    };
  }

  // ---------- Standort
  function pageLocation(id) {
    const l = state.boot.locations.find((x) => x.id === id);
    if (!l) { location.hash = '#/muell'; return; }
    const main = shell(`
      <div class="page-head"><h1><a href="#/muell" class="muted">‹</a> ${esc(l.name)}</h1><div class="actions"><button class="btn secondary sm" data-edit>Bearbeiten</button></div></div>
      <div class="card"><div class="row">${badge(l.icon, l.color, 'lg')}<div class="grow"><div class="title" style="font-size:18px">${esc(l.name)}</div><div class="subtitle">${esc(l.address || '–')}</div></div></div></div>
      <div class="section-title"><span class="ico">🔗</span>Datenquelle</div>
      <div class="card">
        <div class="kv"><span>Quelle</span><span>${l.source_kind === 'awido' ? 'AWIDO-Portal' : l.source_kind === 'icsurl' ? 'ICS-Link (Abo)' : 'Manuell / Datei'}</span></div>
        ${l.source_kind === 'awido' ? `<div class="kv"><span>Adresse</span><span>${esc(l.awido_label || '–')}</span></div>` : ''}
        ${l.source_kind === 'icsurl' ? `<div class="kv"><span>Link</span><span class="small">${esc(l.ics_url || '–')}</span></div>` : ''}
        <div class="kv"><span>Letzter Abgleich</span><span>${esc(fmt.relative(l.last_sync_at))}</span></div>
        ${l.last_sync_message ? `<div class="kv"><span>Status</span><span>${esc(l.last_sync_message)}</span></div>` : ''}
        <div class="row" style="margin-top:12px;flex-wrap:wrap">
          ${l.can_sync ? '<button class="btn" data-sync>🔄 Jetzt aktualisieren</button>' : ''}
          ${l.source_kind === 'awido' ? '<button class="btn secondary" data-awido>📍 Adresse wählen</button>' : ''}
          <button class="btn secondary" data-import>📥 ICS-Datei importieren</button>
        </div>
      </div>
      <div class="section-title"><span class="ico">🗑️</span>Müllarten</div>
      <div class="card">${l.waste_types.length ? l.waste_types.map(typeRow).join('') : empty('📭', 'Noch keine Müllarten.')}
        <button class="btn ghost" data-new-type>＋ Müllart hinzufügen</button></div>
      <button class="btn danger block" data-delete>Standort löschen</button>
    `, 'waste');
    $('[data-edit]', main).onclick = () => locationForm(l);
    $('[data-new-type]', main).onclick = () => wasteTypeForm(null, l.id);
    $('[data-import]', main).onclick = () => icsImport(l.id);
    const awidoBtn = $('[data-awido]', main); if (awidoBtn) awidoBtn.onclick = () => awidoWizard(l);
    const syncBtn = $('[data-sync]', main);
    if (syncBtn) syncBtn.onclick = async () => {
      syncBtn.disabled = true;
      try { const r = await post('location.sync', { id: l.id }); toast(`${r.count} Termine übernommen`); await reloadBoot(); pageLocation(id); }
      catch (e) { fail(e); syncBtn.disabled = false; }
    };
    $('[data-delete]', main).onclick = async () => {
      if (!await confirmDialog(`„${l.name}“ mit allen Müllarten löschen?`)) return;
      try { await post('location.delete', { id: l.id }); await reloadBoot(); location.hash = '#/muell'; } catch (e) { fail(e); }
    };
  }

  function locationForm(l) {
    const v = l || { name: '', address: '', color: '#2E9E6B', icon: '🏠', source_kind: 'manual', ics_url: '' };
    const body = el(`<form>
      <label class="field"><span>Name</span><input type="text" name="name" value="${esc(v.name)}" placeholder="z. B. Gifhorn" required></label>
      <label class="field"><span>Adresse</span><input type="text" name="address" value="${esc(v.address)}" placeholder="Straße, Ort"></label>
      <label class="field"><span>Farbe</span>${swatches('color', v.color)}</label>
      <label class="field"><span>Symbol</span>${emojiGrid('icon', v.icon, HOME_ICONS)}</label>
      <label class="field"><span>Datenquelle</span><select name="source_kind">
        <option value="manual" ${v.source_kind === 'manual' ? 'selected' : ''}>Manuell / ICS-Datei</option>
        <option value="awido" ${v.source_kind === 'awido' ? 'selected' : ''}>AWIDO-Portal (z. B. Landkreis Gifhorn)</option>
        <option value="icsurl" ${v.source_kind === 'icsurl' ? 'selected' : ''}>ICS-Link als Abo (z. B. Abfall-App Landkreis Stendal)</option>
      </select></label>
      <label class="field" data-ics ${v.source_kind === 'icsurl' ? '' : 'hidden'}><span>ICS-Link</span><input type="url" name="ics_url" value="${esc(v.ics_url || '')}" placeholder="https://…/download?system=ical…">
        <div class="hint">Im Portal deines Landkreises den Link hinter „Sync zu Kalender“ kopieren. Die App lädt die Termine dann wöchentlich neu.</div></label>
      <div class="hint muted small" data-awido-hint ${v.source_kind === 'awido' ? '' : 'hidden'}>Nach dem Speichern wählst du im Standort die Adresse über den AWIDO-Assistenten.</div>
    </form>`);
    wirePickers(body);
    $('[name=source_kind]', body).onchange = (e) => {
      $('[data-ics]', body).hidden = e.target.value !== 'icsurl';
      $('[data-awido-hint]', body).hidden = e.target.value !== 'awido';
    };
    openModal({
      title: l ? 'Standort bearbeiten' : 'Neuer Standort', body,
      buttons: [{ label: l ? 'Speichern' : 'Anlegen', onClick: async () => {
        const d = formData(body);
        if (l) { d.id = l.id; d.awido_customer = l.awido_customer; d.awido_oid = l.awido_oid; d.awido_label = l.awido_label; }
        const saved = await post('location.save', d);
        await reloadBoot();
        if (saved.source_kind === 'awido' && !saved.awido_oid) { location.hash = `#/standort/${saved.id}`; setTimeout(() => awidoWizard(saved), 100); }
        else if (saved.can_sync && !l) {
          try { const r = await post('location.sync', { id: saved.id }); toast(`${r.count} Termine geladen`); await reloadBoot(); } catch (e) { fail(e); }
          location.hash = `#/standort/${saved.id}`;
        } else { location.hash = `#/standort/${saved.id}`; render(); }
      } }],
    });
  }

  // ---------- AWIDO-Assistent
  function awidoWizard(l) {
    const providers = state.boot.awido_providers;
    let customer = l.awido_customer || 'gifhorn';
    let place = null, street = null;
    const body = el('<div></div>');
    const modal = openModal({ title: 'AWIDO-Portal', body });

    const list = (title, entries, onPick) => {
      body.innerHTML = `<p class="muted small" style="margin-bottom:10px">${esc(title)}</p>
        <label class="field"><input type="search" placeholder="Suchen …" data-q></label><div class="wizard-list" data-list></div>`;
      const render = (q = '') => {
        $('[data-list]', body).innerHTML = entries.filter((e) => e.value.toLowerCase().includes(q.toLowerCase())).slice(0, 300)
          .map((e) => `<button type="button" data-key="${esc(e.key)}"><span>${esc(e.value)}</span><span class="chev">›</span></button>`).join('') || '<p class="muted">Nichts gefunden.</p>';
        $$('[data-key]', body).forEach((b) => b.onclick = () => onPick(entries.find((e) => e.key === b.dataset.key)));
      };
      render();
      $('[data-q]', body).oninput = (e) => render(e.target.value);
    };
    const loading = (t) => { body.innerHTML = `<p class="muted">${esc(t)}</p>`; };
    const finish = async (oid, label) => {
      loading('Termine werden geladen …');
      await post('location.save', { ...l, source_kind: 'awido', awido_customer: customer, awido_oid: oid, awido_label: label });
      try { const r = await post('location.sync', { id: l.id }); toast(`${r.count} Termine geladen`); }
      catch (e) { fail(e); }
      await reloadBoot(); modal.close(); render();
    };
    const stepProvider = () => {
      body.innerHTML = `<label class="field"><span>Entsorger</span><select data-prov>${Object.entries(providers).map(([k, n]) => `<option value="${k}" ${k === customer ? 'selected' : ''}>${esc(n)}</option>`).join('')}</select></label>
        <button class="btn block" data-go>Weiter zur Ortsauswahl</button>
        <p class="hint muted small" style="margin-top:10px">Die Listen kommen direkt vom AWIDO-Portal (awido.cubefour.de), genau wie in der Abfall-App des Landkreises.</p>`;
      $('[data-go]', body).onclick = async () => {
        customer = $('[data-prov]', body).value; loading('Lade Orte …');
        try { const places = await api('awido.places', { params: { customer } }); list('Ort wählen', places, stepStreet); } catch (e) { fail(e); stepProvider(); }
      };
    };
    const stepStreet = async (p) => {
      place = p; loading('Lade Straßen …');
      try {
        const streets = await api('awido.streets', { params: { customer, oid: p.key } });
        if (!streets.length) return finish(p.key, p.value);
        list(`${p.value}: Straße wählen`, streets, stepHouse);
      } catch (e) { fail(e); stepProvider(); }
    };
    const stepHouse = async (s) => {
      street = s; loading('Prüfe Hausnummern …');
      try {
        const numbers = await api('awido.housenumbers', { params: { customer, oid: s.key } });
        if (!numbers.length) return finish(s.key, `${place.value}, ${s.value}`);
        list(`${s.value}: Hausnummer wählen`, numbers, (n) => finish(n.key, `${place.value}, ${s.value} ${n.value}`));
      } catch (e) { fail(e); stepProvider(); }
    };
    stepProvider();
  }

  // ---------- ICS-Import
  function icsImport(locationId) {
    const body = el(`<div>
      <p class="muted small" style="margin-bottom:12px">Abfuhrkalender als .ics-Datei (z. B. aus der Abfall-App deines Landkreises) übernehmen.</p>
      <label class="field"><span>ICS-Datei</span><input type="file" accept=".ics,text/calendar"></label>
      <div data-preview></div></div>`);
    const modal = openModal({ title: 'ICS importieren', body });
    $('input[type=file]', body).onchange = async (e) => {
      const file = e.target.files[0]; if (!file) return;
      try {
        const text = await file.text();
        const p = await post('ics.preview', { text, location_id: locationId });
        const loc = state.boot.locations.find((l) => l.id === locationId);
        const existing = loc ? loc.waste_types : state.boot.orphan_types;
        $('[data-preview]', body).innerHTML = `
          <div class="kv"><span>Termine</span><span>${p.count}</span></div><div class="kv"><span>Zeitraum</span><span>${esc(fmt.short(p.from))} – ${esc(fmt.short(p.to))}</span></div>
          <div class="section-title">Zuordnung</div>
          ${p.mappings.map((m, i) => `<label class="field"><span>${esc(m.summary)} <span class="tiny">(${m.count}×)</span></span><select data-map="${i}" data-summary="${esc(m.summary)}">
            <option value="ignore" ${m.target === 'ignore' ? 'selected' : ''}>Ignorieren</option>
            ${existing.map((t) => `<option value="existing:${t.id}" ${m.target === 'existing:' + t.id ? 'selected' : ''}>${esc(t.icon)} ${esc(t.name)}</option>`).join('')}
            ${state.boot.presets.map((pr) => `<option value="new:${pr.key}" ${m.target === 'new:' + pr.key ? 'selected' : ''}>Neu: ${esc(pr.icon)} ${esc(m.summary)} (${esc(pr.name)}-Stil)</option>`).join('')}
          </select></label>`).join('')}
          ${switchRow('replace', 'Bisherige Einzeltermine ersetzen', true)}
          <button class="btn block" data-apply>Importieren</button>`;
        $('[data-apply]', body).onclick = async () => {
          const mappings = $$('[data-map]', body).map((s) => ({ summary: s.dataset.summary, target: s.value }));
          try {
            const r = await post('ics.apply', { location_id: locationId, mappings, replace: $('[name=replace]', body).checked });
            toast(`${r.count} Termine importiert`); await reloadBoot(); modal.close(); render();
          } catch (err) { fail(err); }
        };
      } catch (err) { fail(err); }
    };
  }

  // ---------- Müllart
  async function pageWasteDetail(id) {
    const t = await api('wastetype', { params: { id } });
    const main = shell(`
      <div class="page-head"><h1><a href="${t.location_id ? `#/standort/${t.location_id}` : '#/muell'}" class="muted">‹</a> ${esc(t.name)}</h1><div class="actions"><button class="btn secondary sm" data-edit>Bearbeiten</button></div></div>
      <div class="card"><div class="row">${badge(t.icon, t.color, 'lg')}<div class="grow"><div class="title" style="font-size:18px">${esc(t.name)}</div>
        <div class="subtitle">${esc(t.location_name || 'Ohne Standort')} · ${t.active ? 'aktiv' : 'deaktiviert'} · ${t.reminders ? '🔔 Erinnerungen an' : '🔕 keine Erinnerung'}</div></div></div>
        <div class="divider"></div>
        <div class="kv"><span>Rhythmus</span><span>${esc(INTERVALS.find(([w]) => w === t.interval_weeks)?.[1] || `Alle ${t.interval_weeks} Wochen`)}${t.interval_weeks ? ` ab ${esc(fmt.short(t.anchor_date))}` : ''}</span></div>
        <div class="kv"><span>Einzeltermine</span><span>${t.explicit_dates.length}${t.source_key ? ` · Quelle „${esc(t.source_key)}“` : ''}</span></div>
      </div>
      <div class="section-title"><span class="ico">📆</span>Nächste Termine<button class="btn ghost sm" style="margin-left:auto" data-add>＋ Einzeltermin</button></div>
      <div class="card">${t.upcoming.length ? t.upcoming.slice(0, 14).map((d) => `<div class="list-item"><div class="grow"><div class="title">${esc(fmt.short(d))}</div><div class="subtitle">${esc(fmt.countdown(d))}</div></div>
          <div class="date-actions"><button class="btn secondary sm" data-move="${d}">Verschieben</button><button class="btn danger sm" data-skip="${d}">Fällt aus</button></div></div>`).join('')
        : empty('📭', 'Keine Termine in den nächsten 6 Monaten.')}</div>
      ${t.upcoming_skipped.length ? `<div class="section-title">Ausgefallene Termine</div><div class="card">${t.upcoming_skipped.map((d) => `<div class="list-item"><div class="grow muted" style="text-decoration:line-through">${esc(fmt.short(d))}</div><button class="btn secondary sm" data-unskip="${d}">Wiederherstellen</button></div>`).join('')}</div>` : ''}
      <button class="btn danger block" data-delete>Müllart löschen</button>
    `, 'waste');
    const act = async (action, body) => { try { await post(action, { id, ...body }); pageWasteDetail(id); reloadBoot(); } catch (e) { fail(e); } };
    $('[data-edit]', main).onclick = () => wasteTypeForm(t, t.location_id);
    $('[data-add]', main).onclick = () => datePrompt('Einzeltermin hinzufügen', today(), (d) => act('pickup.add', { date: d }));
    $$('[data-skip]', main).forEach((b) => b.onclick = () => act('pickup.skip', { date: b.dataset.skip }));
    $$('[data-unskip]', main).forEach((b) => b.onclick = () => act('pickup.unskip', { date: b.dataset.unskip }));
    $$('[data-move]', main).forEach((b) => b.onclick = () => datePrompt(`Termin ${fmt.short(b.dataset.move)} verschieben auf`, b.dataset.move, (d) => act('pickup.move', { from: b.dataset.move, to: d })));
    $('[data-delete]', main).onclick = async () => {
      if (!await confirmDialog(`„${t.name}“ wirklich löschen?`)) return;
      try { await post('wastetype.delete', { id }); await reloadBoot(); location.hash = t.location_id ? `#/standort/${t.location_id}` : '#/muell'; } catch (e) { fail(e); }
    };
  }
  function datePrompt(title, value, onPick) {
    const body = el(`<label class="field"><span>Datum</span><input type="date" value="${value}"></label>`);
    openModal({ title, body, buttons: [{ label: 'Übernehmen', onClick: () => { const v = $('input', body).value; if (!v) return false; onPick(v); } }] });
  }
  function wasteTypeForm(t, locationId) {
    const v = t || { name: '', color: '#5B6470', icon: '🗑️', active: true, reminders: true, interval_weeks: 0, anchor_date: today() };
    const presets = state.boot.presets;
    const body = el(`<form>
      ${t ? '' : `<label class="field"><span>Vorlage</span><select data-preset><option value="">– Vorlage wählen –</option>${presets.map((p) => `<option value="${p.key}">${p.icon} ${esc(p.name)}</option>`).join('')}</select></label>`}
      <label class="field"><span>Name</span><input type="text" name="name" value="${esc(v.name)}" required placeholder="z. B. Gelber Sack"></label>
      <label class="field"><span>Farbe</span>${swatches('color', v.color)}</label>
      <label class="field"><span>Symbol</span>${emojiGrid('icon', v.icon, WASTE_ICONS)}</label>
      <label class="field"><span>Rhythmus</span><select name="interval_weeks">${INTERVALS.map(([w, l]) => `<option value="${w}" ${w === v.interval_weeks ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
      <label class="field" data-anchor ${v.interval_weeks ? '' : 'hidden'}><span>Ein bekannter Abholtag</span><input type="date" name="anchor_date" value="${esc(v.anchor_date || today())}"><div class="hint">Von diesem Tag aus werden alle weiteren Termine im gewählten Abstand berechnet.</div></label>
      ${t ? switchRow('active', 'Aktiv', v.active) + switchRow('reminders', 'Erinnerungen', v.reminders) : ''}
    </form>`);
    wirePickers(body);
    $('[name=interval_weeks]', body).onchange = (e) => { $('[data-anchor]', body).hidden = e.target.value === '0'; };
    const presetSel = $('[data-preset]', body);
    if (presetSel) presetSel.onchange = () => {
      const p = presets.find((x) => x.key === presetSel.value); if (!p) return;
      $('[name=name]', body).value = p.key === 'sonstiges' ? '' : p.name;
      $('[name=color]', body).value = p.color; $$('.swatch', body).forEach((s) => s.classList.toggle('active', s.dataset.color === p.color));
      $('[name=icon]', body).value = p.icon; $$('[data-emoji] button', body).forEach((b) => b.classList.toggle('active', b.dataset.icon === p.icon));
    };
    openModal({
      title: t ? 'Müllart bearbeiten' : 'Neue Müllart', body,
      buttons: [{ label: t ? 'Speichern' : 'Anlegen', onClick: async () => {
        const d = formData(body); d.location_id = locationId; if (t) d.id = t.id; else { d.active = true; d.reminders = true; }
        const saved = await post('wastetype.save', d);
        await reloadBoot();
        if (t) pageWasteDetail(t.id); else location.hash = `#/muell/${saved.id}`;
      } }],
    });
  }

  // ---------------------------------------------------------------- Geburtstage
  function pageBirthdays() {
    const people = state.boot.people;
    const main = shell(`
      <div class="page-head"><h1>Geburtstage</h1><div class="actions"><button class="btn sm" data-new>+ Neu</button></div></div>
      <div class="card">${people.length ? people.map((p) => {
        const isToday = daysUntil(p.next) === 0;
        return `<div class="list-item link" data-id="${p.id}">${badge(p.initials, p.color, 'initials')}
          <div class="grow"><div class="title">${esc(p.name)}</div><div class="subtitle">${p.age_next !== null ? (isToday ? `wird heute ${p.age_next}` : `wird ${p.age_next}`) + ' · ' : ''}${esc(fmt.short(p.next))}${p.reminders ? '' : ' · 🔕'}</div></div>
          <b style="color:${isToday ? 'var(--pink)' : 'var(--text)'}">${isToday ? '🎉' : esc(fmt.countdown(p.next))}</b><span class="chev">›</span></div>`;
      }).join('') : empty('🎂', 'Noch keine Geburtstage. Füge Familie und Freunde hinzu – die App erinnert dich rechtzeitig.')}</div>
    `, 'birthdays');
    $('[data-new]', main).onclick = () => personForm(null);
    $$('[data-id]', main).forEach((row) => row.onclick = () => personForm(people.find((p) => p.id === Number(row.dataset.id))));
  }
  function personForm(p) {
    const v = p || { name: '', day: 1, month: 1, year: null, notes: '', color: '#EC4899', reminders: true, remind_days_before: 1 };
    const dateValue = `${v.year || 2000}-${pad(v.month)}-${pad(v.day)}`;
    const body = el(`<form>
      <label class="field"><span>Name</span><input type="text" name="name" value="${esc(v.name)}" required></label>
      <label class="field"><span>Geburtstag</span><input type="date" name="date" value="${dateValue}" required></label>
      ${switchRow('year_known', 'Geburtsjahr bekannt', v.year !== null)}
      ${switchRow('reminders', 'Erinnern', v.reminders)}
      <label class="field"><span>Zusätzlich erinnern</span><select name="remind_days_before">${REMIND_BEFORE.map(([d, l]) => `<option value="${d}" ${d === v.remind_days_before ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
      <label class="field"><span>Farbe</span>${swatches('color', v.color)}</label>
      <label class="field"><span>Notizen</span><textarea name="notes" placeholder="Geschenkideen, Adresse …">${esc(v.notes)}</textarea></label>
    </form>`);
    wirePickers(body);
    const buttons = [{ label: p ? 'Speichern' : 'Anlegen', onClick: async () => {
      const d = formData(body);
      const [y, m, day] = d.date.split('-').map(Number);
      await post('person.save', { id: p?.id, name: d.name, day, month: m, year: d.year_known ? y : null, notes: d.notes, color: d.color, reminders: d.reminders, remind_days_before: Number(d.remind_days_before) });
      await reloadBoot(); pageBirthdays();
    } }];
    if (p) buttons.unshift({ label: 'Löschen', cls: 'danger', onClick: async (_, close) => {
      close();
      if (!await confirmDialog(`${p.name} wirklich löschen?`)) return false;
      await post('person.delete', { id: p.id }); await reloadBoot(); pageBirthdays();
    } });
    openModal({ title: p ? 'Geburtstag bearbeiten' : 'Neuer Geburtstag', body, buttons });
  }

  // ---------------------------------------------------------------- Einstellungen
  const isStandalone = () => window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches;
  const isIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  function pushStatusText() {
    if (!('Notification' in window) || !('PushManager' in window)) {
      return isIOS() && !isStandalone() ? 'Auf dem iPhone/iPad zuerst „Teilen → Zum Home-Bildschirm“, dann hier aktivieren.' : 'Dieser Browser unterstützt keine Push-Mitteilungen.';
    }
    if (Notification.permission === 'denied') return 'In den Browser-/Systemeinstellungen blockiert.';
    if (Notification.permission === 'granted') return 'Erlaubt – dieses Gerät erhält Push-Mitteilungen.';
    return 'Noch nicht aktiviert.';
  }
  function pageSettings() {
    const b = state.boot; const s = b.settings;
    const widgetUrl = b.feed_url.replace('feed.php', 'widget.php');
    const main = shell(`
      <div class="page-head"><h1>Einstellungen</h1></div>
      <div class="section-title"><span class="ico">🔔</span>Push-Mitteilungen</div>
      <div class="card">
        <p class="small muted" data-push-status>${esc(pushStatusText())}</p>
        <div class="tiny" style="margin:4px 0 12px">Angemeldete Geräte: ${b.push.subscriptions}${b.cron.last_run ? ` · Cron zuletzt ${esc(fmt.relative(b.cron.last_run))}` : ' · Cron lief noch nie'}</div>
        <div class="row" style="flex-wrap:wrap">
          <button class="btn" data-push-on>🔔 Auf diesem Gerät aktivieren</button>
          <button class="btn secondary" data-push-test ${b.push.subscriptions ? '' : 'disabled'}>Test senden</button>
          <button class="btn ghost" data-push-off>Abmelden</button>
        </div>
      </div>
      <div class="section-title"><span class="ico">📅</span>Kalender-Abo (ohne App-Installation)</div>
      <div class="card">
        <p class="small muted" style="margin-bottom:10px">Diesen Link im iPhone/iPad-Kalender abonnieren (Einstellungen → Kalender → Accounts → Account hinzufügen → Andere → Kalenderabo). Die Alarme sind schon drin: Abends vorher und für Geburtstage.</p>
        <code class="url">${esc(b.feed_url)}</code>
        <div class="row" style="margin-top:10px;flex-wrap:wrap">
          <a class="btn" href="${esc(b.feed_url.replace(/^https?:/, 'webcal:'))}">📲 Im Kalender abonnieren</a>
          <button class="btn secondary" data-copy="${esc(b.feed_url)}">Link kopieren</button>
          <button class="btn ghost" data-feed-regen>Neuen Link erzeugen</button>
        </div>
      </div>
      <div class="section-title"><span class="ico">📱</span>Widget für den Home-Bildschirm (Scriptable)</div>
      <div class="card">
        <p class="small muted" style="margin-bottom:10px">Web-Apps dürfen auf iOS keine Widgets anlegen. Mit der kostenlosen App <b>Scriptable</b> geht es trotzdem: Skript einfügen, Widget hinzufügen, fertig.</p>
        <ol class="small muted" style="margin:0 0 10px 18px;padding:0;line-height:1.6">
          <li>Scriptable aus dem App Store laden.</li>
          <li><a href="scriptable/TonneUndTorte.js" target="_blank" rel="noopener">Skript öffnen</a>, alles markieren und kopieren.</li>
          <li>In Scriptable „+“ tippen, Skript einfügen, als <b>TonneUndTorte</b> speichern.</li>
          <li>Home-Bildschirm lange drücken → „+“ → Scriptable → Größe wählen → Widget bearbeiten → Script „TonneUndTorte“, <b>Parameter</b>: die Widget-URL unten.</li>
        </ol>
        <code class="url">${esc(widgetUrl)}</code>
        <div class="row" style="margin-top:10px;flex-wrap:wrap"><button class="btn secondary" data-copy="${esc(widgetUrl)}">Widget-URL kopieren</button><a class="btn ghost" href="${esc(widgetUrl)}" target="_blank" rel="noopener">Daten ansehen</a></div>
      </div>
      <div class="section-title"><span class="ico">🗑️</span>Müll-Erinnerungen</div>
      <div class="card"><form data-settings>
        ${switchRow('evening_enabled', 'Am Vorabend erinnern', s.evening_enabled)}
        <label class="field"><span>Uhrzeit Vorabend</span><input type="time" name="evening_time" value="${esc(s.evening_time)}"></label>
        ${switchRow('morning_enabled', 'Am Abholtag morgens erinnern', s.morning_enabled)}
        <label class="field"><span>Uhrzeit morgens</span><input type="time" name="morning_time" value="${esc(s.morning_time)}"></label>
        <div class="section-title" style="margin-top:8px"><span class="ico">🎂</span>Geburtstags-Erinnerungen</div>
        <label class="field"><span>Uhrzeit</span><input type="time" name="birthday_time" value="${esc(s.birthday_time)}"><div class="hint">Wie viele Tage vorher erinnert wird, legst du bei jeder Person fest.</div></label>
        <label class="field"><span>Zeitzone</span><input type="text" name="timezone" value="${esc(s.timezone)}"></label>
        <button class="btn block" type="submit">Speichern</button>
      </form></div>
      <div class="section-title"><span class="ico">⏰</span>Cronjob</div>
      <div class="card">
        <p class="small muted" style="margin-bottom:10px">Damit Push-Mitteilungen pünktlich kommen, muss diese URL alle 10 Minuten aufgerufen werden (IONOS: „Cronjobs“ im Kundencenter, oder ein Dienst wie cron-job.org).</p>
        <code class="url">${esc(b.cron.url)}</code>
        <div class="row" style="margin-top:10px"><button class="btn secondary" data-copy="${esc(b.cron.url)}">Link kopieren</button><button class="btn ghost" data-cron-now>Jetzt ausführen</button></div>
      </div>
      <div class="section-title"><span class="ico">🔐</span>Konto &amp; Daten</div>
      <div class="card">
        <form data-password class="stack">
          <label class="field"><span>Aktuelles Passwort</span><input type="password" name="current" autocomplete="current-password" required></label>
          <label class="field"><span>Neues Passwort</span><input type="password" name="new" autocomplete="new-password" required minlength="6"></label>
          <button class="btn secondary block" type="submit">Passwort ändern</button>
        </form>
        <div class="divider"></div>
        <div class="row" style="flex-wrap:wrap">
          <button class="btn secondary sm" data-seed>Standard-Standorte wiederherstellen</button>
          <button class="btn secondary sm" data-demo>Beispiel-Geburtstage</button>
          <button class="btn danger sm" data-reset>Alle Daten löschen</button>
          <button class="btn ghost sm" data-logout>Abmelden</button>
        </div>
        <p class="tiny" style="margin-top:12px">Tonne &amp; Torte · Version ${esc(window.TT_VERSION || '1')} · Termine: AWIDO-Portal (Landkreis Gifhorn), Abfall-App Landkreis Stendal</p>
      </div>
    `, 'settings');

    $$('[data-copy]', main).forEach((b) => b.onclick = async () => { try { await navigator.clipboard.writeText(b.dataset.copy); toast('Kopiert'); } catch (e) { toast('Kopieren nicht möglich – Link markieren und kopieren.', 'error'); } });
    $('[data-feed-regen]', main).onclick = async () => { if (!await confirmDialog('Der alte Abo-Link funktioniert danach nicht mehr.', 'Neuen Link erzeugen')) return; try { await post('feed.regenerate'); await reloadBoot(); pageSettings(); } catch (e) { fail(e); } };
    $('[data-settings]', main).onsubmit = async (e) => { e.preventDefault(); try { await post('settings.save', formData(e.target)); toast('Gespeichert'); await reloadBoot(); } catch (err) { fail(err); } };
    $('[data-password]', main).onsubmit = async (e) => { e.preventDefault(); try { await post('password.change', formData(e.target)); toast('Passwort geändert'); e.target.reset(); } catch (err) { fail(err); } };
    $('[data-cron-now]', main).onclick = async () => { try { const r = await post('cron.run'); toast(`Cron: ${r.sent.length} gesendet, ${r.synced.length} Standorte abgeglichen`); await reloadBoot(); pageSettings(); } catch (e) { fail(e); } };
    $('[data-seed]', main).onclick = async () => { try { const r = await post('seed.defaults'); toast(r.created.length ? `Angelegt: ${r.created.join(', ')}` : 'Schon vorhanden'); await reloadBoot(); } catch (e) { fail(e); } };
    $('[data-demo]', main).onclick = async () => { try { await post('seed.demo'); toast('Beispiel-Geburtstage angelegt'); await reloadBoot(); } catch (e) { fail(e); } };
    $('[data-reset]', main).onclick = async () => { if (!await confirmDialog('Wirklich alle Standorte, Müllarten und Geburtstage löschen?', 'Alles löschen')) return; try { await post('data.reset'); await reloadBoot(); toast('Alles gelöscht'); } catch (e) { fail(e); } };
    $('[data-logout]', main).onclick = async () => { await post('logout'); location.reload(); };
    $('[data-push-on]', main).onclick = () => enablePush();
    $('[data-push-off]', main).onclick = () => disablePush();
    $('[data-push-test]', main).onclick = async () => { try { const r = await post('push.test'); toast(`Gesendet: ${r.sent}, fehlgeschlagen: ${r.failed}${r.errors.length ? ' – ' + r.errors[0] : ''}`); } catch (e) { fail(e); } };
  }

  // ---------------------------------------------------------------- Push & Service Worker
  function urlBase64ToUint8Array(base64) {
    const padding = '='.repeat((4 - (base64.length % 4)) % 4);
    const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
  }
  async function registerSW() {
    if (!('serviceWorker' in navigator)) return null;
    try { return await navigator.serviceWorker.register('sw.js', { scope: './' }); } catch (e) { console.warn('SW', e); return null; }
  }
  async function enablePush() {
    if (!('Notification' in window) || !('PushManager' in window) || !('serviceWorker' in navigator)) {
      return toast(isIOS() && !isStandalone() ? 'Zuerst „Teilen → Zum Home-Bildschirm“, dann aus der installierten App aktivieren.' : 'Dieser Browser unterstützt keine Push-Mitteilungen.', 'error');
    }
    try {
      const reg = (await registerSW()) || (await navigator.serviceWorker.ready);
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') return toast('Mitteilungen wurden nicht erlaubt.', 'error');
      const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(state.boot.push.public_key) });
      await post('push.subscribe', { subscription: sub.toJSON() });
      toast('Push aktiviert 🎉'); await reloadBoot(); pageSettings();
    } catch (e) { fail(e); }
  }
  async function disablePush() {
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      const sub = reg && await reg.pushManager.getSubscription();
      if (sub) { await post('push.unsubscribe', { endpoint: sub.endpoint }); await sub.unsubscribe(); }
      toast('Abgemeldet'); await reloadBoot(); pageSettings();
    } catch (e) { fail(e); }
  }

  start();
})();
