// Renders the Android launcher icons from the game's own pixel art: Abarax, as he stands in play,
// in front of the rose-gold tear in the wall that every run steps through.
// Usage: node all-divine-seams/tools/render-icons.mjs [preview.png]
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const game = path.join(here, '../web/index.html');
const res = path.join(here, '../android/app/src/main/res');
const preview = process.argv[2];

const browser = await chromium.launch();
const page = await browser.newPage();
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + game);
await page.waitForFunction(() => window.AD && AD.art && AD.art.frames && AD.top && AD.top());

const out = await page.evaluate((wantPreview) => {
  AD.display.set('hd');
  const G = AD.gfx;
  // Adaptive icon layers are 108dp square, drawn at one pixel per dp; the figure is doubled, so
  // every density but hdpi is a whole-number scale of whole pixels
  const N = 108, MID = 54;
  const canvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h || w; const x = c.getContext('2d'); x.imageSmoothingEnabled = false; c.x = x; return c; };
  const px = (x, X, Y, col, a) => { x.globalAlpha = a === undefined ? 1 : a; x.fillStyle = col; x.fillRect(X, Y, 1, 1); x.globalAlpha = 1; };
  const bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
  const dither = (t, list, x, y) => { const v = Math.min(0.999, Math.max(0, t)) * (list.length - 1); return list[Math.min(list.length - 1, Math.floor(v) + ((v % 1) * 16 > bayer[y % 4][x % 4] ? 1 : 0))]; };

  // ---- background: the Seams' night, the page's own ink, lit rose from the middle, with motes
  const bg = canvas(N);
  const night = ['#3a2346', '#24204a', '#1a1f45', '#10132c', '#07080f'];
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const d = Math.hypot((x + 0.5 - MID) * 1.25, y + 0.5 - MID) / (N * 0.6);
    px(bg.x, x, y, dither(d, night, x, y));
  }
  let seed = 11;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  for (let k = 0; k < 40; k++) px(bg.x, Math.floor(rnd() * N), Math.floor(rnd() * N), k % 5 ? '#f6ecd4' : '#e8607e', 0.35 + rnd() * 0.5);

  // ---- foreground: the tear and Abarax, inside the 66dp safe-zone circle. `art` holds what the
  // themed icon is cut from
  const fg = canvas(N), art = canvas(N);
  // the tear: a jagged upright slit of light, white-gold at the core, rose at the lips, with a
  // dithered glow round it
  const top = 12, bot = 100;
  const halfW = (y) => { const t = (y - top) / (bot - top); const w = Math.pow(Math.sin(Math.PI * t), 0.8) * 12; return w * (0.8 + 0.2 * Math.sin(y * 1.7) * Math.cos(y * 0.6)); };
  const lean = (y) => Math.round(Math.sin((y - top) * 0.21) * 1.6);
  for (let y = top - 6; y <= bot + 6; y++) for (let x = MID - 28; x <= MID + 28; x++) {
    const inside = y >= top && y <= bot;
    const w = inside ? halfW(y) : 0, dx = Math.abs(x + 0.5 - (MID + lean(y)));
    if (inside && dx <= w) {
      const t = dx / Math.max(0.5, w);
      px(art.x, x, y, t < 0.35 ? '#fff6e2' : t < 0.6 ? '#ffd9a0' : t < 0.85 ? '#f29a8a' : '#e8607e');
    } else {
      // the glow: strongest beside the lips, fading out over 12 pixels
      const near = inside ? dx - w : Math.hypot(dx, y < top ? top - y : y - bot);
      const g = 1 - near / 12;
      if (g > 0 && g * 16 > bayer[y % 4][x % 4]) px(fg.x, x, y, g > 0.6 ? '#e8607e' : '#9a3a5e', 0.55);
    }
  }
  // Abarax as he stands in play, stepping out of the tear, doubled: head to knees show inside the
  // launcher's mask, the tear rising above him and breaking round his shoulders
  const fr = AD.art.frames('abarax', 'idle', 'down', 0);
  const fc = canvas(fr.width, fr.height); fc.x.drawImage(fr, 0, 0);
  const fd = fc.x.getImageData(0, 0, fr.width, fr.height).data;
  // the figure's own bounds inside its frame
  let x0 = 1e9, x1 = -1, y0 = 1e9, y1 = -1;
  for (let y = 0; y < fr.height; y++) for (let x = 0; x < fr.width; x++) if (fd[(y * fr.width + x) * 4 + 3]) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  const S = 2, ox = MID - Math.round(((x0 + x1 + 1) / 2) * S), oy = 40 - y0 * S;
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const i = (y * fr.width + x) * 4;
    if (!fd[i + 3]) continue;
    art.x.globalAlpha = fd[i + 3] / 255;
    art.x.fillStyle = G.hex(fd[i], fd[i + 1], fd[i + 2]);
    art.x.fillRect(ox + x * S, oy + y * S, S, S);
    art.x.globalAlpha = 1;
  }
  fg.x.drawImage(art, 0, 0);

  // ---- monochrome (themed icons, Android 13+): the tear and the figure as one alpha mask
  const mono = canvas(N);
  const md = art.x.getImageData(0, 0, N, N).data;
  const mi = mono.x.createImageData(N, N);
  for (let i = 0; i < md.length; i += 4) {
    if (md[i + 3] < 40) continue;
    const l = (md[i] * 0.3 + md[i + 1] * 0.59 + md[i + 2] * 0.11) / 255;
    mi.data[i] = mi.data[i + 1] = mi.data[i + 2] = 255;
    mi.data[i + 3] = l < 0.08 ? 0 : Math.round(110 + 145 * Math.min(1, l * 1.6));
  }
  mono.x.putImageData(mi, 0, 0);

  const scaled = (src, size, smooth) => {
    const c = canvas(size);
    c.x.imageSmoothingEnabled = !!smooth;
    c.x.imageSmoothingQuality = 'high';
    c.x.drawImage(src, 0, 0, size, size);
    return c;
  };
  const composite = canvas(N);
  composite.x.drawImage(bg, 0, 0); composite.x.drawImage(fg, 0, 0);
  // legacy icon (Android 7): the visible 72dp centre, rounded, at 48dp
  const legacy = (size) => {
    const big = scaled(composite, size * 3, false);
    const c = canvas(size);
    c.x.imageSmoothingEnabled = true; c.x.imageSmoothingQuality = 'high';
    c.x.beginPath();
    c.x.roundRect(0, 0, size, size, size * 0.18);
    c.x.clip();
    c.x.drawImage(big, size * 0.5, size * 0.5, size * 2, size * 2, 0, 0, size, size);
    return c;
  };

  const files = {};
  const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
  for (const [d, k] of Object.entries(dens)) {
    const s = Math.round(108 * k);
    files[`mipmap-${d}/ic_launcher_bg.png`] = scaled(bg, s).toDataURL();
    files[`mipmap-${d}/ic_launcher_fg.png`] = scaled(fg, s).toDataURL();
    files[`mipmap-${d}/ic_launcher_mono.png`] = scaled(mono, s).toDataURL();
    files[`mipmap-${d}/ic_launcher.png`] = legacy(Math.round(48 * k)).toDataURL();
  }

  let sheet = null;
  if (wantPreview) {
    // how launchers will show it: circle, squircle, themed, legacy
    const S2 = 216, pad = 24;
    const c = canvas(pad + 4 * (S2 + pad), S2 + 2 * pad);
    c.x.fillStyle = '#d8dce8'; c.x.fillRect(0, 0, c.width, c.height);
    const full = scaled(composite, S2 * 1.5);
    const shapes = [
      (x) => { x.arc(S2 / 2, S2 / 2, S2 / 2, 0, Math.PI * 2); },
      (x) => { x.roundRect(0, 0, S2, S2, S2 * 0.3); },
    ];
    shapes.forEach((shape, i) => {
      c.x.save(); c.x.translate(pad + i * (S2 + pad), pad); c.x.beginPath(); shape(c.x); c.x.clip();
      c.x.drawImage(full, -S2 * 0.25, -S2 * 0.25); c.x.restore();
    });
    c.x.save(); c.x.translate(pad + 2 * (S2 + pad), pad); c.x.beginPath(); shapes[0](c.x); c.x.clip();
    c.x.fillStyle = '#2d3a2e'; c.x.fillRect(0, 0, S2, S2);
    const tint = canvas(S2 * 1.5); tint.x.drawImage(scaled(mono, S2 * 1.5), 0, 0);
    tint.x.globalCompositeOperation = 'source-in'; tint.x.fillStyle = '#c8e6c0'; tint.x.fillRect(0, 0, S2 * 1.5, S2 * 1.5);
    c.x.drawImage(tint, -S2 * 0.25, -S2 * 0.25); c.x.restore();
    c.x.drawImage(legacy(192), pad + 3 * (S2 + pad) + 12, pad + 12);
    sheet = c.toDataURL();
  }
  return { files, sheet };
}, !!preview);

for (const [rel, url] of Object.entries(out.files)) {
  const p = path.join(res, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, Buffer.from(url.split(',')[1], 'base64'));
}
console.log(`wrote ${Object.keys(out.files).length} icons under ${path.relative(process.cwd(), res)}`);
if (preview) { fs.writeFileSync(preview, Buffer.from(out.sheet.split(',')[1], 'base64')); console.log('wrote', preview); }
await browser.close();
