// Drawing a room (spec §3, §9.1): the baked ground, the floor's live marks (traps, gas, fire,
// telegraphs, pickups), then each row of props with the bodies standing in it, then the effects,
// the light and the bloom. During the 20-frame room slide both rooms are drawn, offset.
// Nothing here changes the game; every position comes from tiles times AD.display.T.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const V = (AD.view = {});
  const A = AD.art, G = AD.gfx, TL = AD.tiles, FX = AD.fx;
  const SLIDE = 20;
  const gba = () => AD.display.mode === 'gba';
  const dirOf = (f) => (!f ? 'down' : f[0] < 0 ? 'left' : f[0] > 0 ? 'right' : f[1] < 0 ? 'up' : 'down');
  V.dirOf = dirOf;
  const GAS_C = [null, '#7ad84a', '#9a9aa8', '#5a4e4e'];
  const DARK = [0.78, 0.6, 0.42, 0.24, 0.08];
  const COLOUR_HEX = { Amber: '#ffb000', Crimson: '#c8203a', Jade: '#3aa86a', Indigo: '#4a4ab8', Golden: '#e8c170', Silver: '#c8ccd8', Charcoal: '#3a3a44', Rose: '#e8607e', Turquoise: '#3ac8c0', Ivory: '#f4eee0', Magenta: '#c83ab8', Azure: '#3a8ae8' };
  V.COLOUR_HEX = COLOUR_HEX;

  // ---------------------------------------------------------------- each room's art
  // kept beside the room, not in it, so the simulation's state stays plain data. Only the rooms drawn
  // most lately keep theirs (the room in play, one sliding in, the few behind): a room walked back
  // into after that is baked again from its tiles as they now stand
  const arts = new WeakMap(), recent = [];
  const KEEP = 6;
  V.KEEP_ART = KEEP;
  function artOf(room) {
    // a place outside the depths (the Garden) says its own biome
    const d = room.biome ? { biome: room.biome, night: !!room.night } : AD.regionAt(room.depth).d;
    let v = arts.get(room);
    if (!v || v.art.mode !== AD.display.mode) {
      v = { art: A.roomArt(room.grid.rows(), d.biome, d.night), version: room.grid.version };
      arts.set(room, v);
    } else if (v.version !== room.grid.version) {
      A.patch(v.art, room.grid.rows());
      v.version = room.grid.version;
    }
    if (recent[0] !== room) {
      const i = recent.indexOf(room);
      if (i > 0) recent.splice(i, 1);
      recent.unshift(room);
      if (recent.length > KEEP) arts.delete(recent.pop());
    }
    return v.art;
  }
  V.artOf = artOf;

  // ---------------------------------------------------------------- how a body stands
  function heroPose(h, room) {
    if (h.dead) return ['dead', 0, {}];
    const a = h.action, def = h.attacking && h.attacking.def;
    if (a) {
      const o = def ? { wind: def.wind, act: def.act } : {};
      if (a.kind === 'combo') return ['attack' + (a.step + 1), a.t, o];
      if (a.kind === 'spin') return ['spin', a.t, o];
      if (a.kind === 'gift') return ['cast', a.t, Object.assign(o, { element: a.gift })];
      if (a.kind === 'roll') return ['roll', a.t, { frames: a.len }];
    }
    if (h.hurtAt != null && room.frame - h.hurtAt < 10) return ['hurt', 0, {}];
    if (h.move) return ['walk', room.frame, {}];
    return ['idle', room.frame, {}];
  }
  function monsterPose(m, room) {
    if (m.dead) return ['dead', 0, {}];
    const t = m.attacking;
    if (t && !t.def.noBusy) {
      const list = (m.def && m.def.attacks) || [], i = list.indexOf(t.def);
      return ['attack' + (i < 0 ? 2 : Math.min(3, i + 1)), t.frame, { wind: t.def.wind, act: t.def.act }];
    }
    if (m.hurtAt != null && room.frame - m.hurtAt < 8 && !m.busy) return ['hurt', 0, {}];
    if (m.move) return ['walk', Math.round(room.frame * ((m.speed || 5) / 7.5)), {}];
    return ['idle', room.frame + (m.id * 7) % 40, {}];
  }
  // how far a blow throws the body forward while it lands
  function lunge(e) {
    const t = e.attacking;
    if (!t || t.def.noBusy) return 0;
    const d = t.def;
    if (t.frame <= d.wind) return 0;
    if (t.frame <= d.wind + d.act) return d.lunge ? 0.35 : 0.18;
    return Math.max(0, (d.lunge ? 0.35 : 0.18) * (1 - (t.frame - d.wind - d.act) / Math.max(1, d.rec)));
  }
  const whites = new WeakMap();
  function white(c) {
    let w = whites.get(c);
    if (!w) { w = G.canvas(c.width, c.height); w.x.drawImage(c, 0, 0); w.x.globalCompositeOperation = 'source-in'; w.x.fillStyle = '#ffffff'; w.x.fillRect(0, 0, c.width, c.height); whites.set(c, w); }
    return w;
  }

  function drawBody(ctx, room, e, ox, oy, run) {
    const T = AD.display.T, f = room.frame;
    const hero = e.kind === 'hero';
    const [action, t, o] = hero ? heroPose(e, room) : monsterPose(e, room);
    const id = hero ? e.look || 'abarax' : e.defId;
    const look = hero ? AD.lookFor('abarax', run && run.armour && !e.dead ? run.armour.id : null) : null;
    const dir = dirOf(e.facing);
    const frame = hero ? A.frames(look, action, dir, t, o) : A.monster(id, action, dir, t, o);
    const an = A.anchor(hero ? 'abarax' : id);
    const fwd = lunge(e);
    let x = ox + (e.fx + e.facing[0] * fwd) * T, y = oy + (e.fy + e.facing[1] * fwd) * T;
    if (e.hitstop > 0) x += e.hitstop % 2 ? 1 : -1;
    const fly = e.mode === 'fly';
    const bob = fly ? Math.round(Math.sin((f + e.id * 9) / 9) * 2) : 0;
    // the shadow anchors the body to its tile
    ctx.fillStyle = 'rgba(8,6,16,0.28)';
    const sw = Math.round(T * (fly ? 0.26 : 0.34)), sy = Math.round(y + T * 0.86);
    ctx.fillRect(Math.round(x + T / 2 - sw), sy, sw * 2, 2); ctx.fillRect(Math.round(x + T / 2 - sw + 2), sy - 1, sw * 2 - 4, 4);
    if (e.elite && AD.ELITES[e.elite]) {
      ctx.globalAlpha = 0.28 + 0.12 * Math.sin(f / 8);
      ctx.fillStyle = AD.ELITES[e.elite].c;
      ctx.fillRect(Math.round(x + T / 2 - sw - 2), sy - 2, sw * 2 + 4, 5);
      ctx.globalAlpha = 1;
    }
    // spawn shimmer, the hero's blink while he cannot be hit
    let alpha = 1;
    if (e.shimmer > 0) alpha = 0.25 + 0.35 * ((f >> 1) % 2);
    else if (hero && e.iframes > 0 && !e.rolling && (f >> 2) % 2) alpha = 0.45;
    ctx.globalAlpha = alpha;
    ctx.drawImage(frame, Math.round(x + an.ox), Math.round(y + an.oy + bob));
    if (e.flash > 0) { ctx.globalAlpha = Math.min(1, e.flash / 4) * 0.85; ctx.drawImage(white(frame), Math.round(x + an.ox), Math.round(y + an.oy + bob)); }
    if (e.shimmer > 0) { ctx.globalAlpha = 0.6; ctx.fillStyle = '#e8e0ff'; ctx.fillRect(Math.round(x + T / 2) - 1, Math.round(y - T * 0.5), 2, Math.round(T * 1.3)); }
    ctx.globalAlpha = 1;
    // the charged spin: the fists gather light, and glint when it is ready
    if (hero && e.charge > 8) {
      const ready = e.charge >= AD.HEROES[e.heroId].spin.charge;
      ctx.fillStyle = ready && (f >> 2) % 2 ? '#ffffff' : '#ffd84a';
      const n = ready ? 6 : 3;
      for (let i = 0; i < n; i++) { const a = f / 6 + (i / n) * Math.PI * 2, r = T * (ready ? 0.55 : 0.75 - Math.min(0.3, e.charge / 120)); ctx.fillRect(Math.round(x + T / 2 + Math.cos(a) * r), Math.round(y + T * 0.4 + Math.sin(a) * r * 0.6), 1, 1); }
    }
    return { x, y: y + bob, an };
  }

  // a monster's bar once it is hurt, its elite mark beside it, sleep and stagger
  function marks(ctx, room, e, at) {
    const T = AD.display.T, f = room.frame;
    if (e.kind === 'monster' && e.hp < e.mhp && !e.dead) {
      const w = Math.round(T * 0.66), bx = Math.round(at.x + (T - w) / 2), by = Math.round(at.y + at.an.oy + (A.BEAST[e.look] ? -1 : 4));
      const shown = trail(e, e.hp / e.mhp);
      ctx.fillStyle = '#06040a'; ctx.fillRect(bx - 1, by - 1, w + 2, 4);
      ctx.fillStyle = '#3a1418'; ctx.fillRect(bx, by, w, 2);
      ctx.fillStyle = '#f4eee0'; ctx.fillRect(bx, by, Math.round(w * shown), 2);
      ctx.fillStyle = e.elite ? AD.ELITES[e.elite].c : '#e8343a'; ctx.fillRect(bx, by, Math.round(w * e.hp / e.mhp), 2);
      if (e.elite && AD.ELITES[e.elite]) { ctx.fillStyle = '#06040a'; ctx.fillRect(bx - 6, by - 2, 5, 5); ctx.fillStyle = AD.ELITES[e.elite].c; ctx.fillRect(bx - 5, by - 1, 3, 3); }
    }
    if (e.state === 'asleep' && !e.dead) {
      const k = (f + e.id * 13) % 60;
      ctx.globalAlpha = k < 45 ? 1 : (60 - k) / 15;
      G.text(ctx, 'z', at.x + T * 0.7 + k / 12, at.y + at.an.oy - k / 6, '#c8d0ff');
      ctx.globalAlpha = 1;
    }
    if ((e.stagger > 0 || e.stunned > 0 || (e.statuses && e.statuses.stun)) && !e.dead) {
      ctx.fillStyle = '#ffd84a';
      for (let i = 0; i < 3; i++) { const a = f / 7 + (i / 3) * Math.PI * 2; ctx.fillRect(Math.round(at.x + T / 2 + Math.cos(a) * T * 0.35), Math.round(at.y + at.an.oy + 2 + Math.sin(a) * 2), 2, 2); }
    }
    if (e.statuses && e.statuses.burn && (f >> 2) % 2) { ctx.fillStyle = '#ff9a3a'; ctx.fillRect(Math.round(at.x + T * (0.3 + ((f >> 3) % 3) * 0.2)), Math.round(at.y + T * 0.1 - (f % 8)), 1, 2); }
  }
  // the damage chunk: what a bar showed a moment ago, falling to what it shows now
  const shownOf = new WeakMap();
  function trail(e, frac) {
    let s = shownOf.get(e);
    if (s === undefined || s < frac) s = frac;
    s = Math.max(frac, s - 0.012);
    shownOf.set(e, s);
    return s;
  }
  V.trail = trail;

  // ---------------------------------------------------------------- a room
  function drawRoom(ctx, run, room, ox, oy, live) {
    const T = AD.display.T, f = room.frame, W = 15, Hh = 10;
    const art = artOf(room), R = art.view;
    ox = Math.round(ox); oy = Math.round(oy);
    ctx.drawImage(R.ground[TL.groundFrame()], ox, oy);
    // the floor's live marks
    if (room.traps) for (const t of room.traps.values()) {
      const s = A.sprite('trap', { kind: t.kind, seen: t.seen });
      ctx.globalAlpha = t.seen ? 1 : 0.16;
      ctx.drawImage(s.c, ox + t.x * T + s.ox, oy + t.y * T + s.oy);
    }
    ctx.globalAlpha = 1;
    if (room.gas) for (let i = 0; i < W * Hh; i++) {
      const v = room.gas[i];
      if (v < 2) continue;
      ctx.globalAlpha = Math.min(0.6, 0.12 + v / 160);
      ctx.fillStyle = GAS_C[room.gasKind[i]] || GAS_C[1];
      const x = i % W, y = (i / W) | 0, w = Math.round(Math.sin((f + i * 5) / 14) * 1.5);
      ctx.fillRect(ox + x * T - w, oy + y * T + w, T + w * 2, T - w);
    }
    ctx.globalAlpha = 1;
    for (const c of room.corpses) {
      ctx.globalAlpha = c.t > 25 ? Math.max(0, (40 - c.t) / 15) : 1;
      const an = A.anchor(c.defId);
      ctx.drawImage(A.monster(c.defId, 'dead', dirOf(c.facing), 0), Math.round(ox + c.x * T + an.ox), Math.round(oy + c.y * T + an.oy));
    }
    ctx.globalAlpha = 1;
    for (const p of room.pickups) {
      const o = pickupLook(run, p);
      const s = A.sprite('pickup', o, f + (p.id ? p.id.length * 7 : 0));
      const bob = p.kind === 'coins' ? 0 : Math.round(Math.sin((f + p.x * 11) / 12) * 1.5) - 1;
      if (o.tier && o.tier !== 'common') { ctx.globalAlpha = 0.25 + 0.15 * Math.sin(f / 10); ctx.fillStyle = A.TIER_C[o.tier]; ctx.fillRect(ox + p.fx * T + T * 0.2, oy + p.fy * T + T * 0.75, T * 0.6, 2); ctx.globalAlpha = 1; }
      ctx.drawImage(s.c, Math.round(ox + p.fx * T + s.ox), Math.round(oy + p.fy * T + s.oy + bob));
    }
    // telegraphs: what is coming fills red across its wind-up; a lit bomb sits on its tile
    for (const a of room.attacks || []) {
      const d = a.def, o = a.owner;
      if (!o || (o.kind === 'hero' && !d.bomb) || a.frame > d.wind) continue;
      const k = d.wind ? a.frame / d.wind : 1;
      for (const [x, y] of a.tiles) {
        ctx.globalAlpha = 0.2 + 0.5 * k;
        ctx.fillStyle = '#d8283a'; ctx.fillRect(ox + x * T + 1, oy + y * T + 1, T - 2, T - 2);
        ctx.globalAlpha = Math.min(1, 0.4 + 0.6 * k);
        ctx.fillStyle = '#ff8a8a';
        ctx.fillRect(ox + x * T + 1, oy + y * T + 1, T - 2, 1); ctx.fillRect(ox + x * T + 1, oy + y * T + T - 2, T - 2, 1);
      }
      ctx.globalAlpha = 1;
      if (d.bomb && d.at) { const s = A.sprite('bomb', { hot: d.wind - a.frame < 24 }, f); ctx.drawImage(s.c, ox + d.at[0] * T + s.ox, oy + d.at[1] * T + s.oy); }
    }
    if (room.fire) for (let i = 0; i < W * Hh; i++) {
      if (!room.fire[i]) continue;
      const s = A.sprite('flame', { f: ((f >> 2) + i) % 4 });
      ctx.drawImage(s.c, ox + (i % W) * T + s.ox, oy + ((i / W) | 0) * T + s.oy);
    }
    // rows of props, with what stands in each row drawn after it
    const bodies = live || room.bodies.size ? [...room.bodies.values()].filter((e) => !e.gone).sort((a, b) => a.fy - b.fy || a.fx - b.fx) : [];
    const glyphs = art.rows;
    const drawn = [];
    let bi = 0;
    for (let Y = 0; Y < Hh; Y++) {
      if (R.rows[Y]) ctx.drawImage(R.rows[Y], ox, oy + Y * T - R.head);
      for (let X = 0; X < W; X++) {
        const ch = glyphs[Y][X];
        let s = null;
        if (ch === 'C') s = A.sprite('chest', { big: room.type === 'secret', open: !!room.chests[X + ',' + Y] });
        else if (ch === 'G') s = A.sprite('gate', room.gateLook || (run && run.gate && run.room === room ? { charge: run.gate.charge, open: run.gate.open } : { charge: 0 }), f);
        else if (ch === 'f') s = A.sprite('flame', { f: (f >> 3) % 4 });
        if (s) ctx.drawImage(s.c, ox + X * T + s.ox, oy + Y * T + s.oy);
      }
      while (bi < bodies.length && Math.floor(bodies[bi].fy + 0.001) <= Y) {
        const e = bodies[bi++];
        drawn.push([e, drawBody(ctx, room, e, ox, oy, run)]);
      }
    }
    while (bi < bodies.length) { const e = bodies[bi++]; drawn.push([e, drawBody(ctx, room, e, ox, oy, run)]); }
    for (const p of room.projs || []) {
      const s = A.sprite('shot', { kind: p.kind });
      ctx.drawImage(s.c, Math.round(ox + (p.x + 0.5) * T + s.ox), Math.round(oy + (p.y + 0.4) * T + s.oy));
    }
    for (const [e, at] of drawn) marks(ctx, room, e, at);
    // the light this room gives off
    // the painter's lamps glow softer here: a pool of light on the stones, not a spotlight
    const lights = R.lights.map((l) => ({ x: ox + l.x, y: oy + l.y, r: l.flicker ? l.r * (0.94 + 0.06 * Math.sin(f / 5)) : l.r, c: l.c, a: (l.a || 0.3) * 0.5 }));
    if (room.fire) for (let i = 0; i < W * Hh; i++) if (room.fire[i]) lights.push({ x: ox + ((i % W) + 0.5) * T, y: oy + (((i / W) | 0) + 0.5) * T, r: T * 1.6, c: '#ff9a3a', a: 0.3 });
    if (live && room.hero && !room.hero.dead) lights.push({ x: ox + (room.hero.fx + 0.5) * T, y: oy + (room.hero.fy + 0.4) * T, r: T * 4, c: null });
    return lights;
  }

  // what a pickup looks like: a draught shows its run's colour, a page its rune's
  function pickupLook(run, p) {
    if (p.kind === 'item') { const it = AD.ITEMS && AD.ITEMS[p.item || p.id]; return { kind: 'item', tier: it ? it.tier : 'common' }; }
    if (p.kind === 'cons') {
      const id = p.cons || p.item || p.id;
      if (id === 'bomb') return { kind: 'cons', bomb: 1 };
      if (AD.SCROLLS && AD.SCROLLS[id]) return { kind: 'cons', scroll: 1, c: '#8a3a6a' };
      const name = run && run.idTable && run.idTable.potions[id];
      return { kind: 'cons', c: COLOUR_HEX[name] || '#c8ccd8' };
    }
    return { kind: p.kind, amount: p.amount };
  }
  V.pickupLook = pickupLook;

  // a room not yet entered, seen through the door during the slide: its layout, nothing alive
  const peeks = new WeakMap();
  function peek(run, key) {
    let m = peeks.get(run);
    if (!m || m.depth !== run.depth) { m = { depth: run.depth, rooms: new Map() }; peeks.set(run, m); }
    if (!m.rooms.has(key)) {
      const info = run.floor.rooms.get(key);
      m.rooms.set(key, { key, type: info ? info.type : 'combat', depth: run.depth, grid: new AD.Grid(run.layoutOf(key).rows), bodies: new Map(), pickups: [], corpses: [], attacks: [], projs: [], chests: {}, frame: 0, hero: null });
    }
    return m.rooms.get(key);
  }

  // ---------------------------------------------------------------- a run on screen
  // effects, HUD and sound follow the run's bus; the region's whole cast is drawn now, in this display
  // mode, so a crowd arriving never pays for its first frames
  const roster = (run) => { const R = run.region().R; return Object.keys(R.weights).concat(R.minis, [R.boss]); };
  let bound = null;
  V.bind = function (run) {
    if (bound) bound.forEach((f) => f());
    FX.bind(run); AD.hud.bind(run);
    const warm = () => { A.warm(['abarax'].concat(roster(run))); };
    warm();
    let region = run.region().id;
    const offDepth = run.events.on('depthStart', () => { if (run.region().id !== region) { region = run.region().id; warm(); } }, 97);
    AD.display.onChange.push(warm);
    bound = [offDepth, () => { const i = AD.display.onChange.indexOf(warm); if (i >= 0) AD.display.onChange.splice(i, 1); }];
    if (AD.audio && AD.audio.bind) bound.push(AD.audio.bind(run.events));
    // haptics (spec 9.3): a tick on landing a blow, a thump on being hurt
    bound.push(run.events.on('hit', (p) => { if (p.src === run.hero && p.amount > 0) AD.input.buzz(p.crit ? 18 : 8); }, 99));
    bound.push(run.events.on('hurt', () => AD.input.buzz(30), 99));
  };

  // ---------------------------------------------------------------- the frame
  function light(ctx, lights, ambient, night, ox, oy) {
    const W = AD.display.W, H = AD.display.H;
    const a = DARK[Math.max(0, Math.min(4, ambient))];
    if (AD.settings.effects) { if (a > 0.02) FX.lighting(ctx, night ? `rgba(6,8,26,${a})` : `rgba(10,8,18,${a})`, lights.concat(FX.lightsAt(ox, oy))); }
    else { ctx.fillStyle = `rgba(10,8,18,${a * 0.5})`; ctx.fillRect(-8, -8, W + 16, H + 16); }
  }
  function finish(ctx) {
    if (AD.settings.effects && !gba()) FX.post(ctx, { bloom: true, tilt: false, threshold: 205, bloomAmt: 0.3 });
    FX.drawFlash(ctx, FX.flashPeak());
  }
  // a place with no run behind it (the Garden): {ambient, night}
  V.drawPlace = function (ctx, room, o) {
    o = o || {};
    const [sx, sy] = FX.offset();
    ctx.save();
    ctx.fillStyle = '#06040a'; ctx.fillRect(0, 0, AD.display.W, AD.display.H);
    ctx.translate(sx, sy);
    const lights = drawRoom(ctx, null, room, 0, 0, true);
    FX.draw(ctx, 0, 0);
    light(ctx, lights, o.ambient === undefined ? 3 : o.ambient, !!o.night, 0, 0);
    FX.drawNumbers(ctx, 0, 0);
    ctx.restore();
    finish(ctx);
  };
  V.draw = function (ctx, run) {
    const W = AD.display.W, H = AD.display.H;
    const [sx, sy] = FX.offset();
    ctx.save();
    ctx.fillStyle = '#06040a'; ctx.fillRect(0, 0, W, H);
    ctx.translate(sx, sy);
    const tr = run.transition;
    let lights, ox = 0, oy = 0;
    if (tr) {
      const p = 1 - tr.t / SLIDE, e = p * p * (3 - 2 * p);
      const [dx, dy] = AD.gen.DIRS[tr.dir];
      ox = -dx * e * W; oy = -dy * e * H;
      lights = drawRoom(ctx, run, run.room, ox, oy, true);
      const next = run.rooms.get(tr.to) || peek(run, tr.to);
      lights = lights.concat(drawRoom(ctx, run, next, ox + dx * W, oy + dy * H, false));
    } else lights = drawRoom(ctx, run, run.room, 0, 0, true);
    FX.draw(ctx, ox, oy);
    const d = AD.regionAt(run.depth).d;
    light(ctx, lights, d.ambient, d.night, ox, oy);
    FX.drawNumbers(ctx, ox, oy);
    ctx.restore();
    finish(ctx);
  };
})(window.AD);
