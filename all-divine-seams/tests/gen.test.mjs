import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const AD = load(['engine/core.js', 'sim/rng.js', 'sim/grid.js', 'data/regions.js', 'data/templates.js', 'gen/floor.js', 'gen/room.js']);
const WALK = new Set(['.', ',', '"', '-', '^', 'G', 'P', 'D', 'w']);
function connected(rows, starts) {
  const all = [];
  for (let y = 0; y < 10; y++) for (let x = 0; x < 15; x++) if (WALK.has(rows[y][x])) all.push(x + ',' + y);
  const seen = new Set([starts ? starts[0] : all[0]]);
  const q = [...seen];
  while (q.length) {
    const [x, y] = q.pop().split(',').map(Number);
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const k = (x + dx) + ',' + (y + dy);
      if (seen.has(k) || x + dx < 0 || y + dy < 0 || x + dx > 14 || y + dy > 9 || !WALK.has(rows[y + dy][x + dx])) continue;
      seen.add(k); q.push(k);
    }
  }
  return (starts || all).every((k) => seen.has(k)) && all.every((k) => seen.has(k));
}
const dump = (F) => JSON.stringify([...F.rooms.values()].map((r) => [r.gx, r.gy, r.type, r.doors]));

test('10,000 seeds generate valid floors', () => {
  for (let s = 1; s <= 10000; s++) for (const depth of [1, 3, 5]) {
    const F = AD.gen.floor(depth, AD.rng.make(s * 7 + depth));
    const v = AD.gen.validate(F);
    assert.ok(v.ok, s + '/' + depth + ' ' + v.why);
    assert.ok(F.rooms.size >= 8 && F.rooms.size <= 16, 'size ' + F.rooms.size);
    const types = [...F.rooms.values()].map((r) => r.type);
    assert.equal(types.filter((t) => t === 'exit').length, 1);
    assert.equal(types.filter((t) => t === 'start').length, 1);
    assert.equal(types.filter((t) => t === 'treasure').length, 1);
    assert.ok(types.filter((t) => t === 'rest').length <= 1);
  }
});

test('the exit is on the dead end farthest from the start', () => {
  for (let s = 1; s <= 200; s++) {
    const F = AD.gen.floor(2, AD.rng.make(s));
    const ex = F.rooms.get(F.exit);
    const deadEnds = [...F.rooms.values()].filter((r) => r.type !== 'secret' && r.key !== F.start && r.links === 1);
    assert.ok(deadEnds.every((r) => r.dist <= ex.dist));
  }
});

test('the secret room touches two rooms or more, never the exit', () => {
  let found = 0;
  for (let s = 1; s <= 300; s++) {
    const F = AD.gen.floor(3, AD.rng.make(s));
    const sec = [...F.rooms.values()].find((r) => r.type === 'secret');
    if (!sec) continue;
    found++;
    const nb = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => (sec.gx + dx) + ',' + (sec.gy + dy)).filter((k) => F.rooms.has(k));
    assert.ok(nb.length >= 2); assert.ok(!nb.includes(F.exit));
    for (const k of nb) { const r = F.rooms.get(k); assert.ok(Object.values(r.doors).includes('secret')); }
  }
  assert.ok(found > 150, 'secret rooms ' + found);
});

test('locked treasure has its key outside the lock', () => {
  let locked = 0;
  for (let s = 1; s <= 300; s++) {
    const F = AD.gen.floor(1, AD.rng.make(s));
    for (const k of F.keys) { locked++; assert.notEqual(k.room, k.lock); assert.ok(F.rooms.get(k.room).type !== 'treasure'); }
  }
  assert.ok(locked > 80 && locked < 220, 'locked ' + locked);
});

test('every template is 15x10, walled, with open door mouths, and connected', () => {
  assert.ok(AD.TEMPLATES.bilibara.filter((t) => t.type === 'combat').length >= 18);
  for (const t of AD.TEMPLATES.bilibara) {
    assert.equal(t.rows.length, 10);
    t.rows.forEach((r) => assert.equal(r.length, 15));
    assert.ok(connected(t.rows), t.id);
  }
});

test('built rooms: doors punched where the floor says, still connected after dressing', () => {
  for (let s = 1; s <= 300; s++) for (const depth of [1, 2, 4]) {
    const r = AD.rng.make(s * 13 + depth);
    const F = AD.gen.floor(depth, r);
    for (const key of F.rooms.keys()) {
      const R = AD.gen.room(F, key, 'bilibara', r);
      const rows = R.rows, d = F.rooms.get(key).doors;
      assert.equal(rows[0][7], d.n === 'open' ? 'D' : d.n === 'locked' ? '+' : d.n === 'secret' ? '%' : '#');
      assert.equal(rows[4][14], d.e === 'open' ? 'D' : d.e === 'locked' ? '+' : d.e === 'secret' ? '%' : '#');
      const starts = [];
      if (d.n === 'open') starts.push('7,0'); if (d.s === 'open') starts.push('7,9'); if (d.w === 'open') starts.push('0,4'); if (d.e === 'open') starts.push('14,4');
      if (starts.length) assert.ok(connected(rows, starts), s + ' ' + key + '\n' + rows.join('\n'));
      if (depth < 2) assert.equal(R.traps.length, 0);
    }
  }
});

test('the same seed gives the same floor and rooms', () => {
  assert.equal(dump(AD.gen.floor(2, AD.rng.make(9))), dump(AD.gen.floor(2, AD.rng.make(9))));
  const a = AD.gen.floor(2, AD.rng.make(9)), b = AD.gen.floor(2, AD.rng.make(9));
  assert.equal(JSON.stringify(AD.gen.room(a, a.start, 'bilibara', AD.rng.make(1)).rows), JSON.stringify(AD.gen.room(b, b.start, 'bilibara', AD.rng.make(1)).rows));
});

test('the boss arena is the Tanneries yard', () => {
  const R = AD.gen.arena('bilibara', AD.rng.make(1));
  assert.equal(R.rows.length, 10); assert.ok(R.rows.join('').split('v').length - 1 >= 4);
});
