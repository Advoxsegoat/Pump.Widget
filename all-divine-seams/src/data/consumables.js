// The Pixel Dungeon layer (spec §5.4): draughts from the Corvel Reliquary, pages torn from Lucien's
// Book, bombs, keys, armour and its curses. Each run hides which colour and which rune is which,
// until the thing is used or read about.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const C = (AD.cons = {});
  const cheb = (ax, ay, bx, by) => Math.max(Math.abs(ax - bx), Math.abs(ay - by));

  AD.POTIONS = {
    healing: { n: 'Draught of Healing', desc: 'Heals 60% over a second and cures burns and bleeding.' },
    haste: { n: 'Draught of Haste', desc: '+50% move and attack speed for 8 s.' },
    toughness: { n: 'Draught of Toughness', desc: '+60 armour for 8 s.' },
    fire: { n: 'Draught of Fire', desc: 'Thrown: fire on everything around where it breaks.', thrown: true },
    frost: { n: 'Draught of Frost', desc: 'Thrown: freezes foes around where it breaks for 3 s.', thrown: true },
    toxic: { n: 'Draught of Toxic Gas', desc: 'Thrown: a cloud of poison.', thrown: true },
    mindvision: { n: 'Draught of Mind Vision', desc: 'See every monster on the floor for 30 s.' },
    experience: { n: 'Draught of Experience', desc: 'Gain a level.' },
  };
  AD.SCROLLS = {
    identify: { n: 'Page of Identify', desc: 'Names your armour, or every page and draught of one kind.' },
    upgrade: { n: 'Page of Upgrade', desc: '+1 to your weapon or your armour.' },
    removecurse: { n: 'Page of Remove Curse', desc: 'Lifts the curse from your armour.' },
    mapping: { n: 'Page of Magic Mapping', desc: 'Every room on the floor, secrets too.' },
    teleport: { n: 'Page of Teleport', desc: 'Somewhere else on this floor that is safe.' },
    rage: { n: 'Page of Rage', desc: 'Everything awake here turns on its own kind for 5 s.' },
    recharging: { n: 'Page of Recharging', desc: 'Your skill, rolls and equipment, ready at once.' },
    lullaby: { n: 'Page of Lullaby', desc: 'Foes within 5 tiles fall asleep.' },
  };
  AD.ARMOUR = {
    jerkin: { n: 'Leather Jerkin', armour: 5, move: 0.05 },
    hauberk: { n: 'Chain Hauberk', armour: 12, move: 0 },
    plate: { n: 'Steel Plate', armour: 22, move: -0.06 },
  };
  const CURSES = ['heavy', 'loud', 'brittle', 'fickle'];
  C.CURSE_TEXT = { heavy: 'Heavy: -10% move speed.', loud: 'Loud: your blows carry twice as far.', brittle: 'Brittle: +10% damage taken.', fickle: 'Fickle: every roll costs 1 HP.' };
  const COLOURS = ['Amber', 'Crimson', 'Jade', 'Indigo', 'Golden', 'Silver', 'Charcoal', 'Rose', 'Turquoise', 'Ivory', 'Magenta', 'Azure'];
  const RUNES = ['KAUNAN', 'SOWILO', 'LAGUZ', 'YNGVI', 'GYFU', 'RAIDO', 'ISAZ', 'MANNAZ', 'NAUDIZ', 'BERKANAN', 'ODAL', 'TIWAZ'];
  const isPotion = (id) => !!AD.POTIONS[id];
  const isScroll = (id) => !!AD.SCROLLS[id];

  C.init = function (run) {
    const r = AD.rng.make(AD.rng.hash(run.seed + ':identities'));
    const pc = AD.rng.shuffle(r, COLOURS), rc = AD.rng.shuffle(r, RUNES);
    run.idTable = { potions: {}, scrolls: {}, known: new Set() };
    Object.keys(AD.POTIONS).forEach((id, i) => { run.idTable.potions[id] = pc[i]; });
    Object.keys(AD.SCROLLS).forEach((id, i) => { run.idTable.scrolls[id] = rc[i]; });
    run.bag = { bomb: 1 };
    run.quick = ['bomb', null];
    run.armour = null;
    run.spareArmour = [];
    Object.defineProperty(run, 'bombs', { get() { return this.bag.bomb || 0; }, set(v) { this.bag.bomb = v; }, configurable: true });
  };

  C.known = (run, id) => run.idTable.known.has(id);
  C.label = function (run, id) {
    if (id === 'bomb') return 'Bomb';
    if (isPotion(id)) return C.known(run, id) ? AD.POTIONS[id].n : run.idTable.potions[id] + ' draught';
    if (isScroll(id)) return C.known(run, id) ? AD.SCROLLS[id].n : 'A page marked ' + run.idTable.scrolls[id];
    return id;
  };
  C.desc = (run, id) => (id === 'bomb' ? 'Set it down ahead: 90 frames, then 300% all round.' : C.known(run, id) ? (AD.POTIONS[id] || AD.SCROLLS[id]).desc : 'Unknown. Use it to find out.');
  C.identify = function (run, id) { if (!run.idTable.known.has(id)) { run.idTable.known.add(id); run.events.emit('identified', { id }); } };

  C.count = (run, id) => run.bag[id] || 0;
  C.give = function (run, id, n) {
    run.bag[id] = (run.bag[id] || 0) + (n || 1);
    if (run.quick.indexOf(id) < 0) { const free = run.quick.indexOf(null); if (free >= 0) run.quick[free] = id; }
  };
  C.slotOf = (run, id) => run.quick.indexOf(id);

  // ---------------------------------------------------------------- using one
  function ahead(run, n) {
    const h = run.hero, g = run.room.grid;
    let x = h.x, y = h.y;
    for (let k = 1; k <= n; k++) {
      const nx = h.x + h.facing[0] * k, ny = h.y + h.facing[1] * k;
      if (!g.passable(nx, ny, 'fly') || AD.tileInfo(g.at(nx, ny)).wall) break;
      x = nx; y = ny;
    }
    return [x, y];
  }
  const square = (x, y) => AD.combat.tiles({ k: 'square', r: 1 }, x, y, [0, 1]);

  // from a quickslot, or (useId) straight from the bag, as the pause menu does
  C.use = (run, slot, choice) => C.useId(run, run.quick[slot], choice);
  C.useId = function (run, id, choice) {
    if (!id || !C.count(run, id) || run.hero.dead) return false;
    const room = run.room, h = run.hero;
    let ok = true;
    switch (id) {
      case 'bomb': {
        const [x, y] = [h.x + h.facing[0], h.y + h.facing[1]];
        if (!room.grid.passable(x, y, 'walk')) { ok = false; break; }
        const tiles = square(x, y).filter((p) => room.grid.inside(p[0], p[1]));
        AD.combat.attack(room, h, {
          tiles, wind: 90, act: 2, rec: 0, pct: 3, proc: 1, type: 'boom', persist: true, noBusy: true, friendly: true, shield: 1, bomb: true, at: [x, y], sfx: 'boom',
          onStrike: (r) => { AD.world.blast(r, tiles, h); AD.ai.noise(r, x, y, 6); },
        });
        break;
      }
      case 'healing':
        (h.hots || (h.hots = [])).push({ left: 60, per: (0.6 * h.mhp) / 60, acc: 0 });
        AD.status.clear(h, 'burn'); AD.status.clear(h, 'bleed');
        break;
      case 'haste': AD.status.apply(h, 'swift', { dur: 480 }); break;
      case 'toughness': AD.status.apply(h, 'tough', { dur: 480 }); break;
      case 'fire': { const [x, y] = ahead(run, 3); for (const [tx, ty] of square(x, y)) { AD.world.flame(room, tx, ty, 150); AD.world.ignite(room, tx, ty); } break; }
      case 'frost': {
        const [x, y] = ahead(run, 3), on = new Set(square(x, y).map((p) => p + ''));
        AD.world.douse(room, square(x, y));
        for (const e of room.bodies.values()) if (e.team !== h.team && !e.dead && on.has([e.x, e.y] + '')) AD.status.apply(e, 'stun', { dur: 180 });
        break;
      }
      case 'toxic': { const [x, y] = ahead(run, 3); AD.world.addGas(room, x, y, 'poison', 600); break; }
      case 'mindvision': run.mindVision = 1800; break;
      case 'experience': if (AD.hero.gainXp(h, AD.stat.xpToNext(h.level) - h.xp)) room.bus.emit('levelUp', { h, level: h.level }); break;
      case 'identify': {
        if (run.armour && !run.armour.known) { run.armour.known = true; run.events.emit('identified', { id: 'armour' }); break; }
        const unknown = Object.keys(run.bag).find((k) => (isPotion(k) || isScroll(k)) && run.bag[k] > 0 && !C.known(run, k) && k !== 'identify');
        if (unknown) C.identify(run, unknown);
        break;
      }
      case 'upgrade':
        if (choice === 'armour' && run.armour) { run.armour.level = Math.max(0, run.armour.level) + 1; C.apply(run); }
        else { h.weaponLevel = (h.weaponLevel || 0) + 1; h.dmgMul = 1 + 0.1 * h.weaponLevel; AD.hero.recompute(h); }
        break;
      case 'removecurse': if (run.armour) { run.armour.cursed = false; run.armour.curse = null; C.apply(run); } break;
      case 'mapping': run.revealed = 'all'; break;
      case 'teleport': {
        // a sealed fight and the arena hold the hero: the page is read, and nothing moves
        if (room.sealed || room.key === 'arena') { room.bus.emit('notice', { text: 'The Seams hold you here.' }); break; }
        const safe = [...run.roomState.entries()].filter(([k, s]) => s.state === 'cleared' && k !== room.key).map(([k]) => k);
        if (safe.length) run.enterRoom(AD.rng.pick(run.streams.loot, safe), null); else ok = false;
        break;
      }
      case 'rage':
        for (const e of room.bodies.values()) if (e.kind === 'monster' && !e.dead && e.state !== 'asleep') { e.rage = 300; e.team = 'rage' + e.id; }
        break;
      case 'recharging': h.skillCd = 0; h.rolls = h.rollMax; h.rollTimer = 0; h.eqCd = 0; break;
      case 'lullaby':
        for (const e of room.bodies.values()) if (e.kind === 'monster' && !e.dead && cheb(e.x, e.y, h.x, h.y) <= 5) e.state = 'asleep';
        break;
      default: ok = false;
    }
    if (!ok) return false;
    run.bag[id]--;
    if (!run.bag[id] && id !== 'bomb') { delete run.bag[id]; const s = run.quick.indexOf(id); if (s >= 0) run.quick[s] = null; }
    if (isPotion(id) || isScroll(id)) C.identify(run, id);
    room.bus.emit('consume', { id, label: C.label(run, id) });
    return true;
  };

  // ---------------------------------------------------------------- armour
  C.makeArmour = function (run, id, o) {
    o = o || {};
    const r = run.streams.loot;
    const cursed = o.cursed !== undefined ? o.cursed : r() < 0.2;
    return {
      id, cursed,
      curse: cursed ? o.curse || AD.rng.pick(r, CURSES) : null,
      level: o.level !== undefined ? o.level : cursed ? -AD.rng.int(r, 1, 3) : 0,
      known: o.known !== undefined ? o.known : false,
    };
  };
  C.armourName = (p) => AD.ARMOUR[p.id].n + (p.known ? (p.level ? (p.level > 0 ? ' +' : ' ') + p.level : '') : '');
  C.apply = function (run) {
    const h = run.hero, p = run.armour;
    const A = p ? AD.ARMOUR[p.id] : null;
    h.armourGear = A ? A.armour + 3 * p.level : 0;
    h.moveGear = A ? (1 + A.move) * (p.curse === 'heavy' ? 0.9 : 1) : 1;
    h.curse = p && p.curse || null;
    h.armourLook = p ? p.id : null;
    AD.hero.recompute(h);
  };
  C.wear = function (run, p) {
    if (run.armour && run.armour.cursed) return false;
    if (run.armour) run.spareArmour.push(run.armour);
    run.spareArmour = run.spareArmour.filter((q) => q !== p);
    run.armour = p;
    C.apply(run);
    run.events.emit('wear', { p });
    return true;
  };
  C.unwear = function (run) {
    if (!run.armour) return true;
    if (run.armour.cursed) return false;
    run.spareArmour.push(run.armour);
    run.armour = null;
    C.apply(run);
    return true;
  };

  // ---------------------------------------------------------------- finding them
  C.randomDrop = function (run, r) {
    const kind = AD.rng.weighted(r, [{ w: 45, v: 'potion' }, { w: 40, v: 'scroll' }, { w: 10, v: 'bomb' }, { w: 5, v: 'armour' }]);
    if (kind === 'potion') return { kind: 'cons', id: AD.rng.pick(r, Object.keys(AD.POTIONS)) };
    if (kind === 'scroll') return { kind: 'cons', id: AD.rng.pick(r, Object.keys(AD.SCROLLS)) };
    if (kind === 'bomb') return { kind: 'cons', id: 'bomb' };
    return { kind: 'armour', piece: C.makeArmour(run, AD.rng.pick(r, Object.keys(AD.ARMOUR))) };
  };
  C.collect = function (run, room, h, p) {
    if (p.kind === 'cons') {
      if (p.id === 'bomb' && C.count(run, 'bomb') >= 9) return false;
      C.give(run, p.id, 1);
      run.banner = { text: C.label(run, p.id), sub: C.desc(run, p.id), t: 90, cons: p.id };
      return true;
    }
    if (p.kind === 'armour') {
      if (!run.armour) C.wear(run, p.piece); else if (run.spareArmour.length < 2) run.spareArmour.push(p.piece); else return false;
      run.banner = { text: C.armourName(p.piece), sub: p.piece.known && p.piece.cursed ? C.CURSE_TEXT[p.piece.curse] : 'Armour, worn where you can see it.', t: 90, armour: p.piece.id };
      return true;
    }
    return false;
  };

  // the quickslot buttons
  C.tick = function (run, pad) {
    if (pad && pad.q) for (let i = 0; i < run.quick.length; i++) if (pad.q[i]) C.use(run, i);
    if (run.mindVision > 0) run.mindVision--;
  };
  // armour worn through a depth names itself; brittle armour lets more through
  C.install = function (run) {
    run.events.on('depthStart', () => { if (run.armour && !run.armour.known) { run.armour.known = true; run.events.emit('identified', { id: 'armour' }); } });
  };
})(window.AD);
