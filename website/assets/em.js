// Mailadresse erst im Browser zusammensetzen, damit Adress-Sammler sie im HTML nicht finden.
(function () {
  document.querySelectorAll('a.em').forEach(function (a) {
    var m = a.getAttribute('data-u') + '@' + a.getAttribute('data-d');
    a.href = 'mailto:' + m;
    a.textContent = m;
  });
})();
