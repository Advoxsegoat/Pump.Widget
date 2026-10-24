// Saving (spec 6.7). The run is saved each time a room is entered, as things stood the moment the
// hero came in: the seed, the depth, the clock, the random streams, the hero, the inventory, each
// room already seen (its tiles, what lies on its floor, its chests and traps) and every pickup
// taken. Loading rebuilds the floor from the seed and walks back in through the same door, so the
// run plays on exactly as it would have. Death and victory delete the run save. The Garden's data
// saves whenever it changes. Saves carry a version; an older one is migrated, an unreadable one is
// set aside with a plain message, and a full or blocked store only ever costs a one-time notice.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const V = 1;
  const S = (AD.save = { warned: false, problem: null });
  const PROBLEM = "Your last run couldn't be restored.";
  const NO_STORE = "Progress can't be saved on this device.";
  S.NO_STORE = NO_STORE;

  // a body's own state as plain data: no functions, and no references to other bodies or rooms
  function plain(v, deep) {
    if (v === null || typeof v !== 'object') return typeof v === 'function' ? undefined : v;
    if (deep > 5) return undefined;
    if (v instanceof Set) return { __set: [...v] };
    if (v instanceof Map) return undefined;
    if (Array.isArray(v)) return v.map((x) => plain(x, deep + 1));
    if (deep > 0 && v.team !== undefined && v.hp !== undefined) return undefined; // another body
    const o = {};
    for (const k of Object.keys(v)) { const x = plain(v[k], deep + 1); if (x !== undefined) o[k] = x; }
    return o;
  }
  function unplain(v) {
    if (v === null || typeof v !== 'object') return v;
    if (Array.isArray(v)) return v.map(unplain);
    if (v.__set) return new Set(v.__set);
    const o = {};
    for (const k of Object.keys(v)) o[k] = unplain(v[k]);
    return o;
  }
  // the hero's fields that belong to the room it stands in, not to the run
  const ROOM_BOUND = new Set(['id', 'x', 'y', 'fx', 'fy', 'move', 'buf', 'attacking', 'action', 'lastHitBy', 'hurtAt', 'pushLeft', 'hitstop', 'flash']);

  // ---------------------------------------------------------------- writing
  S.data = function (run) {
    const e = run.entry || { key: run.room.key, side: null, state: 'cleared', taken: [], streams: run.streamStates() };
    const hero = {};
    for (const [k, v] of Object.entries(run.hero)) if (!ROOM_BOUND.has(k)) { const x = plain(v, 1); if (x !== undefined) hero[k] = x; }
    const rooms = [];
    for (const [key, room] of run.rooms) {
      // the room being entered for the first time is rebuilt by walking in again
      if (key === e.key && e.state === 'unvisited') continue;
      rooms.push({
        key, rows: room.grid.rows(), chests: room.chests, chestDrops: room.chestDrops || {}, nextPickup: room.nextPickup,
        pickups: room.pickups.map((p) => plain(p, 1)),
        traps: room.traps ? [...room.traps.values()].map((t) => ({ x: t.x, y: t.y, kind: t.kind, seen: t.seen })) : [],
      });
    }
    const roomState = [...run.roomState].map(([k, st]) => [k, k === e.key ? { state: e.state, taken: e.taken } : { state: st.state, taken: [...st.taken] }]);
    return {
      v: V, seed: run.seed, difficulty: run.difficulty, heroId: run.heroId, depth: run.depth, frames: run.frames, cleared: run.cleared,
      coins: run.coins, keys: run.keys, petals: run.petals, kills: run.kills, rerolls: run.rerolls, mindVision: run.mindVision || 0,
      metMinis: [...run.metMinis], lore: run.lore || [], found: run.found || [],
      bag: run.bag, quick: run.quick, idTable: { potions: run.idTable.potions, scrolls: run.idTable.scrolls, known: [...run.idTable.known] },
      armour: run.armour, spareArmour: run.spareArmour,
      hero, doors: [...run.floor.rooms].map(([k, R]) => [k, R.doors]), roomState, rooms,
      entry: { key: e.key, side: e.side, streams: e.streams },
    };
  };
  S.run = function (run) {
    let ok = false;
    try { ok = AD.store.set('run', S.data(run)); } catch (err) { AD.report(err, 'save'); }
    if (!ok && !S.warned) { S.warned = true; run.events.emit('saveFailed', { text: NO_STORE }); }
    return ok;
  };
  S.watch = function (run) {
    return [
      run.events.on('enterRoom', () => S.run(run), 99),
      run.events.on('death', () => S.clearRun(), 99),
      run.events.on('victory', () => S.clearRun(), 99),
    ];
  };
  S.endRun = function () { S.clearRun(); };
  S.clearRun = function () { AD.store.del('run'); };
  S.hasRun = () => !!AD.store.raw('run');

  // ---------------------------------------------------------------- reading
  // older saves, brought up to this version; null for what this game cannot read
  S.migrate = function (d) {
    if (!d || typeof d !== 'object' || typeof d.v !== 'number' || d.v > V) return null;
    if (d.v < 1) { d.rerolls = d.rerolls || 0; d.v = 1; }
    if (d.seed === undefined || !d.depth || !d.hero || !d.entry || !d.entry.key) return null;
    return d;
  };
  function setAside(raw) {
    if (raw) AD.store.setRaw('run.bad', raw);
    AD.store.del('run');
    S.problem = PROBLEM;
    return null;
  }
  S.loadRun = function () {
    const raw = AD.store.raw('run');
    if (!raw) return null;
    let d;
    try { d = S.migrate(JSON.parse(raw)); } catch (e) { d = null; }
    if (!d) return setAside(raw);
    try { return rebuild(d); } catch (e) { AD.report(e, 'load'); return setAside(raw); }
  };
  function rebuild(d) {
    const run = new AD.Run({ hero: d.heroId || 'abarax', difficulty: d.difficulty, seed: d.seed, meta: AD.meta });
    if (d.depth !== run.depth) run.startDepth(d.depth);
    // the floor's doors as they were (unlocked ones stay open), and what each room has been
    for (const [k, doors] of d.doors || []) { const R = run.floor.rooms.get(k); if (R) Object.assign(R.doors, doors); }
    // a room left before it was cleared is met fresh (what was taken there stays taken): saved as
    // it was left, it would come back barred, with no fight in it to clear
    run.roomState = new Map((d.roomState || []).map(([k, st]) => [k, { state: st.state === 'entered' ? 'unvisited' : st.state, taken: new Set(st.taken) }]));
    for (const k of run.floor.rooms.keys()) if (!run.roomState.has(k)) run.roomState.set(k, { state: 'unvisited', taken: new Set() });
    run.rooms = new Map();
    for (const R of d.rooms || []) {
      if (!run.floor.rooms.has(R.key) || run.roomState.get(R.key).state === 'unvisited') continue;
      const room = run.liveRoom(R.key);
      R.rows.forEach((row, y) => { for (let x = 0; x < row.length; x++) if (room.grid.at(x, y) !== row[x]) room.grid.set(x, y, row[x]); });
      room.chests = R.chests || {}; room.chestDrops = R.chestDrops || {};
      room.pickups = (R.pickups || []).map(unplain);
      room.nextPickup = R.nextPickup || room.pickups.length;
      if (room.traps) { room.traps.clear(); for (const t of R.traps || []) room.traps.set(t.y * 15 + t.x, { kind: t.kind, seen: t.seen, x: t.x, y: t.y }); }
    }
    // the run and the hero
    Object.assign(run, {
      frames: d.frames, minutes: d.frames / 3600, cleared: d.cleared, coins: d.coins, keys: d.keys, petals: d.petals, kills: d.kills,
      rerolls: d.rerolls || 0, mindVision: d.mindVision || 0, metMinis: new Set(d.metMinis || []), lore: d.lore || [], found: d.found || [],
      bag: d.bag || { bomb: 0 }, quick: d.quick || [null, null], armour: d.armour || null, spareArmour: d.spareArmour || [], gate: null, banner: null,
    });
    run.idTable = { potions: d.idTable.potions, scrolls: d.idTable.scrolls, known: new Set(d.idTable.known) };
    const h = run.hero;
    Object.assign(h, unplain(d.hero));
    AD.hero.recompute(h);
    h.hp = d.hero.hp;
    // the random streams as they stood at the door, then in through it again
    run.streams.layout.restore(d.entry.streams.layout); run.streams.combat.restore(d.entry.streams.combat); run.streams.loot.restore(d.entry.streams.loot);
    if (d.entry.key === 'arena') run.enterArena();
    else run.enterRoom(d.entry.key, d.entry.side);
    return run;
  }

  // ---------------------------------------------------------------- the Garden's data
  S.meta = function () {
    if (!AD.meta) return false;
    const ok = AD.store.set('meta', AD.meta.toJSON());
    if (!ok) S.warned = true;
    return ok;
  };
  S.boot = function () {
    if (!AD.meta) return;
    const raw = AD.store.raw('meta');
    let m = null;
    try { m = raw ? JSON.parse(raw) : null; } catch (e) { AD.store.setRaw('meta.bad', raw); }
    AD.meta.fromJSON(m);
    AD.meta.onChange = () => S.meta();
  };
})(window.AD);
