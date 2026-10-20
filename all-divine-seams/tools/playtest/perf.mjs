// Timing under load (plan Task 16): a combat room with 40 monsters, poison gas and burning grass.
// Simulation and drawing are timed apart, per frame, in both display modes.
//   node tools/playtest/perf.mjs web/index.html [outdir]
// Passes when, in HD at the 95th percentile, a step takes <= 3 ms and a frame draws in <= 8 ms.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'out/perf'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
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
await browser.close();
console.log('hd ', JSON.stringify(res.hd));
console.log('gba', JSON.stringify(res.gba));
const fail = [];
if (res.hd.sim95 > 3) fail.push('hd simulation p95 ' + res.hd.sim95 + ' ms > 3');
if (res.hd.draw95 > 8) fail.push('hd drawing p95 ' + res.hd.draw95 + ' ms > 8');
if (errors.length) fail.push('page errors: ' + errors.slice(0, 3).join(' | '));
if (fail.length) { console.log('perf FAILED\n  ' + fail.join('\n  ')); process.exit(1); }
console.log('perf ok');
