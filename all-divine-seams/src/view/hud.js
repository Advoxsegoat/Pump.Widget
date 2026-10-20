// The HUD (spec §9.2): HP, level and experience top left; coins, keys, bombs, the clock, the band,
// the minimap and the quickslots top right; the boss bar along the bottom; the pickup banner and the
// hint line. Every place is computed from the display mode by HUD.layout, which the phone controls
// also read to find the quickslots. Numbers on it go through stat.short, so nothing outgrows its box.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const HUD = (AD.hud = {});
  const G = () => AD.gfx;

  HUD.coinsText = (n) => AD.stat.short(Math.floor(n));
  HUD.clock = function (frames) {
    const s = Math.floor(frames / 60);
    return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
  };

  // ---------------------------------------------------------------- where everything goes
  HUD.layout = function (mode) {
    const hd = mode !== 'gba', W = hd ? 360 : 240, H = hd ? 240 : 160, m = 3;
    const hpW = hd ? 84 : 60, cs = hd ? 4 : 3, cw = hd ? 32 : 28, qs = hd ? 16 : 12;
    const mm = { x: W - m - 9 * cs, y: m, w: 9 * cs, h: 8 * cs };
    const level = { x: m + hpW + 4, y: m, w: 26, h: 9 };
    const bw = hd ? 220 : 180;
    return {
      hp: { x: m, y: m, w: hpW, h: 9 },
      xp: { x: m, y: m + 10, w: hpW, h: 2 },
      rolls: { x: m, y: m + 14, w: 24, h: 3 },
      level,
      gift: { x: level.x + level.w + 2, y: m, w: 9, h: 9 },
      minimap: mm,
      bombs: { x: mm.x - 4 - cw, y: m, w: cw, h: 9 },
      keys: { x: mm.x - 4 - 2 * cw, y: m, w: cw, h: 9 },
      coins: { x: mm.x - 4 - 3 * cw - (hd ? 6 : 2), y: m, w: cw + (hd ? 6 : 2), h: 9 },
      clock: { x: mm.x - 4 - 26, y: m + 11, w: 26, h: 9 },
      band: { x: mm.x - 4 - 26 - 4 - 64, y: m + 11, w: 64, h: 9 },
      quick0: { x: mm.x, y: mm.y + mm.h + 3, w: qs, h: qs },
      quick1: { x: mm.x + qs + 3, y: mm.y + mm.h + 3, w: qs, h: qs },
      bossName: { x: Math.round(W * 0.2), y: H - 22, w: Math.round(W * 0.6), h: 9 },
      boss: { x: Math.round(W * 0.2), y: H - 11, w: Math.round(W * 0.6), h: 6 },
      banner: { x: (W - bw) / 2, y: hd ? 44 : 34, w: bw, h: 28 },
      depth: { x: m, y: H - 24, w: hd ? 160 : 130, h: 20 },
      hint: { x: m, y: H - 36, w: W - 2 * m, h: 9 },
      notice: { x: m, y: H - 48, w: W - 2 * m, h: 9 },
    };
  };

  // ---------------------------------------------------------------- the slow-device suggestion
  // if the first 300 frames of play average over 20 ms in HD, suggest True GBA, once
  HUD.slowCheck = function () {
    let n = 0, sum = 0, done = false;
    return {
      sample(ms, mode) {
        if (done || mode === 'gba') return false;
        n++; sum += ms;
        if (n < 300) return false;
        done = true;
        return sum / n > 20;
      },
    };
  };

  // ---------------------------------------------------------------- state the HUD keeps itself
  let slow = HUD.slowCheck();
  const S = { hpShown: 1, bossT: 0, bossShown: 1, depth: null, notice: null, hint: null, offs: null };
  HUD.state = S;
  HUD.bind = function (run) {
    if (S.offs) S.offs.forEach((f) => f());
    S.hpShown = 1; S.bossT = 0; S.bossShown = 1; S.depth = null;
    S.offs = [
      run.events.on('depthStart', (p) => { const d = AD.regionAt(p.depth).d; S.depth = { text: d.n, sub: d.sub, t: 90 }; }, 96),
    ];
  };
  // a line of help the menus can set for a first run
  HUD.hint = function (text, frames) { S.hint = text ? { text, t: frames || 360 } : null; };

  const TIER = { common: '#f4eee0', uncommon: '#6ad06a', legendary: '#ef5f6a', boss: '#e8c170', equipment: '#ffb347' };
  const BAND_C = ['#c8d0e0', '#e8e0a0', '#ffc870', '#ff9a5a', '#ff6a5a', '#e8607e', '#c9a0ff'];
  let icons = false;
  function defIcons(G) {
    if (icons) return;
    icons = true;
    G.defIcon('coin', ['..ggg...', '.gwwgg..', 'gwgggcg.', 'gwgggcg.', 'gggggcg.', 'ggggccg.', '.gcccg..', '..ggg...']);
    G.defIcon('bomb', ['.....rg.', '....g...', '..ccc...', '.cccccc.', 'ccwcccc.', 'cwccccc.', 'cccccc..', '.cccc...']);
    G.defIcon('clock', ['..cccc..', '.c.ww.c.', 'c..w...c', 'c..ww..c', 'c......c', '.c....c.', '..cccc..', '........']);
    G.defIcon('potion', ['...cc...', '...ww...', '..cwwc..', '.cbbbbc.', 'cbwbbbbc', 'cbbbbbbc', '.cbbbbc.', '..cccc..']);
    G.defIcon('page', ['.wwwwww.', '.wcccw..', '.wwwwww.', '.wccccw.', '.wwwwww.', '.wcccw..', '.wwwwww.', '........']);
  }

  // ---------------------------------------------------------------- drawing
  // the quickslots take taps while the HUD is on screen
  HUD.quickTappable = () => S.drawnAt != null && AD.frame - S.drawnAt <= 2;
  HUD.draw = function (ctx, run) {
    const g = G(), mode = AD.display.mode, L = HUD.layout(mode), W = AD.display.W;
    S.drawnAt = AD.frame;
    defIcons(g);
    const h = run.hero;
    if (!h) return;
    // HP, with the chunk just lost still showing as it falls away
    const frac = Math.max(0, h.hp / h.mhp);
    if (S.hpShown < frac) S.hpShown = frac; else S.hpShown = Math.max(frac, S.hpShown - 0.008);
    const hc = frac > 0.5 ? '#5ad06a' : frac > 0.25 ? '#e8c040' : '#e8343a';
    ctx.fillStyle = '#06081a'; ctx.fillRect(L.hp.x - 1, L.hp.y - 1, L.hp.w + 2, L.hp.h + 2);
    ctx.fillStyle = '#2a1420'; ctx.fillRect(L.hp.x, L.hp.y, L.hp.w, L.hp.h);
    ctx.fillStyle = '#f4eee0'; ctx.fillRect(L.hp.x, L.hp.y, Math.round(L.hp.w * S.hpShown), L.hp.h);
    ctx.fillStyle = hc; ctx.fillRect(L.hp.x, L.hp.y, Math.round(L.hp.w * frac), L.hp.h);
    ctx.globalAlpha = 0.3; ctx.fillStyle = '#ffffff'; ctx.fillRect(L.hp.x, L.hp.y, Math.round(L.hp.w * frac), 1); ctx.globalAlpha = 1;
    g.text(ctx, AD.stat.short(Math.ceil(h.hp)) + '/' + AD.stat.short(h.mhp), L.hp.x + L.hp.w / 2, L.hp.y, '#ffffff', { align: 'center' });
    g.bar(ctx, L.xp.x, L.xp.y, L.xp.w, L.xp.h, h.xp / AD.stat.xpToNext(h.level), '#7ac8ff', '#14203a');
    for (let i = 0; i < h.rollMax; i++) { ctx.fillStyle = i < h.rolls ? '#e8e0d0' : '#3a3a4a'; ctx.fillRect(L.rolls.x + i * 5, L.rolls.y, 4, 2); }
    g.text(ctx, 'Lv' + h.level, L.level.x, L.level.y, '#ffd84a');
    // the next gift, filling as its cooldown runs out
    const next = AD.hero.nextGift(h), cd = AD.HEROES[h.heroId].gifts.cd * (h.cdMul || 1);
    g.icon(ctx, next, L.gift.x, L.gift.y, h.skillCd > 0 ? 0.35 : 1);
    if (h.skillCd > 0) { ctx.fillStyle = '#ffd84a'; ctx.fillRect(L.gift.x, L.gift.y + L.gift.h, Math.round(L.gift.w * (1 - h.skillCd / cd)), 1); }
    // coins, keys, bombs
    const count = (r, icon, n) => { g.icon(ctx, icon, r.x, r.y); g.text(ctx, HUD.coinsText(n), r.x + 10, r.y, '#f4eee0'); };
    count(L.coins, 'coin', run.coins); count(L.keys, 'key', run.keys); count(L.bombs, 'bomb', run.bombs || 0);
    g.text(ctx, HUD.clock(run.frames), L.clock.x + L.clock.w, L.clock.y, '#f4eee0', { align: 'right' });
    const band = AD.stat.band(run.minutes, run.difficulty);
    g.text(ctx, AD.stat.BANDS[band], L.band.x + L.band.w, L.band.y, BAND_C[band], { align: 'right' });
    minimap(ctx, run, L.minimap);
    quick(ctx, run, L.quick0, 0); quick(ctx, run, L.quick1, 1);
    boss(ctx, run, L);
    if (run.banner) banner(ctx, run.banner, L.banner);
    if (S.depth) {
      S.depth.t--;
      ctx.globalAlpha = Math.min(1, S.depth.t / 15);
      g.text(ctx, S.depth.text, L.depth.x, L.depth.y, '#ffd84a');
      if (mode !== 'gba') g.text(ctx, S.depth.sub, L.depth.x, L.depth.y + 10, '#c8c0b0');
      ctx.globalAlpha = 1;
      if (S.depth.t <= 0) S.depth = null;
    }
    if (S.hint) { S.hint.t--; ctx.globalAlpha = Math.min(1, S.hint.t / 30); g.text(ctx, S.hint.text, W / 2, L.hint.y, '#e8e0d0', { align: 'center' }); ctx.globalAlpha = 1; if (S.hint.t <= 0) S.hint = null; }
    const ms = AD.frameMs && AD.frameMs.length ? AD.frameMs[AD.frameMs.length - 1] : 0;
    if (ms && slow.sample(ms, mode)) S.notice = { text: 'Running slow? Try True GBA in Settings.', t: 360 };
    if (S.notice) { S.notice.t--; ctx.globalAlpha = Math.min(1, S.notice.t / 30); g.text(ctx, S.notice.text, W / 2, L.notice.y, '#ffc870', { align: 'center' }); ctx.globalAlpha = 1; if (S.notice.t <= 0) S.notice = null; }
  };
  HUD.resetSlowCheck = () => { slow = HUD.slowCheck(); };

  // known rooms of this floor: the ones visited, and the ones seen through their doors
  function minimap(ctx, run, r) {
    const F = run.floor, cs = r.w / 9;
    ctx.globalAlpha = 0.55; ctx.fillStyle = '#06081a'; ctx.fillRect(r.x - 1, r.y - 1, r.w + 2, r.h + 2); ctx.globalAlpha = 1;
    const known = new Set();
    for (const [k, st] of run.roomState) if (st.state !== 'unvisited') {
      known.add(k);
      const R = F.rooms.get(k);
      // a secret wall gives nothing away until it is opened (then the room behind is visited)
      for (const [d, link] of Object.entries(R.doors)) if (link && link !== 'secret') { const [dx, dy] = AD.gen.DIRS[d]; known.add((R.gx + dx) + ',' + (R.gy + dy)); }
    }
    const here = run.room && run.room.key;
    for (const k of known) {
      const R = F.rooms.get(k);
      if (!R) continue;
      const st = run.roomState.get(k).state, x = r.x + R.gx * cs, y = r.y + R.gy * cs;
      ctx.fillStyle = k === here ? ((run.frames >> 4) % 2 ? '#ffffff' : '#ffd84a') : st === 'unvisited' ? '#2a2e48' : st === 'entered' ? '#a84a4a' : '#6a6e8e';
      ctx.fillRect(x, y, cs - 1, cs - 1);
      if (st !== 'unvisited' && R.type === 'exit') { ctx.fillStyle = '#c9b0ff'; ctx.fillRect(x + ((cs - 1) >> 1), y + ((cs - 1) >> 1), 1, 1); }
    }
  }
  function quick(ctx, run, r, i) {
    const g = G(), id = run.quick && run.quick[i];
    ctx.fillStyle = '#06081a'; ctx.fillRect(r.x - 1, r.y - 1, r.w + 2, r.h + 2);
    ctx.fillStyle = id ? '#1a2150' : '#10142a'; ctx.fillRect(r.x, r.y, r.w, r.h);
    if (!id) return;
    const icon = id === 'bomb' ? 'bomb' : AD.SCROLLS && AD.SCROLLS[id] ? 'page' : 'potion';
    g.icon(ctx, icon, r.x + (r.w - 9) / 2, r.y + 1);
    const n = AD.cons ? AD.cons.count(run, id) : 0;
    if (n > 1 || id === 'bomb') g.text(ctx, AD.stat.short(n), r.x + r.w, r.y + r.h - 8, '#f4eee0', { align: 'right' });
  }
  // the boss bar slides up from the bottom while the fight runs
  function boss(ctx, run, L) {
    const b = run.bossBody && !run.bossBody.dead ? run.bossBody : run.gate && run.gate.guardian && !run.gate.guardian.dead && run.gate.guardian.kind === 'boss' ? run.gate.guardian : null;
    if (!b || (run.room && !run.room.bodies.has(b.id))) { S.bossT = 0; S.bossShown = 1; return; }
    const g = G();
    S.bossT = Math.min(20, S.bossT + 1);
    const k = S.bossT / 20, dy = Math.round((1 - k * k * (3 - 2 * k)) * 26);
    const frac = Math.max(0, b.hp / b.mhp);
    if (S.bossShown < frac) S.bossShown = frac; else S.bossShown = Math.max(frac, S.bossShown - 0.004);
    const r = L.boss, n = L.bossName;
    const name = (AD.BOSSES[b.defId] && AD.BOSSES[b.defId].n) || b.defId;
    g.text(ctx, name, n.x, n.y + dy, '#ffd84a');
    for (let i = 0; i < (b.pipsMax || 0); i++) g.icon(ctx, i < b.pips ? 'shield' : 'broken', n.x + n.w - (i + 1) * 10, n.y + dy, i < b.pips ? 1 : 0.5);
    ctx.fillStyle = '#06081a'; ctx.fillRect(r.x - 1, r.y - 1 + dy, r.w + 2, r.h + 2);
    ctx.fillStyle = '#2a1420'; ctx.fillRect(r.x, r.y + dy, r.w, r.h);
    ctx.fillStyle = '#f4eee0'; ctx.fillRect(r.x, r.y + dy, Math.round(r.w * S.bossShown), r.h);
    ctx.fillStyle = b.stagger > 0 ? ((run.frames >> 2) % 2 ? '#ffd84a' : '#e8343a') : '#c8283a'; ctx.fillRect(r.x, r.y + dy, Math.round(r.w * frac), r.h);
    // the phase marks at two thirds and one third
    ctx.fillStyle = '#06081a';
    for (const p of [2 / 3, 1 / 3]) ctx.fillRect(r.x + Math.round(r.w * p), r.y + dy, 1, r.h);
  }
  function banner(ctx, b, r) {
    const g = G();
    const a = Math.min(1, b.t / 12);
    ctx.globalAlpha = a;
    g.panel(ctx, r.x, r.y, r.w, r.h, 'ink', 0.9);
    g.text(ctx, b.text, r.x + r.w / 2, r.y + 4, b.tier ? TIER[b.tier] || '#f4eee0' : '#ffd84a', { align: 'center' });
    const line = g.wrap(b.sub || '', r.w - 10)[0] || '';
    g.text(ctx, line, r.x + r.w / 2, r.y + 15, '#c8c0b0', { align: 'center' });
    ctx.globalAlpha = 1;
  }
})(window.AD);
