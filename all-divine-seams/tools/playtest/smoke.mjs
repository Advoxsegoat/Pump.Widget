// Boots the page in Chromium with the frame loop stubbed and drives it by hand.
//   node tools/playtest/smoke.mjs web/index.html [outdir]
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'out/smoke'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top());
const fail = [];
const check = (c, what) => { if (!c) fail.push(what); };
const size = () => page.evaluate(() => [AD.canvas.width, AD.canvas.height]);
await page.evaluate(() => AD.debugStep(30));
check(JSON.stringify(await size()) === '[360,240]', 'hd canvas is 360x240');
await page.evaluate(() => { AD.display.set('gba'); AD.debugStep(5); });
check(JSON.stringify(await size()) === '[240,160]', 'gba canvas is 240x160');
await page.evaluate(() => { AD.display.set('hd'); AD.debugStep(5); });
fs.writeFileSync(path.join(out, 'title.png'), Buffer.from(await page.evaluate(() => AD.canvas.toDataURL('image/png').split(',')[1]), 'base64'));

// a seeded run, driven by a scripted pad: out of the start room into a fight, swinging
const shots = await page.evaluate(() => {
  const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 4242 });
  run.god = true;
  AD.view.bind(run);
  const F = run.floor, S = F.rooms.get(F.start);
  // the first door on the shortest way to a combat room not yet cleared
  const route = (from) => {
    const prev = new Map([[from, null]]), q = [from];
    while (q.length) {
      const k = q.shift(), R = F.rooms.get(k);
      if (k !== from && R.type === 'combat' && run.roomState.get(k).state !== 'cleared') {
        let c = k; while (prev.get(c) && prev.get(c)[0] !== from) c = prev.get(c)[0];
        return prev.get(c)[1];
      }
      for (const [d, link] of Object.entries(R.doors)) {
        if (link !== 'open') continue;
        const n = (R.gx + AD.gen.DIRS[d][0]) + ',' + (R.gy + AD.gen.DIRS[d][1]);
        if (F.rooms.has(n) && !prev.has(n)) { prev.set(n, [k, d]); q.push(n); }
      }
    }
    return null;
  };
  const pad = () => ({ sx: 0, sy: 0, a: false, aHeld: false, aReleased: false, b: false, r: false, l: false, q: [false, false, false] });
  const sgn = (v) => (v > 0 ? 1 : v < 0 ? -1 : 0);
  // the step that goes downhill on the room's distance map to the goal
  const toward = (room, h, gx, gy) => {
    const D = room.grid.distanceMap([[gx, gy]], 'walk');
    let best = null, bd = D[h.y * 15 + h.x] < 0 ? 999 : D[h.y * 15 + h.x];
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]]) {
      const v = D[(h.y + dy) * 15 + h.x + dx];
      if (v >= 0 && v < bd && room.grid.canStep(h.x, h.y, dx, dy, 'walk') && !room.grid.bodyAt(h.x + dx, h.y + dy)) { bd = v; best = [dx, dy]; }
    }
    return best || [sgn(gx - h.x), sgn(gy - h.y)];
  };
  const out = {};
  const ctx = AD.ctx;
  const snap = (name) => { AD.view.draw(ctx, run); AD.hud.draw(ctx, run); out[name] = AD.canvas.toDataURL('image/png').split(',')[1]; };
  const stats = { combat: false, hits: 0, numbers: 0, bars: 0, telegraphs: 0 };
  run.events.on('hit', () => stats.hits++);
  for (let f = 0; f < 600; f++) {
    const p = pad(), h0 = run.hero, room = run.room;
    // decide from where the hero is going: a held direction chains the next step on arrival
    const h = h0.move ? { x: h0.move.x1, y: h0.move.y1, move: null, facing: h0.facing } : h0;
    const side = !run.transition && room.type !== 'combat' ? route(room.key) : null;
    if (side) {
      const [mx, my] = AD.room.MOUTH[side], [dx, dy] = AD.gen.DIRS[side];
      if (h.x === mx && h.y === my) { p.sx = dx; p.sy = dy; } else [p.sx, p.sy] = toward(room, h, mx, my);
    } else if (!run.transition) {
      stats.combat = stats.combat || room.type === 'combat';
      const foes = [...room.bodies.values()].filter((e) => e.kind !== 'hero' && !e.dead && !e.untargetable);
      foes.sort((a, b) => Math.hypot(a.x - h.x, a.y - h.y) - Math.hypot(b.x - h.x, b.y - h.y));
      const m = foes[0];
      if (m) {
        const dx = m.x - h.x, dy = m.y - h.y;
        if (Math.max(Math.abs(dx), Math.abs(dy)) <= 1) { if (!h0.move && f % 3 === 0) { h0.facing = [sgn(dx), dx ? 0 : sgn(dy)]; p.a = true; } }
        else [p.sx, p.sy] = toward(room, h, m.x, m.y);
      }
    }
    run.tick(p); AD.fx.tick();
    stats.numbers = Math.max(stats.numbers, AD.fx.nums.length);
    stats.bars = Math.max(stats.bars, [...run.room.bodies.values()].filter((e) => e.kind === 'monster' && e.hp < e.mhp && !e.dead).length);
    stats.telegraphs = Math.max(stats.telegraphs, (run.room.attacks || []).filter((a) => a.owner && a.owner.kind !== 'hero' && a.frame <= a.def.wind).length);
    if (f === 420 || f === 520) snap('hd-' + f);
    if (run.transition && run.transition.t === 10 && !out['hd-slide']) { snap('hd-slide'); stats.slide = true; }
  }
  snap('hd-600');
  AD.display.set('gba');
  snap('gba-600');
  for (let f = 0; f < 40; f++) { run.tick(pad()); AD.fx.tick(); }
  snap('gba-640');
  AD.display.set('hd');
  return { out, stats };
});
check(shots.stats.combat, 'the scripted pad reached a combat room');
check(shots.stats.slide, 'the room slide was drawn');
check(shots.stats.hits > 0, 'blows landed: ' + shots.stats.hits);
console.log('smoke play:', JSON.stringify(shots.stats));
for (const [k, v] of Object.entries(shots.out)) fs.writeFileSync(path.join(out, 'smoke-' + k + '.png'), Buffer.from(v, 'base64'));
check(errors.length === 0, 'no page errors: ' + errors.slice(0, 3).join(' | '));
await browser.close();
if (fail.length) { console.log('smoke FAILED\n  ' + fail.join('\n  ')); process.exit(1); }
console.log('smoke ok');
