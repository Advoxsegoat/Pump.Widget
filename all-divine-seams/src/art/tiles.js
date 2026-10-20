// Terrain: movement costs and bonuses per tile, plus the pixel art for every biome.
// Ground is baked once per map; tall props (trees, roofs, walls, lamps) are baked per row so
// units can be drawn between rows and stand in front of or behind them.
// Tiles are 24px. Ground is deliberately quiet (broad colour drift, few specks) so units read
// against it; props carry the detail and get a soft dark outline to separate them from the floor.
(function (AD) {
  'use strict';
  const G = AD.gfx;
  const TL = (AD.tiles = {});
  const _ = null;
  const S = 24, HEAD = 56;
  TL.S = S; TL.HEAD = HEAD;
  // cost order: foot, armor, horse, fly, phase, swim
  const MT = { foot: 0, armor: 1, horse: 2, fly: 3, phase: 4, swim: 5 };
  TL.MT = MT;
  const T = {
    '.': { n: 'Plain', c: [1, 1, 1, 1, 1, 1] },
    ',': { n: 'Street', c: [1, 1, 1, 1, 1, 1] },
    '=': { n: 'Road', c: [1, 1, 1, 1, 1, 1] },
    T: { n: 'Trees', c: [2, 3, 3, 1, 2, 2], avo: 20, def: 1, prop: 1 },
    j: { n: 'Pear Tree', c: [2, 3, 3, 1, 2, 2], avo: 20, def: 1, prop: 1 },
    R: { n: 'Gold Roses', c: [2, 3, 3, 1, 2, 2], avo: 20, heal: 10, prop: 1 },
    g: { n: 'Flowers', c: [1, 1, 1, 1, 1, 1], avo: 10 },
    i: { n: 'Bellflowers', c: [1, 1, 1, 1, 1, 1], avo: 10, light: '#a98cf0' },
    '#': { n: 'Wall', c: [_, _, _, _, 2, _], prop: 1 },
    B: { n: 'Roof', c: [_, _, _, 1, _, _], prop: 1 },
    n: { n: 'Neon Front', c: [_, _, _, 1, _, _], prop: 1, light: '#ff5fa8' },
    H: { n: 'House', c: [1, 1, 1, 1, 1, 1], avo: 10, visit: 1, prop: 1, light: '#ffc870' },
    F: { n: 'Fort', c: [2, 2, 2, 2, 2, 2], avo: 20, def: 2, heal: 20, prop: 1, light: '#ff9a4a' },
    G: { n: 'Throne', c: [1, 1, 1, 1, 1, 1], avo: 20, def: 3, heal: 10, prop: 1 },
    '~': { n: 'Sea', c: [_, _, _, 1, _, 1], water: 1 },
    '-': { n: 'Shallows', c: [3, 4, 4, 1, 3, 1], avo: -10, water: 1 },
    b: { n: 'Bridge', c: [1, 1, 1, 1, 1, 1] },
    '^': { n: 'Hill', c: [3, 4, 4, 1, 3, 3], avo: 30, def: 1 },
    M: { n: 'Peak', c: [_, _, _, 2, _, _], avo: 40, def: 2, prop: 1 },
    s: { n: 'Sand', c: [2, 3, 3, 1, 2, 2], avo: 5 },
    '*': { n: 'Snowdrift', c: [2, 3, 3, 1, 2, 2], avo: 5 },
    P: { n: 'Pillar', c: [2, 2, 3, 2, 2, 2], avo: 20, def: 1, prop: 1 },
    D: { n: 'Door', c: [_, _, _, _, 2, _], prop: 1, door: 1 },
    C: { n: 'Chest', c: [1, 1, 1, 1, 1, 1], prop: 1, chest: 1 },
    r: { n: 'Rubble', c: [2, 3, 3, 1, 2, 2], avo: 10 },
    x: { n: 'Gray Nothing', c: [_, _, _, _, _, _], void: 1 },
    L: { n: 'Lamp', c: [_, _, _, _, _, _], prop: 1, light: '#ffd28a' },
    t: { n: 'Counter', c: [_, _, _, 1, _, _], prop: 1 },
    f: { n: 'Fountain', c: [_, _, _, 1, _, _], prop: 1, water: 1 },
    p: { n: 'Pier', c: [1, 1, 1, 1, 1, 1] },
    o: { n: 'Boulder', c: [_, _, _, 1, _, _], prop: 1 },
    a: { n: 'Carpet', c: [1, 1, 1, 1, 1, 1] },
    w: { n: 'Floor', c: [1, 1, 1, 1, 1, 1] },
    K: { n: 'Rose Window', c: [_, _, _, _, _, _], prop: 1, light: '#ff3a3a' },
    k: { n: 'Black Glass', c: [_, _, _, 1, _, _], prop: 1 },
    c: { n: 'Crates', c: [2, 3, 3, 1, 2, 2], avo: 20, def: 1, prop: 1 },
    '<': { n: 'Stairs', c: [1, 1, 1, 1, 1, 1], exit: 1 },
    v: { n: 'Vat', c: [_, _, _, 1, _, _], prop: 1, light: '#7aff9a' },
    '%': { n: 'Hot Spring', c: [2, 3, 3, 1, 2, 1], heal: 20, water: 1 },
    h: { n: 'Tent', c: [1, 1, 1, 1, 1, 1], avo: 10, def: 1, prop: 1 },
    W: { n: 'Wagon', c: [_, _, _, 1, _, _], prop: 1 },
    Q: { n: 'Lighthouse', c: [_, _, _, _, _, _], prop: 1, light: '#ffe8a0' },
    S: { n: 'Shop', c: [1, 1, 1, 1, 1, 1], avo: 10, prop: 1, light: '#ffc870' },
  };
  TL.T = T;
  TL.info = (ch) => T[ch] || T['.'];
  TL.cost = function (ch, mt) {
    const t = T[ch] || T['.'];
    return t.c[MT[mt] === undefined ? 0 : MT[mt]];
  };

  // ---------------------------------------------------------------- biomes
  const BI = {
    city: { plain: 'snowstone', ground: '#8a8ea6', groundD: '#6c7090', groundL: '#a8acc4', cob: '#6e7088', cobD: '#54566c', cobL: '#8a8ca4', road: '#77788c',
      wallT: '#e2d6ba', wallF: '#b8aa8a', wallD: '#8a7e64', roof: '#5f6f8c', roofD: '#47546c', roofL: '#7e8eaa', tree: '#2c5244', treeD: '#1b372e', treeL: '#3e6e5c', trunk: '#4a3628',
      water: '#1e3a64', waterL: '#3a6a9a', waterD: '#142a4c', rose: '#ffcf5a', bush: '#2a4a3a', snow: 1, house: '#9a5a4a', win: '#ffd88a' },
    coast: { plain: 'grass', grass: '#5a9a52', grassD: '#4a8244', grassL: '#7ab66a', cob: '#a8a090', cobD: '#888070', cobL: '#c0b8a8', road: '#b89a6a',
      wallT: '#e8e0d0', wallF: '#c8bca4', wallD: '#9a8e78', roof: '#c0603a', roofD: '#963e24', roofL: '#de8458', tree: '#2e7a3e', treeD: '#1e5a2c', treeL: '#4a9a54', trunk: '#5a3e2a',
      water: '#2a6aaa', waterL: '#5aa0d8', waterD: '#1a4a80', rose: '#e8344e', bush: '#2e6a34', sand: '#e0cc90', house: '#c0603a', win: '#ffe0a0' },
    hills: { plain: 'gorse', grass: '#8a9a4a', grassD: '#6e7e3a', grassL: '#b8b450', cob: '#9a9480', cobD: '#7a7462', cobL: '#b4ae98', road: '#a88a5a',
      wallT: '#c8c0b0', wallF: '#a49c8a', wallD: '#7a7464', roof: '#8a5a3a', roofD: '#6a4228', roofL: '#a87a5a', tree: '#3a5a3a', treeD: '#263e28', treeL: '#4e7450', trunk: '#4a3628', pine: 1,
      water: '#3a6a8a', waterL: '#6a9aba', waterD: '#284e6a', rose: '#e8c040', bush: '#6a7a2a', house: '#8a5a3a', win: '#ffe0a0' },
    vale: { plain: 'grass', grass: '#4a9a5a', grassD: '#3a824a', grassL: '#6ab878', cob: '#a8a090', cobD: '#888070', cobL: '#c0b8a8', road: '#b09a72',
      wallT: '#d8d4c8', wallF: '#b4b0a2', wallD: '#8a867a', roof: '#6a7a9a', roofD: '#4e5a76', roofL: '#8a9aba', tree: '#2a6a44', treeD: '#1a4a30', treeL: '#3e8a5a', trunk: '#4a3628', pine: 1,
      water: '#3a7aba', waterL: '#7ab4e4', waterD: '#285a90', rose: '#e8344e', bush: '#2e6a34', snowcap: 1, house: '#7a5a4a', win: '#ffe0a0' },
    marble: { plain: 'marble', ground: '#e8e2d6', groundD: '#cfc8b8', groundL: '#f6f2ea', cob: '#d8cfbc', cobD: '#b8ae98', cobL: '#ece6d8', road: '#c8b898',
      wallT: '#f4efe4', wallF: '#d4cab4', wallD: '#a89e88', roof: '#4a8a7a', roofD: '#366a5c', roofL: '#6aaa98', tree: '#3a6a3a', treeD: '#284e28', treeL: '#4e8a4e', trunk: '#5a3e2a',
      water: '#2a6aaa', waterL: '#5aa0d8', waterD: '#1a4a80', rose: '#e8344e', bush: '#3a6a3a', granite: '#a84a3a', house: '#a84a3a', win: '#ffe0a0' },
    garden: { plain: 'violet', grass: '#8aa89a', grassD: '#6a8a7e', grassL: '#b4d0c0', cob: '#7a7a9a', cobD: '#5a5a7a', cobL: '#9a9aba', road: '#8a8aa8',
      wallT: '#a8a0c0', wallF: '#7e76a0', wallD: '#5a5278', roof: '#5a4a8a', roofD: '#3e326a', roofL: '#7a6aaa', tree: '#2a4a9a', treeD: '#1a2e6a', treeL: '#4a6ac8', trunk: '#8a8a9a',
      water: '#0e0e1e', waterL: '#3a3a6a', waterD: '#06060e', rose: '#ffe28a', bush: '#4a6a8a', house: '#6a5a9a', win: '#c9b0ff', motes: 1 },
    spire: { plain: 'bone', ground: '#d8d2c2', groundD: '#bab2a0', groundL: '#ece8dc', cob: '#cac2ae', cobD: '#aaa28e', cobL: '#e0dacb', road: '#c0b8a4',
      wallT: '#f0ebe0', wallF: '#d0c8b4', wallD: '#a8a08a', roof: '#e0dace', roofD: '#b8b0a0', roofL: '#f8f4ec', tree: '#4a6a5a', treeD: '#344e42', treeL: '#5e8470', trunk: '#5a4a3a',
      water: '#2a4a6a', waterL: '#4a7aa0', waterD: '#1a3450', rose: '#e8e0ff', bush: '#4a6a5a', house: '#c8c0b0', win: '#fff6d0' },
    flats: { plain: 'snow', ground: '#dfe4ee', groundD: '#c2c8d8', groundL: '#f4f6fc', cob: '#a8acbc', cobD: '#888c9c', cobL: '#c4c8d6', road: '#b0b0bc',
      wallT: '#3a2a3a', wallF: '#2a1e2a', wallD: '#1a121a', roof: '#3a2a3a', roofD: '#2a1e2a', roofL: '#4e3a4e', tree: '#3a3a44', treeD: '#26262e', treeL: '#4e4e5a', trunk: '#2a2a30', dead: 1,
      water: '#1e2e4a', waterL: '#3a5070', waterD: '#121c30', rose: '#ffcf5a', bush: '#3a4a3a', house: '#5a4a5a', win: '#ff8a6a' },
    interior: { plain: 'wood', ground: '#8a5e3e', groundD: '#6e4a30', groundL: '#a4744e', cob: '#7a6a5a', cobD: '#5a4a3a', cobL: '#9a8a7a', road: '#8a5e3e',
      wallT: '#e8d8bc', wallF: '#b49470', wallD: '#7a5e44', roof: '#5a4a3a', roofD: '#3e3226', roofL: '#7a6a5a', tree: '#3a6a3a', treeD: '#284e28', treeL: '#4e8a4e', trunk: '#5a3e2a',
      water: '#2a4a6a', waterL: '#4a7aa0', waterD: '#1a3450', rose: '#e8344e', bush: '#3a6a3a', carpet: '#8e2f4a', house: '#7a5a4a', win: '#ffd88a' },
    dungeon: { plain: 'dstone', ground: '#4a4a58', groundD: '#3a3a46', groundL: '#5a5a6a', cob: '#525262', cobD: '#3e3e4c', cobL: '#646476', road: '#4a4a58',
      wallT: '#6a6a7c', wallF: '#3e3e4e', wallD: '#2a2a36', roof: '#2a2a36', roofD: '#1e1e28', roofL: '#3a3a48', tree: '#2a3a2a', treeD: '#1a261a', treeL: '#3a4e3a', trunk: '#3a2a20',
      water: '#14243e', waterL: '#2a4a6e', waterD: '#0c1628', rose: '#ffcf5a', bush: '#2a3a2a', house: '#4a3a3a', win: '#ff9a4a' },
    salt: { plain: 'salt', ground: '#eef2f6', groundD: '#d4dbe6', groundL: '#ffffff', cob: '#d8dee8', cobD: '#b8c0cc', cobL: '#eef2f6', road: '#d0d6e0',
      wallT: '#c8ccd4', wallF: '#a4a8b0', wallD: '#80848c', roof: '#a4a8b0', roofD: '#80848c', roofL: '#c8ccd4', tree: '#6a7a6a', treeD: '#4e5a4e', treeL: '#8a9a8a', trunk: '#5a4a3a',
      water: '#9ec8e8', waterL: '#d8eefc', waterD: '#7aa8cc', rose: '#ffcf5a', bush: '#6a7a6a', house: '#a4a8b0', win: '#ffe0a0' },
  };
  TL.BI = BI;

  function rndAt(x, y, k) {
    let h = (x * 374761393 + y * 668265263 + (k || 0) * 2246822519) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }
  // smooth value noise across tiles: broad patches of colour instead of per-tile speckle
  function vnoise(x, y, k, sc) {
    const fx = x / sc, fy = y / sc, ix = Math.floor(fx), iy = Math.floor(fy);
    const tx = fx - ix, ty = fy - iy, sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    const a = rndAt(ix, iy, k), b = rndAt(ix + 1, iy, k), c = rndAt(ix, iy + 1, k), d = rndAt(ix + 1, iy + 1, k);
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
  }
  const px = (c, x, y, w, h, col) => { c.fillStyle = col; c.fillRect(x, y, w, h); };
  // pixel-exact shapes, so nothing is antialiased into mush
  function pell(c, cx, cy, rx, ry, col, half) {
    c.fillStyle = col;
    for (let dy = -ry; dy <= ry; dy++) {
      if (half === 'top' && dy > 0) break;
      if (half === 'bottom' && dy < 0) continue;
      const w = Math.round(rx * Math.sqrt(Math.max(0, 1 - (dy / (ry + 0.5)) * (dy / (ry + 0.5)))));
      if (w > 0) c.fillRect(Math.round(cx - w), Math.round(cy + dy), w * 2, 1);
    }
  }
  // rows y0..y1, left and right edges interpolated linearly from (l0,r0) to (l1,r1)
  function trap(c, col, y0, y1, l0, r0, l1, r1) {
    c.fillStyle = col;
    const n = Math.max(1, y1 - y0);
    for (let yy = y0; yy < y1; yy++) {
      const k = (yy - y0) / n;
      const l = Math.round(l0 + (l1 - l0) * k), r = Math.round(r0 + (r1 - r0) * k);
      if (r > l) c.fillRect(l, yy, r - l, 1);
    }
  }
  const sh = (c, k) => G.shade(c, k);

  // ---------------------------------------------------------------- ground
  function ground(c, ch, X, Y, x, y, b, fr, map) {
    const r = (k) => rndAt(X, Y, k);
    const at = (dx, dy) => map && map.at(X + dx, Y + dy);
    const kind = { '.': b.plain, ',': 'cobble', '=': 'road', s: 'sand', '*': 'snowdrift', a: 'carpet', w: 'wood', p: 'pier', '^': 'hill', r: 'rubble', g: 'flowers', i: 'bells', b: 'bridge', '<': 'stairs' }[ch];
    const drift = (k) => (vnoise(X, Y, k, 4) - 0.5);
    const base = (k) => {
      switch (k) {
        case 'grass': case 'gorse': case 'violet': {
          const g0 = sh(b.grass, drift(1) * 0.16);
          px(c, x, y, S, S, g0);
          const gd = sh(g0, -0.09), gl = sh(g0, 0.09);
          for (let i = 0; i < 5; i++) px(c, x + ((r(i) * 23) | 0), y + ((r(i + 20) * 23) | 0), 1, 1, i % 2 ? gd : gl);
          const tufts = r(50) < 0.5 ? (r(53) < 0.35 ? 2 : 1) : 0;
          for (let i = 0; i < tufts; i++) {
            const tx = x + 3 + ((r(51 + i * 3) * 16) | 0), ty = y + 6 + ((r(52 + i * 3) * 13) | 0);
            px(c, tx, ty, 1, 3, b.grassD); px(c, tx + 2, ty + 1, 1, 2, b.grassD); px(c, tx + 1, ty - 1, 1, 4, b.grassL); px(c, tx + 3, ty, 1, 3, b.grassL);
          }
          if (k === 'gorse' && r(60) < 0.4) {
            const gx = x + 3 + ((r(61) * 16) | 0), gy = y + 4 + ((r(62) * 15) | 0);
            px(c, gx, gy, 3, 2, '#d8b830'); px(c, gx + 1, gy - 1, 2, 1, '#e8c840'); px(c, gx + 1, gy, 1, 1, '#fff0a0');
          }
          if (k === 'violet' && r(63) < 0.45) {
            const vx = x + 3 + ((r(64) * 17) | 0), vy = y + 3 + ((r(65) * 17) | 0);
            px(c, vx, vy - 1, 1, 3, '#b48ae8'); px(c, vx - 1, vy, 3, 1, '#b48ae8'); px(c, vx, vy, 1, 1, '#f0e0ff');
          }
          break;
        }
        case 'snowstone': case 'dstone': case 'bone': {
          px(c, x, y, S, S, b.groundD);
          for (let row = 0; row < 2; row++) {
            const off = ((Y * 2 + row) % 2) * 6;
            for (let k2 = -1; k2 < 2; k2++) {
              const sx = x + off + k2 * 12, x0 = Math.max(sx, x), x1 = Math.min(sx + 11, x + S);
              if (x1 <= x0) continue;
              const gi = X * 2 + Math.floor((off + k2 * 12) / 12);
              const col = sh(b.ground, (rndAt(gi, Y * 2 + row, 10) - 0.5) * 0.09 + drift(2) * 0.08);
              px(c, x0, y + row * 12, x1 - x0, 11, col);
              if (sx >= x) px(c, x0, y + row * 12, x1 - x0, 1, sh(col, 0.12));
            }
          }
          if (k === 'snowstone') {
            if (r(70) < 0.45) { const sx = x + 2 + ((r(71) * 12) | 0), sy = y + 6 + ((r(72) * 12) | 0); pell(c, sx + 4, sy, 5, 1, '#e4e8f6'); px(c, sx + 1, sy - 1, 5, 1, '#f6f8ff'); }
          }
          if (k === 'dstone' && r(75) < 0.3) { const cx = x + 4 + ((r(76) * 12) | 0), cy = y + 4 + ((r(77) * 14) | 0); px(c, cx, cy, 3, 1, b.groundD); px(c, cx + 2, cy + 1, 3, 1, b.groundD); px(c, cx + 4, cy + 2, 1, 2, b.groundD); }
          break;
        }
        case 'marble': {
          const m = sh(b.ground, ((X + Y) % 2 ? -0.025 : 0.01));
          px(c, x, y, S, S, m);
          px(c, x, y, S, 1, b.groundL); px(c, x, y, 1, S, b.groundL);
          px(c, x + S - 1, y, 1, S, b.groundD); px(c, x, y + S - 1, S, 1, b.groundD);
          if (r(1) < 0.4) { let vx = x + 4 + ((r(2) * 8) | 0); for (let vy = 3; vy < 21; vy += 2) { px(c, vx, y + vy, 1, 2, sh(m, -0.06)); vx += r(vy) < 0.5 ? 1 : -1; } }
          break;
        }
        case 'snow': {
          const s0 = sh(b.ground, drift(3) * 0.06);
          px(c, x, y, S, S, s0);
          for (let i = 0; i < 3; i++) px(c, x + ((r(i) * 18) | 0), y + ((r(i + 9) * 22) | 0), 3 + ((r(i + 4) * 3) | 0), 1, b.groundD);
          if (r(30) < 0.5) px(c, x + ((r(31) * 22) | 0), y + ((r(32) * 22) | 0), 1, 1, '#ffffff');
          break;
        }
        case 'salt': {
          px(c, x, y, S, S, b.ground);
          px(c, x + ((r(1) * 10) | 0), y + ((r(2) * 20) | 0) + 2, 8, 1, b.groundD);
          px(c, x + ((r(3) * 18) | 0) + 2, y + ((r(4) * 12) | 0), 1, 6, b.groundD);
          if (r(5) < 0.3) px(c, x + 11, y + 11, 1, 1, '#ffffff');
          break;
        }
        case 'wood': {
          for (let k2 = 0; k2 < 4; k2++) {
            const col = sh(b.ground, (rndAt(X, Y * 4 + k2, 7) - 0.5) * 0.1);
            px(c, x, y + k2 * 6, S, 6, col);
            px(c, x, y + k2 * 6, S, 1, sh(col, 0.1));
            px(c, x, y + k2 * 6 + 5, S, 1, b.groundD);
            const sx = (rndAt(X, Y * 4 + k2, 8) * 22) | 0;
            if ((X + k2) % 2) { px(c, x + sx, y + k2 * 6, 1, 5, b.groundD); px(c, x + sx + 2, y + k2 * 6 + 2, 1, 1, sh(b.groundD, -0.2)); }
          }
          break;
        }
        case 'cobble': {
          px(c, x, y, S, S, b.cobD);
          for (let yy = 0; yy < 4; yy++) for (let xx = -1; xx < 4; xx++) {
            const ox = (yy % 2) * 3, sx = x + xx * 6 + ox, sy = y + yy * 6;
            const col = rndAt(X * 4 + xx, Y * 4 + yy, 11) < 0.5 ? b.cob : sh(b.cob, -0.07);
            const cl = (x0, w) => { const a = Math.max(x0, x), z = Math.min(x0 + w, x + S); return [a, z - a]; };
            let [ax, aw] = cl(sx + 1, 3); if (aw > 0) px(c, ax, sy, aw, 1, b.cobL);
            [ax, aw] = cl(sx, 5); if (aw > 0) px(c, ax, sy + 1, aw, 3, col);
            [ax, aw] = cl(sx + 1, 3); if (aw > 0) px(c, ax, sy + 4, aw, 1, sh(col, -0.1));
          }
          if (b.snow && r(90) < 0.3) { const sx = x + ((r(91) * 14) | 0), sy = y + 4 + ((r(92) * 16) | 0); px(c, sx, sy, 6, 1, '#e8ecf8'); px(c, sx + 1, sy - 1, 3, 1, '#f6f8ff'); }
          break;
        }
        case 'road': {
          const r0 = sh(b.road, drift(4) * 0.08);
          px(c, x, y, S, S, r0);
          for (let i = 0; i < 4; i++) { const qx = x + ((r(i) * 21) | 0), qy = y + ((r(i + 9) * 21) | 0); px(c, qx, qy, 2, 1, sh(r0, -0.14)); px(c, qx, qy - 1, 2, 1, sh(r0, 0.1)); }
          const isR = (ch2) => ch2 === '=' || ch2 === ',' || ch2 === 'b' || ch2 === 'H' || ch2 === 'S' || ch2 === '<';
          const rut = sh(r0, -0.07);
          if (isR(at(0, -1)) || isR(at(0, 1))) { px(c, x + 7, y, 1, S, rut); px(c, x + 16, y, 1, S, rut); }
          else { px(c, x, y + 8, S, 1, rut); px(c, x, y + 16, S, 1, rut); }
          const edge = sh(r0, -0.16);
          if (at(-1, 0) && !isR(at(-1, 0))) px(c, x, y, 1, S, edge);
          if (at(1, 0) && !isR(at(1, 0))) px(c, x + S - 1, y, 1, S, edge);
          if (at(0, -1) && !isR(at(0, -1))) px(c, x, y, S, 1, edge);
          if (at(0, 1) && !isR(at(0, 1))) px(c, x, y + S - 1, S, 1, edge);
          break;
        }
        case 'sand': {
          const sd = b.sand || '#e0cc90';
          px(c, x, y, S, S, sh(sd, drift(5) * 0.07));
          for (let k2 = 0; k2 < 3; k2++) {
            const ry = y + 4 + k2 * 8 + ((r(k2) * 3) | 0);
            for (let xx = 0; xx < S; xx += 2) px(c, x + xx, ry + (Math.sin((X * S + xx) / 5) > 0 ? 1 : 0), 2, 1, sh(sd, -0.1));
          }
          if (r(20) < 0.25) px(c, x + 4 + ((r(21) * 15) | 0), y + 4 + ((r(22) * 15) | 0), 2, 1, '#f4ead0');
          break;
        }
        case 'snowdrift': {
          base(b.plain === 'snow' ? 'snow' : b.plain);
          pell(c, x + 12, y + 15, 11, 6, '#c8d0e4');
          pell(c, x + 12, y + 14, 10, 5, '#eef2fc');
          px(c, x + 5, y + 10, 9, 1, '#ffffff');
          break;
        }
        case 'carpet': {
          const cp = b.carpet || '#8e2f4a';
          px(c, x, y, S, S, cp);
          const isC = (ch2) => ch2 === 'a' || ch2 === 'G';
          const gold = G.C.gold;
          if (!isC(at(-1, 0))) { px(c, x, y, 2, S, sh(cp, -0.3)); px(c, x + 2, y, 1, S, gold); }
          if (!isC(at(1, 0))) { px(c, x + S - 2, y, 2, S, sh(cp, -0.3)); px(c, x + S - 3, y, 1, S, gold); }
          if (!isC(at(0, -1))) { px(c, x, y, S, 1, gold); }
          if (!isC(at(0, 1))) { px(c, x, y + S - 1, S, 1, gold); }
          px(c, x + 11, y + 9, 2, 6, sh(cp, 0.12)); px(c, x + 9, y + 11, 6, 2, sh(cp, 0.12));
          break;
        }
        case 'pier': {
          for (let k2 = 0; k2 < 4; k2++) {
            const col = sh('#7a5a3a', (rndAt(X * 4 + k2, Y, 12) - 0.5) * 0.12);
            px(c, x + k2 * 6, y, 6, S, col); px(c, x + k2 * 6, y, 1, S, '#5a3e26');
            px(c, x + k2 * 6 + 3, y + 2, 1, 1, '#3a2818'); px(c, x + k2 * 6 + 3, y + 21, 1, 1, '#3a2818');
          }
          break;
        }
        case 'hill': {
          base(b.plain === 'snowstone' ? 'snow' : b.plain);
          const hc = b.grass || b.ground;
          pell(c, x + 12, y + 17, 12, 10, sh(hc, -0.16), 'top');
          pell(c, x + 12, y + 17, 11, 9, sh(hc, -0.04), 'top');
          pell(c, x + 10, y + 13, 6, 4, sh(hc, 0.1), 'top');
          px(c, x + 6, y + 10, 5, 1, sh(hc, 0.2));
          px(c, x + 1, y + 17, 22, 1, sh(hc, -0.2));
          break;
        }
        case 'rubble': {
          base(b.plain);
          for (let i = 0; i < 4; i++) {
            const rx = x + 2 + ((r(i) * 16) | 0), ry = y + 4 + ((r(i + 9) * 15) | 0), w = 3 + ((r(i + 4) * 3) | 0);
            px(c, rx, ry + 1, w, 2, b.wallD); px(c, rx, ry, w, 2, b.wallF); px(c, rx, ry, w - 1, 1, b.wallT);
          }
          break;
        }
        case 'flowers': {
          base(b.plain);
          const cols = ['#ff7aa0', '#ffe070', '#ffffff', '#c890ff'];
          for (let i = 0; i < 5; i++) {
            const fx = x + 3 + ((r(i) * 17) | 0), fy = y + 3 + ((r(i + 9) * 17) | 0), col = cols[(i + X) % 4];
            px(c, fx, fy + 2, 1, 2, b.grassD || '#3a6a3a');
            px(c, fx - 1, fy, 3, 1, col); px(c, fx, fy - 1, 1, 3, col); px(c, fx, fy, 1, 1, '#ffd84a');
          }
          break;
        }
        case 'bells': {
          base(b.plain);
          for (let i = 0; i < 4; i++) {
            const fx = x + 3 + ((r(i) * 16) | 0), fy = y + 4 + ((r(i + 9) * 14) | 0);
            px(c, fx + 1, fy - 2, 1, 2, '#4a6a5a'); px(c, fx, fy, 3, 3, '#8a6aff'); px(c, fx, fy + 3, 1, 1, '#8a6aff'); px(c, fx + 2, fy + 3, 1, 1, '#8a6aff'); px(c, fx, fy, 1, 1, '#e0d0ff');
          }
          break;
        }
        case 'bridge': {
          waterTile(c, X, Y, x, y, b, fr, map);
          const solid = (ch2) => ch2 && !TL.isWater(ch2);
          const vert = at(0, -1) === 'b' || at(0, 1) === 'b' ? !(at(-1, 0) === 'b' || at(1, 0) === 'b') : (solid(at(0, -1)) || solid(at(0, 1)));
          if (vert) {
            px(c, x + 3, y, 18, S, '#8a6a46');
            for (let k2 = 0; k2 < S; k2 += 4) px(c, x + 3, y + k2 + 3, 18, 1, '#6a4e32');
            px(c, x + 2, y, 2, S, '#4a3420'); px(c, x + 20, y, 2, S, '#4a3420');
            px(c, x + 3, y, 1, S, '#a88a62');
          } else {
            px(c, x, y + 3, S, 18, '#8a6a46');
            for (let k2 = 0; k2 < S; k2 += 4) px(c, x + k2 + 3, y + 3, 1, 18, '#6a4e32');
            px(c, x, y + 3, S, 1, '#a88a62'); px(c, x, y + 20, S, 2, '#4a3420');
          }
          break;
        }
        case 'stairs': {
          base(b.plain);
          for (let k2 = 0; k2 < 5; k2++) { px(c, x + 3, y + 2 + k2 * 4, 18, 4, sh(b.wallF, -k2 * 0.1)); px(c, x + 3, y + 2 + k2 * 4, 18, 1, sh(b.wallT, -k2 * 0.08)); }
          px(c, x + 2, y + 2, 1, 20, b.wallD); px(c, x + 21, y + 2, 1, 20, b.wallD);
          break;
        }
        default: px(c, x, y, S, S, b.ground || b.grass);
      }
    };
    const t = T[ch];
    if (t && (t.water) && ch !== 'f') { if (ch === '%') springTile(c, X, Y, x, y, b, fr); else waterTile(c, X, Y, x, y, b, fr, map, ch === '-'); return; }
    if (ch === 'x') { voidTile(c, X, Y, x, y, fr); return; }
    // a free-standing prop stands on whatever ground surrounds it, not on a patch of its own
    if (t && t.prop && STRUCT.indexOf(ch) < 0 && map) {
      const u = under(map, X, Y);
      if (u !== '.') { ground(c, u, X, Y, x, y, b, fr, map); return; }
    }
    if (kind) base(kind); else base(b.plain);
  }
  const GROUNDS = '.,=s*awpg';
  function under(map, X, Y) {
    const n = {};
    [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(([dx, dy]) => { const ch = map.at(X + dx, Y + dy); if (ch && GROUNDS.indexOf(ch) >= 0) n[ch] = (n[ch] || 0) + 1; });
    let best = '.', bn = 0;
    Object.keys(n).forEach((k) => { if (n[k] > bn) { best = k; bn = n[k]; } });
    return best;
  }
  TL.isWater = (ch) => ch === '~' || ch === '-' || ch === 'b';

  // fr runs 0..3; the waves slide two pixels a frame
  function waterTile(c, X, Y, x, y, b, fr, map, shallow) {
    const w0 = shallow ? G.mix(b.water, b.waterL, 0.4) : sh(b.water, (vnoise(X, Y, 6, 3) - 0.5) * 0.12);
    px(c, x, y, S, S, w0);
    for (let i = 0; i < 3; i++) {
      const wy = y + 4 + i * 8 + ((rndAt(X, Y, i + 30) * 3) | 0);
      const wx = (((X * 11 + i * 7 + fr * 2) % S) + S) % S;
      const len = 4 + ((rndAt(X, Y, i + 40) * 3) | 0);
      for (let k = 0; k < len; k++) px(c, x + ((wx + k) % S), wy, 1, 1, b.waterL);
      px(c, x + ((wx + 1) % S), wy + 1, Math.max(1, len - 2), 1, sh(w0, -0.08));
    }
    if (rndAt(X, Y, 3) < 0.2 && fr % 2 === 0) px(c, x + ((rndAt(X, Y, 4) * 22) | 0), y + ((rndAt(X, Y, 5) * 22) | 0), 1, 1, '#ffffff');
    // the land casts a band of shade, then foam laps the edge
    if (map) {
      const land = (dx, dy) => { const ch = map.at(X + dx, Y + dy); return ch && !TL.isWater(ch) && ch !== '%'; };
      const foam = '#dfeeff';
      const lap = fr % 2;
      if (land(0, -1)) { px(c, x, y, S, 3, b.waterD); px(c, x, y + 3, S, 1, foam); for (let k = lap; k < S; k += 4) px(c, x + k, y + 4, 2, 1, foam); }
      if (land(0, 1)) { px(c, x, y + S - 1, S, 1, foam); for (let k = lap * 2; k < S; k += 5) px(c, x + k, y + S - 2, 2, 1, foam); }
      if (land(-1, 0)) { px(c, x, y, 1, S, foam); for (let k = lap; k < S; k += 4) px(c, x + 1, y + k, 1, 2, foam); }
      if (land(1, 0)) { px(c, x + S - 1, y, 1, S, foam); for (let k = 1 - lap; k < S; k += 4) px(c, x + S - 2, y + k, 1, 2, foam); }
    }
  }
  function springTile(c, X, Y, x, y, b, fr) {
    px(c, x, y, S, S, '#4aa8b8');
    px(c, x, y, S, 2, '#e8e2d6'); px(c, x, y + S - 2, S, 2, '#bab2a0');
    px(c, x, y + 2, S, 1, '#2a7888');
    for (let i = 0; i < 3; i++) px(c, x + ((X * 5 + i * 8 + fr * 2) % 19), y + 6 + i * 6, 4, 1, '#9ae8f0');
    const st = ['rgba(255,255,255,0.5)', 'rgba(255,255,255,0.35)'];
    px(c, x + 5 + fr, y + 8 - fr, 2, 2, st[0]); px(c, x + 15 - fr, y + 12 - fr, 2, 2, st[1]);
  }
  function voidTile(c, X, Y, x, y, fr) {
    px(c, x, y, S, S, '#8e939a');
    for (let i = 0; i < 4; i++) px(c, x + ((rndAt(X, Y, i) * 22) | 0), y + ((rndAt(X, Y, i + 7) * 22) | 0), 3, 1, fr % 2 ? '#a4a9b0' : '#7e838a');
  }

  // ---------------------------------------------------------------- props (drawn into row canvases)
  // (x, y) is the top-left of the tile inside the row canvas; there are HEAD px of headroom above.
  // Structural props (walls, roofs, doors) join their neighbours and are drawn straight in;
  // free-standing ones are drawn on a separate layer that gets a dark outline.
  const STRUCT = '#KBnD';
  function prop(c, ch, X, Y, x, y, b, map, state, night) {
    const r = (k) => rndAt(X, Y, k);
    const at = (dx, dy) => map.at(X + dx, Y + dy);
    switch (ch) {
      case 'T': case 'j': {
        if (b.dead) {
          px(c, x + 11, y - 2, 3, 24, b.trunk); px(c, x + 12, y - 2, 1, 24, sh(b.trunk, 0.25));
          px(c, x + 5, y + 4, 6, 1, b.trunk); px(c, x + 4, y + 2, 1, 2, b.trunk);
          px(c, x + 14, y, 6, 1, b.trunk); px(c, x + 19, y - 3, 1, 3, b.trunk);
          px(c, x + 7, y - 6, 1, 6, b.trunk); px(c, x + 15, y + 8, 4, 1, b.trunk);
          break;
        }
        px(c, x + 11, y + 10, 3, 13, b.trunk); px(c, x + 11, y + 10, 1, 13, sh(b.trunk, 0.22));
        px(c, x + 10, y + 21, 5, 2, sh(b.trunk, -0.15));
        if (b.pine && ch === 'T') {
          const tiers = [[-14, 4], [-8, 7], [-2, 9], [4, 11]];
          tiers.forEach(([ty, hw], k) => {
            trap(c, k % 2 ? b.tree : b.treeD, y + ty, y + ty + 8, x + 12 - 1, x + 12 + 1, x + 12 - hw, x + 12 + hw);
            trap(c, b.treeL, y + ty + 1, y + ty + 7, x + 11, x + 12, x + 12 - hw + 1, x + 12 - hw + 3);
          });
          if (b.snowcap) { px(c, x + 11, y - 14, 2, 1, '#ffffff'); px(c, x + 10, y - 13, 4, 2, '#f4f6ff'); }
        } else {
          const col = ch === 'j' ? '#7a9a8a' : b.tree, colL = ch === 'j' ? '#a8c8b8' : b.treeL;
          pell(c, x + 12, y + 3, 11, 10, b.treeD);
          pell(c, x + 11, y + 1, 10, 9, col);
          pell(c, x + 8, y - 3, 5, 4, colL);
          // leaf clusters break up the silhouette
          [[3, 6], [16, 4], [9, 9], [18, -2], [5, -4]].forEach(([dx, dy], i) => { px(c, x + dx, y + dy, 3, 2, i % 2 ? b.treeD : sh(col, -0.08)); px(c, x + dx, y + dy - 1, 2, 1, colL); });
          if (ch === 'j') { [[5, 5], [15, 2], [11, 8]].forEach(([dx, dy]) => { px(c, x + dx, y + dy, 2, 3, '#e4e8a8'); px(c, x + dx, y + dy, 1, 1, '#ffffff'); }); }
          if (b.snow) { px(c, x + 4, y - 7, 12, 2, '#eef2fc'); px(c, x + 7, y - 8, 6, 1, '#ffffff'); }
          if (b.motes && r(5) < 0.6) px(c, x + 4 + ((r(6) * 14) | 0), y - 3 + ((r(7) * 10) | 0), 1, 1, '#ffe28a');
        }
        break;
      }
      case 'R': {
        pell(c, x + 12, y + 15, 11, 8, sh(b.bush, -0.15));
        pell(c, x + 11, y + 14, 10, 7, b.bush);
        pell(c, x + 8, y + 11, 4, 3, sh(b.bush, 0.18));
        [[5, 10], [14, 9], [10, 15], [17, 15], [4, 17], [12, 11]].forEach(([dx, dy], i) => {
          px(c, x + dx, y + dy, 3, 3, b.rose); px(c, x + dx + 1, y + dy + 1, 1, 1, sh(b.rose, -0.3));
          if (i % 2) px(c, x + dx, y + dy, 1, 1, '#ffffff');
        });
        break;
      }
      case '#': case 'K': {
        const isW = (ch2) => ch2 === '#' || ch2 === 'K' || ch2 === 'D';
        const wallBelow = isW(at(0, 1)), wallAbove = isW(at(0, -1));
        const top = wallAbove ? 0 : -9;
        const edgeL = !isW(at(-1, 0)), edgeR = !isW(at(1, 0));
        if (wallBelow) {
          px(c, x, y + top, S, S - top, b.wallT);
          if (!wallAbove) px(c, x, y + top, S, 1, sh(b.wallT, 0.15));
        } else {
          px(c, x, y + top, S, 10 - top, b.wallT);
          if (!wallAbove) px(c, x, y + top, S, 1, sh(b.wallT, 0.15));
          px(c, x, y + 10, S, 14, b.wallF);
          px(c, x, y + 10, S, 1, b.wallD);
          for (let k = 0; k < 3; k++) {
            const cy = y + 14 + k * 4;
            px(c, x, cy, S, 1, sh(b.wallF, -0.12));
            const off = ((k + Y) % 2) * 6 + (X % 2) * 12;
            for (let jx = off % 12; jx < S; jx += 12) px(c, x + jx, cy - 3, 1, 3, sh(b.wallF, -0.12));
          }
          px(c, x, y + 23, S, 1, b.wallD);
          if (ch === 'K') {
            px(c, x + 5, y + 12, 14, 11, '#1a1020'); px(c, x + 7, y + 11, 10, 1, '#1a1020');
            const cols = ['#ff3a3a', '#ffcf3a', '#3a8aff', '#ff3a3a', '#a84aff'];
            for (let i = 0; i < 4; i++) px(c, x + 6 + i * 3, y + 13, 2, 9, cols[(i + X) % 5]);
            px(c, x + 6, y + 17, 12, 1, '#1a1020');
          }
        }
        if (edgeL) px(c, x, y + top, 1, S - top, sh(b.wallT, -0.14));
        if (edgeR) px(c, x + S - 1, y + top, 1, S - top, sh(b.wallT, -0.22));
        if (b.snow && !wallAbove) { px(c, x, y + top, S, 2, '#eef2fc'); px(c, x + ((r(1) * 16) | 0), y + top + 2, 4, 1, '#eef2fc'); }
        break;
      }
      case 'B': case 'n': {
        const isB = (ch2) => ch2 === 'B' || ch2 === 'n';
        const below = isB(at(0, 1)), above = isB(at(0, -1));
        const top = above ? 0 : -8;
        const roofEnd = below ? S : 9;
        px(c, x, y + top, S, roofEnd - top, b.roof);
        // shingles: staggered rows, each with a shadowed lower lip
        for (let yy = top + 2; yy < roofEnd; yy += 4) {
          px(c, x, y + yy + 2, S, 1, b.roofD);
          const off = ((yy - top) / 4) % 2 ? 3 : 0;
          for (let xx = off; xx < S; xx += 6) px(c, x + xx, y + yy, 1, 3, b.roofD);
        }
        if (!above) { px(c, x, y + top, S, 2, b.roofL); if (b.snow) { px(c, x, y + top, S, 2, '#eef2fc'); px(c, x + 3, y + top + 2, 7, 1, '#eef2fc'); } }
        if (!isB(at(-1, 0))) px(c, x, y + top, 1, roofEnd - top, b.roofD);
        if (!isB(at(1, 0))) px(c, x + S - 1, y + top, 1, roofEnd - top, sh(b.roofD, -0.15));
        if (!below) {
          px(c, x, y + 9, S, 15, b.wallT);
          px(c, x, y + 9, S, 2, sh(b.roofD, -0.2));
          px(c, x, y + 23, S, 1, b.wallD);
          const lit = night ? (r(3) < 0.65) : false;
          const wc = lit ? b.win : sh(b.wallF, -0.4);
          [5, 15].forEach((wx) => {
            px(c, wx + x - 1, y + 12, 6, 8, sh(b.wallT, -0.25));
            px(c, wx + x, y + 13, 4, 6, wc); px(c, wx + x, y + 16, 4, 1, sh(b.wallT, -0.25)); px(c, wx + x + 2, y + 13, 1, 6, sh(b.wallT, -0.25));
            if (!lit) px(c, wx + x, y + 13, 1, 1, sh(wc, 0.4));
          });
          if (ch === 'n') {
            const col = ['#ff5fa8', '#ffd84a', '#5fe8ff'][(X + Y) % 3];
            px(c, x + 2, y + 9, 20, 3, col); px(c, x + 3, y + 10, 18, 1, '#ffffff');
          }
        }
        break;
      }
      case 'H': case 'S': {
        const roofC = ch === 'S' ? '#4a6a9a' : b.house;
        px(c, x + 2, y + 9, 20, 15, b.wallT);
        px(c, x + 2, y + 23, 20, 1, b.wallD);
        px(c, x + 21, y + 9, 1, 15, b.wallD);
        if (ch === 'H') { px(c, x + 15, y - 6, 3, 7, sh(b.wallF, -0.2)); px(c, x + 15, y - 6, 3, 1, sh(b.wallT, 0)); }
        trap(c, sh(roofC, -0.3), y - 5, y + 11, x + 11, x + 13, x - 1, x + 25);
        trap(c, roofC, y - 4, y + 10, x + 11, x + 13, x, x + 24);
        trap(c, sh(roofC, 0.18), y - 4, y + 10, x + 11, x + 12, x, x + 4);
        for (let k = 0; k < 3; k++) px(c, x + 6 - k * 2, y + 1 + k * 3, 12 + k * 4, 1, sh(roofC, -0.18));
        if (b.snow) { px(c, x + 8, y - 3, 8, 2, '#eef2fc'); px(c, x + 5, y + 1, 4, 1, '#eef2fc'); }
        const done = state && state.visited && state.visited[X + ',' + Y];
        px(c, x + 9, y + 14, 6, 10, sh('#6a4228', -0.3));
        px(c, x + 10, y + 15, 4, 9, done ? '#3a2a2a' : '#6a4228'); px(c, x + 13, y + 19, 1, 1, G.C.gold);
        const wc = night ? b.win : '#7a8aa0';
        px(c, x + 3, y + 13, 5, 5, sh(b.wallT, -0.3)); px(c, x + 4, y + 14, 3, 3, wc);
        px(c, x + 16, y + 13, 5, 5, sh(b.wallT, -0.3)); px(c, x + 17, y + 14, 3, 3, wc);
        if (ch === 'S') { px(c, x + 6, y + 9, 12, 4, '#3a2a1a'); px(c, x + 7, y + 10, 10, 2, '#e8c170'); px(c, x + 11, y + 10, 2, 2, '#fff2c0'); }
        break;
      }
      case 'F': {
        px(c, x + 1, y - 2, 22, 26, b.wallF);
        px(c, x + 1, y - 2, 22, 3, b.wallT);
        for (let k = 0; k < 4; k++) { px(c, x + 1 + k * 6, y - 6, 4, 4, b.wallT); px(c, x + 1 + k * 6, y - 6, 4, 1, sh(b.wallT, 0.15)); }
        for (let k = 0; k < 4; k++) px(c, x + 1, y + 4 + k * 5, 22, 1, sh(b.wallF, -0.12));
        px(c, x + 22, y - 2, 1, 26, b.wallD);
        px(c, x + 8, y + 11, 8, 13, '#2a1e1a'); px(c, x + 9, y + 10, 6, 1, '#2a1e1a');
        px(c, x + 11, y - 18, 1, 13, '#5a4a3a'); px(c, x + 12, y - 18, 8, 5, '#c83a4a'); px(c, x + 12, y - 18, 8, 1, '#e86a6a');
        break;
      }
      case 'G': {
        if (b.plain === 'wood' || b.plain === 'marble' || b.plain === 'bone' || b.plain === 'dstone') {
          px(c, x + 5, y - 6, 14, 20, '#8e2f4a'); px(c, x + 5, y - 6, 14, 2, G.C.gold);
          px(c, x + 5, y - 6, 1, 20, G.C.gold); px(c, x + 18, y - 6, 1, 20, G.C.gold);
          px(c, x + 3, y + 9, 18, 8, '#6a1e34'); px(c, x + 3, y + 9, 18, 1, '#a84a64');
          px(c, x + 3, y + 9, 2, 13, G.C.gold); px(c, x + 19, y + 9, 2, 13, G.C.gold);
          px(c, x + 11, y - 9, 2, 3, G.C.gold); px(c, x + 10, y - 8, 4, 1, G.C.gold);
        } else {
          px(c, x + 11, y - 14, 2, 36, '#6a5a4a'); px(c, x + 11, y - 14, 1, 36, '#8a7a6a');
          px(c, x + 13, y - 13, 9, 7, '#e8607e'); px(c, x + 13, y - 13, 9, 1, '#ffffff'); px(c, x + 19, y - 7, 3, 2, '#e8607e');
          px(c, x + 8, y + 20, 8, 3, '#4a3a2a');
        }
        break;
      }
      case 'M': {
        trap(c, b.wallF, y - 16, y + 24, x + 11, x + 13, x - 3, x + 27);
        trap(c, b.wallD, y - 16, y + 24, x + 12, x + 13, x + 13, x + 27);
        trap(c, sh(b.wallF, 0.12), y - 12, y + 10, x + 11, x + 12, x + 4, x + 7);
        trap(c, '#f4f6ff', y - 16, y - 3, x + 11, x + 13, x + 6, x + 18);
        trap(c, '#c8d0e4', y - 15, y - 3, x + 12, x + 13, x + 12, x + 18);
        break;
      }
      case 'P': {
        px(c, x + 6, y - 16, 12, 37, b.wallT);
        px(c, x + 15, y - 16, 3, 37, b.wallD);
        px(c, x + 9, y - 16, 1, 37, sh(b.wallT, 0.12)); px(c, x + 12, y - 16, 1, 37, sh(b.wallT, -0.08));
        px(c, x + 4, y - 20, 16, 4, b.wallT); px(c, x + 4, y - 20, 16, 1, sh(b.wallT, 0.15)); px(c, x + 4, y - 17, 16, 1, b.wallD);
        px(c, x + 4, y + 19, 16, 4, b.wallF); px(c, x + 4, y + 19, 16, 1, sh(b.wallT, 0.1));
        break;
      }
      case 'L': {
        px(c, x + 11, y - 10, 2, 32, '#2a2a36'); px(c, x + 11, y - 10, 1, 32, '#4a4a5a');
        px(c, x + 8, y + 20, 8, 3, '#2a2a36');
        px(c, x + 8, y - 17, 8, 8, '#1e1e28');
        px(c, x + 9, y - 16, 6, 5, '#ffe8a8'); px(c, x + 10, y - 16, 3, 2, '#ffffff');
        px(c, x + 7, y - 18, 10, 2, '#2a2a36'); px(c, x + 11, y - 20, 2, 2, '#2a2a36');
        break;
      }
      case 't': {
        px(c, x, y + 6, S, 14, '#6a4228');
        px(c, x, y + 4, S, 4, '#c8a070'); px(c, x, y + 4, S, 1, '#e8c898');
        for (let k = 3; k < S; k += 7) px(c, x + k, y + 9, 1, 10, '#4a2c18');
        px(c, x, y + 19, S, 1, '#3a2418');
        if (r(1) < 0.4) { px(c, x + 7, y - 1, 5, 5, '#f4f0e8'); px(c, x + 7, y + 3, 5, 1, '#c8a070'); px(c, x + 8, y, 3, 1, '#a8d8f0'); }
        break;
      }
      case 'f': {
        pell(c, x + 12, y + 16, 12, 7, b.wallD);
        pell(c, x + 12, y + 15, 11, 6, b.wallF);
        pell(c, x + 12, y + 14, 9, 4, b.water);
        px(c, x + 6, y + 13, 6, 1, b.waterL);
        px(c, x + 11, y - 2, 3, 16, b.wallT); px(c, x + 13, y - 2, 1, 16, b.wallD);
        px(c, x + 9, y - 6, 7, 3, b.waterL); px(c, x + 7, y - 4, 1, 6, b.waterL); px(c, x + 17, y - 4, 1, 6, b.waterL);
        px(c, x + 11, y - 7, 3, 1, '#ffffff');
        break;
      }
      case 'o': {
        pell(c, x + 12, y + 15, 11, 8, b.wallD);
        pell(c, x + 11, y + 13, 10, 8, b.wallF);
        pell(c, x + 8, y + 10, 5, 3, b.wallT);
        px(c, x + 13, y + 14, 4, 1, b.wallD); px(c, x + 16, y + 15, 1, 3, b.wallD);
        if (b.snow) { px(c, x + 5, y + 6, 11, 2, '#eef2fc'); px(c, x + 7, y + 5, 6, 1, '#ffffff'); }
        break;
      }
      case 'k': {
        for (let i = 0; i < 4; i++) {
          const bx = x + 1 + i * 5, top = y - 6 + ((i * 7 + X) % 4) * 3;
          trap(c, i % 2 ? '#1a1428' : '#2a2040', top, y + 23, bx + 3, bx + 5, bx, bx + 8);
          px(c, bx + 4, top + 2, 1, 8, '#6a5aa0');
        }
        break;
      }
      case 'c': {
        px(c, x + 2, y + 8, 20, 15, '#8a6440'); px(c, x + 2, y + 8, 20, 1, '#b08a5a');
        px(c, x + 2, y + 15, 20, 1, '#5a4028'); px(c, x + 11, y + 8, 1, 15, '#5a4028');
        px(c, x + 2, y + 8, 1, 15, '#5a4028'); px(c, x + 21, y + 8, 1, 15, '#4a3020');
        if (r(2) < 0.5) {
          px(c, x + 5, y - 3, 13, 11, '#9a7450'); px(c, x + 5, y - 3, 13, 1, '#c09a6a');
          px(c, x + 5, y + 2, 13, 1, '#5a4028'); px(c, x + 5, y - 3, 1, 11, '#5a4028'); px(c, x + 17, y - 3, 1, 11, '#4a3020');
        }
        break;
      }
      case 'C': {
        const open = state && state.opened && state.opened[X + ',' + Y];
        px(c, x + 4, y + 11, 16, 11, '#7a4a2a'); px(c, x + 4, y + 21, 16, 1, '#3a2418');
        px(c, x + 4, y + 14, 16, 1, G.C.gold); px(c, x + 4, y + 11, 1, 11, G.C.gold); px(c, x + 19, y + 11, 1, 11, G.C.gold);
        if (open) { px(c, x + 4, y + 5, 16, 6, '#5a3418'); px(c, x + 5, y + 11, 14, 3, '#1a1010'); px(c, x + 4, y + 5, 16, 1, '#7a4a2a'); }
        else { px(c, x + 4, y + 7, 16, 5, '#9a6a3a'); px(c, x + 4, y + 7, 16, 1, '#c08a5a'); px(c, x + 11, y + 12, 3, 4, G.C.gold); px(c, x + 12, y + 13, 1, 2, '#3a2418'); }
        break;
      }
      case 'D': {
        const open = state && state.opened && state.opened[X + ',' + Y];
        px(c, x, y - 9, S, 33, b.wallF);
        px(c, x, y - 9, S, 10, b.wallT); px(c, x, y - 9, S, 1, sh(b.wallT, 0.15));
        px(c, x + 3, y + 1, 18, 23, sh(b.wallF, -0.2));
        if (open) px(c, x + 4, y + 2, 16, 22, '#120c14');
        else {
          px(c, x + 4, y + 2, 16, 22, '#6a4228'); px(c, x + 4, y + 2, 16, 1, '#8a5a38');
          px(c, x + 11, y + 2, 2, 22, '#4a2c18'); px(c, x + 4, y + 9, 16, 1, '#4a2c18'); px(c, x + 4, y + 17, 16, 1, '#4a2c18');
          px(c, x + 15, y + 12, 2, 2, G.C.gold);
        }
        break;
      }
      case 'v': {
        px(c, x + 3, y - 4, 18, 27, '#3a3a44'); px(c, x + 3, y - 4, 18, 3, '#5a5a66');
        px(c, x + 5, y - 3, 14, 2, '#7aff9a'); px(c, x + 7, y - 3, 4, 1, '#d8ffe0');
        px(c, x + 3, y + 7, 18, 1, '#2a2a30'); px(c, x + 3, y + 15, 18, 1, '#2a2a30');
        px(c, x + 18, y - 4, 3, 27, '#26262e');
        break;
      }
      case 'h': {
        trap(c, '#d8c8a0', y - 4, y + 23, x + 11, x + 13, x + 1, x + 23);
        trap(c, '#b0a078', y - 4, y + 23, x + 12, x + 13, x + 12, x + 23);
        trap(c, '#3a2a1a', y + 10, y + 23, x + 11, x + 13, x + 8, x + 16);
        px(c, x + 11, y - 7, 2, 4, '#6a4a2a');
        break;
      }
      case 'W': {
        px(c, x + 1, y + 7, 22, 10, '#8a6440'); px(c, x + 1, y + 7, 22, 1, '#b08a5a'); px(c, x + 1, y + 16, 22, 1, '#5a4028');
        pell(c, x + 12, y + 7, 11, 9, '#e8dcc0', 'top'); pell(c, x + 12, y + 7, 9, 7, '#f4ecd8', 'top');
        px(c, x + 6, y, 1, 7, '#c8b890'); px(c, x + 17, y, 1, 7, '#c8b890');
        pell(c, x + 6, y + 19, 3, 3, '#3a2a1a'); pell(c, x + 18, y + 19, 3, 3, '#3a2a1a');
        px(c, x + 6, y + 19, 1, 1, '#8a6a4a'); px(c, x + 18, y + 19, 1, 1, '#8a6a4a');
        break;
      }
      case 'Q': {
        trap(c, '#e8e0d0', y - 44, y + 24, x + 7, x + 17, x + 4, x + 20);
        trap(c, '#c8bcac', y - 44, y + 24, x + 14, x + 17, x + 15, x + 20);
        for (let k = 0; k < 4; k++) px(c, x + 4, y - 38 + k * 16, 16, 5, '#c83a4a');
        px(c, x + 5, y - 52, 14, 9, '#2a2a36'); px(c, x + 7, y - 51, 10, 6, '#fff2b0'); px(c, x + 9, y - 50, 4, 2, '#ffffff');
        px(c, x + 3, y - 43, 18, 2, '#2a2a36'); px(c, x + 10, y - 55, 4, 3, '#2a2a36');
        px(c, x + 9, y + 12, 6, 12, '#3a2a1a');
        break;
      }
    }
  }

  // ---------------------------------------------------------------- bake
  // map: { w, h, at(x,y), rows: [string], biome }
  const FRAMES = 4;
  TL.bake = function (map, state) {
    const b = BI[map.biome] || BI.city;
    const night = !!map.night;
    const W = map.w * S, Hh = map.h * S;
    const grounds = [];
    for (let fr = 0; fr < FRAMES; fr++) {
      const cv = G.canvas(W, Hh);
      if (fr > 0) {
        // only the animated tiles change between frames
        cv.x.drawImage(grounds[0], 0, 0);
        for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
          const ch = map.at(x, y);
          if (ch === '~' || ch === '-' || ch === 'b' || ch === '%' || ch === 'x') ground(cv.x, ch, x, y, x * S, y * S, b, fr, map);
        }
      } else {
        for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) ground(cv.x, map.at(x, y), x, y, x * S, y * S, b, fr, map);
      }
      // soft shadow under props to anchor them
      for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
        const t = T[map.at(x, y)];
        if (t && t.prop && '#BnKDQ'.indexOf(map.at(x, y)) < 0) {
          cv.x.fillStyle = 'rgba(10,8,20,0.24)';
          for (let dy = -2; dy <= 2; dy++) { const w = Math.round(10 * Math.sqrt(1 - (dy / 3) * (dy / 3))); cv.x.fillRect(x * S + 12 - w, y * S + 21 + dy, w * 2, 1); }
        }
      }
      grounds.push(cv);
    }
    const rows = [];
    for (let y = 0; y < map.h; y++) rows.push(TL.bakeRow(map, y, state));
    const lights = [];
    for (let y = 0; y < map.h; y++) for (let x = 0; x < map.w; x++) {
      const ch = map.at(x, y), t = T[ch];
      if (!t || !t.light) continue;
      if ((ch === 'H' || ch === 'S' || ch === 'n') && !night) continue;
      const big = ch === 'Q' ? 120 : ch === 'K' ? 60 : ch === 'L' ? 50 : ch === 'n' ? 44 : ch === 'i' ? 20 : 38;
      lights.push({ x: x * S + 12, y: y * S + (ch === 'L' ? -12 : ch === 'Q' ? -46 : 12), r: big, c: t.light, a: ch === 'i' ? 0.18 : 0.32 });
    }
    return { grounds, rows, lights, biome: b };
  };
  const tmp = G.canvas(8, 8), ol = G.canvas(8, 8);
  function sized(cv, w, h) { if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; } else cv.x.clearRect(0, 0, w, h); cv.x.imageSmoothingEnabled = false; return cv.x; }
  TL.bakeRow = function (map, y, state) {
    const b = BI[map.biome] || BI.city;
    const w = map.w * S, h = HEAD + S;
    const cv = G.canvas(w, h);
    let any = false, free = false;
    const fx = sized(tmp, w, h);
    for (let x = 0; x < map.w; x++) {
      const ch = map.at(x, y), t = T[ch];
      if (!t || !t.prop) continue;
      any = true;
      if (STRUCT.indexOf(ch) >= 0) prop(cv.x, ch, x, y, x * S, HEAD, b, map, state, map.night);
      else { prop(fx, ch, x, y, x * S, HEAD, b, map, state, map.night); free = true; }
    }
    if (free) {
      const o = sized(ol, w, h);
      [[-1, 0], [1, 0], [0, -1], [0, 1]].forEach(([dx, dy]) => o.drawImage(tmp, dx, dy));
      o.globalCompositeOperation = 'source-in';
      o.fillStyle = 'rgba(12,10,24,0.72)';
      o.fillRect(0, 0, w, h);
      o.globalCompositeOperation = 'source-over';
      cv.x.drawImage(ol, 0, 0);
      cv.x.drawImage(tmp, 0, 0);
    }
    return any ? cv : null;
  };
  // ground tiles that animate (water, springs, void) step through the baked frames
  TL.groundFrame = () => Math.floor(AD.frame / 16) % FRAMES;
})(window.AD);

