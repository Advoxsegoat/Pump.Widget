// The heroes. M1 has Abarax (spec §4.4); the cast arrives in later milestones.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  AD.HEROES = {
    abarax: {
      id: 'abarax', n: 'Abarax', look: 'abarax', weapon: 'The Open Hand',
      base: { hp: 110, regen: 1.0, dmg: 12, armour: 0, crit: 0.01, atkSpeed: 1, move: 7.5, rolls: 2 },
      combo: {
        hits: [
          { pct: 1, shape: { k: 'adjacent' } },
          { pct: 1, shape: { k: 'adjacent' } },
          { pct: 1.8, shape: { k: 'arc3' }, push: 1 },
        ],
        wind: 4, act: 2, rec: 8, reset: 20, sfx: ['palm1', 'palm2', 'palm3'],
      },
      spin: { charge: 40, pct: 3, shape: { k: 'ring', r: 1 }, shield: 2, wind: 2, act: 2, rec: 12 },
      gifts: {
        cd: 240,
        order: ['flame', 'bloom', 'tide'],
        flame: { shape: { k: 'cone', n: 2 }, pct: 2.2, status: { kind: 'burn', dur: 180 }, wind: 6, act: 2, rec: 10, type: 'burn' },
        bloom: { shape: { k: 'plus', r: 1, at: 2 }, pct: 1.5, status: { kind: 'root', dur: 120 }, wind: 8, act: 2, rec: 10, type: 'bloom' },
        tide: { shape: { k: 'wave', w: 3, n: 4 }, pct: 1.2, push: 2, wind: 6, act: 3, rec: 10, type: 'tide' },
      },
      roll: { tiles: 2, frames: 14, iframes: 12, recharge: 180 },
      getup: { heal: 0.2, over: 60, iframes: 120 },
    },
  };
})(window.AD);
