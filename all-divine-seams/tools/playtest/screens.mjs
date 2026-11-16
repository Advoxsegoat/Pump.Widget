// Pictures of every screen around play, in both display modes, to check by eye.
//   node tools/playtest/screens.mjs web/index.html out/screens
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'out/screens'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 600 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top());
const shots = await page.evaluate(async () => {
  const step = async (n) => { for (let i = 0; i < (n || 1); i++) { AD.debugStep(1); await null; } };
  const snap = () => AD.canvas.toDataURL('image/png').split(',')[1];
  const res = {};
  AD.meta.petals = 95; AD.meta.unlocks.add('startHealing');
  ['grunt', 'rat', 'whelp', 'tough', 'goldtooth'].forEach((id) => AD.meta.book.monsters.add(id));
  ['lazyman', 'sparkcoil', 'roseheart'].forEach((id) => AD.meta.book.items.add(id));
  for (const mode of ['hd', 'gba']) {
    AD.display.set(mode);
    while (AD.stack.length) AD.pop();
    AD.push(new AD.Title()); await step(30); res[mode + '-title'] = snap();
    const g = new AD.Garden(); while (AD.stack.length) AD.pop(); AD.push(g); await step(12);
    for (let i = 0; i < 3; i++) { g.go(i, i === 0 ? [7, 2] : i === 1 ? [4, 3] : [8, 4]); g.hero.facing = [1, 0]; await step(12); res[mode + '-garden' + i] = snap(); }
    g.go(0, [7, 2]); await step(10);
    const tear = new AD.Tear(); AD.push(tear); tear.done = () => AD.pop(tear); await step(2); res[mode + '-tear'] = snap(); AD.pop(tear);
    const shop = new AD.Shop(); AD.push(shop); shop.done = () => AD.pop(shop); await step(2); res[mode + '-shop'] = snap(); AD.pop(shop);
    const book = new AD.Book(); AD.push(book); book.done = () => AD.pop(book); book.menu.i = 2; await step(2); res[mode + '-book'] = snap(); AD.pop(book);
    const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 99, meta: AD.meta });
    run.god = true;
    ['lazyman', 'lazyman', 'sparkcoil', 'warmmitts', 'roseheart', 'tinring', 'bellchime'].forEach((id) => AD.items.give(run, run.hero, id));
    AD.cons.give(run, 'haste'); AD.cons.give(run, 'identify');
    const play = new AD.Play(run); while (AD.stack.length) AD.pop(); AD.push(play); await step(40);
    const pause = new AD.Pause(run); AD.push(pause); pause.done = () => AD.pop(pause); await step(2); res[mode + '-pause'] = snap();
    const items = new AD.Items(run); AD.push(items); items.done = () => AD.pop(items); items.i = 2; await step(2); res[mode + '-items'] = snap(); AD.pop(items);
    const map = new AD.MapView(run); AD.push(map); map.done = () => AD.pop(map); await step(2); res[mode + '-map'] = snap(); AD.pop(map);
    const set = new AD.Settings(); AD.push(set); set.done = () => AD.pop(set); await step(2); res[mode + '-settings'] = snap(); AD.pop(set);
    AD.pop(pause);
    run.petals = 7; run.kills = 23; run.end(false, 'Gold Tooth');
    const sum = new AD.Summary(run, null); while (AD.stack.length) AD.pop(); AD.push(sum); await step(40); res[mode + '-summary'] = snap();
  }
  AD.display.set('hd');
  return res;
});
for (const [k, v] of Object.entries(shots)) fs.writeFileSync(path.join(out, k + '.png'), Buffer.from(v, 'base64'));
await browser.close();
if (errors.length) { console.log('page errors:\n  ' + errors.slice(0, 5).join('\n  ')); process.exit(1); }
console.log('screens written to', out, Object.keys(shots).length);
