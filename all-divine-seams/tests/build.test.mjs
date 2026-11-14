import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { load, ROOT } from './load.mjs';

test('build joins modules in order and the page boots in node', () => {
  execFileSync('node', ['tools/build.mjs'], { cwd: ROOT });
  const html = fs.readFileSync(path.join(ROOT, 'web/index.html'), 'utf8');
  const order = fs.readFileSync(path.join(ROOT, 'src/order.txt'), 'utf8').split(/\s+/).filter(Boolean);
  let at = -1;
  for (const f of order) { const i = html.indexOf('// ---- src/' + f + '\n'); assert.ok(i > at, f); at = i; }
  assert.ok(html.startsWith('<!doctype html>'));
  assert.ok(html.trimEnd().endsWith('</html>'));
});

test('the artifact page drops the document skeleton', () => {
  const out = path.join(ROOT, 'web/.page-test.html');
  execFileSync('node', ['tools/build.mjs', '--page', out], { cwd: ROOT });
  const page = fs.readFileSync(out, 'utf8');
  fs.unlinkSync(out);
  assert.ok(page.startsWith('<title>Between the Rooms</title>'));
  assert.ok(!page.includes('</body></html>'));
});

test('display modes', () => {
  const AD = load(['engine/core.js']);
  assert.deepEqual([AD.display.W, AD.display.H, AD.display.T], [360, 240, 24]);
  AD.display.set('gba');
  assert.deepEqual([AD.display.W, AD.display.H, AD.display.T, AD.display.mode], [240, 160, 16, 'gba']);
});

test('storage is namespaced seams. and survives a missing localStorage', () => {
  const AD = load(['engine/core.js']);
  assert.equal(AD.store.get('x'), null);
  assert.equal(AD.store.set('x', 1), false);
});
