import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, memoryStorage } from './load.mjs';

const SIM = ['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js', 'sim/boss.js', 'data/regions.js', 'sim/director.js', 'sim/world.js', 'data/templates.js', 'gen/floor.js', 'gen/room.js', 'sim/room.js', 'data/consumables.js', 'game/run.js', 'data/lore.js', 'game/meta.js', 'game/save.js'];
const storage = memoryStorage();
const AD = load(SIM, { localStorage: storage });
const PAD = () => ({ sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] });
const tickN = (run, n, pad) => { for (let i = 0; i < n; i++) run.tick(typeof pad === 'function' ? pad(run.frames) : pad || PAD()); };
const newRun = (seed) => { const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: seed || 4821, meta: AD.meta }); run.god = true; return run; };
const fresh = () => { storage.full(false); for (const k of storage.keys()) storage.removeItem(k); AD.save.warned = false; AD.save.problem = null; };
// the first open door out of a room, and the room beyond it
function doorOut(run) {
  const S = run.floor.rooms.get(run.room.key);
  const d = Object.keys(S.doors).find((k) => S.doors[k] === 'open');
  return { d, key: (S.gx + AD.gen.DIRS[d][0]) + ',' + (S.gy + AD.gen.DIRS[d][1]) };
}
const walkThrough = (run, d) => { const pad = PAD(); [pad.sx, pad.sy] = AD.gen.DIRS[d]; for (let i = 0; i < 400 && !run.transition; i++) run.tick(pad); tickN(run, 25); };

test('resume does not duplicate pickups or coins', () => {
  fresh();
  const run = newRun(4821);
  const start = run.room.key;
  // coins and a key, picked up in the first room
  AD.room.drop(run.room, run.hero.x, run.hero.y, { kind: 'coins', amount: 12 });
  AD.room.drop(run.room, run.hero.x, run.hero.y, { kind: 'key' });
  tickN(run, 30);
  assert.ok(run.coins >= 12 && run.keys >= 1);
  const { d, key } = doorOut(run);
  run.enterRoom(key, AD.gen.OPP[d]);
  tickN(run, 5);
  const coins = run.coins, keys = run.keys;
  AD.save.run(run);
  const back = AD.save.loadRun();
  assert.ok(back);
  assert.equal(back.coins, coins); assert.equal(back.keys, keys);
  assert.equal(back.room.key, key);
  back.enterRoom(start, d);
  assert.equal(back.room.pickups.length, 0);
});

test('a room comes back as it was left: broken pots stay broken, an open chest stays open', () => {
  fresh();
  const run = newRun(77);
  const start = run.room.key;
  run.room.grid.set(3, 3, 'p'); run.room.grid.set(4, 3, 'C');
  AD.world.breakAt(run.room, 3, 3);
  run.coins = 1e6; run.openChest(run.room, 4, 3);
  const left = run.room.grid.rows().join('/'), pickups = run.room.pickups.length;
  const { d, key } = doorOut(run);
  run.enterRoom(key, AD.gen.OPP[d]);
  AD.save.run(run);
  const back = AD.save.loadRun();
  back.enterRoom(start, d);
  assert.equal(back.room.grid.rows().join('/').replace(/=/g, 'D'), left.replace(/=/g, 'D'));
  assert.equal(back.room.chests['4,3'], true);
  assert.equal(back.room.pickups.length, pickups);
  assert.equal(back.openChest(back.room, 4, 3), false, 'no second item from it');
});

test('a room left before it was cleared comes back fresh on a resume, never barred and empty', () => {
  fresh();
  const run = newRun(4821);
  const R = [...run.floor.rooms.values()].find((r) => r.type === 'combat');
  run.enterRoom(R.key, 's'); tickN(run, 5);
  assert.ok(run.room.sealed);
  // out of it before it was cleared (as a Page of Teleport once could)
  run.enterRoom(run.floor.start, null); tickN(run, 5);
  AD.save.run(run);
  const back = AD.save.loadRun();
  back.enterRoom(R.key, 's'); tickN(back, 25);
  assert.ok(back.room.sealed, 'the fight is there again');
  for (let i = 0; i < 600 && !AD.director.done(back.room); i++) {
    for (const b of [...back.room.bodies.values()]) if (b.kind === 'monster' && !b.dead && !b.untargetable) AD.combat.deal(back.room, { src: back.hero, tgt: b, pct: 1e5, type: 'normal', proc: 0, mask: [] });
    tickN(back, 1);
  }
  tickN(back, 2);
  assert.equal(back.roomState.get(R.key).state, 'cleared');
  assert.ok(!back.room.grid.rows().join('').includes('='), 'its doors open');
});

test('a half-charged gate restarts', () => {
  fresh();
  const run = newRun(4821);
  const R = [...run.floor.rooms.values()].find((r) => r.type === 'exit');
  run.enterRoom(R.key, 's'); tickN(run, 25);
  const [gx, gy] = run.gateTile();
  run.touchGate(); run.place(gx, gy);
  tickN(run, 900);
  assert.ok(run.gate.charge > 0.4);
  AD.save.run(run);
  const back = AD.save.loadRun();
  assert.equal(back.gate, null);
  assert.equal(back.room.key, R.key);
});

test('saving without storage notices once and keeps playing', () => {
  fresh();
  storage.full(true);
  const run = newRun(3);
  let notices = 0;
  run.events.on('saveFailed', () => notices++);
  AD.save.run(run); AD.save.run(run);
  assert.equal(notices, 1);
  assert.equal(AD.save.warned, true);
  tickN(run, 60);
  assert.ok(!run.over);
  storage.full(false);
});

test('an unreadable save is set aside, with a plain message, and nothing breaks', () => {
  fresh();
  AD.store.setRaw('run', '{bad');
  assert.equal(AD.save.hasRun(), true);
  assert.equal(AD.save.loadRun(), null);
  assert.ok(AD.store.raw('run.bad'));
  assert.equal(AD.store.raw('run'), null);
  assert.equal(AD.save.problem, "Your last run couldn't be restored.");
  // a save from a newer game than this one is set aside too
  AD.store.set('run', { v: 99, seed: 1 });
  assert.equal(AD.save.loadRun(), null);
});

test('an older save is migrated', () => {
  fresh();
  const run = newRun(12);
  AD.save.run(run);
  const d = AD.store.get('run');
  d.v = 0; delete d.rerolls;
  AD.store.set('run', d);
  const back = AD.save.loadRun();
  assert.ok(back);
  assert.equal(back.rerolls, 0);
});

test('replay: same seed and input log give the same hash', () => {
  const LOG = (f) => ({ sx: [1, 0, -1, 0, 1][(f >> 4) % 5], sy: [0, 1, 0, -1, 1][(f >> 5) % 5], a: f % 11 === 0, aHeld: false, aReleased: false, b: f % 97 === 0, r: f % 131 === 0, l: false, q: [false, false, false] });
  const replay = (seed) => { const run = newRun(seed); tickN(run, 1500, LOG); return run.hash(); };
  assert.equal(replay(91), replay(91));
});

test('resuming at a room entry plays on exactly as if the game had never closed', () => {
  fresh();
  const pad = (f) => ({ sx: [1, 0, -1, 0][(f >> 5) % 4], sy: [0, 1, 0, -1][(f >> 4) % 4], a: f % 7 === 0, aHeld: false, aReleased: false, b: f % 83 === 0, r: false, l: false, q: [false, false, false] });
  const run = newRun(4821);
  let saved = null;
  run.events.on('enterRoom', () => { if (!saved && run.frames > 0) { AD.save.run(run); saved = AD.store.raw('run'); } });
  const { d } = doorOut(run);
  walkThrough(run, d);
  assert.ok(saved, 'the second room was entered');
  const at = run.frames;
  // a copy loaded from the save, and the same run played straight through, each play on from the entry
  const ahead = (r) => { for (let i = 0; i < 2000 && r.frames < at + 600 && !r.over; i++) r.tick(pad(r.frames)); return [r.frames, r.hash()]; };
  // god mode is a test switch, not part of a save: set it on the copy too
  const fromSave = (() => { AD.store.setRaw('run', saved); const r = AD.save.loadRun(); r.god = true; return ahead(r); })();
  const original = (() => { const r2 = newRun(4821); let reached = false; r2.events.on('enterRoom', () => { if (r2.frames > 0) reached = true; }); const { d: d2 } = doorOut(r2); const p = PAD(); [p.sx, p.sy] = AD.gen.DIRS[d2]; for (let i = 0; i < 600 && !reached; i++) r2.tick(p); return ahead(r2); })();
  assert.equal(fromSave[0], at + 600);
  assert.deepEqual(fromSave, original);
});

test('death clears the run save; the Garden saves whenever it changes', () => {
  fresh();
  const run = newRun(5);
  AD.save.watch(run);
  run.enterRoom(run.room.key, null);
  assert.ok(AD.save.hasRun());
  AD.save.endRun(run);
  assert.equal(AD.save.hasRun(), false);
  AD.save.boot();
  AD.meta.petals = 70; AD.meta.buy('thirdSlot');
  const m = AD.store.get('meta');
  assert.equal(m.petals, 30);
  assert.deepEqual([...m.unlocks], ['thirdSlot']);
});
