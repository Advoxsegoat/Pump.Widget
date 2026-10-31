import { test } from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const AD = load(['engine/core.js', 'sim/stats.js', 'view/hud.js']);
const overlap = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

test('the HUD layout fits the screen in both display modes, and its corners never collide', () => {
  for (const mode of ['hd', 'gba']) {
    const L = AD.hud.layout(mode), W = mode === 'hd' ? 360 : 240, H = mode === 'hd' ? 240 : 160;
    for (const [k, r] of Object.entries(L)) {
      assert.ok(r.x >= 0 && r.y >= 0 && r.x + r.w <= W && r.y + r.h <= H, mode + ' ' + k + ' ' + JSON.stringify(r));
    }
    assert.ok(!overlap(L.hp, L.coins), mode + ' hp/coins');
    assert.ok(!overlap(L.minimap, L.hp), mode + ' minimap/hp');
    for (const k of ['coins', 'keys', 'bombs', 'clock', 'band', 'quick0', 'quick1']) assert.ok(!overlap(L[k], L.hp) && !overlap(L[k], L.level), mode + ' ' + k);
    assert.ok(!overlap(L.quick0, L.quick1) && !overlap(L.coins, L.keys) && !overlap(L.keys, L.bombs) && !overlap(L.clock, L.band), mode + ' top right');
    assert.ok(L.quick0.y >= L.minimap.y + L.minimap.h, mode + ' quickslots sit under the minimap');
  }
});

test('big numbers shorten: coins, damage and the rest go through stat.short', () => {
  assert.equal(AD.hud.coinsText(12345), '12.3k');
  assert.equal(AD.hud.coinsText(999), '999');
  assert.equal(AD.hud.coinsText(4100000), '4.1m');
});

test('the clock reads m:ss of play', () => {
  assert.equal(AD.hud.clock(0), '0:00');
  assert.equal(AD.hud.clock(3600 * 12 + 60 * 34), '12:34');
});

test('the slow-frame notice: only in hd, only when the first 300 frames of play average over 20 ms', () => {
  const S = AD.hud.slowCheck();
  for (let i = 0; i < 299; i++) assert.equal(S.sample(25, 'hd'), false);
  assert.equal(S.sample(25, 'hd'), true);
  assert.equal(S.sample(25, 'hd'), false, 'once only');
  const F = AD.hud.slowCheck();
  let any = false;
  for (let i = 0; i < 400; i++) any = F.sample(12, 'hd') || any;
  assert.equal(any, false, 'a fast device is never told');
  const G = AD.hud.slowCheck();
  any = false;
  for (let i = 0; i < 400; i++) any = G.sample(40, 'gba') || any;
  assert.equal(any, false, 'already in True GBA');
});

test('the third quickslot, once unlocked, has a place of its own on screen and takes taps', () => {
  for (const mode of ['hd', 'gba']) {
    const L = AD.hud.layout(mode);
    assert.ok(L.quick2, mode);
    for (const k of ['quick0', 'quick1', 'minimap', 'clock', 'band', 'coins', 'keys', 'bombs', 'hp', 'level', 'gift']) assert.ok(!overlap(L.quick2, L[k]), mode + ' quick2/' + k);
  }
  const L = AD.hud.layout('hd'), mid = (r) => [r.x + r.w / 2, r.y + r.h / 2];
  AD.hud.state.slots = 3;
  assert.equal(AD.hud.quickAt(...mid(L.quick2), 'hd'), 2);
  assert.equal(AD.hud.quickAt(...mid(L.quick0), 'hd'), 0);
  AD.hud.state.slots = 2;
  assert.equal(AD.hud.quickAt(...mid(L.quick2), 'hd'), -1, 'no third slot drawn, no tap there');
});

