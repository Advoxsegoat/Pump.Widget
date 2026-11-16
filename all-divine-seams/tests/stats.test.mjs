import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js']);
const S = AD.stat;

test('stacking rules', () => {
  assert.equal(S.linear(25, 25, 3), 75);
  assert.equal(+S.hyperbolic(0.15, 1).toFixed(4), 0.1304);
  assert.equal(+S.hyperbolic(0.15, 10).toFixed(4), 0.6);
  assert.equal(+S.diminish(0.9, 2).toFixed(2), 0.81);
  assert.equal(S.hyperbolic(0.15, 0), 0);
});

test('difficulty clock and enemy scaling (Risk of Rain curve)', () => {
  assert.equal(+S.coefficient(2, 10, 0).toFixed(3), 2.012);
  assert.equal(+S.coefficient(2, 10, 2).toFixed(3), 2.661);
  assert.equal(S.enemyLevel(1), 1);
  assert.equal(S.enemyLevel(2.012), 4);
  assert.equal(S.scaleHp(60, 4), 114);
  assert.equal(S.scaleDmg(10, 4), 16);
});

test('armour, prices, coins, experience', () => {
  assert.equal(S.mitigate(100, 100), 50);
  assert.equal(+S.mitigate(100, -50).toFixed(2), 133.33);
  assert.equal(S.chestCost(25, 1), 25);
  assert.equal(S.chestCost(25, 2), 59);
  assert.equal(S.coinsFor(8, 1), 4);
  assert.equal(S.coinsFor(8, 2), 6);
  assert.equal(S.xpFor(8), 4);
  assert.equal(S.xpToNext(1), 20);
  assert.equal(Math.round(S.xpToNext(3)), 48);
});

test('difficulty bands and short numbers', () => {
  assert.equal(S.band(0, 2), 0);
  assert.equal(S.band(5, 2), 1);
  assert.equal(S.band(60, 2), 6);
  assert.equal(S.BANDS[6], 'It has noticed');
  assert.equal(S.short(950), '950');
  assert.equal(S.short(12345), '12.3k');
  assert.equal(S.short(4100000), '4.1m');
});

test('seeded streams are independent and repeatable', () => {
  const a = AD.rng.streams(42, 1), b = AD.rng.streams(42, 1);
  assert.equal(a.layout(), b.layout());
  assert.notEqual(AD.rng.streams(42, 1).layout(), AD.rng.streams(42, 2).layout());
  assert.notEqual(AD.rng.streams(42, 1).layout(), AD.rng.streams(42, 1).loot());
  const r = AD.rng.make(5);
  for (let i = 0; i < 200; i++) { const v = AD.rng.int(r, 2, 4); assert.ok(v >= 2 && v <= 4); }
  assert.equal(AD.rng.weighted(AD.rng.make(1), [{ w: 0, v: 'a' }, { w: 1, v: 'b' }]), 'b');
});

test('seed text round-trips, and typed text hashes', () => {
  assert.equal(AD.rng.seedFromText(AD.rng.seedText(123456)), 123456);
  assert.match(AD.rng.seedText(123456), /^[A-Z]+-\d{4}$/);
  assert.equal(AD.rng.seedFromText('hello'), AD.rng.seedFromText('hello'));
  assert.notEqual(AD.rng.seedFromText('hello'), AD.rng.seedFromText('hellp'));
});

test('bus runs handlers by order and isolates a throwing one', () => {
  const bus = new AD.Bus(), seen = [];
  AD.report = () => {};
  bus.on('hit', () => seen.push('b'), 60);
  bus.on('hit', () => { throw new Error('x'); }, 10);
  const off = bus.on('hit', () => seen.push('a'), 50);
  const p = bus.emit('hit', { n: 1 });
  assert.deepEqual(seen, ['a', 'b']);
  assert.equal(p.n, 1);
  off(); bus.emit('hit', {});
  assert.deepEqual(seen, ['a', 'b', 'b']);
});
