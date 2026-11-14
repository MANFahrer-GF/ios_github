// Kontaktformular: prüfen, ohne Neuladen absenden, Erfolg und Fehler direkt am Feld zeigen.
(function () {
  var f = document.getElementById('kontakt');
  if (!f) return;
  var done = document.querySelector('.done');
  var ort = f.querySelector('.ort');
  var text = f.querySelector('#f-text');
  var zaehler = document.getElementById('zaehler');
  var formErr = f.querySelector('.form-err');
  var btn = f.querySelector('.send');
  f.querySelector('#f-t').value = String(Date.now());

  function themaWahl() {
    var istOrt = f.thema.value === 'Ort fehlt';
    ort.hidden = !istOrt;
  }
  f.addEventListener('change', function (e) { if (e.target.name === 'thema') themaWahl(); });
  text.addEventListener('input', function () { zaehler.textContent = text.value.length; });
  themaWahl();

  function markiere(felder) {
    f.querySelectorAll('.err').forEach(function (p) { p.textContent = ''; });
    f.querySelectorAll('[aria-invalid]').forEach(function (el) { el.removeAttribute('aria-invalid'); });
    var erstes = null;
    Object.keys(felder || {}).forEach(function (k) {
      var p = document.getElementById('e-' + k);
      var el = f.querySelector('[name="' + k + '"]');
      if (p) p.textContent = felder[k];
      if (el) { el.setAttribute('aria-invalid', 'true'); erstes = erstes || el; }
    });
    if (erstes) erstes.focus();
  }

  function pruefe() {
    var fe = {};
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.email.value.trim())) fe.email = 'Bitte eine gültige E-Mail-Adresse angeben, damit ich antworten kann.';
    if (f.thema.value === 'Ort fehlt' && f.ort.value.trim().length < 2) fe.ort = 'Welcher Ort fehlt? Landkreis und Gemeinde helfen.';
    if (text.value.trim().length < 10) fe.nachricht = 'Bitte schreib ein paar Worte mehr (mindestens 10 Zeichen).';
    return fe;
  }

  f.addEventListener('submit', function (e) {
    e.preventDefault();
    formErr.textContent = '';
    var fe = pruefe();
    markiere(fe);
    if (Object.keys(fe).length) return;
    btn.disabled = true; btn.classList.add('busy');
    fetch(f.action, { method: 'POST', body: new FormData(f), headers: { 'X-Requested-With': 'fetch' } })
      .then(function (r) { return r.json().catch(function () { return { ok: false }; }); })
      .then(function (d) {
        if (d.ok) {
          f.hidden = true; done.hidden = false; done.focus();
          return;
        }
        markiere(d.felder);
        formErr.textContent = d.fehler || 'Das hat leider nicht geklappt. Bitte direkt an thomas@kant.ovh schreiben.';
      })
      .catch(function () { formErr.textContent = 'Keine Verbindung. Bitte später noch einmal versuchen oder direkt an thomas@kant.ovh schreiben.'; })
      .finally(function () { btn.disabled = false; btn.classList.remove('busy'); });
  });
})();
