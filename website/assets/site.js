// Abschnitte beim Hereinscrollen sanft einblenden (nur ohne „Bewegung reduzieren“).
(function () {
  var els = document.querySelectorAll('.reveal');
  if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) {
    els.forEach(function (el) { el.classList.add('in'); });
    return;
  }
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
    });
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
  els.forEach(function (el) { io.observe(el); });
})();

// Bewertungen aus dem App Store (über den eigenen Server, siehe api/bewertungen.php).
(function () {
  var sec = document.getElementById('bewertungen');
  if (!sec || !window.fetch) return;
  // Sterne eindeutig zeichnen: volle ★, leere ☆, beim Durchschnitt ein anteilig gefüllter Stern.
  function sterne(el, wert) {
    el.textContent = '';
    for (var i = 1; i <= 5; i++) {
      var s = document.createElement('span');
      if (wert >= i) { s.className = 'v'; s.textContent = '★'; }
      else if (wert > i - 1) { s.className = 't'; s.textContent = '★'; s.style.setProperty('--pct', Math.round((wert - i + 1) * 100) + '%'); }
      else { s.className = 'l'; s.textContent = '☆'; }
      s.setAttribute('aria-hidden', 'true');
      el.appendChild(s);
    }
    el.setAttribute('role', 'img');
  }
  fetch('api/bewertungen.php?v=8').then(function (r) { return r.ok ? r.json() : null; }).then(function (d) {
    if (!d || !d.ok || !d.anzahl) return;
    var de = function (n) { return n.toLocaleString('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 }); };
    sec.querySelector('[data-avg]').textContent = de(d.schnitt);
    var st = sec.querySelector('[data-stars]');
    sterne(st, d.schnitt);
    st.setAttribute('aria-label', de(d.schnitt) + ' von 5 Sternen');
    sec.querySelector('[data-count]').textContent = d.anzahl + (d.anzahl === 1 ? ' Bewertung' : ' Bewertungen') + ' im App Store';
    var box = sec.querySelector('[data-reviews]');
    var alle = (d.rezensionen || []).filter(function (r) { return r.text || r.titel; });
    // Zwei Spalten: höchstens 8 und immer eine gerade Anzahl (bei nur einer Bewertung diese eine)
    var anz = Math.min(8, alle.length); if (anz > 1 && anz % 2) anz--;
    var neu = alle.slice(0, anz);
    var nh = sec.querySelector('[data-neueste]'); if (nh) nh.firstChild.textContent = neu.length === 1 ? 'Die neueste Bewertung ' : 'Die ' + neu.length + ' neuesten Bewertungen ';
    neu.forEach(function (r) {
      var a = document.createElement('article'); a.className = 'review';
      var h = document.createElement('h3'); h.textContent = r.titel;
      var by = document.createElement('p'); by.className = 'by';
      var dt = r.datum ? new Date(r.datum + 'T12:00:00').toLocaleDateString('de-DE', { day: 'numeric', month: 'short', year: 'numeric' }) : '';
      by.textContent = dt;
      var top = document.createElement('div'); top.className = 'top'; top.append(h, by);
      var s = document.createElement('span'); s.className = 'stars sm'; sterne(s, r.sterne);
      s.setAttribute('aria-label', r.sterne + ' von 5 Sternen');
      var au = document.createElement('p'); au.className = 'by'; au.textContent = r.autor;
      var p = document.createElement('p'); p.className = 't'; p.textContent = r.text;
      a.append(top, s, au, p);
      if (r.antwort && r.antwort.text) {
        var ant = document.createElement('div'); ant.className = 'answer';
        var ah = document.createElement('p'); ah.className = 'ah';
        var ad = r.antwort.datum ? new Date(r.antwort.datum + 'T12:00:00').toLocaleDateString('de-DE', { day: 'numeric', month: 'short' }) : '';
        ah.textContent = 'Antwort des Entwicklers' + (ad ? ', ' + ad : '');
        var at = document.createElement('p'); at.className = 'at'; at.textContent = r.antwort.text;
        ant.append(ah, at); a.appendChild(ant);
      }
      var mehr = document.createElement('button'); mehr.type = 'button'; mehr.className = 'mehr'; mehr.textContent = 'mehr';
      mehr.addEventListener('click', function () { var o = a.classList.toggle('open'); mehr.textContent = o ? 'weniger' : 'mehr'; });
      a.appendChild(mehr);
      box.appendChild(a);
      setTimeout(function () { var lang = [].some.call(a.querySelectorAll('p.t, .at'), function (x) { return x.scrollHeight > x.clientHeight + 2; }); if (!lang) mehr.remove(); }, 0);
    });
    if (!box.children.length) box.remove();
    sec.hidden = false;
    var rv = sec.querySelectorAll('.reveal');
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (es) { es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }); }, { threshold: 0.12 });
      rv.forEach(function (el) { io.observe(el); });
    } else rv.forEach(function (el) { el.classList.add('in'); });
  }).catch(function () {});
})();

// Downloads und Updates aus App Store Connect (über den eigenen Server, siehe api/zahlen.php).
(function () {
  var sec = document.getElementById('bewertungen');
  if (!sec || !window.fetch) return;
  fetch('api/zahlen.php?v=1').then(function (r) { return r.ok ? r.json() : null; }).then(function (z) {
    if (!z || !z.ok) return;
    var n = function (x) { return x.toLocaleString('de-DE'); };
    sec.querySelector('[data-dl]').textContent = n(z.downloads);
    sec.querySelector('[data-up]').textContent = n(z.updates);
    sec.querySelectorAll('[data-zahl]').forEach(function (e) { e.hidden = false; });
    if (z.stand) {
      var st = sec.querySelector('[data-stand]');
      st.textContent = 'Stand ' + new Date(z.stand + 'T12:00:00').toLocaleDateString('de-DE', { day: 'numeric', month: 'long', year: 'numeric' }) + ', Zahlen aus App Store Connect';
      st.hidden = false;
    }
  }).catch(function () {});
})();

// Trailer: stumm abspielen, solange er zu sehen ist; „Ton an“ startet ihn von vorn mit Ton.
(function () {
  var v = document.querySelector('[data-trailer]');
  if (!v) return;
  var mute = document.querySelector('[data-trailer-mute]');
  var ton = document.querySelector('[data-trailer-ton]');
  var ruhig = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var sichtbar = false, angehalten = false;
  function spiel() { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  function knopf() {
    mute.textContent = v.muted ? '🔇 Ton an' : '🔊 Ton aus';
    mute.setAttribute('aria-label', v.muted ? 'Ton einschalten' : 'Ton ausschalten');
  }
  function stumm() { v.muted = true; v.loop = true; knopf(); if (ruhig) v.pause(); }
  function mitTon() {
    angehalten = false; v.muted = false; v.loop = false; v.currentTime = 0;
    spiel(); knopf();
  }
  mute.addEventListener('click', function () { if (v.muted) mitTon(); else stumm(); });
  ton.addEventListener('click', function () {
    mitTon();
    if (innerWidth < 735) v.scrollIntoView({ behavior: ruhig ? 'auto' : 'smooth', block: 'center' });
  });
  // Tipp aufs Video hält an bzw. spielt weiter; angehalten bleibt angehalten, auch beim Scrollen.
  function umschalten() { if (v.paused) { angehalten = false; spiel(); } else { angehalten = true; v.pause(); } }
  v.addEventListener('click', umschalten);
  v.addEventListener('keydown', function (e) {
    if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); umschalten(); }
  });
  v.addEventListener('ended', function () { v.currentTime = 0; stumm(); if (sichtbar && !ruhig && !angehalten) spiel(); });
  if (!('IntersectionObserver' in window)) return;
  new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      sichtbar = e.isIntersecting && e.intersectionRatio >= 0.45;
      if (sichtbar && !angehalten && (!ruhig || !v.muted)) spiel();
      else if (!sichtbar) v.pause();
    });
  }, { threshold: [0, 0.45] }).observe(v);
})();
