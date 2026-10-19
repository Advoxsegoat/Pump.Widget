// Monsters (spec §7.2, §7.3). Base stats are at level 1; speed is in tiles a second; attack frames
// are wind-up / active / recovery. `from` is the first depth a monster appears on.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const adj = { k: 'adjacent' };
  const A = (shape, wind, act, rec, pct, more) => Object.assign({ shape, wind, act, rec, pct: pct || 1, proc: 1 }, more || {});
  const M = (AD.MONSTERS = {
    rat: { n: 'Sewer Rat', family: 'vermin', hp: 20, dmg: 4, speed: 6, cost: 3, from: 1, mode: 'walk', brain: 'melee',
      attacks: [A(adj, 14, 2, 10, 1, { sfx: 'bite' })], look: 'rat' },
    grunt: { n: 'Goblin Grunt', family: 'goblin', hp: 60, dmg: 10, speed: 5, cost: 8, from: 1, mode: 'walk', brain: 'melee',
      attacks: [A({ k: 'line', n: 2 }, 24, 3, 18, 1, { lunge: 1, sfx: 'goblinSwing' })], look: 'grunt' },
    slinger: { n: 'Goblin Slinger', family: 'goblin', hp: 45, dmg: 8, speed: 4.5, cost: 10, from: 1, mode: 'walk', brain: 'ranged', keep: [3, 4],
      attacks: [A({ k: 'shot', range: 6, speed: 9 }, 30, 1, 24, 1, { shot: 'stone', sfx: 'sling' })], look: 'slinger' },
    bomber: { n: 'Goblin Bomber', family: 'goblin', hp: 50, dmg: 18, speed: 4, cost: 14, from: 2, mode: 'walk', brain: 'ranged', keep: [3, 4],
      attacks: [A({ k: 'lob', range: 3 }, 20, 1, 30, 1, { bomb: { fuse: 90, shape: { k: 'plus', r: 1 } }, sfx: 'fuse' })], look: 'bomber' },
    shaman: { n: 'Goblin Shaman', family: 'goblin', hp: 55, dmg: 0, speed: 4, cost: 18, from: 3, mode: 'walk', brain: 'shaman', keep: [3, 4],
      attacks: [], heal: { amount: 15, every: 240, r: 3, haste: 180 }, look: 'shaman' },
    pickpocket: { n: 'Goblin Pickpocket', family: 'goblin', hp: 40, dmg: 0, speed: 7, cost: 12, from: 2, mode: 'walk', brain: 'thief',
      attacks: [A(adj, 10, 2, 8, 0, { steal: true, sfx: 'coin' })], escape: 600, look: 'pickpocket' },
    whelp: { n: 'Wyvern Whelp', family: 'wyvern', hp: 70, dmg: 12, speed: 5, cost: 15, from: 3, mode: 'fly', brain: 'melee',
      attacks: [A({ k: 'line', n: 2 }, 20, 3, 20, 1, { lunge: 1, sfx: 'bite' })], eye: true, look: 'whelp' },
    tough: { n: 'Street Tough', family: 'thug', hp: 90, dmg: 14, speed: 4.5, cost: 12, from: 1, mode: 'walk', brain: 'melee',
      attacks: [A(adj, 22, 2, 14, 1, { sfx: 'clang', then: A(adj, 12, 2, 20, 1, { sfx: 'clang' }) })], look: 'tough' },
    hound: { n: 'Gray Hound', family: 'hound', hp: 50, dmg: 9, speed: 9, cost: 7, from: 1, mode: 'walk', brain: 'melee', pack: 3,
      attacks: [A({ k: 'line', n: 2 }, 16, 3, 16, 1, { lunge: 1, sfx: 'bite' })], look: 'hound' },
    fusilier: { n: 'Crown Fusilier', family: 'crown', hp: 70, dmg: 16, speed: 4, cost: 16, from: 2, mode: 'walk', brain: 'ranged', keep: [3, 5], aligned: true,
      attacks: [A({ k: 'line', n: 8 }, 45, 2, 40, 1, { sfx: 'musket' })], look: 'fusilier' },
    brassmask: { n: 'Brass Mask', family: 'hand', hp: 140, dmg: 15, speed: 3.5, cost: 24, from: 4, mode: 'walk', brain: 'melee', shield: 0.8, turn: 20,
      attacks: [A(adj, 26, 3, 20, 1, { push: 1, sfx: 'clang' })], look: 'brassmask' },
    knuckle: { n: 'Knuckle of the Hand', family: 'hand', hp: 110, dmg: 18, speed: 5, cost: 20, from: 4, mode: 'walk', brain: 'melee',
      attacks: [A(adj, 18, 2, 8, 1, { sfx: 'palm1', then: A(adj, 6, 2, 8, 1, { sfx: 'palm2', then: A(adj, 6, 2, 8, 1, { sfx: 'palm3' }) }) })], look: 'knuckle' },
  });
  AD.MONSTER_IDS = Object.keys(M);
})(window.AD);
