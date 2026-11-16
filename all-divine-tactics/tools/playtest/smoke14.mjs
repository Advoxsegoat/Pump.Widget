// Checks the 1.4 additions and renders sheets of them:
//   gear (equip, stats, growth, the dressed look), skill and art ranks, the stat buffs, the new
//   side quests; a contact sheet of every new weapon's duel, one of every duel backdrop, and
//   the wardrobe; then the wardrobe again through real key presses.
//   node smoke14.mjs <game.html> <outdir>
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const [game, out = 'smoke14-out'] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 800, height: 450 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
await page.goto('file://' + path.resolve(game));
await page.waitForFunction(() => window.AD && AD.top && AD.top() instanceof AD.Title);
const save = (name, b64) => fs.writeFileSync(path.join(out, name + '.png'), Buffer.from(b64, 'base64'));

const logic = await page.evaluate(async () => {
  const pass = [], fail = [];
  const ok = (cond, what) => (cond ? pass : fail).push(what);
  const GM = AD.game;
  for (let i = 0; i < 40; i++) AD.debugStep(1);
  AD.TEST = true;
  GM.newGame(1, false);
  Object.keys(AD.UNITS).forEach((id) => { if (AD.UNITS[id].looks) GM.addUnit(id, true); });
  ok(['jerkin', 'tinring', 'silkscarf'].every((id) => GM.state.convoy.some((it) => it.id === id)), 'a new game starts with a starter kit of gear');

  // gear in and out of the convoy
  const benny = GM.record('benny');
  GM.toConvoy(AD.item('steelplate')); GM.toConvoy(AD.item('chainmail'));
  GM.equip(benny, 'armor', 'steelplate');
  ok(benny.gear.armor === 'steelplate' && !GM.state.convoy.some((it) => it.id === 'steelplate'), 'equipping takes the piece out of the convoy');
  const gs = GM.gearStats(benny);
  ok(gs.def === 5 && gs.res === 1 && gs.spd === -1, 'Steel Plate: Def +5, Res +1, Spd -1 (' + JSON.stringify(gs) + ')');
  GM.equip(benny, 'armor', 'chainmail');
  ok(benny.gear.armor === 'chainmail' && GM.state.convoy.some((it) => it.id === 'steelplate'), 'swapping puts the old piece back');
  const L = AD.lookFor(benny);
  ok(L.armor && L.armor.pieces.indexOf('pauldrons') >= 0 && L.armor.chain, 'the chain hauberk shows on his look');
  GM.toConvoy(AD.item('duelistcoat')); GM.equip(benny, 'outfit', 'duelistcoat');
  ok(AD.lookFor(benny).outfit === 'longcoat' && AD.lookFor(benny).main === '#2a2430', 'an outfit changes his clothes');
  GM.toConvoy(AD.item('mooncirclet')); GM.equip(benny, 'acc', 'mooncirclet');
  ok(AD.lookFor(benny).trinket && AD.lookFor(benny).trinket.kind === 'circlet', 'a circlet shows too');
  // growing gear
  const ab = GM.record('abarax');
  GM.toConvoy(AD.item('roselocket')); GM.equip(ab, 'acc', 'roselocket');
  ab.lv = 1; const g1 = GM.gearStats(ab).hp; ab.lv = 18; const g18 = GM.gearStats(ab).hp; ab.lv = 1;
  ok(g1 === 3 && g18 === 9, 'the Rose Locket grows with its wearer (' + g1 + ' at Lv 1, ' + g18 + ' at Lv 18)');
  // a battle unit carries it all
  const bu = AD.unitFromRecord(benny);
  ok(bu.gs && bu.gs.def === 3 && bu.gs.res === 3 && bu.gs.avo === 5 && bu.look.armor, 'a battle unit takes the gear, its stats and its look (' + JSON.stringify(bu.gs) + ')');

  // ranks
  ok(AD.scaleArt(AD.ARTS.windsweep, 3).n === 'Windsweep III' && AD.scaleArt(AD.ARTS.haymaker, 2).mt === 7, 'arts scale with weapon rank');
  ok(/\+30/.test(AD.skillText('wrath', 2)) && /\+40/.test(AD.skillText('wrath', 3)), 'skill texts follow the rank');
  ok(AD.skillName('wrath', 3) === 'Hot Blood III' && AD.skillName('steal', 3) === 'Steal', 'only scaling skills show a rank');
  ok(AD.skillRank({ cls: 'cook', lv: 5 }) === 1 && AD.skillRank({ cls: 'rosedivine', lv: 5 }) === 2 && AD.skillRank({ cls: 'alldivine', lv: 1 }) === 3, 'ranks go with tier and level');

  // buffs
  ok(AD.UNITS.abarax.grow.str >= 70 && AD.UNITS.abarax.skills.indexOf('roseheart') >= 0, 'Abarax grows faster and has Rose Heart');
  ok(AD.CLASSES.alldivine.bonus.hp >= 8, 'the All-Divine promotion gives more');
  const old = { id: 'vanity', cls: 'dealer', lv: 15, stats: { hp: 30, str: 10, mag: 4, skl: 15, spd: 18, lck: 8, def: 7, res: 7 } };
  AD.retroBuff(old);
  ok(old.stats.hp >= 32 && old.stats.str >= 11, 'a save from before gets the buff as if it had grown with it (' + JSON.stringify(old.stats) + ')');

  // personal weapons grow
  const mk = (units, deploy) => { const ch = { id: 'test', n: 0, title: 'Test', map: { rows: Array.from({ length: 8 }, () => '.'.repeat(12)), biome: 'city' }, goal: { type: 'rout' }, units, events: [] }; const bt = new AD.Battle(ch, deploy); AD.curBattle = bt; return bt; };
  let bt = mk([{ c: 'thug', x: 4, y: 3, lv: 1, stats: { hp: 99, def: 0 } }], [{ id: 'abarax', x: 3, y: 3 }]);
  let a = bt.units.find((u) => u.id === 'abarax'), e = bt.units.find((u) => u.team === 'e');
  a.items.unshift({ id: 'openhand', uses: 60 }); a.eq = 0;
  const d1 = bt.calc(a, e, AD.equipped(a), 1, 0).A.dmg; a.lv = 10; const d20 = bt.calc(a, e, AD.equipped(a), 1, 0).A.dmg;
  ok(d20 - d1 === 2, 'the Open Hand gains Mt as Abarax levels (+' + (d20 - d1) + ' at Lv 10)');

  // the new arts do what they say
  bt = mk([{ c: 'thug', x: 4, y: 3, lv: 1, stats: { hp: 99 }, shield: 4 }, { c: 'thug', x: 5, y: 3, lv: 1, stats: { hp: 99 } }], [{ id: 'benny', x: 3, y: 3 }]);
  const bn = bt.units.find((u) => u.id === 'benny'), t1 = bt.units.find((u) => u.team === 'e' && u.x === 4);
  bn.items.unshift({ id: 'warhammer', uses: 35 }); bn.eq = 0; bn.stats.skl = 60; bn.wexp.fist = 300;
  const sh = AD.artFor(bn, AD.equipped(bn));
  ok(sh && sh.id === 'shatter' && sh.n === 'Shatter III', 'the War Hammer offers Shatter, at rank III for a master');
  const rs = bt.resolve(bt.calc(bn, t1, AD.equipped(bn), 1, 0, undefined, undefined, sh));
  ok(t1.broken || t1.hp <= 0 || rs.tl.every((x) => !x.hit), 'Shatter breaks the guard outright');

  // side quests
  const st = GM.state;
  ['c9', 'c15', 'c19'].forEach((k) => { st.done[k] = true; });
  ok(['s15', 's16', 's17'].every((id) => AD.sideOpen(AD.CHAPTERS[id])), 'the three new side quests open');
  ['s15', 's16', 's17'].forEach((id) => {
    const ch = AD.CHAPTERS[id];
    ch.map.rows.forEach((r) => { if (r.length !== ch.map.rows[0].length) fail.push(id + ' ragged map'); });
    ch.units.forEach((u) => { const t = AD.tiles.cost(ch.map.rows[u.y][u.x], AD.CLASSES[u.c].mt); if (t == null) fail.push(id + ' unit on a blocked tile ' + u.x + ',' + u.y); const w = (u.items || []).filter((i) => AD.ITEMS[i].weapon); if (w.length && !w.some((i) => AD.CLASSES[u.c].w.indexOf(AD.ITEMS[i].t) >= 0)) fail.push(id + ' ' + u.c + ' cannot use ' + w.join(',')); });
    ch.deploy.forEach(([x, y]) => { if (AD.tiles.cost(ch.map.rows[y][x], 'foot') == null) fail.push(id + ' deploy on a blocked tile ' + x + ',' + y); });
  });
  // every item a shop sells exists
  Object.values(AD.SHOPS).forEach((sh2) => sh2.items.forEach((id) => { if (!AD.ITEMS[id]) fail.push('shop sells unknown ' + id); }));
  AD.TEST = false;
  return { pass, fail };
});
console.log('PASS ' + logic.pass.length);
logic.pass.forEach((p) => console.log('  ok  ' + p));
logic.fail.forEach((p) => console.log('  FAIL ' + p));

// ---------------------------------------------------------------- sheets
// every new weapon, at its moment of impact, against a thug on a plain
const weaponSheet = await page.evaluate(async () => {
  const GM = AD.game;
  const ids = ['irongreat', 'silvergreat', 'rapier', 'duelrapier', 'chakram', 'moonring', 'warhammer', 'maul', 'warfan', 'cranefan', 'scythe', 'reaper', 'chainwhip', 'thornlash', 'longbow', 'yewbow', 'pistol', 'twinpistols', 'meteor', 'verdance', 'maelstrom'];
  const who = { irongreat: 'kael', silvergreat: 'kael', rapier: 'vanity', duelrapier: 'kael', chakram: 'gerace', moonring: 'vanity', warhammer: 'benny', maul: 'galt', warfan: 'benny', cranefan: 'kesra', scythe: 'aurelian', reaper: 'oren', chainwhip: 'aurelian', thornlash: 'oren', longbow: 'vehday', yewbow: 'vehday', pistol: 'xav', twinpistols: 'vehday', meteor: 'reigna', verdance: 'liora', maelstrom: 'hesper' };
  const sheet = document.createElement('canvas'); const cols = 4, cw = 400, chh = 175;
  sheet.width = cols * cw; sheet.height = Math.ceil(ids.length / cols) * chh;
  const sx = sheet.getContext('2d');
  const errs = [];
  for (let n = 0; n < ids.length; n++) {
    const id = ids[n], uid = who[id], d = AD.ITEMS[id];
    const rng = d.rng[0] > 1 ? 2 : 1;
    const ch = { id: 'w', n: 0, title: 'W', map: { rows: Array.from({ length: 6 }, () => '.'.repeat(10)), biome: 'coast' }, goal: { type: 'rout' }, units: [{ c: 'thug', x: 3 + rng, y: 2, lv: 3, stats: { hp: 99 } }], events: [] };
    const bt = new AD.Battle(ch, [{ id: uid, x: 3, y: 2 }]);
    AD.curBattle = bt;
    const u = bt.units.find((o) => o.id === uid), foe = bt.units.find((o) => o.team === 'e');
    u.items.unshift({ id, uses: 30 }); u.eq = 0; u.wexp[d.t] = 300; u.stats.skl = 30;
    const wo = { it: u.items[0], i: 0, d };
    const fc = bt.calc(u, foe, wo, rng, 0);
    AD.rng = AD.makeRng(n + 5);
    const res = bt.resolve(fc);
    res.tl.forEach((e) => { e.hit = true; e.crit = false; });
    const duel = new AD.Duel(bt, fc, res);
    duel.phase = 'strike';
    AD.stack.length = 0; AD.push(duel);
    // run until the first impact has shown, then a few frames for the effect to bloom
    let f = 0, shownAt = -1;
    while (f < 600 && duel.phase !== 'gone') {
      try { duel.update(); } catch (e) { errs.push(id + ': ' + e.message); break; }
      AD.fx.update && AD.fx.update();
      if (shownAt < 0 && res.tl[0] && res.tl[0].shown) shownAt = f;
      if (shownAt >= 0 && f - shownAt >= 3) break;
      f++;
    }
    try { duel.draw(AD.ctx); } catch (e) { errs.push(id + ' draw: ' + e.message); }
    sx.drawImage(AD.canvas, 0, 0, 400, 175, (n % cols) * cw, Math.floor(n / cols) * chh, cw, chh);
    sx.fillStyle = 'rgba(6,8,26,0.8)'; sx.fillRect((n % cols) * cw + 4, Math.floor(n / cols) * chh + 4, 140, 14);
    sx.fillStyle = '#e8c170'; sx.font = '11px monospace'; sx.fillText(d.n, (n % cols) * cw + 8, Math.floor(n / cols) * chh + 15);
  }
  return { b64: sheet.toDataURL('image/png').split(',')[1], errs };
});
save('weapons', weaponSheet.b64);
console.log('weapon sheet errors', weaponSheet.errs);

// every backdrop, day and night where it makes sense
const bgSheet = await page.evaluate(() => {
  const scenes = AD.backdrop.SCENES;
  const cols = 4, cw = 400, chh = 175;
  const sheet = document.createElement('canvas'); sheet.width = cols * cw; sheet.height = Math.ceil(scenes.length / cols) * chh;
  const sx = sheet.getContext('2d');
  const biomeOf = { street: 'city', nightstreet: 'city', meadow: 'coast', heath: 'hills', vale: 'vale', terrace: 'marble', garden: 'garden', spire: 'spire', blackfort: 'flats', tavern: 'interior', cave: 'dungeon', saltflat: 'salt', works: 'dungeon', hall: 'marble', throne: 'marble' };
  scenes.forEach((sc, n) => {
    const biome = biomeOf[sc] || 'coast';
    const map = { biome, night: sc === 'nightstreet' || sc === 'rooftop' || sc === 'bells', weather: sc === 'snow' ? 'snow' : null, at: () => '.' };
    const ctx = AD.ctx;
    ctx.save(); ctx.fillStyle = '#000'; ctx.fillRect(0, 0, 400, 225);
    AD.backdrop.draw(ctx, map, AD.tiles.BI[biome], 120, sc);
    ctx.restore();
    sx.drawImage(AD.canvas, 0, 0, 400, 175, (n % cols) * cw, Math.floor(n / cols) * chh, cw, chh);
    sx.fillStyle = 'rgba(6,8,26,0.8)'; sx.fillRect((n % cols) * cw + 4, Math.floor(n / cols) * chh + 4, 90, 14);
    sx.fillStyle = '#e8c170'; sx.font = '11px monospace'; sx.fillText(sc, (n % cols) * cw + 8, Math.floor(n / cols) * chh + 15);
  });
  return sheet.toDataURL('image/png').split(',')[1];
});
save('backdrops', bgSheet);

// the wardrobe, trying on plate
const wardrobe = await page.evaluate(async () => {
  const GM = AD.game;
  const r = GM.record('kael');
  ['steelplate', 'mooncirclet', 'travelcloak', 'divineplate'].forEach((id) => GM.toConvoy(AD.item(id)));
  GM.equip(r, 'acc', 'mooncirclet');
  const w = new AD.Wardrobe(r);
  AD.stack.length = 0; AD.push(w);
  w.mode = 'pick'; w.si = 0; w.list = w.options('armor'); w.i = w.list.findIndex((o) => o.id === 'divineplate');
  for (let i = 0; i < 6; i++) AD.debugStep(1);
  return AD.canvas.toDataURL('image/png').split(',')[1];
});
save('wardrobe', wardrobe);
// the same wardrobe through real key presses: Items -> a friend -> Gear -> Accessory, down a
// list longer than the panel, wear the tenth, and back out to the world map
const step = (n, press) => page.evaluate(async ([n, press]) => { for (let i = 0; i < Math.max(n, press ? 3 : 0); i++) { if (press && i === 0) AD.input.src.key[press] = true; if (press && i === 2) AD.input.src.key[press] = false; AD.debugStep(1); await new Promise((r) => setTimeout(r, 0)); } }, [n, press || null]);
const top = () => page.evaluate(() => { const t = AD.top(); return { menu: t instanceof AD.Menu ? t.items.map((x) => x.label) : null, i: t && t.i, si: t && t.si, wardrobe: t instanceof AD.Wardrobe, world: t instanceof AD.World, mode: t && t.mode, n: t && t.list && t.list.length, scroll: t instanceof AD.Wardrobe && t.mode === 'pick' ? t.top() : 0 }; });
await page.evaluate(() => {
  AD.stack.length = 0;
  Object.keys(AD.ITEMS).forEach((id) => { if (AD.ITEMS[id].gear === 'acc') AD.game.toConvoy(AD.item(id)); });
  AD.game.record(AD.game.party()[0].id).gear.acc = null;
  AD.goto(new AD.World());
});
await step(60);
await page.evaluate(() => { AD.itemsManager(); });
await step(20);
const keyed = [];
await step(4, 'a');
await step(6);
for (let k = 0; k < 6; k++) { const s = await top(); if (s.menu && s.menu[s.i] === 'Gear') break; await step(4, 'down'); }
await step(4, 'a'); await step(6);
keyed.push([(await top()).wardrobe, 'Gear opens the wardrobe']);
for (let k = 0; k < 4; k++) { if ((await top()).si === 2) break; await step(4, 'down'); }
await step(4, 'a'); await step(4);
const listed = await top();
keyed.push([listed.mode === 'pick' && listed.n >= 12, 'the accessory list holds every kind in the convoy (' + listed.n + ')']);
for (let k = 0; k < 9; k++) await step(4, 'down');
const scrolled = await top();
keyed.push([scrolled.i === 9 && scrolled.scroll > 0, 'the list scrolls to keep the cursor in view (top ' + scrolled.scroll + ')']);
const want = await page.evaluate(() => AD.top().list[9].id);
await step(4, 'a'); await step(4);
const worn = await page.evaluate(() => AD.game.record(AD.game.party()[0].id).gear.acc);
keyed.push([worn === want, 'A wears it (' + worn + ')']);
for (let k = 0; k < 4 && !(await top()).world; k++) { await step(4, 'b'); await step(6); }
keyed.push([(await top()).world, 'B backs out to the world map']);
keyed.forEach(([c, what]) => console.log((c ? '  ok  ' : '  FAIL ') + what));
console.log('errlog', JSON.stringify(await page.evaluate(() => AD.errlog.slice(-5).map((e) => e.where + ': ' + e.msg))));
console.log('page errors', errors.slice(0, 8));
await browser.close();
