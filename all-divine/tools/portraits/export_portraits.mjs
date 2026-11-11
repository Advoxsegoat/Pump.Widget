// Renders the book's portraits to PNGs: the earlier Tactics game draws every portrait in code
// (all-divine-tactics/web/index.html, AD.spr.portrait), so this opens that page and writes each look and
// expression as it is drawn: 48x48, no scaling, to assets/portraits/<id>/<expression>.png.
// Usage: node tools/portraits/export_portraits.mjs      (from all-divine/; needs Node and Playwright)
// The PNGs are committed: only a re-render needs this.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const game = path.join(here, '../../../all-divine-tactics/web/index.html');
const out = path.join(here, '../../assets/portraits');
const LOOKS = ['abarax', 'noella', 'sierra', 'kesra', 'goldtooth'];
const EXPRESSIONS = ['neutral', 'smile', 'serious', 'angry', 'sad', 'surprise'];

const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto('file://' + game);
await page.waitForFunction(() => window.AD && AD.spr && AD.PORTS && AD.PORTS.abarax);

const files = await page.evaluate(([looks, expressions]) => {
  const found = {};
  for (const id of looks) {
    for (const expression of expressions) {
      const canvas = AD.spr.portrait(AD.PORTS[id], expression);
      found[`${id}/${expression}.png`] = canvas.toDataURL('image/png');
    }
  }
  return found;
}, [LOOKS, EXPRESSIONS]);

for (const [rel, url] of Object.entries(files)) {
  const file = path.join(out, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.from(url.split(',')[1], 'base64'));
}
console.log(`wrote ${Object.keys(files).length} portraits under ${path.relative(process.cwd(), out)}`);
await browser.close();
