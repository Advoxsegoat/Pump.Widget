// The numbers underneath (spec §2.3, §4.1, §5.1, §5.2).
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const S = (AD.stat = {});
  // stacking
  S.linear = (base, per, n) => (n <= 0 ? 0 : base + per * (n - 1));
  S.hyperbolic = (k, n) => 1 - 1 / (1 + k * n);
  S.diminish = (m, n) => Math.pow(m, n);
  // the difficulty clock: d = 1 Dawn, 2 Dusk, 3 Rose Hour
  S.coefficient = (d, minutes, cleared) => (1 + 0.0506 * d * minutes) * Math.pow(1.15, cleared);
  S.enemyLevel = (coef) => 1 + Math.floor((coef - 1) / 0.33 + 1e-9);
  S.scaleHp = (base, lvl) => Math.round(base * (1 + 0.3 * (lvl - 1)));
  S.scaleDmg = (base, lvl) => Math.round(base * (1 + 0.2 * (lvl - 1)));
  // armour
  S.mitigate = (amount, armour) => (armour >= 0 ? (amount * 100) / (100 + armour) : amount * (2 - 100 / (100 - armour)));
  // economy
  S.chestCost = (base, coef) => Math.round(base * Math.pow(coef, 1.25));
  S.coinsFor = (cost, coef) => Math.ceil(cost * 0.5 * (1 + 0.3 * (coef - 1)));
  // experience
  S.xpFor = (cost) => cost * 0.5;
  S.xpToNext = (level) => 20 * Math.pow(1.55, level - 1);
  // the difficulty bands on the clock
  S.BANDS = ['Calm', 'Restless', 'Hunted', 'Haunted', 'Unbound', 'Between', 'It has noticed'];
  S.band = (minutes, d) => Math.min(6, Math.floor(minutes / ((5 * 2) / d)));
  // HUD numbers
  S.short = function (n) {
    const a = Math.abs(n);
    if (a < 1000) return String(Math.round(n));
    if (a < 1e6) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return (n / 1e6).toFixed(1).replace(/\.0$/, '') + 'm';
  };
})(window.AD);
