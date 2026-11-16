// The playtest bot, injected into the page. It reads the game each frame and presses keys, or
// touches the phone controls, as a player would; it never calls the game's own functions to act.
//   BOT.start({mode: 'keys'|'touch'}); then each frame BOT.frame() before the game steps.
// It fights the nearest monster, faces it and strikes, rolls out of red tiles, uses its Gift when
// ready, picks things up, pays for chests it can afford, heads for the exit when a room is clear,
// holds the Seam Gate, and drinks Healing below 30%.
(function () {
  'use strict';
  const BOT = (window.BOT = { mode: 'keys', held: new Set(), log: [] });
  const DIRS8 = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]];
  const sgn = (v) => (v > 0 ? 1 : v < 0 ? -1 : 0);
  const cheb = (a, b, c, d) => Math.max(Math.abs(a - c), Math.abs(b - d));

  // ---------------------------------------------------------------- the devices
  const KEY = { up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight', a: 'z', b: 'x', r: 'c', l: 'v', q0: '1', q1: '2', start: 'Enter' };
  const key = (k, down) => window.dispatchEvent(new KeyboardEvent(down ? 'keydown' : 'keyup', { key: k }));
  const P = (type, el, id, x, y) => el.dispatchEvent(new PointerEvent(type, { pointerId: id, pointerType: 'touch', clientX: x, clientY: y, bubbles: true, cancelable: true }));
  const centre = (el) => { const b = el.getBoundingClientRect(); return [b.left + b.width / 2, b.top + b.height / 2]; };
  const touch = { stick: null, ids: { a: 11, b: 12, r: 13, l: 14, start: 15 }, down: new Set() };
  // want: {dir: [sx, sy], press: Set of buttons tapped this frame, hold: Set held}
  function apply(want) {
    if (BOT.mode === 'touch') return applyTouch(want);
    const next = new Set();
    const [sx, sy] = want.dir || [0, 0];
    if (sx > 0) next.add('right'); if (sx < 0) next.add('left'); if (sy > 0) next.add('down'); if (sy < 0) next.add('up');
    for (const b of want.hold || []) next.add(b);
    for (const b of BOT.held) if (!next.has(b)) key(KEY[b], false);
    for (const b of next) if (!BOT.held.has(b)) key(KEY[b], true);
    BOT.held = next;
    // a tap: down now, up on the next frame (a tap shorter than a frame still counts)
    for (const b of want.press || []) { if (!BOT.held.has(b)) { key(KEY[b], true); BOT.release.push(b); } }
  }
  BOT.release = [];
  function applyTouch(want) {
    const zone = document.getElementById('stickZone');
    const [sx, sy] = want.dir || [0, 0];
    if (sx || sy) {
      const z = zone.getBoundingClientRect(), cx = z.left + z.width / 2, cy = z.top + z.height / 2;
      if (!touch.stick) { P('pointerdown', zone, 1, cx, cy); touch.stick = true; }
      const m = Math.hypot(sx, sy);
      P('pointermove', zone, 1, cx + (sx / m) * 38, cy + (sy / m) * 38);
    } else if (touch.stick) { P('pointerup', zone, 1, 0, 0); touch.stick = null; }
    const hold = new Set(want.hold || []);
    BOT.holding = hold;
    for (const b of ['a', 'b', 'r', 'l', 'start']) {
      const el = document.querySelector('[data-btn="' + b + '"]');
      const on = hold.has(b) || (want.press && want.press.has(b));
      if (on && !touch.down.has(b)) { P('pointerdown', el, touch.ids[b], ...centre(el)); touch.down.add(b); }
      else if (!on && touch.down.has(b)) { P('pointerup', el, touch.ids[b], ...centre(el)); touch.down.delete(b); }
    }
    for (const q of ['q0', 'q1']) if (want.press && want.press.has(q)) tapQuick(+q[1]);
  }
  function tapQuick(i) {
    const cv = document.getElementById('screen').getBoundingClientRect(), r = AD.hud.layout(AD.display.mode)['quick' + i], k = cv.width / AD.display.W;
    P('pointerdown', document.getElementById('screen'), 20 + i, cv.left + (r.x + r.w / 2) * k, cv.top + (r.y + r.h / 2) * k);
  }
  function endFrame() {
    if (BOT.mode === 'keys') { for (const b of BOT.release) key(KEY[b], false); BOT.release = []; }
    else for (const b of [...touch.down]) if (!BOT.holding.has(b)) { const el = document.querySelector('[data-btn="' + b + '"]'); P('pointerup', el, touch.ids[b], ...centre(el)); touch.down.delete(b); }
  }
  BOT.holding = new Set();

  // ---------------------------------------------------------------- reading the room
  function step(room, from, to) {
    // the first step on the distance map from `from` toward the goal tiles `to`
    const D = room.grid.distanceMap(to, 'walk');
    const here = D[from[1] * 15 + from[0]];
    let best = null, bd = here < 0 ? 9999 : here;
    for (const [dx, dy] of DIRS8) {
      const x = from[0] + dx, y = from[1] + dy, v = D[y * 15 + x];
      if (x < 0 || y < 0 || x > 14 || y > 9 || v < 0 || v >= bd) continue;
      if (!room.grid.canStep(from[0], from[1], dx, dy, 'walk')) continue;
      const b = room.grid.bodyAt(x, y);
      if (b && !to.some(([tx, ty]) => tx === x && ty === y)) continue;
      bd = v; best = [dx, dy];
    }
    return best;
  }
  // tiles about to be struck, with how many frames are left before each lands
  const danger = (room) => {
    const s = new Map();
    for (const a of room.attacks || []) {
      if (!a.owner || a.owner.kind === 'hero' || a.frame > a.def.wind) continue;
      const left = a.def.wind - a.frame;
      for (const [x, y] of a.tiles) { const k = x + ',' + y; if (!s.has(k) || s.get(k) > left) s.set(k, left); }
    }
    // shots in flight: the tiles they will cross in the next 20 frames
    for (const p of room.projs || []) {
      if (p.team === 'p') continue;
      for (let t = 0; t <= 20; t += 2) { const k = Math.round(p.x + p.vx * t) + ',' + Math.round(p.y + p.vy * t); if (!s.has(k) || s.get(k) > t) s.set(k, t); }
    }
    return s;
  };
  // frames until a blow could land on each tile: the red tiles exactly, and for each monster that
  // could start one, its cooldown, the steps it needs to come within reach and its wind-up (what a
  // player learns of a monster's rhythm by watching it)
  function threat(room, hot) {
    const T = new Map(hot);
    const set = (x, y, t) => { const k = x + ',' + y; if (!T.has(k) || T.get(k) > t) T.set(k, t); };
    for (const m of room.bodies.values()) {
      if (m.dead || m.gone || m.team === 'p' || m.kind === 'hero' || m.state === 'asleep') continue;
      if (m.kind === 'boss') {
        // between patterns a boss waits out its gap, then telegraphs for at least 18 frames
        const ready = (m.busy || 0) + (m.gap || 0) + Math.max(m.stunned || 0, m.stagger || 0) + 18;
        for (let y = 0; y < 10; y++) for (let x = 0; x < 15; x++) if (cheb(m.x, m.y, x, y) <= 6) set(x, y, ready);
        continue;
      }
      if (m.kind !== 'monster' || !m.def || !m.def.attacks) continue;
      const a = m.seq || m.def.attacks[0];
      if (!a || (m.def.dmg || 0) <= 0) continue;
      const ready = Math.max(m.seq ? m.busy || 0 : Math.max(m.atkCd || 0, m.busy || 0), m.shimmer || 0);
      const k = a.shape.k, reach = k === 'adjacent' ? 1 : k === 'line' ? a.shape.n : k === 'shot' ? a.shape.range : k === 'lob' ? a.shape.range + 1 : 2;
      const fpt = Math.round(60 / (m.speed || 4));
      for (let y = 0; y < 10; y++) for (let x = 0; x < 15; x++) {
        const d = cheb(m.x, m.y, x, y);
        if (k === 'shot') { if (d <= reach) set(x, y, ready + a.wind + d * 6); continue; }
        const steps = Math.max(0, d - reach);
        if (steps <= 3) set(x, y, Math.max(ready, steps * fpt) + a.wind);
      }
    }
    return T;
  }
  const at0 = (T, x, y) => { const k = x + ',' + y; return T.has(k) ? T.get(k) : 999; };
  // a tile next to `at` that nothing is about to strike
  function safeStep(room, at, hot) {
    let best = null, bs = -1;
    for (const [dx, dy] of DIRS8) {
      const x = at[0] + dx, y = at[1] + dy, k = x + ',' + y;
      if (!room.grid.canStep(at[0], at[1], dx, dy, 'walk') || room.grid.bodyAt(x, y)) continue;
      const score = hot.has(k) ? hot.get(k) : 100;
      if (score > bs) { bs = score; best = [dx, dy]; }
    }
    return bs > 12 ? best : null;
  }
  // the first door on the way to the nearest room not yet seen (a player clears the floor for its
  // experience, coins and chests), and once there are none, to the exit
  function routeToExit(run) {
    const F = run.floor, from = run.room.key;
    // a gate already charging: back to it first
    const unseen = !(run.gate && !run.gate.open) && [...run.roomState].some(([k, st]) => st.state === 'unvisited' && reachable(run, k));
    const goal = (k, R) => k !== from && (unseen ? run.roomState.get(k).state === 'unvisited' : R.type === 'exit');
    const prev = new Map([[from, null]]), q = [from];
    while (q.length) {
      const k = q.shift(), R = F.rooms.get(k);
      if (!R) continue;
      if (goal(k, R)) { let c = k; while (prev.get(c) && prev.get(c)[0] !== from) c = prev.get(c)[0]; return prev.get(c)[1]; }
      for (const [d, link] of Object.entries(R.doors)) {
        if (link !== 'open' && !(link === 'locked' && run.keys > 0)) continue;
        const n = (R.gx + AD.gen.DIRS[d][0]) + ',' + (R.gy + AD.gen.DIRS[d][1]);
        if (F.rooms.has(n) && !prev.has(n)) { prev.set(n, [k, d]); q.push(n); }
      }
    }
    return null;
  }

  function reachable(run, key) {
    const F = run.floor, from = run.room.key, seen = new Set([from]), q = [from];
    while (q.length) {
      const k = q.shift(); if (k === key) return true;
      const R = F.rooms.get(k);
      for (const [d, link] of Object.entries(R.doors)) {
        if (link !== 'open' && !(link === 'locked' && run.keys > 0)) continue;
        const n = (R.gx + AD.gen.DIRS[d][0]) + ',' + (R.gy + AD.gen.DIRS[d][1]);
        if (F.rooms.has(n) && !seen.has(n)) { seen.add(n); q.push(n); }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- deciding
  function play(run, want) {
    decide(run, want);
    if (BOT.charging) want.hold.push('a');
  }
  function decide(run, want) {
    const room = run.room, h = run.hero;
    if (run.transition || h.dead) return;
    const at = h.move ? [h.move.x1, h.move.y1] : [h.x, h.y];
    const hot = danger(room);
    BOT.why = 'explore'; BOT.cornered = false;
    // red tiles (and shots on their way): out of them before they land, rolling if it is close
    const k0 = at[0] + ',' + at[1];
    if (hot.has(k0) && hot.get(k0) <= 24) {
      const left = hot.get(k0), out = safeStep(room, at, hot);
      // a step changes tile half way (4 frames); a roll is invulnerable for 12. Stuck in a blow's
      // recovery, or with no way out on foot, roll (a roll pressed while a blow lands is queued)
      const stuck = h.busy > 0 && h.busy + 5 >= left;
      if ((stuck || !out) && h.rolls > 0 && left <= 11) { want.dir = out || h.facing; want.press.add('r'); BOT.why = 'roll'; return; }
      if (out && !h.busy) { want.dir = out; BOT.why = 'dodge'; return; }
      // nowhere to go: it lands either way, so hit back
      if (!out) BOT.cornered = true;
    }
    const foes = [...room.bodies.values()].filter((e) => (e.kind === 'monster' || e.kind === 'boss') && !e.dead && !e.gone && !e.untargetable);
    if (quick(run, foes, hot, want)) return;
    const g = run.gate;
    // holding the gate: stay within reach of it unless something is close
    if (g && !g.open && room.type === 'exit') {
      const near = foes.filter((e) => cheb(e.x, e.y, g.tile[0], g.tile[1]) <= 4);
      if (!near.length || cheb(at[0], at[1], g.tile[0], g.tile[1]) > 3) {
        if (cheb(at[0], at[1], g.tile[0], g.tile[1]) > 2) { want.dir = step(room, at, [g.tile]) || [0, 0]; return; }
        if (!near.length) return;
      }
      return fight(run, near, at, want);
    }
    if (foes.length) return fight(run, foes, at, want);
    // a gate to open, or step through
    const G = findTile(room, 'G');
    if (room.type === 'exit' && G && (!g || g.open)) {
      if (at[0] === G[0] && at[1] === G[1] && !h.move) { want.press.add('a'); return; }
      want.dir = step(room, at, [G]) || [sgn(G[0] - at[0]), sgn(G[1] - at[1])];
      return;
    }
    // things on the floor
    const items = room.pickups.filter((p) => p.t >= 10);
    if (items.length) {
      const p = items.sort((a, b) => cheb(a.x, a.y, at[0], at[1]) - cheb(b.x, b.y, at[0], at[1]))[0];
      const s = step(room, at, [[p.x, p.y]]);
      if (s) { want.dir = s; return; }
    }
    // a chest it can afford
    const C = chestToOpen(run, room);
    if (C) {
      if (Math.abs(C[0] - at[0]) + Math.abs(C[1] - at[1]) === 1) {
        // let the step onto the tile beside it finish: a held direction would chain the next one
        if (h.move) return;
        const f = [C[0] - at[0], C[1] - at[1]];
        if (h.facing[0] !== f[0] || h.facing[1] !== f[1]) { want.dir = f; return; }
        want.press.add('a'); return;
      }
      const goals = [[C[0] + 1, C[1]], [C[0] - 1, C[1]], [C[0], C[1] + 1], [C[0], C[1] - 1]].filter(([x, y]) => room.grid.passable(x, y, 'walk'));
      const s = step(room, at, goals);
      if (s) { want.dir = s; return; }
    }
    // on toward the exit
    const side = routeToExit(run);
    if (side) {
      const [mx, my] = AD.room.MOUTH[side], [dx, dy] = AD.gen.DIRS[side];
      if (at[0] === mx && at[1] === my) want.dir = [dx, dy];
      else want.dir = step(room, at, [[mx, my]]) || [sgn(mx - at[0]), sgn(my - at[1])];
    }
  }
  // the quickslots: Healing below 35%; in a fight with a boss, Haste and Toughness, and a thrown
  // draught when the boss stands three tiles ahead; in a quiet moment, the pages and draughts that
  // help at once, and anything not yet named (a draught only when hurt, so Healing is not wasted)
  function quick(run, foes, hot, want) {
    const h = run.hero, C = AD.cons, t = run.room.frame;
    if (h.busy || h.move || t % 3) return false;
    const use = (i) => { want.press.add('q' + i); BOT.why = 'item'; return true; };
    for (let i = 0; i < Math.min(2, run.quick.length); i++) {
      const id = run.quick[i];
      if (!id || id === 'bomb' || !C.count(run, id)) continue;
      const known = C.known(run, id), potion = !!AD.POTIONS[id];
      if (known && id === 'healing' && h.hp < h.mhp * 0.35) return use(i);
      const boss = foes.find((e) => e.kind === 'boss');
      if (known && boss && (id === 'haste' || id === 'toughness')) return use(i);
      if (known && boss && AD.POTIONS[id] && AD.POTIONS[id].thrown && boss.x === h.x + h.facing[0] * 3 && boss.y === h.y + h.facing[1] * 3) return use(i);
      if (foes.length || hot.size) continue;
      if (known && ['upgrade', 'experience', 'identify', 'mapping'].includes(id)) return use(i);
      if (known && id === 'removecurse' && run.armour && run.armour.cursed) return use(i);
      // not while the gate charges: a Page of Teleport would carry the hero away from it
      if (!known && (!potion || h.hp < h.mhp * 0.7) && !(run.gate && !run.gate.open)) return use(i);
    }
    return false;
  }
  function fight(run, foes, at, want) {
    const room = run.room, h = run.hero, hot = danger(room);
    BOT.why = 'fight';
    // a crowd around the hero: the Gift first
    foes.sort((a, b) => cheb(a.x, a.y, at[0], at[1]) - cheb(b.x, b.y, at[0], at[1]));
    const m = foes[0], d = cheb(m.x, m.y, at[0], at[1]);
    const T = threat(room, hot), t = at0(T, at[0], at[1]);
    if (d <= 2 && h.skillCd === 0 && !h.move && !h.busy && (t > 26 || (h.rolls > 0 && t > 14))) { want.dir = [sgn(m.x - at[0]), sgn(m.y - at[1])]; want.press.add('b'); return; }
    // a boss, or a crowd around the hero: hold A (the press is the first palm) to charge the spin
    // while closing in and dodging, and let it go beside them: it wears the boss's shield
    const boss = foes.find((e) => e.kind === 'boss' && cheb(e.x, e.y, at[0], at[1]) <= 1);
    const around = foes.filter((e) => cheb(e.x, e.y, at[0], at[1]) <= 1).length;
    if (BOT.charging && h.charge >= AD.HEROES[h.heroId].spin.charge && (boss || around >= 2) && !h.busy && (t > 20 || (h.rolls > 0 && t > 8) || BOT.cornered)) { BOT.charging = false; BOT.why = 'spin'; return; }
    if (!BOT.charging && d === 1 && (m.kind === 'boss' || around >= 3) && !h.busy && !h.move && (t > 22 || (h.rolls > 0 && t > 10))) { BOT.charging = true; want.dir = [sgn(m.x - at[0]), sgn(m.y - at[1])]; return; }
    if (d === 1 && BOT.charging) { want.dir = [sgn(m.x - at[0]), sgn(m.y - at[1])]; return; }
    if (d === 1) {
      // face it (a press toward a body only turns) and strike in a window it can get out of: the
      // palm takes 17 frames with its hit-stop and a step 5 more to clear a tile. With a roll in
      // hand, the recovery can be cancelled; a weak foe is worth trading blows with
      const f = [sgn(m.x - at[0]), sgn(m.y - at[1])];
      if (h.facing[0] !== f[0] || h.facing[1] !== f[1]) { want.dir = f; return; }
      const weak = foes.filter((e) => cheb(e.x, e.y, at[0], at[1]) <= 2).reduce((a, e) => a + (e.dmg || 0), 0) <= h.mhp * 0.06 && h.hp > h.mhp * 0.5;
      const ok = t > 22 || (h.rolls > 0 && t > 10) || weak || BOT.cornered;
      if (!h.busy && !h.move && ok && (room.frame + h.id) % 2 === 0) want.press.add('a');
      return;
    }
    // close in, but never onto a tile a blow is about to land on
    const s1 = step(room, at, [[m.x, m.y]]) || [sgn(m.x - at[0]), sgn(m.y - at[1])];
    const nk = (at[0] + s1[0]) + ',' + (at[1] + s1[1]);
    want.dir = hot.has(nk) && hot.get(nk) <= 20 ? [0, 0] : s1;
  }
  const findTile = (room, ch) => { for (let y = 0; y < 10; y++) for (let x = 0; x < 15; x++) if (room.grid.at(x, y) === ch) return [x, y]; return null; };
  function chestToOpen(run, room) {
    const C = findTile(room, 'C');
    if (!C || room.chests[C[0] + ',' + C[1]]) return null;
    const cost = room.type === 'treasure' && run.floor.keys.some((q) => q.lock === room.key) ? 0 : AD.stat.chestCost(room.type === 'secret' ? 50 : 25, run.coef());
    return run.coins >= cost ? C : null;
  }

  // the screens around play
  function menus(top, want) {
    const name = AD.sceneName(top);
    BOT.t = (BOT.t || 0) + 1;
    if (name === 'Garden') {
      const h = top.hero, G = findTile(top.room, 'G');
      if (!G) return;
      // decide from where the hero is going: a held direction chains the next step
      const at = h.move ? [h.move.x1, h.move.y1] : [h.x, h.y];
      if (cheb(at[0], at[1], G[0], G[1]) <= 1) { if (!h.move && BOT.t % 4 === 0) want.press.add('a'); return; }
      want.dir = step(top.room, at, [[G[0], G[1] + 1]]) || [0, -1];
      return;
    }
    if (name === 'Pause' || name === 'Settings' || name === 'Items' || name === 'MapView' || name === 'Book' || name === 'Shop') { if (BOT.t % 6 === 0) want.press.add('b'); return; }
    if (BOT.t % 8 === 0) want.press.add('a');
  }

  BOT.start = function (o) { BOT.mode = (o && o.mode) || 'keys'; BOT.held = new Set(); BOT.release = []; BOT.t = 0; BOT.charging = false; };
  BOT.frame = function () {
    endFrame();
    const want = { dir: [0, 0], press: new Set(), hold: [] };
    const top = AD.top();
    if (top && top.run && AD.sceneName(top) === 'Play') { if (!top.run.over) play(top.run, want); }
    else if (top) { BOT.charging = false; menus(top, want); }
    apply(want);
  };
})();
