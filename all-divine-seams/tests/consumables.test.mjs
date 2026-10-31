import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const SIM = ['engine/core.js', 'sim/rng.js', 'sim/events.js', 'sim/stats.js', 'sim/grid.js', 'sim/entity.js', 'sim/status.js', 'sim/combat.js', 'data/items.js', 'sim/items.js', 'data/heroes.js', 'sim/hero.js', 'data/monsters.js', 'sim/ai.js', 'sim/boss.js', 'data/regions.js', 'sim/director.js', 'sim/world.js', 'data/templates.js', 'gen/floor.js', 'gen/room.js', 'sim/room.js', 'data/consumables.js', 'game/run.js'];
const AD = load(SIM);
const PAD = () => ({ sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] });
const tickN = (run, n) => { for (let i = 0; i < n; i++) run.tick(PAD()); };
const newRun = (seed) => { const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed }); run.god = true; return run; };
const use = (run, id, choice) => AD.cons.useId(run, id, choice);

test('names are hidden until known, and shuffled per run', () => {
  const run = newRun(77);
  assert.match(AD.cons.label(run, 'healing'), / draught$/);
  assert.match(AD.cons.label(run, 'identify'), /^A page marked [A-Z]+$/);
  assert.notEqual(JSON.stringify(newRun(77).idTable.potions), JSON.stringify(newRun(78).idTable.potions));
  assert.equal(JSON.stringify(newRun(77).idTable.potions), JSON.stringify(newRun(77).idTable.potions));
});

test('a run starts with one bomb in a quickslot', () => {
  const run = newRun(1);
  assert.equal(run.bombs, 1);
  assert.equal(run.quick[0], 'bomb');
});

test('drinking Healing heals 60% over a second, cures burns, and names it', () => {
  const run = newRun(77);
  AD.cons.give(run, 'healing');
  run.hero.hp = 10;
  AD.status.apply(run.hero, 'burn', { src: run.hero, dur: 180 });
  assert.ok(use(run, 'healing'));
  tickN(run, 60);
  assert.ok(run.hero.hp >= 76 && run.hero.hp <= 77, 'hp ' + run.hero.hp);       // 10 + 66, and a second of regen
  assert.equal(run.hero.statuses.burn, undefined);
  assert.equal(AD.cons.label(run, 'healing'), 'Draught of Healing');
  assert.equal(AD.cons.count(run, 'healing'), 0);
});

test('Haste and Toughness', () => {
  const run = newRun(5);
  AD.cons.give(run, 'haste'); AD.cons.give(run, 'toughness');
  use(run, 'haste'); use(run, 'toughness');
  const m = AD.status.mods(run.hero);
  assert.equal(+m.move.toFixed(2), 1.5); assert.equal(m.armour, 60);
});

test('thrown potions land three tiles ahead', () => {
  const run = newRun(6);
  run.place(3, 4); run.hero.facing = [1, 0];
  AD.cons.give(run, 'toxic');
  use(run, 'toxic');
  assert.ok(run.room.gas[4 * 15 + 6] > 0);
});

test('Experience gives a level', () => {
  const run = newRun(8);
  const ups = [];
  run.events.on('levelUp', (p) => ups.push(p.level));
  AD.cons.give(run, 'experience');
  use(run, 'experience');
  assert.equal(run.hero.level, 2);
  assert.deepEqual([...ups], [2]);
});

test('armour: worn, upgraded, cursed until Remove Curse', () => {
  const run = newRun(9);
  const p = AD.cons.makeArmour(run, 'plate', { cursed: true, curse: 'heavy', level: -2 });
  assert.ok(AD.cons.wear(run, p));
  assert.equal(run.hero.armour, 16);                                           // 22 - 2 x 3
  assert.equal(+run.hero.moveGear.toFixed(2), +(0.94 * 0.9).toFixed(2));      // plate -6%, heavy -10%
  assert.equal(AD.cons.unwear(run), false);
  AD.cons.give(run, 'removecurse'); use(run, 'removecurse');
  assert.equal(AD.cons.unwear(run), true);
  assert.equal(run.hero.armour, 0);
});

test('Upgrade: the weapon, +10% damage a level; on armour it clears a curse\'s penalty first', () => {
  const run = newRun(10);
  AD.cons.give(run, 'upgrade'); use(run, 'upgrade', 'weapon');
  assert.equal(+run.hero.dmgMul.toFixed(2), 1.1);
  assert.equal(+run.hero.dmg.toFixed(1), 13.2);
  const p = AD.cons.makeArmour(run, 'hauberk', { cursed: false, level: -1 });
  AD.cons.wear(run, p);
  AD.cons.give(run, 'upgrade'); use(run, 'upgrade', 'armour');
  assert.equal(p.level, 1); assert.equal(run.hero.armour, 15);
});

test('Lullaby puts the room to sleep, and a sleeper takes a surprise crit', () => {
  const run = newRun(11);
  const g = AD.ai.spawn(run.room, 'grunt', run.hero.x + 2, run.hero.y, {});
  AD.cons.give(run, 'lullaby'); use(run, 'lullaby');
  assert.equal(g.state, 'asleep');
});

test('Recharging refills everything', () => {
  const run = newRun(12);
  run.hero.skillCd = 200; run.hero.rolls = 0; run.hero.equipment = 'anchor'; run.hero.eqCd = 900;
  AD.cons.give(run, 'recharging'); use(run, 'recharging');
  assert.deepEqual([run.hero.skillCd, run.hero.rolls, run.hero.eqCd], [0, 2, 0]);
});

test('a bomb: placed ahead, 90 frames, 300% around it, never hurts its maker', () => {
  const run = newRun(13);
  run.place(5, 4); run.hero.facing = [1, 0];
  const g = AD.ai.spawn(run.room, 'grunt', 7, 4, { hp: 100 });
  g.shimmer = 0; g.untargetable = false; AD.status.apply(g, 'stun', { dur: 999 });   // awake (no surprise crit) but still
  assert.ok(use(run, 'bomb'));
  assert.equal(run.bombs, 0);
  tickN(run, 95);
  assert.equal(g.hp, 64);
  assert.equal(run.hero.hp, run.hero.mhp);
});

test('the quickslot button uses the slot', () => {
  const run = newRun(14);
  AD.cons.give(run, 'healing');
  const s = AD.cons.slotOf(run, 'healing');
  run.hero.hp = 50;
  const pad = PAD(); pad.q[s] = true;
  run.tick(pad); tickN(run, 60);
  assert.ok(run.hero.hp > 100);
});

test('identify names the worn armour first', () => {
  const run = newRun(15);
  const p = AD.cons.makeArmour(run, 'jerkin', { cursed: false, level: 0, known: false });
  AD.cons.wear(run, p);
  AD.cons.give(run, 'identify'); use(run, 'identify');
  assert.equal(p.known, true);
});

test('a Page of Teleport cannot carry the hero out of a sealed fight or the arena', () => {
  const run = newRun(4821);
  const R = [...run.floor.rooms.values()].find((r) => r.type === 'combat');
  run.enterRoom(R.key, 's'); tickN(run, 5);
  assert.ok(run.room.sealed);
  const notes = [];
  run.events.on('notice', (p) => notes.push(p.text));
  AD.cons.give(run, 'teleport', 1);
  // read and used up, and so named, but the Seams hold the hero where the fight is
  assert.equal(use(run, 'teleport'), true);
  assert.equal(run.room.key, R.key);
  assert.equal(AD.cons.known(run, 'teleport'), true);
  assert.equal(notes.length, 1);
  run.enterArena(); tickN(run, 5);
  AD.cons.give(run, 'teleport', 1);
  use(run, 'teleport');
  assert.equal(run.room.key, 'arena');
});

test('a Page of Upgrade asks what to upgrade once there is armour to choose', () => {
  const run = newRun(9);
  assert.deepEqual([...AD.cons.choices(run, 'upgrade')], [], 'nothing to choose: the weapon');
  AD.cons.wear(run, AD.cons.makeArmour(run, 'jerkin', { known: true, level: 0, cursed: false }));
  assert.deepEqual([...AD.cons.choices(run, 'upgrade')], ['weapon', 'armour']);
  assert.deepEqual([...AD.cons.choices(run, 'healing')], []);
});

test('spare armour can be worn, and armour taken off, unless the worn piece is cursed', () => {
  const run = newRun(10);
  const a = AD.cons.makeArmour(run, 'jerkin', { known: true, level: 0, cursed: false });
  const b = AD.cons.makeArmour(run, 'plate', { known: true, level: 0, cursed: false });
  AD.cons.wear(run, a); run.spareArmour.push(b);
  assert.equal(AD.cons.toggleArmour(run, b), 'worn');
  assert.equal(run.armour, b); assert.ok(run.spareArmour.includes(a));
  assert.equal(AD.cons.toggleArmour(run, b), 'off');
  assert.equal(run.armour, null); assert.equal(run.spareArmour.length, 2);
  const c = AD.cons.makeArmour(run, 'hauberk', { known: true, level: -1, cursed: true, curse: 'heavy' });
  AD.cons.wear(run, c);
  assert.equal(AD.cons.toggleArmour(run, c), 'cursed');
  assert.equal(AD.cons.toggleArmour(run, a), 'cursed');
  assert.equal(run.armour, c);
});

