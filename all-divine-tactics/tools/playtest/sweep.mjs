// node sweep.mjs <game.html> [seeds] [frames] [parallel] [chapters...]
// Fuzz-plays each chapter in keys and touch modes; reports stalls and errors.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const [game, seedsArg = '2', framesArg = '30000', parArg = '4', ...only] = process.argv.slice(2);
const SEEDS = Number(seedsArg), FRAMES = Number(framesArg), PAR = Number(parArg);
const browser = await chromium.launch();

async function runOne(ch, seed, input) {
  const page = await browser.newPage();
  await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
  await page.goto('file://' + path.resolve(game));
  await page.waitForFunction(() => window.AD && AD.top && AD.top() instanceof AD.Title);
  await page.addScriptTag({ path: path.join(here, 'bot.js') });
  const rep = await page.evaluate(async ({ ch, seed, input, FRAMES }) => {
    AD.rng = AD.makeRng(seed * 7919);
    BOT.seed(seed * 104729 + input.length);
    BOT.fuzz = true; BOT.input = input; BOT.tough = true; BOT.readDialogue = seed % 2 === 0;
    const GM = AD.game;
    GM.newGame(seed % 3 === 0 ? 0 : 1, false);
    Object.keys(AD.UNITS).forEach((id) => { if (AD.UNITS[id].looks) GM.addUnit(id, true); });
    GM.state.convoy.push(AD.item('stack'), AD.item('stack'));
    GM.lastSlot = 1;
    let result = null;
    BOT.onWorld = () => { result = result || 'won'; BOT.done = true; };
    BOT.onGameOver = () => { result = result || 'lost'; BOT.done = true; };
    // let the boot fade-in finish first: a scene change on frame 0 hits engine bug A
    for (let i = 0; i < 40; i++) { AD.debugStep(1); await null; }
    BOT.ch = ch;
    GM.startChapter(ch);
    const r = await BOT.run(FRAMES, 3600);
    if (AD.curBattle && AD.curBattle.ch.id !== ch && r.result !== 'STUCK') r.wrongChapter = AD.curBattle.ch.id;
    r.result = r.stuck ? 'STUCK' : r.errors.length ? 'ERROR' : result || 'timeout';
    return r;
  }, { ch, seed, input, FRAMES });
  await page.close();
  return rep;
}

const chapters = only.length ? only : await (async () => {
  const p = await browser.newPage();
  await p.goto('file://' + path.resolve(game));
  await p.waitForFunction(() => window.AD && AD.CHAPTERS);
  const ids = await p.evaluate(() => Object.keys(AD.CHAPTERS).filter((k) => AD.CHAPTERS[k].map));
  await p.close();
  return ids;
})();
const jobs = [];
for (const ch of chapters) for (let s = 1; s <= SEEDS; s++) for (const input of ['keys', 'touch']) jobs.push({ ch, seed: s, input });
console.log(`${jobs.length} runs over ${chapters.length} chapters`);
const results = [];
let next = 0;
const t0 = Date.now();
async function worker() {
  while (next < jobs.length) {
    const j = jobs[next++];
    let r;
    try { r = await runOne(j.ch, j.seed, j.input); } catch (e) { r = { result: 'HARNESS', errors: [String(e)], frames: 0 }; }
    results.push({ ...j, ...r });
    fs.writeFileSync(path.join(here, process.env.OUT || 'sweep-results.json'), JSON.stringify(results, null, 2));
    const flag = ['STUCK', 'ERROR', 'HARNESS'].includes(r.result) ? '  <<<<<' : '';
    console.log(`${((Date.now() - t0) / 1000).toFixed(0)}s ${j.ch} s${j.seed} ${j.input}: ${r.result} frames=${r.frames} cmds=${r.commands}${flag}`);
  }
}
await Promise.all(Array.from({ length: PAR }, worker));
fs.writeFileSync(path.join(here, process.env.OUT || 'sweep-results.json'), JSON.stringify(results, null, 2));
const bad = results.filter((r) => ['STUCK', 'ERROR', 'HARNESS'].includes(r.result));
console.log(`\n${bad.length} problem runs of ${results.length}`);
bad.forEach((r) => console.log(JSON.stringify({ ch: r.ch, seed: r.seed, input: r.input, result: r.result, stuck: r.stuck, errors: r.errors, stack: r.stack, sig: r.sig, battle: r.battle, log: (r.log || []).slice(-12) }, null, 1)));
await browser.close();
