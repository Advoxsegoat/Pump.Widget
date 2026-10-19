// A run (spec §2.2, §6): the floors, the rooms, the clock, coins and keys, pickups, the Seam Gate,
// the depths, and how a run ends. run.tick(pad) is one 60 Hz step of the whole game.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const MOUTH = () => AD.room.MOUTH;
  const SIDE_OF = (x, y) => (y === 0 ? 'n' : y === 9 ? 's' : x === 0 ? 'w' : x === 14 ? 'e' : null);
  const cheb = (ax, ay, bx, by) => Math.max(Math.abs(ax - bx), Math.abs(ay - by));
  const TRANSITION = 20;
  const ITEM_POOL = (tier) => Object.values(AD.ITEMS).filter((i) => i.tier === tier).map((i) => i.id);

  function Run(o) {
    o = o || {};
    this.heroId = o.hero || 'abarax';
    this.difficulty = o.difficulty || 2;
    this.seed = o.seed === undefined ? AD.rng.newSeed() : o.seed;
    this.meta = o.meta || null;
    this.events = new AD.Bus();
    this.depth = 1; this.cleared = 0; this.frames = 0; this.minutes = 0;
    this.coins = 0; this.keys = 0; this.bombs = 1; this.petals = 0; this.kills = 0;
    this.paused = false; this.over = null; this.god = false;
    this.metMinis = new Set();
    this.banner = null; this.transition = null; this.gate = null;
    this.quick = [null, null];
    if (AD.cons) { AD.cons.init(this); AD.cons.install(this); }
    this.startDepth(1, true);
  }
  AD.Run = Run;
  const P = Run.prototype;

  P.useQuick = function (pad) { if (AD.cons) AD.cons.tick(this, pad); };
  P.coef = function () { return AD.stat.coefficient(this.difficulty, this.minutes, this.cleared); };
  P.region = function () { return AD.regionAt(this.depth); };

  P.startDepth = function (depth, first) {
    this.depth = depth;
    this.streams = AD.rng.streams(this.seed, depth);
    this.floor = AD.gen.floor(depth, this.streams.layout);
    this.rooms = new Map();
    this.roomState = new Map();
    for (const k of this.floor.rooms.keys()) this.roomState.set(k, { state: 'unvisited', taken: new Set() });
    this.gate = null;
    this.events.emit('depthStart', { depth, first: !!first });
    const S = this.floor.rooms.get(this.floor.start);
    this.enterRoom(S.key, null);
  };

  // ---------------------------------------------------------------- rooms
  P.liveRoom = function (key) {
    let room = this.rooms.get(key);
    if (room) return room;
    const info = this.floor.rooms.get(key);
    // each room draws its layout from a stream of its own, so the order rooms are visited never changes them
    const r = AD.rng.make(AD.rng.hash(this.seed + ':' + this.depth + ':room:' + key));
    const layout = AD.gen.room(this.floor, key, this.region().id, r);
    room = AD.room.build(this, key, layout, info);
    this.rooms.set(key, room);
    return room;
  };

  P.enterRoom = function (key, side) {
    const old = this.room;
    const h = this.hero;
    if (old && h) { old.grid.release(h.id, h.x, h.y); if (h.move) old.grid.release(h.id, h.move.x1, h.move.y1); old.bodies.delete(h.id); }
    const room = key === 'arena' ? this.arena : this.liveRoom(key);
    this.room = room;
    room.hero = null;
    let [x, y] = side ? MOUTH()[side] : [7, 4];
    if (!room.grid.passable(x, y, 'walk')) [x, y] = [7, 8];
    if (room.grid.bodyAt(x, y)) {
      const free = AD.director.spawnTiles({ grid: room.grid, hero: null }, 1, AD.rng.make(1));
      if (free[0]) [x, y] = free[0];
    }
    room.entry = [x, y];
    if (!h) this.hero = AD.hero.make(room, this.heroId, this, x, y);
    else AD.hero.enter(room, h, x, y);
    room.hero = this.hero;
    if (side) this.hero.facing = { n: [0, 1], s: [0, -1], w: [1, 0], e: [-1, 0] }[side];
    const st = this.roomState.get(key);
    if (st && st.state === 'unvisited') this.firstVisit(room, st);
    this.events.emit('enterRoom', { room, sealed: room.sealed, key });
    return room;
  };

  P.firstVisit = function (room, st) {
    st.state = 'entered';
    const t = room.type;
    if (t === 'combat') {
      room.sealed = true;
      for (const [d, [x, y]] of Object.entries(AD.gen.DOOR_AT)) if (room.grid.at(x, y) === 'D') room.grid.set(x, y, '=');
      const waves = AD.director.plan(this.streams.combat, this.region().id, this.depth, AD.director.budget(this.coef(), 'room'));
      room.level = AD.stat.enemyLevel(this.coef());
      // a quarter of the rooms are found asleep (Pixel Dungeon): the first wave is already there
      if (waves.length && this.streams.combat() < 0.25) {
        const first = waves.shift();
        const tiles = AD.director.spawnTiles(room, first.length, this.streams.combat);
        first.forEach((s, i) => { if (tiles[i]) AD.ai.spawn(room, s.id, tiles[i][0], tiles[i][1], { level: room.level, elite: s.elite, eliteTier: s.eliteTier, asleep: true }); });
        AD.director.begin(room, [[]].concat(waves));
      } else AD.director.begin(room, waves);
    } else {
      st.state = 'cleared';
      if (t === 'rest') {
        const p = this.findTile(room, 'P');
        if (p && !st.taken.has('lore')) AD.room.drop(room, p[0], p[1], { kind: 'lore', depth: this.depth, id: 'lore' });
      }
    }
    // the key for a locked room on this floor
    for (const k of this.floor.keys) if (k.room === room.key) room.keyHere = true;
    if (room.keyHere && t !== 'combat' && !st.taken.has('key')) AD.room.drop(room, 7, 4, { kind: 'key', id: 'key' });
  };

  P.findTile = function (room, ch) {
    for (let y = 0; y < 10; y++) for (let x = 0; x < 15; x++) if (room.grid.at(x, y) === ch) return [x, y];
    return null;
  };

  // listeners every room gets from the run
  P.install = function (room) {
    const run = this;
    room.bus.on('kill', (p) => {
      const m = p.tgt;
      if (m === run.hero) return;
      if (m.kind !== 'monster' && m.kind !== 'boss') return;
      run.kills++;
      const cost = (m.cost || 0) * (m.eliteTier === 2 ? 36 : m.eliteTier === 1 ? 6 : 1);
      if (cost) {
        AD.room.drop(room, m.x, m.y, { kind: 'coins', amount: AD.stat.coinsFor(cost, run.coef()) });
        if (run.hero && !run.hero.dead) AD.hero.gainXp(run.hero, AD.stat.xpFor(cost));
      }
      if (run.gate && m === run.gate.guardian) run.guardianDown(room, m);
      if (m === run.bossBody) run.bossDown(room, m);
      // now and then a monster leaves something behind
      if (AD.cons && run.streams.loot() < 0.03) AD.room.drop(room, m.x, m.y, AD.cons.randomDrop(run, run.streams.loot));
      room.corpses.push({ look: m.look, defId: m.defId, x: m.fx, y: m.fy, facing: m.facing, t: 0, elite: m.elite });
      AD.ent.remove(room, m);
    }, 90);
    // brittle armour lets more through
    room.bus.on('takeMods', (p) => { if (p.tgt === run.hero && run.hero.curse === 'brittle') p.mul *= 1.1; });
    // a test and debug hook: nothing kills the hero
    room.bus.on('lethal', (p) => { if (run.god && p.tgt === run.hero) { p.cancel = true; p.tgt.hp = p.tgt.mhp; } }, 1);
  };

  // ---------------------------------------------------------------- the step
  P.tick = function (pad) {
    if (this.paused || this.over) return;
    if (this.transition) { if (--this.transition.t <= 0) { const t = this.transition; this.transition = null; this.enterRoom(t.to, t.side); } return; }
    const room = this.room, h = this.hero;
    room.frame++;
    this.frames++;
    this.minutes = this.frames / 3600;
    room.level = AD.stat.enemyLevel(this.coef());
    if (this.banner && --this.banner.t <= 0) this.banner = null;
    pad = this.interact(room, h, pad);
    AD.hero.control(room, h, pad);
    if (this.useQuick) this.useQuick(pad);
    for (const e of [...room.bodies.values()]) {
      if (e.kind === 'monster') AD.ai.think(room, e);
      else if (e.kind === 'boss' && AD.boss) AD.boss.think(room, e);
    }
    AD.combat.tick(room);
    AD.ai.tickProjectiles(room);
    for (const e of [...room.bodies.values()]) AD.ent.tick(room, e);
    for (const e of [...room.bodies.values()]) AD.status.tick(room, e);
    AD.items.tick(room, h);
    AD.world.tick(room);
    AD.director.tick(room);
    AD.director.tickElites(room);
    this.tickPickups(room, h);
    for (let i = room.corpses.length - 1; i >= 0; i--) if (++room.corpses[i].t > 40) room.corpses.splice(i, 1);
    if (room.sealed && AD.director.done(room)) this.clearRoom(room);
    if (this.gate) this.tickGate(room, h);
    if (h.dead && !this.over) this.end(false, h.lastHitBy ? (h.lastHitBy.def ? h.lastHitBy.def.n : h.lastHitBy.n || 'the Seams') : 'the Seams');
  };

  // A pressed facing a chest or the gate opens it instead of swinging; walking into a locked door
  // with a key opens it
  P.interact = function (room, h, pad) {
    if (h.dead || h.busy || h.move) return pad;
    const fx = h.x + h.facing[0], fy = h.y + h.facing[1];
    const ahead = room.grid.at(fx, fy);
    if (pad.a && ahead === 'C') { this.openChest(room, fx, fy); return Object.assign({}, pad, { a: false }); }
    if (pad.a && (ahead === 'G' || room.grid.at(h.x, h.y) === 'G')) {
      if (this.gate && this.gate.open) this.enterGate(); else this.touchGate();
      return Object.assign({}, pad, { a: false });
    }
    if (pad.sx || pad.sy) {
      const lx = h.x + (pad.sx || 0), ly = h.y + (pad.sy || 0);
      if (room.grid.at(lx, ly) === '+' && this.keys > 0) this.unlock(room, lx, ly);
    }
    return pad;
  };

  P.unlock = function (room, x, y) {
    this.keys--;
    room.grid.set(x, y, 'D');
    const side = SIDE_OF(x, y), info = room.info;
    if (side && info.doors[side] === 'locked') {
      info.doors[side] = 'open';
      const [dx, dy] = AD.gen.DIRS[side];
      const nk = (info.gx + dx) + ',' + (info.gy + dy);
      const N = this.floor.rooms.get(nk);
      if (N) N.doors[AD.gen.OPP[side]] = 'open';
      const live = this.rooms.get(nk);
      if (live) { const [ox, oy] = AD.gen.DOOR_AT[AD.gen.OPP[side]]; live.grid.set(ox, oy, 'D'); }
    }
    room.bus.emit('unlock', { x, y });
  };

  P.rollItem = function (r, odds) {
    const x = r();
    let acc = 0;
    for (const [tier, p] of odds) { acc += p; if (x < acc) { const pool = ITEM_POOL(tier); return AD.rng.pick(r, pool); } }
    return AD.rng.pick(r, ITEM_POOL(odds[0][0]));
  };

  P.openChest = function (room, x, y) {
    const k = x + ',' + y;
    if (room.chests[k]) return false;
    const big = room.type === 'secret';
    const lockedTreasure = room.type === 'treasure' && this.floor.keys.some((q) => q.lock === room.key);
    const cost = lockedTreasure ? 0 : AD.stat.chestCost(big ? 50 : 25, this.coef());
    if (this.coins < cost) { room.bus.emit('cantAfford', { cost }); return false; }
    this.coins -= cost;
    room.chests[k] = true;
    const r = this.streams.loot;
    const st = this.roomState.get(room.key);
    if (st) st.taken.add('chest:' + k);
    let drop;
    if (big && r() < 0.5) drop = { kind: 'item', item: AD.rng.pick(r, ITEM_POOL('equipment')) };
    else if (big) drop = { kind: 'item', item: this.rollItem(r, [['uncommon', 0.8], ['legendary', 0.2]]) };
    else drop = { kind: 'item', item: this.rollItem(r, [['common', 0.79], ['uncommon', 0.2], ['legendary', 0.01]]) };
    const h = this.hero;
    AD.room.drop(room, h.x, h.y, drop);
    room.bus.emit('chest', { x, y, cost, big });
    return true;
  };

  P.clearRoom = function (room) {
    room.sealed = false;
    for (const [x, y] of Object.values(AD.gen.DOOR_AT)) if (room.grid.at(x, y) === '=') room.grid.set(x, y, 'D');
    const st = this.roomState.get(room.key);
    if (st) st.state = 'cleared';
    room.bus.emit('roomClear', { room });
    const r = this.streams.loot;
    const roll = r();
    if (roll < 0.3) AD.room.drop(room, 7, 4, { kind: 'coins', amount: AD.stat.coinsFor(10, this.coef()) });
    else if (roll < 0.4) {
      if (AD.cons && AD.cons.randomDrop && r() < 0.5) AD.room.drop(room, 7, 4, AD.cons.randomDrop(this, r));
      else AD.room.drop(room, 7, 4, { kind: 'key' });
    }
    if (room.keyHere && st && !st.taken.has('key')) AD.room.drop(room, 7, 5, { kind: 'key', id: 'key' });
  };

  // ---------------------------------------------------------------- pickups
  P.tickPickups = function (room, h) {
    if (h.dead) return;
    for (let i = room.pickups.length - 1; i >= 0; i--) {
      const p = room.pickups[i];
      p.t++;
      if (p.kind === 'coins' && Math.max(Math.abs(p.fx - h.fx), Math.abs(p.fy - h.fy)) <= 2) {
        const dx = h.fx - p.fx, dy = h.fy - p.fy, d = Math.hypot(dx, dy) || 1;
        const s = Math.min(d, 0.15);
        p.fx += (dx / d) * s; p.fy += (dy / d) * s;
      }
      const onIt = p.kind === 'coins' ? Math.hypot(p.fx - h.fx, p.fy - h.fy) < 0.5 : Math.round(h.fx) === p.x && Math.round(h.fy) === p.y;
      if (!onIt || p.t < 10) continue;
      if (!this.collect(room, h, p)) continue;
      room.pickups.splice(i, 1);
      const st = this.roomState.get(room.key);
      if (st && p.id) st.taken.add(p.id.indexOf('#') < 0 ? p.id : p.id);
      room.bus.emit('pickup', { p });
    }
  };
  P.collect = function (room, h, p) {
    switch (p.kind) {
      case 'coins': this.coins += p.amount; return true;
      case 'heart': AD.items.heal(room, h, h.mhp * 0.1); return true;
      case 'heal': AD.items.heal(room, h, p.amount); return true;
      case 'key': if (this.keys >= 9) return false; this.keys++; return true;
      case 'bomb': if (this.bombs >= 9) return false; this.bombs++; return true;
      case 'petal': this.petals += p.amount || 1; return true;
      case 'lore': this.lore = (this.lore || []).concat([p.depth]); this.banner = { text: AD.LORE && AD.LORE.page ? AD.LORE.page(p.depth).title : 'A page', sub: 'Added to the Book', t: 120 }; return true;
      case 'item': {
        AD.items.give(this, h, p.item);
        const d = AD.ITEMS[p.item];
        this.banner = { text: d.n, sub: d.desc, t: 90, tier: d.tier, item: p.item };
        this.found = (this.found || []).concat([p.item]);
        return true;
      }
      default: return AD.cons && AD.cons.collect ? AD.cons.collect(this, room, h, p) : false;
    }
  };
  P.dropEquipment = function (id) { const h = this.hero; AD.room.drop(this.room, h.x, h.y, { kind: 'item', item: id }); };

  // ---------------------------------------------------------------- arriving on a tile
  P.arrive = function (room, e) {
    AD.world.arrive(room, e);
    if (e !== this.hero || e.dead) return;
    const ch = room.grid.at(e.x, e.y);
    const side = SIDE_OF(e.x, e.y);
    if (ch === 'D' && side) {
      const info = room.info, [dx, dy] = AD.gen.DIRS[side];
      const to = room.key === 'arena' ? null : (info.gx + dx) + ',' + (info.gy + dy);
      if (to && this.floor.rooms.has(to)) this.transition = { to, side: AD.gen.OPP[side], dir: side, t: TRANSITION };
    }
    if (ch === 'G') { if (this.gate && this.gate.open) this.enterGate(); else this.touchGate(); }
  };

  // ---------------------------------------------------------------- the Seam Gate
  P.gateTile = function () { return this.findTile(this.room, 'G'); };
  P.place = function (x, y) {
    const h = this.hero, g = this.room.grid;
    g.release(h.id, h.x, h.y);
    if (h.move) g.release(h.id, h.move.x1, h.move.y1);
    h.move = null; h.pushLeft = 0;
    h.x = x; h.y = y; h.fx = x; h.fy = y;
    g.claim(h.id, x, y);
  };
  P.touchGate = function () {
    const room = this.room;
    if (room.type !== 'exit' || this.gate) return false;
    const [gx, gy] = this.gateTile();
    const R = this.region().R;
    const fresh = R.minis.filter((m) => !this.metMinis.has(m));
    const id = AD.rng.pick(this.streams.combat, fresh.length ? fresh : R.minis);
    this.metMinis.add(id);
    const spot = AD.director.spawnTiles(room, 1, this.streams.combat)[0] || [gx, Math.max(1, gy - 3)];
    const level = AD.stat.enemyLevel(this.coef());
    const guardian = AD.boss && AD.BOSSES && AD.BOSSES[id]
      ? AD.boss.spawn(room, id, spot[0], spot[1], { level })
      : AD.ai.spawn(room, 'tough', spot[0], spot[1], { level, elite: 'thorned', eliteTier: 1 });
    guardian.guardian = true;
    room.waves = []; room.waveIdx = 0; room.pending = []; room.waveCost = 0;
    this.gate = { charge: 0, f: 0, guardian, open: false, waveT: 480, tile: [gx, gy], id };
    room.bus.emit('gateStart', { gate: this.gate });
    return true;
  };
  P.tickGate = function (room, h) {
    const g = this.gate;
    if (g.open) return;
    // whole frames, so a full charge is exactly 1
    if (!h.dead && cheb(h.x, h.y, g.tile[0], g.tile[1]) <= 3 && g.f < 1800) { g.f++; g.charge = g.f / 1800; }
    if (g.charge < 1 && --g.waveT <= 0) {
      g.waveT = 480;
      const w = AD.director.plan(this.streams.combat, this.region().id, this.depth, AD.director.budget(this.coef(), 'gate'))[0] || [];
      room.pending.push(...w);
    }
    if (g.charge >= 1 && (g.guardian.dead || g.guardian.gone)) {
      g.open = true;
      room.pending = [];
      room.bus.emit('gateCharged', { gate: g });
    }
  };
  P.guardianDown = function (room, m) {
    const r = this.streams.loot;
    AD.room.drop(room, m.x, m.y, { kind: 'item', item: this.rollItem(r, [['uncommon', 0.9], ['legendary', 0.1]]) });
    AD.room.drop(room, m.x, m.y, { kind: 'petal', amount: 3 });
  };
  P.enterGate = function () {
    if (!this.gate || !this.gate.open) return false;
    if (this.floor.bossDepth) { this.enterArena(); return true; }
    this.nextDepth();
    return true;
  };
  P.nextDepth = function () {
    this.cleared++;
    this.petals += 1;
    this.hero.getUpUsed = false;
    this.startDepth(this.depth + 1);
  };

  // ---------------------------------------------------------------- the boss
  P.enterArena = function () {
    const R = this.region();
    const layout = AD.gen.arena(R.id, this.streams.layout);
    const info = { type: 'boss', doors: { n: null, s: null, w: null, e: null }, gx: -1, gy: -1 };
    this.arena = AD.room.build(this, 'arena', layout, info);
    this.gate = null;
    this.enterRoom('arena', 's');
    const level = AD.stat.enemyLevel(this.coef());
    const room = this.arena;
    this.bossBody = AD.boss && AD.BOSSES && AD.BOSSES[R.R.boss]
      ? AD.boss.spawn(room, R.R.boss, 7, 3, { level, boss: true })
      : AD.ai.spawn(room, 'knuckle', 7, 3, { level, hp: 2800 });
    room.bus.emit('bossIn', { boss: this.bossBody });
  };
  P.bossDown = function (room, b) {
    if (AD.boss && AD.boss.reward) AD.boss.reward(this, b);
    else this.petals += 10;
    this.end(true, null);
  };

  P.end = function (won, by) {
    if (this.over) return;
    this.over = { won, by, depth: this.depth, minutes: this.minutes, kills: this.kills, petals: this.petals, found: this.found || [] };
    this.events.emit(won ? 'victory' : 'death', { run: this });
  };

  // ---------------------------------------------------------------- a hash of the state, for replays
  P.hash = function () {
    const room = this.room, h = this.hero;
    const bodies = [...room.bodies.values()].sort((a, b) => a.id - b.id).map((b) => [b.defId || b.kind, b.x, b.y, Math.round(b.hp * 100)]);
    const s = JSON.stringify([this.depth, room.key, this.frames, h.x, h.y, Math.round(h.hp * 100), h.level, Math.round(h.xp * 100), this.coins, this.keys, bodies, room.pickups.length,
      this.streams.layout.state(), this.streams.combat.state(), this.streams.loot.state()]);
    return AD.rng.hash(s).toString(16);
  };
})(window.AD);
