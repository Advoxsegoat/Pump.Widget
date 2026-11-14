import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const AD = load(['engine/core.js', 'sim/events.js', 'engine/audio.js']);
function listen() {
  const bus = new AD.Bus(), heard = [], tracks = [];
  AD.audio.sfx = (n, o) => heard.push([n, o || {}]);
  AD.audio.play = (t) => tracks.push(t);
  AD.audio.bind(bus);
  return { bus, heard, tracks, names: () => heard.map((h) => h[0]) };
}

test('events map to sounds: a crit, a room sealing, a room clearing', () => {
  const { bus, names } = listen();
  bus.emit('hit', { amount: 20, crit: true, tgt: { mhp: 100 } });
  bus.emit('enterRoom', { sealed: true });
  bus.emit('roomClear', {});
  assert.deepEqual(names(), ['crit', 'doorSlam', 'chime']);
});

test('a hit is louder and lower the more of its target it takes; the hero\'s own pain is hurt', () => {
  const { bus, heard, names } = listen();
  bus.emit('hit', { amount: 5, tgt: { mhp: 100 } });
  bus.emit('hit', { amount: 60, tgt: { mhp: 100 } });
  assert.ok(heard[1][1].vol > heard[0][1].vol);
  assert.ok(heard[1][1].pitch < heard[0][1].pitch);
  bus.emit('hit', { amount: 0, tgt: { mhp: 100 } });
  bus.emit('hit', { amount: 9, tgt: { kind: 'hero', mhp: 110 } });
  bus.emit('hurt', { amount: 9 });
  assert.deepEqual(names(), ['hit', 'hit', 'hurt']);
});

test('a blow sounds on its own frames: the whoosh as it winds up, its impact on the first active frame', () => {
  const { bus, names } = listen();
  const atk = { owner: { kind: 'hero' }, def: { kind: 'combo', sfx: 'palm2', wind: 4, act: 2 } };
  bus.emit('attackStart', { attack: atk });
  assert.deepEqual(names(), ['whoosh']);
  bus.emit('strike', { attack: atk });
  assert.deepEqual(names(), ['whoosh', 'palm2']);
  // a fusilier cocks as it aims and fires on the shot; a bomb hisses and the blast is its own event
  bus.emit('attackStart', { attack: { owner: { kind: 'monster' }, def: { sfx: 'musket', wind: 45 } } });
  bus.emit('attackStart', { attack: { owner: { kind: 'monster' }, def: { sfx: 'fuse', bomb: true, wind: 90 } } });
  bus.emit('strike', { attack: { owner: { kind: 'monster' }, def: { sfx: 'fuse', bomb: true, wind: 90 } } });
  bus.emit('explode', { x: 3, y: 3, r: 1 });
  assert.deepEqual(names().slice(2), ['clang', 'fuse', 'boom']);
});

test('footsteps follow the hero\'s steps and the floor under them', () => {
  assert.equal(AD.audio.stepSound(','), 'step_grass');
  assert.equal(AD.audio.stepSound('"'), 'step_grass');
  assert.equal(AD.audio.stepSound('-'), 'step_water');
  assert.equal(AD.audio.stepSound('w'), 'step_wood');
  assert.equal(AD.audio.stepSound('.', 'interior'), 'step_wood');
  assert.equal(AD.audio.stepSound('.'), 'step_stone');
  const { bus, names } = listen();
  bus.emit('arrive', { e: { kind: 'hero' }, tile: '-' });
  bus.emit('arrive', { e: { kind: 'monster' }, tile: '.' });
  assert.deepEqual(names(), ['step_water']);
});

test('the music follows the fight: sealed room, clear, boss, gate', () => {
  const { bus, tracks, names } = listen();
  bus.emit('depthStart', { depth: 1 });
  bus.emit('enterRoom', { sealed: true });
  bus.emit('roomClear', {});
  bus.emit('gateStart', { gate: { charge: 0 } });
  bus.emit('gateCharging', { gate: { charge: 0.5 } });
  bus.emit('gateCharged', { gate: { charge: 1 } });
  bus.emit('bossIn', {});
  assert.deepEqual(tracks, ['bilibara', 'fight', 'bilibara', 'fight', 'bilibara', 'boss']);
  assert.deepEqual(names(), ['doorSlam', 'chime', 'gateHum', 'gateHum', 'gateDone', 'bossIn']);
});

test('the gate\'s hum rises as it charges', () => {
  const { bus, heard } = listen();
  bus.emit('gateCharging', { gate: { charge: 0.2 } });
  bus.emit('gateCharging', { gate: { charge: 0.8 } });
  assert.ok(heard[1][1].pitch > heard[0][1].pitch);
});

test('pickups each have their own sound', () => {
  const { bus, names } = listen();
  for (const p of [{ kind: 'coins' }, { kind: 'heart' }, { kind: 'key' }, { kind: 'item' }, { kind: 'cons', id: 'healing' }, { kind: 'cons', id: 'p-x', scroll: true }]) bus.emit('pickup', { p });
  assert.deepEqual(names(), ['coin', 'heart', 'key', 'item', 'potion', 'scroll']);
});

test('a track change waits for the next bar', () => {
  // 16 sixteenth-steps to a bar: at 0.1 s a step a bar is 1.6 s
  assert.equal(AD.audio.nextBar(1.0, 0, 0.1, 0.15), 1.6);
  assert.equal(+AD.audio.nextBar(1.5, 0, 0.1, 0.15).toFixed(6), 3.2);
});

test('every name in the sound table plays without an audio device', () => {
  const A = load(['engine/core.js', 'sim/events.js', 'engine/audio.js']).audio;
  for (const n of A.NAMES) A.sfx(n, { pitch: 1.2, vol: 0.5 });
  assert.ok(A.NAMES.length >= 40);
});

test('every sound a move names is in the table', async () => {
  const fs = await import('node:fs');
  const { ROOT } = await import('./load.mjs');
  const names = new Set(AD.audio.NAMES), want = new Set();
  // the moves name their sounds in the data, and the bosses' inside their patterns
  for (const f of ['data/heroes.js', 'data/monsters.js', 'data/consumables.js', 'sim/boss.js', 'sim/hero.js']) {
    const src = fs.readFileSync(ROOT + '/src/' + f, 'utf8');
    for (const m of src.matchAll(/sfx: '([A-Za-z0-9_]+)'/g)) want.add(m[1]);
    for (const m of src.matchAll(/sfx: \[([^\]]*)\]/g)) for (const n of m[1].matchAll(/'([A-Za-z0-9_]+)'/g)) want.add(n[1]);
  }
  for (const g of ['flame', 'bloom', 'tide']) want.add(g);
  const missing = [...want].filter((n) => !names.has(n));
  assert.deepEqual(missing, []);
  assert.ok(want.size >= 15, 'found ' + want.size);
});
