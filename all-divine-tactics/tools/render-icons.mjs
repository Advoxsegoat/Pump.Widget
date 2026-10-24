// Renders the Android launcher icons from the game's own procedural pixel art: Abarax's
// Rose Divine portrait in a gilt medallion over the Tanneries night sky.
// Usage: node all-divine-tactics/tools/render-icons.mjs [preview.png]
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
await page.goto('file://' + game);
await page.waitForFunction(() => window.AD && AD.spr && AD.UNITS && AD.UNITS.abarax);

const out = await page.evaluate((wantPreview) => {
  const G = AD.gfx;
  // Adaptive icon layers are 108dp square. Art is drawn at one pixel per dp, so the portrait
  // keeps the game's pixel size and every density but hdpi is a whole-number scale.
  const N = 108, MID = 54;
  const canvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h || w; const x = c.getContext('2d'); x.imageSmoothingEnabled = false; c.x = x; return c; };
  const px = (x, X, Y, col) => { x.fillStyle = col; x.fillRect(X, Y, 1, 1); };

  // ---- background: radial night sky, Bayer-dithered between the game's blues, with snow
  const bg = canvas(N);
  const sky = ['#2b3473', '#1d2550', '#141a36', '#0b0e1c', '#07080f'];
  const bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const d = Math.hypot(x + 0.5 - MID, (y + 0.5 - MID + 8) * 1.1) / (N * 0.62);
    const t = Math.min(0.999, d) * (sky.length - 1);
    const i = Math.floor(t) + ((t % 1) * 16 > bayer[y % 4][x % 4] ? 1 : 0);
    px(bg.x, x, y, sky[Math.min(sky.length - 1, i)]);
  }
  // faint gilt lattice, like the window studs
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if ((x + y) % 18 === 0 && (x - y + 108) % 18 === 0) { bg.x.globalAlpha = 0.35; px(bg.x, x, y, '#a2783a'); bg.x.globalAlpha = 1; }
  }
  let seed = 7;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  for (let k = 0; k < 44; k++) {
    const x = Math.floor(rnd() * N), y = Math.floor(rnd() * N);
    bg.x.globalAlpha = 0.5 + rnd() * 0.5;
    px(bg.x, x, y, k % 7 ? '#f6ecd4' : '#e8c170');
  }
  bg.x.globalAlpha = 1;

  // ---- foreground: medallion + portrait, inside the 66dp safe-zone circle.
  // `art` holds the ring, portrait and rose; the themed icon is cut from it alone.
  const fg = canvas(N), art = canvas(N);
  const R = 33; // ring outer radius
  const well = ['#2b3473', '#1d2550', '#141a36']; // the portrait-window gradient
  const inCircle = (x, y, r) => Math.hypot(x + 0.5 - MID, y + 0.5 - MID) <= r;
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if (!inCircle(x, y, R)) continue;
    if (!inCircle(x, y, R - 1)) px(art.x, x, y, '#06081a');
    else if (!inCircle(x, y, R - 4)) {
      // gilt ring, lit from the top-left like the game's shading
      const a = Math.atan2(y + 0.5 - MID, x + 0.5 - MID);
      px(art.x, x, y, Math.cos(a + 2.4) > 0.35 ? '#ffe6a0' : Math.cos(a + 2.4) < -0.5 ? '#a2783a' : '#e8c170');
    } else if (!inCircle(x, y, R - 5)) px(art.x, x, y, '#06081a');
    else {
      const t = Math.min(0.999, (y - (MID - R + 5)) / (2 * (R - 5))) * (well.length - 1);
      px(fg.x, x, y, well[Math.min(well.length - 1, Math.floor(t) + ((t % 1) * 16 > bayer[y % 4][x % 4] ? 1 : 0))]);
    }
  }
  // the 48x48 portrait at 1:1, shoulders resting on the bottom of the ring
  const U = AD.UNITS.abarax;
  const P = Object.assign({}, U.port, U.ports.rosedivine);
  const face = AD.spr.portrait(P, 'smile');
  const crop = canvas(N);
  crop.x.drawImage(face, MID - 24, MID + R - 5 - 48);
  const fd = crop.x.getImageData(0, 0, N, N).data;
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const i = (y * N + x) * 4;
    if (fd[i + 3] && inCircle(x, y, R - 5)) px(art.x, x, y, G.hex(fd[i], fd[i + 1], fd[i + 2]));
  }
  // a rose at the foot of the ring, the game's own rose icon
  const rose = canvas(9);
  G.icon(rose.x, 'rose', 0, 0);
  art.x.drawImage(rose, MID - 4, MID + R - 7);
  fg.x.drawImage(art, 0, 0);

  // ---- monochrome (themed icons, Android 13+): ring, portrait and rose as one alpha mask
  const mono = canvas(N);
  const md = art.x.getImageData(0, 0, N, N).data;
  const mi = mono.x.createImageData(N, N);
  for (let i = 0; i < md.length; i += 4) {
    if (!md[i + 3]) continue;
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
    const r = size * 0.18;
    c.x.beginPath();
    c.x.roundRect(0, 0, size, size, r);
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
    const S = 216, pad = 24;
    const c = canvas(pad + 4 * (S + pad), S + 2 * pad);
    c.x.fillStyle = '#d8dce8'; c.x.fillRect(0, 0, c.width, c.height);
    const full = scaled(composite, S * 1.5);
    const shapes = [
      (x) => { x.arc(S / 2, S / 2, S / 2, 0, Math.PI * 2); },
      (x) => { x.roundRect(0, 0, S, S, S * 0.3); },
    ];
    shapes.forEach((shape, i) => {
      c.x.save(); c.x.translate(pad + i * (S + pad), pad); c.x.beginPath(); shape(c.x); c.x.clip();
      c.x.drawImage(full, -S * 0.25, -S * 0.25); c.x.restore();
    });
    c.x.save(); c.x.translate(pad + 2 * (S + pad), pad); c.x.beginPath(); shapes[0](c.x); c.x.clip();
    c.x.fillStyle = '#2d3a2e'; c.x.fillRect(0, 0, S, S);
    const tint = canvas(S * 1.5); tint.x.drawImage(scaled(mono, S * 1.5), 0, 0);
    tint.x.globalCompositeOperation = 'source-in'; tint.x.fillStyle = '#c8e6c0'; tint.x.fillRect(0, 0, S * 1.5, S * 1.5);
    c.x.drawImage(tint, -S * 0.25, -S * 0.25); c.x.restore();
    c.x.drawImage(legacy(192), pad + 3 * (S + pad) + 12, pad + 12);
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
