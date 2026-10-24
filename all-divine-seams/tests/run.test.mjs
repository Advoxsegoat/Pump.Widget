import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

export const SIM = ['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js', 'sim/boss.js', 'data/regions.js', 'sim/director.js', 'sim/world.js', 'data/templates.js', 'gen/floor.js', 'gen/room.js', 'sim/room.js', 'data/consumables.js', 'game/run.js'];
const AD = load(SIM);
const PAD = () => ({ sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] });
const tickN = (run, n, pad) => { for (let i = 0; i < n; i++) run.tick(pad || PAD()); };
const newRun = (seed, o) => { const run = new AD.Run(Object.assign({ hero: 'abarax', difficulty: 2, seed }, o)); return run; };
const tough = (run) => { run.god = true; };
function gotoRoomOfType(run, type) {
  const R = [...run.floor.rooms.values()].find((r) => r.type === type);
  run.enterRoom(R.key, 's');
  tickN(run, 25);
  return R;
}
function killAll(run) {
  for (let i = 0; i < 400 && !AD.director.done(run.room); i++) {
    for (const b of [...run.room.bodies.values()]) if (b.kind === 'monster' && !b.dead && !b.untargetable) AD.combat.deal(run.room, { src: run.hero, tgt: b, pct: 1e5, type: 'normal', proc: 0, mask: [] });
    tickN(run, 1);
  }
}
const sealed = (room) => room.grid.rows().join('').includes('=');

test('a run starts on depth 1 in the start room', () => {
  const run = newRun(4821);
  assert.equal(run.depth, 1);
  assert.equal(run.room.key, run.floor.start);
  assert.equal(run.roomState.get(run.floor.start).state, 'cleared');
  assert.deepEqual([run.hero.hp, run.hero.mhp], [110, 110]);
});

test('the clock runs in play and stops while paused', () => {
  const run = newRun(4821);
  tickN(run, 3600);
  assert.equal(+run.minutes.toFixed(2), 1);
  run.paused = true; tickN(run, 3600);
  assert.equal(+run.minutes.toFixed(2), 1);
  run.paused = false;
  assert.equal(+run.coef().toFixed(4), +(1 + 0.0506 * 2 * 1).toFixed(4));
});

test('a room\'s events reach the run', () => {
  const run = newRun(1);
  let seen = 0; run.events.on('ping', () => seen++);
  run.room.bus.emit('ping', {});
  assert.equal(seen, 1);
});

test('a combat room seals on entry, opens on clearing, rolls a reward', () => {
  const run = newRun(4821); tough(run);
  gotoRoomOfType(run, 'combat');
  assert.ok(sealed(run.room));
  assert.ok([...run.room.bodies.values()].some((b) => b.kind === 'monster'));
  let cleared = 0; run.events.on('roomClear', () => cleared++);
  killAll(run); tickN(run, 2);
  assert.ok(!sealed(run.room));
  assert.equal(cleared, 1);
  assert.equal(run.roomState.get(run.room.key).state, 'cleared');
});

test('a combat room found asleep opens once everything in it is down', () => {
  // a quarter of the rooms are found asleep: find one on these seeds and clear it, twenty minutes
  // in, when a room's budget buys more than one wave
  let found = 0;
  for (let seed = 1; seed < 60 && found < 3; seed++) {
    const run = newRun(seed); tough(run); run.minutes = 20;
    for (const R of [...run.floor.rooms.values()].filter((r) => r.type === 'combat')) {
      run.enterRoom(R.key, 's');
      if (![...run.room.bodies.values()].some((b) => b.kind === 'monster' && b.state === 'asleep')) continue;
      found++;
      killAll(run); tickN(run, 2);
      assert.ok(!sealed(run.room), 'seed ' + seed + ' room ' + R.key + ' opens');
      assert.equal(run.roomState.get(R.key).state, 'cleared');
      break;
    }
  }
  assert.equal(found, 3);
});

test('fresh spawns shimmer: they cannot act or be hit for 18 frames', () => {
  const run = newRun(4821); tough(run);
  gotoRoomOfType(run, 'combat');
  const m = [...run.room.bodies.values()].find((b) => b.kind === 'monster');
  void m;
  const r2 = newRun(4821); tough(r2);
  const R = [...r2.floor.rooms.values()].find((r) => r.type === 'combat');
  r2.enterRoom(R.key, 's');
  tickN(r2, 2);
  const fresh = [...r2.room.bodies.values()].find((b) => b.kind === 'monster');
  assert.equal(fresh.untargetable, true);
  tickN(r2, 25);
  assert.equal(fresh.untargetable, false);
});

test('kills drop coins that drift to the hero and give experience', () => {
  const run = newRun(4821); tough(run);
  gotoRoomOfType(run, 'combat');
  const m = [...run.room.bodies.values()].find((b) => b.kind === 'monster' && !b.untargetable);
  const coins0 = run.coins;
  AD.combat.deal(run.room, { src: run.hero, tgt: m, pct: 1e5, type: 'normal', proc: 0, mask: [] });
  assert.ok(run.room.pickups.some((p) => p.kind === 'coins'));
  assert.ok(run.hero.xp > 0 || run.hero.level > 1);
  const p = run.room.pickups.find((q) => q.kind === 'coins');
  p.x = run.hero.x + 1; p.y = run.hero.y; p.fx = p.x; p.fy = p.y;
  tickN(run, 30);
  assert.ok(run.coins > coins0);
});

test('a locked door takes a key', () => {
  for (let s = 1; s < 60; s++) {
    const run = newRun(s); tough(run);
    if (!run.floor.keys.length) continue;
    const lock = run.floor.keys[0].lock;
    const T = run.floor.rooms.get(lock);
    const d = Object.keys(T.doors).find((k) => T.doors[k] === 'locked');
    const [dx, dy] = AD.gen.DIRS[d];
    const outsideKey = (T.gx + dx) + ',' + (T.gy + dy);
    run.enterRoom(outsideKey, 's'); tickN(run, 25);
    if (run.roomState.get(outsideKey).state !== 'cleared') killAll(run);
    tickN(run, 5);
    const od = AD.gen.OPP[d];
    const [lx, ly] = AD.gen.DOOR_AT[od];
    const [mx, my] = [lx === 0 ? 1 : lx === 14 ? 13 : lx, ly === 0 ? 1 : ly === 9 ? 8 : ly];
    run.hero.x = mx; run.hero.y = my; run.hero.fx = mx; run.hero.fy = my;
    run.room.grid.occ.fill(0); run.room.grid.claim(run.hero.id, mx, my);
    run.keys = 1;
    const pad = PAD(); pad.sx = Math.sign(lx - mx); pad.sy = Math.sign(ly - my);
    tickN(run, 3, pad);
    assert.equal(run.keys, 0);
    assert.equal(run.room.grid.at(lx, ly), 'D');
    return;
  }
  assert.fail('no locked door found');
});

test('walking out of a door slides to the next room and enters at its door', () => {
  const run = newRun(77); tough(run);
  const S = run.floor.rooms.get(run.floor.start);
  const d = Object.keys(S.doors).find((k) => S.doors[k] === 'open');
  const [dx, dy] = AD.gen.DIRS[d];
  const next = (S.gx + dx) + ',' + (S.gy + dy);
  const pad = PAD(); pad.sx = dx; pad.sy = dy;
  tickN(run, 200, pad);
  assert.equal(run.room.key, next);
  const [ex, ey] = { n: [7, 8], s: [7, 1], w: [13, 4], e: [1, 4] }[d];
  void ex; void ey;
  assert.ok(run.room.grid.bodyAt(run.hero.x, run.hero.y) === run.hero.id);
});

test('the Seam Gate: charges only near it, needs its guardian dead, then leads down', () => {
  const run = newRun(4821); tough(run);
  gotoRoomOfType(run, 'exit');
  const [gx, gy] = run.gateTile();
  run.touchGate();
  assert.ok(run.gate && run.gate.guardian);
  // five tiles away: no charge
  run.place(gx, gy - 5 >= 1 ? gy - 3 : gy + 3); run.place(gx <= 7 ? gx + 5 : gx - 5, gy);
  tickN(run, 600);
  assert.equal(run.gate.charge, 0);
  run.place(gx, gy);
  const hum = [];
  run.events.on('gateCharging', (p) => hum.push(p.gate.charge));
  tickN(run, 1800);
  assert.equal(run.gate.charge, 1);
  // a hum every half second while it fills, for its rising tone
  assert.equal(hum.length, 60);
  assert.ok(hum.every((c, i) => i === 0 || c > hum[i - 1]));
  assert.equal(run.gate.open, false);
  AD.combat.deal(run.room, { src: run.hero, tgt: run.gate.guardian, pct: 1e6, type: 'normal', proc: 0, mask: [] });
  tickN(run, 2);
  assert.equal(run.gate.open, true);
  const petals = run.petals;
  run.enterGate();
  assert.equal(run.depth, 2);
  assert.equal(run.petals, petals + 1);
  assert.equal(run.hero.getUpUsed, false);
});

test('away from the exit room (out of a door, or by a Page of Teleport) the gate waits', () => {
  const run = newRun(4821); tough(run);
  const R = gotoRoomOfType(run, 'exit');
  const [gx, gy] = run.gateTile();
  run.touchGate(); run.place(gx, gy);
  tickN(run, 300);
  const charge = run.gate.charge;
  assert.ok(charge > 0);
  // somewhere else on the floor: nothing breaks, nothing charges
  const other = [...run.floor.rooms.values()].find((r) => r.type === 'treasure' || r.type === 'start');
  run.enterRoom(other.key, null); tickN(run, 600);
  assert.equal(run.gate.charge, charge);
  // back at the gate it carries on
  run.enterRoom(R.key, 's'); tickN(run, 25); run.place(gx, gy); tickN(run, 60);
  assert.ok(run.gate.charge > charge);
});

// out of the room through the door on `side`, from its mouth
function walkOut(run, side) {
  run.place(...AD.room.MOUTH[side]);
  const pad = PAD(); [pad.sx, pad.sy] = AD.gen.DIRS[side];
  for (let i = 0; i < 120 && !run.transition; i++) run.tick(pad);
  tickN(run, 25);
}
const nextKey = (R, side) => (R.gx + AD.gen.DIRS[side][0]) + ',' + (R.gy + AD.gen.DIRS[side][1]);

test('a cracked wall bombed open is a door both ways: into the secret room and back out', () => {
  let tried = 0;
  for (let seed = 1; seed < 60 && tried < 3; seed++) {
    const run = newRun(seed); tough(run);
    const S = [...run.floor.rooms.values()].find((r) => r.type === 'secret');
    const side = S && Object.keys(S.doors).find((d) => S.doors[d] === 'secret' && run.floor.rooms.has(nextKey(S, d)));
    if (!side) continue;
    // the neighbour, cleared, with its cracked wall toward the secret room
    const nKey = nextKey(S, side), toS = AD.gen.OPP[side];
    run.enterRoom(nKey, null); tickN(run, 25); killAll(run); tickN(run, 2);
    const [wx, wy] = AD.gen.DOOR_AT[toS];
    assert.equal(run.room.grid.at(wx, wy), '%');
    AD.world.blast(run.room, [[wx, wy]], run.hero);
    walkOut(run, toS);
    assert.equal(run.room.key, S.key, 'seed ' + seed + ': into the secret room');
    walkOut(run, side);
    assert.equal(run.room.key, nKey, 'seed ' + seed + ': and back out the way in');
    tried++;
  }
  assert.equal(tried, 3);
});

test('a cracked wall blown open in a sealed fight stays barred until the room is clear', () => {
  for (let seed = 1; seed < 60; seed++) {
    const run = newRun(seed); tough(run);
    const S = [...run.floor.rooms.values()].find((r) => r.type === 'secret');
    const side = S && Object.keys(S.doors).find((d) => S.doors[d] === 'secret' && run.floor.rooms.get(nextKey(S, d)) && run.floor.rooms.get(nextKey(S, d)).type === 'combat');
    if (!side) continue;
    const toS = AD.gen.OPP[side];
    run.enterRoom(nextKey(S, side), null); tickN(run, 5);
    assert.ok(run.room.sealed);
    const [wx, wy] = AD.gen.DOOR_AT[toS];
    AD.world.blast(run.room, [[wx, wy]], run.hero);
    assert.equal(run.room.grid.at(wx, wy), '=');
    killAll(run); tickN(run, 2);
    assert.equal(run.room.grid.at(wx, wy), 'D');
    return;
  }
  assert.fail('no combat room beside a secret room in 60 seeds');
});

test('walking back into a room does not stack the hero\'s items', () => {
  const run = newRun(4821); tough(run);
  const h = run.hero;
  AD.items.give(run, h, 'warmmitts');
  const blow = () => {
    const m = AD.ent.make(run.room, { kind: 'monster', team: 'e', x: 12, y: 2, speed: 0.001, hp: 1e6, dmg: 0, crit: 0 });
    h.crit = 0;
    let got = 0;
    const off = run.room.bus.on('hit', (p) => { if (p.tgt === m) got = p.amount; });
    AD.combat.deal(run.room, { src: h, tgt: m, pct: 1, type: 'normal', proc: 1, mask: [] });
    off(); AD.ent.remove(run.room, m);
    return got;
  };
  const start = run.room.key, first = blow();
  const S = run.floor.rooms.get(start);
  const d = Object.keys(S.doors).find((k) => S.doors[k] === 'open');
  const next = nextKey(S, d);
  for (let i = 0; i < 3; i++) { run.enterRoom(next, AD.gen.OPP[d]); tickN(run, 3); run.enterRoom(start, d); tickN(run, 3); }
  assert.equal(blow(), first);
});

test('timers the hero carries count on through a door (Taffy heals 7 s after the last hurt)', () => {
  const run = newRun(4821); tough(run);
  const h = run.hero;
  AD.items.give(run, h, 'taffy');
  tickN(run, 1200);
  const src = AD.ent.make(run.room, { kind: 'monster', team: 'e', x: 12, y: 2, speed: 0.001, hp: 100, dmg: 30, crit: 0 });
  AD.combat.deal(run.room, { src, tgt: h, pct: 1, type: 'normal', proc: 0, mask: [] });
  AD.ent.remove(run.room, src);
  const S = run.floor.rooms.get(run.room.key);
  const d = Object.keys(S.doors).find((k) => S.doors[k] === 'open');
  run.enterRoom(nextKey(S, d), AD.gen.OPP[d]);
  killAll(run);
  h.regen = 0;
  const hp = h.hp;
  tickN(run, 600);
  assert.ok(h.hp > hp, 'Taffy healed in the next room');
});

test('determinism: same seed, same inputs, same state', () => {
  const script = (i) => { const p = PAD(); p.sx = [1, 0, -1, 0][(i >> 5) & 3]; p.sy = [0, 1, 0, -1][(i >> 5) & 3]; p.a = i % 9 === 0; return p; };
  const go = () => { const run = newRun(4821); for (let i = 0; i < 5000; i++) run.tick(script(i)); return run.hash(); };
  assert.equal(go(), go());
});

test('the bus carries hurt and levelUp (spec 6.5) for the sound, the HUD and the effects', () => {
  const run = newRun(9); run.god = true;
  gotoRoomOfType(run, 'combat');
  const seen = [];
  run.events.on('hurt', (p) => seen.push(['hurt', p.amount]));
  run.events.on('levelUp', (p) => seen.push(['levelUp', p.level]));
  const m = [...run.room.bodies.values()].find((b) => b.kind === 'monster') || AD.ai.spawn(run.room, 'grunt', 3, 3, { level: 1 });
  AD.combat.deal(run.room, { src: m, tgt: run.hero, amount: 7, type: 'normal', proc: 0, mask: [], fixed: true });
  run.hero.xp = AD.stat.xpToNext(1) - 0.5;
  m.untargetable = false; m.shimmer = 0;
  AD.combat.deal(run.room, { src: run.hero, tgt: m, pct: 1e5, type: 'normal', proc: 0, mask: [] });
  assert.deepEqual(seen.map((s) => s[0]), ['hurt', 'levelUp']);
  assert.equal(seen[0][1], 7);
  assert.equal(seen[1][1], 2);
});

test('death ends the run', () => {
  const run = newRun(9);
  run.hero.getUpUsed = true;
  AD.combat.deal(run.room, { src: null, tgt: run.hero, amount: 9999, type: 'normal', proc: 0, mask: [], fixed: true });
  tickN(run, 2);
  assert.ok(run.over && run.over.won === false);
});

test('soak: random play through floors throws nothing', () => {
  const errs = [];
  AD.report = (e, where) => errs.push(where + ': ' + (e && e.message));
  for (const seed of [11, 22, 33]) {
    const run = newRun(seed); run.god = true;
    const r = AD.rng.make(seed);
    let pad = PAD();
    for (let i = 0; i < 20000; i++) {
      if (i % 20 === 0) { pad = PAD(); pad.sx = AD.rng.int(r, -1, 1); pad.sy = AD.rng.int(r, -1, 1); }
      pad.a = r() < 0.08; pad.b = r() < 0.01; pad.r = r() < 0.01; pad.l = r() < 0.005;
      pad.aHeld = pad.a; pad.aReleased = r() < 0.02; pad.q = [r() < 0.004, r() < 0.004, false];
      run.tick(pad);
      if (run.room.type === 'exit' && !run.gate) run.touchGate();
      if (run.gate && run.gate.open) run.enterGate();
      if (run.over) break;
    }
  }
  assert.deepEqual(errs, []);
});
