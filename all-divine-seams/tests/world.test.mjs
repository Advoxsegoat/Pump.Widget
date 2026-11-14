import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, testRoom } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js', 'sim/world.js']);
const idx = (x, y) => y * 15 + x;
const sum = (a) => a.reduce((t, v) => t + v, 0);

function world() {
  const room = testRoom(AD);
  room.rng = { combat: AD.rng.make(41), loot: AD.rng.make(42) };
  room.level = 1; room.depth = 1;
  AD.world.init(room, { ambient: 1 });
  const h = AD.hero.make(room, 'abarax', null, 5, 5);
  room.hero = h;
  AD.ai.install(room);
  room.onArrive = (e) => AD.world.arrive(room, e);
  const ticks = (n) => { for (let i = 0; i < n; i++) { AD.world.tick(room); for (const e of room.bodies.values()) { AD.ent.tick(room, e); AD.status.tick(room, e); } room.frame++; } };
  return { room, h, ticks };
}

test('the hero may walk into a pit; monsters may not', () => {
  const { room } = world();
  room.grid.set(6, 5, 'O');
  assert.equal(room.grid.passable(6, 5, 'hero'), true);
  assert.equal(room.grid.passable(6, 5, 'walk'), false);
  assert.equal(room.grid.passable(6, 6, 'hero'), true);
});

test('gas spreads, walls stop it, it fades', () => {
  const { room, ticks } = world();
  AD.world.addGas(room, 5, 5, 'poison', 600);
  ticks(30);
  const total = sum(Array.from(room.gas));
  assert.ok(total < 600 && total > 300, 'total ' + total);
  assert.equal(room.gas[idx(0, 0)], 0);
  assert.ok(room.gas[idx(6, 5)] > 0);
});

test('poison gas hurts what stands in it', () => {
  const { room, h, ticks } = world();
  room.hero = null;
  AD.world.addGas(room, 5, 5, 'poison', 3000);
  ticks(60);
  assert.ok(h.hp < 110);
});

test('fire spreads on grass only and leaves ash', () => {
  const { room, ticks } = world();
  for (let x = 1; x <= 13; x++) room.grid.set(x, 3, ',');
  AD.world.ignite(room, 2, 3);
  ticks(400);
  assert.equal(room.grid.at(2, 3), '.');
  assert.ok(room.burned >= 2, 'burned ' + room.burned);
  assert.equal(room.grid.at(5, 5), '.');
  assert.equal(room.fire[idx(5, 5)], 0);
});

test('standing in fire burns', () => {
  const { room, h, ticks } = world();
  room.grid.set(5, 5, ',');
  AD.world.ignite(room, 5, 5);
  ticks(2);
  assert.ok(h.statuses.burn);
});

test('an explosion opens a cracked wall, chains a barrel, breaks pots', () => {
  const { room, h } = world();
  room.grid.set(5, 0, '%'); room.grid.set(6, 2, 'b'); room.grid.set(7, 3, 'p');
  AD.world.explode(room, 5, 1, 1, 3, h);
  assert.equal(room.grid.at(5, 0), 'D');
  assert.equal(room.grid.at(6, 2), '.');
  assert.equal(room.grid.at(7, 3), '.');                    // the barrel's blast broke the pot
});

test('an explosion hurts what is in it, never its own maker', () => {
  const { room, h } = world();
  const g = AD.ai.spawn(room, 'grunt', 6, 6, { hp: 100 });
  AD.world.explode(room, 5, 5, 1, 3, h);
  assert.equal(g.hp, 64); assert.equal(h.hp, 110);
});

test('pots drop coins or hearts', () => {
  const drops = [];
  for (let s = 0; s < 100; s++) {
    const { room } = world();
    room.rng.loot = AD.rng.make(500 + s);
    room.dropPickup = (x, y, p) => drops.push(p.kind);
    room.grid.set(3, 3, 'p');
    AD.world.breakAt(room, 3, 3);
  }
  const coins = drops.filter((k) => k === 'coins').length, hearts = drops.filter((k) => k === 'heart').length;
  assert.ok(coins > 45 && coins < 75, 'coins ' + coins);
  assert.ok(hearts > 5 && hearts < 26, 'hearts ' + hearts);
});

test('a pit costs 10% and returns the hero to the entry', () => {
  const { room, h, ticks } = world();
  room.entry = [1, 5]; room.grid.set(6, 5, 'O');
  AD.ent.tryStep(room, h, 1, 0);
  ticks(10);
  assert.deepEqual([h.x, h.y], [1, 5]);
  assert.equal(h.hp, 99);
});

test('shallow water puts out a burn', () => {
  const { room, h, ticks } = world();
  room.grid.set(6, 5, '-');
  AD.status.apply(h, 'burn', { dur: 180, src: h });
  AD.ent.tryStep(room, h, 1, 0);
  ticks(12);
  assert.equal(h.statuses.burn, undefined);
});

test('traps: hidden until spotted, a spike hurts when stepped on', () => {
  const { room, h, ticks } = world();
  AD.world.setTrap(room, 6, 5, 'spike');
  assert.equal(AD.world.trapAt(room, 6, 5).seen, false);
  AD.ent.tryStep(room, h, 1, 0);
  ticks(10);
  assert.ok(h.hp < 110);
  assert.equal(AD.world.trapAt(room, 6, 5).seen, true);
});

test('a trap is spotted within 2 tiles, sooner or later', () => {
  const { room, ticks } = world();
  AD.world.setTrap(room, 7, 5, 'alarm');
  ticks(60 * 30);
  assert.equal(AD.world.trapAt(room, 7, 5).seen, true);
});

test('light: lamps light the dark; sight is 8 in light, 4 in the dark', () => {
  const { room } = world();
  room.grid.set(10, 2, 'L');
  AD.world.tick(room);
  assert.equal(AD.world.sightRange(room, 10, 3), 8);
  assert.equal(AD.world.sightRange(room, 2, 8), 4);
});
