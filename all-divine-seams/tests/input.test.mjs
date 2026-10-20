import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const AD = load(['engine/core.js', 'engine/input.js']);
const I = AD.input;
const dir = (x, y, d) => [...I.stickDir(x, y, d)];

test('the stick reads eight ways, 22.5 degrees either side of each, with a dead zone', () => {
  assert.deepEqual(dir(0.1, 0.1), [0, 0]);
  assert.deepEqual(dir(1, 0.1), [1, 0]);
  assert.deepEqual(dir(0.7, 0.7), [1, 1]);
  assert.deepEqual(dir(-0.2, -1), [0, -1]);
  assert.deepEqual(dir(-1, 0.3), [-1, 0]);
  assert.deepEqual(dir(-0.6, 0.8), [-1, 1]);
  // just either side of a sector's edge (22.5 degrees)
  const a = (deg) => [Math.cos((deg * Math.PI) / 180), Math.sin((deg * Math.PI) / 180)];
  assert.deepEqual(dir(...a(22)), [1, 0]);
  assert.deepEqual(dir(...a(23)), [1, 1]);
  assert.deepEqual(dir(0.3, 0, 0.28), [1, 0]);
  assert.deepEqual(dir(0.27, 0, 0.28), [0, 0]);
});

test('the pad: held directions, a press for one frame, A held and released', () => {
  I.clear(); I.releaseAll();
  I.src.key.right = true; I.src.key.up = true;
  I.update();
  assert.equal(AD.pad.sx, 1); assert.equal(AD.pad.sy, -1);
  I.src.key.up = false; I.src.key.right = false;
  I.src.key.a = true; I.latch.a = true;
  I.update();
  assert.equal(AD.pad.sx, 0);
  assert.equal(AD.pad.a, true); assert.equal(AD.pad.aHeld, true);
  I.update();
  assert.equal(AD.pad.a, false); assert.equal(AD.pad.aHeld, true);
  I.src.key.a = false;
  I.update();
  assert.equal(AD.pad.aReleased, true); assert.equal(AD.pad.aHeld, false);
});

test('a tap shorter than a frame still counts as one press', () => {
  I.releaseAll();
  I.update();
  I.latch.b = true; // down and up between two frames
  I.update();
  assert.equal(AD.pad.b, true);
  I.update();
  assert.equal(AD.pad.b, false);
});

test('the touch stick moves the pad; letting go stops it', () => {
  I.releaseAll();
  I.stick.on = true; I.stick.dx = 0.9; I.stick.dy = -0.1;
  I.update();
  assert.equal(AD.pad.sx, 1); assert.equal(AD.pad.sy, 0);
  I.stickUp();
  I.update();
  assert.equal(AD.pad.sx, 0);
});

test('quickslots and the other buttons each reach the pad', () => {
  I.releaseAll();
  for (const k of ['q0', 'q1', 'q2', 'r', 'l', 'start', 'map']) I.latch[k] = true;
  I.update();
  assert.deepEqual([...AD.pad.q], [true, true, true]);
  assert.equal(AD.pad.r, true); assert.equal(AD.pad.l, true); assert.equal(AD.pad.start, true); assert.equal(AD.pad.map, true);
});

test('losing the page releases everything and pauses', () => {
  I.src.key.left = true; I.src.touch.a = true; I.stick.on = true; I.stick.dx = 1;
  AD.paused = false;
  I.releaseAll('hidden');
  I.update();
  assert.equal(AD.pad.sx, 0); assert.equal(AD.pad.aHeld, false);
  assert.equal(AD.paused, true);
});

test('the keyboard map follows spec 4.2', () => {
  const K = I.KEYMAP;
  assert.equal(K.ArrowLeft, 'left'); assert.equal(K.a, 'left'); assert.equal(K.d, 'right');
  assert.equal(K.z, 'a'); assert.equal(K.j, 'a');
  assert.equal(K.x, 'b'); assert.equal(K.k, 'b');
  assert.equal(K.c, 'r'); assert.equal(K.l, 'r');
  assert.equal(K.v, 'l'); assert.equal(K[';'], 'l');
  assert.equal(K['1'], 'q0'); assert.equal(K['2'], 'q1'); assert.equal(K['3'], 'q2');
  assert.equal(K.Enter, 'start'); assert.equal(K.Escape, 'start'); assert.equal(K.m, 'map');
});
