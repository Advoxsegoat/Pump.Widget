// The tile grid of one room: what each tile is, who stands on it, what can be seen, and how far
// everything is from a goal. Rooms are 15x10 in every display mode.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const W = 15, H = 10;
  // walk: walkers may enter; fly: flyers may enter; sight: blocks sight; plus what the world systems need
  const T = (AD.TILES = {
    '.': { n: 'Floor', walk: 1, fly: 1 },
    ',': { n: 'Grass', walk: 1, fly: 1, flammable: 1 },
    '"': { n: 'Tall grass', walk: 1, fly: 1, sight: 1, flammable: 1, cut: 1 },
    '-': { n: 'Shallows', walk: 1, fly: 1, water: 1, slow: 0.3 },
    '~': { n: 'Deep water', fly: 1, water: 1, deep: 1 },
    O: { n: 'Pit', fly: 1, pit: 1 },
    '#': { n: 'Wall', sight: 1, wall: 1 },
    '%': { n: 'Cracked wall', sight: 1, wall: 1, cracked: 1 },
    D: { n: 'Door', walk: 1, fly: 1, door: 1 },
    '+': { n: 'Locked door', sight: 1, door: 1, locked: 1 },
    '=': { n: 'Sealed door', sight: 1, door: 1, sealed: 1 },
    p: { n: 'Pot', breakable: 1, solid: 1 },
    c: { n: 'Crate', breakable: 1, solid: 1, flammable: 1 },
    b: { n: 'Powder barrel', breakable: 1, solid: 1, explosive: 1 },
    L: { n: 'Lamp', solid: 1, light: 3 },
    v: { n: 'Vat', solid: 1, light: 2 },
    '^': { n: 'Trap', walk: 1, fly: 1, trap: 1 },
    G: { n: 'Seam Gate', walk: 1, fly: 1, gate: 1, light: 3 },
    C: { n: 'Chest', solid: 1, chest: 1 },
    P: { n: 'Pedestal', walk: 1, fly: 1, pedestal: 1 },
    B: { n: 'Block', solid: 1, sight: 1 },
    f: { n: 'Campfire', solid: 1, light: 4 },
    w: { n: 'Wood floor', walk: 1, fly: 1, flammable: 0 },
  });
  AD.tileInfo = (ch) => T[ch] || T['#'];

  function Grid(rows) {
    this.w = W; this.h = H;
    this.t = new Array(W * H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) this.t[y * W + x] = (rows[y] && rows[y][x]) || '#';
    this.occ = new Int32Array(W * H);
    this.version = 0;
  }
  Grid.prototype.inside = function (x, y) { return x >= 0 && y >= 0 && x < W && y < H; };
  Grid.prototype.at = function (x, y) { return this.inside(x, y) ? this.t[y * W + x] : '#'; };
  Grid.prototype.set = function (x, y, ch) { if (this.inside(x, y)) { this.t[y * W + x] = ch; this.version++; } };
  Grid.prototype.rows = function () { const out = []; for (let y = 0; y < H; y++) out.push(this.t.slice(y * W, y * W + W).join('')); return out; };
  Grid.prototype.passable = function (x, y, mode) {
    if (!this.inside(x, y)) return false;
    const d = T[this.t[y * W + x]] || T['#'];
    // the hero may walk (or be knocked) into a pit; monsters' paths never cross one
    if (mode === 'hero') return !!(d.walk || d.pit);
    return !!(mode === 'fly' ? d.fly : d.walk);
  };
  Grid.prototype.opaque = function (x, y) {
    if (!this.inside(x, y)) return true;
    const d = T[this.t[y * W + x]] || T['#'];
    return !!d.sight;
  };
  // Bresenham; the two end tiles are never tested
  Grid.prototype.los = function (x0, y0, x1, y1) {
    let dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx + dy, x = x0, y = y0;
    while (!(x === x1 && y === y1)) {
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x += sx; }
      if (e2 <= dx) { err += dx; y += sy; }
      if (x === x1 && y === y1) break;
      if (this.opaque(x, y)) return false;
    }
    return true;
  };
  // may a body step from (x,y) by (dx,dy)? diagonals need both orthogonal neighbours open
  Grid.prototype.canStep = function (x, y, dx, dy, mode) {
    if (!this.passable(x + dx, y + dy, mode)) return false;
    if (dx && dy) return this.passable(x + dx, y, mode) && this.passable(x, y + dy, mode);
    return true;
  };
  const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
  AD.DIRS = DIRS;
  // breadth-first distance in steps from the goals; -1 where unreachable
  Grid.prototype.distanceMap = function (goals, mode) {
    const d = new Int16Array(W * H).fill(-1);
    const q = [];
    for (const [gx, gy] of goals) { if (this.inside(gx, gy)) { d[gy * W + gx] = 0; q.push(gy * W + gx); } }
    for (let qi = 0; qi < q.length; qi++) {
      const i = q[qi], x = i % W, y = (i / W) | 0;
      for (const [dx, dy] of DIRS) {
        const nx = x + dx, ny = y + dy;
        if (!this.inside(nx, ny) || d[ny * W + nx] >= 0) continue;
        if (!this.canStep(x, y, dx, dy, mode)) continue;
        d[ny * W + nx] = d[i] + 1;
        q.push(ny * W + nx);
      }
    }
    return d;
  };
  // Pixel Dungeon's flee map: the distance scaled by -1.2, then relaxed so a fleer is not trapped in
  // a corner. Lower is better.
  Grid.prototype.fleeMap = function (dist) {
    const f = new Float32Array(W * H);
    for (let i = 0; i < W * H; i++) f[i] = dist[i] < 0 ? 9999 : -1.2 * dist[i];
    for (let pass = 0; pass < 12; pass++) {
      let changed = false;
      for (let i = 0; i < W * H; i++) {
        if (dist[i] < 0) continue;
        const x = i % W, y = (i / W) | 0;
        for (const [dx, dy] of DIRS) {
          const nx = x + dx, ny = y + dy;
          if (!this.inside(nx, ny) || dist[ny * W + nx] < 0) continue;
          const v = f[ny * W + nx] + 1;
          if (v < f[i]) { f[i] = v; changed = true; }
        }
      }
      if (!changed) break;
    }
    return f;
  };
  // occupancy: one body per tile
  Grid.prototype.claim = function (id, x, y) {
    if (!this.inside(x, y)) return false;
    const i = y * W + x;
    if (this.occ[i] && this.occ[i] !== id) return false;
    this.occ[i] = id;
    return true;
  };
  Grid.prototype.release = function (id, x, y) {
    if (!this.inside(x, y)) return;
    const i = y * W + x;
    if (this.occ[i] === id) this.occ[i] = 0;
  };
  Grid.prototype.bodyAt = function (x, y) { return this.inside(x, y) ? this.occ[y * W + x] : 0; };
  Grid.W = W; Grid.H = H;
  AD.Grid = Grid;
})(window.AD);
