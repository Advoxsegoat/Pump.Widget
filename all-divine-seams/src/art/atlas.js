// The atlas (spec §9.1): every picture the game draws, in the current display mode. HD art comes
// from the Tactics painters plus the Seams' own props; True GBA art is the same picture through
// the 3:2 reducer, cached beside it. Positions handed back are in the current mode's pixels.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const A = (AD.art = AD.art || {});
  const G = AD.gfx, S = AD.spr, TL = AD.tiles;
  const T = 24, HEAD = 56;
  const gba = () => AD.display.mode === 'gba';
  const view = (c) => (gba() ? A.down32(c) : c);
  const two3 = (v) => Math.round((v * 2) / 3);
  const px = (c, x, y, w, h, col) => { c.fillStyle = col; c.fillRect(x, y, w, h); };
  const sh = (c, k) => G.shade(c, k);
  function ell(c, cx, cy, rx, ry, col, half) {
    c.fillStyle = col;
    for (let dy = -ry; dy <= ry; dy++) {
      if (half === 'top' && dy > 0) break;
      const w = Math.round(rx * Math.sqrt(Math.max(0, 1 - (dy / (ry + 0.5)) * (dy / (ry + 0.5)))));
      if (w > 0) c.fillRect(Math.round(cx - w), Math.round(cy + dy), w * 2, 1);
    }
  }
  function rnd(x, y, k) {
    let h = (x * 374761393 + y * 668265263 + (k || 0) * 2246822519) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  }
  function flipC(c, vertical) {
    const o = G.canvas(c.width, c.height);
    if (vertical) { o.x.translate(0, c.height); o.x.scale(1, -1); } else { o.x.translate(c.width, 0); o.x.scale(-1, 1); }
    o.x.drawImage(c, 0, 0);
    return o;
  }
  // a quarter turn q (clockwise) about the body's centre, lowered by dy so it lies on the ground
  function rot(c, q, dy) {
    const o = G.canvas(c.width, c.height);
    const cx = S.FRAME.ox + 12, cy = S.FRAME.oy + 16;
    o.x.translate(cx, cy + (dy || 0)); o.x.rotate((q * Math.PI) / 2); o.x.drawImage(c, -cx, -cy);
    return o;
  }

  // ---------------------------------------------------------------- figures
  // the style each look fights with; the hero's three blows each have their own
  const STYLE = {
    abarax: ['punch', 'jab', 'palm'], knuckle: ['punch', 'jab', 'palm'], firstknuckle: ['punch', 'jab', 'palm'],
    grunt: 'slash', slinger: 'shoot', bomber: 'slash', shaman: 'cast', pickpocket: 'punch',
    tough: 'slash', hound: 'punch', fusilier: 'shoot', brassmask: 'slash',
    goldtooth: 'slash', fixer: 'slash', marais: 'slash',
  };
  const ELEMENT = { shaman: 'song', firstknuckle: 'all' };
  A.STYLE = STYLE;
  const baseOf = (L) => String(L.key || '').split('|')[0];
  function styleFor(L, action) {
    const s = STYLE[baseOf(L)] || 'punch';
    if (Array.isArray(s)) return s[action === 'attack2' ? 1 : action === 'attack3' ? 2 : 0];
    return s;
  }
  // which phase of a blow frame t falls in, from the move's own wind-up and active frames
  function phaseAt(t, o) {
    const wind = o.wind != null ? o.wind : 4, act = o.act != null ? o.act : 2;
    return t < wind ? 'windup' : t < wind + act ? 'strike' : 'follow';
  }
  // the up and down blows: which hand reaches and how far (negative: drawn back to wind up)
  const REACH = {
    near: { windup: [0, -0.7], strike: [0, 1.5], follow: [0, 0.8] },
    far: { windup: [-0.7, 0], strike: [1.5, 0], follow: [0.8, 0] },
    both: { windup: [-1, -1], strike: [1.6, 1.6], follow: [0.9, 0.9] },
  };
  function frontBlow(style, ph, back) {
    if (style === 'cast' || style === 'sing') return ph === 'windup' ? { raise: 1 } : { reach: ph === 'strike' ? [1.4, 1.4] : [0.7, 0.7] };
    if (style === 'shoot') return back ? { reach: [0, 1] } : { reach: [0, ph === 'strike' ? 1.4 : 1], wa: 0 };
    const P = { reach: REACH[style === 'palm' ? 'both' : style === 'jab' ? 'far' : 'near'][ph] };
    if (!back && (style === 'slash' || style === 'thrust')) P.wa = ph === 'windup' ? 180 : 0;
    return P;
  }
  const SPIN = ['down', 'right', 'up', 'left'];
  const dcache = {};
  function derived(key, make) { return dcache[key] || (dcache[key] = make()); }

  function hd(L, action, dir, t, o) {
    const side = dir === 'left' || dir === 'right', flip = dir === 'left', back = dir === 'up';
    const u = S.unit(L);
    switch (action) {
      case 'walk': return u[dir][Math.floor(t / 4) % u[dir].length];
      case 'attack1': case 'attack2': case 'attack3': case 'cast': {
        const style = action === 'cast' ? 'cast' : styleFor(L, action);
        const ph = phaseAt(t, o);
        if (side) return S.pose(L, style, ph, flip, o.element || ELEMENT[baseOf(L)]);
        return S.frontPose(L, back, frontBlow(style, ph, back));
      }
      case 'spin': {
        // the charged spin: wound up toward the facing, then the palm sweeps all four ways
        const wind = o.wind != null ? o.wind : 2;
        if (t < wind) return side ? S.pose(L, 'palm', 'windup', flip) : S.frontPose(L, back, frontBlow('palm', 'windup', back));
        const d = SPIN[(SPIN.indexOf(dir) + Math.floor((t - wind) / 3)) % 4];
        return d === 'left' || d === 'right' ? S.pose(L, 'palm', 'strike', d === 'left') : S.frontPose(L, d === 'up', frontBlow('palm', 'strike', d === 'up'));
      }
      case 'roll': {
        // a tumble: four quarter turns over the roll, toward the way it goes
        const q = Math.min(3, Math.floor((t * 4) / (o.frames || 14)));
        return derived(L.key + '|roll|' + dir + '|' + q, () => {
          if (side) { const c = rot(S.pose(L, 'punch', 'dodge', false), q, q % 2 ? 4 : 0); return flip ? flipC(c) : c; }
          return rot(u.stand[dir], back ? (4 - q) % 4 : q, q % 2 ? 4 : 0);
        });
      }
      case 'hurt':
        if (side) return S.pose(L, styleFor(L, 'attack1'), 'hurt', flip);
        return S.frontPose(L, back, { hurt: 1, bob: 1, swing: [-1, -1] });
      case 'dead': {
        // knocked flat on their back, head away from the blow
        const left = dir === 'left' || dir === 'up';
        return derived(L.key + '|dead|' + (left ? 'l' : 'r'), () => {
          const c = rot(S.pose(L, styleFor(L, 'attack1'), 'hurt', false), 3, 8);
          return left ? flipC(c) : c;
        });
      }
      default:
        if (dir === 'down') return S.frameFor(L, 'idle', t);
        return u.stand[dir];
    }
  }
  const seenLooks = new Map();
  // a figure's frame: action idle|walk|attack1|attack2|attack3|spin|cast|roll|hurt|dead, dir
  // down|up|left|right, t frames into the action; o: {wind, act} of the move, {element} of a cast,
  // {frames} of a roll
  A.frames = function (look, action, dir, t, o) {
    const L = typeof look === 'string' ? AD.lookFor(look) : look;
    if (!seenLooks.has(L.key)) seenLooks.set(L.key, L);
    return view(hd(L, action || 'idle', dir || 'down', t || 0, o || {}));
  };

  // monsters: paper dolls through the same frames; the whelp and the rat are painted beasts
  const lookOf = (id) => ((AD.MONSTERS && AD.MONSTERS[id]) || (AD.BOSSES && AD.BOSSES[id]) || {}).look || id;
  A.monster = function (id, action, dir, t, o) {
    const look = lookOf(id);
    if (A.BEAST[look]) {
      const d = dir === 'left' ? 'left' : 'right';
      if (action === 'dead') return view(derived('beast|dead|' + look + '|' + d, () => flipC(A.beast(look, 'idle', d, 0), true)));
      return view(A.beast(look, /^attack/.test(action) ? 'attack' : action === 'walk' ? 'walk' : 'idle', d, t || 0));
    }
    return A.frames(look, action, dir, t, o);
  };
  // where a body's frame goes, relative to its tile's top-left
  const FIG = { w: 48, h: 40, ox: -12, oy: -12 };
  A.anchor = function (id) {
    const b = A.BEAST[lookOf(id)] || FIG;
    if (!gba()) return b;
    return { w: Math.ceil((b.w * 2) / 3), h: Math.ceil((b.h * 2) / 3), ox: two3(b.ox), oy: two3(b.oy) };
  };

  // ---------------------------------------------------------------- rooms
  // our glyphs as the Tactics painter knows them; the rest is the floor, with our own props on top
  const TR = { '.': '.', ',': 'g', '"': 'g', '-': '-', '~': '~', '#': '#', '%': '#', D: '#', '+': '#', '=': '#', w: 'w', c: 'c', L: 'L', v: 'v' };
  const FREE = 'p"bPfB';   // free-standing props of ours: drawn on the outlined layer
  const DOORS = 'D+=%';
  function proxy(rows, biome, night) {
    const h = rows.length, w = rows[0].length;
    return { w, h, rows, biome, night, at: (x, y) => (x < 0 || y < 0 || x >= w || y >= h ? '#' : TR[rows[y][x]] || '.') };
  }
  // which wall a door sits in
  function doorSide(x, y, w, h) { return y === 0 ? 'n' : y === h - 1 ? 's' : x === 0 ? 'w' : x === w - 1 ? 'e' : 'n'; }

  // ground marks of ours: pits and the soft shadows under our props
  function groundMarks(c, rows, b) {
    for (let Y = 0; Y < rows.length; Y++) for (let X = 0; X < rows[0].length; X++) groundMark(c, rows, X, Y, b);
  }
  function groundMark(c, rows, X, Y, b) {
    const h = rows.length, w = rows[0].length;
    const pit = (x, y) => x >= 0 && y >= 0 && x < w && y < h && rows[y][x] === 'O';
    const ch = rows[Y][X], x = X * T, y = Y * T;
    if (ch === 'O') {
      px(c, x, y, T, T, '#07060c');
      if (!pit(X, Y - 1)) { px(c, x, y, T, 7, sh(b.wallD, -0.25)); px(c, x, y, T, 1, sh(b.groundD || b.wallD, -0.1)); px(c, x, y + 7, T, 2, '#120e1a'); }
      if (!pit(X - 1, Y)) px(c, x, y, 1, T, sh(b.wallD, -0.4));
      if (!pit(X + 1, Y)) px(c, x + T - 1, y, 1, T, sh(b.wallD, -0.4));
      if (!pit(X, Y + 1)) px(c, x, y + T - 1, T, 1, sh(b.groundL || b.wallT, -0.05));
      if (rnd(X, Y, 3) < 0.5) px(c, x + 6 + ((rnd(X, Y, 4) * 10) | 0), y + 14, 1, 1, '#2a2438');
    } else if (FREE.indexOf(ch) >= 0 || ch === 'C') {
      c.fillStyle = 'rgba(10,8,20,0.24)';
      for (let dy = -2; dy <= 2; dy++) { const ww = Math.round(9 * Math.sqrt(1 - (dy / 3) * (dy / 3))); c.fillRect(x + 12 - ww, y + 21 + dy, ww * 2, 1); }
    }
  }

  // our free-standing props, facing the viewer, on the tile whose top-left is (x, y)
  function freeProp(c, ch, X, Y, x, y, b) {
    switch (ch) {
      case 'p': { // a clay pot
        const k = rnd(X, Y, 1) < 0.5 ? '#a8643a' : '#9a5a3e';
        ell(c, x + 12, y + 15, 7, 7, sh(k, -0.25)); ell(c, x + 11, y + 14, 6, 6, k);
        px(c, x + 8, y + 5, 8, 4, sh(k, -0.1)); px(c, x + 7, y + 4, 10, 2, sh(k, 0.22)); px(c, x + 9, y + 5, 6, 1, '#2a1a14');
        px(c, x + 8, y + 11, 2, 4, sh(k, 0.35)); px(c, x + 7, y + 16, 10, 1, sh(k, -0.18));
        break;
      }
      case 'b': { // a powder barrel
        px(c, x + 5, y + 5, 14, 17, '#8a5a34'); px(c, x + 4, y + 8, 16, 11, '#8a5a34');
        px(c, x + 15, y + 5, 4, 17, '#6a4228'); px(c, x + 7, y + 6, 2, 15, '#a8744a');
        px(c, x + 4, y + 8, 16, 1, '#3a3a44'); px(c, x + 4, y + 18, 16, 1, '#3a3a44');
        ell(c, x + 12, y + 5, 7, 2, '#b08a5a'); px(c, x + 8, y + 5, 8, 1, '#6a4228');
        px(c, x + 9, y + 11, 6, 5, '#c83a3a'); px(c, x + 11, y + 12, 2, 2, '#f4eee0');
        px(c, x + 12, y + 1, 1, 3, '#3a3a44'); px(c, x + 13, y, 1, 1, '#ffb347');
        break;
      }
      case '"': { // tall grass
        const cols = [b.treeD, b.tree, b.treeL];
        for (let i = 0; i < 8; i++) {
          const bx = x + 1 + i * 3, ht = 12 + ((rnd(X, Y, i) * 8) | 0), lean = rnd(X, Y, 10 + i) < 0.5 ? -1 : 1;
          const col = cols[i % 3];
          for (let k = 0; k < ht; k++) px(c, bx + (k > ht * 0.6 ? lean : 0), y + 23 - k, 2, 1, col);
          px(c, bx + lean, y + 23 - ht, 1, 1, sh(col, 0.3));
        }
        break;
      }
      case 'P': { // a stone pedestal
        px(c, x + 7, y + 6, 10, 15, b.wallF); px(c, x + 14, y + 6, 3, 15, b.wallD); px(c, x + 8, y + 6, 1, 15, sh(b.wallT, 0.1));
        px(c, x + 4, y + 2, 16, 5, b.wallT); px(c, x + 4, y + 2, 16, 1, sh(b.wallT, 0.18)); px(c, x + 4, y + 6, 16, 1, b.wallD);
        px(c, x + 5, y + 20, 14, 3, b.wallD); px(c, x + 5, y + 20, 14, 1, b.wallF);
        break;
      }
      case 'B': { // a push block
        px(c, x + 2, y - 2, 20, 12, b.wallT); px(c, x + 2, y - 2, 20, 1, sh(b.wallT, 0.18));
        px(c, x + 2, y + 10, 20, 12, b.wallF); px(c, x + 2, y + 10, 20, 1, b.wallD); px(c, x + 19, y + 10, 3, 12, b.wallD);
        [[5, 13], [16, 13], [5, 19], [16, 19]].forEach(([dx, dy]) => px(c, x + dx, y + dy, 1, 1, sh(b.wallF, 0.3)));
        break;
      }
      case 'f': { // a campfire's stones and logs (the flames are a sprite)
        for (let i = 0; i < 9; i++) {
          const a = (i / 9) * Math.PI * 2, sx = x + 12 + Math.cos(a) * 8, sy = y + 16 + Math.sin(a) * 4;
          px(c, Math.round(sx) - 1, Math.round(sy) - 1, 3, 2, i % 2 ? '#7a7a86' : '#5a5a66'); px(c, Math.round(sx) - 1, Math.round(sy) - 1, 2, 1, '#9a9aa6');
        }
        ell(c, x + 12, y + 16, 6, 3, '#2a2020');
        px(c, x + 6, y + 15, 12, 2, '#5a3a22'); px(c, x + 9, y + 13, 2, 6, '#4a2c18'); px(c, x + 14, y + 13, 2, 6, '#6a4228');
        px(c, x + 10, y + 16, 4, 1, '#ff8a3a');
        break;
      }
    }
  }

  // doors in the room's walls, and cracks in a wall a bomb can open
  function doorProp(c, ch, side, x, y, b) {
    const dark = '#0c0812', wood = '#6a4228', woodL = '#8a5a38', woodD = '#4a2c18', iron = '#5a5a66', ironL = '#9a9aa8';
    if (ch === '%') {
      const crack = (pts) => { for (let i = 0; i + 1 < pts.length; i++) { const [x0, y0] = pts[i], [x1, y1] = pts[i + 1]; const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)); for (let k = 0; k <= n; k++) px(c, Math.round(x + x0 + ((x1 - x0) * k) / n), Math.round(y + y0 + ((y1 - y0) * k) / n), 1, 1, '#1a1420'); } };
      if (side === 'n' || side === 's') { crack([[8, 11], [11, 15], [9, 18], [13, 22]]); crack([[11, 15], [16, 14], [18, 19]]); px(c, x + 12, y + 16, 1, 1, sh(b.wallF, 0.3)); }
      else { crack([[6, 4], [10, 9], [8, 14], [13, 19]]); crack([[10, 9], [16, 8]]); }
      return;
    }
    if (side === 'n') {
      c.clearRect(x, y + 4, T, T - 4);
      px(c, x, y + 4, 4, T - 4, b.wallF); px(c, x + 20, y + 4, 4, T - 4, b.wallF);
      px(c, x + 3, y + 4, 1, T - 4, b.wallD); px(c, x + 20, y + 4, 1, T - 4, b.wallD);
      px(c, x + 4, y + 4, 16, T - 8, dark); px(c, x + 4, y + 4, 16, 2, sh(b.wallD, -0.3));
      if (ch === '+') { px(c, x + 5, y + 6, 14, T - 10, wood); px(c, x + 5, y + 6, 14, 1, woodL); px(c, x + 11, y + 6, 2, T - 10, woodD); px(c, x + 10, y + 12, 4, 4, G.C.gold); px(c, x + 11, y + 14, 2, 1, '#3a2418'); }
      if (ch === '=') for (let i = 0; i < 4; i++) { px(c, x + 5 + i * 4, y + 4, 2, T - 6, iron); px(c, x + 5 + i * 4, y + 4, 1, T - 6, ironL); }
    } else if (side === 's') {
      c.clearRect(x, 0, T, y + T);
      px(c, x, y - 9, 3, 33, b.wallT); px(c, x + 21, y - 9, 3, 33, b.wallT); px(c, x + 2, y - 9, 1, 33, b.wallD); px(c, x + 21, y - 9, 1, 33, b.wallD);
      px(c, x + 3, y + 14, 18, 10, dark);
      if (ch === '+') { px(c, x + 3, y + 8, 18, 9, wood); px(c, x + 3, y + 8, 18, 1, woodL); px(c, x + 11, y + 8, 2, 9, woodD); px(c, x + 10, y + 10, 4, 4, G.C.gold); }
      if (ch === '=') for (let i = 0; i < 4; i++) { px(c, x + 4 + i * 4, y - 2, 2, 22, iron); px(c, x + 4 + i * 4, y - 2, 1, 22, ironL); }
    } else {
      const out = side === 'w' ? x : x + 14;
      c.clearRect(x, y, T, T);
      px(c, x, y, T, 3, b.wallT); px(c, x, y + 21, T, 3, b.wallT); px(c, x, y + 2, T, 1, b.wallD); px(c, x, y + 21, T, 1, b.wallD);
      px(c, out, y + 3, 10, 18, dark); px(c, side === 'w' ? x + 10 : x + 13, y + 3, 1, 18, sh(b.wallD, -0.3));
      if (ch === '+') { const dx = side === 'w' ? x + 9 : x + 11; px(c, dx, y + 3, 4, 18, wood); px(c, dx, y + 3, 1, 18, woodL); px(c, dx, y + 10, 4, 4, G.C.gold); }
      if (ch === '=') for (let i = 0; i < 4; i++) { px(c, x + 2, y + 5 + i * 4, 20, 2, iron); px(c, x + 2, y + 5 + i * 4, 20, 1, ironL); }
    }
  }

  // outline a layer of free props the way the Tactics painter does, then lay it on the row
  function outlined(row, layer) {
    const o = G.canvas(layer.width, layer.height);
    [[-1, 0], [1, 0], [0, -1], [0, 1]].forEach(([dx, dy]) => o.x.drawImage(layer, dx, dy));
    o.x.globalCompositeOperation = 'source-in';
    o.x.fillStyle = 'rgba(12,10,24,0.72)';
    o.x.fillRect(0, 0, o.width, o.height);
    row.x.drawImage(o, 0, 0);
    row.x.drawImage(layer, 0, 0);
  }

  // one row of props: the Tactics painter's (row, or null), with ours laid on
  function ourRow(row, rows, Y, b) {
    const h = rows.length, w = rows[0].length;
    let layer = null;
    for (let X = 0; X < w; X++) {
      const ch = rows[Y][X];
      if (FREE.indexOf(ch) < 0 && DOORS.indexOf(ch) < 0) continue;
      if (!row) row = G.canvas(w * T, HEAD + T);
      if (DOORS.indexOf(ch) >= 0) doorProp(row.x, ch, doorSide(X, Y, w, h), X * T, HEAD, b);
      else { if (!layer) layer = G.canvas(w * T, HEAD + T); freeProp(layer.x, ch, X, Y, X * T, HEAD, b); }
    }
    if (layer) outlined(row, layer);
    return row;
  }
  function bakeHD(rows, biome, night) {
    const map = proxy(rows, biome, night);
    const B = TL.bake(map, {});
    const b = B.biome;
    const h = rows.length, w = rows[0].length;
    B.grounds.forEach((g) => groundMarks(g.x, rows, b));
    for (let Y = 0; Y < h; Y++) B.rows[Y] = ourRow(B.rows[Y], rows, Y, b);
    // light from our own props
    for (let Y = 0; Y < h; Y++) for (let X = 0; X < w; X++) {
      const ch = rows[Y][X];
      if (ch === 'f') B.lights.push({ x: X * T + 12, y: Y * T + 12, r: 56, c: '#ffb347', a: 0.4, flicker: 1 });
      if (ch === 'G') B.lights.push({ x: X * T + 12, y: Y * T - 6, r: 60, c: '#a98cf0', a: 0.3 });
    }
    return { ground: B.grounds, rows: B.rows, lights: B.lights, biome: b, head: HEAD, tile: T };
  }
  // the room in gba: the reducer on every layer; each row is padded by a pixel so its tile starts
  // on a 3-pixel boundary (56 + 1 = 57), which puts the reduced tile at 38
  const padRow = (c) => { if (!c) return null; const o = G.canvas(c.width, c.height + 1); o.x.drawImage(c, 0, 1); return A.down32(o); };
  function toGba(R) {
    const pad = padRow;
    return {
      ground: R.ground.map((g) => A.down32(g)), rows: R.rows.map(pad),
      lights: R.lights.map((l) => Object.assign({}, l, { x: two3(l.x), y: two3(l.y), r: two3(l.r) })),
      biome: R.biome, head: 38, tile: 16,
    };
  }
  const rooms = new Map();
  const remember = (k, v) => { rooms.set(k, v); if (rooms.size > 48) rooms.delete(rooms.keys().next().value); return v; };
  // rows: the room's glyph rows; biome: the depth's ('city', 'dungeon', 'interior'); night: the depth's
  // returns {ground: canvas[4] (animation frames), rows: canvas|null per tile row (each drawn at
  // y * tile - head), lights, biome, head, tile}
  const hdRoom = (k, rows, biome, night) => rooms.get('hd|' + k) || remember('hd|' + k, bakeHD(rows, biome, night));
  const keyOf = (rows, biome, night) => biome + '|' + (night ? 1 : 0) + '|' + rows.join('/');
  A.room = function (rows, biome, night) {
    const k = keyOf(rows, biome, night);
    const hdR = hdRoom(k, rows, biome, night);
    if (!gba()) return hdR;
    return rooms.get('gba|' + k) || remember('gba|' + k, toGba(hdR));
  };

  // a room's art of its own, which A.patch changes in place as the room changes in play (a pot
  // breaks, grass burns, a door opens): only the changed tiles and the rows round them are redone
  const copy = (c) => { if (!c) return null; const o = G.canvas(c.width, c.height); o.x.drawImage(c, 0, 0); return o; };
  const cloneArt = (R) => Object.assign({}, R, { ground: R.ground.map(copy), rows: R.rows.map(copy), lights: R.lights.slice() });
  A.roomArt = function (rows, biome, night) {
    const k = keyOf(rows, biome, night);
    const hdR = hdRoom(k, rows, biome, night);
    const art = { rows: rows.slice(), biome, night, mode: AD.display.mode, hd: cloneArt(hdR) };
    if (gba()) art.gba = cloneArt(rooms.get('gba|' + k) || remember('gba|' + k, toGba(hdR)));
    art.view = art.gba || art.hd;
    return art;
  };
  A.patch = function (art, rows) {
    const h = rows.length, w = rows[0].length;
    const tiles = new Set(), rowsY = new Set();
    for (let Y = 0; Y < h; Y++) for (let X = 0; X < w; X++) {
      if (art.rows[Y][X] === rows[Y][X]) continue;
      // water edges and wall faces join their neighbours, so the ring round a change is redone too
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const x = X + dx, y = Y + dy;
        if (x >= 0 && y >= 0 && x < w && y < h) tiles.add(y * w + x);
      }
      for (let dy = -1; dy <= 1; dy++) if (Y + dy >= 0 && Y + dy < h) rowsY.add(Y + dy);
    }
    if (!tiles.size) return false;
    const map = proxy(rows, art.biome, art.night);
    const hd = art.hd, b = hd.biome;
    for (const i of tiles) {
      const X = i % w, Y = (i / w) | 0;
      TL.groundTile(hd.ground, map, X, Y);
      hd.ground.forEach((g) => groundMark(g.x, rows, X, Y, b));
    }
    for (const Y of rowsY) hd.rows[Y] = ourRow(TL.bakeRow(map, Y, {}), rows, Y, b);
    if (art.gba) {
      for (const i of tiles) {
        const X = i % w, Y = (i / w) | 0;
        hd.ground.forEach((g, fr) => A.down32Into(g, X * T, Y * T, T, T, art.gba.ground[fr]));
      }
      for (const Y of rowsY) art.gba.rows[Y] = padRow(hd.rows[Y]);
    }
    art.rows = rows.slice();
    return true;
  };

  // ---------------------------------------------------------------- sprites that change in play
  const sprites = {};
  function sprite(key, w, h, paint) {
    if (!sprites[key]) { const c = G.canvas(w, h); paint(c.x); sprites[key] = c; }
    return sprites[key];
  }
  const TRAP_ICON = {
    spike: (c) => { [[8, 8], [14, 8], [8, 14], [14, 14]].forEach(([x, y]) => { px(c, x, y, 2, 2, '#1a1a20'); px(c, x, y, 1, 1, '#c8ccd8'); }); },
    alarm: (c) => { px(c, 10, 8, 4, 6, '#e8c170'); px(c, 9, 13, 6, 1, '#e8c170'); px(c, 11, 14, 2, 1, '#8a6a2a'); px(c, 10, 8, 1, 3, '#fff2b0'); },
    fire: (c) => { px(c, 11, 7, 2, 10, '#ff8a3a'); px(c, 8, 11, 8, 2, '#ff8a3a'); px(c, 11, 11, 2, 2, '#fff2b0'); },
    gas: (c) => { for (let i = 0; i < 3; i++) px(c, 8, 8 + i * 3, 8, 1, '#7aff9a'); px(c, 8, 8, 1, 7, '#2a3a2a'); },
    pit: (c) => { const z = [[7, 8], [10, 11], [9, 14], [13, 16], [16, 13]]; z.forEach(([x, y]) => px(c, x, y, 2, 1, '#1a1a20')); },
  };
  const SPRITES = {
    // {big, open}
    chest(o) {
      return sprite('chest|' + (o.big ? 1 : 0) + (o.open ? 1 : 0), 24, 36, (c) => {
        const y = 12, x0 = o.big ? 1 : 4, w = o.big ? 22 : 16, gold = G.C.gold;
        px(c, x0, y + 11, w, 11, o.big ? '#5a3a6a' : '#7a4a2a'); px(c, x0, y + 21, w, 1, '#2a1828');
        px(c, x0, y + 14, w, 1, gold); px(c, x0, y + 11, 1, 11, gold); px(c, x0 + w - 1, y + 11, 1, 11, gold);
        if (o.open) {
          px(c, x0, y + 4, w, 7, o.big ? '#3a2448' : '#5a3418'); px(c, x0, y + 4, w, 1, o.big ? '#7a5a8a' : '#7a4a2a');
          px(c, x0 + 1, y + 11, w - 2, 3, '#120c14');
          if (o.big) px(c, x0 + 3, y + 11, w - 6, 1, '#a98cf0');
        } else {
          px(c, x0, y + 6, w, 6, o.big ? '#6a4a7a' : '#9a6a3a'); px(c, x0, y + 6, w, 1, o.big ? '#8a6a9a' : '#c08a5a');
          px(c, 10, y + 11, 4, 5, gold); px(c, 11, y + 13, 2, 2, o.big ? '#a98cf0' : '#3a2418');
          if (o.big) { px(c, x0 + 3, y + 6, 1, 6, gold); px(c, x0 + w - 4, y + 6, 1, 6, gold); }
        }
      });
    },
    // {kind, seen}: an unspotted trap is only its plate (drawn faint); a spotted one shows what it is
    trap(o) {
      return sprite('trap|' + o.kind + '|' + (o.seen ? 1 : 0), 24, 24, (c) => {
        px(c, 5, 5, 14, 1, '#2a2a32'); px(c, 5, 18, 14, 1, '#2a2a32'); px(c, 5, 5, 1, 14, '#2a2a32'); px(c, 18, 5, 1, 14, '#2a2a32');
        if (!o.seen) return;
        px(c, 6, 6, 12, 12, '#5a5a64'); px(c, 6, 6, 12, 1, '#7a7a86');
        (TRAP_ICON[o.kind] || TRAP_ICON.spike)(c);
      });
    },
    // {charge 0..1, open}: the Seam Gate, a standing arch over the tile with the seam inside it
    gate(o, t) {
      const lit = Math.round((o.charge || 0) * 12), fr = o.open ? (t >> 3) % 4 : (t >> 4) % 2;
      return sprite('gate|' + (o.open ? 'o' : lit) + '|' + fr, 48, 60, (c) => {
        const stone = '#d8d2c2', stoneD = '#a8a08a', stoneL = '#f0ebe0';
        ell(c, 24, 54, 13, 5, '#5a5a6a'); ell(c, 24, 54, 10, 3, '#1a1428');
        px(c, 12, 18, 6, 38, stone); px(c, 16, 18, 2, 38, stoneD); px(c, 12, 18, 1, 38, stoneL);
        px(c, 30, 18, 6, 38, stone); px(c, 34, 18, 2, 38, stoneD); px(c, 30, 18, 1, 38, stoneL);
        px(c, 9, 12, 30, 7, stone); px(c, 9, 12, 30, 1, stoneL); px(c, 9, 18, 30, 1, stoneD);
        // the twelve runes round the arch light as the charge fills
        for (let i = 0; i < 12; i++) {
          const rx = i < 4 ? 14 : i < 8 ? 13 + (i - 4) * 6 : 32, ry = i < 4 ? 50 - i * 9 : i < 8 ? 14 : 23 + (i - 8) * 9;
          px(c, rx + (i >= 4 && i < 8 ? 0 : 1), ry, 2, 2, i < lit || o.open ? '#ffe28a' : '#5a4a6a');
        }
        if (o.open) {
          ell(c, 24, 36, 5, 16, '#ffe28a'); ell(c, 24, 36, 3, 12, '#ffffff');
          for (let i = 0; i < 4; i++) { const a = ((i + fr / 4) / 4) * Math.PI * 2; px(c, Math.round(24 + Math.cos(a) * 4), Math.round(36 + Math.sin(a) * 12), 1, 1, '#a98cf0'); }
        } else {
          const wide = 1 + Math.round(((o.charge || 0) * 6) / 2) * 2;
          px(c, 24 - (wide >> 1), 22, wide, 30, lit ? '#c9b0ff' : '#6a5a9a');
          px(c, 24, 22 + fr * 3, 1, 26 - fr * 3, lit > 6 ? '#ffe28a' : '#a98cf0');
        }
      });
    },
    // {f}: a campfire's flames, four frames
    flame(o) {
      const f = (o.f || 0) % 4;
      return sprite('flame|' + f, 24, 36, (c) => {
        const hts = [[9, 13, 8], [11, 9, 12], [8, 12, 10], [12, 10, 9]][f];
        [[8, '#ff6a3a'], [12, '#ffb347'], [16, '#ff6a3a']].forEach(([fx, col], i) => {
          const ht = hts[i];
          for (let k = 0; k < ht; k++) { const ww = Math.max(1, Math.round(3 * (1 - k / ht))); px(c, fx - (ww >> 1) + 1, 12 + 16 - k, ww, 1, col); }
        });
        px(c, 12, 12 + 10, 2, 5, '#fff2b0');
      });
    },
  };
  // things on the floor to pick up: {kind, c (a draught's colour), scroll, tier, amount}
  const TIER_C = { common: '#f4eee0', uncommon: '#6ad06a', legendary: '#ef5f6a', boss: '#e8c170', equipment: '#ffb347', spent: '#8a8a96' };
  A.TIER_C = TIER_C;
  const PICK = {
    coins(c, o, f) {
      const w = [5, 3, 1, 3][f], n = o.amount >= 8 ? 3 : o.amount >= 3 ? 2 : 1;
      const at = [[12, 15], [8, 17], [15, 18]].slice(0, n);
      for (const [x, y] of at) { px(c, x - (w >> 1), y - 3, w, 6, '#a8803a'); px(c, x - (w >> 1), y - 3, Math.max(1, w - 1), 5, '#e8c170'); if (w > 2) px(c, x - 1, y - 2, 1, 2, '#fff2b0'); }
    },
    heart(c) { px(c, 8, 10, 3, 2, '#e8344e'); px(c, 13, 10, 3, 2, '#e8344e'); px(c, 7, 11, 10, 3, '#e8344e'); px(c, 8, 14, 8, 2, '#c8203a'); px(c, 10, 16, 4, 1, '#c8203a'); px(c, 11, 17, 2, 1, '#a8102a'); px(c, 8, 11, 2, 1, '#ffb0b8'); },
    key(c) { ell(c, 8, 13, 3, 3, '#e8c170'); ell(c, 8, 13, 1, 1, '#4a3a2a'); px(c, 10, 12, 8, 2, '#e8c170'); px(c, 15, 14, 1, 2, '#e8c170'); px(c, 17, 14, 1, 3, '#e8c170'); px(c, 10, 12, 8, 1, '#fff2b0'); },
    item(c, o) {
      const k = TIER_C[o.tier] || TIER_C.common;
      for (let i = 0; i < 5; i++) px(c, 12 - i, 9 + i, i * 2 + 1, 1, k);
      for (let i = 0; i < 4; i++) px(c, 12 - (3 - i), 14 + i, (3 - i) * 2 + 1, 1, sh(k, -0.25));
      px(c, 11, 10, 1, 3, '#ffffff');
    },
    cons(c, o) {
      if (o.bomb) { ell(c, 12, 15, 4, 4, '#2a2a30'); px(c, 10, 12, 2, 2, '#5a5a66'); px(c, 13, 9, 1, 3, '#8a6a4a'); return; }
      if (o.scroll) { px(c, 7, 9, 10, 9, '#efe2c4'); px(c, 6, 8, 12, 2, '#c8b890'); px(c, 6, 17, 12, 2, '#c8b890'); px(c, 9, 12, 6, 1, o.c || '#8a6a3a'); px(c, 9, 14, 4, 1, o.c || '#8a6a3a'); return; }
      const k = o.c || '#c8ccd8';
      px(c, 11, 6, 2, 3, '#8a6a4a'); px(c, 10, 9, 4, 2, '#c8d8e8');
      ell(c, 12, 15, 5, 4, '#c8d8e8'); ell(c, 12, 16, 4, 3, k); px(c, 9, 13, 1, 2, '#ffffff');
    },
    armour(c) { px(c, 7, 8, 10, 10, '#8a8e9a'); px(c, 5, 8, 3, 4, '#8a8e9a'); px(c, 16, 8, 3, 4, '#8a8e9a'); px(c, 10, 8, 4, 2, '#3a3a44'); px(c, 8, 9, 1, 8, '#c0c8d8'); px(c, 7, 17, 10, 1, '#5a5e6a'); },
    lore(c) { px(c, 7, 7, 10, 12, '#efe2c4'); px(c, 15, 7, 2, 2, '#c8b890'); for (let i = 0; i < 4; i++) px(c, 9, 10 + i * 2, 6 - (i % 2) * 2, 1, '#8a6a3a'); },
    petal(c) { ell(c, 12, 14, 3, 4, '#e8607e'); px(c, 11, 11, 1, 3, '#ffb0c8'); px(c, 12, 18, 1, 2, '#6ad06a'); },
  };
  SPRITES.pickup = function (o, t) {
    const f = o.kind === 'coins' ? (t >> 3) % 4 : 0;
    const key = 'pick|' + o.kind + '|' + (o.c || '') + (o.scroll ? 's' : '') + (o.bomb ? 'b' : '') + '|' + (o.tier || '') + '|' + (o.kind === 'coins' ? (o.amount >= 8 ? 3 : o.amount >= 3 ? 2 : 1) : '') + '|' + f;
    return sprite(key, 24, 24, (c) => (PICK[o.kind] || PICK.item)(c, o, f));
  };
  // a lit bomb on the floor, its fuse sparking; {hot} in its last moments
  SPRITES.bomb = function (o, t) {
    return sprite('bomb|' + (o.hot ? 1 : 0) + '|' + ((t >> 2) % 2), 24, 24, (c) => {
      ell(c, 12, 15, 5, 5, o.hot && (t >> 2) % 2 ? '#8a2a2a' : '#2a2a30'); px(c, 9, 11, 3, 2, '#5a5a66');
      px(c, 13, 8, 1, 3, '#8a6a4a'); px(c, 14, 6, 1, 2, (t >> 2) % 2 ? '#ffb347' : '#fff2b0'); px(c, 15, 5, 1, 1, '#ff6a3a');
    });
  };
  // what monsters throw and shoot: {kind}
  SPRITES.shot = function (o) {
    return sprite('shot|' + o.kind, 12, 12, (c) => {
      if (o.kind === 'ball') { px(c, 4, 4, 4, 4, '#2a2a30'); px(c, 5, 5, 1, 1, '#c8ccd8'); }
      else { ell(c, 6, 6, 2, 2, '#9a948a'); px(c, 5, 5, 1, 1, '#d8d2c2'); }
    });
  };
  const SPRITE_AT = { chest: [0, -12], trap: [0, 0], gate: [-12, -36], flame: [0, -12], pickup: [0, 0], bomb: [0, 0], shot: [-6, -6] };
  // a prop that changes in play: {c, ox, oy}, placed relative to its tile's top-left
  A.sprite = function (name, o, t) {
    const c = SPRITES[name](o || {}, t || 0);
    const [ox, oy] = SPRITE_AT[name];
    return gba() ? { c: A.down32(c), ox: two3(ox), oy: two3(oy) } : { c, ox, oy };
  };

  // ---------------------------------------------------------------- mode changes
  const ACTIONS = ['idle', 'walk', 'attack1', 'attack2', 'attack3', 'spin', 'cast', 'roll', 'hurt', 'dead'];
  // the frames a figure is drawn with, so a mode change rebuilds them before play resumes
  const SAMPLES = [0, 4, 5, 8, 12, 40];
  function warm(L) {
    for (const a of ACTIONS) for (const d of SPIN) for (const t of SAMPLES) A.frames(L, a, d, t);
  }
  // every frame these monsters can show, made now rather than the first time one is seen
  A.warm = function (ids) {
    for (const id of ids) {
      const look = lookOf(id);
      if (A.BEAST[look]) { for (const a of ['idle', 'walk', 'attack1', 'dead']) for (const d of ['left', 'right']) for (const t of [0, 10, 20]) A.monster(id, a, d, t); }
      else warm(AD.lookFor(look));
    }
  };
  A.build = function (mode) {
    if (mode !== 'gba') return;
    warm(AD.lookFor('abarax'));
    for (const L of seenLooks.values()) warm(L);
  };
  if (AD.display && AD.display.onChange) AD.display.onChange.push((m) => A.build(m));
})(window.AD);
