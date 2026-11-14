// Live-Ortssuche: dieselben Daten und dieselbe Reihenfolge wie die Suche in der App (CatalogSearch.swift).
// Alles läuft im Browser; Eingaben verlassen das Gerät nicht. Daten: data/orte.json (website/tools/orte_export.py).
(function () {
  var box = document.getElementById('ortsuche');
  if (!box) return;
  var input = box.querySelector('input');
  var list = box.querySelector('.results');
  var status = box.querySelector('.status');
  var D = null, laden = null;

  function fold(s) { return s.trim().normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' '); }

  function vorbereiten(d) {
    d.gf = d.g.map(function (g) { return fold(g[0]); });
    d.sorted = d.gf.map(function (_, i) { return i; }).sort(function (a, b) { return d.gf[a] < d.gf[b] ? -1 : d.gf[a] > d.gf[b] ? 1 : a - b; });
    d.ot = {};
    d.of = [];
    d.o.forEach(function (o, i) {
      var f = fold(o[0]); d.of.push(f);
      (d.ot[f] = d.ot[f] || []).push(i);
      var k = f.indexOf(' (');
      if (k > 0) { var b = f.slice(0, k); (d.ot[b] = d.ot[b] || []).push(i); }
    });
    d.kf = d.k.map(fold);
    d.core = {};
    var namen = new Set(d.gf);
    d.kf.forEach(function (k, i) {
      ['landkreis ', 'kreisfreie stadt ', 'stadtkreis ', 'kreis ', 'regionalverband ', 'region '].some(function (p) {
        if (k.indexOf(p) !== 0) return false;
        var c = k.slice(p.length);
        if (!namen.has(c)) (d.core[c] = d.core[c] || []).push(i);
        return true;
      });
    });
    d.ef = d.e.map(function (e) { return fold(e[0]); });
    d.kreisG = d.k.map(function () { return [0, 0]; });
    d.g.forEach(function (g) { d.kreisG[g[1]][0]++; if (g[2].length) d.kreisG[g[1]][1]++; });
    return d;
  }

  function holen() {
    if (!laden) {
      status.textContent = 'Orte werden geladen …';
      laden = fetch('data/orte.json').then(function (r) { return r.json(); }).then(function (d) { D = vorbereiten(d); status.textContent = ''; return D; })
        .catch(function () { status.textContent = 'Die Ortsliste konnte gerade nicht geladen werden.'; laden = null; });
    }
    return laden;
  }

  // Gemeinden: genau, sonst Anfang gefolgt von Nicht-Buchstabe (wie die App), beim Tippen auch bloßer Anfang.
  function gemeinden(n) {
    var lo = 0, hi = D.sorted.length;
    while (lo < hi) { var mid = (lo + hi) >> 1; if (D.gf[D.sorted[mid]] < n) lo = mid + 1; else hi = mid; }
    var exakt = [], wort = [], anfang = [];
    for (var i = lo; i < D.sorted.length && D.gf[D.sorted[i]].indexOf(n) === 0; i++) {
      var g = D.sorted[i], f = D.gf[g];
      if (f === n) exakt.push(g); else if (!/\p{L}/u.test(f.charAt(n.length))) wort.push(g); else anfang.push(g);
    }
    return exakt.concat(wort, anfang);
  }

  function suche(q) {
    var n = fold(q), out = [], gesehen = new Set();
    if (n.length < 2) return out;
    function gem(g, ortsteil) {
      var key = g + '|' + (ortsteil || '');
      if (gesehen.has(g) && !ortsteil) return;
      if (gesehen.has(key)) return;
      gesehen.add(key); gesehen.add(g);
      out.push({ typ: 'g', g: g, ortsteil: ortsteil });
    }
    // Kreis („Landkreis Gifhorn“, „Gifhorn“ nur, wenn es keine Gemeinde ist)
    D.kf.forEach(function (k, i) { if (k === n || (n.length >= 4 && k.indexOf(n) === 0 && /kreis|region/.test(n))) out.push({ typ: 'k', k: i }); });
    (D.core[n] || []).forEach(function (i) { if (!out.some(function (r) { return r.typ === 'k' && r.k === i; })) out.push({ typ: 'k', k: i }); });

    if (n.length >= 2) gemeinden(n).slice(0, 8).forEach(function (g) { gem(g); });
    // Ortsteil genau (höchstens 8 Gemeinden, wie in der App), sonst Anfang ab 4 Buchstaben
    if (n.length >= 3) {
      var ot = D.ot[n] || [];
      var orte = new Set(ot.map(function (i) { return D.o[i][1]; }));
      if (ot.length && orte.size <= 8) ot.forEach(function (i) { gem(D.o[i][1], D.o[i][0]); });
      if (out.length < 8 && n.length >= 4) {
        for (var i = 0; i < D.of.length && out.length < 10; i++) if (D.of[i].indexOf(n) === 0 && D.of[i] !== n) gem(D.o[i][1], D.o[i][0]);
      }
    }
    // „Riedstadt-Erfelden“, „Borken Singlis“, „Erfelden (Riedstadt)“
    var m = n.match(/^(.{3,}?)[\s\-,/(]+([^\s\-,/(][^)]*?)\)?$/);
    if (m) {
      var links = m[1], rechts = m[2];
      (D.ot[rechts] || []).forEach(function (i) { if (D.gf[D.o[i][1]].indexOf(links) === 0) gem(D.o[i][1], D.o[i][0]); });
      (D.ot[links] || []).forEach(function (i) { if (D.gf[D.o[i][1]].indexOf(rechts) === 0) gem(D.o[i][1], D.o[i][0]); });
      if (!out.length) gemeinden(links).filter(function (g) { return D.gf[g] === links; }).forEach(function (g) { gem(g); });
    }
    // Entsorger nach Name (z. B. „ALBA“, „Müllmax“)
    if (n.length >= 3) {
      var w = n.split(' ');
      var es = [];
      D.ef.forEach(function (f, i) { if (w.every(function (x) { return f.indexOf(x) >= 0; })) es.push(i); });
      es.slice(0, 4).forEach(function (i) { out.push({ typ: 'e', e: i }); });
    }
    return out.slice(0, 12);
  }

  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function kreisName(i) { return D.k[i].replace(/^Kreis Kreis /, 'Kreis '); }

  function zeigen(q) {
    list.innerHTML = '';
    if (!D) return;
    var r = suche(q);
    if (fold(q).length >= 2 && !r.length) {
      var leer = el('li', 'none');
      leer.append(el('p', 't', 'Kein Ort gefunden.'), el('p', 'd', 'Prüf die Schreibweise oder versuch es mit der Gemeinde statt des Ortsteils. Fehlt dein Ort wirklich, sag mir Bescheid.'));
      var a = el('a', 'more', 'Ort melden'); a.href = 'kontakt.html?thema=Ort%20fehlt&ort=' + encodeURIComponent(q.trim());
      leer.appendChild(a); list.appendChild(leer); return;
    }
    r.forEach(function (x) {
      var li = el('li');
      if (x.typ === 'g') {
        var g = D.g[x.g];
        var kopf = el('p', 't'); kopf.textContent = x.ortsteil ? x.ortsteil : g[0];
        var unter = el('p', 'd', (x.ortsteil ? 'Ortsteil von ' + g[0] + ', ' : '') + kreisName(g[1]));
        li.append(kopf, unter);
        if (g[2].length) {
          li.classList.add('ok');
          var namen = g[2].slice(0, 2).map(function (i) { return D.e[i][0]; }).join(' · ');
          var mehr = g[2].length > 2 ? ' und ' + (g[2].length - 2) + ' weitere' : '';
          li.append(el('p', 'badge ok', 'Dabei'), el('p', 'src', 'Termine über ' + namen + mehr));
        } else {
          li.classList.add('no');
          var gap = (g[3] || '').split('|');
          var text = gap[0] === 'n' ? 'Kein abrufbarer Online-Kalender' : 'Noch nicht angebunden';
          li.appendChild(el('p', 'badge no', text));
          if (gap[2]) li.appendChild(el('p', 'src', 'Geprüft bei ' + gap[2] + (gap[4] ? ' am ' + gap[4].split('-').reverse().join('.') : '')));
          var a = el('a', 'more', 'Termine trotzdem nutzen'); a.href = 'support.html';
          li.appendChild(a);
        }
      } else if (x.typ === 'k') {
        var c = D.kreisG[x.k];
        li.classList.add(c[1] === c[0] ? 'ok' : 'part');
        li.append(el('p', 't', kreisName(x.k)), el('p', 'd', c[0] === 1 ? 'Kreisfreie Stadt' : c[0] + ' Gemeinden'));
        li.appendChild(el('p', 'badge ' + (c[1] === c[0] ? 'ok' : 'part'), c[1] === c[0] ? 'Komplett dabei' : c[1] + ' von ' + c[0] + ' Gemeinden dabei'));
      } else {
        li.classList.add('ok');
        li.append(el('p', 't', D.e[x.e][0]), el('p', 'd', 'Entsorger'));
        li.appendChild(el('p', 'badge ok', 'Dabei'));
      }
      list.appendChild(li);
    });
  }

  var t;
  input.addEventListener('focus', holen, { once: true });
  input.addEventListener('input', function () {
    clearTimeout(t);
    var q = input.value;
    t = setTimeout(function () { (D ? Promise.resolve() : holen()).then(function () { zeigen(q); }); }, 60);
  });
  box.addEventListener('submit', function (e) { e.preventDefault(); });
})();
