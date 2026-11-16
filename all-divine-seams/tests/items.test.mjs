import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, testRoom } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js']);
const setup = (opts) => {
  const room = testRoom(AD);
  room.rng = { combat: (opts && opts.rng) || AD.rng.make(3), loot: AD.rng.make(4) };
  const h = AD.ent.make(room, { kind: 'hero', team: 'p', x: 5, y: 5, speed: 7.5, hp: 110, dmg: 12, crit: 0 });
  h.items = {}; h.itemOrder = [];
  AD.items.install(room, h);
  return { room, h };
};
const mob = (room, x, y, o) => AD.ent.make(room, Object.assign({ kind: 'monster', team: 'e', x, y, speed: 5, hp: 60, dmg: 10, crit: 0 }, o));
const give = (h, id, n) => { for (let i = 0; i < (n || 1); i++) AD.items.give(null, h, id); };
const rec = (src, tgt, o) => Object.assign({ src, tgt, pct: 1, type: 'normal', proc: 1, mask: [] }, o);

test('the M1 catalogue is complete', () => {
  const tiers = {};
  for (const it of Object.values(AD.ITEMS)) tiers[it.tier] = (tiers[it.tier] || 0) + 1;
  assert.equal(tiers.common, 15); assert.equal(tiers.uncommon, 7); assert.equal(tiers.legendary, 2);
  assert.equal(tiers.boss, 1); assert.equal(tiers.equipment, 4);
  for (const it of Object.values(AD.ITEMS)) { assert.ok(it.n && it.desc, it.id); }
});

test('stat items stack by their rules', () => {
  const { h } = setup();
  give(h, 'lazyman', 3); assert.equal(AD.items.totals(h).maxHp, 75);
  give(h, 'coffeeflask', 2); assert.equal(+AD.items.totals(h).move.toFixed(2), 0.28);
  give(h, 'tinring', 1); assert.equal(+AD.items.blockChance(h).toFixed(4), 0.1304);
  give(h, 'lucienswatch', 2); assert.equal(+AD.items.totals(h).cdMul.toFixed(2), 0.81);
  give(h, 'crowfeather', 1); assert.equal(AD.items.totals(h).rolls, 1);
});

test('Warm Mitts: +75% against an enemy above 90% HP', () => {
  const { room, h } = setup(); give(h, 'warmmitts');
  const g = mob(room, 6, 5);
  assert.equal(AD.combat.deal(room, rec(h, g)).amount, 21);
  assert.equal(AD.combat.deal(room, rec(h, g)).amount, 12);   // now below 90%
});

test('Brass Buttons take 5 off each hit, never below 1', () => {
  const { room, h } = setup(); give(h, 'brassbuttons');
  const g = mob(room, 6, 5, { dmg: 4 });
  assert.equal(AD.combat.deal(room, rec(g, h)).amount, 1);
  const big = mob(room, 4, 5, { dmg: 20 });
  assert.equal(AD.combat.deal(room, rec(big, h)).amount, 15);
});

test('proc chains trigger each other and end', () => {
  const { room, h } = setup({ rng: () => 0 });          // every chance succeeds
  give(h, 'sparkcoil'); give(h, 'throwingknives'); give(h, 'petalstorm'); give(h, 'rosethorn');
  for (let i = 0; i < 10; i++) mob(room, 6 + (i % 4), 3 + (i >> 2), { hp: 10000 });
  let hits = 0; room.bus.on('hit', () => hits++);
  AD.combat.deal(room, rec(h, [...room.bodies.values()].find((b) => b.team === 'e')));
  assert.ok(hits > 3 && hits < 200, 'hits ' + hits);
});

test('an item never triggers from a chain that already holds it', () => {
  const { room, h } = setup({ rng: () => 0 }); give(h, 'throwingknives');
  const a = mob(room, 6, 5, { hp: 10000 }); mob(room, 7, 5, { hp: 10000 });
  let hits = 0; room.bus.on('hit', () => hits++);
  AD.combat.deal(room, rec(h, a));
  assert.equal(hits, 2);                                  // the hit, and one knife
});

test('Rose Divine Heart revives once and wilts', () => {
  const { room, h } = setup(); give(h, 'roseheart');
  const g = mob(room, 6, 5, { dmg: 500 });
  AD.combat.deal(room, rec(g, h));
  assert.equal(h.hp, h.mhp); assert.equal(h.dead, undefined);
  assert.equal(AD.items.count(h, 'roseheart'), 0); assert.equal(AD.items.count(h, 'wiltedrose'), 1);
  AD.combat.deal(room, rec(g, h));
  assert.equal(h.dead, true);
});

test('Brass Moon: every third hit crits', () => {
  const { room, h } = setup(); give(h, 'brassmoon');
  const d = mob(room, 6, 5, { hp: 100000 });
  const crits = [1, 2, 3, 4, 5, 6].map(() => AD.combat.deal(room, rec(h, d)).crit);
  assert.deepEqual(crits, [false, false, true, false, false, true]);
});

test('Bouillabaisse heals on a kill; Sardine Tin heals when a room clears', () => {
  const { room, h } = setup(); give(h, 'bouillabaisse'); give(h, 'sardinetin');
  h.hp = 50;
  AD.combat.deal(room, rec(h, mob(room, 6, 5, { hp: 1 })));
  assert.equal(h.hp, 60);                                 // 8 + 2% of 110 = 10.2
  room.bus.emit('roomClear', {});
  assert.equal(h.hp, 69);                                 // + 8% of 110 = 8.8
});

test('equipment cooldowns', () => {
  const { room, h } = setup();
  h.equipment = 'anchor';
  const g = mob(room, 6, 6, { hp: 100 });
  assert.ok(AD.items.useEquipment(room, h));
  assert.equal(g.hp, 52);                                 // 400% of 12
  assert.ok(!AD.items.useEquipment(room, h));
  assert.equal(h.eqCd, 1800);
  for (let i = 0; i < 1800; i++) AD.items.tick(room, h);
  assert.ok(AD.items.useEquipment(room, h));
});

test('Henri\'s Skillet blocks a blow from the front', () => {
  const { room, h } = setup(); h.equipment = 'skillet'; h.facing = [1, 0];
  const g = mob(room, 6, 5, { dmg: 30 });
  AD.items.useEquipment(room, h);
  assert.equal(AD.combat.deal(room, rec(g, h)).blocked, true);
  const back = mob(room, 4, 5, { dmg: 30 });
  assert.equal(AD.combat.deal(room, rec(back, h)).blocked, false);
});
