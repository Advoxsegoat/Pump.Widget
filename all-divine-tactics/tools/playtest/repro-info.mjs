// Reproduce: INFO during the attack forecast, then attack and defeat the enemy.
// node repro-info.mjs <game.html>
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game] = process.argv.slice(2);
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', e.message));
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top() instanceof AD.Title);
const out = await page.evaluate(async () => {
  const log = [];
  const name = (s) => { for (const k of Object.keys(AD)) if (AD[k] === s.constructor) return k; return s.constructor.name || 'anon'; };
  const stack = () => AD.stack.map(name).join('>');
  const step = async (n, press) => { for (let i = 0; i < n; i++) { if (press && i === 0) AD.input.latch[press] = true; AD.debugStep(1); for (let k = 0; k < 8; k++) await null; } };
  const until = async (pred, max) => { for (let i = 0; i < (max || 2000); i++) { if (pred()) return true; await step(1); } return false; };
  AD.rng = AD.makeRng(5);
  const GM = AD.game; GM.newGame(1, false);
  await step(40);
  GM.startChapter('c1');
  // skip story to the battle
  for (let i = 0; i < 3000 && !(AD.top() instanceof AD.Battle && AD.top().phase === 'p' && AD.top().state === 'map' && !AD.top().busy && !AD.top().banner); i++) {
    const t = AD.top();
    if (t instanceof AD.Dialogue) await step(2, 'start'); else if (t instanceof AD.Menu) await step(2, 'a'); else if (t instanceof AD.TitleCard && t.t > 32) await step(2, 'a'); else await step(1);
  }
  const bt = AD.curBattle;
  const u = bt.alive('p')[0];
  u.stats.str += 30; u.stats.skl += 30; // guarantee the kill
  const foe = bt.alive('e').sort((a, b) => Math.abs(a.x - u.x) + Math.abs(a.y - u.y) - (Math.abs(b.x - u.x) + Math.abs(b.y - u.y)))[0];
  // put Abarax next to a foe so Attack is offered
  const spot = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => [foe.x + dx, foe.y + dy]).find(([x, y]) => bt.map.at(x, y) && !bt.unitAt(x, y) && AD.tiles.cost(bt.map.at(x, y), 'foot') !== null);
  u.x = spot[0]; u.y = spot[1];
  bt.cursor.x = u.x; bt.cursor.y = u.y;
  await step(3, 'a');              // select
  await step(3, 'a');              // stay put -> action menu
  log.push('after move: ' + stack() + ' state=' + bt.state);
  const m = AD.top(); m.i = m.items.findIndex((it) => it.value === 'attack');
  await step(3, 'a');              // Attack -> forecast
  log.push('forecast: ' + stack());
  await step(3, 'x');              // INFO on the target
  log.push('status: ' + stack() + ' busy=' + bt.busy);
  await step(3, 'b');              // close status
  log.push('closed status: ' + stack() + ' busy=' + bt.busy);
  await step(3, 'a');              // confirm the attack
  // watch what follows
  let phantom = false, last = '';
  for (let i = 0; i < 1800; i++) {
    await step(1);
    const s = stack() + ' ph=' + bt.phase + ' st=' + bt.state + ' busy=' + bt.busy + ' turn=' + bt.turn;
    if (s !== last) { log.push('[' + i + '] ' + s); last = s; }
    if (AD.top() instanceof AD.Menu && AD.top().items.some((it) => it.value === 'wait') && u.done) phantom = true;
  }
  return { log, phantom, foeDead: foe.dead, uDone: u.done };
});
console.log(out.log.join('\n'));
console.log('phantom action menu for a finished unit:', out.phantom, ' foe dead:', out.foeDead, ' unit done:', out.uDone);
await browser.close();
