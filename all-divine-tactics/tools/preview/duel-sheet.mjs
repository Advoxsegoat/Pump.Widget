// Renders a contact sheet of one duel, frame by frame, so battle animation can be judged by eye.
//   node duel-sheet.mjs <game.html> '<config json>' <out.png>
// config: { a, d: unit or look ids ("abarax", "kael", "thug", "horror"; "abarax:rosedivine" picks a look),
//           wa, wd: weapon ids, dist: 1 or 2, ev: [{ who: 'a'|'d', hit, crit }], every: frames between shots,
//           cols, scale, crop: [top, bottom], biome }
// Needs Playwright (npm i -g playwright).
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const here = path.dirname(fileURLToPath(import.meta.url));
const [game, cfg, out] = process.argv.slice(2);
const browser = await chromium.launch();
const page = await browser.newPage();
const errs = [];
page.on('pageerror', (e) => errs.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.Duel);
await page.addScriptTag({ content: 'window.DUEL = ' + JSON.stringify(JSON.parse(cfg)) + ';\n' + fs.readFileSync(path.join(here, 'duel-sheet.js'), 'utf8') });
const url = await page.evaluate(() => window.SCENE().toDataURL());
fs.writeFileSync(out, Buffer.from(url.split(',')[1], 'base64'));
if (errs.length) { console.log('ERRORS:\n' + errs.join('\n')); process.exitCode = 1; }
await browser.close();
