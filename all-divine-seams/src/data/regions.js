// Regions: one part of the book each (spec §2.1). M1 has Bilibara, depths 1-5.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  AD.REGIONS = {
    bilibara: {
      n: 'Bilibara', part: 'Book One', music: 'bilibara',
      // ambient: how much light a room has before lamps and fire (0 dark .. 4 bright)
      depths: [
        { n: 'Rue Caillou', sub: 'A week after his brother left', biome: 'city', night: true, ambient: 1 },
        { n: 'The Harbor', sub: 'Behind the sardine cannery', biome: 'city', night: true, ambient: 1 },
        { n: 'Under Bilibara', sub: 'The old sewers', biome: 'dungeon', night: false, ambient: 0 },
        { n: 'The Tanneries', sub: 'Tuesday, 11:40 in the morning', biome: 'interior', night: false, ambient: 2 },
        { n: 'The Tanneries Yard', sub: 'Where the Hand collects', biome: 'city', night: false, ambient: 3 },
      ],
      // spawn weights (spec §7.3); a monster only spawns from its `from` depth
      weights: { rat: 10, grunt: 10, hound: 8, slinger: 7, tough: 7, bomber: 5, pickpocket: 3, fusilier: 5, whelp: 5, shaman: 3, brassmask: 4, knuckle: 4 },
      minis: ['goldtooth', 'fixer', 'marais'],
      boss: 'firstknuckle',
    },
  };
  AD.regionAt = (depth) => ({ id: 'bilibara', R: AD.REGIONS.bilibara, d: AD.REGIONS.bilibara.depths[Math.min(4, depth - 1)] });
})(window.AD);
