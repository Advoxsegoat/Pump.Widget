// The Seams' beasts that are not paper dolls: the one-eyed wyvern whelp, the sewer rat and the gray
// hound. Each is painted into a raster, shaded and outlined like the figures, two frames a pose.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const G = AD.gfx, Ras = AD.spr.Ras;
  const OUT = '#120c1a';
  const finish = (r) => { r.shade(0.12); r.outline(OUT); return r.canvas(); };
  const flip = (c) => { const o = G.canvas(c.width, c.height); o.x.translate(c.width, 0); o.x.scale(-1, 1); o.x.drawImage(c, 0, 0); return o; };

  // a whelp, facing right: wings up (f=0) or down (f=1); `bite` opens the jaw and stretches the neck
  function whelp(f, bite, pal) {
    const r = new Ras(40, 34);
    const body = pal.body, belly = pal.belly, wing = pal.wing, eye = pal.eye;
    // tail
    r.line(4, 22, 12, 20, body); r.line(4, 23, 12, 21, body); r.set(3, 22, G.shade(body, -0.2)); r.set(2, 21, G.shade(body, -0.2));
    // far wing
    if (f === 0) r.poly([[16, 16], [10, 4], [22, 8], [24, 16]], G.shade(wing, -0.25));
    else r.poly([[16, 18], [8, 24], [22, 22], [24, 18]], G.shade(wing, -0.25));
    // body
    r.ellipse(19, 20, 8, 5, body);
    r.ellipse(19, 22, 6, 3, belly);
    // legs
    r.rect(14, 24, 2, 4, G.shade(body, -0.15)); r.rect(22, 24, 2, 4, G.shade(body, -0.15));
    r.row(28, 13, 16, '#e8e0c8'); r.row(28, 21, 24, '#e8e0c8');
    // neck and head
    const nx = bite ? 30 : 27, hy = bite ? 15 : 13;
    r.line(24, 17, nx, hy + 2, body); r.line(25, 18, nx + 1, hy + 3, body); r.line(24, 18, nx, hy + 3, body);
    r.ellipse(nx + 3, hy, 4, 3, body);
    // the one eye: large, lidded, gold
    r.ellipse(nx + 3, hy - 1, 2, 2, '#f4eee0'); r.set(nx + 3, hy - 1, eye); r.set(nx + 4, hy - 1, eye); r.set(nx + 3, hy - 2, '#ffffff');
    r.row(hy - 3, nx + 1, nx + 5, G.shade(body, -0.3));
    // horns
    r.set(nx + 1, hy - 4, '#e8e0c8'); r.set(nx, hy - 5, '#e8e0c8');
    // jaw
    if (bite) { r.row(hy + 2, nx + 4, nx + 8, G.shade(body, -0.1)); r.row(hy + 4, nx + 3, nx + 7, G.shade(body, -0.1)); r.set(nx + 6, hy + 3, '#ffffff'); r.set(nx + 8, hy + 3, '#ffffff'); }
    else r.row(hy + 2, nx + 4, nx + 7, G.shade(body, -0.15));
    // near wing
    if (f === 0) r.poly([[18, 16], [20, 0], [30, 6], [26, 16]], wing);
    else r.poly([[18, 18], [16, 30], [28, 26], [26, 18]], wing);
    r.line(20, 1, 19, 16, G.shade(wing, -0.3));
    return finish(r);
  }
  // a sewer rat, facing right: legs scurry (f), the head lunges and the jaw opens to bite
  function rat(f, bite) {
    const r = new Ras(30, 18);
    const c = '#6a5a52', d = '#4a3e38', l = '#8a7a70', pink = '#d8a098';
    const hx = bite ? 2 : 0;
    // tail, curling behind
    r.line(1, 10 + f, 4, 12, pink); r.line(4, 12, 9, 12, pink); r.set(0, 9 + f, pink);
    // body and belly
    r.ellipse(14, 11, 8, 4, c); r.row(14, 9, 19, d); r.ellipse(13, 9, 4, 1, l);
    // legs: two pairs that swap as it runs
    const lx = f ? [8, 17] : [10, 15];
    r.rect(lx[0], 14, 2, 2, d); r.rect(lx[1], 14, 2, 2, d); r.set(lx[0] + 1, 16, pink); r.set(lx[1] + 1, 16, pink);
    // head, ear, eye, nose and whiskers
    r.ellipse(22 + hx, 10, 4, 3, c); r.ellipse(19 + hx, 6, 2, 2, d); r.set(19 + hx, 6, pink);
    r.set(23 + hx, 9, '#ff4a4a'); r.set(23 + hx, 8, '#ffd0d0');
    r.set(26 + hx, 10, pink); r.set(27 + hx, 10, pink);
    r.set(25 + hx, 12, l); r.set(27 + hx, 12, l);
    if (bite) { r.row(12, 23 + hx, 27 + hx, '#2a1418'); r.set(24 + hx, 13, '#ffffff'); r.set(26 + hx, 13, '#ffffff'); r.set(25 + hx, 11, '#ffffff'); }
    return finish(r);
  }

  // a gray hound, facing right: lean, low and long-legged; it lopes (f), and pounces with its body
  // stretched flat, forelegs reaching and jaws open
  function hound(f, bite) {
    const r = new Ras(34, 22);
    const c = '#7a7a88', d = '#55556a', l = '#a4a4b2', eye = '#ff5a4a';
    const lunge = bite ? 3 : 0, by = bite ? 11 : 12;
    // tail, raised behind
    if (bite) { r.line(2, by - 1, 8, by, c); r.line(2, by, 8, by + 1, d); }
    else { r.line(3, 5 + f, 8, by - 1, c); r.line(4, 5 + f, 9, by - 1, c); }
    // body: a deep chest and a tucked waist
    r.ellipse(14 + lunge, by, 7, 3, c);
    r.ellipse(20 + lunge, by, 4, 4, c);
    r.row(by - 3, 10 + lunge, 19 + lunge, d);
    r.ellipse(19 + lunge, by + 2, 3, 1, l);
    // legs: thin, two pairs that swap as it lopes; in the pounce, stretched fore and aft
    const leg = (x0, y0, x1, y1) => { r.line(x0, y0, x1, y1, d); r.line(x0 + 1, y0, x1 + 1, y1, c); };
    if (bite) { leg(21 + lunge, by + 2, 28, by + 6); leg(9, by + 2, 3, by + 6); leg(11, by + 2, 6, by + 7); }
    else {
      const a = f ? [-2, 2] : [2, -2];
      leg(20, by + 2, 20 + a[0], 20); leg(22, by + 2, 22 + a[1], 20);
      leg(9, by + 2, 9 + a[1], 20); leg(11, by + 2, 11 + a[0], 20);
    }
    // neck, head and long muzzle
    const hx = 25 + lunge + (bite ? 1 : 0), hy = bite ? by - 1 : by - 4;
    r.line(21 + lunge, by - 2, hx - 1, hy + 1, c); r.line(22 + lunge, by - 1, hx, hy + 2, c);
    r.ellipse(hx + 1, hy, 3, 2, c);
    r.rect(hx + 3, hy, 4, 2, c); r.set(hx + 7, hy, '#1a1418');
    // ear, pricked back, and the red eye
    r.set(hx - 1, hy - 3, d); r.set(hx, hy - 3, d); r.set(hx, hy - 2, d); r.set(hx - 1, hy - 2, d);
    r.set(hx + 2, hy - 1, eye); r.set(hx + 3, hy - 1, '#ffd0c8');
    // jaw: shut, or open with teeth
    if (bite) { r.row(hy + 2, hx + 2, hx + 7, '#2a1418'); r.row(hy + 3, hx + 2, hx + 6, c); r.set(hx + 4, hy + 2, '#ffffff'); r.set(hx + 6, hy + 2, '#ffffff'); }
    else r.row(hy + 2, hx + 2, hx + 6, d);
    return finish(r);
  }

  const PAL = { whelp: { body: '#6a8a4a', belly: '#c8c890', wing: '#4a6a3a', eye: '#ffb000' } };
  const cache = {};
  // frame for a beast: action 'idle'|'walk'|'attack'|'hurt', dir, t
  AD.art = AD.art || {};
  AD.art.beast = function (kind, action, dir, t) {
    const f = Math.floor(t / (kind === 'whelp' ? 10 : 6)) % 2;
    const bite = action === 'attack' ? 1 : 0;
    const key = kind + '|' + f + '|' + bite + '|' + (dir === 'left' ? 'l' : 'r');
    if (cache[key]) return cache[key];
    let c = kind === 'rat' ? rat(f, bite) : kind === 'hound' ? hound(f, bite) : whelp(f, bite, PAL.whelp);
    if (dir === 'left') c = flip(c);
    cache[key] = c;
    return c;
  };
  AD.art.BEAST = { whelp: { w: 40, h: 34, ox: -8, oy: -18 }, rat: { w: 30, h: 18, ox: -3, oy: 4 }, hound: { w: 34, h: 22, ox: -5, oy: 1 } };
})(window.AD);
