// A depth's floor (spec §6.1): rooms on a 9x8 grid of slots, grown outward from the start by a
// queue walk, then the special rooms placed where they make sense, locks before keys, and a check
// that the whole floor can be walked. A seed that fails is redrawn.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const GN = (AD.gen = AD.gen || {});
  const GW = 9, GH = 8;
  const DIRS = { n: [0, -1], s: [0, 1], w: [-1, 0], e: [1, 0] };
  const OPP = { n: 's', s: 'n', w: 'e', e: 'w' };
  GN.DIRS = DIRS; GN.OPP = OPP;
  const K = (x, y) => x + ',' + y;
  const inside = (x, y) => x >= 0 && y >= 0 && x < GW && y < GH;

  function neighbours(set, x, y) {
    let n = 0;
    for (const [dx, dy] of Object.values(DIRS)) if (set.has(K(x + dx, y + dy))) n++;
    return n;
  }

  function attempt(depth, r) {
    const want = Math.min(16, 8 + Math.floor(0.4 * depth) + AD.rng.int(r, 0, 2));
    const slots = new Set([K(4, 4)]);
    const queue = [[4, 4]];
    while (queue.length && slots.size < want) {
      const [cx, cy] = queue.shift();
      for (const d of AD.rng.shuffle(r, Object.keys(DIRS))) {
        const [dx, dy] = DIRS[d], nx = cx + dx, ny = cy + dy;
        if (!inside(nx, ny) || slots.has(K(nx, ny)) || slots.size >= want) continue;
        if (neighbours(slots, nx, ny) > 1) continue;
        if (r() < 0.5) continue;
        slots.add(K(nx, ny));
        queue.push([nx, ny]);
      }
    }
    if (slots.size < want) return null;
    const rooms = new Map();
    for (const k of slots) {
      const [gx, gy] = k.split(',').map(Number);
      rooms.set(k, { key: k, gx, gy, type: 'combat', doors: { n: null, s: null, w: null, e: null }, dist: -1, links: 0 });
    }
    for (const R of rooms.values()) {
      for (const [d, [dx, dy]] of Object.entries(DIRS)) if (rooms.has(K(R.gx + dx, R.gy + dy))) R.doors[d] = 'open';
    }
    const start = K(4, 4);
    rooms.get(start).type = 'start';
    // distances from the start, in rooms
    const q = [start]; rooms.get(start).dist = 0;
    while (q.length) {
      const R = rooms.get(q.shift());
      for (const [d, [dx, dy]] of Object.entries(DIRS)) {
        if (!R.doors[d]) continue;
        const N = rooms.get(K(R.gx + dx, R.gy + dy));
        if (N.dist < 0) { N.dist = R.dist + 1; q.push(N.key); }
      }
    }
    const links = (R) => Object.values(R.doors).filter((v) => v === 'open' || v === 'locked').length;
    const dead = [...rooms.values()].filter((R) => R.key !== start && links(R) === 1);
    if (dead.length < 2) return null;
    // the exit on the farthest dead end
    dead.sort((a, b) => b.dist - a.dist || (a.key < b.key ? -1 : 1));
    const exit = dead[0];
    exit.type = 'exit';
    // treasure on another dead end, locked half the time
    const others = dead.slice(1);
    const treasure = AD.rng.pick(r, others);
    treasure.type = 'treasure';
    const keys = [];
    if (r() < 0.5) {
      const d = Object.keys(treasure.doors).find((k) => treasure.doors[k] === 'open');
      const [dx, dy] = DIRS[d];
      treasure.doors[d] = 'locked';
      rooms.get(K(treasure.gx + dx, treasure.gy + dy)).doors[OPP[d]] = 'locked';
      const holders = [...rooms.values()].filter((R) => R.type === 'combat');
      if (!holders.length) return null;
      keys.push({ room: AD.rng.pick(r, holders).key, lock: treasure.key });
    }
    // one rest room, a spare dead end if there is one
    const spare = dead.filter((R) => R.type === 'combat');
    const pool = spare.length ? spare : [...rooms.values()].filter((R) => R.type === 'combat' && !keys.some((k) => k.room === R.key));
    if (pool.length > 1) AD.rng.pick(r, pool).type = 'rest';
    // the secret room: the empty slot touching the most rooms, never beside the exit or the treasure
    let best = [], bestN = 1;
    for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++) {
      if (slots.has(K(x, y))) continue;
      const nb = Object.values(DIRS).map(([dx, dy]) => K(x + dx, y + dy)).filter((k) => slots.has(k));
      if (nb.length < 2 || nb.includes(exit.key) || nb.includes(treasure.key)) continue;
      if (nb.length > bestN) { best = [[x, y]]; bestN = nb.length; } else if (nb.length === bestN) best.push([x, y]);
    }
    if (best.length) {
      const [sx, sy] = AD.rng.pick(r, best);
      const S = { key: K(sx, sy), gx: sx, gy: sy, type: 'secret', doors: { n: null, s: null, w: null, e: null }, dist: -1, links: 0 };
      for (const [d, [dx, dy]] of Object.entries(DIRS)) {
        const N = rooms.get(K(sx + dx, sy + dy));
        if (!N) continue;
        S.doors[d] = 'secret';
        N.doors[OPP[d]] = 'secret';
      }
      rooms.set(S.key, S);
    }
    for (const R of rooms.values()) R.links = links(R);
    return { depth, rooms, start, exit: exit.key, keys, bossDepth: depth % 5 === 0 };
  }

  GN.floor = function (depth, r) {
    for (let i = 0; i < 200; i++) {
      const F = attempt(depth, r);
      if (F && GN.validate(F).ok) return F;
    }
    throw new Error('no floor for depth ' + depth);
  };

  function reach(F, pass) {
    const seen = new Set([F.start]);
    const q = [F.start];
    while (q.length) {
      const R = F.rooms.get(q.shift());
      for (const [d, [dx, dy]] of Object.entries(DIRS)) {
        const door = R.doors[d];
        if (!door || !pass(door, R)) continue;
        const k = K(R.gx + dx, R.gy + dy);
        if (!F.rooms.has(k) || seen.has(k)) continue;
        seen.add(k); q.push(k);
      }
    }
    return seen;
  }
  GN.validate = function (F) {
    if (!F.rooms.has(F.start) || !F.rooms.has(F.exit)) return { ok: false, why: 'no start or exit' };
    const free = reach(F, (d) => d === 'open');
    if (!free.has(F.exit)) return { ok: false, why: 'exit behind a lock or secret' };
    for (const k of F.keys) if (!free.has(k.room)) return { ok: false, why: 'key ' + k.room + ' behind its lock' };
    const all = reach(F, () => true);
    for (const k of F.rooms.keys()) if (!all.has(k)) return { ok: false, why: 'unreachable ' + k };
    for (const R of F.rooms.values()) {
      if (R.type === 'secret' || R.type === 'treasure') continue;
      if (!free.has(R.key)) return { ok: false, why: 'room ' + R.key + ' needs a key or a bomb' };
    }
    return { ok: true, why: '' };
  };
})(window.AD);
