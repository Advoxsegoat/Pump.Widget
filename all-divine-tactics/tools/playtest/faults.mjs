// Injects faults into the flows that used to freeze and checks that the game recovers.
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import path from 'node:path';
const require = createRequire(path.join(execSync('npm root -g').toString().trim(), 'noop.js'));
const { chromium } = require('playwright');
const browser = await chromium.launch();
async function scenario(name, fn) {
  const page = await browser.newPage();
  await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
  await page.goto('file://' + path.resolve(process.argv[2]));
  await page.waitForFunction(() => window.AD && AD.top && AD.top() instanceof AD.Title);
  const r = await page.evaluate(fn);
  console.log(name.padEnd(28), JSON.stringify(r));
  await page.close();
}
const setup = `
  const GM = AD.game;
  for (let i = 0; i < 40; i++) AD.debugStep(1);
  GM.newGame(1, false);
  ['vanity','benny','xav','echoe','reigna'].forEach((id) => GM.addUnit(id, true));
  const run = async (n, each) => { for (let i = 0; i < n; i++) { if (each) each(i); AD.debugStep(1); await null; } };
  const skipTalk = () => { const t = AD.top(); if (t instanceof AD.Dialogue) AD.input.latch.start = true; if (t instanceof AD.Notice && t.t > 12) AD.input.latch.a = true; if (t instanceof AD.TitleCard && t.t > 32) AD.input.latch.a = true; };
`;
await scenario('AI throws in enemy phase', new Function(`return (async () => { ${setup}
  const ch = AD.chapter('c2'); GM.current = ch; GM.preBattle = AD.deep(GM.state);
  const b = new AD.Battle(ch, [{ id: 'abarax', x: 1, y: 5 }, { id: 'vanity', x: 1, y: 6 }]);
  AD.goto(b);
  await run(400, skipTalk);
  let thrown = 0; const orig = b.aiAct; b.aiAct = function (u) { if (thrown++ === 0) throw new Error('injected AI fault'); return orig.call(this, u); };
  b.alive('p').forEach((u) => { u.done = true; });
  b.async(() => b.endPlayerPhase());
  await run(2500, skipTalk);
  return { thrown, phase: b.phase, turn: b.turn, busy: b.busy, state: b.state, log: AD.errlog.map((e) => e.where + ': ' + e.msg) };
})()`));
await scenario('duel draw throws', new Function(`return (async () => { ${setup}
  const ch = AD.chapter('c2'); GM.current = ch; GM.preBattle = AD.deep(GM.state);
  const b = new AD.Battle(ch, [{ id: 'abarax', x: 1, y: 5 }]);
  AD.goto(b); await run(400, skipTalk);
  const od = AD.Duel.prototype.draw; AD.Duel.prototype.draw = function () { throw new Error('injected duel draw fault'); };
  const a = b.lord(), d = b.alive('e')[0]; a.x = d.x - 1; a.y = d.y;
  const w = AD.equipped(a);
  let done = false; b.async(async () => { await b.fight(a, d, w, 0); done = true; });
  await run(900, skipTalk);
  AD.Duel.prototype.draw = od;
  return { fightReturned: done, top: AD.sceneName(AD.top()), busy: b.busy, log: AD.errlog.map((e) => e.where + ': ' + e.msg).slice(-2) };
})()`));
await scenario('world menu throws', new Function(`return (async () => { ${setup}
  GM.state.done.c1 = true; GM.state.next = 'c2'; GM.state.node = 'bilibara';
  const ow = AD.World.prototype.nodeMenu; AD.World.prototype.nodeMenu = async function () { throw new Error('injected node menu fault'); };
  AD.goto(new AD.World()); await run(60, skipTalk);
  AD.input.latch.a = true; await run(30, skipTalk);
  const w = AD.top(); AD.World.prototype.nodeMenu = ow;
  return { top: AD.sceneName(w), busy: w.busy, log: AD.errlog.map((e) => e.where + ': ' + e.msg) };
})()`));
await scenario('chapter end throws', new Function(`return (async () => { ${setup}
  const ch = Object.assign({}, AD.chapter('c1'), { after: [['@narrate', 'x'], ['@boom']] });
  const oc = GM.command; GM.command = function (L) { if (L[0] === '@boom') throw new Error('injected after-dialogue fault'); return oc.apply(this, arguments); };
  GM.current = ch; GM.preBattle = AD.deep(GM.state);
  const b = new AD.Battle(ch, [{ id: 'abarax', x: 2, y: 4 }]);
  GM.endBattle(b, true);
  await run(900, (i) => { skipTalk(); const t = AD.top(); if (t instanceof AD.Dialogue) AD.input.latch.a = true; });
  return { top: AD.sceneName(AD.top()), log: AD.errlog.map((e) => e.where + ': ' + e.msg).slice(-2) };
})()`));
await browser.close();
