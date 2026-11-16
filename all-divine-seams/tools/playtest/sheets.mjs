// Contact sheets of the art in both display modes, to check by eye.
//   node tools/playtest/sheets.mjs web/index.html out/sheets
// hero.png: every Abarax action in four directions; monsters.png: every monster walking and
// attacking; rooms-hd.png / rooms-gba.png: 12 generated Bilibara rooms; tiles.png: every new prop.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'out/sheets'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top());

const sheets = await page.evaluate(() => {
  const A = AD.art, G = AD.gfx;
  const png = (c) => c.toDataURL('image/png').split(',')[1];
  const label = (x, s, tx, ty, col) => { x.font = '8px monospace'; x.fillStyle = col || '#e8e0d0'; x.fillText(s, tx, ty); };
  const zoom = (c, k) => { const o = G.canvas(c.width * k, c.height * k); o.x.imageSmoothingEnabled = false; o.x.drawImage(c, 0, 0, o.width, o.height); return o; };
  const modes = ['hd', 'gba'];
  const res = { times: {} };

  // ---- hero
  {
    const ACT = {
      idle: [[0, 20, 40, 199]], walk: [[0, 4, 8, 12]],
      attack1: [[1, 4, 6, 9], { wind: 4, act: 2 }], attack2: [[1, 4, 6, 9], { wind: 4, act: 2 }], attack3: [[1, 4, 6, 9], { wind: 4, act: 2 }],
      spin: [[0, 2, 5, 8], { wind: 2 }], cast: [[2, 6, 7, 12], { wind: 6, act: 2, element: 'flame' }],
      roll: [[0, 4, 8, 12], { frames: 14 }], hurt: [[0]], dead: [[0]],
    };
    const dirs = ['down', 'up', 'left', 'right'];
    const parts = modes.map((m) => {
      AD.display.set(m);
      const fw = m === 'hd' ? 48 : 32, fh = m === 'hd' ? 40 : 27;
      const names = Object.keys(ACT);
      const c = G.canvas(60 + 16 * (fw + 2), names.length * (fh + 2) + 12);
      c.x.fillStyle = '#4a4a58'; c.x.fillRect(0, 0, c.width, c.height);
      label(c.x, m, 2, 9, '#ffe28a');
      names.forEach((a, row) => {
        const [ts, o] = ACT[a];
        label(c.x, a, 2, 12 + row * (fh + 2) + fh / 2);
        let col = 0;
        dirs.forEach((d) => ts.forEach((t) => {
          const f = A.frames('abarax', a, d, t, o);
          const x = 60 + col * (fw + 2), y = 12 + row * (fh + 2);
          c.x.fillStyle = col % 8 < 4 ? '#55556a' : '#4e4e62'; c.x.fillRect(x, y, fw, fh);
          c.x.drawImage(f, x, y);
          col++;
        }));
      });
      return zoom(c, 3);
    });
    const c = G.canvas(Math.max(parts[0].width, parts[1].width), parts[0].height + parts[1].height);
    c.x.drawImage(parts[0], 0, 0); c.x.drawImage(parts[1], 0, parts[0].height);
    res.hero = png(c);
  }

  // ---- monsters
  {
    const ids = Object.keys(AD.MONSTERS).concat(Object.keys(AD.BOSSES));
    const cells = [['idle', 'down', 0], ['walk', 'down', 4], ['walk', 'up', 4], ['walk', 'left', 4], ['walk', 'right', 8],
      ['attack1', 'right', 1], ['attack1', 'right', 5], ['attack1', 'left', 5], ['attack1', 'down', 1], ['attack1', 'down', 5], ['attack1', 'up', 5],
      ['hurt', 'right', 0], ['dead', 'right', 0]];
    const parts = modes.map((m) => {
      AD.display.set(m);
      const k = m === 'hd' ? 1 : 2 / 3, cw = Math.round(64 * k), ch = Math.round(60 * k), tx = Math.round(20 * k), ty = Math.round(28 * k), T = AD.display.T;
      const c = G.canvas(70 + cells.length * (cw + 2), ids.length * (ch + 2) + 12);
      c.x.fillStyle = '#4a4a58'; c.x.fillRect(0, 0, c.width, c.height);
      label(c.x, m, 2, 9, '#ffe28a');
      ids.forEach((id, row) => {
        label(c.x, id, 2, 12 + row * (ch + 2) + ch / 2);
        const an = A.anchor(id);
        cells.forEach(([a, d, t], col) => {
          const x = 70 + col * (cw + 2), y = 12 + row * (ch + 2);
          c.x.fillStyle = '#55556a'; c.x.fillRect(x, y, cw, ch);
          c.x.fillStyle = '#5e5e74'; c.x.fillRect(x + tx, y + ty, T, T);
          c.x.drawImage(A.monster(id, a, d, t, { wind: 4, act: 2 }), x + tx + an.ox, y + ty + an.oy);
        });
      });
      return zoom(c, 3);
    });
    const c = G.canvas(Math.max(parts[0].width, parts[1].width), parts[0].height + parts[1].height);
    c.x.drawImage(parts[0], 0, 0); c.x.drawImage(parts[1], 0, parts[0].height);
    res.monsters = png(c);
  }

  // a room drawn as the renderer will: ground, then each row of props, with the live sprites on top
  function drawRoom(x, rows, info, sprites) {
    const R = A.room(rows, info.biome, info.night);
    const T = R.tile;
    x.drawImage(R.ground[0], 0, 0);
    for (let Y = 0; Y < rows.length; Y++) {
      if (R.rows[Y]) x.drawImage(R.rows[Y], 0, Y * T - R.head);
      for (const s of sprites.filter((q) => q.y === Y)) { const sp = A.sprite(s.name, s.o, 40); x.drawImage(sp.c, s.x * T + sp.ox, s.y * T + sp.oy); }
    }
    return R;
  }
  function spritesOf(rows, traps) {
    const out = [];
    rows.forEach((row, y) => [...row].forEach((ch, x) => {
      if (ch === 'C') out.push({ name: 'chest', o: { big: x % 2 === 0 }, x, y });
      if (ch === 'G') out.push({ name: 'gate', o: { charge: 0.5 }, x, y });
      if (ch === 'f') out.push({ name: 'flame', o: { f: 1 }, x, y });
    }));
    for (const t of traps || []) out.push({ name: 'trap', o: { kind: t.kind, seen: true }, x: t.x, y: t.y });
    return out;
  }

  // ---- rooms
  {
    const list = [];
    for (let d = 1; list.length < 12 && d <= 5; d++) {
      const F = AD.gen.floor(d, AD.rng.make(1000 + d));
      const keys = [...F.rooms.keys()];
      for (const key of keys.slice(0, d === 5 ? 4 : 2)) {
        const lay = AD.gen.room(F, key, 'bilibara', AD.rng.make(AD.rng.hash('sheet:' + d + ':' + key)));
        list.push({ d, key, lay, type: F.rooms.get(key).type, info: AD.regionAt(d).d });
      }
      if (d === 4) list.push({ d: 5, key: 'arena', lay: AD.gen.arena('bilibara', AD.rng.make(5)), type: 'boss', info: AD.regionAt(5).d });
    }
    for (const m of modes) {
      AD.display.set(m);
      const W = AD.display.W, H = AD.display.H;
      const c = G.canvas(4 * (W + 4), 3 * (H + 14));
      c.x.fillStyle = '#1a1420'; c.x.fillRect(0, 0, c.width, c.height);
      const t0 = performance.now();
      list.slice(0, 12).forEach((r, i) => {
        const rc = G.canvas(W, H);
        drawRoom(rc.x, r.lay.rows, r.info, spritesOf(r.lay.rows, r.lay.traps));
        const x = (i % 4) * (W + 4), y = Math.floor(i / 4) * (H + 14);
        c.x.drawImage(rc, x, y + 12);
        label(c.x, 'd' + r.d + ' ' + r.type + ' ' + r.info.biome + (r.info.night ? ' night' : ''), x + 2, y + 9);
      });
      res.times[m] = Math.round(performance.now() - t0);
      res['rooms-' + m] = png(m === 'gba' ? zoom(c, 2) : c);
    }
  }

  // ---- tiles: every new prop, in three biomes, plus the sprites that change in play
  {
    const rows = [
      '###%###D#######',
      '#.p.c.b.".P.f.#',
      '#..""".p.......#'.slice(0, 15),
      '#.C...OO..^...#',
      'D.....G.......=',
      '#..L..v..B....#',
      '#..,,,-~~.....#',
      '#..,,.-~~.p.b.#',
      '#.............#',
      '#######+#######',
    ];
    const infos = [{ biome: 'city', night: true }, { biome: 'dungeon', night: false }, { biome: 'interior', night: false }];
    const parts = modes.map((m) => {
      AD.display.set(m);
      const W = AD.display.W, H = AD.display.H, T = AD.display.T;
      const c = G.canvas(3 * (W + 4), H + 14 + 3 * (T * 2 + 4));
      c.x.fillStyle = '#1a1420'; c.x.fillRect(0, 0, c.width, c.height);
      infos.forEach((info, i) => {
        const rc = G.canvas(W, H);
        drawRoom(rc.x, rows, info, spritesOf(rows, [{ x: 10, y: 3, kind: 'spike' }]));
        c.x.drawImage(rc, i * (W + 4), 12);
        label(c.x, m + ' ' + info.biome, i * (W + 4) + 2, 9, '#ffe28a');
      });
      // the live sprites
      const sp = [];
      for (const big of [false, true]) for (const open of [false, true]) sp.push(['chest', { big, open }]);
      for (const kind of ['spike', 'alarm', 'fire', 'gas', 'pit']) { sp.push(['trap', { kind, seen: false }]); sp.push(['trap', { kind, seen: true }]); }
      for (const charge of [0, 0.25, 0.5, 0.75, 1]) sp.push(['gate', { charge }]);
      sp.push(['gate', { open: true }]);
      for (let f = 0; f < 4; f++) sp.push(['flame', { f }]);
      const cw = T * 2 + 4, y0 = H + 18;
      sp.forEach(([n, o], i) => {
        const s = A.sprite(n, o, 8);
        const x = (i % 22) * cw + T / 2, y = y0 + Math.floor(i / 22) * (T * 3) + T * 1.5;
        c.x.fillStyle = '#4a4a58'; c.x.fillRect(x, y, T, T);
        c.x.drawImage(s.c, x + s.ox, y + s.oy);
      });
      return zoom(c, 2);
    });
    const c = G.canvas(Math.max(parts[0].width, parts[1].width), parts[0].height + parts[1].height);
    c.x.drawImage(parts[0], 0, 0); c.x.drawImage(parts[1], 0, parts[0].height);
    res.tiles = png(c);
  }
  AD.display.set('hd');
  return res;
});
for (const k of ['hero', 'monsters', 'rooms-hd', 'rooms-gba', 'tiles']) fs.writeFileSync(path.join(out, k + '.png'), Buffer.from(sheets[k], 'base64'));
await browser.close();
console.log('bake ms for 12 rooms:', JSON.stringify(sheets.times));
if (errors.length) { console.log('page errors:\n  ' + errors.slice(0, 5).join('\n  ')); process.exit(1); }
console.log('sheets written to', out);
