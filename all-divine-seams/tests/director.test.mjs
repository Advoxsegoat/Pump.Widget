import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, testRoom } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js', 'data/regions.js', 'sim/director.js']);
const costOf = (w) => w.reduce((t, s) => t + AD.MONSTERS[s.id].cost * (s.elite ? (s.eliteTier === 2 ? 36 : 6) : 1), 0);

function world() {
  const room = testRoom(AD);
  room.rng = { combat: AD.rng.make(31), loot: AD.rng.make(32) };
  room.hero = AD.hero.make(room, 'abarax', null, 2, 2);
  room.level = 1;
  AD.ai.install(room); AD.director.install(room);
  return room;
}

test('budgets (spec 6.3, 6.4)', () => {
  assert.equal(AD.director.budget(1, 'room'), 30);
  assert.equal(AD.director.budget(1, 'challenge'), 45);
  assert.equal(AD.director.budget(2, 'gate'), 31);
});

test('a depth-1 room: early monsters only, no elites, within budget', () => {
  for (let s = 1; s <= 50; s++) {
    const waves = AD.director.plan(AD.rng.make(s), 'bilibara', 1, 30);
    assert.ok(waves.length >= 1 && waves.length <= 3);
    const all = waves.flat();
    assert.ok(all.length > 0);
    assert.ok(all.every((x) => AD.MONSTERS[x.id].from <= 1 && !x.elite), JSON.stringify(all));
    assert.ok(costOf(all) <= 30);
  }
});

test('elites appear from depth 3 when the budget allows', () => {
  const late = AD.director.plan(AD.rng.make(7), 'bilibara', 4, 400);
  assert.ok(late.flat().some((x) => x.elite));
  assert.ok(late.flat().every((x) => !x.elite || AD.ELITES[x.elite]));
  const early = AD.director.plan(AD.rng.make(7), 'bilibara', 2, 400);
  assert.ok(early.flat().every((x) => !x.elite));
});

test('hounds come in threes when they can', () => {
  let packs = 0;
  for (let s = 1; s <= 80; s++) {
    const all = AD.director.plan(AD.rng.make(s), 'bilibara', 1, 60).flat();
    const n = all.filter((x) => x.id === 'hound').length;
    if (n) { assert.equal(n % 3, 0, 'seed ' + s); packs++; }
  }
  assert.ok(packs > 0);
});

test('spawn tiles: walkable, free, away from the hero and the doors', () => {
  const room = world();
  room.grid.set(0, 4, 'D');
  const tiles = AD.director.spawnTiles(room, 10, AD.rng.make(3));
  assert.equal(tiles.length, 10);
  for (const [x, y] of tiles) {
    assert.ok(room.grid.passable(x, y, 'walk'));
    assert.equal(room.grid.bodyAt(x, y), 0);
    assert.ok(Math.max(Math.abs(x - 2), Math.abs(y - 2)) >= 4);
    assert.ok(!(x === 0 && y === 4));
  }
});

test('the next wave comes when the alive cost drops under 30%', () => {
  const room = world();
  AD.director.begin(room, [[{ id: 'grunt' }, { id: 'grunt' }], [{ id: 'rat' }]]);
  AD.director.tick(room);
  const grunts = [...room.bodies.values()].filter((b) => b.defId === 'grunt');
  assert.equal(grunts.length, 2);
  assert.ok(grunts.every((g) => g.shimmer === 18));
  grunts[0].dead = true; AD.ent.remove(room, grunts[0]);
  AD.director.tick(room);
  assert.equal([...room.bodies.values()].filter((b) => b.defId === 'rat').length, 0);   // 50% left
  grunts[1].dead = true; AD.ent.remove(room, grunts[1]);
  AD.director.tick(room);
  assert.equal([...room.bodies.values()].filter((b) => b.defId === 'rat').length, 1);
  assert.equal(AD.director.done(room), false);
});

test('never more than 40 alive', () => {
  const room = world();
  AD.director.begin(room, [Array.from({ length: 120 }, () => ({ id: 'rat' }))]);
  let max = 0;
  for (let i = 0; i < 600; i++) {
    AD.director.tick(room);
    const alive = [...room.bodies.values()].filter((b) => b.kind === 'monster' && !b.dead);
    max = Math.max(max, alive.length);
    if (i % 5 === 0) for (const b of alive.slice(0, 3)) { b.dead = true; AD.ent.remove(room, b); }
  }
  assert.ok(max <= 40, 'max ' + max);
  assert.equal(max, 40);
});

test('elites: x4 HP, x2 damage; Thorned stops healing; Ivory chills', () => {
  const room = world();
  const e = AD.ai.spawn(room, 'grunt', 8, 2, { elite: 'thorned' });
  assert.equal(e.mhp, 240); assert.equal(e.dmg, 20);
  AD.combat.deal(room, { src: e, tgt: room.hero, pct: 1, type: 'normal', proc: 1, mask: [] });
  assert.ok(room.hero.statuses.noheal);
  const iv = AD.ai.spawn(room, 'grunt', 9, 2, { elite: 'ivory' });
  AD.combat.deal(room, { src: iv, tgt: room.hero, pct: 1, type: 'normal', proc: 1, mask: [] });
  assert.ok(room.hero.statuses.chill);
});

test('an elite drops a petal a quarter of the time', () => {
  let petals = 0;
  for (let s = 0; s < 200; s++) {
    const room = world();
    room.rng.loot = AD.rng.make(1000 + s);
    room.dropPickup = (x, y, p) => { if (p.kind === 'petal') petals++; };
    const e = AD.ai.spawn(room, 'rat', 8, 2, { elite: 'goldflame' });
    AD.combat.deal(room, { src: room.hero, tgt: e, pct: 100, type: 'normal', proc: 1, mask: [] });
  }
  assert.ok(petals > 30 && petals < 70, 'petals ' + petals);
});
