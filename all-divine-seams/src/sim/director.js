// The spawner (Risk of Rain's director, spec §6.3) and elites (§7.4). A room gets a credit budget
// from the difficulty clock and spends it in up to three waves; the next wave comes when what is
// alive is worth less than 30% of the current wave. Never more than 40 monsters at once.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const D = (AD.director = {});
  const MAX_ALIVE = 40;
  D.MAX_ALIVE = MAX_ALIVE;

  AD.ELITES = {
    goldflame: { n: 'Gold-flame', icon: 'flame', c: '#ffb347' },
    ivory: { n: 'Ivory', icon: 'ivory', c: '#cfe8ff' },
    spark: { n: 'Spark-struck', icon: 'spark', c: '#c9a0ff' },
    thorned: { n: 'Thorned', icon: 'thorn', c: '#6ad06a' },
    seam: { n: 'Seam-touched', icon: 'seam', c: '#e8607e' },
  };
  const AFFIXES = Object.keys(AD.ELITES);

  D.budget = (coef, kind) => (kind === 'gate' ? 15 + 8 * coef : (20 + 10 * coef) * (kind === 'challenge' ? 1.5 : 1));

  const eliteCost = (cost, tier) => cost * (tier === 2 ? 36 : tier === 1 ? 6 : 1);

  D.plan = function (r, regionId, depth, budget) {
    const R = AD.REGIONS[regionId];
    const pool = Object.keys(R.weights).filter((id) => AD.MONSTERS[id] && AD.MONSTERS[id].from <= depth);
    const waves = budget < 40 ? 1 : budget < 80 ? 2 : 3;
    const out = [];
    for (let w = 0; w < waves; w++) {
      let left = budget / waves;
      const wave = [];
      for (let guard = 0; guard < 400; guard++) {
        const can = pool.filter((id) => AD.MONSTERS[id].cost <= left);
        if (!can.length) break;
        const id = AD.rng.weighted(r, can.map((v) => ({ w: R.weights[v], v })));
        const M = AD.MONSTERS[id];
        const tier = depth >= 16 && left >= eliteCost(M.cost, 2) ? 2 : depth >= 3 && left >= eliteCost(M.cost, 1) ? 1 : 0;
        const one = (el) => (el ? { id, elite: AD.rng.pick(r, AFFIXES), eliteTier: tier } : { id });
        if (M.pack && !tier && left >= M.cost * M.pack) {
          for (let k = 0; k < M.pack; k++) wave.push(one(false));
          left -= M.cost * M.pack;
        } else if (M.pack && !tier) {
          // a pack it cannot afford: something else
          const others = can.filter((v) => !AD.MONSTERS[v].pack);
          if (!others.length) break;
          continue;
        } else {
          wave.push(one(tier > 0));
          left -= eliteCost(M.cost, tier);
        }
      }
      if (wave.length) out.push(wave);
    }
    return out;
  };

  // free walkable tiles away from the hero and the doors; the farther the better at first
  D.spawnTiles = function (room, n, r) {
    const g = room.grid, h = room.hero;
    for (const minD of [4, 3, 2, 1]) {
      const ok = [];
      for (let y = 1; y < g.h - 1; y++) for (let x = 1; x < g.w - 1; x++) {
        const t = AD.tileInfo(g.at(x, y));
        if (!t.walk || t.door || t.trap || t.gate || t.pit || t.pedestal) continue;
        if (g.bodyAt(x, y)) continue;
        if (h && Math.max(Math.abs(x - h.x), Math.abs(y - h.y)) < minD) continue;
        // not in a doorway's mouth either
        if ((y === 1 || y === g.h - 2) && x === 7 || (x === 1 || x === g.w - 2) && y === 4) continue;
        ok.push([x, y]);
      }
      if (ok.length >= n || minD === 1) return AD.rng.shuffle(r, ok).slice(0, n);
    }
    return [];
  };

  D.begin = function (room, waves) {
    room.waves = waves;
    room.waveIdx = 1;
    room.pending = (waves[0] || []).slice();
    room.waveCost = waveCost(waves[0] || []);
  };
  const waveCost = (w) => w.reduce((t, s) => t + eliteCost(AD.MONSTERS[s.id].cost, s.elite ? s.eliteTier || 1 : 0), 0);
  const alive = (room) => [...room.bodies.values()].filter((b) => (b.kind === 'monster' || b.kind === 'boss') && !b.dead && !b.gone && !b.ally);

  D.tick = function (room) {
    if (!room.waves) return;
    const live = alive(room);
    if (!room.pending.length && room.waveIdx < room.waves.length) {
      const cost = live.reduce((t, b) => t + eliteCost(b.cost || 0, b.eliteTier || 0), 0);
      if (cost < room.waveCost * 0.3) {
        const w = room.waves[room.waveIdx++];
        room.pending = w.slice();
        room.waveCost = waveCost(w);
        room.bus.emit('wave', { n: room.waveIdx });
      }
    }
    if (room.pending.length) {
      const space = Math.max(0, MAX_ALIVE - live.length);
      if (!space) return;
      const batch = room.pending.splice(0, space);
      const r = (room.rng && room.rng.combat) || AD.rng.make(1);
      const tiles = D.spawnTiles(room, batch.length, r);
      batch.forEach((s, i) => {
        if (!tiles[i]) { room.pending.push(s); return; }
        AD.ai.spawn(room, s.id, tiles[i][0], tiles[i][1], { level: room.level || 1, elite: s.elite, eliteTier: s.eliteTier, shimmer: 18 });
      });
    }
  };
  D.done = (room) => !room.waves || (room.waveIdx >= room.waves.length && !room.pending.length && !alive(room).length);

  // elite behaviour
  D.install = function (room) {
    const bus = room.bus;
    const loot = () => (room.rng && room.rng.loot) || AD.rng.make(2);
    bus.on('hit', (p) => {
      const s = p.src;
      if (!s || !s.elite || !p.tgt || p.tgt.team === s.team || p.rec.fixed) return;
      switch (s.elite) {
        case 'goldflame': AD.status.apply(p.tgt, 'burn', { src: s, dur: 180 }); break;
        case 'ivory': AD.status.apply(p.tgt, 'chill', { dur: 120 }); break;
        case 'thorned': AD.status.apply(p.tgt, 'noheal', { dur: 240 }); break;
        case 'spark': (room.sparks || (room.sparks = [])).push({ tgt: p.tgt, src: s, t: 90 }); break;
        default: break;
      }
    }, 70);
    bus.on('kill', (p) => {
      const m = p.tgt;
      if (!m.elite) return;
      if (m.elite === 'ivory') {
        const tiles = AD.combat.tiles({ k: 'square', r: 1 }, m.x, m.y, [0, 1]);
        AD.combat.attack(room, m, { tiles, wind: 60, act: 2, rec: 0, pct: 1, proc: 0, persist: true, noBusy: true, status: { kind: 'chill', dur: 120 }, type: 'chill' });
      }
      if (loot()() < 0.25 && room.dropPickup) room.dropPickup(m.x, m.y, { kind: 'petal', amount: 1 });
    }, 70);
  };

  // per-frame elite effects: fire trails, sparks, blinks
  D.tickElites = function (room) {
    if (room.sparks && room.sparks.length) {
      for (let i = room.sparks.length - 1; i >= 0; i--) {
        const s = room.sparks[i];
        if (--s.t > 0) continue;
        room.sparks.splice(i, 1);
        if (!s.tgt.dead && !s.tgt.gone) AD.combat.deal(room, { src: s.src, tgt: s.tgt, pct: 1, base: s.src.dmg, type: 'spark', proc: 0, mask: [], noStop: true });
      }
    }
    const h = room.hero;
    for (const m of room.bodies.values()) {
      if (!m.elite || m.dead || m.gone || m.shimmer > 0) continue;
      if (m.elite === 'goldflame' && m.move && m.move.t === 1 && AD.world && AD.world.flame) AD.world.flame(room, m.move.x0, m.move.y0, 90);
      if (m.elite === 'seam' && h && !h.dead) {
        m.blinkT = (m.blinkT || 240) - 1;
        if (m.blinkT <= 0 && !m.busy && !m.move) {
          m.blinkT = 240;
          const bx = h.x - h.facing[0], by = h.y - h.facing[1];
          if (room.grid.passable(bx, by, m.mode) && !room.grid.bodyAt(bx, by)) {
            room.grid.release(m.id, m.x, m.y);
            m.x = bx; m.y = by; m.fx = bx; m.fy = by;
            room.grid.claim(m.id, bx, by);
            m.facing = [Math.sign(h.x - bx), Math.sign(h.y - by)];
            room.bus.emit('blink', { m });
          }
        }
      }
    }
  };
})(window.AD);
