// Effects (spec §3): damage numbers, sparks, the blows' trails, explosions, shake and flash. All of
// it is presentation: it listens to the run's bus and reads the bodies, and changes nothing in play.
// Positions are kept in tiles and turned into pixels when drawn, so a mode change keeps them.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const FX = (AD.fx = AD.fx || {});
  const G = AD.gfx;
  // the Settings the effects obey (the Settings screen writes these)
  AD.settings = Object.assign({ shake: 'full', flashes: 'full', numbers: true, effects: true }, AD.settings || {});
  const gba = () => AD.display.mode === 'gba';
  const TT = () => AD.display.T;
  const rnd = Math.random;
  FX.nums = []; FX.sparks = []; FX.trails = []; FX.lights = [];

  // ---------------------------------------------------------------- numbers
  const NUM_C = { normal: '#ffffff', crit: '#ffd84a', burn: '#ff9a3a', bleed: '#ff4a4a', chill: '#7ac8ff', spark: '#c9a0ff', heal: '#6ad06a', poison: '#a8e05a', boom: '#ffb347', bloom: '#ff9ab8', tide: '#7ad8ff', word: '#e8e0d0' };
  FX.NUM_C = NUM_C;
  // a number rising from a tile; hits from one source on one target within 10 frames merge into one
  FX.number = function (x, y, amount, type, src, tgt) {
    if (!AD.settings.numbers) return null;
    const merge = src && FX.nums.find((n) => n.src === src && n.tgt === tgt && n.type === type && n.age < 10);
    if (merge) { merge.amount += amount; merge.age = 0; merge.t = Math.min(merge.t, 6); return merge; }
    const n = { x, y, amount, type, src, tgt, t: 0, age: 0, life: type === 'crit' ? 48 : 40, jx: (rnd() - 0.5) * 0.3 };
    FX.nums.push(n);
    if (FX.nums.length > 24) FX.nums.shift();
    return n;
  };
  // a word in place of a number (miss, block, BREAK, level up)
  FX.word = function (x, y, text, color) {
    FX.nums.push({ x, y, text, type: 'word', color: color || NUM_C.word, t: 0, age: 99, life: 44, jx: 0 });
    if (FX.nums.length > 24) FX.nums.shift();
  };

  // ---------------------------------------------------------------- sparks and smoke
  // size ~ how hard the blow was; half as many in True GBA
  FX.spark = function (x, y, size, color) {
    let n = Math.max(3, Math.min(12, Math.round(size)));
    if (gba()) n = Math.ceil(n / 2);
    for (let i = 0; i < n; i++) {
      const a = rnd() * Math.PI * 2, v = 0.04 + rnd() * 0.05 * (1 + size / 8);
      FX.sparks.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 0.01, t: 0, life: 8 + ((rnd() * 7) | 0), c: color || (i % 3 ? '#fff2b0' : '#ffffff'), g: 0 });
    }
    if (size >= 7) FX.trails.push({ kind: 'ring', x, y, t: 0, life: 10, r0: 0.2, r1: 0.9, c: color || '#ffffff' });
  };
  FX.puff = function (x, y, n, colors, rise) {
    if (gba()) n = Math.ceil(n / 2);
    for (let i = 0; i < n; i++) {
      const a = rnd() * Math.PI * 2, v = 0.01 + rnd() * 0.03;
      FX.sparks.push({ x: x + (rnd() - 0.5) * 0.4, y: y + (rnd() - 0.5) * 0.3, vx: Math.cos(a) * v, vy: Math.sin(a) * v - (rise || 0.02), t: 0, life: 18 + ((rnd() * 12) | 0), c: colors[i % colors.length], s: 2, g: -0.0005 });
    }
  };
  // a light that flares and fades: explosions, muzzle flashes, gifts
  FX.flare = function (x, y, r, c, life) { FX.lights.push({ x, y, r, c, t: 0, life: life || 12 }); };

  // ---------------------------------------------------------------- the blows' trails
  // a trail for an attack as its active frames begin: what it looks like follows what it is
  FX.trail = function (atk) {
    const d = atk.def, o = atk.owner;
    if (!o) return;
    const base = { x: o.fx, y: o.fy, facing: atk.facing || o.facing || [0, 1], tiles: atk.tiles || [], t: 0 };
    let k;
    if (d.bomb) return; // the explosion draws itself
    if (d.kind === 'spin') k = { kind: 'ring', life: 12, r0: 0.5, r1: 1.6, c: '#fff2b0', w: 2 };
    else if (d.kind === 'gift') k = { kind: d.gift, life: d.gift === 'tide' ? 20 : 16 };
    else if (d.kind === 'combo') k = { kind: 'arc', life: 8, c: '#ffffff', wide: d.step === 2 ? 1.6 : 1, r: d.step === 2 ? 1.1 : 0.85 };
    else if (d.shape && d.shape.k === 'line') k = d.lunge ? { kind: 'streak', life: 8, c: '#e8e0d0' } : { kind: 'streak', life: 10, c: '#fff2b0', bright: 1 };
    else if (d.shape && (d.shape.k === 'shot' || d.shape.k === 'lob')) return;
    else k = { kind: 'arc', life: 8, c: o.elite && AD.ELITES[o.elite] ? AD.ELITES[o.elite].c : '#ffd0c0', wide: 1, r: 0.85 };
    FX.trails.push(Object.assign(base, k));
    if (k.kind === 'streak' && k.bright) { const end = base.tiles[base.tiles.length - 1] || [o.x, o.y]; FX.flare(o.fx + 0.5, o.fy + 0.5, 1.6, '#ffe8a0', 8); FX.spark(end[0] + 0.5, end[1] + 0.5, 3, '#ffe8a0'); }
    if (d.kind === 'gift') FX.flare(o.fx + 0.5, o.fy + 0.5, 2.2, { flame: '#ff9a3a', bloom: '#ff7a9a', tide: '#7ad8ff' }[d.gift], 16);
  };
  FX.boom = function (x, y, r) {
    FX.trails.push({ kind: 'boom', x, y, t: 0, life: 16, r: r || 1 });
    FX.puff(x + 0.5, y + 0.5, 14, ['#ffb347', '#ff6a3a', '#5a5050', '#8a8a96'], 0.03);
    FX.flare(x + 0.5, y + 0.5, 3.5, '#ffb347', 18);
    FX.shake(3, 14);
  };

  // ---------------------------------------------------------------- shake and flash
  const SHAKE_K = { full: 1, low: 0.4, off: 0 };
  FX.shake = function (a, t) {
    const k = SHAKE_K[AD.settings.shake] === undefined ? 1 : SHAKE_K[AD.settings.shake];
    if (!k) return;
    if (a * k >= FX.shakeA * (FX.shakeT > 0 ? 1 : 0)) { FX.shakeA = a * k; FX.shakeT = t || 8; }
  };
  // flashes never pass 30% (low: 12%)
  FX.flashPeak = () => (AD.settings.flashes === 'low' ? 0.12 : 0.3);

  // ---------------------------------------------------------------- the bus
  const centre = (e) => [e.fx + 0.5, e.fy + 0.3];
  FX.bind = function (run) {
    FX.clear();
    const on = (n, f) => run.events.on(n, f, 95);
    const offs = [
      on('hit', (p) => {
        const t = p.tgt;
        if (!t) return;
        const [x, y] = centre(t);
        if (p.amount > 0) {
          FX.number(x, y - 0.4, p.amount, p.crit ? 'crit' : (p.type && NUM_C[p.type] ? p.type : 'normal'), p.src, t);
          const hard = Math.min(8, 3 + (p.amount / Math.max(1, t.mhp)) * 24);
          FX.spark(x, y, p.crit ? 8 : hard, p.type === 'burn' ? '#ff9a3a' : p.type === 'spark' ? '#c9a0ff' : null);
          if (t === run.hero) { FX.shake(2, 8); FX.flash('#ff2a2a', 6); }
          else if (p.crit) FX.shake(1.5, 6);
          else if (t.kind === 'boss') FX.shake(1, 4);
        }
      }),
      on('blocked', (p) => { if (p.tgt) { const [x, y] = centre(p.tgt); FX.spark(x, y, 4, '#a9c8ff'); FX.word(x, y - 0.5, 'block', '#a9c8ff'); } }),
      on('miss', (p) => { const t = p.rec && p.rec.tgt; if (t) { const [x, y] = centre(t); FX.word(x, y - 0.5, 'miss', '#a8a8b8'); } }),
      on('heal', (p) => { if (p.tgt && p.amount >= 1) { const [x, y] = centre(p.tgt); FX.number(x, y - 0.5, Math.round(p.amount), 'heal', 'heal', p.tgt); FX.puff(x, y, 4, ['#6ad06a', '#c8ffd8'], 0.03); } }),
      on('strike', (p) => FX.trail(p.attack)),
      on('explode', (p) => FX.boom(p.x, p.y, p.r)),
      on('kill', (p) => { const t = p.tgt; if (t && t !== run.hero) { const [x, y] = centre(t); FX.puff(x, y + 0.2, 8, ['#8a8a96', '#5a5a66', '#c8c8d0']); } }),
      on('break', (p) => { const [x, y] = centre(p.b); FX.word(x, y - 0.9, 'BREAK!', '#ffd84a'); FX.flash('#ffffff', 10); FX.shake(3, 16); FX.spark(x, y, 12, '#ffd84a'); }),
      on('bossPhase', () => FX.shake(2.5, 20)),
      on('levelUp', (p) => { const [x, y] = centre(p.h); FX.word(x, y - 1, 'LEVEL ' + p.level, '#ffd84a'); FX.trails.push({ kind: 'ring', x, y: y + 0.2, t: 0, life: 18, r0: 0.3, r1: 1.4, c: '#ffd84a', w: 2 }); }),
      on('pickup', (p) => { const q = p.p; if (q && q.kind !== 'coins') FX.puff(q.x + 0.5, q.y + 0.5, 5, ['#fff2b0', '#ffffff'], 0.04); }),
      on('roll', (p) => FX.puff(p.h.fx + 0.5, p.h.fy + 0.85, 4, ['#c8c0b0', '#a8a094'], 0.005)),
      on('gateCharged', (p) => { FX.flash('#c9b0ff', 12); FX.flare(p.gate.tile[0] + 0.5, p.gate.tile[1] - 0.2, 4, '#ffe28a', 40); }),
      on('opened', (p) => FX.puff(p.x + 0.5, p.y + 0.5, 10, ['#8a8a96', '#c8c0b0'], 0.02)),
    ];
    FX.unbind = () => offs.forEach((f) => f && f());
    return FX.unbind;
  };
  FX.clear = function () { FX.nums.length = 0; FX.sparks.length = 0; FX.trails.length = 0; FX.lights.length = 0; };

  // one step, with the simulation
  FX.tick = function () {
    if (FX.update) FX.update(); // shake and flash wear off (gfx)
    for (const n of FX.nums) { n.t++; n.age++; }
    FX.nums = FX.nums.filter((n) => n.t < n.life);
    for (const s of FX.sparks) { s.t++; s.x += s.vx; s.y += s.vy; s.vy += s.g || 0.004; s.vx *= 0.92; s.vy *= 0.92; }
    FX.sparks = FX.sparks.filter((s) => s.t < s.life);
    for (const t of FX.trails) t.t++;
    FX.trails = FX.trails.filter((t) => t.t < t.life);
    for (const l of FX.lights) l.t++;
    FX.lights = FX.lights.filter((l) => l.t < l.life);
  };

  // lights the effects add this frame, in pixels from (ox, oy)
  FX.lightsAt = function (ox, oy) {
    const T = TT();
    return FX.lights.map((l) => ({ x: ox + l.x * T, y: oy + l.y * T, r: l.r * T * (1 - (l.t / l.life) * 0.4), c: l.c, a: 0.5 * (1 - l.t / l.life) }));
  };

  // ---------------------------------------------------------------- drawing
  const px = (c, x, y, w, h) => c.fillRect(Math.round(x), Math.round(y), w, h);
  function arcPts(c, cx, cy, r, a0, a1, w) {
    const n = Math.max(6, Math.round(Math.abs(a1 - a0) * r / 1.5));
    for (let i = 0; i <= n; i++) { const a = a0 + ((a1 - a0) * i) / n; px(c, cx + Math.cos(a) * r - w / 2, cy + Math.sin(a) * r - w / 2, w, w); }
  }
  const TRAIL = {
    // a crescent swept through the facing, brightest where the blow lands
    arc(c, t, T, ox, oy) {
      const k = t.t / t.life, [fx, fy] = t.facing, a = Math.atan2(fy, fx);
      const cx = ox + (t.x + 0.5) * T, cy = oy + (t.y + 0.45) * T, span = 0.9 * t.wide;
      c.globalAlpha = 1 - k; c.fillStyle = t.c;
      const sweep = Math.min(1, k * 2.2);
      arcPts(c, cx, cy, T * t.r, a - span, a - span + 2 * span * sweep, gba() ? 1 : 2);
      c.globalAlpha = (1 - k) * 0.5;
      arcPts(c, cx, cy, T * (t.r - 0.18), a - span * 0.7, a - span * 0.7 + 1.4 * span * sweep, 1);
      if (k < 0.4) { c.globalAlpha = 1 - k * 2; c.fillStyle = '#ffffff'; const s = (gba() ? 2 : 3) + (t.wide > 1 ? 1 : 0); px(c, cx + fx * T * t.r - s / 2, cy + fy * T * t.r - s / 2, s, s); }
    },
    ring(c, t, T, ox, oy) {
      const k = t.t / t.life;
      c.globalAlpha = 1 - k; c.fillStyle = t.c;
      arcPts(c, ox + t.x * T, oy + t.y * T, T * (t.r0 + (t.r1 - t.r0) * k), 0, Math.PI * 2, t.w && !gba() ? 2 : 1);
    },
    streak(c, t, T, ox, oy) {
      const k = t.t / t.life, end = t.tiles[t.tiles.length - 1];
      if (!end) return;
      const x0 = ox + (t.x + 0.5) * T, y0 = oy + (t.y + 0.4) * T, x1 = ox + (end[0] + 0.5) * T, y1 = oy + (end[1] + 0.4) * T;
      c.globalAlpha = 1 - k; c.fillStyle = t.c;
      const n = Math.max(2, Math.round(Math.hypot(x1 - x0, y1 - y0) / 2));
      for (let i = Math.floor(n * k * 0.6); i <= n; i++) px(c, x0 + ((x1 - x0) * i) / n, y0 + ((y1 - y0) * i) / n, t.bright ? 2 : 1, t.bright ? 1 : 1);
    },
    flame(c, t, T, ox, oy) {
      const k = t.t / t.life;
      t.tiles.forEach(([x, y], i) => {
        const cx = ox + (x + 0.5) * T, cy = oy + (y + 0.7) * T;
        for (let j = 0; j < (gba() ? 2 : 4); j++) {
          const h = T * (0.3 + 0.4 * Math.sin((t.t + i * 3 + j * 5) * 0.5) * 0.5 + 0.3) * (1 - k);
          c.globalAlpha = 1 - k; c.fillStyle = j % 2 ? '#ffb347' : '#ff6a3a';
          px(c, cx - T * 0.3 + j * T * 0.18, cy - h, Math.max(1, T / 8), h);
          c.fillStyle = '#fff2b0'; px(c, cx - T * 0.3 + j * T * 0.18, cy - h, Math.max(1, T / 8), 1);
        }
      });
    },
    bloom(c, t, T, ox, oy) {
      const k = t.t / t.life;
      t.tiles.forEach(([x, y], i) => {
        const cx = ox + (x + 0.5) * T, cy = oy + (y + 0.5) * T, r = T * 0.45 * Math.min(1, k * 3);
        c.globalAlpha = 1 - k;
        for (let j = 0; j < 5; j++) { const a = (j / 5) * Math.PI * 2 + i; c.fillStyle = j % 2 ? '#ff7a9a' : '#ffb0c8'; px(c, cx + Math.cos(a) * r - 1, cy + Math.sin(a) * r - 1, 2, 2); }
        c.fillStyle = '#6ad06a'; px(c, cx - 1, cy - 1, 2, 2);
      });
    },
    tide(c, t, T, ox, oy) {
      // the wave runs out tile by tile from the hero
      const reach = (t.t / t.life) * 5;
      t.tiles.forEach(([x, y]) => {
        const d = Math.max(Math.abs(x - t.x), Math.abs(y - t.y));
        const on = 1 - Math.min(1, Math.abs(d - reach));
        if (on <= 0) return;
        c.globalAlpha = on * 0.75; c.fillStyle = '#5ab0e8'; px(c, ox + x * T + 1, oy + y * T + T * 0.3, T - 2, T * 0.55);
        c.fillStyle = '#e8f8ff'; px(c, ox + x * T + 1, oy + y * T + T * 0.3, T - 2, 1);
      });
    },
    boom(c, t, T, ox, oy) {
      const k = t.t / t.life, cx = ox + (t.x + 0.5) * T, cy = oy + (t.y + 0.5) * T;
      c.globalAlpha = 1 - k; c.fillStyle = k < 0.3 ? '#ffffff' : '#ffb347';
      arcPts(c, cx, cy, T * (0.4 + (t.r + 0.6) * k), 0, Math.PI * 2, gba() ? 1 : 2);
      if (k < 0.35) { c.globalAlpha = (0.35 - k) * 2; c.fillStyle = '#fff2b0'; c.beginPath(); c.arc(cx, cy, T * (0.5 + t.r * k * 2), 0, Math.PI * 2); c.fill(); }
    },
  };
  // everything above the bodies, from the room drawn at (ox, oy)
  FX.draw = function (ctx, ox, oy) {
    const T = TT();
    ctx.save();
    for (const t of FX.trails) (TRAIL[t.kind] || TRAIL.arc)(ctx, t, T, ox, oy);
    for (const s of FX.sparks) {
      ctx.globalAlpha = s.t > s.life - 5 ? (s.life - s.t) / 5 : 1;
      ctx.fillStyle = s.c;
      const z = s.s && !gba() ? s.s : 1;
      px(ctx, ox + s.x * T, oy + s.y * T, z, z);
    }
    ctx.restore();
  };
  // numbers last, over the lighting, so the dark never hides them
  FX.drawNumbers = function (ctx, ox, oy) {
    const T = TT();
    for (const n of FX.nums) {
      const k = n.t / n.life, rise = (1 - Math.pow(1 - Math.min(1, k * 1.6), 2)) * T * 0.75;
      const pop = n.type === 'crit' && n.t < 5 ? -2 : 0;
      ctx.globalAlpha = n.t > n.life - 10 ? (n.life - n.t) / 10 : 1;
      const text = n.text || (n.type === 'heal' ? '+' : '') + AD.stat.short(n.amount) + (n.type === 'crit' ? '!' : '');
      G.text(ctx, text, ox + (n.x + n.jx) * T, oy + n.y * T - rise + pop - 4, n.color || NUM_C[n.type] || '#ffffff', { align: 'center' });
    }
    ctx.globalAlpha = 1;
  };
})(window.AD);
