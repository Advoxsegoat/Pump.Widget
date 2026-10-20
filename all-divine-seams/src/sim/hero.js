// The hero: reading the pad, the kit (combo, charged spin, skill, roll), Get Up, regen and levels.
// pad = {sx, sy, a, aHeld, aReleased, b, r, l, q: [..]} where sx, sy are -1, 0 or 1 and a, b, r, l
// are true on the frame the button went down.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const H = (AD.hero = {});

  H.make = function (room, id, run, x, y) {
    const D = AD.HEROES[id];
    const h = AD.ent.make(room, {
      kind: 'hero', team: 'p', x, y, mode: 'hero', heroId: id, look: D.look,
      speed: D.base.move, hp: D.base.hp, dmg: D.base.dmg, armour: D.base.armour, crit: D.base.crit,
      facing: [0, 1], items: {}, itemOrder: [], equipment: null, eqCd: 0,
      level: 1, xp: 0, rolls: D.base.rolls, rollMax: D.base.rolls, rollTimer: 0,
      skillCd: 0, giftIdx: 0, combo: { step: 0, lastEnd: -999 }, charge: 0, queueA: false, queueSpin: false,
      getUpUsed: false, dmgMul: 1, armourGear: 0, moveGear: 1, regenAcc: 0,
    });
    h.onItems = () => H.recompute(h);
    H.recompute(h);
    H.install(room, h);
    return h;
  };

  // hand a hero (with its run state) into a new room
  H.enter = function (room, h, x, y) {
    h.id = ++room.nextId;
    h.x = x; h.y = y; h.fx = x; h.fy = y; h.move = null; h.buf = null; h.pushLeft = 0; h.busy = 0; h.attacking = null; h.queueA = false; h.queueSpin = false; h.gone = false;
    room.bodies.set(h.id, h);
    room.grid.claim(h.id, x, y);
    H.install(room, h);
  };

  H.install = function (room, h) {
    AD.items.install(room, h);
    // Get Up: once a depth, a lethal blow leaves 1 HP
    room.bus.on('lethal', (p) => {
      if (p.tgt !== h || p.cancel || h.getUpUsed) return;
      const G = AD.HEROES[h.heroId].getup;
      if (!G) return;
      p.cancel = true; h.getUpUsed = true;
      h.hp = 1; h.iframes = G.iframes;
      h.getupHeal = { left: G.over, per: (G.heal * h.mhp) / G.over, acc: 0 };
      room.bus.emit('getup', { h });
    }, 40);
  };

  H.recompute = function (h) {
    const D = AD.HEROES[h.heroId], B = D.base, T = AD.items.totals(h);
    const lv = h.level - 1;
    const oldMax = h.mhp;
    // bosses beaten add 10% each
    h.mhp = Math.round((B.hp * (1 + 0.3 * lv) + T.maxHp) * (1 + (h.bossHp || 0)));
    if (oldMax) h.hp = Math.max(1, Math.min(h.mhp, h.hp + Math.max(0, h.mhp - oldMax)));
    h.dmg = B.dmg * (1 + 0.2 * lv) * h.dmgMul;
    h.crit = B.crit + T.crit;
    h.atkSpeed = B.atkSpeed + T.atkSpeed;
    h.itemMove = 1 + T.move;
    h.armour = B.armour + h.armourGear;
    const oldRollMax = h.rollMax;
    h.rollMax = B.rolls + T.rolls + (h.bonusRolls || 0);
    if (h.rollMax > oldRollMax) h.rolls += h.rollMax - oldRollMax;
    h.rolls = Math.min(h.rolls, h.rollMax);
    h.cdMul = T.cdMul;
    h.regen = B.regen * (1 + 0.2 * lv);
  };

  H.gainXp = function (h, n) {
    h.xp += n;
    let up = false;
    while (h.xp >= AD.stat.xpToNext(h.level) - 1e-9) {
      h.xp -= AD.stat.xpToNext(h.level);
      h.level++; up = true;
    }
    if (h.xp < 1e-9) h.xp = 0;
    if (up) H.recompute(h);
    return up;
  };

  H.nextGift = (h) => AD.HEROES[h.heroId].gifts.order[h.giftIdx];

  const spd = (h, f) => Math.max(1, Math.round(f / (h.atkSpeed * AD.status.mods(h).atk)));

  function startCombo(room, h) {
    const C = AD.HEROES[h.heroId].combo;
    if (room.frame - h.combo.lastEnd > C.reset) h.combo.step = 0;
    const hit = C.hits[h.combo.step];
    const def = { shape: hit.shape, pct: hit.pct, push: hit.push, wind: spd(h, C.wind), act: C.act, rec: spd(h, C.rec), proc: 1, kind: 'combo', step: h.combo.step, sfx: C.sfx && C.sfx[h.combo.step] };
    AD.combat.attack(room, h, def);
    h.combo.step = (h.combo.step + 1) % C.hits.length;
    h.combo.lastEnd = room.frame + def.wind + def.act + def.rec;
    h.action = { kind: 'combo', step: def.step, t: 0, len: def.wind + def.act + def.rec };
  }
  function startSpin(room, h) {
    const S = AD.HEROES[h.heroId].spin;
    const twice = AD.items.count(h, 'knucklebrass') > 0;
    const def = { shape: S.shape, pct: S.pct, wind: S.wind, act: S.act, rec: spd(h, S.rec), proc: 1, shield: S.shield, kind: 'spin', sfx: 'spin' };
    AD.combat.attack(room, h, def);
    if (twice) AD.combat.attack(room, h, Object.assign({}, def, { wind: S.wind + S.act + 4 }));
    h.combo.step = 0;
    h.action = { kind: 'spin', t: 0, len: def.wind + def.act + def.rec };
  }
  function startGift(room, h) {
    const G = AD.HEROES[h.heroId].gifts;
    const name = G.order[h.giftIdx];
    const g = G[name];
    AD.combat.attack(room, h, { shape: g.shape, pct: g.pct, status: g.status, push: g.push, wind: g.wind, act: g.act, rec: spd(h, g.rec), proc: 1, type: g.type, kind: 'gift', gift: name, sfx: name });
    h.giftIdx = (h.giftIdx + 1) % G.order.length;
    h.skillCd = Math.round(G.cd * h.cdMul);
    h.action = { kind: 'gift', gift: name, t: 0, len: g.wind + g.act + g.rec };
  }
  // a blow on its active frames: a roll cannot cancel it
  const landing = (h) => !!h.attacking && h.attacking.frame > h.attacking.def.wind && h.attacking.frame <= h.attacking.def.wind + h.attacking.def.act;
  function startRoll(room, h, dx, dy) {
    const R = AD.HEROES[h.heroId].roll;
    if (h.attacking) { // a roll cancels a blow still winding up or recovering, never one landing
      const t = h.attacking;
      if (landing(h)) return false;
      room.attacks.splice(room.attacks.indexOf(t), 1);
      h.attacking = null;
    }
    h.busy = 0;
    h.rolls--;
    if (h.curse === 'fickle' && h.hp > 1) h.hp -= 1;
    if (!h.rollTimer) h.rollTimer = R.recharge;
    h.iframes = Math.max(h.iframes, R.iframes);
    h.facing = [dx, dy];
    h.rolling = R.frames;
    AD.ent.push(room, h, dx, dy, R.tiles, Math.round(R.frames / R.tiles));
    h.action = { kind: 'roll', t: 0, len: R.frames };
    room.bus.emit('roll', { h });
    return true;
  }

  H.control = function (room, h, pad) {
    if (h.dead || h.gone) return;
    const D = AD.HEROES[h.heroId];
    // timers
    if (h.skillCd > 0) h.skillCd--;
    if (h.rollTimer > 0 && --h.rollTimer === 0) {
      h.rolls = Math.min(h.rollMax, h.rolls + 1);
      if (h.rolls < h.rollMax) h.rollTimer = D.roll.recharge;
    }
    if (h.rolling > 0) h.rolling--;
    if (h.action) { h.action.t++; if (h.action.t > h.action.len) h.action = null; }
    if (h.getupHeal) {
      const g = h.getupHeal;
      g.acc += g.per; const k = Math.floor(g.acc + 1e-9); g.acc -= k;
      if (k) h.hp = Math.min(h.mhp, h.hp + k);
      if (--g.left <= 0) h.getupHeal = null;
    }
    // healing over time (a draught of Healing)
    if (h.hots && h.hots.length) {
      for (const g of h.hots) { g.acc += g.per; const k = Math.floor(g.acc + 1e-9); g.acc -= k; if (k) AD.items.heal(room, h, k); g.left--; }
      h.hots = h.hots.filter((g) => g.left > 0);
    }
    // regen, carried a fraction at a time
    if (h.hp < h.mhp && !AD.status.mods(h).noHeal) {
      h.regenAcc += h.regen / 60;
      if (h.regenAcc >= 1) { const k = Math.floor(h.regenAcc); h.regenAcc -= k; h.hp = Math.min(h.mhp, h.hp + k); }
    } else h.regenAcc = 0;
    h.moveMul = h.itemMove * (h.harpoonMul || 1) * h.moveGear * AD.status.mods(h).move;

    const m = AD.status.mods(h);
    if (m.stunned) return;
    // charging a spin while A is held
    if (pad.aHeld && ++h.charge === D.spin.charge) room.bus.emit('charged', { h });
    if (pad.aReleased) {
      if (h.charge >= D.spin.charge) h.queueSpin = true;
      h.charge = 0;
    }
    if (pad.a) h.queueA = true;
    const dir = [pad.sx || 0, pad.sy || 0];
    const moving = !!(dir[0] || dir[1]);
    // roll
    if (pad.r && h.rolls > 0 && !h.rolling && !h.pushLeft) {
      const [dx, dy] = moving ? dir : h.facing;
      if (h.move || landing(h)) {
        // finish the step, or let the blow land: the roll is taken the first frame it can be
        h.queueRoll = [dx, dy];
      } else if (startRoll(room, h, dx, dy)) { h.queueA = false; return; }
    }
    if (h.queueRoll && !h.move && !h.pushLeft && !landing(h)) { const [dx, dy] = h.queueRoll; h.queueRoll = null; if (h.rolls > 0) { startRoll(room, h, dx, dy); return; } }
    if (h.rolling || h.pushLeft) return;
    // equipment
    if (pad.l) AD.items.useEquipment(room, h);
    // quickslots are the run's to handle (consumables)
    const free = !h.busy && !h.move;
    if (free) {
      if (h.queueSpin) { h.queueSpin = false; h.queueA = false; startSpin(room, h); return; }
      if (pad.b && h.skillCd === 0) { if (moving) h.facing = dir; startGift(room, h); h.queueA = false; return; }
      if (h.queueA) { h.queueA = false; if (moving) h.facing = dir; startCombo(room, h); return; }
    }
    if (h.busy) return;
    // walking
    if (moving && !m.rooted) {
      if (h.move) AD.ent.buffer(h, dir[0], dir[1]);
      else if (!AD.ent.tryStep(room, h, dir[0], dir[1])) {
        // slide along a wall when a diagonal is blocked
        if (dir[0] && dir[1]) { if (!AD.ent.tryStep(room, h, dir[0], 0)) AD.ent.tryStep(room, h, 0, dir[1]); h.facing = dir; }
      }
    } else if (moving) h.facing = dir;
  };
})(window.AD);
