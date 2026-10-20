// Core: display size, loop, scene stack, storage, error log. Everything hangs off the one global, AD.
// Carried over from All-Divine Tactics; the screen size is no longer fixed, and nothing here knows
// about battles. Input lives in engine/input.js.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  AD.VERSION = '0.1.0';
  AD.frame = 0;
  AD.paused = false;

  // ---------------------------------------------------------------- display
  // hd: the GBA's 3:2 shape at 1.5x its resolution, with Tactics' 24 px art. gba: the real thing.
  const MODES = { hd: { W: 360, H: 240, T: 24 }, gba: { W: 240, H: 160, T: 16 } };
  AD.display = {
    mode: 'hd', W: 360, H: 240, T: 24, onChange: [],
    set(mode) {
      const m = MODES[mode];
      if (!m) return;
      this.mode = mode; this.W = m.W; this.H = m.H; this.T = m.T;
      AD.W = m.W; AD.H = m.H;
      if (AD.canvas) { AD.canvas.width = m.W; AD.canvas.height = m.H; AD.ctx.imageSmoothingEnabled = false; }
      this.onChange.forEach((fn) => { try { fn(mode); } catch (e) { AD.report(e, 'display'); } });
      if (AD.fit) AD.fit();
    },
  };
  AD.W = 360; AD.H = 240;

  // ---------------------------------------------------------------- utils
  AD.clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  AD.lerp = (a, b, t) => a + (b - a) * t;
  AD.ease = (t) => t * t * (3 - 2 * t);
  AD.timers = [];
  AD.wait = (frames) => new Promise((res) => AD.timers.push({ t: frames, res }));
  AD.deep = (o) => JSON.parse(JSON.stringify(o));

  // ---------------------------------------------------------------- storage
  // localStorage can be missing or throw (private windows, sandboxed previews); every access is
  // guarded and the game runs without it. Keys are prefixed so Tactics' saves are never touched.
  AD.store = {
    get(key) {
      try { const v = window.localStorage.getItem('seams.' + key); return v ? JSON.parse(v) : null; }
      catch (e) { return null; }
    },
    set(key, val) {
      try { window.localStorage.setItem('seams.' + key, JSON.stringify(val)); return true; }
      catch (e) { return false; }
    },
    raw(key) { try { return window.localStorage.getItem('seams.' + key); } catch (e) { return null; } },
    setRaw(key, s) { try { window.localStorage.setItem('seams.' + key, s); return true; } catch (e) { return false; } },
    del(key) { try { window.localStorage.removeItem('seams.' + key); } catch (e) { /* ignore */ } },
  };

  // ---------------------------------------------------------------- errors
  // Every error the game survives is kept (the last 30, in storage too), so a problem on a phone
  // can be reported: Settings > Report a problem copies the log.
  AD.errlog = AD.store.get('errlog') || [];
  const sceneName = (s) => (s ? Object.keys(AD).find((k) => AD[k] === s.constructor) || s.constructor.name || '?' : '-');
  AD.sceneName = sceneName;
  AD.report = function (e, where) {
    try {
      const msg = String((e && e.message) || e);
      const stack = String((e && e.stack) || '').split('\n').slice(1, 4).map((l) => l.trim()).join(' | ');
      const run = AD.play && AD.play.run;
      AD.errlog.push({
        at: new Date().toISOString(), where: where || '', msg, stack,
        scenes: AD.stack.map(sceneName).join('>'),
        run: run ? 'd' + run.depth + ' ' + (run.room ? run.room.key : '') : '',
      });
      if (AD.errlog.length > 30) AD.errlog.splice(0, AD.errlog.length - 30);
      AD.store.set('errlog', AD.errlog);
    } catch (e2) { /* the log must never throw */ }
    if (typeof console !== 'undefined') console.error(e);
  };
  AD.settle = (p, fn) => Promise.resolve(p).catch((e) => AD.report(e, 'flow')).then(fn);
  if (window.addEventListener) {
    window.addEventListener('error', (ev) => AD.report(ev.error || ev.message, 'window'));
    window.addEventListener('unhandledrejection', (ev) => AD.report(ev.reason, 'promise'));
  }

  // ---------------------------------------------------------------- scenes
  // A stack: the top scene updates; every scene down to the last opaque one draws.
  AD.stack = [];
  const clearInput = () => { if (AD.input && AD.input.clear) AD.input.clear(); };
  AD.push = function (scene) {
    AD.stack.push(scene);
    scene.enter && scene.enter();
    clearInput();
    return scene;
  };
  AD.pop = function (scene) {
    const i = scene ? AD.stack.lastIndexOf(scene) : AD.stack.length - 1;
    if (i < 0) return;
    const [s] = AD.stack.splice(i, 1);
    s.exit && s.exit();
    clearInput();
  };
  AD.top = () => AD.stack[AD.stack.length - 1];
  // replace everything, through a fade
  AD.goto = function (scene, opts) {
    opts = opts || {};
    return AD.fade.out(opts.speed || 10).then(() => {
      while (AD.stack.length) AD.pop();
      AD.push(scene);
      return AD.fade.in(opts.speed || 10);
    });
  };
  // push a scene and resolve when it pops itself with scene.done(value)
  AD.run = function (scene) {
    return new Promise((res) => {
      scene.done = (v) => { AD.pop(scene); res(v); };
      AD.push(scene);
    });
  };

  AD.fade = {
    a: 0, target: 0, speed: 0, res: null, color: '#05060c',
    out(frames) { return this.to(1, frames); },
    in(frames) { return this.to(0, frames); },
    to(t, frames) {
      return new Promise((res) => {
        this.target = t; this.speed = 1 / Math.max(1, frames || 10);
        if (this.res) this.res();
        this.res = res;
      });
    },
    update() {
      // already there (a fade to black while black): settle on the next frame instead of never
      if (this.a === this.target && this.res) { const r = this.res; this.res = null; r(); }
      else if (this.a !== this.target) {
        this.a += Math.sign(this.target - this.a) * this.speed;
        if (Math.abs(this.a - this.target) <= this.speed) {
          this.a = this.target;
          const r = this.res; this.res = null; r && r();
        }
      }
    },
  };

  // A scene that throws every frame would hold the screen still forever. After a few failures in
  // a row it is closed instead: a pushed scene resolves as cancelled; anything else falls back to
  // the Garden, or the title.
  AD.rescue = function (scene, why) {
    AD.report(new Error((why || 'scene failed') + ': closed ' + sceneName(scene)), 'rescue');
    const i = AD.stack.indexOf(scene);
    if (i > 0) {
      if (scene.done) { try { scene.done(null); } catch (e) { AD.pop(scene); } } else AD.pop(scene);
      if (AD.stack.indexOf(scene) >= 0) AD.pop(scene);
      return;
    }
    if (AD.Garden && !(scene instanceof AD.Garden)) AD.goto(new AD.Garden());
    else if (AD.Title) AD.goto(new AD.Title());
  };
  function failed(scene, e, what) {
    AD.report(e, what + ' ' + sceneName(scene));
    scene.__fails = (scene.__fails || 0) + 1;
    if (scene.__fails >= 8) { scene.__fails = 0; AD.rescue(scene, what + ' kept throwing'); }
  }

  // ---------------------------------------------------------------- loop
  let acc = 0, last = 0;
  function step() {
    AD.frame++;
    if (AD.input && AD.input.update) AD.input.update();
    for (let i = AD.timers.length - 1; i >= 0; i--) {
      if (--AD.timers[i].t <= 0) { const t = AD.timers.splice(i, 1)[0]; t.res(); }
    }
    AD.fade.update();
    const top = AD.top();
    if (top && top.update) {
      try { top.update(); top.__fails = 0; } catch (e) { failed(top, e, 'update'); }
    }
    if (AD.input && AD.input.endFrame) AD.input.endFrame();
    AD.fx && AD.fx.update && AD.fx.update();
    AD.audio && AD.audio.tick && AD.audio.tick();
  }

  function render() {
    const ctx = AD.ctx;
    if (!ctx) return;
    const W = AD.display.W, H = AD.display.H;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = '#05060c';
    ctx.fillRect(0, 0, W, H);
    let from = 0;
    for (let i = AD.stack.length - 1; i >= 0; i--) { if (AD.stack[i].opaque) { from = i; break; } }
    for (let i = from; i < AD.stack.length; i++) {
      const s = AD.stack[i];
      ctx.save();
      try { s.draw && s.draw(ctx); } catch (e) { failed(s, e, 'draw'); }
      ctx.restore();
    }
    if (AD.fade.a > 0) {
      ctx.globalAlpha = AD.fade.a;
      ctx.fillStyle = AD.fade.color;
      ctx.fillRect(0, 0, W, H);
      ctx.globalAlpha = 1;
    }
  }
  AD.render = render;

  // frame time of the last few frames (ms), for the slow-device suggestion
  AD.frameMs = [];
  let loopErrors = 0;
  function loop(t) {
    // schedule first: an exception in one frame must not stop every frame after it
    requestAnimationFrame(loop);
    if (!last) last = t;
    let dt = t - last; last = t;
    if (dt > 250) dt = 250;
    acc += dt;
    let n = 0;
    try {
      const t0 = performance.now();
      while (acc >= 1000 / 60 && n < 4) { step(); acc -= 1000 / 60; n++; }
      if (n === 4) acc = 0;
      render();
      AD.frameMs.push(performance.now() - t0);
      if (AD.frameMs.length > 300) AD.frameMs.shift();
    } catch (e) {
      acc = 0;
      if (loopErrors++ < 5) AD.report(e, 'loop');
    }
  }

  // test hook: advance the simulation by hand (a hidden tab gets no animation frames)
  AD.debugStep = function (n) {
    for (let i = 0; i < (n || 1); i++) step();
    render();
    return AD.stack.map(sceneName);
  };

  // ---------------------------------------------------------------- boot
  AD.boot = function (start) {
    const cv = document.getElementById('screen');
    AD.canvas = cv;
    AD.ctx = cv.getContext('2d');
    cv.width = AD.display.W; cv.height = AD.display.H;
    AD.ctx.imageSmoothingEnabled = false;
    AD.fit = () => {
      const wrap = document.getElementById('stage');
      if (!wrap) return;
      const r = wrap.getBoundingClientRect(), cs = getComputedStyle(wrap);
      // the stage's padding is where the phone controls sit (landscape): the screen fits inside it
      const rw = r.width - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight), rh = r.height - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
      const W = AD.display.W, H = AD.display.H;
      const s = Math.min(rw / W, rh / H);
      if (!(s > 0)) return;
      // integer scale when there is room, so pixels stay square and even
      const k = s >= 2 ? Math.floor(s) : s;
      cv.style.width = Math.floor(W * k) + 'px';
      cv.style.height = Math.floor(H * k) + 'px';
    };
    window.addEventListener('resize', AD.fit);
    if (window.ResizeObserver) new ResizeObserver(AD.fit).observe(document.getElementById('stage'));
    AD.fit();
    if (AD.input && AD.input.bind) AD.input.bind(cv);
    start();
    requestAnimationFrame(loop);
  };
})(window.AD);
