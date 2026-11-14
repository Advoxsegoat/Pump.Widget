// What outlasts a run (spec 5.5, 8): rose petals, Midas's unlocks, Lucien's Book (monsters met,
// items carried), the best run, the hints already shown, and the Settings. Saved by game/save.js.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  // available: false where M1 has nothing for it yet (one region: no later depths, no stalls)
  const UNLOCKS = {
    startHealing: { n: 'A Healing draught to start', cost: 30, desc: 'Every run begins with a Draught of Healing, already known.' },
    thirdSlot: { n: 'A third quickslot', cost: 40, desc: 'Three things to hand instead of two.' },
    extraRoll: { n: 'One more roll', cost: 60, desc: '+1 roll charge.' },
    chestReroll: { n: 'A chest reroll', cost: 80, desc: 'Once a depth, A on an open chest again trades its item for another of the same kind.' },
    stalls: { n: "Midas's stalls, cheaper", cost: 60, desc: 'Everything at my stalls 10% less.', later: 'Midas has no stalls in Bilibara yet.' },
    depth6: { n: 'Start at depth 6', cost: 50, desc: 'Begin past Bilibara.', later: 'Opens when the road past Bilibara does.' },
    depth11: { n: 'Start at depth 11', cost: 80, desc: 'Begin further down.', later: 'Opens with the next region.' },
    depth16: { n: 'Start at depth 16', cost: 120, desc: 'Begin further down still.', later: 'Opens with the region after that.' },
  };
  const ORDER = Object.keys(UNLOCKS);
  const fresh = () => ({ petals: 0, unlocks: new Set(), book: { monsters: new Set(), items: new Set() }, best: { depth: 0, kills: 0, frames: 0 }, runs: 0, wins: 0, hints: new Set(), firstRun: true });

  const M = (AD.meta = Object.assign(fresh(), { UNLOCKS, ORDER }));
  M.settings = AD.settings || (AD.settings = {});
  M.reset = function () { Object.assign(M, fresh()); };

  M.owned = (id) => M.unlocks.has(id);
  M.available = (id) => !!UNLOCKS[id] && !UNLOCKS[id].later && !M.unlocks.has(id);
  M.buy = function (id) {
    const u = UNLOCKS[id];
    if (!M.available(id) || M.petals < u.cost) return false;
    M.petals -= u.cost;
    M.unlocks.add(id);
    if (M.onChange) M.onChange('buy');
    return true;
  };
  // a first-run hint: true the first time it is asked for, never again
  M.hint = function (id) {
    if (M.hints.has(id)) return false;
    M.hints.add(id);
    if (M.onChange) M.onChange('hint');
    return true;
  };

  // the Book fills as a run goes
  M.watch = function (run) {
    const on = (n, f) => run.events.on(n, f, 96);
    return [
      on('spawn', (p) => { if (p.m && p.m.defId) M.book.monsters.add(p.m.defId); }),
      on('bossSpawn', (p) => { if (p.b && p.b.defId) M.book.monsters.add(p.b.defId); }),
      on('pickup', (p) => { if (p.p && p.p.kind === 'item' && p.p.item) M.book.items.add(p.p.item); }),
    ];
  };
  // a run ended: keep its petals (spec 2.2: kept on death) and its bests, once
  M.recordRun = function (run) {
    if (run.recorded) return null;
    run.recorded = true;
    M.petals += run.petals;
    M.runs++;
    if (run.over && run.over.won) M.wins++;
    M.best.depth = Math.max(M.best.depth, run.depth);
    M.best.kills = Math.max(M.best.kills, run.kills);
    M.best.frames = Math.max(M.best.frames, run.frames);
    M.firstRun = false;
    if (M.onChange) M.onChange('run');
    return { petals: run.petals, depth: run.depth, frames: run.frames, kills: run.kills };
  };

  // for the save
  M.toJSON = function () {
    return {
      v: 1, petals: M.petals, unlocks: [...M.unlocks], book: { monsters: [...M.book.monsters], items: [...M.book.items] },
      best: M.best, runs: M.runs, wins: M.wins, hints: [...M.hints], firstRun: M.firstRun, settings: Object.assign({}, AD.settings),
    };
  };
  M.fromJSON = function (o) {
    M.reset();
    if (!o || typeof o !== 'object') return M;
    M.petals = Math.max(0, Math.floor(+o.petals || 0));
    M.unlocks = new Set((o.unlocks || []).filter((id) => UNLOCKS[id]));
    M.book = { monsters: new Set((o.book && o.book.monsters) || []), items: new Set((o.book && o.book.items) || []) };
    M.best = Object.assign(fresh().best, o.best || {});
    M.runs = +o.runs || 0; M.wins = +o.wins || 0;
    M.hints = new Set(o.hints || []);
    M.firstRun = o.firstRun !== false;
    if (o.settings && typeof o.settings === 'object') Object.assign(AD.settings, o.settings);
    M.settings = AD.settings;
    return M;
  };
})(window.AD);
