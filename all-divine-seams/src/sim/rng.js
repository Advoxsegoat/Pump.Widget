// Seeded randomness. The simulation draws from three streams per depth (layout, combat, loot), so a
// choice made in a fight never changes the floor ahead. Drawing and sound may use Math.random.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const R = (AD.rng = {});

  // mulberry32
  R.make = function (seed) {
    let a = seed >>> 0;
    const f = function () {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    f.state = () => a >>> 0;
    f.restore = (s) => { a = s | 0; };
    return f;
  };

  // FNV-1a over a string
  R.hash = function (str) {
    let h = 0x811c9dc5;
    for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 0x01000193); }
    return h >>> 0;
  };

  R.streams = function (runSeed, depth) {
    const one = (name) => R.make(R.hash(runSeed + ':' + depth + ':' + name));
    return { layout: one('layout'), combat: one('combat'), loot: one('loot') };
  };

  R.int = (r, lo, hi) => lo + Math.floor(r() * (hi - lo + 1));
  R.pick = (r, arr) => arr[Math.floor(r() * arr.length)];
  R.chance = (r, p) => r() < p;
  R.weighted = function (r, entries) {
    let total = 0;
    for (const e of entries) total += Math.max(0, e.w);
    let x = r() * total;
    for (const e of entries) { if (e.w <= 0) continue; x -= e.w; if (x < 0) return e.v; }
    for (let i = entries.length - 1; i >= 0; i--) if (entries[i].w > 0) return entries[i].v;
    return undefined;
  };
  R.shuffle = function (r, arr) {
    const a = arr.slice();
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); const t = a[i]; a[i] = a[j]; a[j] = t; }
    return a;
  };

  // Seeds read like ROSE-4821: a word from the book and four digits. A run seed is below 640,000
  // so its text round-trips; any other typed text is hashed.
  const WORDS = ['ROSE', 'GARDEN', 'TIDE', 'LANTERN', 'IVORY', 'NIGHT', 'BELL', 'CROWN', 'HAND', 'KNUCKLE', 'BRASS', 'GOLD',
    'FLAME', 'BLOOM', 'SEAM', 'SALT', 'GORSE', 'SPIRE', 'MOON', 'PEAR', 'SKILLET', 'HARBOR', 'TANNERY', 'CAILLOU',
    'MIREILLE', 'LENARIS', 'RODDEN', 'CONCORD', 'CHOIR', 'FINGER', 'HOLLOW', 'WRAITH', 'MOTH', 'HOUND', 'LAZYMAN', 'COFFEE',
    'SARDINE', 'TAFFY', 'CROW', 'SWALLOW', 'THORN', 'PALM', 'STAIR', 'CATHEDRAL', 'TESSELLATE', 'WICK', 'HOOK', 'GIANT',
    'DAWN', 'DUSK', 'EMBER', 'ASH', 'PETAL', 'LOCKET', 'SIGNET', 'MANTLE', 'VAT', 'PIER', 'DOCK', 'ALLEY', 'STOOP', 'CELL', 'GATE', 'BOOK'];
  R.WORDS = WORDS;
  R.SEED_MAX = 64 * 10000;
  R.seedText = (s) => WORDS[s & 63] + '-' + String(Math.floor(s / 64) % 10000).padStart(4, '0');
  R.seedFromText = function (txt) {
    const m = /^([A-Z]+)-(\d{4})$/.exec(String(txt).trim().toUpperCase());
    if (m) { const w = WORDS.indexOf(m[1]); if (w >= 0) return w + 64 * Number(m[2]); }
    return R.hash(String(txt));
  };
  R.newSeed = () => Math.floor(Math.random() * R.SEED_MAX);
})(window.AD);
