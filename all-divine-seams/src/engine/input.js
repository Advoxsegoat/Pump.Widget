// Input (spec §4.2, §9.3): keyboard, gamepad and the phone's touch controls, read into one pad the
// game reads each frame: AD.pad = {sx, sy, a, aHeld, aReleased, b, r, l, q: [3], start, map}.
// A tap shorter than a frame still counts. Anything that takes the page away (a call, the app
// switcher, a lost touch) lets go of everything and pauses, so nothing is ever left held down.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const KEYMAP = {
    ArrowUp: 'up', w: 'up', W: 'up', ArrowDown: 'down', s: 'down', S: 'down',
    ArrowLeft: 'left', a: 'left', A: 'left', ArrowRight: 'right', d: 'right', D: 'right',
    z: 'a', Z: 'a', j: 'a', J: 'a',
    x: 'b', X: 'b', k: 'b', K: 'b',
    c: 'r', C: 'r', l: 'r', L: 'r',
    v: 'l', V: 'l', ';': 'l',
    1: 'q0', 2: 'q1', 3: 'q2',
    Enter: 'start', Escape: 'start',
    m: 'map', M: 'map',
  };
  const BTN = ['up', 'down', 'left', 'right', 'a', 'b', 'r', 'l', 'q0', 'q1', 'q2', 'start', 'map'];
  const I = (AD.input = {
    KEYMAP, BTN, held: {}, prev: {}, cnt: {}, latch: {}, src: { key: {}, pad: {}, touch: {} },
    stick: { on: false, id: null, x0: 0, y0: 0, dx: 0, dy: 0 },
    padStick: [0, 0], click: null, lastDevice: 'key',
  });
  BTN.forEach((b) => { I.held[b] = false; I.prev[b] = false; I.cnt[b] = 0; });
  AD.pad = { sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false], start: false, map: false };

  I.pressed = (b) => I.held[b] && !I.prev[b];
  I.released = (b) => !I.held[b] && I.prev[b];
  // pressed, then repeating while held (menus)
  I.rep = (b) => I.held[b] && (I.cnt[b] === 1 || (I.cnt[b] > 14 && I.cnt[b] % 4 === 0));
  I.dir = function () {
    for (const [b, d] of [['up', [0, -1]], ['down', [0, 1]], ['left', [-1, 0]], ['right', [1, 0]]]) if (I.rep(b)) return d;
    const [sx, sy] = [AD.pad.sx, AD.pad.sy];
    if ((sx || sy) && (I.stickCnt === 1 || (I.stickCnt > 14 && I.stickCnt % 4 === 0))) return sy ? [0, sy] : [sx, 0];
    return null;
  };
  I.consumeClick = function () { const c = I.click; I.click = null; return c; };

  // eight ways: each direction owns 22.5 degrees either side; inside the dead zone, none
  I.stickDir = function (dx, dy, dead) {
    if (Math.hypot(dx, dy) < (dead === undefined ? 0.28 : dead)) return [0, 0];
    const s = ((Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) % 8) + 8) % 8;
    return [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]][s];
  };

  // ---------------------------------------------------------------- each frame
  function pollPad() {
    const s = I.src.pad;
    BTN.forEach((b) => { s[b] = false; });
    I.padStick = [0, 0];
    const nav = typeof navigator !== 'undefined' ? navigator : null;
    const pads = nav && nav.getGamepads ? nav.getGamepads() : [];
    const p = pads && Array.from(pads).find((g) => g && g.connected);
    if (!p) return;
    const bt = (i) => !!(p.buttons[i] && p.buttons[i].pressed);
    s.a = bt(0); s.b = bt(2); s.r = bt(1) || bt(5); s.l = bt(4); s.q0 = bt(6); s.q1 = bt(7); s.start = bt(9); s.map = bt(8);
    s.up = bt(12); s.down = bt(13); s.left = bt(14); s.right = bt(15);
    I.padStick = I.stickDir(p.axes[0] || 0, p.axes[1] || 0, 0.35);
    if (BTN.some((b) => s[b]) || I.padStick[0] || I.padStick[1]) { I.lastDevice = 'pad'; if (AD.audio) AD.audio.unlock(); }
  }
  I.update = function () {
    pollPad();
    BTN.forEach((b) => {
      I.prev[b] = I.held[b];
      const latched = I.latch[b];
      I.latch[b] = false;
      // a press since the last frame reads as one frame up, then down: a tap already let go of, or a
      // button let go of and pressed again between two frames
      if (latched && I.prev[b]) I.prev[b] = false;
      I.held[b] = !!(I.src.key[b] || I.src.pad[b] || I.src.touch[b] || latched);
      I.cnt[b] = I.held[b] ? (latched && !I.prev[b] ? 1 : I.cnt[b] + 1) : 0;
    });
    // direction: the touch stick, else the gamepad stick, else the keys and D-pad
    let [sx, sy] = I.stick.on ? I.stickDir(I.stick.dx, I.stick.dy) : I.padStick;
    if (!sx && !sy) { sx = (I.held.right ? 1 : 0) - (I.held.left ? 1 : 0); sy = (I.held.down ? 1 : 0) - (I.held.up ? 1 : 0); }
    I.stickCnt = sx || sy ? (I.stickCnt || 0) + 1 : 0;
    const P = AD.pad;
    P.sx = sx; P.sy = sy;
    P.a = I.pressed('a'); P.aHeld = I.held.a; P.aReleased = I.released('a');
    P.b = I.pressed('b'); P.r = I.pressed('r'); P.l = I.pressed('l');
    P.q = [I.pressed('q0'), I.pressed('q1'), I.pressed('q2')];
    P.start = I.pressed('start'); P.map = I.pressed('map');
    return P;
  };
  I.endFrame = function () { I.click = null; };
  // after a scene change: what is held stays held but no longer counts as a fresh press
  I.clear = function () {
    BTN.forEach((b) => { I.prev[b] = I.held[b]; I.cnt[b] = I.held[b] ? 99 : 0; });
    I.click = null;
  };
  I.stickUp = function () { const s = I.stick; s.on = false; s.id = null; s.dx = 0; s.dy = 0; if (I.onStick) I.onStick(null); };
  // let go of everything; 'hidden' (the page went away) also pauses
  I.releaseAll = function (why) {
    // fingers whose lift may never arrive (a paused WebView) are forgotten too
    BTN.forEach((b) => { I.src.key[b] = false; I.src.touch[b] = false; I.latch[b] = false; if (I.fingers && I.fingers[b]) I.fingers[b].clear(); });
    I.stickUp();
    if (typeof document !== 'undefined' && document.querySelectorAll) document.querySelectorAll('#controls .down').forEach((el) => el.classList.remove('down'));
    if (why) AD.paused = true;
  };

  // ---------------------------------------------------------------- the page
  const unlock = () => { if (AD.audio) AD.audio.unlock(); };
  // the touch controls show on a touch screen, or once a finger is seen
  function touchUI() {
    const root = document.documentElement;
    if (root.classList.contains('touch')) return;
    root.classList.add('touch');
    if (AD.fit) AD.fit();
  }
  function onKey(e, down) {
    const b = KEYMAP[e.key];
    if (!b || e.ctrlKey || e.metaKey || e.altKey) return;
    e.preventDefault();
    I.src.key[b] = down;
    if (down && !e.repeat) I.latch[b] = true;
    if (down) { I.lastDevice = 'key'; unlock(); }
  }
  function canvasPos(ev) {
    const r = AD.canvas.getBoundingClientRect();
    return { x: Math.floor(((ev.clientX - r.left) / r.width) * AD.display.W), y: Math.floor(((ev.clientY - r.top) / r.height) * AD.display.H) };
  }
  // a tap on the canvas: the HUD's quickslots (with hit areas half as big again), else a click for menus
  function onCanvas(ev) {
    unlock();
    if (ev.pointerType === 'touch') touchUI();
    const p = canvasPos(ev);
    if (AD.hud && AD.hud.layout) {
      const L = AD.hud.layout(AD.display.mode);
      for (const [i, r] of [[0, L.quick0], [1, L.quick1]]) {
        const gx = r.w * 0.25, gy = r.h * 0.25;
        if (p.x >= r.x - gx && p.x < r.x + r.w + gx && p.y >= r.y - gy && p.y < r.y + r.h + gy && AD.hud.quickTappable && AD.hud.quickTappable()) { I.latch['q' + i] = true; ev.preventDefault(); return; }
      }
    }
    I.click = p;
    I.lastDevice = ev.pointerType === 'mouse' ? 'mouse' : 'touch';
  }

  // the floating stick: it appears where the thumb lands in its zone and its knob stays within 40 px
  const RADIUS = 40;
  function bindStick(zone, base, knob) {
    const place = () => {
      const s = I.stick, k = Math.min(1, Math.hypot(s.dx, s.dy));
      const a = Math.atan2(s.dy, s.dx);
      knob.style.transform = `translate(${Math.cos(a) * k * RADIUS}px, ${Math.sin(a) * k * RADIUS}px)`;
    };
    I.onStick = (s) => { if (!s) { base.classList.remove('on'); knob.style.transform = ''; } };
    zone.addEventListener('pointerdown', (ev) => {
      ev.preventDefault(); unlock(); touchUI();
      if (I.stick.on) return;
      const zr = zone.getBoundingClientRect();
      // keep the whole base inside its zone
      const x = Math.min(zr.right - RADIUS, Math.max(zr.left + RADIUS, ev.clientX)), y = Math.min(zr.bottom - RADIUS, Math.max(zr.top + RADIUS, ev.clientY));
      Object.assign(I.stick, { on: true, id: ev.pointerId, x0: x, y0: y, dx: (ev.clientX - x) / RADIUS, dy: (ev.clientY - y) / RADIUS });
      base.style.left = x - zr.left + 'px'; base.style.top = y - zr.top + 'px';
      base.classList.add('on');
      place();
      try { zone.setPointerCapture(ev.pointerId); } catch (e) { /* synthetic pointers have nothing to capture */ }
    });
    zone.addEventListener('pointermove', (ev) => {
      const s = I.stick;
      if (!s.on || ev.pointerId !== s.id) return;
      let dx = (ev.clientX - s.x0) / RADIUS, dy = (ev.clientY - s.y0) / RADIUS;
      const m = Math.hypot(dx, dy);
      if (m > 1) { dx /= m; dy /= m; }
      s.dx = dx; s.dy = dy;
      place();
    });
    const up = (ev) => { if (I.stick.on && ev.pointerId === I.stick.id) I.stickUp(); };
    ['pointerup', 'pointercancel', 'lostpointercapture'].forEach((n) => zone.addEventListener(n, up));
  }
  // the fingers on each on-screen button: it is held while any of them is down
  I.fingers = {};
  I.touchDown = function (b, id) {
    (I.fingers[b] = I.fingers[b] || new Set()).add(id);
    I.src.touch[b] = true; I.latch[b] = true; I.lastDevice = 'touch';
  };
  I.touchUp = function (b, id) {
    const f = I.fingers[b];
    if (f) f.delete(id);
    if (f && f.size) return false;
    I.src.touch[b] = false;
    return true;
  };
  function bindButtons() {
    document.querySelectorAll('#controls [data-btn]').forEach((el) => {
      const b = el.getAttribute('data-btn');
      const on = (ev) => {
        ev.preventDefault(); unlock(); touchUI();
        I.touchDown(b, ev.pointerId); el.classList.add('down');
        try { el.setPointerCapture(ev.pointerId); } catch (e) { /* synthetic pointers have nothing to capture */ }
      };
      const off = (ev) => { if (I.touchUp(b, ev.pointerId)) el.classList.remove('down'); };
      el.addEventListener('pointerdown', on);
      ['pointerup', 'pointercancel', 'lostpointercapture'].forEach((n) => el.addEventListener(n, off));
      el.addEventListener('contextmenu', (ev) => ev.preventDefault());
    });
  }
  // a short buzz on a phone, when the Settings allow it (on landing a hit and on being hurt)
  I.buzz = function (ms) {
    if (!AD.settings || !AD.settings.haptics || typeof navigator === 'undefined' || !navigator.vibrate) return;
    try { navigator.vibrate(ms); } catch (e) { /* not allowed in this frame */ }
  };
  // Settings: size 80-130%, opacity 30-90%, handedness
  I.applyControls = function (o) {
    if (typeof document === 'undefined' || !document.documentElement) return;
    const root = document.documentElement;
    o = o || AD.settings || {};
    root.style.setProperty('--ctl-scale', String((o.ctlSize || 100) / 100));
    root.style.setProperty('--ctl-alpha', String((o.ctlAlpha || 50) / 100));
    root.classList.toggle('left-handed', !!o.leftHanded);
    if (AD.fit) AD.fit();
  };

  I.bind = function (cv) {
    window.addEventListener('keydown', (e) => onKey(e, true));
    window.addEventListener('keyup', (e) => onKey(e, false));
    cv.addEventListener('pointerdown', onCanvas);
    cv.addEventListener('contextmenu', (ev) => ev.preventDefault());
    const zone = document.getElementById('stickZone');
    if (zone) bindStick(zone, zone.querySelector('.stick'), zone.querySelector('.knob'));
    bindButtons();
    // the page going away lets go of everything and pauses
    window.addEventListener('blur', () => I.releaseAll('blur'));
    window.addEventListener('pagehide', () => I.releaseAll('pagehide'));
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') I.releaseAll('hidden'); });
    if (window.matchMedia && window.matchMedia('(pointer: coarse)').matches) touchUI();
    I.applyControls();
  };
})(window.AD);
