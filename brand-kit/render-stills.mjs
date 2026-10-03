// Renders the profile picture and YouTube banner to brand-kit/out/.
// Usage: node brand-kit/render-stills.mjs ["CHANNEL NAME"]
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');

const here = path.dirname(fileURLToPath(import.meta.url));
const name = process.argv[2] || 'END OF FEED';
const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: 2560, height: 1440 } });

for (const which of ['avatar', 'banner']) {
  const url = `file://${here}/src/stills.html?which=${which}&name=${encodeURIComponent(name)}`;
  await page.goto(url);
  await page.waitForFunction(() => window.ready === true);
  await page.locator('#c').screenshot({ path: `${here}/out/${which}.png` });
  console.log(`wrote out/${which}.png`);
}
await browser.close();
