// Mini-bosses and bosses (spec §7.6): three phases, telegraphed patterns picked by weight (never the
// same one three times running), and Tactics' Shield and Break. Heavy blows wear the shield's
// pips; with none left the boss is staggered for 3 s and takes +50%. The shield refills each phase.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const B = (AD.boss = {});
  const sgn = Math.sign;
  const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
  const STAGGER = 180;
  const rngOf = (room) => AD.combat.rngOf(room);

  B.spawn = function (room, id, x, y, o) {
    o = o || {};
    const D = AD.BOSSES[id];
    const level = o.level || 1;
    const hp = AD.stat.scaleHp(D.hp, level);
    const b = AD.ent.make(room, {
      kind: 'boss', team: 'e', x, y, mode: 'walk', speed: D.speed, hp, mhp: hp, dmg: AD.stat.scaleDmg(D.dmg, level), crit: 0,
      defId: id, def: D, look: D.look, level, heavy: true, cost: D.cost, pips: D.shield, pipsMax: D.shield,
      phase: 1, stagger: 0, stunned: 0, gap: 50, last: [], timers: [], isBoss: !!D.boss,
    });
    if (room.hero) b.facing = [sgn(room.hero.x - x) || 0, sgn(room.hero.y - y) || 1];
    room.bus.emit('bossSpawn', { b });
    return b;
  };

  B.count = (room, defId) => [...room.bodies.values()].filter((e) => e.defId === defId && !e.dead).length;
  const dir8 = (b, h) => { const f = [sgn(h.x - b.x), sgn(h.y - b.y)]; return f[0] || f[1] ? f : [0, 1]; };

  // ---------------------------------------------------------------- pattern pieces
  B.aimed = function (room, b, h, def) {
    b.facing = dir8(b, h);
    AD.combat.attack(room, b, Object.assign({ proc: 1, type: 'normal' }, def));
  };
  B.combo = function (room, b, h, defs) {
    b.facing = dir8(b, h);
    let at = 0;
    defs.forEach((d, i) => {
      const def = Object.assign({ proc: 1, type: 'normal' }, d, { wind: d.wind + at });
      if (i > 0) def.noBusy = true;
      AD.combat.attack(room, b, def);
      at += d.wind + d.act;
    });
    b.busy = Math.max(b.busy, at + defs[defs.length - 1].rec);
  };
  // a straight rush: the tiles to the first wall or solid thing (or n), and a stun if it hit one
  B.dash = function (room, b, h, o) {
    const f = dir8(b, h);
    b.facing = f;
    const tiles = [];
    let blocked = false;
    for (let k = 1; k <= o.n; k++) {
      const x = b.x + f[0] * k, y = b.y + f[1] * k;
      if (!room.grid.passable(x, y, 'walk')) { blocked = true; break; }
      tiles.push([x, y]);
    }
    if (!tiles.length) return B.aimed(room, b, h, { shape: { k: 'adjacent' }, wind: 16, act: 2, rec: 16, pct: o.pct });
    AD.combat.attack(room, b, {
      tiles, wind: o.wind, act: Math.max(4, tiles.length * 2), rec: 20, pct: o.pct, proc: 1, type: 'normal', kind: 'dash', sfx: 'dash',
      onStrike: (r) => {
        const free = [];
        for (const [x, y] of tiles) { const who = r.grid.bodyAt(x, y); if (who && who !== b.id) break; free.push([x, y]); }
        if (free.length) AD.ent.push(r, b, f[0], f[1], free.length, 2);
        if (blocked && o.stun && free.length === tiles.length) b.stunNext = o.stun;
      },
    });
  };
  B.three = function (room, b, h, o) {
    b.facing = dir8(b, h);
    for (let i = 0; i < 3; i++) {
      b.timers.push({ t: i * o.wind, fn: (r) => {
        const hh = r.hero;
        if (!hh || b.dead) return;
        const tiles = AD.combat.tiles({ k: 'square', r: 1 }, hh.x, hh.y, [0, 1]).filter((p) => r.grid.inside(p[0], p[1]));
        AD.combat.attack(r, b, { tiles, wind: o.wind, act: 2, rec: 0, pct: o.pct, proc: 1, type: 'normal', noBusy: true, persist: true, sfx: 'thud' });
      } });
    }
    b.busy = o.wind * 3 + 16;
  };
  B.volley = function (room, b, h, o) {
    const f = dir8(b, h);
    b.facing = f;
    const px = -f[1], py = f[0];
    const tiles = [];
    for (const s of [-1, 0, 1]) {
      const x0 = b.x + px * s, y0 = b.y + py * s;
      for (let k = 1; k <= o.n; k++) {
        const x = x0 + f[0] * k, y = y0 + f[1] * k;
        if (!room.grid.inside(x, y) || AD.tileInfo(room.grid.at(x, y)).wall) break;
        tiles.push([x, y]);
      }
    }
    AD.combat.attack(room, b, { tiles, wind: o.wind, act: o.act, rec: o.rec, pct: o.pct, proc: 1, type: 'normal', sfx: 'musket' });
  };
  B.sidestep = function (room, b, h, n, reload) {
    const f = dir8(b, h);
    const opts = [[-f[1], f[0]], [f[1], -f[0]]];
    for (const [dx, dy] of rngOf(room)() < 0.5 ? opts : opts.reverse()) {
      if (AD.ent.canStep(room, b, dx, dy)) { AD.ent.push(room, b, dx, dy, n, 5); break; }
    }
    b.busy = n * 5 + reload;
  };
  B.summon = function (room, b, id, n) {
    // in the arena they come in at the barred doors the hero didn't use; elsewhere, away from him
    const r = rngOf(room);
    let tiles = [];
    if (room.key === 'arena') {
      tiles = AD.rng.shuffle(r, ['n', 'w', 'e'].map((d) => AD.room.MOUTH[d]))
        .filter(([x, y]) => room.grid.passable(x, y, 'walk') && !room.grid.bodyAt(x, y)).slice(0, n);
    }
    if (tiles.length < n) tiles = tiles.concat(AD.director.spawnTiles(room, n - tiles.length, r));
    for (const [x, y] of tiles) AD.ai.spawn(room, id, x, y, { level: b.level, shimmer: 18 });
    b.busy = 30;
    room.bus.emit('summon', { b, id, n: tiles.length });
  };
  B.debts = function (room, b, o) {
    const spots = [];
    for (let y = 1; y < 9; y++) for (let x = 1; x < 14; x++) if (room.grid.passable(x, y, 'walk') && room.grid.bodyAt(x, y) !== b.id) spots.push([x, y]);
    const tiles = AD.rng.shuffle(rngOf(room), spots).slice(0, o.n);
    AD.combat.attack(room, b, {
      tiles, wind: o.wind, act: 2, rec: 16, pct: o.pct, proc: 1, type: 'normal', sfx: 'coin',
      onStrike: (r) => { for (const [x, y] of tiles) AD.room.drop(r, x, y, { kind: 'coins', amount: o.coins, debts: true }); },
    });
  };

  // ---------------------------------------------------------------- the brain
  function phaseCheck(room, b) {
    const ratio = b.hp / b.mhp;
    const want = ratio <= 0.33 ? 3 : ratio <= 0.66 ? 2 : 1;
    while (b.phase < want) {
      b.phase++;
      b.pips = b.pipsMax;
      room.bus.emit('bossPhase', { b, phase: b.phase });
      const on = b.def.onPhase && b.def.onPhase[b.phase];
      if (on) on(room, b, room.hero, B);
    }
  }
  function pick(room, b, h) {
    const P = b.def.patterns.filter((p) => p.phase <= b.phase && (!p.when || p.when(room, b, h)));
    const two = b.last.length >= 2 && b.last[0] === b.last[1] ? b.last[0] : null;
    const ok = P.filter((p) => p.id !== two);
    if (!ok.length) return null;
    return AD.rng.weighted(rngOf(room), ok.map((p) => ({ w: p.weight, v: p })));
  }
  function run(room, b, h, p) {
    p.run(room, b, h, B);
    b.last.unshift(p.id); b.last.length = Math.min(2, b.last.length);
    b.gap = 30 + Math.floor(rngOf(room)() * 21);
    room.bus.emit('bossPattern', { b, id: p.id });
    if (b.onPattern) b.onPattern(p.id);
  }

  B.think = function (room, b) {
    if (b.dead || b.gone) return;
    phaseCheck(room, b);
    for (let i = b.timers.length - 1; i >= 0; i--) { const t = b.timers[i]; if (t.t-- <= 0) { b.timers.splice(i, 1); t.fn(room); } }
    if (b.stunNext && !b.move && !b.pushLeft) { b.stunned = b.stunNext; b.stunNext = 0; room.bus.emit('bossStunned', { b }); }
    if (b.stagger > 0) { b.stagger--; return; }
    if (b.stunned > 0) { b.stunned--; return; }
    if (b.hitstop > 0 || b.busy || b.move || b.pushLeft) return;
    if (AD.status.mods(b).stunned) return;
    const h = room.hero;
    if (!h || h.dead) return;
    if (b.force) {
      const p = b.def.patterns.find((q) => q.id === b.force);
      b.force = null;
      if (p) { run(room, b, h, p); return; }
    }
    if (b.gap > 0) {
      b.gap--;
      // between patterns: close in (or keep a distance, for a marksman)
      const maps = AD.ai.maps(room);
      if (b.def.keep) {
        const d = cheb(b, h);
        if (d < b.def.keep[0]) step(room, b, room.grid.fleeMap(maps.walk));
        else if (d > b.def.keep[1]) step(room, b, maps.walk);
      } else if (cheb(b, h) > 1) step(room, b, maps.walk);
      return;
    }
    const p = pick(room, b, h);
    if (p) run(room, b, h, p);
  };
  const ORDER = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]];
  function step(room, b, map) {
    const cur = map[b.y * 15 + b.x];
    let best = null, bv = cur < 0 ? Infinity : cur;
    for (const [dx, dy] of ORDER) {
      const v = map[(b.y + dy) * 15 + b.x + dx];
      if (v === undefined || v < 0 || v >= 9999) continue;
      if (v < bv && AD.ent.canStep(room, b, dx, dy)) { best = [dx, dy]; bv = v; }
    }
    if (best) AD.ent.tryStep(room, b, best[0], best[1]);
  }

  // ---------------------------------------------------------------- listeners
  B.install = function (room) {
    room.bus.on('hit', (p) => {
      const b = p.tgt;
      if (b.kind !== 'boss' || b.dead || b.stagger > 0 || b.pips <= 0) return;
      let wear = p.rec.shield || 0;
      if (p.src && p.src.kind === 'hero' && AD.items.count(p.src, 'knucklebrass') && !p.rec.fixed) wear += 1;
      if (!wear) return;
      b.pips = Math.max(0, b.pips - wear);
      room.bus.emit('pip', { b });
      if (b.pips === 0) { b.stagger = STAGGER; b.busy = 0; room.bus.emit('break', { b }); }
    }, 25);
    room.bus.on('takeMods', (p) => { if (p.tgt.kind === 'boss' && p.tgt.stagger > 0) p.mul *= 1.5; });
  };

  B.reward = function (run, b) {
    const h = run.hero, D = b.def;
    if (D.reward) {
      AD.items.give(run, h, D.reward);
      const it = AD.ITEMS[D.reward];
      run.banner = { text: it.n, sub: it.desc, t: 120, tier: it.tier, item: D.reward };
      run.found = (run.found || []).concat([D.reward]);
    }
    h.bossHp = (h.bossHp || 0) + 0.1;
    AD.hero.recompute(h);
    run.petals += 10;
  };
})(window.AD);
