// Timing under load (plan Task 16): a combat room with 40 monsters, poison gas and burning grass.
// Simulation and drawing are timed apart, per frame, in both display modes. Then memory (plan Task
// 21): 30 rooms walked into, each played and drawn for a second, ten rooms of the first floor three
// times over, the floor built afresh each time (so what is alive at the 10th room and the 30th is
// the same art, and anything kept from a room or a floor left behind shows as growth); after a
// collection, the JS heap and the canvas pixels still alive are compared at those two rooms.
//   node tools/playtest/perf.mjs web/index.html [outdir]
// Passes when, in HD at the 95th percentile, a step takes <= 3 ms and a frame draws in <= 8 ms, and
// memory is flat (within 15%) and within 16 M canvas pixels in both display modes.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'out/perf'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ args: ['--js-flags=--expose-gc', '--enable-precise-memory-info'] });
const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.addInitScript(() => {
  window.requestAnimationFrame = () => 0;
  // every canvas made from here on, held weakly, so the ones still alive can be counted
  window.__canvases = [];
  const make = document.createElement.bind(document);
  document.createElement = function (t, o) { const el = make(t, o); if (String(t).toLowerCase() === 'canvas') window.__canvases.push(new WeakRef(el)); return el; };
});
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top());

const res = await page.evaluate(() => {
  const pct = (a, p) => { const s = a.slice().sort((x, y) => x - y); return +s[Math.min(s.length - 1, Math.floor(s.length * p))].toFixed(2); };
  const result = {};
  for (const mode of ['hd', 'gba']) {
    AD.display.set(mode);
    const run = new AD.Run({ hero: 'abarax', difficulty: 3, seed: 777 });
    run.god = true;
    AD.view.bind(run);
    const key = [...run.floor.rooms.values()].find((r) => r.type === 'combat').key;
    run.enterRoom(key, 's');
    const room = run.room;
    room.waves = []; room.pending = []; room.waveIdx = 0;
    for (const e of [...room.bodies.values()]) if (e.kind === 'monster') AD.ent.remove(room, e);
    const ids = ['grunt', 'slinger', 'rat', 'hound', 'tough', 'whelp', 'bomber', 'fusilier'];
    const tiles = AD.director.spawnTiles(room, 40, AD.rng.make(5));
    tiles.forEach(([x, y], i) => AD.ai.spawn(room, ids[i % ids.length], x, y, { level: 3, elite: i % 9 === 0 ? 'goldflame' : null, eliteTier: i % 9 === 0 ? 1 : 0 }));
    // grass to burn and gas to spread
    for (let x = 2; x < 13; x++) if (room.grid.at(x, 6) === '.') room.grid.set(x, 6, ',');
    for (let x = 2; x < 13; x += 3) AD.world.ignite(room, x, 6);
    AD.world.addGas(room, 4, 3, 'poison', 900); AD.world.addGas(room, 10, 3, 'smoke', 900);
    const sim = [], draw = [];
    const pad = (f) => ({ sx: [1, 0, -1, 0][(f >> 5) % 4], sy: [0, 1, 0, -1][(f >> 5) % 4], a: f % 9 === 0, aHeld: false, aReleased: false, b: f % 240 === 0, r: false, l: false, q: [false, false, false] });
    const ctx = AD.ctx;
    for (let f = 0; f < 600; f++) {
      const t0 = performance.now();
      run.tick(pad(f)); AD.fx.tick();
      const t1 = performance.now();
      AD.view.draw(ctx, run); AD.hud.draw(ctx, run);
      // a page presents every frame; with the frame loop stubbed nothing does, and the canvas would
      // pile up a dozen frames' drawing and raster it all at once: read one pixel to raster each frame
      ctx.getImageData(0, 0, 1, 1);
      const t2 = performance.now();
      if (f >= 60) { sim.push(t1 - t0); draw.push(t2 - t1); }
      if (f === 300) result[mode + 'Shot'] = AD.canvas.toDataURL('image/png').split(',')[1];
    }
    result[mode] = { alive: [...room.bodies.values()].filter((e) => e.kind === 'monster' && !e.dead).length, sim50: pct(sim, 0.5), sim95: pct(sim, 0.95), draw50: pct(draw, 0.5), draw95: pct(draw, 0.95) };
  }
  AD.display.set('hd');
  return result;
});
for (const m of ['hd', 'gba']) fs.writeFileSync(path.join(out, 'perf-' + m + '.png'), Buffer.from(res[m + 'Shot'], 'base64'));

// memory across 30 rooms
const memory = {};
for (const mode of ['hd', 'gba']) {
  await page.evaluate((mode) => {
    AD.display.set(mode);
    const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 4242 });
    run.god = true;
    AD.view.bind(run);
    window.__mem = { run, n: 0, order: [] };
  }, mode);
  const measure = async () => {
    for (let i = 0; i < 3; i++) { await page.evaluate(() => window.gc()); await page.waitForTimeout(30); }
    return page.evaluate(() => {
      let px = 0, live = 0;
      window.__canvases = window.__canvases.filter((r) => { const c = r.deref(); if (c) { px += c.width * c.height; live++; } return !!c; });
      return { heap: performance.memory.usedJSHeapSize, px, canvases: live };
    });
  };
  const samples = [];
  for (let n = 1; n <= 30; n++) {
    await page.evaluate(() => {
      const M = window.__mem, run = M.run;
      // ten rooms, then the same floor built again
      if (M.n > 0 && M.n % 10 === 0) run.startDepth(1);
      const keys = [...run.floor.rooms.keys()];
      const key = keys[M.n % 10 % keys.length];
      run.enterRoom(key, 's');
      M.n++;
      const ctx = AD.ctx;
      for (let f = 0; f < 60; f++) { run.tick({ sx: 0, sy: 0, a: f % 9 === 0, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] }); AD.fx.tick(); AD.view.draw(ctx, run); AD.hud.draw(ctx, run); }
      ctx.getImageData(0, 0, 1, 1);
    });
    if (n === 10 || n === 30) samples.push(await measure());
  }
  const [a, b] = samples;
  memory[mode] = { heap10: +(a.heap / 1e6).toFixed(1), heap30: +(b.heap / 1e6).toFixed(1), heapGrowth: +(b.heap / a.heap - 1).toFixed(3), px10: +(a.px / 1e6).toFixed(2), px30: +(b.px / 1e6).toFixed(2), pxGrowth: +(b.px / a.px - 1).toFixed(3), canvases10: a.canvases, canvases30: b.canvases };
}
await page.evaluate(() => AD.display.set('hd'));
await browser.close();
console.log('hd ', JSON.stringify(res.hd));
console.log('gba', JSON.stringify(res.gba));
console.log('memory hd ', JSON.stringify(memory.hd));
console.log('memory gba', JSON.stringify(memory.gba));
const fail = [];
for (const m of ['hd', 'gba']) {
  if (Math.abs(memory[m].heapGrowth) > 0.15) fail.push(m + ' JS heap changed ' + (memory[m].heapGrowth * 100).toFixed(1) + '% from room 10 to room 30');
  if (Math.abs(memory[m].pxGrowth) > 0.15) fail.push(m + ' live canvas pixels changed ' + (memory[m].pxGrowth * 100).toFixed(1) + '% from room 10 to room 30');
  // a phone's WebView gives a page a few hundred MB: all the art alive at once stays within 64 MB
  if (memory[m].px30 > 16) fail.push(m + ' ' + memory[m].px30 + ' M canvas pixels alive (over 16 M, 64 MB)');
}
if (res.hd.sim95 > 3) fail.push('hd simulation p95 ' + res.hd.sim95 + ' ms > 3');
if (res.hd.draw95 > 8) fail.push('hd drawing p95 ' + res.hd.draw95 + ' ms > 8');
if (errors.length) fail.push('page errors: ' + errors.slice(0, 3).join(' | '));
if (fail.length) { console.log('perf FAILED\n  ' + fail.join('\n  ')); process.exit(1); }
console.log('perf ok');
