import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const AD = load(['engine/core.js', 'sim/grid.js']);
const rows = [
  '###############',
  '#.............#',
  '#..#..........#',
  '#..#...~~.....#',
  '#..#...~~.....#',
  'D.............D',
  '#......O......#',
  '#.....""......#',
  '#.............#',
  '#######D#######',
];
const at = (x, y) => y * 15 + x;

test('walkers and flyers', () => {
  const g = new AD.Grid(rows);
  assert.equal(g.w, 15); assert.equal(g.h, 10);
  assert.equal(g.passable(7, 3, 'walk'), false);
  assert.equal(g.passable(7, 3, 'fly'), true);
  assert.equal(g.passable(7, 6, 'walk'), false);   // pit
  assert.equal(g.passable(7, 6, 'fly'), true);
  assert.equal(g.passable(0, 5, 'walk'), true);    // door
  assert.equal(g.passable(-1, 5, 'walk'), false);  // off the map
});

test('sight lines', () => {
  const g = new AD.Grid(rows);
  assert.equal(g.los(1, 3, 6, 3), false);           // the wall at x=3 blocks
  assert.equal(g.los(4, 7, 9, 7), false);           // tall grass blocks sight
  assert.equal(g.los(4, 1, 12, 8), true);
  assert.equal(g.los(4, 4, 4, 4), true);
});

test('distance maps: 8-way without corner cutting', () => {
  const g = new AD.Grid(rows);
  const d = g.distanceMap([[1, 1]], 'walk');
  assert.equal(d[at(2, 1)], 1);
  assert.equal(d[at(7, 3)], -1);                    // deep water is out of reach on foot
  assert.equal(d[at(2, 2)], 1);                     // diagonal allowed: both orthogonals open
  assert.equal(d[at(4, 3)], 5);                     // round the end of the wall at x=3, no corner cutting
  const f = g.distanceMap([[1, 1]], 'fly');
  assert.ok(f[at(7, 3)] > 0);
});

test('flee maps point away', () => {
  const g = new AD.Grid(rows);
  const d = g.distanceMap([[7, 5]], 'walk');
  const fl = g.fleeMap(d);
  assert.ok(fl[at(1, 1)] < fl[at(6, 5)]);           // lower is better for a fleer
});

test('one body per tile', () => {
  const g = new AD.Grid(rows);
  assert.ok(g.claim(5, 4, 4)); assert.ok(!g.claim(6, 4, 4));
  assert.equal(g.bodyAt(4, 4), 5);
  g.release(5, 4, 4); assert.ok(g.claim(6, 4, 4));
  g.release(5, 4, 4); assert.equal(g.bodyAt(4, 4), 6); // releasing someone else's tile does nothing
});

test('set changes the tile and its rules', () => {
  const g = new AD.Grid(rows);
  g.set(1, 1, '#'); assert.equal(g.at(1, 1), '#'); assert.equal(g.passable(1, 1, 'walk'), false);
});
