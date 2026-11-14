// A live room: its grid, its bodies, its pickups, its own event bus (which passes everything on to
// the run's). Rooms stay alive for the whole depth, so a broken pot stays broken.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const RM = (AD.room = {});
  const MOUTH = { n: [7, 1], s: [7, 8], w: [1, 4], e: [13, 4] };
  RM.MOUTH = MOUTH;

  RM.build = function (run, key, layout, info) {
    const room = {
      key, type: info.type, info, name: layout.name, template: layout.template,
      grid: new AD.Grid(layout.rows), bodies: new Map(), bus: new AD.Bus().forward(run.events),
      frame: 0, nextId: 0, rng: run.streams, run, hero: null, pickups: [], corpses: [], attacks: [], projs: [],
      level: 1, depth: run.depth, entry: [7, 8], sealed: false, chests: {}, nextPickup: 0,
    };
    const d = AD.regionAt(run.depth).d;
    AD.world.init(room, { ambient: d.ambient });
    for (const t of layout.traps || []) AD.world.setTrap(room, t.x, t.y, t.kind);
    AD.ai.install(room);
    AD.director.install(room);
    AD.world.install(room);
    if (AD.boss) AD.boss.install(room);
    room.onArrive = (e) => run.arrive(room, e);
    room.dropPickup = (x, y, p) => RM.drop(room, x, y, p);
    run.install(room);
    return room;
  };

  // a pickup lands on the nearest open tile without one
  RM.drop = function (room, x, y, p) {
    const g = room.grid;
    let best = null, bd = 99;
    for (let r = 0; r <= 4 && !best; r++) {
      for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        const nx = x + dx, ny = y + dy;
        if (!g.passable(nx, ny, 'walk') || AD.tileInfo(g.at(nx, ny)).door) continue;
        if (room.pickups.some((q) => q.x === nx && q.y === ny && q.kind !== 'coins')) continue;
        const d = Math.abs(dx) + Math.abs(dy);
        if (d < bd) { bd = d; best = [nx, ny]; }
      }
    }
    if (!best) best = [x, y];
    const q = Object.assign({ id: room.key + '#' + (room.nextPickup++), t: 0 }, p, { x: best[0], y: best[1], fx: best[0], fy: best[1] });
    room.pickups.push(q);
    room.bus.emit('drop', { p: q });
    return q;
  };
})(window.AD);
