// What items do (spec §5.1, §5.3). Items stack without limit. On-hit chances are multiplied by the
// hit's proc coefficient, and a hit made by an item carries that item in its chain mask, so items
// set each other off but never loop.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const IT = (AD.items = {});
  const St = AD.stat;
  const n = (h, id) => (h.items && h.items[id]) || 0;
  IT.count = n;

  IT.give = function (run, h, id) {
    const d = AD.ITEMS[id];
    if (!d) return false;
    if (d.tier === 'equipment') {
      const old = h.equipment;
      h.equipment = id; h.eqCd = 0;
      if (old && run && run.dropEquipment) run.dropEquipment(old);
    } else {
      h.items = h.items || {}; h.itemOrder = h.itemOrder || [];
      if (!h.items[id]) h.itemOrder.push(id);
      h.items[id] = (h.items[id] || 0) + 1;
    }
    h.flat = IT.totals(h).flat;
    if (h.onItems) h.onItems();
    return true;
  };
  IT.take = function (h, id) {
    if (!n(h, id)) return false;
    h.items[id]--;
    if (!h.items[id]) { delete h.items[id]; h.itemOrder = h.itemOrder.filter((x) => x !== id); }
    h.flat = IT.totals(h).flat;
    if (h.onItems) h.onItems();
    return true;
  };

  // the stat items, summed
  IT.totals = function (h) {
    return {
      maxHp: St.linear(25, 25, n(h, 'lazyman')),
      move: 0.14 * n(h, 'coffeeflask'),
      atkSpeed: 0.15 * n(h, 'silkscarf'),
      crit: 0.1 * n(h, 'gamblerschip'),
      regenOOC: 3 * n(h, 'taffy'),
      rolls: n(h, 'crowfeather'),
      cdMul: St.diminish(0.9, n(h, 'lucienswatch')),
      flat: 5 * n(h, 'brassbuttons'),
    };
  };
  IT.blockChance = (h) => St.hyperbolic(0.15, n(h, 'tinring'));

  IT.heal = function (room, h, amount) {
    if (h.dead || amount <= 0) return 0;
    if (AD.status && AD.status.mods(h).noHeal) return 0;
    const before = h.hp;
    h.hp = Math.min(h.mhp, h.hp + Math.round(amount * (h.healMul || 1)));
    const got = h.hp - before;
    if (got > 0) room.bus.emit('heal', { tgt: h, amount: got });
    return got;
  };

  // enemies of h near a point, nearest first (ties by id, so it stays deterministic)
  IT.foesNear = function (room, h, x, y, r, skip) {
    const out = [];
    for (const e of room.bodies.values()) {
      if (e.team === h.team || e.dead || e.gone || e.untargetable || (skip && skip.has(e.id))) continue;
      if (e.kind !== 'monster' && e.kind !== 'boss') continue;
      const d = Math.max(Math.abs(e.x - x), Math.abs(e.y - y));
      if (d <= r) out.push([d, e.id, e]);
    }
    out.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    return out.map((o) => o[2]);
  };

  function procHit(room, h, tgt, pct, id, parent, proc, extra) {
    return AD.combat.deal(room, Object.assign({ src: h, tgt, pct, type: extra && extra.type || 'normal', proc, mask: parent.mask.concat([id]), noStop: true, canCrit: true }, extra));
  }
  const chanceOk = (room, p) => p > 0 && AD.combat.rngOf(room)() < p;

  IT.install = function (room, h) {
    const bus = room.bus;
    // damage bonuses
    bus.on('dealMods', (p) => {
      if (p.src !== h) return;
      const mitts = n(h, 'warmmitts');
      if (mitts && p.tgt.mhp && p.tgt.hp / p.tgt.mhp > 0.9) p.bonus += 0.75 * mitts;
      if (n(h, 'brassmoon') && !p.rec.mask.length && !p.rec.fixed && p.rec.proc >= 1) {
        h.moonCount = (h.moonCount || 0) + 1;
        if (h.moonCount % 3 === 0) { p.crit = true; p.rec.moonCrit = true; }
      }
    }, 40);
    // blocks
    bus.on('block', (p) => {
      if (p.tgt !== h || p.blocked) return;
      if (h.skillet > 0 && p.src) {
        const dx = p.src.x - h.x, dy = p.src.y - h.y;
        if (dx * h.facing[0] + dy * h.facing[1] > 0) { p.blocked = true; return; }
      }
      if (n(h, 'tinring') && chanceOk(room, IT.blockChance(h))) p.blocked = true;
    }, 40);
    // on-hit
    bus.on('hit', (p) => {
      if (p.src !== h || !p.tgt || p.tgt.team === h.team) return;
      const rec = p.rec, proc = rec.proc || 0;
      if (rec.moonCrit) {
        const k = 2 + (n(h, 'brassmoon') - 1);
        IT.foesNear(room, h, p.tgt.x, p.tgt.y, 4, new Set([p.tgt.id])).slice(0, k)
          .forEach((e) => procHit(room, h, e, 0.8, 'brassmoon', rec, 0.2, { type: 'spark' }));
      }
      if (!proc) return;
      for (const id of (h.itemOrder || []).slice()) {
        const c = n(h, id);
        if (!c || rec.mask.indexOf(id) >= 0) continue;
        switch (id) {
          case 'rosethorn':
            if (chanceOk(room, 0.1 * c * proc) && !p.tgt.dead) AD.status.apply(p.tgt, 'bleed', { src: h, dur: 180 });
            break;
          case 'sparkcoil':
            if (chanceOk(room, 0.25 * proc)) {
              IT.foesNear(room, h, p.tgt.x, p.tgt.y, 4, new Set([p.tgt.id])).slice(0, 3 + 2 * (c - 1))
                .forEach((e) => procHit(room, h, e, 0.8, id, rec, 0.2, { type: 'spark' }));
            }
            break;
          case 'throwingknives':
            if (chanceOk(room, 0.1 * c * proc)) {
              const t = IT.foesNear(room, h, h.x, h.y, 5, new Set([p.tgt.id]))[0];
              if (t) procHit(room, h, t, 2, id, rec, 0.5);
            }
            break;
          case 'petalstorm':
            if (chanceOk(room, 0.1 * proc)) {
              const foes = IT.foesNear(room, h, h.x, h.y, 6);
              for (let i = 0; i < 3 + (c - 1) && foes.length; i++) procHit(room, h, foes[i % foes.length], 1, id, rec, 0.33);
            }
            break;
          case 'ivoryshard':
            if (chanceOk(room, 0.08 * c * proc)) {
              IT.foesNear(room, h, p.tgt.x, p.tgt.y, 1).forEach((e) => procHit(room, h, e, 1.5, id, rec, 0, { type: 'chill', status: { kind: 'chill', dur: 120 } }));
            }
            break;
          case 'bloodroot':
            h.bloodAcc = (h.bloodAcc || 0) + c * proc;
            if (h.bloodAcc >= 1) { const k = Math.floor(h.bloodAcc); h.bloodAcc -= k; IT.heal(room, h, k); }
            break;
          default: break;
        }
      }
    }, 60);
    // on-kill
    bus.on('kill', (p) => {
      if (p.src !== h || p.tgt === h) return;
      const body = p.tgt;
      const bo = n(h, 'bouillabaisse');
      if (bo) {
        const amt = 8 + 0.02 * bo * h.mhp;
        if (room.dropPickup) room.dropPickup(body.x, body.y, { kind: 'heal', amount: amt }); else IT.heal(room, h, amt);
      }
      const bell = n(h, 'bellchime');
      if (bell && p.rec.mask.indexOf('bellchime') < 0) {
        IT.foesNear(room, h, body.x, body.y, 1, new Set([body.id])).forEach((e) => procHit(room, h, e, 1 + 0.75 * (bell - 1), 'bellchime', p.rec, 0.5));
      }
      const hp = n(h, 'harpoon');
      if (hp) h.harpoon = { t: 120, amt: 1.25 + 0.25 * (hp - 1) };
      const band = n(h, 'bandolier');
      if (band && chanceOk(room, St.hyperbolic(0.18, band))) { h.rolls = h.rollMax || h.rolls; h.skillCd = 0; room.bus.emit('refill', { h }); }
    }, 60);
    // the heart
    bus.on('lethal', (p) => {
      if (p.tgt !== h || p.cancel || !n(h, 'roseheart')) return;
      p.cancel = true;
      IT.take(h, 'roseheart');
      IT.give(null, h, 'wiltedrose');
      h.hp = h.mhp; h.iframes = 120;
      room.bus.emit('revive', { tgt: h, by: 'roseheart' });
    }, 60);
    bus.on('roomClear', () => {
      const s = n(h, 'sardinetin');
      if (s) IT.heal(room, h, 0.08 * s * h.mhp);
    }, 60);
  };

  IT.tick = function (room, h) {
    if (h.eqCd > 0) h.eqCd--;
    if (h.skillet > 0) h.skillet--;
    if (h.harpoon) { h.harpoon.t--; if (h.harpoon.t <= 0) h.harpoon = null; }
    h.harpoonMul = h.harpoon ? 1 + h.harpoon.amt * (h.harpoon.t / 120) : 1;
    const taffy = n(h, 'taffy');
    if (taffy && room.frame - (h.hurtAt === undefined ? -9999 : h.hurtAt) >= 420 && room.frame % 60 === 0 && h.hp < h.mhp) IT.heal(room, h, 3 * taffy);
    const buck = n(h, 'kaelsbuckler');
    h.armourBonus = buck && h.busy > 0 ? 30 * buck : 0;
  };

  IT.useEquipment = function (room, h) {
    const id = h.equipment, d = id && AD.ITEMS[id];
    if (!d || h.eqCd > 0 || h.dead) return false;
    const rec0 = { mask: [], proc: 1 };
    switch (id) {
      case 'anchor': {
        for (const e of IT.foesNear(room, h, h.x, h.y, 1)) procHit(room, h, e, 4, id, rec0, 1);
        for (const e of IT.foesNear(room, h, h.x, h.y, 2)) {
          if (e.dead || e.immovable || e.heavy) continue;
          const dx = Math.sign(h.x - e.x), dy = Math.sign(h.y - e.y);
          if (Math.max(Math.abs(e.x - h.x), Math.abs(e.y - h.y)) > 1) AD.ent.push(room, e, dx, dy, 1);
        }
        break;
      }
      case 'powderbarrel': {
        let x = h.x, y = h.y;
        for (let k = 1; k <= 4; k++) {
          const nx = h.x + h.facing[0] * k, ny = h.y + h.facing[1] * k;
          if (!room.grid.passable(nx, ny, 'fly')) break;
          x = nx; y = ny;
        }
        if (AD.world && AD.world.explode) AD.world.explode(room, x, y, 2, 6, h, { shield: 2 });
        break;
      }
      case 'pocketbell':
        if (room.run) room.run.revealed = true;
        for (const e of IT.foesNear(room, h, h.x, h.y, 4)) AD.status.apply(e, 'stun', { dur: 90 });
        break;
      case 'skillet':
        h.skillet = 180;
        break;
      default: return false;
    }
    h.eqCd = d.cd * 60;
    room.bus.emit('useEquipment', { h, id });
    return true;
  };
})(window.AD);
