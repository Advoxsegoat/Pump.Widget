import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const SIM = ['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js', 'sim/boss.js', 'data/regions.js', 'sim/director.js', 'sim/world.js', 'data/templates.js', 'gen/floor.js', 'gen/room.js', 'sim/room.js', 'data/consumables.js', 'game/run.js'];
const AD = load(SIM.concat(['data/lore.js', 'game/meta.js']));
const M = AD.meta;
const PAD = () => ({ sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] });

test('Midas sells unlocks for petals (spec 5.5): what you can afford, and nothing you cannot', () => {
  M.reset(); M.petals = 35;
  assert.equal(M.buy('startHealing'), true);
  assert.equal(M.petals, 5);
  assert.equal(M.buy('thirdSlot'), false);
  assert.equal(M.petals, 5);
  assert.equal(M.buy('startHealing'), false, 'bought once');
  assert.deepEqual(Object.fromEntries(Object.entries(M.UNLOCKS).map(([k, u]) => [k, u.cost])),
    { startHealing: 30, thirdSlot: 40, extraRoll: 60, chestReroll: 80, stalls: 60, depth6: 50, depth11: 80, depth16: 120 });
});

test('what Bilibara cannot offer yet stays locked: the starting depths and the stalls', () => {
  M.reset(); M.petals = 999;
  for (const id of ['depth6', 'depth11', 'depth16', 'stalls']) { assert.equal(M.available(id), false, id); assert.equal(M.buy(id), false, id); }
  assert.equal(M.petals, 999);
});

test('a run starts with what was bought: the Healing draught first in the quickslots', () => {
  M.reset(); M.petals = 35; M.buy('startHealing');
  const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 1, meta: M });
  assert.equal(run.quick[0], 'healing');
  assert.equal(run.quick[1], 'bomb');
  assert.equal(AD.cons.count(run, 'healing'), 1);
  assert.equal(AD.cons.label(run, 'healing'), 'Draught of Healing');
});

test('the third quickslot and the extra roll', () => {
  M.reset(); M.petals = 100; M.buy('thirdSlot'); M.buy('extraRoll');
  const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 1, meta: M });
  assert.equal(run.quick.length, 3);
  assert.equal(run.hero.rollMax, AD.HEROES.abarax.base.rolls + 1);
  assert.equal(run.hero.rolls, run.hero.rollMax);
  const plain = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 1 });
  assert.equal(plain.quick.length, 2);
  assert.equal(plain.hero.rollMax, AD.HEROES.abarax.base.rolls);
});

test('one free chest reroll per depth: A on the open chest again, while its item still lies there', () => {
  M.reset(); M.petals = 80; M.buy('chestReroll');
  const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 5, meta: M });
  run.coins = 1e6;
  const room = run.room;
  room.grid.set(5, 3, 'C');
  assert.equal(run.openChest(room, 5, 3), true);
  const p = room.pickups.find((q) => q.kind === 'item');
  const first = p.item;
  assert.equal(run.openChest(room, 5, 3), true, 'rerolled');
  assert.equal(room.pickups.filter((q) => q.kind === 'item').length, 1);
  assert.equal(run.rerolls, 0);
  assert.equal(AD.ITEMS[p.item].tier, AD.ITEMS[first].tier, 'the same tier, a new item');
  assert.equal(run.openChest(room, 5, 3), false, 'only once a depth');
  run.nextDepth && run.nextDepth();
  if (run.depth === 2) assert.equal(run.rerolls, 1);
});

test('first-run hints show once each', () => {
  M.reset();
  assert.equal(M.hint('attack'), true);
  assert.equal(M.hint('attack'), false);
  assert.equal(M.hint('skill'), true);
  for (const id of ['attack', 'skill', 'roll', 'gate', 'quick']) assert.ok(AD.LORE.hints[id], id);
});

test('a finished run keeps its petals, its best depth and what the Book saw', () => {
  M.reset();
  const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 7, meta: M });
  run.god = true;
  M.watch(run);
  const m = AD.ai.spawn(run.room, 'grunt', 3, 3, { level: 1 });
  m.shimmer = 0; m.untargetable = false;
  AD.combat.deal(run.room, { src: run.hero, tgt: m, pct: 1e5, type: 'normal', proc: 0, mask: [] });
  AD.room.drop(run.room, run.hero.x, run.hero.y, { kind: 'item', item: 'lazyman' });
  for (let i = 0; i < 20; i++) run.tick(PAD());
  run.petals = 4; run.depth = 3;
  M.recordRun(run);
  assert.equal(M.petals, 4);
  assert.equal(M.best.depth, 3);
  assert.ok(M.book.monsters.has('grunt'));
  assert.ok(M.book.items.has('lazyman'));
  assert.equal(M.runs, 1);
});

test('the meta save round-trips', () => {
  M.reset(); M.petals = 90; M.buy('thirdSlot'); M.hint('gate'); M.book.monsters.add('rat'); M.settings.shake = 'low';
  const back = M.fromJSON(JSON.parse(JSON.stringify(M.toJSON())));
  assert.equal(back.petals, 50);
  assert.ok(back.unlocks.has('thirdSlot'));
  assert.ok(back.hints.has('gate'));
  assert.ok(back.book.monsters.has('rat'));
  assert.equal(back.settings.shake, 'low');
});
