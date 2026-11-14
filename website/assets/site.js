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
  fetch('api/bewertungen.php').then(function (r) { return r.ok ? r.json() : null; }).then(function (d) {
    if (!d || !d.ok || !d.anzahl) return;
    var de = function (n) { return n.toLocaleString('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 }); };
    sec.querySelector('[data-avg]').textContent = de(d.schnitt);
    var st = sec.querySelector('[data-stars]');
    st.style.setProperty('--pct', (d.schnitt / 5 * 100) + '%');
    st.setAttribute('aria-label', de(d.schnitt) + ' von 5 Sternen');
    sec.querySelector('[data-count]').textContent = d.anzahl + (d.anzahl === 1 ? ' Bewertung' : ' Bewertungen') + ' im App Store';
    var box = sec.querySelector('[data-reviews]');
    (d.rezensionen || []).filter(function (r) { return r.sterne >= 4 && r.text; }).slice(0, 8).forEach(function (r) {
      var a = document.createElement('article'); a.className = 'review';
      var s = document.createElement('span'); s.className = 'stars sm'; s.textContent = '★★★★★';
      s.style.setProperty('--pct', (r.sterne / 5 * 100) + '%'); s.setAttribute('aria-label', r.sterne + ' von 5 Sternen');
      var h = document.createElement('h3'); h.textContent = r.titel;
      var p = document.createElement('p'); p.className = 't'; p.textContent = r.text;
      var by = document.createElement('p'); by.className = 'by';
      var dt = r.datum ? new Date(r.datum + 'T12:00:00').toLocaleDateString('de-DE', { day: 'numeric', month: 'long', year: 'numeric' }) : '';
      by.textContent = r.autor + (dt ? ', ' + dt : '');
      a.append(s, h, p, by); box.appendChild(a);
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
