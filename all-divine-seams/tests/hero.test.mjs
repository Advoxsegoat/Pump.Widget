import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, testRoom } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js']);

function world() {
  const room = testRoom(AD);
  room.rng = { combat: AD.rng.make(9), loot: AD.rng.make(10) };
  const h = AD.hero.make(room, 'abarax', null, 5, 5);
  h.facing = [1, 0];
  const pad = { sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] };
  const frame = () => {
    AD.hero.control(room, h, pad);
    AD.combat.tick(room);
    for (const e of room.bodies.values()) AD.ent.tick(room, e);
    AD.items.tick(room, h);
    for (const e of room.bodies.values()) AD.status.tick(room, e);
    room.frame++;
    pad.a = false; pad.b = false; pad.r = false; pad.l = false; pad.aReleased = false;
  };
  const run = (n) => { for (let i = 0; i < n; i++) frame(); };
  const press = (k) => { pad[k] = true; if (k === 'a') pad.aHeld = true; frame(); if (k === 'a') pad.aHeld = false; };
  const dummy = (x, y) => {
    const d = AD.ent.make(room, { kind: 'monster', team: 'e', x, y, speed: 0.001, hp: 100000, dmg: 0, crit: 0 });
    d.log = []; return d;
  };
  room.bus.on('hit', (p) => { if (p.tgt.log) p.tgt.log.push(p.amount); });
  return { room, h, pad, run, press, dummy, frame };
}

test('Abarax\'s base stats (spec 4.4)', () => {
  const { h } = world();
  assert.equal(h.mhp, 110); assert.equal(h.hp, 110); assert.equal(h.dmg, 12); assert.equal(h.armour, 0);
  assert.equal(h.crit, 0.01); assert.equal(h.speed, 7.5); assert.equal(h.rolls, 2);
});

test('palm combo: 100%, 100%, 180%, then it resets after a pause', () => {
  const { h, run, press, dummy } = world();
  h.crit = 0;
  const d = dummy(6, 5); d.immovable = true;                       // the third hit pushes; keep it in reach
  press('a'); run(14); press('a'); run(14); press('a'); run(14);
  assert.deepEqual(d.log, [12, 12, 22]);
  run(30); press('a'); run(14);
  assert.equal(d.log[3], 12);
});

test('an A pressed mid-combo is queued and fires when the hit ends', () => {
  const { h, run, press, dummy } = world();
  h.crit = 0;
  const d = dummy(6, 5);
  press('a'); run(3); press('a'); run(30);
  assert.deepEqual(d.log, [12, 12]);
});

test('the third hit pushes', () => {
  const { h, run, press, dummy } = world();
  h.crit = 0;
  const d = dummy(6, 5); d.speed = 5;
  press('a'); run(14); press('a'); run(14); press('a'); run(30);
  assert.equal(d.x, 7);
});

test('charged spin: hold A for 40 frames, 300% to all eight neighbours', () => {
  const { h, pad, run, frame, dummy } = world();
  h.crit = 0;
  const ring = [[4, 4], [5, 4], [6, 4], [4, 5], [6, 5], [4, 6], [5, 6], [6, 6]].map(([x, y]) => dummy(x, y));
  pad.a = true; pad.aHeld = true; frame();
  for (let i = 0; i < 40; i++) frame();
  pad.aHeld = false; pad.aReleased = true; frame();
  run(20);
  for (const d of ring) assert.equal(d.log[d.log.length - 1], 36);
});

test('a held A tells the bus once, the frame the spin is ready (its glint and sound)', () => {
  const { room, h, pad, frame } = world();
  const ready = [];
  room.bus.on('charged', (p) => ready.push(p.h === h ? room.frame : -1));
  pad.a = true; pad.aHeld = true; frame();
  for (let i = 0; i < 60; i++) frame();
  assert.equal(ready.length, 1);
  assert.equal(h.charge, 61);
});

test('Three Gifts: flame, bloom, tide in turn, every 4 s', () => {
  const { h, run, press, dummy } = world();
  h.crit = 0;
  const near = dummy(6, 5), far = dummy(7, 4);
  assert.equal(AD.hero.nextGift(h), 'flame');
  press('b'); run(20);
  assert.equal(near.log[0], 26);                                   // 220% of 12 = 26.4
  assert.ok(near.statuses.burn); assert.ok(far.log.length === 1);  // the row beyond is 3 wide
  assert.equal(AD.hero.nextGift(h), 'bloom');
  press('b'); assert.equal(AD.hero.nextGift(h), 'bloom');          // still cooling down
  run(240); press('b'); run(20);
  assert.equal(AD.hero.nextGift(h), 'tide');
});

test('roll: two tiles, invulnerable, two charges, 3 s each to come back', () => {
  const { h, run, press } = world();
  press('r'); run(14);
  assert.deepEqual([h.x, h.y], [7, 5]);
  press('r'); press('r');
  assert.equal(h.rolls, 0);
  run(180);
  assert.equal(h.rolls, 1);
});

test('a roll dodges a telegraphed blow', () => {
  const { room, h, run, press } = world();
  const g = AD.ent.make(room, { kind: 'monster', team: 'e', x: 6, y: 5, speed: 5, hp: 50, dmg: 20, crit: 0, facing: [-1, 0] });
  AD.combat.attack(room, g, { shape: { k: 'adjacent' }, wind: 8, act: 2, rec: 10, pct: 1, proc: 1 });
  run(5); h.facing = [0, 1]; press('r'); run(20);
  assert.equal(h.hp, 110);
});

test('a roll pressed while a blow lands is taken the frame the blow can be cancelled', () => {
  const { h, run, press, dummy } = world();
  dummy(6, 5);
  press('a');
  // through the wind-up to the frame the palm lands (and the hit-stop that holds it there)
  for (let i = 0; i < 12 && !(h.attacking && h.attacking.frame > h.attacking.def.wind); i++) run(1);
  assert.ok(h.attacking && h.attacking.frame > h.attacking.def.wind, 'the blow is landing');
  h.facing = [0, 1];
  press('r');
  run(20);
  assert.equal(h.rolls, 1, 'the roll was taken');
  assert.deepEqual([h.x, h.y], [5, 7]);
});

test('Get Up: once a depth, a lethal blow leaves 1 HP', () => {
  const { room, h, run } = world();
  const big = AD.ent.make(room, { kind: 'monster', team: 'e', x: 8, y: 8, speed: 5, hp: 50, dmg: 999, crit: 0 });
  AD.combat.deal(room, { src: big, tgt: h, pct: 1, type: 'normal', proc: 1, mask: [] });
  assert.equal(h.dead, undefined); assert.equal(h.hp, 1); assert.equal(h.iframes, 120);
  run(60);
  assert.equal(h.hp, 24);                                           // +20% of 110 over a second, and a second of regen
  AD.combat.deal(room, { src: big, tgt: h, pct: 1, type: 'normal', proc: 1, mask: [] });
  assert.equal(h.dead, true);
});

test('levels: +30% base HP and +20% base damage', () => {
  const { h } = world();
  AD.hero.gainXp(h, 20);
  assert.equal(h.level, 2); assert.equal(h.mhp, 143); assert.equal(+h.dmg.toFixed(1), 14.4); assert.equal(h.xp, 0);
});

test('items change the stats', () => {
  const { h } = world();
  AD.items.give(null, h, 'lazyman'); AD.items.give(null, h, 'crowfeather'); AD.items.give(null, h, 'gamblerschip');
  assert.equal(h.mhp, 135); assert.equal(h.hp, 135); assert.equal(h.rollMax, 3); assert.equal(+h.crit.toFixed(2), 0.11);
});

test('regen: 1 HP a second', () => {
  const { h, run } = world();
  h.hp = 50; run(120);
  assert.equal(h.hp, 52);
});
