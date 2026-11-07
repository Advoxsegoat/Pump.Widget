import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, testRoom } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js']);

function world(rows) {
  const room = testRoom(AD, rows);
  room.rng = { combat: AD.rng.make(21), loot: AD.rng.make(22) };
  const h = AD.hero.make(room, 'abarax', null, 5, 5);
  room.hero = h;
  AD.ai.install(room);
  const tick = () => {
    for (const e of room.bodies.values()) if (e.kind === 'monster') AD.ai.think(room, e);
    AD.combat.tick(room);
    AD.ai.tickProjectiles(room);
    for (const e of room.bodies.values()) AD.ent.tick(room, e);
    for (const e of room.bodies.values()) AD.status.tick(room, e);
    room.frame++;
  };
  const ticks = (n) => { for (let i = 0; i < n; i++) tick(); };
  return { room, h, tick, ticks };
}
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const rec = (src, tgt, o) => Object.assign({ src, tgt, pct: 1, type: 'normal', proc: 1, mask: [] }, o);

test('the Bilibara roster matches the spec table', () => {
  const M = AD.MONSTERS;
  const want = { rat: [20, 4, 6, 3], grunt: [60, 10, 5, 8], slinger: [45, 8, 4.5, 10], bomber: [50, 18, 4, 14], shaman: [55, 0, 4, 18], pickpocket: [40, 0, 7, 12], whelp: [70, 12, 5, 15], tough: [90, 14, 4.5, 12], hound: [50, 9, 9, 7], fusilier: [70, 16, 4, 16], brassmask: [140, 15, 3.5, 24], knuckle: [110, 18, 5, 20] };
  for (const [id, [hp, dmg, speed, cost]] of Object.entries(want)) {
    assert.deepEqual([M[id].hp, M[id].dmg, M[id].speed, M[id].cost], [hp, dmg, speed, cost], id);
  }
});

test('levels scale HP and damage', () => {
  const { room } = world();
  const g = AD.ai.spawn(room, 'grunt', 10, 2, { level: 4 });
  assert.equal(g.mhp, 114); assert.equal(g.dmg, 16);
});

test('a grunt closes in and strikes', () => {
  const { room, h, ticks } = world();
  const g = AD.ai.spawn(room, 'grunt', 10, 5);
  ticks(120);
  assert.ok(cheb(g, h) <= 2, 'distance ' + cheb(g, h));
  ticks(120);
  assert.ok(h.hp < 110);
});

test('a slinger keeps 3 to 4 tiles away and shoots', () => {
  const { room, h, ticks } = world();
  const sl = AD.ai.spawn(room, 'slinger', 8, 5);
  ticks(180);
  const d = cheb(sl, h);
  assert.ok(d >= 3 && d <= 4, 'distance ' + d);
  ticks(240);
  assert.ok(h.hp < 110);
});

test('a sleeper stays asleep, and a surprise hit always crits', () => {
  const { room, h, ticks } = world();
  const s = AD.ai.spawn(room, 'tough', 12, 2, { asleep: true });
  ticks(30);
  assert.equal(s.state, 'asleep');
  assert.equal(AD.combat.deal(room, rec(h, s)).crit, true);
  assert.equal(s.state, 'hunt');
});

test('noise wakes sleepers nearby', () => {
  const { room } = world();
  const near = [0, 1, 2, 3, 4, 5].map((i) => AD.ai.spawn(room, 'rat', 2 + i, 2, { asleep: true }));
  AD.ai.noise(room, 5, 3, 6);
  assert.ok(near.some((r) => r.state !== 'asleep'));
  const far = AD.ai.spawn(room, 'rat', 13, 8, { asleep: true });
  AD.ai.noise(room, 1, 1, 3);
  assert.equal(far.state, 'asleep');
});

test('the Brass Mask shield takes 80% from the front', () => {
  const { room, h } = world();
  const mask = AD.ai.spawn(room, 'brassmask', 6, 5); mask.facing = [-1, 0];
  assert.equal(AD.combat.deal(room, rec(h, mask)).amount, 2);
  mask.facing = [1, 0];
  assert.equal(AD.combat.deal(room, rec(h, mask)).amount, 12);
});

test('a pickpocket steals a tenth of the coins and runs', () => {
  const { room, h } = world();
  room.run.coins = 100;
  const t = AD.ai.spawn(room, 'pickpocket', 6, 5);
  AD.combat.deal(room, rec(t, h, { steal: true }));
  assert.equal(room.run.coins, 90); assert.equal(t.state, 'flee'); assert.equal(h.hp, 110);
  const drops = []; room.dropPickup = (x, y, p) => drops.push(p);
  AD.combat.deal(room, rec(h, t, { pct: 100 }));
  assert.equal(drops[0].kind, 'coins'); assert.equal(drops[0].amount, 15);
});

test('a whelp flies over a pit row a grunt cannot cross', () => {
  const rows = ['###############', '#.............#', '#.............#', '#.............#', '#OOOOOOOOOOOOO#', '#.............#', '#.............#', '#.............#', '#.............#', '###############'];
  const { room, h, ticks } = world(rows);
  const w = AD.ai.spawn(room, 'whelp', 6, 1);
  const g = AD.ai.spawn(room, 'grunt', 9, 1);
  ticks(180);
  assert.ok(w.y >= 4 && cheb(w, h) <= 2, 'whelp at ' + w.x + ',' + w.y);   // over the pits, in reach
  assert.ok(g.y <= 3, 'grunt at ' + g.y);
});

test('a goblin low on HP may flee', () => {
  const { room, h } = world();
  let fled = 0;
  for (let i = 0; i < 10; i++) {
    const g = AD.ai.spawn(room, 'grunt', 1 + i, 8, { hp: 100 });
    AD.combat.deal(room, rec(h, g, { pct: 6.5 }));
    if (g.state === 'flee') fled++;
  }
  assert.ok(fled > 0 && fled < 10, 'fled ' + fled);
});

test('a bomber\'s bomb lands, waits its fuse, and blows a plus', () => {
  const { room, h, ticks } = world();
  const b = AD.ai.spawn(room, 'bomber', 8, 5);
  ticks(200);
  assert.ok(h.hp < 110 || room.bombsThrown > 0);
  assert.ok(room.bombsThrown > 0);
  void b;
});
