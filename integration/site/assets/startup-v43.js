/* The decorative intro must never prevent access to the website. */
(function () {
  'use strict';
  var timer;
  function dismiss(recover) {
    var intro = document.getElementById('genesisV29');
    if (!intro || intro.classList.contains('is-done')) return;
    intro.classList.add('is-done');
    intro.classList.remove('is-opening');
    intro.style.display = 'none';
    if (document.body) {
      document.body.classList.remove('locked');
      if (recover) document.body.classList.add('aims-startup-recovered');
    }
    clearTimeout(timer);
  }
  function ready() {
    var skip = document.getElementById('skipIntroV29');
    if (skip) skip.addEventListener('click', function () { dismiss(false); });
    timer = setTimeout(function () { dismiss(true); }, 9000);
  }
  window.addEventListener('error', function (event) {
    // Resource errors are not enough to discard the intro. A script exception is.
    if (event.error) dismiss(true);
  });
  window.addEventListener('pageshow', function (event) {
    if (event.persisted) dismiss(false);
  });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready);
  else ready();
}());
