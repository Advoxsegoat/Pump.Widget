// Plays All-Divine Tactics through its real input path, one simulated frame at a time.
// Injected into the page; the rAF loop is disabled so the bot owns time.
(function () {
  const BOT = (window.BOT = { log: [], errors: [], frames: 0, battles: 0, combats: 0, commands: 0, done: false });
  const note = (s) => { BOT.log.push('[' + BOT.frames + '] ' + s); if (BOT.log.length > 400) BOT.log.shift(); };
  window.addEventListener('error', (e) => BOT.errors.push('error: ' + (e.error && e.error.stack || e.message)));
  window.addEventListener('unhandledrejection', (e) => BOT.errors.push('unhandledrejection: ' + (e.reason && e.reason.stack || e.reason)));
  const ce = console.error.bind(console);
  console.error = (...a) => { BOT.errors.push('console.error: ' + a.map((x) => (x && x.stack) || String(x)).join(' ')); ce(...a); };

  const name = (s) => { if (!s) return '-'; for (const k of Object.keys(AD)) if (AD[k] === s.constructor) return k; return s.constructor.name || 'anon'; };
  BOT.stackNames = () => AD.stack.map(name);
  const press = (b) => { AD.input.latch[b] = true; };
  let rs = 12345;
  BOT.seed = (n) => { rs = n >>> 0 || 1; };
  const rnd = () => { rs ^= rs << 13; rs >>>= 0; rs ^= rs >> 17; rs ^= rs << 5; rs >>>= 0; return rs / 4294967296; };
  const chance = (p) => BOT.fuzz && rnd() < p;
  const touch = () => BOT.input === 'touch';
  const tap = (x, y) => { AD.debugClick(Math.round(x), Math.round(y)); AD.input.lastDevice = 'touch'; };
  const tapTile = (bt, x, y) => {
    const sx = x * 16 + 8 - bt.cam.x, sy = y * 16 + 8 - bt.cam.y;
    if (sx < 2 || sy < 2 || sx > AD.W - 2 || sy > AD.H - 2) return false;
    tap(sx, sy); return true;
  };
  let wait = 0; // frames before the next decision

  function battle() { return AD.curBattle; }

  function chooseMenu(m) {
    const bt = battle();
    const labels = m.items.map((it) => it.label);
    const pickLabel = (...want) => { for (const w of want) { const j = labels.findIndex((l) => typeof l === 'string' && l.indexOf(w) === 0); if (j >= 0 && m.items[j].enabled !== false) return j; } return -1; };
    let j = -1;
    const enabled = m.items.map((it, k) => (it.enabled === false ? -1 : k)).filter((k) => k >= 0);
    if (bt && bt.state === 'action' && AD.stack.indexOf(bt) >= 0 && labels.indexOf('Wait') >= 0) {
      if (BOT.fuzz) {
        if (chance(0.06) && m.o.cancel !== false) { note('action menu ' + JSON.stringify(labels) + ' -> CANCEL'); press('b'); return; }
        const pool = [];
        enabled.forEach((k) => { const w = labels[k] === 'Wait' ? 1 : labels[k] === 'Attack' ? 4 : 2; for (let q = 0; q < w; q++) pool.push(k); });
        j = pool[Math.floor(rnd() * pool.length)];
      } else j = pickLabel(BOT.prefer || 'Attack', 'Attack', 'Seize', 'Escape', 'Visit', 'Chest', 'Talk', 'Song', 'Wait');
      BOT.commands++;
      note('action menu ' + JSON.stringify(labels) + ' -> ' + labels[j]);
    } else if (labels.indexOf('Fight!') >= 0) j = 0;
    else if (labels.indexOf('End Turn') >= 0 && BOT.fuzz && chance(0.3)) j = Math.floor(rnd() * labels.length);
    else if (BOT.fuzz && labels.indexOf('Yes') < 0 && labels.indexOf('New Game') < 0 && labels.indexOf('End Turn') < 0) {
      if (chance(0.15) && m.o.cancel !== false) { note('menu ' + JSON.stringify(labels.slice(0, 6)) + ' -> CANCEL'); press('b'); return; }
      j = enabled.length ? enabled[Math.floor(rnd() * enabled.length)] : 0;
      note('menu ' + JSON.stringify(labels.slice(0, 6)) + ' -> ' + labels[j]);
    }
    else if (labels.indexOf('End Turn') >= 0) j = 0;
    else if (labels.indexOf('Yes') >= 0) j = labels.indexOf('Yes');
    else if (labels.indexOf('New Game') >= 0) j = labels.indexOf('New Game');
    else j = 0;
    if (j < 0) j = 0;
    if (touch() && j >= m.scroll && j < m.scroll + m.vis) {
      const top = m.y + 3 + (m.o.title ? 12 : 0);
      tap(m.x + m.w / 2, top + (j - m.scroll) * m.rowH + m.rowH / 2);
      return;
    }
    m.i = j;
    press('a');
  }

  function playBattle(bt) {
    if (bt.busy && BOT.fuzz && chance(0.05)) { if (touch()) tap(rnd() * AD.W, rnd() * AD.H); else press(['a', 'b', 'x', 'start'][Math.floor(rnd() * 4)]); return; }
    if (bt.busy || bt.over || bt.phase !== 'p' || bt.banner) return;
    if (bt.state === 'map') {
      const ready = bt.alive('p').filter((u) => !u.done);
      if (!ready.length) return;
      const u = BOT.fuzz ? ready[Math.floor(rnd() * ready.length)] : ready[0];
      if (touch() && tapTile(bt, u.x, u.y)) return;
      bt.cursor.x = u.x; bt.cursor.y = u.y;
      press('a');
      return;
    }
    if (bt.state === 'move') {
      const u = bt.sel;
      // attack from the best spot if anything is in reach, else walk toward the nearest foe
      const foes = bt.alive('e').filter((e) => bt.visible(e.x, e.y));
      let dest = null;
      for (const f of foes) { const k = f.x + ',' + f.y; if (bt.atk.has(k) || [...bt.moves.values()].some((v) => Math.abs(v.x - f.x) + Math.abs(v.y - f.y) === 1)) { const s = bt.bestSpotToHit(u, f); if (s) { dest = s; break; } } }
      if (!dest) {
        // terrain-aware: the same distance field the enemy AI walks by
        const goal = bt.goal.type === 'seize' && u.lord ? [{ x: bt.goal.x, y: bt.goal.y }] : foes;
        const field = goal.length ? bt.distField(u, goal) : null;
        let best = null;
        bt.moves.forEach((v) => {
          const d = field ? field.get(v.x + ',' + v.y) : 0;
          if (d === undefined) return;
          if (!best || d < best.d) best = { v, d };
        });
        dest = best ? best.v : { x: u.x, y: u.y };
      }
      if (touch() && BOT.fuzz && chance(0.6)) {
        const inReach = foes.filter((f) => bt.atk.has(f.x + ',' + f.y));
        if (inReach.length) { const f = inReach[Math.floor(rnd() * inReach.length)]; if (tapTile(bt, f.x, f.y)) { BOT.commands++; note('tap-attack ' + f.id); return; } }
      }
      if (BOT.fuzz && chance(0.08)) { press('x'); return; }
      if (BOT.fuzz && chance(0.25)) { const all = [...bt.moves.values()]; dest = all[Math.floor(rnd() * all.length)]; }
      if (BOT.fuzz && chance(0.04)) { press('b'); return; }
      if (touch() && tapTile(bt, dest.x, dest.y)) return;
      bt.cursor.x = dest.x; bt.cursor.y = dest.y;
      bt.path = bt.pathTo(bt.moves, dest.x, dest.y);
      press('a');
    }
  }

  function decide() {
    const top = AD.top();
    const n = name(top);
    switch (n) {
      case 'Title': if (BOT.ch) return 20; press('a'); return 20;
      case 'Menu': chooseMenu(top); return 6;
      case 'Notice': if (top.t > 12) { if (touch()) tap(160, 90); else press('a'); } return 4;
      case 'Dialogue': if (touch() && BOT.readDialogue) tap(160, 90); else press(BOT.readDialogue ? 'a' : 'start'); return 4;
      case 'TitleCard': if (top.t > 32) { if (touch()) tap(160, 90); else press('a'); } return 4;
      case 'Blank': return 4;
      case 'Prep': return 4;
      case 'Battle':
        if (BOT.tough && !top.__toughened) {
          top.__toughened = true;
          top.units.filter((u) => u.team === 'p').forEach((u) => { u.stats.def += 25; u.stats.res += 25; u.stats.str += 8; u.stats.mag += 8; u.stats.spd += 4; u.stats.skl += 10; u.mhp = u.hp = Math.max(u.mhp, 60); });
        }
        playBattle(top); return 6;
      case 'Duel': return 4;
      case 'World': case 'Town': case 'Ending':
        if (BOT.onWorld) BOT.onWorld(n); return 30;
      case 'GameOver': BOT.gameOver = (BOT.gameOver || 0) + 1; note('GAME OVER'); if (BOT.onGameOver) BOT.onGameOver(); return 30;
      default:
        // Forecast, Picker, LevelUp, TradeScene, Status...
        if (n === 'LevelUp' && top.t < 112) return 4;
        if (n === 'Status') { press('b'); return 6; }
        if (n === 'TradeScene') { if (BOT.fuzz && chance(0.5)) { press(rnd() < 0.5 ? 'down' : 'right'); return 4; } if (BOT.fuzz && chance(0.3)) { press('a'); return 4; } press('b'); return 6; }
        if (BOT.fuzz && chance(0.12)) { press('b'); return 6; }
        if (BOT.fuzz && chance(0.25)) { press(['left', 'right', 'up', 'down', 'l', 'r', 'x', 'y'][Math.floor(rnd() * 8)]); return 4; }
        if (touch() && n === 'Forecast') { tap(160, 170); return 6; }
        if (touch() && n === 'Picker') { const p = top.list[top.i]; if (!tapTile(top.bt, p.x, p.y)) press('a'); else if (!BOT.tapTwice) { BOT.tapTwice = true; return 2; } BOT.tapTwice = false; return 6; }
        if (touch() && n === 'LevelUp') { tap(160, 90); return 6; }
        press('a'); return 6;
    }
  }

  // progress watchdog: something observable must change within the window
  let lastSig = '', lastChange = 0;
  function signature() {
    const bt = battle();
    const s = [BOT.stackNames().join('>')];
    if (bt) s.push(bt.phase, bt.turn, bt.state, bt.busy, bt.units.map((u) => u.x + ':' + u.y + ':' + u.hp + ':' + (u.done ? 1 : 0) + ':' + (u.dead ? 1 : 0)).join('|'));
    const top = AD.top();
    if (top && top.k !== undefined) s.push('k' + top.k + ':' + (top.pt | 0) + ':' + (top.t | 0));
    if (top && top.t !== undefined) s.push('t' + Math.floor(top.t / 60));
    return s.join(' ');
  }

  BOT.run = async function (maxFrames, stuckFrames) {
    stuckFrames = stuckFrames || 2400;
    const end = BOT.frames + maxFrames;
    while (BOT.frames < end && !BOT.done) {
      if (--wait <= 0) wait = decide();
      try { AD.debugStep(1); } catch (e) { BOT.errors.push('THROWN in step/render: ' + (e.stack || e)); BOT.stuck = 'exception'; return BOT.report(); }
      BOT.frames++;
      for (let i = 0; i < 6; i++) await null;
      const sig = signature();
      if (sig !== lastSig) { lastSig = sig; lastChange = BOT.frames; }
      if (BOT.frames - lastChange > stuckFrames) { BOT.stuck = 'no progress for ' + stuckFrames + ' frames'; return BOT.report(); }
      if (BOT.frames % 30 === 0) await new Promise((r) => setTimeout(r, 0));
    }
    return BOT.report();
  };

  BOT.report = function () {
    const bt = battle();
    return {
      frames: BOT.frames, stuck: BOT.stuck || null, errors: BOT.errors.slice(0, 20), commands: BOT.commands,
      stack: BOT.stackNames(), sig: signature(),
      battle: bt && { ch: bt.ch.id, turn: bt.turn, phase: bt.phase, state: bt.state, busy: bt.busy, over: bt.over, sel: bt.sel && bt.sel.id,
        units: bt.units.filter((u) => !u.dead && !u.gone).map((u) => u.id + '@' + u.x + ',' + u.y + ' hp' + u.hp + (u.done ? ' done' : '')) },
      log: BOT.log.slice(-40),
    };
  };
})();
