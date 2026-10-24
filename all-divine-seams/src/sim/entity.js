// Bodies and how they move: tile to tile, with a smooth glide between. A body holds its tile and
// claims the next one when a step begins, so two bodies never meet on one tile.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const E = (AD.ent = {});
  const PUSH_FRAMES = 6;

  E.framesPerTile = (speed) => Math.max(1, Math.round(60 / speed));

  E.make = function (room, o) {
    const e = Object.assign({
      kind: 'monster', team: 'e', mode: 'walk', speed: 5, hp: 1, mhp: 0,
      facing: [0, 1], statuses: {}, iframes: 0, hitstop: 0, armour: 0, moveMul: 1,
    }, o);
    e.id = ++room.nextId;
    if (!e.mhp) e.mhp = e.hp;
    e.fx = e.x; e.fy = e.y;
    e.move = null; e.buf = null; e.pushLeft = 0;
    room.bodies.set(e.id, e);
    room.grid.claim(e.id, e.x, e.y);
    return e;
  };

  E.remove = function (room, e) {
    room.grid.release(e.id, e.x, e.y);
    if (e.move) room.grid.release(e.id, e.move.x1, e.move.y1);
    room.bodies.delete(e.id);
    e.gone = true;
  };

  // can e enter (x,y) by (dx,dy) right now?
  function free(room, e, x, y) {
    const who = room.grid.bodyAt(x, y);
    return !who || who === e.id;
  }
  E.canStep = function (room, e, dx, dy) {
    const g = room.grid, nx = e.x + dx, ny = e.y + dy;
    if (!g.canStep(e.x, e.y, dx, dy, e.mode)) return false;
    if (!free(room, e, nx, ny)) return false;
    if (dx && dy && (!free(room, e, e.x + dx, e.y) || !free(room, e, e.x, e.y + dy))) return false;
    return true;
  };

  function begin(room, e, dx, dy, dur) {
    const nx = e.x + dx, ny = e.y + dy;
    room.grid.claim(e.id, nx, ny);
    e.move = { x0: e.x, y0: e.y, x1: nx, y1: ny, t: 0, dur };
  }

  E.stepFrames = function (room, e, dx, dy) {
    const t = AD.tileInfo(room.grid.at(e.x + dx, e.y + dy));
    const slow = e.mode !== 'fly' && t.slow ? 1 - t.slow : 1;
    return E.framesPerTile(e.speed * e.moveMul * slow);
  };

  E.tryStep = function (room, e, dx, dy) {
    if (e.move || e.pushLeft || e.gone) return false;
    if (!dx && !dy) return false;
    e.facing = [dx, dy];
    if (!E.canStep(room, e, dx, dy)) return false;
    begin(room, e, dx, dy, E.stepFrames(room, e, dx, dy));
    return true;
  };

  // the last direction pressed mid-step, taken the frame the step ends
  E.buffer = function (e, dx, dy) { e.buf = dx || dy ? [dx, dy] : null; };

  // knock-back: a fast glide, tile by tile, stopping at the first tile it cannot enter
  E.push = function (room, e, dx, dy, tiles, frames) {
    if (e.gone || e.immovable) return;
    if (e.move) {
      // settle on the nearer of the two tiles it holds
      const m = e.move;
      if (m.t * 2 >= m.dur) { room.grid.release(e.id, m.x0, m.y0); e.x = m.x1; e.y = m.y1; }
      else room.grid.release(e.id, m.x1, m.y1);
      e.fx = e.x; e.fy = e.y; e.move = null;
    }
    e.buf = null;
    e.pushDir = [dx, dy];
    e.pushLeft = tiles;
    e.pushFrames = frames || PUSH_FRAMES;
    nextPush(room, e);
  };
  function nextPush(room, e) {
    const [dx, dy] = e.pushDir;
    if (e.pushLeft > 0 && E.canStep(room, e, dx, dy)) { e.pushLeft--; begin(room, e, dx, dy, e.pushFrames || PUSH_FRAMES); return true; }
    e.pushLeft = 0;
    return false;
  }

  E.tick = function (room, e) {
    if (e.gone) return;
    if (e.iframes > 0) e.iframes--;
    if (e.flash > 0) e.flash--;
    if (e.hitstop > 0) { e.hitstop--; return; }
    const m = e.move;
    if (!m) return;
    m.t++;
    const k = Math.min(1, m.t / m.dur);
    e.fx = m.x0 + (m.x1 - m.x0) * k;
    e.fy = m.y0 + (m.y1 - m.y0) * k;
    if (m.t < m.dur) return;
    room.grid.release(e.id, m.x0, m.y0);
    e.x = m.x1; e.y = m.y1; e.fx = e.x; e.fy = e.y;
    e.move = null;
    if (room.onArrive) room.onArrive(e);
    if (e.gone) return;
    if (e.pushLeft) { nextPush(room, e); return; }
    if (e.buf) { const [dx, dy] = e.buf; e.buf = null; E.tryStep(room, e, dx, dy); }
  };

  E.dist = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
})(window.AD);
