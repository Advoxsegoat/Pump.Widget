// Graphics: bitmap font, windows, icons, colour helpers, and the diorama post-effects
// (light pools, bloom, tilt-shift blur, vignette, weather).
(function (AD) {
  'use strict';
  let W = AD.display.W, H = AD.display.H;
  const G = (AD.gfx = {});

  // ---------------------------------------------------------------- palette
  G.C = {
    ink: '#0b0e1c', night: '#141a36', navy: '#1d2550', indigo: '#2b3473', slate: '#4a5390',
    gold: '#e8c170', goldD: '#a2783a', rose: '#e8607e', roseD: '#8e2f4a', cream: '#f6ecd4',
    gray: '#9aa1c4', dim: '#626a96', blue: '#5b9cf5', red: '#ef5858', green: '#58c97a',
    hp: '#7be88f', hpLow: '#ef5858', teal: '#5fd4c8', violet: '#a98cf0', white: '#ffffff',
  };

  G.rgb = function (hex) {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  };
  G.hex = (r, g, b) => '#' + [r, g, b].map((v) => AD.clamp(Math.round(v), 0, 255).toString(16).padStart(2, '0')).join('');
  // amt > 0 lightens toward white, < 0 darkens toward black
  G.shade = function (hex, amt) {
    const [r, g, b] = G.rgb(hex);
    if (amt >= 0) return G.hex(r + (255 - r) * amt, g + (255 - g) * amt, b + (255 - b) * amt);
    return G.hex(r * (1 + amt), g * (1 + amt), b * (1 + amt));
  };
  G.mix = function (a, b, t) {
    const A = G.rgb(a), B = G.rgb(b);
    return G.hex(A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t);
  };
  G.canvas = function (w, h, readBack) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    // a canvas whose pixels are read every frame lives in memory, not on the GPU
    const x = c.getContext('2d', readBack ? { willReadFrequently: true } : undefined);
    x.imageSmoothingEnabled = false;
    c.x = x;
    return c;
  };

  // ---------------------------------------------------------------- font
  // 5x9 cells: rows 0-6 sit on the baseline, rows 7-8 are descenders. Widths trim automatically.
  const F = {
    A: ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    B: ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
    C: ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
    D: ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
    E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    F: ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
    G: ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####'],
    H: ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    I: ['###', '.#.', '.#.', '.#.', '.#.', '.#.', '###'],
    J: ['..###', '...#.', '...#.', '...#.', '#..#.', '#..#.', '.##..'],
    K: ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
    L: ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
    M: ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
    N: ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
    O: ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    P: ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
    Q: ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
    R: ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    S: ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
    T: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
    U: ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    V: ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
    W: ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
    X: ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
    Y: ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
    Z: ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
    a: ['.....', '.....', '.###.', '....#', '.####', '#...#', '.####'],
    b: ['#....', '#....', '####.', '#...#', '#...#', '#...#', '####.'],
    c: ['....', '....', '.###', '#...', '#...', '#...', '.###'],
    d: ['....#', '....#', '.####', '#...#', '#...#', '#...#', '.####'],
    e: ['.....', '.....', '.###.', '#...#', '#####', '#....', '.###.'],
    f: ['..##', '.#..', '.#..', '####', '.#..', '.#..', '.#..'],
    g: ['.....', '.....', '.####', '#...#', '#...#', '#...#', '.####', '....#', '.###.'],
    h: ['#....', '#....', '####.', '#...#', '#...#', '#...#', '#...#'],
    i: ['#', '.', '#', '#', '#', '#', '#'],
    j: ['..#', '...', '..#', '..#', '..#', '..#', '..#', '#.#', '.#.'],
    k: ['#...', '#...', '#..#', '#.#.', '##..', '#.#.', '#..#'],
    l: ['#.', '#.', '#.', '#.', '#.', '#.', '.#'],
    m: ['.....', '.....', '##.#.', '#.#.#', '#.#.#', '#.#.#', '#.#.#'],
    n: ['.....', '.....', '####.', '#...#', '#...#', '#...#', '#...#'],
    o: ['.....', '.....', '.###.', '#...#', '#...#', '#...#', '.###.'],
    p: ['.....', '.....', '####.', '#...#', '#...#', '#...#', '####.', '#....', '#....'],
    q: ['.....', '.....', '.####', '#...#', '#...#', '#...#', '.####', '....#', '....#'],
    r: ['....', '....', '#.##', '##..', '#...', '#...', '#...'],
    s: ['....', '....', '.###', '#...', '.##.', '...#', '###.'],
    t: ['.#..', '.#..', '####', '.#..', '.#..', '.#..', '..##'],
    u: ['.....', '.....', '#...#', '#...#', '#...#', '#...#', '.####'],
    v: ['.....', '.....', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
    w: ['.....', '.....', '#...#', '#...#', '#.#.#', '#.#.#', '.#.#.'],
    x: ['.....', '.....', '#...#', '.#.#.', '..#..', '.#.#.', '#...#'],
    y: ['.....', '.....', '#...#', '#...#', '#...#', '#...#', '.####', '....#', '.###.'],
    z: ['.....', '.....', '#####', '...#.', '..#..', '.#...', '#####'],
    0: ['.##.', '#..#', '#..#', '#..#', '#..#', '#..#', '.##.'],
    1: ['.#.', '##.', '.#.', '.#.', '.#.', '.#.', '###'],
    2: ['.##.', '#..#', '...#', '..#.', '.#..', '#...', '####'],
    3: ['###.', '...#', '...#', '.##.', '...#', '...#', '###.'],
    4: ['#..#', '#..#', '#..#', '####', '...#', '...#', '...#'],
    5: ['####', '#...', '#...', '###.', '...#', '...#', '###.'],
    6: ['.##.', '#...', '#...', '###.', '#..#', '#..#', '.##.'],
    7: ['####', '...#', '...#', '..#.', '..#.', '.#..', '.#..'],
    8: ['.##.', '#..#', '#..#', '.##.', '#..#', '#..#', '.##.'],
    9: ['.##.', '#..#', '#..#', '.###', '...#', '...#', '.##.'],
    '.': ['.', '.', '.', '.', '.', '.', '#'],
    ',': ['.', '.', '.', '.', '.', '.', '#', '#'],
    '!': ['#', '#', '#', '#', '#', '.', '#'],
    '?': ['.##.', '#..#', '...#', '..#.', '.#..', '....', '.#..'],
    ':': ['.', '.', '#', '.', '.', '.', '#'],
    ';': ['.', '.', '#', '.', '.', '.', '#', '#'],
    "'": ['#', '#'],
    '"': ['#.#', '#.#'],
    '-': ['...', '...', '...', '###'],
    '\u2014': ['.....', '.....', '.....', '#####'],
    '_': ['....', '....', '....', '....', '....', '....', '....', '####'],
    '(': ['.#', '#.', '#.', '#.', '#.', '#.', '.#'],
    ')': ['#.', '.#', '.#', '.#', '.#', '.#', '#.'],
    '[': ['##', '#.', '#.', '#.', '#.', '#.', '##'],
    ']': ['##', '.#', '.#', '.#', '.#', '.#', '##'],
    '/': ['...#', '...#', '..#.', '.#..', '.#..', '#...', '#...'],
    '+': ['.....', '..#..', '..#..', '#####', '..#..', '..#..'],
    '=': ['....', '....', '####', '....', '####'],
    '%': ['#...#', '#..#.', '...#.', '..#..', '.#...', '.#..#', '#...#'],
    '&': ['.##..', '#..#.', '.##..', '.#...', '#.#.#', '#..#.', '.##.#'],
    '#': ['.#.#.', '#####', '.#.#.', '.#.#.', '#####', '.#.#.'],
    '<': ['...#', '..#.', '.#..', '#...', '.#..', '..#.', '...#'],
    '>': ['#...', '.#..', '..#.', '...#', '..#.', '.#..', '#...'],
    '*': ['.....', '#.#.#', '.###.', '#####', '.###.', '#.#.#'],
    '\u2026': ['.....', '.....', '.....', '.....', '.....', '.....', '#.#.#'],
    '\u00e9': ['...#.', '..#..', '.###.', '#...#', '#####', '#....', '.###.'],
    '\u00e8': ['.#...', '..#..', '.###.', '#...#', '#####', '#....', '.###.'],
    '\u00e0': ['.#...', '..#..', '.###.', '....#', '.####', '#...#', '.####'],
    '\u00e7': ['....', '....', '.###', '#...', '#...', '#...', '.###', '..#.', '.#..'],
    '\u2665': ['.....', '##.##', '#####', '#####', '.###.', '..#..'],
    '\u2666': ['..#..', '.###.', '#####', '.###.', '..#..'],
    '\u25ba': ['#...', '##..', '###.', '####', '###.', '##..', '#...'],
    '\u25c4': ['...#', '..##', '.###', '####', '.###', '..##', '...#'],
    '\u00b7': ['..', '..', '..', '##', '##'],
    '$': ['..#..', '.####', '#.#..', '.###.', '..#.#', '####.', '..#..'],
    '@': ['.###.', '#...#', '#.###', '#.#.#', '#.###', '#....', '.###.'],
    '\u00ea': ['.#.', '#.#', '.#.', '###', '#..', '#..', '.##'],
    '\u00f4': ['.#.', '#.#', '...', '.#.', '#.#', '#.#', '.#.'],
    '\u25bc': ['.....', '.....', '#####', '.###.', '..#..'],
    '\u25b2': ['..#..', '.###.', '#####'],
  };
  F['\u2019'] = F["'"]; F['\u2018'] = F["'"]; F['\u201c'] = F['"']; F['\u201d'] = F['"']; F['\u2013'] = F['-'];

  const glyphs = {};
  const atlas = G.canvas(1024, 9);
  (function buildFont() {
    let x = 0;
    for (const ch in F) {
      const rows = F[ch];
      let w = 0;
      rows.forEach((r) => { const k = r.lastIndexOf('#'); if (k + 1 > w) w = k + 1; });
      if (w === 0) w = 1;
      rows.forEach((r, y) => {
        for (let i = 0; i < r.length; i++) if (r[i] === '#') { atlas.x.fillStyle = '#fff'; atlas.x.fillRect(x + i, y, 1, 1); }
      });
      glyphs[ch] = { x, w };
      x += w + 1;
    }
  })();
  const tinted = {};
  function tint(color) {
    if (tinted[color]) return tinted[color];
    const c = G.canvas(atlas.width, atlas.height);
    c.x.drawImage(atlas, 0, 0);
    c.x.globalCompositeOperation = 'source-in';
    c.x.fillStyle = color;
    c.x.fillRect(0, 0, c.width, c.height);
    tinted[color] = c;
    return c;
  }
  G.LINE = 10;
  G.hasGlyph = (ch) => ch === ' ' || !!glyphs[ch];

  // Inline marks: *gold*, ~rose~, ^blue^ toggle colour. Returns pixel width.
  G.measure = function (str, mono) {
    let w = 0;
    for (const ch of String(str)) {
      if (ch === '*' || ch === '~' || ch === '^') continue;
      if (ch === ' ') { w += mono ? 5 : 3; continue; }
      const g = glyphs[ch] || glyphs['?'];
      w += (mono && /[0-9]/.test(ch) ? 4 : g.w) + 1;
    }
    return Math.max(0, w - 1);
  };

  G.text = function (ctx, str, x, y, color, opt) {
    opt = opt || {};
    str = String(str);
    color = color || G.C.cream;
    const k = opt.scale || 1;
    const w = G.measure(str, opt.mono) * k;
    if (opt.align === 'center') x -= Math.floor(w / 2);
    else if (opt.align === 'right') x -= w;
    x = Math.round(x); y = Math.round(y);
    if (opt.shadow !== false) drawRun(ctx, str, x + k, y + k, opt.shadowColor || 'rgba(4,5,12,0.85)', opt, true);
    drawRun(ctx, str, x, y, color, opt, false);
    return w;
  };
  function drawRun(ctx, str, x, y, color, opt, isShadow) {
    const k = opt.scale || 1;
    let cur = color;
    const stackC = [];
    const marks = { '*': G.C.gold, '~': G.C.rose, '^': G.C.blue };
    for (const ch of str) {
      if (marks[ch]) {
        if (!isShadow) {
          if (stackC.length && stackC[stackC.length - 1][0] === ch) cur = stackC.pop()[1];
          else { stackC.push([ch, cur]); cur = marks[ch]; }
        }
        continue;
      }
      if (ch === ' ') { x += (opt.mono ? 5 : 3) * k; continue; }
      const g = glyphs[ch] || glyphs['?'];
      const src = tint(isShadow ? color : cur);
      let gx = x;
      if (opt.mono && /[0-9]/.test(ch)) gx += Math.floor((4 - g.w) / 2) * k;
      ctx.drawImage(src, g.x, 0, g.w, 9, gx, y, g.w * k, 9 * k);
      x += ((opt.mono && /[0-9]/.test(ch) ? 4 : g.w) + 1) * k;
    }
  }

  G.wrap = function (str, maxW) {
    const out = [];
    String(str).split('\n').forEach((para) => {
      const words = para.split(' ');
      let line = '';
      words.forEach((wd) => {
        const t = line ? line + ' ' + wd : wd;
        if (G.measure(t) > maxW && line) { out.push(line); line = wd; } else line = t;
      });
      out.push(line);
    });
    return out;
  };

  // ---------------------------------------------------------------- windows
  // Ink-blue panels with a thin gilt edge and diamond studs at the corners.
  const STYLES = {
    ink: ['#1a2150', '#0e1330', '#c9a35d', '#06081a'],
    blue: ['#2a4a9a', '#13245a', '#a9c8ff', '#06081a'],
    red: ['#8a2a3e', '#45121f', '#ffb0b8', '#140308'],
    green: ['#2a7a52', '#103c28', '#b8ffd0', '#03140a'],
    paper: ['#efe2c4', '#d8c59c', '#8a6a3a', '#3a2a14'],
    violet: ['#3a2a6a', '#1a1238', '#d8c0ff', '#08061a'],
  };
  G.panel = function (ctx, x, y, w, h, style, alpha) {
    const s = STYLES[style || 'ink'];
    x = Math.round(x); y = Math.round(y); w = Math.round(w); h = Math.round(h);
    ctx.save();
    ctx.globalAlpha = alpha === undefined ? 0.94 : alpha;
    const g = ctx.createLinearGradient(0, y, 0, y + h);
    g.addColorStop(0, s[0]); g.addColorStop(1, s[1]);
    ctx.fillStyle = g;
    ctx.fillRect(x + 1, y, w - 2, h);
    ctx.fillRect(x, y + 1, w, h - 2);
    ctx.globalAlpha = 1;
    ctx.fillStyle = s[3];
    ctx.fillRect(x + 1, y - 1, w - 2, 1); ctx.fillRect(x + 1, y + h, w - 2, 1);
    ctx.fillRect(x - 1, y + 1, 1, h - 2); ctx.fillRect(x + w, y + 1, 1, h - 2);
    ctx.fillStyle = s[2];
    ctx.fillRect(x + 2, y, w - 4, 1); ctx.fillRect(x + 2, y + h - 1, w - 4, 1);
    ctx.fillRect(x, y + 2, 1, h - 4); ctx.fillRect(x + w - 1, y + 2, 1, h - 4);
    // corner studs
    [[x + 1, y + 1], [x + w - 2, y + 1], [x + 1, y + h - 2], [x + w - 2, y + h - 2]].forEach(([cx, cy]) => {
      ctx.fillRect(cx, cy, 1, 1);
    });
    ctx.globalAlpha = 0.18;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(x + 2, y + 1, w - 4, 1);
    ctx.restore();
  };

  // menu cursor: a small rose-gold pointing hand made of pixels
  G.pointer = function (ctx, x, y) {
    const bob = Math.floor(AD.frame / 8) % 2;
    x = Math.round(x) - bob;
    ctx.fillStyle = '#06081a';
    ctx.fillRect(x - 1, y + 1, 7, 5);
    ctx.fillStyle = G.C.gold;
    ctx.fillRect(x, y + 2, 5, 3);
    ctx.fillRect(x + 5, y + 3, 1, 1);
    ctx.fillStyle = G.C.cream;
    ctx.fillRect(x, y + 2, 3, 1);
  };

  G.bar = function (ctx, x, y, w, h, frac, color, back) {
    ctx.fillStyle = '#06081a';
    ctx.fillRect(x - 1, y - 1, w + 2, h + 2);
    ctx.fillStyle = back || '#2a2f52';
    ctx.fillRect(x, y, w, h);
    ctx.fillStyle = color;
    ctx.fillRect(x, y, Math.round(w * AD.clamp(frac, 0, 1)), h);
    ctx.globalAlpha = 0.35;
    ctx.fillStyle = '#fff';
    ctx.fillRect(x, y, Math.round(w * AD.clamp(frac, 0, 1)), 1);
    ctx.globalAlpha = 1;
  };

  // ---------------------------------------------------------------- icons (8x8)
  const ICONS = {
    blade: ['......#.', '.....#c.', '....#c..', '...#c...', '..#c....', '.##.....', '.#g#....', 'g.......'],
    fist: ['........', '.cccc...', 'ccccc...', 'ccccc#..', 'cccc#c..', '.cccc...', '..cc....', '........'],
    pole: ['.......#', '......#c', '.....g..', '....g...', '...g....', '..g.....', '.g......', 'g.......'],
    shot: ['........', '#.......', '.#......', 'cc#cccc#', '.g#.....', '.g......', '.g......', '........'],
    flame: ['...r....', '...rr...', '..rgr...', '.rrggr..', '.rgwgr..', '.rgwgr..', '..rggr..', '...rr...'],
    bloom: ['........', '..rr.r..', '.rrrrr..', '.rrrrr..', '..rrr...', '...g....', '..gg....', '...g....'],
    tide: ['........', '...b....', '..bb....', '.bbbb...', '.bwbbb..', 'bbwbbb..', '.bbbb...', '..bb....'],
    song: ['....##..', '....#.#.', '....#...', '....#...', '..###...', '.####...', '.###....', '........'],
    all: ['...g....', '.g.g.g..', '..ggg...', 'gggwggg.', '..ggg...', '.g.g.g..', '...g....', '........'],
    item: ['..cc....', '.cwwc...', '.cwwc...', 'cwwwwc..', 'cwrrwc..', 'cwrrwc..', '.cccc...', '........'],
    key: ['.ggg....', 'g...g...', 'g...g...', '.ggg....', '..g.....', '..gg....', '..g.....', '..gg....'],
    shield: ['.cccccc.', 'cwwwwwwc', 'cwccccwc', 'cwcwwcwc', 'cwcwwcwc', '.cwccwc.', '..cwwc..', '...cc...'],
    broken: ['.c.cccc.', 'cw.wwwwc', 'cwc.ccwc', 'cwcw.cwc', 'cwcwwc.c', '.cwccw..', '..cw.c..', '...c....'],
    star: ['...g....', '...g....', '..ggg...', 'gggwggg.', '.ggggg..', '.gg.gg..', '.g...g..', '........'],
    rose: ['..rr....', '.rrrr...', 'rrwrrr..', '.rrrr...', '..g.....', '.gg.g...', '..ggg...', '..g.....'],
    armor: ['.c....c.', 'cwc..cwc', 'cwwwwwwc', '.cwccwc.', '.cwwwwc.', '.cwccwc.', '..cwwc..', '...cc...'],
    outfit: ['..g..g..', '.cccccc.', 'ccwccwcc', 'c.cwwc.c', '..cwwc..', '..cwwc..', '..c..c..', '........'],
    acc: ['...rr...', '..rwwr..', '...gg...', '..g..g..', '.g....g.', '.g....g.', '..g..g..', '...gg...'],
  };
  const ICOL = { '#': '#e6ecff', c: '#b8c0e0', g: '#e8c170', r: '#ef5f6a', w: '#ffffff', b: '#5fb6f5' };
  // more 8x8 icons, in the same letters
  G.defIcon = (name, rows) => { ICONS[name] = rows; };
  const iconCache = {};
  G.icon = function (ctx, name, x, y, alpha) {
    let c = iconCache[name];
    if (!c) {
      const rows = ICONS[name] || ICONS.item;
      c = G.canvas(9, 9);
      rows.forEach((r, yy) => {
        for (let xx = 0; xx < r.length; xx++) {
          const k = r[xx];
          if (k !== '.') {
            c.x.fillStyle = '#06081a'; c.x.fillRect(xx + 1, yy + 1, 1, 1);
          }
        }
      });
      rows.forEach((r, yy) => {
        for (let xx = 0; xx < r.length; xx++) {
          const k = r[xx];
          if (k !== '.') { c.x.fillStyle = ICOL[k] || '#fff'; c.x.fillRect(xx, yy, 1, 1); }
        }
      });
      iconCache[name] = c;
    }
    if (alpha !== undefined) ctx.globalAlpha = alpha;
    ctx.drawImage(c, Math.round(x), Math.round(y));
    ctx.globalAlpha = 1;
  };

  // ---------------------------------------------------------------- FX
  const FX = (AD.fx = {
    parts: [], shakeT: 0, shakeA: 0, flashT: 0, flashC: '#fff', weather: null, enabled: true,
    floats: [],
  });
  FX.shake = function (a, t) { FX.shakeA = a; FX.shakeT = t; };
  FX.flash = function (c, t) { FX.flashC = c; FX.flashT = t; FX.flashMax = t; };
  FX.offset = function () {
    if (FX.shakeT <= 0) return [0, 0];
    const a = FX.shakeA * (FX.shakeT / 20 + 0.3);
    return [Math.round((Math.random() * 2 - 1) * a), Math.round((Math.random() * 2 - 1) * a)];
  };
  FX.setWeather = function (kind, density) {
    FX.weather = kind || null;
    FX.parts = [];
    if (!kind) return;
    const n = Math.round((density || 1) * ({ snow: 70, petals: 26, rain: 90, motes: 40, ash: 40, embers: 30, fog: 6, sparks: 20 }[kind] || 40));
    for (let i = 0; i < n; i++) FX.parts.push(spawn(kind, true));
  };
  function spawn(kind, anywhere) {
    const p = { kind, x: Math.random() * (W + 40) - 20, y: anywhere ? Math.random() * H : -6, t: Math.random() * 1000 };
    switch (kind) {
      case 'snow': p.vx = -0.15 + Math.random() * 0.2; p.vy = 0.25 + Math.random() * 0.4; p.s = Math.random() < 0.2 ? 2 : 1; break;
      case 'petals': p.vx = 0.3 + Math.random() * 0.4; p.vy = 0.3 + Math.random() * 0.3; p.s = 2; p.c = Math.random() < 0.7 ? '#e8607e' : '#e8c170'; break;
      case 'rain': p.vx = -0.8; p.vy = 4 + Math.random() * 2; break;
      case 'motes': p.vx = (Math.random() - 0.5) * 0.15; p.vy = -0.08 - Math.random() * 0.15; p.c = Math.random() < 0.5 ? '#ffe28a' : '#c9b0ff'; if (!anywhere) p.y = H + 4; break;
      case 'ash': p.vx = 0.2 + Math.random() * 0.2; p.vy = 0.15 + Math.random() * 0.2; break;
      case 'embers': p.vx = (Math.random() - 0.5) * 0.3; p.vy = -0.3 - Math.random() * 0.4; if (!anywhere) p.y = H + 4; break;
      case 'sparks': p.vx = (Math.random() - 0.5) * 0.2; p.vy = -0.1 - Math.random() * 0.2; if (!anywhere) p.y = H + 4; break;
      case 'fog': p.vx = 0.08 + Math.random() * 0.08; p.vy = 0; p.r = 30 + Math.random() * 40; break;
      default: p.vx = 0; p.vy = 0.3;
    }
    return p;
  }
  FX.update = function () {
    if (FX.shakeT > 0) FX.shakeT--;
    if (FX.flashT > 0) FX.flashT--;
    FX.parts.forEach((p, i) => {
      p.t++;
      p.x += p.vx + (p.kind === 'snow' || p.kind === 'petals' ? Math.sin(p.t / 30) * 0.2 : 0);
      p.y += p.vy;
      if (p.y > H + 8 || p.y < -10 || p.x > W + 30 || p.x < -30) {
        if (p.kind === 'fog') { p.x = -60; p.y = Math.random() * H; }
        else FX.parts[i] = spawn(p.kind, false);
      }
    });
    for (let i = FX.floats.length - 1; i >= 0; i--) {
      const f = FX.floats[i];
      f.t++; f.y += f.vy; f.vy *= 0.9;
      if (f.t > f.life) FX.floats.splice(i, 1);
    }
  };
  FX.float = function (text, x, y, color, opt) {
    FX.floats.push({ text: String(text), x, y, vy: -1.4, t: 0, life: (opt && opt.life) || 50, color: color || '#fff', big: opt && opt.big });
  };
  FX.drawFloats = function (ctx, ox, oy) {
    FX.floats.forEach((f) => {
      const a = f.t > f.life - 12 ? (f.life - f.t) / 12 : 1;
      ctx.globalAlpha = a;
      G.text(ctx, f.text, f.x - (ox || 0), f.y - (oy || 0), f.color, { align: 'center' });
    });
    ctx.globalAlpha = 1;
  };
  FX.drawWeather = function (ctx) {
    if (!FX.weather) return;
    FX.parts.forEach((p) => {
      switch (p.kind) {
        case 'snow':
          ctx.fillStyle = 'rgba(240,244,255,0.85)'; ctx.fillRect(p.x | 0, p.y | 0, p.s, p.s); break;
        case 'petals':
          ctx.fillStyle = p.c; ctx.fillRect(p.x | 0, p.y | 0, 2, 1);
          ctx.fillRect((p.x | 0) + (Math.sin(p.t / 9) > 0 ? 1 : 0), (p.y | 0) + 1, 1, 1); break;
        case 'rain':
          ctx.fillStyle = 'rgba(150,180,240,0.45)'; ctx.fillRect(p.x | 0, p.y | 0, 1, 4); break;
        case 'motes': {
          const a = 0.5 + 0.5 * Math.sin(p.t / 20);
          ctx.globalAlpha = a; ctx.fillStyle = p.c; ctx.fillRect(p.x | 0, p.y | 0, 1, 1);
          ctx.globalAlpha = a * 0.3; ctx.fillRect((p.x | 0) - 1, p.y | 0, 3, 1); ctx.fillRect(p.x | 0, (p.y | 0) - 1, 1, 3);
          ctx.globalAlpha = 1; break;
        }
        case 'ash':
          ctx.fillStyle = 'rgba(160,160,170,0.7)'; ctx.fillRect(p.x | 0, p.y | 0, 1, 1); break;
        case 'embers':
          ctx.fillStyle = Math.sin(p.t / 6) > 0 ? '#ffb347' : '#ff6a3a'; ctx.fillRect(p.x | 0, p.y | 0, 1, 1); break;
        case 'sparks':
          ctx.fillStyle = Math.sin(p.t / 4) > 0 ? '#fff6c0' : '#e8c170'; ctx.fillRect(p.x | 0, p.y | 0, 1, 1); break;
        case 'fog': {
          const g = ctx.createRadialGradient(p.x, p.y, 2, p.x, p.y, p.r);
          g.addColorStop(0, 'rgba(200,205,215,0.22)'); g.addColorStop(1, 'rgba(200,205,215,0)');
          ctx.fillStyle = g; ctx.fillRect(p.x - p.r, p.y - p.r, p.r * 2, p.r * 2); break;
        }
      }
    });
  };
  FX.drawFlash = function (ctx, peak) {
    if (FX.flashT > 0) {
      ctx.globalAlpha = (FX.flashT / FX.flashMax) * (peak || 0.8);
      ctx.fillStyle = FX.flashC;
      ctx.fillRect(0, 0, W, H);
      ctx.globalAlpha = 1;
    }
  };

  // ------------------------------------------------ lighting: darkness with light pools
  let lightCv, glowCv;
  // lights: [{x, y, r, c (glow colour), a (glow strength)}] in screen space
  FX.lighting = function (ctx, ambient, lights) {
    if (!ambient) return;
    const L = lightCv.x;
    L.globalCompositeOperation = 'source-over';
    L.clearRect(0, 0, W, H);
    L.fillStyle = ambient;
    L.fillRect(0, 0, W, H);
    L.globalCompositeOperation = 'destination-out';
    lights.forEach((l) => {
      const g = L.createRadialGradient(l.x, l.y, 0, l.x, l.y, l.r);
      g.addColorStop(0, 'rgba(0,0,0,1)');
      g.addColorStop(0.55, 'rgba(0,0,0,0.6)');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      L.fillStyle = g;
      L.fillRect(l.x - l.r, l.y - l.r, l.r * 2, l.r * 2);
    });
    ctx.drawImage(lightCv, 0, 0);
    const Gx = glowCv.x;
    Gx.clearRect(0, 0, W, H);
    lights.forEach((l) => {
      if (!l.c) return;
      const g = Gx.createRadialGradient(l.x, l.y, 0, l.x, l.y, l.r * 0.8);
      const [r, gg, b] = G.rgb(l.c);
      g.addColorStop(0, `rgba(${r},${gg},${b},${l.a || 0.35})`);
      g.addColorStop(1, `rgba(${r},${gg},${b},0)`);
      Gx.fillStyle = g;
      Gx.fillRect(l.x - l.r, l.y - l.r, l.r * 2, l.r * 2);
    });
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.drawImage(glowCv, 0, 0);
    ctx.restore();
  };

  // ------------------------------------------------ post: bloom, tilt-shift, vignette
  // the full-screen buffers follow the display mode
  let SW, SH, HW, HH, small, half, band, vign, bandMask;
  function sizeFor() {
    W = AD.display.W; H = AD.display.H;
    SW = W >> 2; SH = H >> 2; HW = W >> 1; HH = H >> 1;
    lightCv = G.canvas(W, H); glowCv = G.canvas(W, H);
    small = G.canvas(SW, SH, true); half = G.canvas(HW, HH);
    band = G.canvas(W, H); vign = G.canvas(W, H); bandMask = G.canvas(W, H);
    let g = vign.x.createRadialGradient(W / 2, H / 2, H * 0.35, W / 2, H / 2, H * 1.05);
    g.addColorStop(0, 'rgba(4,5,14,0)');
    g.addColorStop(1, 'rgba(4,5,14,0.62)');
    vign.x.fillStyle = g;
    vign.x.fillRect(0, 0, W, H);
    g = bandMask.x.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, 'rgba(0,0,0,0.75)');
    g.addColorStop(0.1, 'rgba(0,0,0,0)');
    g.addColorStop(0.9, 'rgba(0,0,0,0)');
    g.addColorStop(1, 'rgba(0,0,0,0.75)');
    bandMask.x.fillStyle = g;
    bandMask.x.fillRect(0, 0, W, H);
  }
  sizeFor();
  AD.display.onChange.push(sizeFor);
  FX.post = function (ctx, opt) {
    opt = opt || {};
    if (!FX.enabled) { if (opt.vignette !== false) ctx.drawImage(vign, 0, 0); return; }
    const src = ctx.canvas;
    // tilt-shift: soften the top and bottom of the frame like a diorama photograph
    if (opt.tilt !== false) {
      half.x.imageSmoothingEnabled = true;
      half.x.clearRect(0, 0, HW, HH);
      half.x.drawImage(src, 0, 0, HW, HH);
      const B = band.x;
      B.globalCompositeOperation = 'source-over';
      B.clearRect(0, 0, W, H);
      B.imageSmoothingEnabled = true;
      B.drawImage(half, 0, 0, W, H);
      B.globalCompositeOperation = 'destination-in';
      B.drawImage(bandMask, 0, 0);
      ctx.drawImage(band, 0, 0);
    }
    // bloom: bright pixels, blurred and added back
    if (opt.bloom !== false) {
      small.x.imageSmoothingEnabled = true;
      small.x.globalCompositeOperation = 'source-over';
      small.x.drawImage(src, 0, 0, SW, SH);
      const id = small.x.getImageData(0, 0, SW, SH);
      const d = id.data;
      const th = opt.threshold || 170;
      for (let i = 0; i < d.length; i += 4) {
        const l = (d[i] * 0.3 + d[i + 1] * 0.59 + d[i + 2] * 0.11);
        const k = l > th ? (l - th) / (255 - th) : 0;
        d[i] *= k; d[i + 1] *= k; d[i + 2] *= k; d[i + 3] = 255;
      }
      small.x.putImageData(id, 0, 0);
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.globalAlpha = opt.bloomAmt || 0.55;
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(small, -2, -2, W + 4, H + 4);
      ctx.restore();
      ctx.imageSmoothingEnabled = false;
    }
    if (opt.vignette !== false) ctx.drawImage(vign, 0, 0);
  };
})(window.AD);

