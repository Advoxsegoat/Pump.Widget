// Monster logic (spec §7.1). States: asleep, wander, hunt, flee. Walkers follow a distance map from
// the hero, rebuilt only when the hero changes tile; ranged monsters use the inverted keep-away map;
// flyers have their own map over pits and water. Every attack is telegraphed (sim/combat.js).
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const AI = (AD.ai = {});
  const W = 15;
  const sgn = Math.sign;
  const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
  const rngOf = (room) => AD.combat.rngOf(room);
  const ELITE = { 1: { hp: 4, dmg: 2 }, 2: { hp: 18, dmg: 6 } };

  AI.spawn = function (room, id, x, y, o) {
    o = o || {};
    const D = AD.MONSTERS[id];
    const level = o.level || 1;
    const tier = o.elite ? o.eliteTier || 1 : 0;
    const k = tier ? ELITE[tier] : { hp: 1, dmg: 1 };
    const hp = o.hp !== undefined ? o.hp : AD.stat.scaleHp(D.hp, level) * k.hp;
    const m = AD.ent.make(room, {
      kind: 'monster', team: 'e', x, y, mode: D.mode, speed: D.speed, hp, mhp: hp,
      dmg: AD.stat.scaleDmg(D.dmg, level) * k.dmg, crit: 0, defId: id, def: D, family: D.family, look: D.look,
      level, elite: o.elite || null, eliteTier: tier, state: o.asleep ? 'asleep' : 'hunt', atkCd: 30 + ((x * 7 + y * 13) % 20),
      cost: D.cost, shimmer: o.shimmer || 0, untargetable: !!o.shimmer, healT: D.heal ? D.heal.every : 0, turnT: 0,
    });
    if (room.hero) m.facing = [sgn(room.hero.x - x) || 0, sgn(room.hero.y - y) || 1];
    if (room.bus) room.bus.emit('spawn', { m });
    return m;
  };

  // ---------------------------------------------------------------- maps
  AI.maps = function (room) {
    const h = room.hero;
    const key = h ? h.x + ',' + h.y + ',' + room.grid.version : 'none';
    if (room.aiMaps && room.aiMaps.key === key) return room.aiMaps;
    const goal = h ? [[h.x, h.y]] : [];
    room.aiMaps = { key, walk: room.grid.distanceMap(goal, 'walk'), fly: room.grid.distanceMap(goal, 'fly'), flee: {} };
    return room.aiMaps;
  };
  function fleeMap(room, mode) {
    const M = AI.maps(room);
    if (!M.flee[mode]) M.flee[mode] = room.grid.fleeMap(M[mode]);
    return M.flee[mode];
  }
  // step to the neighbour that lowers the map the most; ties go to straight steps, in a fixed order
  const ORDER = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]];
  function stepBy(room, m, map, opts) {
    const cur = map[m.y * W + m.x];
    let best = null, bestV = cur < 0 ? Infinity : cur;
    for (const [dx, dy] of ORDER) {
      const nx = m.x + dx, ny = m.y + dy;
      const v = map[ny * W + nx];
      if (v === undefined || v < 0 || v >= 9999) continue;
      if (opts && opts.keep && !opts.keep(nx, ny)) continue;
      if (v < bestV - 1e-6 && AD.ent.canStep(room, m, dx, dy)) { best = [dx, dy]; bestV = v; }
    }
    if (!best && opts && opts.side) {
      // blocked by bodies: sidestep to an equal tile now and then, so crowds flow round each other
      for (const [dx, dy] of ORDER) {
        const v = map[(m.y + dy) * W + m.x + dx];
        if (v === cur && AD.ent.canStep(room, m, dx, dy) && rngOf(room)() < 0.25) { best = [dx, dy]; break; }
      }
    }
    if (best) return AD.ent.tryStep(room, m, best[0], best[1]);
    return false;
  }

  // ---------------------------------------------------------------- attacks
  const dir8 = (m, t) => [sgn(t.x - m.x), sgn(t.y - m.y)];
  const aligned = (m, t) => { const dx = t.x - m.x, dy = t.y - m.y; return dx === 0 || dy === 0 || Math.abs(dx) === Math.abs(dy); };
  function canHit(room, m, def, t) {
    const d = cheb(m, t), s = def.shape;
    if (s.k === 'shot') return d <= s.range && room.grid.los(m.x, m.y, t.x, t.y);
    if (s.k === 'lob') return d >= 2 && d <= s.range + 1;
    if (!aligned(m, t) && s.k !== 'adjacent') return false;
    const f = dir8(m, t);
    const [tx, ty] = AD.combat.tileOf(t);
    return AD.combat.aim(room, s, m.x, m.y, f).some((p) => p[0] === tx && p[1] === ty);
  }
  function startAttack(room, m, def, t) {
    m.facing = dir8(m, t);
    if (!m.facing[0] && !m.facing[1]) m.facing = [0, 1];
    const s = def.shape;
    let full = def;
    if (s.k === 'shot') {
      const tiles = AD.combat.aim(room, { k: 'line', n: s.range }, m.x, m.y, m.facing);
      full = Object.assign({}, def, { tiles: [], aimTiles: tiles, pct: 0, onStrike: (r) => shoot(r, m, def, t) });
    } else if (s.k === 'lob') {
      full = Object.assign({}, def, { tiles: [], pct: 0, onStrike: (r) => lob(r, m, def, t) });
    } else if (def.lunge) {
      full = Object.assign({}, def, { onStrike: (r) => { const [dx, dy] = m.facing; if (!m.dead && AD.ent.canStep(r, m, dx, dy)) AD.ent.push(r, m, dx, dy, def.lunge, 4); } });
    }
    AD.combat.attack(room, m, full);
    m.seq = def.then || null;
    m.atkCd = def.cool || 24;
  }
  function shoot(room, m, def, t) {
    if (m.dead) return;
    const s = def.shape;
    let vx = t.fx - m.x, vy = t.fy - m.y;
    const len = Math.hypot(vx, vy) || 1;
    vx = (vx / len) * (s.speed / 60); vy = (vy / len) * (s.speed / 60);
    (room.projs || (room.projs = [])).push({ x: m.x, y: m.y, vx, vy, left: s.range, owner: m, team: m.team, pct: def.pct, kind: def.shot || 'stone', id: ++room.nextId });
  }
  function lob(room, m, def, t) {
    if (m.dead) return;
    const s = def.shape;
    let tx = t.x, ty = t.y;
    if (cheb(m, t) > s.range) { const f = dir8(m, t); tx = m.x + f[0] * s.range; ty = m.y + f[1] * s.range; }
    const tiles = AD.combat.tiles(def.bomb.shape, tx, ty, [0, 1]).filter((p) => room.grid.inside(p[0], p[1]) && !AD.tileInfo(room.grid.at(p[0], p[1])).wall);
    room.bombsThrown = (room.bombsThrown || 0) + 1;
    AD.combat.attack(room, m, {
      tiles, wind: def.bomb.fuse, act: 2, rec: 0, pct: def.pct, proc: 1, type: 'boom', persist: true, friendly: true, noBusy: true, bomb: true, at: [tx, ty], sfx: 'boom',
      onStrike: (r) => { if (AD.world && AD.world.blast) AD.world.blast(r, tiles, m); AI.noise(r, tx, ty, 6); },
    });
  }

  AI.tickProjectiles = function (room) {
    const P = room.projs;
    if (!P || !P.length) return;
    for (let i = P.length - 1; i >= 0; i--) {
      const p = P[i];
      p.x += p.vx; p.y += p.vy;
      p.left -= Math.hypot(p.vx, p.vy);
      const tx = Math.round(p.x), ty = Math.round(p.y);
      if (p.left <= 0 || !room.grid.passable(tx, ty, 'fly') && !AD.tileInfo(room.grid.at(tx, ty)).solid || AD.tileInfo(room.grid.at(tx, ty)).wall) { P.splice(i, 1); continue; }
      let gone = false;
      for (const e of room.bodies.values()) {
        if (e.team === p.team || e.dead || e.gone || e === p.owner || e.untargetable) continue;
        const [ex, ey] = AD.combat.tileOf(e);
        if (ex !== tx || ey !== ty) continue;
        if (e.iframes > 0) continue;
        if (e.skillet > 0 && (-p.vx * e.facing[0] - p.vy * e.facing[1]) > 0) {
          p.vx = -p.vx; p.vy = -p.vy; p.team = e.team; p.owner = e; p.left = 8;
          room.bus.emit('reflect', { p, by: e });
          break;
        }
        AD.combat.deal(room, { src: p.owner, tgt: e, pct: p.pct, type: 'normal', proc: 1, mask: [], noStop: true });
        gone = true;
        break;
      }
      if (gone) P.splice(i, 1);
    }
  };

  // ---------------------------------------------------------------- noise and sight
  AI.noise = function (room, x, y, r) {
    for (const e of room.bodies.values()) {
      if (e.state !== 'asleep' || e.dead) continue;
      if (Math.max(Math.abs(e.x - x), Math.abs(e.y - y)) > r) continue;
      if (rngOf(room)() < 0.5) { e.state = 'hunt'; room.bus.emit('wake', { m: e }); }
    }
  };
  const sight = (room, m) => (AD.world && AD.world.sightRange ? AD.world.sightRange(room, m.x, m.y) : 8);
  AI.sees = (room, m, t) => cheb(m, t) <= sight(room, m) && room.grid.los(m.x, m.y, t.x, t.y);

  // ---------------------------------------------------------------- brains
  AI.think = function (room, m) {
    if (m.dead || m.gone) return;
    if (m.shimmer > 0) { m.shimmer--; m.untargetable = m.shimmer > 0; return; }
    if (m.hitstop > 0) return;
    const st = AD.status.mods(m);
    m.moveMul = st.move;
    if (st.stunned) return;
    if (m.atkCd > 0) m.atkCd--;
    if (m.busy) return;
    const t = room.hero;
    if (m.state === 'asleep') return;
    if (!t || t.dead || t.gone) return;
    const D = m.def;
    // a chained blow (the Tough's second swing, the Knuckle's combo) follows at once
    if (m.seq) { const nx = m.seq; m.seq = null; if (canHit(room, m, nx, t)) { startAttack(room, m, nx, t); return; } }
    if (D.brain === 'shaman') return shaman(room, m, t, st);
    if (m.state === 'flee' || D.brain === 'thief' && m.stolen) return flee(room, m, t, st);
    if (m.state === 'wander') { if (AI.sees(room, m, t)) m.state = 'hunt'; else return; }
    const atk = D.attacks[0];
    // Brass Masks turn slowly: flank them
    if (D.turn) {
      if (--m.turnT <= 0) { m.facing = dir8(m, t); m.turnT = D.turn; }
    }
    if (atk && m.atkCd <= 0 && canHit(room, m, atk, t) && !(D.turn && !facingOk(m, t))) { startAttack(room, m, atk, t); return; }
    if (st.rooted || m.move || m.pushLeft) return;
    if (D.brain === 'ranged') return ranged(room, m, t, D);
    // melee: close in until a blow can land, then wait for it
    if (atk && canHit(room, m, atk, t)) return;
    stepBy(room, m, AI.maps(room)[m.mode], { side: true });
  };
  const facingOk = (m, t) => { const f = dir8(m, t); return f[0] === m.facing[0] && f[1] === m.facing[1]; };

  function ranged(room, m, t, D) {
    const d = cheb(m, t), [lo, hi] = D.keep;
    const M = AI.maps(room);
    if (d < lo) { if (!stepBy(room, m, fleeMap(room, m.mode), { keep: (x, y) => Math.max(Math.abs(x - t.x), Math.abs(y - t.y)) <= hi })) stepBy(room, m, fleeMap(room, m.mode)); return; }
    const sees = AI.sees(room, m, t);
    if (d > hi || !sees) { stepBy(room, m, M[m.mode], { side: true }); return; }
    if (D.aligned && !aligned(m, t)) {
      // line up for a shot, keeping the distance
      for (const [dx, dy] of ORDER) {
        const nx = m.x + dx, ny = m.y + dy, nd = Math.max(Math.abs(nx - t.x), Math.abs(ny - t.y));
        const ok = nx === t.x || ny === t.y || Math.abs(nx - t.x) === Math.abs(ny - t.y);
        if (ok && nd >= lo && nd <= hi && AD.ent.canStep(room, m, dx, dy)) { AD.ent.tryStep(room, m, dx, dy); return; }
      }
    }
  }

  function shaman(room, m, t, st) {
    const H = m.def.heal;
    if (--m.healT <= 0) {
      m.healT = H.every;
      let any = false;
      for (const e of room.bodies.values()) {
        if (e.family !== 'goblin' || e.dead || e === m || cheb(e, m) > H.r) continue;
        if (e.hp < e.mhp) { e.hp = Math.min(e.mhp, e.hp + H.amount); room.bus.emit('heal', { tgt: e, amount: H.amount }); }
        AD.status.apply(e, 'haste', { dur: H.haste });
        any = true;
      }
      if (any) room.bus.emit('shamanCast', { m });
    }
    if (st.rooted || m.move || m.pushLeft) return;
    ranged(room, m, t, m.def);
  }

  function flee(room, m, t, st) {
    if (m.def.brain === 'thief') {
      if (--m.escape <= 0) { room.bus.emit('escape', { m }); AD.ent.remove(room, m); return; }
    } else if (--m.fleeT <= 0 || m.hp > m.mhp * 0.5) { m.state = 'hunt'; return; }
    if (st.rooted || m.move || m.pushLeft) return;
    // goblins run to a shaman if one lives, otherwise away
    const sh = m.family === 'goblin' && [...room.bodies.values()].find((e) => e.defId === 'shaman' && !e.dead && e !== m);
    if (sh && m.def.brain !== 'thief') { if (cheb(m, sh) > 1) stepBy(room, m, room.grid.distanceMap([[sh.x, sh.y]], m.mode)); return; }
    stepBy(room, m, fleeMap(room, m.mode), { side: true });
  }

  // ---------------------------------------------------------------- listeners
  AI.install = function (room) {
    const bus = room.bus;
    // a surprise blow always crits
    bus.on('dealMods', (p) => { if (p.tgt && p.tgt.state === 'asleep') p.crit = true; }, 30);
    // a shield takes most of a blow from the front
    bus.on('takeMods', (p) => {
      const tg = p.tgt, s = p.src;
      if (!tg.def || !tg.def.shield || !s || p.rec.fixed) return;
      const dx = s.x - tg.x, dy = s.y - tg.y;
      if (dx * tg.facing[0] + dy * tg.facing[1] > 0) { p.mul *= 1 - tg.def.shield; p.shielded = true; }
    });
    bus.on('hit', (p) => {
      const tg = p.tgt;
      if (tg.state === 'asleep') tg.state = 'hunt';
      // the pickpocket's hand
      if (p.rec.steal && p.src && p.src.def && p.src.def.brain === 'thief' && tg === room.hero && room.run) {
        const coins = room.run.coins || 0;
        const take = Math.min(coins, Math.max(5, Math.min(50, Math.round(coins * 0.1))));
        room.run.coins = coins - take;
        p.src.stolen = (p.src.stolen || 0) + take;
        p.src.state = 'flee'; p.src.escape = p.src.def.escape;
        bus.emit('stolen', { m: p.src, amount: take });
      }
      // goblins below a quarter of their health may run
      if (tg.family === 'goblin' && !tg.dead && tg.def.brain !== 'thief' && !tg.moraleRolled && tg.hp < tg.mhp * 0.25) {
        tg.moraleRolled = true;
        if (rngOf(room)() < 0.5) { tg.state = 'flee'; tg.fleeT = 300; }
      }
    }, 20);
    bus.on('kill', (p) => {
      if (p.tgt.stolen && room.dropPickup) room.dropPickup(p.tgt.x, p.tgt.y, { kind: 'coins', amount: Math.round(p.tgt.stolen * 1.5) });
    });
    // what wakes sleepers
    bus.on('attackStart', (p) => { const o = p.attack.owner; if (o.kind === 'hero') AI.noise(room, o.x, o.y, 4); });
    bus.on('roll', (p) => AI.noise(room, p.h.x, p.h.y, 2));
  };
})(window.AD);
