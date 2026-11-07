import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const SIM = ['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js', 'sim/boss.js', 'data/regions.js', 'sim/director.js', 'sim/world.js', 'data/templates.js', 'gen/floor.js', 'gen/room.js', 'sim/room.js', 'game/run.js'];
const AD = load(SIM);
const PAD = () => ({ sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] });
const tickN = (run, n) => { for (let i = 0; i < n; i++) run.tick(PAD()); };
const rec = (src, tgt, o) => Object.assign({ src, tgt, pct: 1, type: 'normal', proc: 1, mask: [] }, o);
const forcePattern = (b, id) => { b.stagger = 0; b.busy = 0; b.gap = 0; b.stunned = 0; b.force = id; };

function arena(seed) {
  const run = new AD.Run({ hero: 'abarax', difficulty: 1, seed: seed || 3 });
  run.god = true;
  run.enterArena();
  return { run, b: run.bossBody, h: run.hero, room: run.room };
}

test('the bosses and mini-bosses exist with their numbers', () => {
  const B = AD.BOSSES;
  assert.deepEqual([B.firstknuckle.hp, B.firstknuckle.dmg, B.firstknuckle.shield], [2800, 22, 4]);
  for (const id of ['goldtooth', 'fixer', 'marais']) {
    assert.deepEqual([B[id].hp, B[id].dmg, B[id].shield], [900, 20, 3], id);
    assert.equal(B[id].patterns.length, 4, id);
  }
  assert.deepEqual([...B.firstknuckle.patterns.map((p) => p.id)].sort(), ['debts', 'dash', 'three', 'uppercut'].sort());
});

test('the arena: First Knuckle, 2,800 HP, 4 pips', () => {
  const { b } = arena();
  assert.equal(b.kind, 'boss'); assert.equal(b.mhp, 2800); assert.equal(b.pips, 4);
});

test('Shield and Break: heavy blows wear the pips; at none he staggers and takes +50%', () => {
  const { b, h, room } = arena();
  AD.combat.deal(room, rec(h, b, { pct: 3, shield: 2 }));
  AD.combat.deal(room, rec(h, b, { pct: 3, shield: 2 }));
  assert.equal(b.pips, 0); assert.equal(b.stagger, 180);
  assert.equal(AD.combat.deal(room, rec(h, b)).amount, 18);
});

test('phase two at 66%: the Hand comes, the shield is back', () => {
  const { run, b, h, room } = arena();
  AD.combat.deal(room, rec(h, b, { pct: 3, shield: 2 })); AD.combat.deal(room, rec(h, b, { pct: 3, shield: 2 }));
  b.hp = Math.floor(b.mhp * 0.65);
  tickN(run, 2);
  assert.equal(b.phase, 2);
  assert.equal([...room.bodies.values()].filter((x) => x.defId === 'tough').length, 2);
  assert.equal(b.pips, 4);
});

test('Call the Hand: the toughs come in at the arena\'s sealed doors, not out of the floor', () => {
  const { run, b, h, room } = arena();
  for (const [x, y] of Object.values(AD.gen.DOOR_AT)) assert.equal(room.grid.at(x, y), '=', 'door ' + x + ',' + y);
  AD.combat.deal(room, rec(h, b, { pct: 3, shield: 2 })); AD.combat.deal(room, rec(h, b, { pct: 3, shield: 2 }));
  b.hp = Math.floor(b.mhp * 0.65);
  tickN(run, 2);
  const mouths = ['n', 'w', 'e'].map((d) => AD.room.MOUTH[d].join(','));
  const toughs = [...room.bodies.values()].filter((x) => x.defId === 'tough');
  assert.equal(toughs.length, 2);
  for (const t of toughs) assert.ok(mouths.includes(t.x + ',' + t.y), 'tough at ' + t.x + ',' + t.y);
});

test('Knuckle Dash into a vat stuns him', () => {
  const { run, b, room } = arena();
  run.place(7, 8);
  room.grid.release(b.id, b.x, b.y); b.x = 7; b.y = 3; b.fx = 7; b.fy = 3; room.grid.claim(b.id, 7, 3);
  room.grid.set(7, 6, 'v');
  forcePattern(b, 'dash');
  tickN(run, 60);
  assert.ok(b.stunned > 0, 'stunned ' + b.stunned);
  assert.ok(b.y <= 5);
});

test('Debts Paid: eight marked tiles, each leaves five coins', () => {
  const { run, b, room } = arena();
  b.hp = Math.floor(b.mhp * 0.3);
  tickN(run, 2);
  for (const x of [...room.bodies.values()]) if (x.defId === 'tough') { x.dead = true; AD.ent.remove(room, x); }
  let debts = 0; room.bus.on('drop', (e) => { if (e.p.debts) debts++; });
  forcePattern(b, 'debts');
  tickN(run, 60);
  assert.equal(debts, 8);
});

test('beating First Knuckle: Knuckle Brass, +10% max HP, 10 petals, the run is won', () => {
  const { run, b, h, room } = arena();
  const mhp = h.mhp, petals = run.petals;
  AD.combat.deal(room, rec(h, b, { pct: 1e6 }));
  tickN(run, 2);
  assert.equal(AD.items.count(h, 'knucklebrass'), 1);
  assert.equal(h.mhp, Math.round(mhp * 1.1));
  assert.equal(run.petals, petals + 10);
  assert.ok(run.over && run.over.won);
});

test('a pattern never runs three times in a row', () => {
  const { run, b } = arena(9);
  const seen = [];
  b.onPattern = (id) => seen.push(id);
  for (let i = 0; i < 4000 && seen.length < 40; i++) { b.stagger = 0; tickN(run, 1); }
  assert.ok(seen.length >= 10, 'patterns ' + seen.length);
  for (let i = 2; i < seen.length; i++) assert.ok(!(seen[i] === seen[i - 1] && seen[i] === seen[i - 2]), seen.join(','));
});

test('the gate guardian is a real mini-boss', () => {
  const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 4821 }); run.god = true;
  const R = [...run.floor.rooms.values()].find((r) => r.type === 'exit');
  run.enterRoom(R.key, 's'); tickN(run, 25);
  run.touchGate();
  const g = run.gate.guardian;
  assert.equal(g.kind, 'boss'); assert.ok(['goldtooth', 'fixer', 'marais'].includes(g.defId)); assert.equal(g.pips, 3);
});
