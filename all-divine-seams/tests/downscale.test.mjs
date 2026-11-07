import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const AD = load(['engine/core.js', 'art/downscale.js']);
const OUT = '#120c1a';
const grid = (w, h, f) => { const a = []; for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) a.push(f(x, y)); return a; };
const cells = (o) => { const a = []; for (let y = 0; y < o.h; y++) for (let x = 0; x < o.w; x++) a.push(o.get(x, y)); return a; };

test('3:2 — six becomes four', () => {
  const o = AD.art.reduce(grid(6, 6, () => '#8a5e3e'), 6, 6);
  assert.equal(o.w, 4); assert.equal(o.h, 4);
  assert.ok(cells(o).every((c) => c === '#8a5e3e'));
});

test('the outline survives', () => {
  const px = grid(6, 6, (x, y) => (x === 0 || y === 0 || x === 5 || y === 5) ? OUT : (x === 2 && y === 2) ? '#ffd27a' : '#8a5e3e');
  const o = AD.art.reduce(px, 6, 6);
  assert.equal(o.get(0, 0), OUT); assert.equal(o.get(3, 3), OUT); assert.equal(o.get(0, 2), OUT); assert.equal(o.get(3, 1), OUT);
});

test('the most saturated pixel (an eye) survives', () => {
  const px = grid(6, 6, (x, y) => (x === 0 || y === 0 || x === 5 || y === 5) ? OUT : (x === 2 && y === 2) ? '#ffd27a' : '#8a5e3e');
  assert.ok(cells(AD.art.reduce(px, 6, 6)).includes('#ffd27a'));
});

test('transparent only where the whole quarter is', () => {
  const px = grid(3, 3, (x, y) => (x === 2 && y === 2 ? '#a0a0a0' : null));
  const o = AD.art.reduce(px, 3, 3);
  assert.equal(o.get(0, 0), null);
  assert.equal(o.get(1, 1), '#a0a0a0');
});

test('sizes that are not multiples of three round up', () => {
  const o = AD.art.reduce(grid(7, 4, () => '#ffffff'), 7, 4);
  assert.equal(o.w, 5); assert.equal(o.h, 3);
});
