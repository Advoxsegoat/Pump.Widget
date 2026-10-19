// Statuses (spec §7.5). Damage over time ticks once a second and carries its fractions, so small
// numbers add up honestly.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const S = (AD.status = {});
  // per-second damage as a share of the source's base damage, and how the status stacks
  const DEF = {
    burn: { dot: 0.5, stack: 'refresh', dur: 180, type: 'burn' },
    bleed: { dot: 0.8, stack: 'stack', dur: 180, type: 'bleed' },
    poison: { stack: 'refresh', dur: 60, type: 'poison' },
    chill: { stack: 'refresh', dur: 120 },
    root: { stack: 'refresh', dur: 120 },
    stun: { stack: 'refresh', dur: 60 },
    blind: { stack: 'refresh', dur: 180 },
    weaken: { stack: 'refresh', dur: 240 },
    noheal: { stack: 'refresh', dur: 240 },
    haste: { stack: 'refresh', dur: 180 },
    swift: { stack: 'refresh', dur: 480 },
    tough: { stack: 'refresh', dur: 480 },
  };
  S.DEF = DEF;

  S.apply = function (e, kind, o) {
    if (!e || e.dead || e.gone) return false;
    const d = DEF[kind];
    if (!d) return false;
    o = o || {};
    if (e.immune && e.immune[kind]) return false;
    const dur = o.dur || d.dur;
    const base = o.src ? o.src.dmg || 0 : 0;
    const cur = e.statuses[kind];
    if (d.stack === 'stack' && cur) { cur.stacks.push({ t: 0, dur, per: (o.pct || d.dot) * base }); return true; }
    e.statuses[kind] = { t: 0, dur, src: o.src || null, per: (o.pct || d.dot || 0) * base, amt: o.amt || 0, acc: 0, stacks: d.stack === 'stack' ? [{ t: 0, dur, per: (o.pct || d.dot) * base }] : null };
    return true;
  };
  S.has = (e, kind) => !!e.statuses[kind];
  S.clear = (e, kind) => { delete e.statuses[kind]; };

  function hurt(room, e, st, amount, type) {
    st.acc += amount;
    const n = Math.round(st.acc);
    if (n <= 0) return;
    st.acc -= n;
    AD.combat.deal(room, { src: st.src, tgt: e, amount: n, type, proc: 0, mask: [], fixed: true });
  }

  S.tick = function (room, e) {
    if (e.dead || e.gone) return;
    for (const kind of Object.keys(e.statuses)) {
      const st = e.statuses[kind], d = DEF[kind];
      if (st.stacks) {
        let sum = 0;
        for (const s of st.stacks) { s.t++; if (s.t % 60 === 0) sum += s.per; }
        st.stacks = st.stacks.filter((s) => s.t < s.dur);
        if (sum) hurt(room, e, st, sum, d.type);
        if (!st.stacks.length) delete e.statuses[kind];
        continue;
      }
      st.t++;
      if (d.dot && st.t % 60 === 0) hurt(room, e, st, st.per, d.type);
      if (kind === 'poison' && st.t % 60 === 0 && st.amt) hurt(room, e, st, st.amt, 'poison');
      if (e.dead) return;
      if (st.t >= st.dur) delete e.statuses[kind];
    }
  };

  // what the statuses do to a body right now
  S.mods = function (e) {
    const s = e.statuses;
    const m = { move: 1, atk: 1, dmg: 1, armour: 0, miss: 0, rooted: false, stunned: false, noHeal: false };
    if (s.chill) { m.move *= 0.6; m.atk *= 0.6; }
    if (s.haste) { m.move *= 1.3; m.atk *= 1.3; }
    if (s.swift) { m.move *= 1.5; m.atk *= 1.5; }
    if (s.tough) m.armour += 60;
    if (s.root) m.rooted = true;
    if (s.stun) m.stunned = true;
    if (s.blind) m.miss = 0.5;
    if (s.weaken) { m.dmg *= 0.7; m.armour -= 20; }
    if (s.noheal) m.noHeal = true;
    return m;
  };
})(window.AD);
