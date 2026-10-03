// Renders the teaser frames to a temp dir, then build-teaser.py adds audio and encodes.
// Usage: node brand-kit/render-teaser.mjs <frames_dir> ["CHANNEL NAME"]
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = process.argv[2];
const name = process.argv[3] || 'END OF FEED';
const FPS = 30;
fs.mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
page.on('pageerror', (e) => { console.error('pageerror:', e.message); process.exit(1); });
await page.goto(`file://${here}/src/teaser.html?name=${encodeURIComponent(name)}`);
await page.waitForFunction(() => window.ready === true);
const duration = await page.evaluate(() => window.DURATION);
const total = Math.round(duration * FPS);
for (let i = 0; i < total; i++) {
  await page.evaluate((t) => window.renderFrame(t), i / FPS);
  await page.screenshot({ path: path.join(outDir, `${String(i).padStart(5, '0')}.jpg`), type: 'jpeg', quality: 92 });
  if (i % 60 === 0) console.log(`frame ${i}/${total}`);
}
await browser.close();
console.log(`rendered ${total} frames`);
