import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, testRoom } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js']);
const J = (v) => JSON.stringify(v);
const hero = (room, x, y) => AD.ent.make(room, { kind: 'hero', team: 'p', x, y, speed: 7.5, hp: 110, dmg: 12, crit: 0 });
const goblin = (room, x, y, o) => AD.ent.make(room, Object.assign({ kind: 'monster', team: 'e', x, y, speed: 5, hp: 60, dmg: 10, crit: 0 }, o));
const rec = (src, tgt, o) => Object.assign({ src, tgt, pct: 1, type: 'normal', proc: 1, mask: [] }, o);

test('shapes', () => {
  assert.equal(J(AD.combat.tiles({ k: 'arc3' }, 5, 5, [1, 0])), J([[6, 5], [6, 4], [6, 6]]));
  assert.equal(AD.combat.tiles({ k: 'plus', r: 1, at: 2 }, 5, 5, [0, 1]).length, 5);
  assert.equal(J(AD.combat.tiles({ k: 'plus', r: 1, at: 2 }, 5, 5, [0, 1])[0]), J([5, 7]));
  assert.equal(AD.combat.tiles({ k: 'square', r: 1 }, 5, 5, [1, 0]).length, 9);
  assert.equal(AD.combat.tiles({ k: 'ring', r: 1 }, 5, 5, [1, 0]).length, 8);
  assert.equal(J(AD.combat.tiles({ k: 'line', n: 3 }, 5, 5, [0, -1])), J([[5, 4], [5, 3], [5, 2]]));
  assert.equal(AD.combat.tiles({ k: 'cone', n: 2 }, 5, 5, [1, 0]).length, 4);    // rows of 1 and 3
  assert.equal(AD.combat.tiles({ k: 'wave', w: 3, n: 4 }, 5, 5, [1, 0]).length, 12);
});

test('damage: base x pct, armour', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5);
  const r1 = AD.combat.deal(room, rec(h, g));
  assert.equal(r1.amount, 12); assert.equal(g.hp, 48); assert.equal(h.hitstop, 3); assert.equal(g.hitstop, 3);
  g.armour = 100;
  assert.equal(AD.combat.deal(room, rec(h, g)).amount, 6);
});

test('crits double and hit-stop runs longer', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5);
  const r = AD.combat.deal(room, rec(h, g, { forceCrit: true }));
  assert.equal(r.amount, 24); assert.equal(r.crit, true); assert.equal(h.hitstop, 5);
});

test('damage bonuses add, then multiply once', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5);
  room.bus.on('dealMods', (p) => { p.bonus += 0.5; });
  room.bus.on('dealMods', (p) => { p.bonus += 0.25; });
  assert.equal(AD.combat.deal(room, rec(h, g)).amount, 21);   // 12 x 1.75
});

test('a block stops the hit', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5);
  room.bus.on('block', (p) => { if (p.tgt === g) p.blocked = true; });
  const r = AD.combat.deal(room, rec(h, g));
  assert.equal(r.blocked, true); assert.equal(g.hp, 60);
});

test('a telegraph: invulnerable frames dodge it, standing in it hurts', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5);
  g.facing = [-1, 0];
  AD.combat.attack(room, g, { shape: { k: 'adjacent' }, wind: 24, act: 3, rec: 18, pct: 1, proc: 1 });
  h.iframes = 30;
  for (let i = 0; i < 27; i++) AD.combat.tick(room);
  assert.equal(h.hp, 110);
  assert.equal(g.busy > 0, true);                                // still recovering
  AD.combat.attack(room, g, { shape: { k: 'adjacent' }, wind: 24, act: 3, rec: 18, pct: 1, proc: 1 });
  h.iframes = 0;
  for (let i = 0; i < 24; i++) AD.combat.tick(room);
  assert.equal(h.hp, 110);                                       // still winding up
  AD.combat.tick(room);
  assert.equal(h.hp, 100);
  for (let i = 0; i < 4; i++) AD.combat.tick(room);
  assert.equal(h.hp, 100);                                       // one hit per attack
});

test('the telegraph tiles stay where they were aimed', () => {
  const room = testRoom(AD), g = goblin(room, 6, 5);
  g.facing = [-1, 0];
  const t = AD.combat.attack(room, g, { shape: { k: 'line', n: 9 }, wind: 10, act: 1, rec: 1, pct: 1, proc: 1 });
  assert.equal(J(t.tiles[0]), J([5, 5]));
  assert.equal(t.tiles.length, 5);                               // stops at the wall at x=0
});

test('burn: half the burner\'s damage each second', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5);
  AD.status.apply(g, 'burn', { dur: 180, src: h });
  const before = g.hp;
  for (let i = 0; i < 60; i++) AD.status.tick(room, g);
  assert.equal(before - g.hp, 6);
  for (let i = 0; i < 200; i++) AD.status.tick(room, g);
  assert.equal(before - g.hp, 18);                               // three seconds, then it ends
  assert.equal(g.statuses.burn, undefined);
});

test('bleed stacks', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5, { hp: 200 });
  AD.status.apply(g, 'bleed', { dur: 180, src: h }); AD.status.apply(g, 'bleed', { dur: 180, src: h });
  for (let i = 0; i < 180; i++) AD.status.tick(room, g);
  assert.equal(200 - g.hp, 58);                                  // 2 x 240% of 12 = 57.6
});

test('chill, root, weaken, blind', () => {
  const room = testRoom(AD), h = hero(room, 5, 5);
  AD.status.apply(h, 'chill', { dur: 120 }); AD.status.apply(h, 'root', { dur: 120 }); AD.status.apply(h, 'weaken', { dur: 240 });
  const m = AD.status.mods(h);
  assert.equal(+m.move.toFixed(2), 0.6); assert.equal(+m.atk.toFixed(2), 0.6); assert.equal(m.rooted, true);
  assert.equal(+m.dmg.toFixed(2), 0.7); assert.equal(m.armour, -20);
  AD.status.apply(h, 'blind', { dur: 180 }); assert.equal(AD.status.mods(h).miss, 0.5);
});

test('a lethal hit can be cancelled', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5);
  room.bus.on('lethal', (p) => { p.cancel = true; p.tgt.hp = 1; });
  const r = AD.combat.deal(room, rec(g, h, { pct: 50 }));
  assert.equal(r.killed, false); assert.equal(h.hp, 1);
});

test('a kill is announced once', () => {
  const room = testRoom(AD), h = hero(room, 5, 5), g = goblin(room, 6, 5, { hp: 5 });
  let kills = 0;
  room.bus.on('kill', () => kills++);
  assert.equal(AD.combat.deal(room, rec(h, g)).killed, true);
  assert.equal(AD.combat.deal(room, rec(h, g)), null);           // the dead take no more hits
  assert.equal(kills, 1); assert.equal(g.dead, true);
});
