// Combat: the shapes attacks cover, the damage pipeline, and telegraphed attacks that wind up,
// strike and recover. Every hit is a damage record that items can read and add to (spec §5.1).
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const C = (AD.combat = {});
  const fallbackRng = AD.rng ? AD.rng.make(1) : () => 0.5;
  const rngOf = (room) => (room.rng && room.rng.combat) || fallbackRng;
  C.rngOf = rngOf;

  // ---------------------------------------------------------------- shapes
  // facing is a unit step [dx, dy]; p is the perpendicular
  C.tiles = function (shape, x, y, facing) {
    const [fx, fy] = facing;
    const px = -fy, py = fx;
    const out = [];
    const add = (tx, ty) => out.push([tx, ty]);
    const at = shape.at || 0;
    switch (shape.k) {
      case 'adjacent': add(x + fx, y + fy); break;
      case 'point': add(x + fx * at, y + fy * at); break;
      case 'line': for (let k = 1; k <= shape.n; k++) add(x + fx * k, y + fy * k); break;
      case 'arc3': add(x + fx, y + fy); add(x + fx - px, y + fy - py); add(x + fx + px, y + fy + py); break;
      case 'cone':
        for (let k = 1; k <= shape.n; k++) for (let j = -(k - 1); j <= k - 1; j++) add(x + fx * k + px * j, y + fy * k + py * j);
        break;
      case 'wave': {
        const half = (shape.w - 1) >> 1;
        for (let k = 1; k <= shape.n; k++) for (let j = -half; j <= half; j++) add(x + fx * k + px * j, y + fy * k + py * j);
        break;
      }
      case 'ring': {
        const r = shape.r, cx = x + fx * at, cy = y + fy * at;
        for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) if (Math.max(Math.abs(dx), Math.abs(dy)) === r) add(cx + dx, cy + dy);
        break;
      }
      case 'square': {
        const r = shape.r, cx = x + fx * at, cy = y + fy * at;
        for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) add(cx + dx, cy + dy);
        break;
      }
      case 'plus': {
        const cx = x + fx * at, cy = y + fy * at;
        add(cx, cy);
        for (let k = 1; k <= shape.r; k++) { add(cx + k, cy); add(cx - k, cy); add(cx, cy + k); add(cx, cy - k); }
        break;
      }
      case 'list': for (const t of shape.tiles) add(t[0], t[1]); break;
      default: break;
    }
    return out;
  };

  // the tiles an attack really covers in this room: lines and waves stop at walls, nothing lands in one
  C.aim = function (room, shape, x, y, facing) {
    const g = room.grid;
    const raw = C.tiles(shape, x, y, facing);
    if (shape.k === 'line') {
      const out = [];
      for (const t of raw) { if (!g.inside(t[0], t[1]) || g.opaque(t[0], t[1]) && AD.tileInfo(g.at(t[0], t[1])).wall) break; out.push(t); }
      return out;
    }
    return raw.filter((t) => g.inside(t[0], t[1]) && !AD.tileInfo(g.at(t[0], t[1])).wall);
  };

  // which tile a body counts as standing on (the nearer of the two it holds mid-step)
  C.tileOf = (e) => [Math.round(e.fx), Math.round(e.fy)];

  // ---------------------------------------------------------------- the damage pipeline
  C.deal = function (room, rec) {
    const src = rec.src, tgt = rec.tgt;
    if (!tgt || tgt.dead || tgt.gone || tgt.hp <= 0) return null;
    const bus = room.bus, r = rngOf(room);
    const res = { amount: 0, crit: false, blocked: false, killed: false, missed: false };
    let amount;
    if (rec.fixed) {
      amount = rec.amount;
    } else {
      const sm = src ? AD.status.mods(src) : null;
      if (sm && sm.miss && r() < sm.miss) { res.missed = true; bus.emit('miss', { rec }); return res; }
      const base = rec.base !== undefined ? rec.base : (src ? src.dmg || 0 : 0);
      const p = bus.emit('dealMods', { rec, src, tgt, bonus: 0, crit: !!rec.forceCrit, mul: 1 });
      if (!p.crit && rec.canCrit !== false && src && src.crit && r() < src.crit) p.crit = true;
      res.crit = p.crit;
      amount = base * rec.pct * (p.crit ? 2 : 1) * (1 + p.bonus) * p.mul * (sm ? sm.dmg : 1);
      const b = bus.emit('block', { rec, src, tgt, blocked: false });
      if (b.blocked) { res.blocked = true; bus.emit('blocked', { rec, src, tgt }); return res; }
      const tm = bus.emit('takeMods', { rec, src, tgt, mul: 1 });
      amount *= tm.mul;
      const armour = (tgt.armour || 0) + (tgt.armourBonus || 0) + AD.status.mods(tgt).armour;
      amount = AD.stat.mitigate(amount, armour);
      if (tgt.flat) amount = Math.max(1, amount - tgt.flat);
      amount = Math.max(1, Math.round(amount));
      const stop = p.crit ? 5 : 3;
      if (src && !rec.noStop) src.hitstop = Math.max(src.hitstop || 0, stop);
      tgt.hitstop = Math.max(tgt.hitstop || 0, stop);
      tgt.flash = 6;
    }
    tgt.hp -= amount;
    res.amount = amount;
    tgt.lastHitBy = src;
    tgt.hurtAt = room.frame;
    bus.emit('hit', { rec, src, tgt, amount, crit: res.crit, type: rec.type });
    if (tgt.hp <= 0) {
      const l = bus.emit('lethal', { rec, src, tgt, cancel: false });
      if (!l.cancel || tgt.hp <= 0) {
        tgt.hp = 0; tgt.dead = true; res.killed = true;
        bus.emit('kill', { rec, src, tgt });
        return res;
      }
    }
    if (rec.status) AD.status.apply(tgt, rec.status.kind, Object.assign({ src }, rec.status));
    if (rec.push && !tgt.dead) {
      const dx = Math.sign(tgt.x - (src ? src.x : tgt.x)) || (src ? src.facing[0] : 0);
      const dy = Math.sign(tgt.y - (src ? src.y : tgt.y)) || (src ? src.facing[1] : 0);
      if (dx || dy) AD.ent.push(room, tgt, dx, dy, rec.push);
    }
    return res;
  };

  // ---------------------------------------------------------------- telegraphed attacks
  // def: {shape, wind, act, rec, pct, proc, status?, push?, type?, onHit?, onStrike?}
  C.attack = function (room, owner, def, facing) {
    facing = facing || owner.facing;
    const tiles = def.tiles || C.aim(room, def.shape, owner.x, owner.y, facing);
    const t = { owner, def, tiles, facing, frame: 0, hit: new Set(), id: ++room.nextId };
    (room.attacks || (room.attacks = [])).push(t);
    owner.busy = def.wind + def.act + def.rec;
    owner.attacking = t;
    if (room.bus) room.bus.emit('attackStart', { attack: t });
    return t;
  };

  C.tick = function (room) {
    const list = room.attacks;
    if (!list || !list.length) { for (const e of room.bodies.values()) if (e.busy > 0 && !e.hitstop) e.busy--; return; }
    for (const e of room.bodies.values()) if (e.busy > 0 && !e.hitstop) e.busy--;
    for (let i = list.length - 1; i >= 0; i--) {
      const t = list[i], d = t.def, o = t.owner;
      if (o.dead || o.gone) { if (t.frame < d.wind || d.persist !== true) { list.splice(i, 1); if (o.attacking === t) o.attacking = null; continue; } }
      if (o.hitstop > 0 && !d.persist) continue;
      t.frame++;
      if (t.frame === d.wind + 1 && d.onStrike) d.onStrike(room, t);
      if (t.frame > d.wind && t.frame <= d.wind + d.act) strike(room, t);
      if (t.frame >= d.wind + d.act + d.rec) { list.splice(i, 1); if (o.attacking === t) o.attacking = null; }
    }
  };

  function strike(room, t) {
    const d = t.def, o = t.owner;
    const on = new Set(t.tiles.map((p) => p[0] + ',' + p[1]));
    for (const e of room.bodies.values()) {
      if (e === o || e.dead || e.gone || t.hit.has(e.id)) continue;
      if (d.friendly !== true && e.team === o.team) continue;
      if (e.untargetable) continue;
      const [ex, ey] = C.tileOf(e);
      if (!on.has(ex + ',' + ey)) continue;
      if (e.iframes > 0) { t.hit.add(e.id); if (room.bus) room.bus.emit('dodge', { attack: t, tgt: e }); continue; }
      t.hit.add(e.id);
      const res = C.deal(room, { src: o, tgt: e, pct: d.pct, type: d.type || 'normal', proc: d.proc === undefined ? 1 : d.proc, mask: [], status: d.status, push: d.push, shield: d.shield, attack: t, canCrit: d.canCrit, base: d.base });
      if (d.onHit && res) d.onHit(room, t, e, res);
    }
  }

  // a body can act when it is not winding up, striking, recovering, stunned or frozen
  C.free = (e) => !e.busy && !e.hitstop && !e.dead && !(e.statuses && (e.statuses.stun));
})(window.AD);
