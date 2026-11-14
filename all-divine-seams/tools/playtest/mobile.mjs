// The phone controls in four phone sizes (spec 9.3): every control on screen and clear of the game,
// at its size, multi-touch, and nothing left held when a touch is cancelled or the page goes away.
//   node tools/playtest/mobile.mjs web/index.html [outdir]
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'out/mobile'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const SIZES = [[360, 780], [412, 915], [780, 360], [915, 412]];
const fail = [];
for (const [w, h] of SIZES) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
  await page.goto('file://' + path.resolve(game));
  await page.waitForFunction(() => window.AD && AD.top && AD.top());
  const r = await page.evaluate(() => {
    const res = { fails: [] };
    const bad = (m) => res.fails.push(m);
    const W = innerWidth, H = innerHeight;
    const cv = document.getElementById('screen').getBoundingClientRect();
    const over = (a, b) => a.left < b.right - 1 && b.left < a.right - 1 && a.top < b.bottom - 1 && b.top < a.bottom - 1;
    const want = { a: 48, b: 44, r: 44, l: 40, start: 32 };
    if (!document.documentElement.classList.contains('touch')) bad('the touch controls are not shown');
    for (const el of document.querySelectorAll('#controls [data-btn]')) {
      const k = el.getAttribute('data-btn'), b = el.getBoundingClientRect();
      if (b.left < 0 || b.top < 0 || b.right > W || b.bottom > H) bad(k + ' is off screen ' + JSON.stringify([b.left, b.top, b.right, b.bottom]));
      if (Math.abs(b.width - want[k]) > 0.6 || Math.abs(b.height - want[k]) > 0.6) bad(k + ' is ' + b.width + 'x' + b.height + ', not ' + want[k]);
      if (over(b, cv)) bad(k + ' sits over the game');
      for (const o of document.querySelectorAll('#controls [data-btn]')) if (o !== el && over(b, o.getBoundingClientRect())) bad(k + ' overlaps ' + o.getAttribute('data-btn'));
    }
    const z = document.getElementById('stickZone').getBoundingClientRect();
    if (over(z, cv)) bad('the stick zone sits over the game');
    if (z.width < 100 || z.height < 100) bad('the stick zone is too small: ' + z.width + 'x' + z.height);
    if (cv.width < 200) bad('the game is only ' + cv.width + ' px wide');
    const P = (type, el, id, x, y) => el.dispatchEvent(new PointerEvent(type, { pointerId: id, pointerType: 'touch', isPrimary: id === 1, clientX: x, clientY: y, bubbles: true, cancelable: true }));
    const centre = (el) => { const b = el.getBoundingClientRect(); return [b.left + b.width / 2, b.top + b.height / 2]; };
    const zone = document.getElementById('stickZone'), A = document.querySelector('[data-btn="a"]');
    // two fingers: the stick pushed right, and A
    const [zx, zy] = [z.left + z.width / 2, z.top + z.height / 2];
    P('pointerdown', zone, 1, zx, zy); P('pointermove', zone, 1, zx + 45, zy + 3);
    P('pointerdown', A, 2, ...centre(A));
    AD.debugStep(1);
    if (!(AD.pad.sx === 1 && AD.pad.sy === 0 && AD.pad.a)) bad('stick and A together: ' + JSON.stringify([AD.pad.sx, AD.pad.sy, AD.pad.a]));
    res.shot = true;
    P('pointerup', A, 2, ...centre(A));
    // a cancelled touch lets go of the stick
    P('pointercancel', zone, 1, zx + 45, zy + 3);
    AD.debugStep(1);
    if (AD.pad.sx !== 0 || AD.input.held.a) bad('pointercancel releases the stick: ' + AD.pad.sx);
    // a key held while the page is hidden
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight' }));
    AD.debugStep(1);
    if (AD.pad.sx !== 1) bad('a held key moves');
    Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
    AD.debugStep(1);
    if (AD.pad.sx !== 0 || !AD.paused) bad('input releases on visibility change: ' + AD.pad.sx + ' paused ' + AD.paused);
    Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
    AD.paused = false;
    // and on blur
    P('pointerdown', A, 3, ...centre(A));
    AD.debugStep(1);
    window.dispatchEvent(new Event('blur'));
    AD.debugStep(1);
    if (AD.input.held.a || !AD.paused) bad('input releases on blur');
    AD.paused = false;
    // the HUD's quickslots take taps on the screen
    const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 3 });
    AD.view.bind(run);
    AD.view.draw(AD.ctx, run); AD.hud.draw(AD.ctx, run);
    const q = AD.hud.layout(AD.display.mode).quick0, k = cv.width / AD.display.W;
    P('pointerdown', document.getElementById('screen'), 4, cv.left + (q.x + q.w / 2) * k, cv.top + (q.y + q.h / 2) * k);
    AD.debugStep(1);
    if (!AD.pad.q[0]) bad('a tap on the first quickslot uses it');
    // show the stick held, for the picture
    P('pointerdown', zone, 5, zx, zy); P('pointermove', zone, 5, zx + 20, zy - 20);
    P('pointerdown', A, 6, ...centre(A));
    AD.view.draw(AD.ctx, run); AD.hud.draw(AD.ctx, run);
    res.canvas = [cv.left, cv.top, cv.width, cv.height].map(Math.round);
    return res;
  });
  await page.screenshot({ path: path.join(out, w + 'x' + h + '.png') });
  for (const f of r.fails) fail.push(w + 'x' + h + ': ' + f);
  if (errors.length) fail.push(w + 'x' + h + ': page errors ' + errors.slice(0, 3).join(' | '));
  console.log(w + 'x' + h, 'canvas', JSON.stringify(r.canvas), r.fails.length ? 'FAIL' : 'ok');
  await ctx.close();
}
await browser.close();
if (fail.length) { console.log('mobile FAILED\n  ' + fail.join('\n  ')); process.exit(1); }
console.log('mobile ok');
