// The world's own rules (spec §6.6): gas, fire, water, traps, pits, explosions, breakables and light.
// All tile-based, all deterministic: chances draw from the room's combat and loot streams.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const Wd = (AD.world = {});
  const W = 15, H = 10, N = W * H;
  const GAS = { poison: 1, smoke: 2, ash: 3 };
  const GAS_NAME = ['', 'poison', 'smoke', 'ash'];
  const N4 = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  const rngC = (room) => (room.rng && room.rng.combat) || AD.combat.rngOf(room);
  const rngL = (room) => (room.rng && room.rng.loot) || AD.combat.rngOf(room);
  // light each source gives: strength falls by one a tile
  const LIGHT = { L: 3, v: 2, G: 3, f: 4 };
  // trap damage at level 1, before the trap's share
  const TRAP_BASE = 20;

  Wd.init = function (room, o) {
    o = o || {};
    room.gas = new Float32Array(N);
    room.gasKind = new Uint8Array(N);
    room.fire = new Uint8Array(N);
    room.light = new Uint8Array(N);
    room.ambient = o.ambient === undefined ? 2 : o.ambient;
    room.traps = new Map();
    room.burned = 0;
    room.lightKey = '';
  };

  // ---------------------------------------------------------------- gas
  Wd.addGas = function (room, x, y, kind, vol) {
    if (!room.grid.inside(x, y)) return;
    const i = y * W + x;
    room.gas[i] += vol;
    room.gasKind[i] = GAS[kind] || 1;
  };
  // gas drifts over the floor, water, pits and low clutter; walls, closed doors and big furniture stop it
  const gasOpen = (g, x, y) => {
    if (!g.inside(x, y)) return false;
    const t = AD.tileInfo(g.at(x, y));
    return !t.wall && !t.locked && !t.sealed && !(t.solid && !t.breakable);
  };
  function tickGas(room) {
    const g = room.grid, gas = room.gas;
    let any = false;
    for (let i = 0; i < N; i++) if (gas[i] > 0) { any = true; break; }
    if (!any) return;
    const next = new Float32Array(N), kind = new Uint8Array(N);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const i = y * W + x, v = gas[i];
      if (v <= 0) continue;
      const to = [i];
      for (const [dx, dy] of N4) if (gasOpen(g, x + dx, y + dy)) to.push((y + dy) * W + x + dx);
      const share = v / to.length;
      for (const j of to) { next[j] += share; if (!kind[j] || next[j] === share) kind[j] = room.gasKind[i]; }
    }
    for (let i = 0; i < N; i++) { next[i] *= 0.98; if (next[i] < 0.05) { next[i] = 0; kind[i] = 0; } }
    room.gas = next; room.gasKind = kind;
    // poison: 1% of max HP a second for each 100 volume
    if (room.frame % 60 === 0) {
      for (const e of room.bodies.values()) {
        if (e.dead || e.gone || e.mode === 'fly' && e.kind !== 'hero') continue;
        const i = e.y * W + e.x;
        if (room.gasKind[i] !== GAS.poison || room.gas[i] <= 0) continue;
        const dmg = Math.max(1, Math.round(e.mhp * 0.01 * (room.gas[i] / 100)));
        AD.combat.deal(room, { src: null, tgt: e, amount: dmg, type: 'poison', proc: 0, mask: [], fixed: true });
      }
    }
  }
  Wd.gasAt = (room, x, y) => ({ vol: room.gas[y * W + x], kind: GAS_NAME[room.gasKind[y * W + x]] });

  // ---------------------------------------------------------------- fire
  const burns = (ch) => !!AD.tileInfo(ch).flammable;
  Wd.ignite = function (room, x, y) {
    const g = room.grid;
    if (!g.inside(x, y) || !burns(g.at(x, y)) || room.fire[y * W + x]) return false;
    room.fire[y * W + x] = 120 + Math.floor(rngC(room)() * 61);
    room.bus.emit('ignite', { x, y });
    return true;
  };
  // fire that burns on any open tile for a while (a gold-flame elite's trail)
  Wd.flame = function (room, x, y, frames) {
    const g = room.grid;
    if (!g.inside(x, y) || AD.tileInfo(g.at(x, y)).water || AD.tileInfo(g.at(x, y)).wall) return;
    room.fire[y * W + x] = Math.max(room.fire[y * W + x], frames);
  };
  Wd.douse = function (room, tiles) { for (const [x, y] of tiles) if (room.grid.inside(x, y)) room.fire[y * W + x] = 0; };
  function tickFire(room) {
    const g = room.grid, f = room.fire;
    for (let i = 0; i < N; i++) {
      if (!f[i]) continue;
      const x = i % W, y = (i / W) | 0;
      for (const [dx, dy] of N4) {
        const nx = x + dx, ny = y + dy;
        if (g.inside(nx, ny) && !f[ny * W + nx] && burns(g.at(nx, ny)) && rngC(room)() < 0.12) Wd.ignite(room, nx, ny);
      }
      if (--f[i] === 0) {
        if (burns(g.at(x, y))) { g.set(x, y, '.'); room.burned++; room.bus.emit('burnedOut', { x, y }); }
      }
    }
    for (const e of room.bodies.values()) {
      if (e.dead || e.gone || e.mode === 'fly' && e.kind !== 'hero') continue;
      const [ex, ey] = AD.combat.tileOf(e);
      if (!g.inside(ex, ey) || !f[ey * W + ex]) continue;
      if (!e.statuses.burn) AD.status.apply(e, 'burn', { dur: 180, pct: 1, src: { dmg: Math.max(2, Math.round(e.mhp * 0.04)), team: 'world' } });
    }
  }

  // ---------------------------------------------------------------- explosions and breakables
  Wd.breakAt = function (room, x, y) {
    const g = room.grid, ch = g.at(x, y), t = AD.tileInfo(ch);
    if (!t.breakable && !t.cut) return false;
    if (t.explosive) { Wd.explode(room, x, y, 1, 3, room.hero || null, { barrel: true }); return true; }
    g.set(x, y, t.cut ? ',' : '.');
    room.bus.emit('broke', { x, y, ch });
    const r = rngL(room)();
    if (room.dropPickup) {
      if (r < 0.6) room.dropPickup(x, y, { kind: 'coins', amount: 1 + Math.floor(rngL(room)() * 3) + (room.depth || 1) });
      else if (r < 0.75) room.dropPickup(x, y, { kind: 'heart' });
    }
    return true;
  };
  // the terrain side of a blast: pots, crates, barrels, cracked walls
  Wd.blast = function (room, tiles, src) {
    const g = room.grid;
    const chain = [];
    for (const [x, y] of tiles) {
      if (!g.inside(x, y)) continue;
      const t = AD.tileInfo(g.at(x, y));
      // a door now, barred like the others while the room is sealed
      if (t.cracked) { g.set(x, y, room.sealed ? '=' : 'D'); room.bus.emit('opened', { x, y, secret: true }); }
      else if (t.explosive) { g.set(x, y, '.'); chain.push([x, y]); }
      else if (t.breakable || t.cut) Wd.breakAt(room, x, y);
    }
    for (const [x, y] of chain) Wd.explode(room, x, y, 1, 3, src, { barrel: true });
  };
  Wd.explode = function (room, x, y, r, pct, src, o) {
    o = o || {};
    const tiles = AD.combat.tiles({ k: 'square', r }, x, y, [0, 1]).filter((p) => room.grid.inside(p[0], p[1]));
    const on = new Set(tiles.map((p) => p[0] + ',' + p[1]));
    const base = src && src.dmg ? src.dmg : TRAP_BASE * (1 + 0.2 * ((room.level || 1) - 1));
    for (const e of [...room.bodies.values()]) {
      if (e === src || e.dead || e.gone) continue;
      const [ex, ey] = AD.combat.tileOf(e);
      if (!on.has(ex + ',' + ey)) continue;
      AD.combat.deal(room, { src, tgt: e, pct, base, type: 'boom', proc: 1, mask: ['explosion'], noStop: true, shield: o.shield });
    }
    room.bus.emit('explode', { x, y, r, tiles });
    if (AD.ai && AD.ai.noise) AD.ai.noise(room, x, y, 6);
    Wd.blast(room, tiles, src);
  };

  // ---------------------------------------------------------------- traps
  Wd.setTrap = function (room, x, y, kind) {
    room.grid.set(x, y, '^');
    room.traps.set(y * W + x, { kind, seen: false, x, y });
  };
  Wd.trapAt = (room, x, y) => room.traps.get(y * W + x) || null;
  function spot(room) {
    const h = room.hero;
    if (!h || h.dead || room.frame % 60 !== 0) return;
    for (const t of room.traps.values()) {
      if (t.seen) continue;
      if (Math.max(Math.abs(t.x - h.x), Math.abs(t.y - h.y)) > 2) continue;
      if (rngC(room)() < (h.trapSense || 0.2)) { t.seen = true; room.bus.emit('trapSpotted', { trap: t }); }
    }
  }
  function spring(room, e, t) {
    t.seen = true;
    room.bus.emit('trap', { trap: t, e });
    const lvl = 1 + 0.2 * ((room.level || 1) - 1);
    switch (t.kind) {
      case 'spike': AD.combat.deal(room, { src: null, tgt: e, amount: Math.round(TRAP_BASE * 0.6 * lvl), type: 'normal', proc: 0, mask: [], fixed: true }); return; // re-arms
      case 'alarm': for (const b of room.bodies.values()) if (b.state === 'asleep') b.state = 'hunt'; break;
      case 'fire': for (const [x, y] of AD.combat.tiles({ k: 'square', r: 1 }, t.x, t.y, [0, 1])) { Wd.flame(room, x, y, 150); Wd.ignite(room, x, y); } break;
      case 'gas': Wd.addGas(room, t.x, t.y, 'poison', 300); break;
      case 'pit': room.grid.set(t.x, t.y, 'O'); room.traps.delete(t.y * W + t.x); fall(room, e); return;
      default: break;
    }
    room.traps.delete(t.y * W + t.x);
    room.grid.set(t.x, t.y, '.');
  }

  // ---------------------------------------------------------------- pits, water, arriving on a tile
  function fall(room, e) {
    const [ex, ey] = room.entry || [7, 8];
    room.grid.release(e.id, e.x, e.y);
    e.move = null; e.pushLeft = 0; e.buf = null;
    // the entry tile may be taken: the nearest free walkable tile to it
    let best = [ex, ey];
    if (room.grid.bodyAt(ex, ey)) {
      let bd = 99;
      for (let y = 1; y < H - 1; y++) for (let x = 1; x < W - 1; x++) {
        if (!room.grid.passable(x, y, 'walk') || room.grid.bodyAt(x, y)) continue;
        const d = Math.max(Math.abs(x - ex), Math.abs(y - ey));
        if (d < bd) { bd = d; best = [x, y]; }
      }
    }
    e.x = best[0]; e.y = best[1]; e.fx = e.x; e.fy = e.y;
    room.grid.claim(e.id, e.x, e.y);
    AD.combat.deal(room, { src: null, tgt: e, amount: Math.max(1, Math.round(e.mhp * 0.1)), type: 'normal', proc: 0, mask: [], fixed: true });
    e.iframes = Math.max(e.iframes, 30);
    room.bus.emit('fall', { e });
  }
  Wd.arrive = function (room, e) {
    const g = room.grid, t = AD.tileInfo(g.at(e.x, e.y));
    if (t.pit && e.mode !== 'fly') { fall(room, e); return; }
    if (t.water && e.statuses.burn) AD.status.clear(e, 'burn');
    if (t.trap && e.kind === 'hero') { const tr = Wd.trapAt(room, e.x, e.y); if (tr) spring(room, e, tr); }
    room.bus.emit('arrive', { e, tile: g.at(e.x, e.y) });
  };

  // ---------------------------------------------------------------- light
  function relight(room) {
    const g = room.grid;
    let fires = 0;
    for (let i = 0; i < N; i++) if (room.fire[i]) fires++;
    const key = g.version + ':' + fires + ':' + room.ambient;
    if (key === room.lightKey) return;
    room.lightKey = key;
    const L = room.light;
    L.fill(room.ambient);
    const src = [];
    for (let i = 0; i < N; i++) {
      const s = Math.max(LIGHT[g.t[i]] || 0, room.fire[i] ? 2 : 0);
      if (s) src.push([i % W, (i / W) | 0, s]);
    }
    for (let i = 0; i < N; i++) {
      const x = i % W, y = (i / W) | 0;
      for (const [sx, sy, s] of src) {
        const v = s - Math.max(Math.abs(x - sx), Math.abs(y - sy));
        if (v > L[i]) L[i] = v;
      }
    }
  }
  Wd.lightAt = (room, x, y) => (room.grid.inside(x, y) ? room.light[y * W + x] : 0);
  Wd.sightRange = (room, x, y) => (Wd.lightAt(room, x, y) >= 2 ? 8 : 4);

  Wd.tick = function (room) {
    tickGas(room);
    tickFire(room);
    spot(room);
    relight(room);
  };

  // what a hero's blow does to the room: cut tall grass, break pots and crates
  Wd.install = function (room) {
    room.bus.on('strike', (p) => {
      const t = p.attack;
      if (!t.owner || t.owner.kind !== 'hero') return;
      for (const [x, y] of t.tiles) {
        const ti = AD.tileInfo(room.grid.at(x, y));
        if (ti.cut || ti.breakable) Wd.breakAt(room, x, y);
        if (t.def.type === 'burn') Wd.ignite(room, x, y);
        if (t.def.type === 'tide') Wd.douse(room, [[x, y]]);
      }
    });
  };
})(window.AD);
