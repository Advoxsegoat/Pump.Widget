// Injected by MainActivity once the game page has loaded. Everything Android-only that the page
// needs lives here, so web/index.html stays exactly as exported from the game's artifact.
(function () {
  'use strict';
  if (window.__androidShell) return;
  window.__androidShell = true;
  var host = window.AndroidHost;

  // navigator.clipboard is unreliable inside a WebView: send save codes to the native clipboard.
  try {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (t) { host.copy(String(t)); return Promise.resolve(); } },
    });
  } catch (e) { /* the page falls back to showing the code in the box under the game */ }

  // a haptic tick for the on-screen buttons
  document.addEventListener('pointerdown', function (e) {
    var t = e.target;
    if (t && t.closest && t.closest('[data-btn]')) host.haptic();
  }, true);

  // Touch layouts. On a portrait phone the pad's single row is wider than the screen and pushes
  // the A button off the edge, so the six small buttons get a row of their own. In landscape the
  // D-pad and A/B sit either side of the screen, like a handheld, so the game itself gets larger.
  var css = [
    '@media (pointer: coarse) and (orientation: portrait) {',
    '  #app #pad { flex-wrap: wrap; row-gap: 10px; }',
    '  #app #pad .mid { order: -1; flex: 1 0 100%; max-width: none; grid-template-columns: repeat(6, 1fr); }',
    '}',
    '@media (pointer: coarse) and (orientation: landscape) {',
    '  #app { display: grid; grid-template-columns: auto minmax(0, 1fr) auto;',
    '    grid-template-rows: minmax(0, 1fr) auto auto; grid-template-areas: "dpad stage ab" "dpad mid ab" "code code code";',
    '    align-items: center; column-gap: 16px; row-gap: 8px; }',
    '  #app #stage { grid-area: stage; align-self: stretch; }',
    '  #app #pad { display: contents; }',
    '  #app #pad .dpad { grid-area: dpad; }',
    '  #app #pad .ab { grid-area: ab; }',
    '  #app #pad .mid { grid-area: mid; justify-self: center; width: 100%; max-width: 420px; grid-template-columns: repeat(6, 1fr); }',
    '  #app #codebox { grid-area: code; justify-self: center; }',
    '}',
  ].join('\n');
  var style = document.createElement('style');
  style.textContent = css;
  document.body.appendChild(style);
})();
