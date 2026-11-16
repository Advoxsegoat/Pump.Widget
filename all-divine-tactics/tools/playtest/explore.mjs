// Fuzz-plays everything outside a single battle: the world map, towns (talk, path actions,
// secrets, shops, inns), camp menus, saves, prep, side stories, dungeons and road fights.
// Reports any scene left busy with nothing running, any thrown error or rejected promise.
//   node explore.mjs <game.html> [seeds] [frames] [parallel]
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const [game, seedsArg = '6', framesArg = '40000', parArg = '3'] = process.argv.slice(2);
const SEEDS = Number(seedsArg), FRAMES = Number(framesArg), PAR = Number(parArg);
const browser = await chromium.launch();

async function runOne(seed) {
  const page = await browser.newPage();
  await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
  await page.goto('file://' + path.resolve(game));
  await page.waitForFunction(() => window.AD && AD.top && AD.top() instanceof AD.Title);
  await page.addScriptTag({ path: path.join(here, process.env.BOTJS || 'bot.js') });
  const rep = await page.evaluate(async ({ seed, FRAMES }) => {
    const GM = AD.game;
    const rnd = AD.makeRng(seed * 7717 + 3);
    AD.rng = AD.makeRng(seed * 7919);
    BOT.seed(seed * 104729 + 11);
    BOT.fuzz = true; BOT.tough = true; BOT.readDialogue = seed % 2 === 0;
    BOT.input = seed % 3 === 0 ? 'touch' : 'keys';
    GM.options.anims = seed % 4 !== 1;
    GM.newGame(seed % 3 === 0 ? 0 : 1, seed % 5 === 0);
    Object.keys(AD.UNITS).forEach((id) => { if (AD.UNITS[id].looks) GM.addUnit(id, true); });
    const s = GM.state;
    s.gold = 60000;
    const ids = Object.keys(AD.CHAPTERS).filter((k) => /^c\d+$/.test(k)).sort((a, b) => +a.slice(1) - +b.slice(1));
    const upto = [8, 13, 17, 21, 24, 27][seed % 6];
    ids.slice(0, upto).forEach((k) => { s.done[k] = true; });
    s.next = ids[upto] || 'end';
    ['dray_spared', 'ivo_met', 'tomas_boat', 'tomas_hint', 'midas_shop', 'bookone', 'files', 'benedict'].forEach((f) => { s.flags[f] = true; });
    Object.keys(AD.SUPPORTS || {}).forEach((k) => { s.supports[k] = 40 + (seed % 3) * 10; });
    ['stack', 'bouill', 'coffee', 'silverbolt', 'doorkey', 'chestkey', 'pear', 'apron', 'ring', 'goldfruit', 'steelsword', 'harbor'].forEach((id) => s.convoy.push(AD.item(id)));
    s.node = ['bilibara', 'saintmireille', 'lenaris', 'garden', 'castemere', 'springs'][seed % 6];
    if (!AD.WORLD.nodes[s.node] || !AD.worldOpen(s.node)) s.node = 'bilibara';
    GM.lastSlot = 1;

    const counts = {};
    const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
    const press = (b) => { AD.input.latch[b] = true; };
    BOT.onWorld = (n) => {
      counts[n] = (counts[n] || 0) + 1;
      const top = AD.top();
      if (top.busy || top.walking) return;
      if (n === 'World') press(pick(['up', 'down', 'left', 'right', 'right', 'down', 'a', 'a', 'a', 'b']));
      else if (n === 'Town') press(pick(['up', 'down', 'left', 'right', 'up', 'left', 'a', 'a', 'a', 'b']));
      else press('a');
    };
    BOT.onGameOver = () => {};

    // a scene's own clock keeps the bot's progress signature moving, so watch the flows directly
    let lastKey = '', since = 0, inBattle = 0;
    BOT.watch = () => {
      const top = AD.top();
      // keep battles short so the run spends its time on the world, towns and menus
      const bt = AD.curBattle;
      if (bt && AD.stack.indexOf(bt) >= 0 && !bt.over) { if (++inBattle > 2500 && !bt.busy && bt.phase === 'p') { inBattle = 0; bt.async(() => bt.win()); } } else inBattle = 0;
      const n = BOT.stackNames().slice(-1)[0];
      const key = n + '|' + (top && (top.busy || top.menuOpen) ? 1 : 0) + '|' + AD.stack.length;
      if (key !== lastKey) { lastKey = key; since = BOT.frames; }
      const age = BOT.frames - since;
      if ((n === 'World' || n === 'Town') && top.busy && !top.walking && age > 900) return n + ' busy with nothing running';
      if (n === 'Title' && top.menuOpen && age > 900) return 'Title menu flow died';
      if ((n === 'Prep' || n === 'Blank') && age > 1800) return n + ' with nothing running';
      return null;
    };
    for (let i = 0; i < 40; i++) { AD.debugStep(1); await null; }
    AD.goto(new AD.World());
    const r = await BOT.run(FRAMES, 4800);
    r.result = r.stuck ? 'STUCK' : r.errors.length ? 'ERROR' : 'ok';
    r.counts = counts;
    r.chapters = Object.keys(GM.state.done).length;
    return r;
  }, { seed, FRAMES });
  await page.close();
  return rep;
}

const results = [];
let next = 1;
const t0 = Date.now();
async function worker() {
  while (next <= SEEDS) {
    const seed = next++;
    let r;
    try { r = await runOne(seed); } catch (e) { r = { result: 'HARNESS', errors: [String(e)] }; }
    results.push({ seed, ...r });
    fs.writeFileSync(path.join(here, process.env.OUT || 'explore.json'), JSON.stringify(results, null, 2));
    const flag = r.result !== 'ok' ? '  <<<<<' : '';
    console.log(`${((Date.now() - t0) / 1000).toFixed(0)}s seed ${seed}: ${r.result} frames=${r.frames} cmds=${r.commands} scenes=${JSON.stringify(r.counts || {})}${flag}`);
  }
}
await Promise.all(Array.from({ length: PAR }, worker));
const bad = results.filter((r) => r.result !== 'ok');
console.log(`\n${bad.length} problem runs of ${results.length}`);
bad.forEach((r) => console.log(JSON.stringify({ seed: r.seed, result: r.result, stuck: r.stuck, errors: (r.errors || []).slice(0, 4), stack: r.stack, log: (r.log || []).slice(-10) }, null, 1)));
await browser.close();
