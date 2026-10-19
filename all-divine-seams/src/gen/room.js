// One room's tiles (spec §6.1): a template of the room's type, mirrored or flipped, doors punched
// where the floor says, then dressed by the region's rules. Dressing never cuts a room in two.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const GN = (AD.gen = AD.gen || {});
  const DOOR_AT = { n: [7, 0], s: [7, 9], w: [0, 4], e: [14, 4] };
  const MOUTHS = [[7, 1], [7, 8], [1, 4], [1, 5], [13, 4], [13, 5]];
  const GLYPH = { open: 'D', locked: '+', secret: '%' };
  const WALK = new Set(['.', ',', '"', '-', '^', 'G', 'P', 'D', 'w']);
  GN.DOOR_AT = DOOR_AT;

  // every walkable tile reachable from the first door mouth (4-way, as a walker sees it)
  function connected(rows) {
    const all = [];
    for (let y = 0; y < 10; y++) for (let x = 0; x < 15; x++) if (WALK.has(rows[y][x])) all.push(y * 15 + x);
    if (!all.length) return false;
    const seen = new Set([all[0]]); const q = [all[0]];
    while (q.length) {
      const i = q.pop(), x = i % 15, y = (i / 15) | 0;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx > 14 || ny > 9) continue;
        const j = ny * 15 + nx;
        if (!seen.has(j) && WALK.has(rows[ny][nx])) { seen.add(j); q.push(j); }
      }
    }
    return seen.size === all.length;
  }
  GN.connected = connected;

  const nearMouth = (x, y) => MOUTHS.some(([mx, my]) => Math.max(Math.abs(mx - x), Math.abs(my - y)) <= 1);

  // dressing by depth: streets get weeds, pots and crates; the sewers get standing water
  const DRESS = {
    city: [[',', 0.05], ['"', 0.02], ['p', 0.03], ['c', 0.02]],
    dungeon: [['-', 0.05], ['p', 0.03], ['c', 0.01]],
    interior: [['p', 0.04], ['c', 0.03], [',', 0.02]],
  };
  const TRAPS = [{ w: 4, v: 'spike' }, { w: 2, v: 'alarm' }, { w: 2, v: 'fire' }, { w: 2, v: 'gas' }, { w: 1, v: 'pit' }];

  GN.room = function (F, key, regionId, r) {
    const info = F.rooms.get(key);
    const all = AD.TEMPLATES[regionId].filter((t) => t.type === info.type);
    const tpl = AD.rng.pick(r, all);
    let rows = tpl.rows.map((s) => s.split(''));
    if (r() < 0.5) rows = rows.map((row) => row.slice().reverse());
    if (r() < 0.5) rows = rows.slice().reverse();
    for (const [d, [x, y]] of Object.entries(DOOR_AT)) rows[y][x] = info.doors[d] ? GLYPH[info.doors[d]] : '#';
    const depth = F.depth;
    const reg = AD.REGIONS[regionId].depths[Math.min(4, depth - 1)];
    const traps = [];
    if (info.type !== 'boss') {
      const dress = DRESS[reg.biome] || DRESS.city;
      for (let y = 1; y < 9; y++) for (let x = 1; x < 14; x++) {
        if (rows[y][x] !== '.' || nearMouth(x, y)) continue;
        const roll = r();
        let acc = 0;
        for (const [g, p] of dress) {
          acc += p;
          if (roll >= acc) continue;
          const was = rows[y][x];
          rows[y][x] = g;
          if (!WALK.has(g) && !connected(rows.map((row) => row.join('')))) rows[y][x] = was;
          break;
        }
      }
      if (depth >= 2 && info.type === 'combat') {
        const n = r() < 0.6 ? 1 : 2;
        const spots = [];
        for (let y = 2; y < 8; y++) for (let x = 2; x < 13; x++) if (rows[y][x] === '.' && !nearMouth(x, y)) spots.push([x, y]);
        for (const [x, y] of AD.rng.shuffle(r, spots).slice(0, n)) traps.push({ x, y, kind: AD.rng.weighted(r, TRAPS) });
      }
    }
    const out = rows.map((row) => row.join(''));
    return { rows: out, traps, template: tpl.id, name: tpl.n };
  };

  // the boss arena: the region's yard, entered from below
  GN.arena = function (regionId, r) {
    const tpl = AD.TEMPLATES[regionId].find((t) => t.type === 'boss');
    let rows = tpl.rows.map((s) => s.split(''));
    if (r() < 0.5) rows = rows.map((row) => row.slice().reverse());
    return { rows: rows.map((row) => row.join('')), traps: [], template: tpl.id, name: tpl.n };
  };
})(window.AD);
