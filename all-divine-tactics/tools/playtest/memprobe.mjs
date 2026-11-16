// Plays the campaign in one page for a long time and samples the JS heap and live canvases,
// to find memory that grows with every battle.
//   node memprobe.mjs <game.html> [frames] [every]
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const [game, framesArg = '120000', everyArg = '10000'] = process.argv.slice(2);
const browser = await chromium.launch({ args: ['--js-flags=--expose-gc'] });
const page = await browser.newPage();
await page.addInitScript(() => {
  window.requestAnimationFrame = () => 0;
  // count canvases that are still alive
  window.__cv = [];
  const ce = document.createElement.bind(document);
  document.createElement = (t, o) => { const e = ce(t, o); if (String(t).toLowerCase() === 'canvas') window.__cv.push(new WeakRef(e)); return e; };
});
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top() instanceof AD.Title);
await page.addScriptTag({ path: path.join(here, 'bot.js') });
const cdp = await page.context().newCDPSession(page);
await cdp.send('Performance.enable');
await page.evaluate(() => {
  const GM = AD.game;
  AD.rng = AD.makeRng(4242);
  BOT.seed(99); BOT.fuzz = true; BOT.tough = true; BOT.input = 'keys';
  GM.newGame(1, false);
  Object.keys(AD.UNITS).forEach((id) => { if (AD.UNITS[id].looks) GM.addUnit(id, true); });
  GM.lastSlot = 1;
  // straight through the campaign: each win goes to the next chapter
  BOT.onWorld = () => {
    if (AD.fade.a !== 0 || AD.fade.target !== 0) return;
    const nx = GM.state.next;
    if (!nx || nx === 'end' || !AD.chapter(nx)) { GM.state.next = 'c1'; }
    BOT.battles++;
    GM.startChapter(GM.state.next);
  };
  BOT.onGameOver = () => { BOT.gameOverHandled = true; };
  window.__start = () => GM.startChapter('c1');
});
await page.evaluate(async () => { for (let i = 0; i < 40; i++) { AD.debugStep(1); await null; } __start(); });
const FR = Number(framesArg), EV = Number(everyArg);
console.log('frames  battles chapter  heapMB  liveCanvas  totalCanvas  fighterCache');
for (let f = 0; f < FR; f += EV) {
  await page.evaluate(async (n) => { await BOT.run(n, 1e9); }, EV);
  // a new battle every segment: battle units are new objects each time, which is where leaks show
  await page.evaluate(() => { const k = (BOT.battles++ % 9) + 1; AD.game.startChapter('c' + k); });
  await cdp.send('HeapProfiler.collectGarbage');
  const m = await cdp.send('Performance.getMetrics');
  const heap = m.metrics.find((x) => x.name === 'JSHeapUsedSize').value / 1048576;
  const s = await page.evaluate(() => ({
    live: __cv.filter((r) => r.deref()).length, total: __cv.length, battles: BOT.battles,
    ch: AD.curBattle && AD.curBattle.ch.id, errors: BOT.errors.length,
  }));
  console.log(`${String(f + EV).padStart(6)}  ${String(s.battles).padStart(7)}  ${String(s.ch).padStart(7)}  ${heap.toFixed(1).padStart(6)}  ${String(s.live).padStart(10)}  ${String(s.total).padStart(11)}  errors=${s.errors}`);
}
await browser.close();
