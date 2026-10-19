// Drives the 1.3 mechanics directly: arts, statuses, new skills, rescue/mend/drop, and renders
// the new screens (forecast with an art, the face-off card, the skills page) to PNGs.
//   node smoke.mjs <game.html> <outdir>
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'smoke-out'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 800, height: 450 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top() instanceof AD.Title);
const shot = async (name) => {
  const b64 = await page.evaluate(() => AD.canvas.toDataURL('image/png').split(',')[1]);
  fs.writeFileSync(path.join(out, name + '.png'), Buffer.from(b64, 'base64'));
};
// one frame per macrotask, as in the game: promise continuations run between frames
const step = (n, press) => page.evaluate(async ([n, press]) => { for (let i = 0; i < Math.max(n, press ? 3 : 0); i++) { if (press && i === 0) AD.input.src.key[press] = true; if (press && i === 2) AD.input.src.key[press] = false; AD.debugStep(1); await new Promise((r) => setTimeout(r, 0)); } }, [n, press || null]);

// ---------------------------------------------------------------- logic
const logic = await page.evaluate(async () => {
  const pass = [], fail = [];
  const ok = (cond, what) => (cond ? pass : fail).push(what);
  const GM = AD.game;
  for (let i = 0; i < 40; i++) AD.debugStep(1);
  // waits resolve at once: nothing here needs the clock
  AD.TEST = true;
  GM.newGame(1, false);
  Object.keys(AD.UNITS).forEach((id) => { if (AD.UNITS[id].looks) GM.addUnit(id, true); });
  const G = AD.gfx;
  Object.entries(AD.ARTS).forEach(([id, a]) => { if (G.measure(a.desc) > 244) fail.push('art desc too wide: ' + id + ' ' + G.measure(a.desc)); });
  Object.values(AD.ITEMS).filter((d) => d.weapon).forEach((d) => { try { AD.weaponHelp(d); } catch (e) { fail.push('help ' + d.id + ' ' + e); } });
  ok(Object.values(AD.ITEMS).filter((d) => d.weapon).every((d) => AD.ARTS[AD.artId(d)]), 'every weapon has an art');
  Object.values(AD.LEARN).forEach((l) => l.forEach(([, , sk]) => { if (!AD.SKILLS[sk]) fail.push('unknown skill ' + sk); }));
  Object.keys(AD.LEARN).forEach((id) => { if (!AD.UNITS[id]) fail.push('LEARN for unknown unit ' + id); });

  // learning: a record that is already past a level gets the skill on repair
  const rec = GM.record('vanity'); rec.lv = 13;
  const notes = GM.repair();
  ok(rec.skills.indexOf('focus') >= 0 && rec.skills.indexOf('luna') >= 0 && rec.skills.indexOf('galeforce') < 0, 'repair teaches Vanity Lone Wolf and Moon Bite, not her tier-2 skill');
  ok(notes.some((n) => /Vanity learned/.test(n)), 'repair says so');
  ok(GM.repair().every((n) => !/Vanity learned/.test(n)), 'and only once');
  rec.lv = 3; rec.skills = rec.skills.filter((s) => s === 'crowswatch');
  // the twins: Chapter 7 won early still brings them to the Garden
  const fresh = GM.newGame(1, false);
  Object.keys(AD.CHAPTERS).filter((k) => /^c[1-7]$/.test(k)).forEach((k) => { fresh.done[k] = true; });
  GM.repair();
  ok(GM.record('noella') && GM.record('sierra'), 'Noella and Sierra join once Chapter 7 is won');
  Object.keys(AD.UNITS).forEach((id) => { if (AD.UNITS[id].looks) GM.addUnit(id, true); });

  // a flat test field
  const mkBattle = (units, deploy) => {
    const ch = { id: 'test', n: 0, title: 'Test', map: { rows: Array.from({ length: 10 }, () => '.'.repeat(16)), biome: 'city' }, goal: { type: 'rout' }, units, events: [] };
    const bt = new AD.Battle(ch, deploy);
    AD.curBattle = bt;
    return bt;
  };
  const by = (bt, id) => bt.units.find((u) => u.id === id || u.cls === id);

  // ---- arts in the math
  let bt = mkBattle([{ c: 'thug', x: 5, y: 3, lv: 4 }, { c: 'thug', x: 6, y: 3, lv: 4 }, { c: 'thug', x: 5, y: 4, lv: 4 }], [{ id: 'kael', x: 4, y: 3 }, { id: 'abarax', x: 2, y: 2 }]);
  const kael = by(bt, 'kael'), thug = bt.units.find((u) => u.x === 5 && u.y === 3);
  const wo = AD.equipped(kael);
  const art = AD.artFor(kael, wo);
  ok(art && art.id === 'finalcut', 'Severance offers Final Cut');
  const plain = bt.calc(kael, thug, wo, 1, 0);
  const withArt = bt.calc(kael, thug, wo, 1, 0, undefined, undefined, art);
  ok(withArt.A.crit >= Math.min(100, plain.A.crit + 40) || withArt.A.crit === 100, 'Final Cut raises crit');
  const ws = { d: AD.ITEMS.ironsword, i: 0, it: { id: 'ironsword', uses: 46 } };
  kael.items.unshift({ id: 'ironsword', uses: 46 }); kael.eq = 0;
  const wsArt = AD.artFor(kael, { d: AD.ITEMS.ironsword, i: 0 });
  ok(wsArt && wsArt.id === 'windsweep', 'iron sword offers Windsweep');
  ok(!bt.calc(kael, thug, { d: AD.ITEMS.ironsword, i: 0 }, 1, 0, undefined, undefined, wsArt).D, 'Windsweep: no counter');
  void ws;
  // paying for it
  kael.items[0].uses = 10;
  const before = kael.items[0].uses;
  const fc = bt.calc(kael, thug, { d: AD.ITEMS.ironsword, i: 0 }, 1, 0, undefined, undefined, wsArt);
  const res = bt.resolve(fc);
  const aStrikes = res.tl.filter((e) => e.who === 'a' && !e.thrift).length;
  ok(kael.items[0].uses === before - 3 - (aStrikes - 1), 'Windsweep costs 3 uses on its first strike (' + before + ' -> ' + kael.items[0].uses + ', ' + aStrikes + ' strikes)');
  ok(/^Windsweep( II| III)?$/.test(res.tl[0].art), 'first strike carries the art name (' + res.tl[0].art + ')');
  kael.items.shift(); kael.eq = 0;

  // ---- statuses
  bt = mkBattle([{ c: 'thug', x: 5, y: 3, lv: 4 }], [{ id: 'abarax', x: 2, y: 2 }]);
  const t2 = bt.units.find((u) => u.team === 'e');
  ok(bt.inflict(t2, 'root', 1) && bt.movOf(t2) === 0, 'root pins');
  ok(bt.moveTiles(t2).size === 1, 'rooted unit can only stay');
  bt.inflict(t2, 'chill', 1);
  const spd0 = t2.stats.spd;
  ok(bt.calc(t2, by(bt, 'abarax'), AD.equipped(t2), 1, 0).A.as <= spd0 - 4 + 2, 'chill slows');
  bt.inflict(t2, 'burn', 2);
  t2.hp = t2.mhp;
  bt.phase = 'e';
  await bt.phaseEffects('e');
  ok(t2.hp < t2.mhp, 'burn bites at the start of its phase');
  bt.tickStatus('e');
  ok(!t2.st.root && !t2.st.chill && t2.st.burn === 1, 'root and chill wear off after its phase, burn has a turn left: ' + JSON.stringify(t2.st));
  t2.hp = 1; await bt.phaseEffects('e');
  ok(t2.hp === 1, 'burn never kills');
  // status applied during the victim's own phase lasts through its next one too
  bt.phase = 'e'; t2.st = {}; bt.inflict(t2, 'blind', 1);
  bt.tickStatus('e'); ok(t2.st.blind === 1, 'blind applied on their own phase survives that phase');
  bt.phase = 'p';
  // ward
  const ab = by(bt, 'abarax'); ab.skills.push('ward');
  ok(!bt.inflict(ab, 'burn', 2), 'Clear Mind wards off burn');

  // ---- push and chain
  bt = mkBattle([{ c: 'thug', x: 4, y: 3, lv: 1, stats: { hp: 60 } }, { c: 'thug', x: 4, y: 4, lv: 1, stats: { hp: 60 } }], [{ id: 'abarax', x: 3, y: 3 }]);
  const ab2 = by(bt, 'abarax');
  ab2.items.unshift({ id: 'goldflame', uses: 60 }); ab2.eq = 0; ab2.stats.skl = 40; ab2.stats.mag = 30;
  const gw = AD.equipped(ab2);
  const sb = AD.artFor(ab2, gw);
  ok(sb && sb.id === 'sunburst', 'Gold Flame offers Sunburst');
  const tA = bt.units.find((u) => u.team === 'e' && u.y === 3), tB = bt.units.find((u) => u.team === 'e' && u.y === 4);
  const hpB = tB.hp;
  const r2 = bt.resolve(bt.calc(ab2, tA, gw, 1, 0, undefined, undefined, sb));
  ok(r2.after && r2.after.hits.length === 1 && tB.hp < hpB, 'Sunburst splashes the foe beside the target');
  // haymaker push
  const bn = mkBattle([{ c: 'thug', x: 4, y: 3, lv: 1, stats: { hp: 80 } }], [{ id: 'benny', x: 3, y: 3 }]);
  const benny = by(bn, 'benny'); benny.stats.skl = 40;
  const hw = AD.equipped(benny), hm = AD.artFor(benny, hw);
  const th = bn.units.find((u) => u.team === 'e');
  const r3 = bn.resolve(bn.calc(benny, th, hw, 1, 0, undefined, undefined, hm));
  ok(hm.id === 'haymaker' && r3.after && r3.after.move && r3.after.move.x === 5, 'Haymaker knocks the foe back a tile: ' + JSON.stringify(r3.after && r3.after.move && { x: r3.after.move.x, y: r3.after.move.y }));
  await bn.afterCombat(bn.calc(benny, th, hw, 1, 0, undefined, undefined, hm), r3);
  ok(th.x === 5, 'and it moves');

  // ---- new skills
  bt = mkBattle([{ c: 'thug', x: 4, y: 3, lv: 1 }], [{ id: 'abarax', x: 3, y: 3 }]);
  const a3 = by(bt, 'abarax'), e3 = bt.units.find((u) => u.team === 'e');
  e3.skills.push('vantage'); e3.hp = 2; e3.mhp = 20;
  ok(bt.calc(a3, e3, AD.equipped(a3), 1, 0).vantage, 'First Word: wounded defender goes first');
  const r4 = bt.resolve(bt.calc(a3, e3, AD.equipped(a3), 1, 0));
  ok(r4.tl[0].who === 'd', 'and its strike comes first in the exchange');
  e3.skills = ['quickriposte']; e3.hp = e3.mhp = 40;
  ok(bt.calc(a3, e3, AD.equipped(a3), 1, 0).dDouble, 'Quick Riposte doubles back');
  a3.skills.push('wrath'); a3.hp = 5;
  const cw = bt.calc(a3, e3, AD.equipped(a3), 1, 0).A.crit;
  a3.skills = a3.skills.filter((s) => s !== 'wrath');
  ok(cw >= bt.calc(a3, e3, AD.equipped(a3), 1, 0).A.crit + 20 || cw === 100, 'Hot Blood adds crit when low');

  // ---- rescue, mend, drop
  bt = mkBattle([{ c: 'thug', x: 12, y: 8, lv: 1 }], [{ id: 'noella', x: 3, y: 3 }, { id: 'benny', x: 4, y: 3 }]);
  const no = by(bt, 'noella'), be = by(bt, 'benny');
  be.hp = 5;
  ok(bt.rescuable(no).indexOf(be) >= 0, 'Noella can rescue Benny');
  AD.TEST = true;
  bt.pickTarget = async (u, list) => list[0];
  bt.pickTile = async (u, spots) => spots[0];
  const realMenu = AD.menu;
  AD.menu = async (o) => (o.items.some((i) => i.value === 'mend') ? 'mend' : null);
  const done = await bt.rescueFlow(no);
  ok(done && no.carry === 'benny' && be.carriedBy === 'noella', 'rescued');
  ok(bt.alive('p').indexOf(be) < 0 && !bt.unitAt(4, 3), 'Benny is off the map');
  ok(be.hp > 5, 'and mended straight away: ' + be.hp);
  const spdC = bt.calc(no, bt.units.find((u) => u.team === 'e'), AD.equipped(no) || { d: AD.ITEMS.ironblade || AD.ITEMS.kitknife, i: 0 }, 1, 0);
  void spdC;
  // carrier walks, cargo follows
  no.x = 6; no.y = 5; bt.update();
  ok(be.x === 6 && be.y === 5, 'cargo follows the carrier');
  // next turn the carried get their turn back
  be.done = true; await bt.beginPhase('p');
  ok(!be.done, 'carried unit is refreshed at the start of the phase');
  const dropped = await bt.dropFlow(no);
  ok(dropped && !be.carriedBy && !no.carry && bt.unitAt(be.x, be.y) === be, 'dropped beside her at ' + be.x + ',' + be.y);
  // a carrier who falls lets go
  await bt.rescueFlow(no);
  no.hp = 0; await bt.kill(no, null);
  ok(!be.carriedBy && bt.unitAt(be.x, be.y) === be, 'carrier falls, the carried is set down');
  AD.menu = realMenu;

  // ---- suspend round trip keeps statuses and carrying
  bt = mkBattle([{ c: 'thug', x: 12, y: 8, lv: 1 }], [{ id: 'sierra', x: 3, y: 3 }, { id: 'abarax', x: 4, y: 3 }]);
  const si = by(bt, 'sierra'), abx = by(bt, 'abarax');
  si.carry = 'abarax'; abx.carriedBy = 'sierra'; bt.inflict(bt.units.find((u) => u.team === 'e'), 'burn', 2);
  GM.suspend(bt);
  const d = AD.store.get('suspend');
  ok(d.units.find((u) => u.id === 'abarax').carriedBy === 'sierra' && d.units.find((u) => u.team === 'e').st.burn, 'suspend keeps carrying and statuses');
  AD.store.del('suspend');
  AD.TEST = false;
  return { pass, fail };
});
console.log('PASS ' + logic.pass.length);
logic.pass.forEach((p) => console.log('  ok  ' + p));
logic.fail.forEach((p) => console.log('  FAIL ' + p));

// ---------------------------------------------------------------- screens
await page.evaluate(() => {
  const GM = AD.game;
  GM.newGame(1, false);
  ['vanity', 'benny', 'noella', 'kael', 'reigna'].forEach((id) => GM.addUnit(id, true));
  const ch = { id: 'test', n: 0, title: 'Test', map: { rows: Array.from({ length: 10 }, () => '.'.repeat(18)), biome: 'city' }, goal: { type: 'rout' },
    units: [{ c: 'brassmask', x: 7, y: 4, lv: 6, boss: true, name: 'Brass Captain' }, { c: 'thug', x: 8, y: 4, lv: 4 }, { c: 'thug', x: 7, y: 5, lv: 4 }], events: [] };
  const bt = new AD.Battle(ch, [{ id: 'kael', x: 6, y: 4 }, { id: 'noella', x: 5, y: 4 }, { id: 'benny', x: 5, y: 5 }, { id: 'abarax', x: 4, y: 4 }]);
  bt.started = true;
  AD.stack.length = 0; AD.push(bt);
  AD.fx.floats.length = 0;
  window.__bt = bt;
  bt.inflict(bt.units.find((u) => u.cls === 'thug'), 'burn', 2);
  bt.inflict(bt.units.find((u) => u.boss), 'chill', 1);
  bt.units.find((u) => u.boss).st.root = 1;
});
await step(30);
await page.evaluate(() => { const bt = __bt; const k = bt.units.find((u) => u.id === 'kael'); bt.async(() => bt.attackFlow(k)); });
await step(4);
await step(2, 'y');
await step(6);
await shot('forecast-art');
await step(2, 'y');
await step(4);
await shot('forecast-plain');
await step(2, 'y');
await step(2, 'a');
for (const t of [3, 9, 13, 30, 54, 60]) { await page.evaluate(async (t) => { const d = AD.top(); if (d instanceof AD.Duel) while (d.pt < t && d.phase === 'vs') { AD.debugStep(1); await new Promise((r) => setTimeout(r, 0)); } }, t); await shot('vs-' + t); }
await step(20); await shot('duel-callout');
await step(70);
await shot('duel-art');
await step(900);
await shot('after');
// the HUD over a burning, rooted foe; then the skills page
await page.evaluate(() => { const bt = __bt; const b = bt.units.find((u) => u.boss && !u.dead) || bt.units.find((u) => u.team === 'e' && !u.dead); if (b) { bt.cursor.x = b.x; bt.cursor.y = b.y; } });
await step(30);
await shot('hud-status');
await page.evaluate(() => { const bt = __bt; const n = bt.units.find((u) => u.id === 'noella'); n.skills.push('warmhands', 'shelter'); bt.async(() => AD.status([n], 0)); });
await step(4); await page.evaluate(() => { AD.top().page = 2; }); await step(2);
await shot('status-skills');
await page.evaluate(() => { const t = AD.top(); t.units = [__bt.units.find((u) => u.team === 'e' && !u.dead && u.st && Object.keys(u.st).length) || __bt.units.find((u) => u.team === 'e' && !u.dead)]; t.i = 0; }); await step(2);
await shot('status-skills-foe');
// rescue on the map: Noella lifts Benny and mends him
await page.evaluate(() => { const t = AD.top(); if (t instanceof AD.Status) t.done(); });
await step(4);
await page.evaluate(() => {
  const bt = __bt; const n = bt.units.find((u) => u.id === 'noella'), b = bt.units.find((u) => u.id === 'benny');
  n.done = false; b.hp = Math.max(1, b.mhp - 15); n.x = 4; n.y = 6; b.x = 5; b.y = 6;
  bt.pickTarget = async (u, list) => list.find((o) => o === b) || list[0];
  bt.cursor.x = 4; bt.cursor.y = 6;
  bt.async(() => bt.rescueFlow(n));
});
await step(40);
await shot('rescue-menu');
await step(2, 'a');
await step(14);
await shot('rescue-mend');
await step(60);
await shot('rescue-hud');
console.log('stack', await page.evaluate(() => AD.stack.map(AD.sceneName).join('>')));
console.log('errlog', JSON.stringify(await page.evaluate(() => AD.errlog.slice(-5).map((e) => e.where + ': ' + e.msg))));
console.log('page errors', errors);
await browser.close();
