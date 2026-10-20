// The playtest sweep: the bot plays from the title, through the tear, to death, victory or the frame
// limit, for each seed, with the keyboard and with the phone's touch controls.
//   node tools/playtest/sweep.mjs <html> <seeds> <frames> <parallel> [touch|keys]
// Each run reports the depth reached, won or lost, frames played, errors (AD.errlog and page
// errors), soft-locks (3,600 frames with no change of hero tile, room, monster HP or gate charge),
// and the 95th-percentile frame time. Exits non-zero on any error or soft-lock.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const [game, seedsArg = '4', framesArg = '36000', parArg = '4', only] = process.argv.slice(2);
const SEEDS = +seedsArg, FRAMES = +framesArg, PAR = +parArg;
const modes = only ? [only] : ['keys', 'touch'];
const jobs = [];
for (let s = 1; s <= SEEDS; s++) for (const m of modes) jobs.push({ seed: 1000 + s * 37, mode: m });
const browser = await chromium.launch();
const results = [];
async function one(job) {
  const touch = job.mode === 'touch';
  const ctx = await browser.newContext(touch ? { viewport: { width: 780, height: 360 }, hasTouch: true, isMobile: true } : { viewport: { width: 900, height: 600 } });
  const page = await ctx.newPage();
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(String(e)));
  await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
  await page.goto('file://' + path.resolve(game));
  await page.waitForFunction(() => window.AD && AD.top && AD.top());
  await page.addScriptTag({ path: path.join(here, 'bot.js') });
  await page.evaluate(({ seed, mode }) => {
    AD.rng.newSeed = () => seed;
    BOT.start({ mode });
    window.SW = { f: 0, sig: '', still: 0, soft: false, times: [], errs0: AD.errlog.length, deepest: 1, done: false };
  }, job);
  let st;
  for (;;) {
    st = await page.evaluate(async (limit) => {
      const S = window.SW;
      for (let i = 0; i < 1200 && S.f < limit && !S.done; i++) {
        BOT.frame();
        const draw = S.f % 4 === 0;
        const t0 = performance.now();
        AD.debugStep(1, { render: draw });
        if (draw) { AD.ctx.getImageData(0, 0, 1, 1); S.times.push(performance.now() - t0); }
        await null;
        S.f++;
        const top = AD.top(), name = AD.sceneName(top);
        if (name === 'Summary' || (top && top.run && top.run.over)) { S.done = true; S.over = top.run ? top.run.over : null; S.run = top.run; break; }
        if (top && top.run) {
          const run = top.run, h = run.hero;
          S.deepest = Math.max(S.deepest, run.depth);
          S.run = run;
          const hp = [...run.room.bodies.values()].reduce((a, e) => a + (e.kind !== 'hero' ? Math.round(e.hp) : 0), 0);
          const sig = [run.room.key, h.x, h.y, hp, run.gate ? run.gate.f : -1, Math.round(h.hp)].join('|');
          if (sig === S.sig) { if (++S.still >= 3600) { S.soft = true; S.done = true; S.where = sig + ' ' + name; } } else { S.sig = sig; S.still = 0; }
        }
      }
      const run = S.run;
      const ts = S.times.slice().sort((a, b) => a - b);
      return { f: S.f, done: S.done, soft: S.soft, where: S.where, depth: run ? run.depth : 0, deepest: S.deepest, won: !!(S.over && S.over.won), by: S.over ? S.over.by : null, coins: run ? run.coins : 0, kills: run ? run.kills : 0, items: run && run.hero ? (run.hero.itemOrder || []).length : 0, level: run && run.hero ? run.hero.level : 0, errors: AD.errlog.slice(S.errs0).map((e) => e.msg + ' @' + e.where), p95: ts.length ? +ts[Math.floor(ts.length * 0.95)].toFixed(2) : 0 };
    }, FRAMES);
    if (st.done || st.f >= FRAMES) break;
  }
  await ctx.close();
  const r = Object.assign({ seed: job.seed, mode: job.mode, pageErrors }, st);
  r.problem = r.soft || r.errors.length > 0 || pageErrors.length > 0;
  results.push(r);
  console.log(`${String(r.seed).padStart(5)} ${r.mode.padEnd(5)} depth ${r.deepest} ${r.won ? 'WON ' : r.by ? 'lost' : 'time'} f=${r.f} lv${r.level} kills ${r.kills} items ${r.items} p95 ${r.p95}ms${r.by ? ' by ' + r.by : ''}${r.soft ? ' SOFT-LOCK ' + r.where : ''}${r.errors.length ? ' ERRORS ' + r.errors.slice(0, 2).join(' | ') : ''}${pageErrors.length ? ' PAGE ' + pageErrors[0] : ''}`);
}
const queue = jobs.slice();
await Promise.all(Array.from({ length: PAR }, async () => { while (queue.length) await one(queue.shift()); }));
await browser.close();
const problems = results.filter((r) => r.problem).length;
const best = Math.max(...results.map((r) => r.deepest));
fs.mkdirSync('out', { recursive: true });
fs.writeFileSync('out/sweep.json', JSON.stringify(results, null, 1));
console.log(`${problems} problem runs of ${results.length}; deepest depth ${best}; wins ${results.filter((r) => r.won).length}`);
process.exit(problems ? 1 : 0);
