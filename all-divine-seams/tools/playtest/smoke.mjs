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
check(errors.length === 0, 'no page errors: ' + errors.slice(0, 3).join(' | '));
fs.writeFileSync(path.join(out, 'title.png'), Buffer.from(await page.evaluate(() => AD.canvas.toDataURL('image/png').split(',')[1]), 'base64'));
await browser.close();
if (fail.length) { console.log('smoke FAILED\n  ' + fail.join('\n  ')); process.exit(1); }
console.log('smoke ok');
