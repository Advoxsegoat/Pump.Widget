// Injected by MainActivity once the game page has loaded. Everything Android-only that the page
// needs lives here, so web/index.html stays exactly as built. The page brings its own touch
// controls; this only reaches the two things a WebView does not give it.
(function () {
  'use strict';
  if (window.__androidShell) return;
  window.__androidShell = true;
  var host = window.AndroidHost;

  // navigator.clipboard is unreliable inside a WebView: send a copied seed to the native clipboard.
  try {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (t) { host.copy(String(t)); return Promise.resolve(); } },
    });
  } catch (e) { /* the page shows the seed instead */ }

  // navigator.vibrate needs a permission the app does not ask for: the game's buzz (on landing a
  // blow and on being hurt, when the Settings allow it) becomes the phone's haptic feedback
  try {
    Object.defineProperty(navigator, 'vibrate', {
      configurable: true,
      value: function (ms) { host.haptic(Math.round(+ms || 0)); return true; },
    });
  } catch (e) { /* no buzz */ }
})();
