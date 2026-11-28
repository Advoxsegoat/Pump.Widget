import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load, testRoom } from './load.mjs';

const AD = load(['engine/core.js', 'sim/events.js', 'sim/grid.js', 'sim/entity.js']);
const hero = (room, x, y) => AD.ent.make(room, { kind: 'hero', team: 'p', x, y, speed: 7.5, mode: 'walk', hp: 110 });

test('frames per tile', () => {
  assert.equal(AD.ent.framesPerTile(7.5), 8);
  assert.equal(AD.ent.framesPerTile(5), 12);
});

test('a step glides tile to tile, holding both tiles until it lands', () => {
  const room = testRoom(AD), e = hero(room, 5, 5);
  assert.equal(room.grid.bodyAt(5, 5), e.id);
  assert.ok(AD.ent.tryStep(room, e, 1, 0));
  assert.equal(room.grid.bodyAt(6, 5), e.id);
  assert.deepEqual([...e.facing], [1, 0]);
  for (let i = 0; i < 4; i++) AD.ent.tick(room, e);
  assert.equal(e.fx, 5.5);
  assert.equal(AD.ent.tryStep(room, e, 0, 1), false);   // mid-step: not a new step
});

test('a direction pressed mid-step is taken the frame the step ends', () => {
  const room = testRoom(AD), e = hero(room, 5, 5);
  AD.ent.tryStep(room, e, 1, 0);
  for (let i = 0; i < 4; i++) AD.ent.tick(room, e);
  AD.ent.buffer(e, 0, 1);
  for (let i = 0; i < 4; i++) AD.ent.tick(room, e);
  assert.deepEqual([e.x, e.y], [6, 5]);
  assert.equal(room.grid.bodyAt(5, 5), 0);
  assert.ok(e.move && e.move.y1 === 6);
});

test('bodies never share a tile, and diagonals need both sides open and free', () => {
  const room = testRoom(AD), e = hero(room, 5, 5);
  const m = AD.ent.make(room, { kind: 'monster', team: 'e', x: 8, y: 5, speed: 5, mode: 'walk', hp: 60 });
  assert.equal(AD.ent.tryStep(room, m, -1, 0), true);              // m claims (7,5)
  const n = AD.ent.make(room, { kind: 'monster', team: 'e', x: 6, y: 4, speed: 5, mode: 'walk', hp: 1 });
  assert.equal(AD.ent.tryStep(room, n, 1, 1), false);              // (7,5) is claimed
  assert.equal(AD.ent.tryStep(room, n, -1, 1), false);             // (5,5) holds the hero
  assert.equal(AD.ent.tryStep(room, n, 0, -1), true);
  assert.equal(e.hp, 110);
});

test('arrival is announced', () => {
  const room = testRoom(AD), e = hero(room, 2, 2), seen = [];
  room.onArrive = (b) => seen.push([b.x, b.y]);
  AD.ent.tryStep(room, e, 1, 1);
  for (let i = 0; i < 8; i++) AD.ent.tick(room, e);
  assert.deepEqual(seen, [[3, 3]]);
});

test('a push glides 6 frames a tile and stops at the first blocked tile', () => {
  const room = testRoom(AD), e = hero(room, 11, 5);
  AD.ent.push(room, e, 1, 0, 3);                                  // wall at x=14: only 2 tiles of room
  for (let i = 0; i < 30; i++) AD.ent.tick(room, e);
  assert.deepEqual([e.x, e.y], [13, 5]);
  assert.equal(room.grid.bodyAt(11, 5), 0);
});

test('hit-stop freezes the glide', () => {
  const room = testRoom(AD), e = hero(room, 5, 5);
  AD.ent.tryStep(room, e, 1, 0);
  e.hitstop = 3;
  for (let i = 0; i < 3; i++) AD.ent.tick(room, e);
  assert.equal(e.fx, 5);
});

test('a struck body\'s white flash wears off, hit-stop or not', () => {
  const room = testRoom(AD), e = hero(room, 5, 5);
  e.flash = 6; e.hitstop = 3;
  for (let i = 0; i < 5; i++) AD.ent.tick(room, e);
  assert.equal(e.flash, 1);
  AD.ent.tick(room, e);
  assert.equal(e.flash, 0);
  AD.ent.tick(room, e);
  assert.equal(e.flash, 0);
});
