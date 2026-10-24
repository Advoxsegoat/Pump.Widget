// The screens around play (spec 8, 9.4): the title; Selenne's Garden, three screens to walk, with
// Selenne, Lucien and his Book, Midas and his unlocks, a training yard, and the tear in the wall
// that starts a run; play itself; the pause menu with the items and the map; the run's summary;
// and the Settings. Menus are the Tactics panels and font, read from AD.pad, the keys and taps,
// and nothing in them animates for longer than 8 frames.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const G = AD.gfx, C = G.C, I = AD.input;
  const W = () => AD.display.W, H = () => AD.display.H;
  const sfx = (n, o) => AD.audio && AD.audio.sfx(n, o);
  const FADE = 8;
  const pressedBack = () => I.pressed('b') || I.pressed('start');

  // ---------------------------------------------------------------- a menu
  // items: [{label, value, enabled, icon, right, help, color}]; o.onSide(dx, item, menu) for < >
  AD.Menu = function (o) {
    this.o = o;
    this.items = o.items;
    this.i = o.start || 0;
    while (this.items[this.i] && this.items[this.i].enabled === false && this.i < this.items.length - 1) this.i++;
    this.scroll = 0;
  };
  AD.Menu.prototype.layout = function () {
    const o = this.o, rowH = o.rowH || 12;
    const lw = Math.max(...this.items.map((it) => G.measure(it.label) + (it.icon ? 11 : 0) + (it.right !== undefined ? G.measure(String(it.right)) + 12 : 0)), o.title ? G.measure(o.title) : 0);
    const w = Math.min(W() - 8, Math.max(o.w || 0, lw + 24));
    const helpH = o.helpBox === false ? 0 : 30;
    const vis = Math.max(1, Math.min(this.items.length, o.max || 11, Math.floor((H() - 16 - helpH - (o.title ? 12 : 0)) / rowH)));
    const h = vis * rowH + 7 + (o.title ? 12 : 0);
    let x = o.x === undefined ? Math.round((W() - w) / 2) : o.x, y = o.y === undefined ? Math.round((H() - h - helpH) / 2) : o.y;
    x = AD.clamp(x, 2, W() - 2 - w); y = AD.clamp(y, 2, H() - 2 - h);
    return { x, y, w, h, vis, rowH, top: y + 4 + (o.title ? 12 : 0) };
  };
  AD.Menu.prototype.update = function () {
    const n = this.items.length, L = this.layout();
    const move = (k) => {
      let j = this.i;
      for (let t = 0; t < n; t++) { j = (j + k + n) % n; if (this.items[j].enabled !== false || this.o.allowDisabled) break; }
      if (j !== this.i) { this.i = j; sfx('cursor'); }
    };
    const d = I.dir();
    if (d && d[1]) move(d[1]);
    if (d && d[0] && this.o.onSide) this.o.onSide(d[0], this.items[this.i], this);
    if (this.i < this.scroll) this.scroll = this.i;
    if (this.i >= this.scroll + L.vis) this.scroll = this.i - L.vis + 1;
    const click = I.consumeClick();
    let pick = I.pressed('a');
    if (click) {
      const inside = click.x >= L.x && click.x < L.x + L.w && click.y >= L.top && click.y < L.top + L.vis * L.rowH;
      if (inside) {
        const j = this.scroll + Math.floor((click.y - L.top) / L.rowH);
        if (j < n) {
          // a tap on the right of a < value > row steps it, as left and right would
          if (this.o.onSide && this.items[j].side && j === this.i) { this.o.onSide(click.x > L.x + L.w / 2 ? 1 : -1, this.items[j], this); return; }
          this.i = j; pick = true;
        }
      } else if (this.o.cancel !== false) { sfx('cancel'); this.done(null); return; }
    }
    if (pick) {
      const it = this.items[this.i];
      if (it && it.enabled !== false) { sfx('select'); this.done(it.value === undefined ? it.label : it.value); }
      else sfx('cancel');
      return;
    }
    if (pressedBack() && this.o.cancel !== false) { sfx('cancel'); this.done(null); }
  };
  AD.Menu.prototype.draw = function (ctx) {
    const o = this.o, L = this.layout();
    G.panel(ctx, L.x, L.y, L.w, L.h, o.style);
    if (o.title) G.text(ctx, o.title, L.x + 7, L.y + 5, C.gold);
    for (let k = 0; k < L.vis; k++) {
      const j = this.scroll + k, it = this.items[j];
      if (!it) break;
      const ry = L.top + k * L.rowH;
      if (j === this.i) { ctx.fillStyle = 'rgba(232,193,112,0.16)'; ctx.fillRect(L.x + 3, ry - 2, L.w - 6, L.rowH - 1); }
      let tx = L.x + 13;
      if (it.icon) { G.icon(ctx, it.icon, tx, ry, it.enabled === false ? 0.4 : 1); tx += 11; }
      G.text(ctx, it.label, tx, ry, it.enabled === false ? C.dim : it.color || C.cream);
      if (it.right !== undefined) G.text(ctx, String(it.right), L.x + L.w - 7, ry, it.enabled === false ? C.dim : it.rightColor || C.gray, { align: 'right' });
    }
    if (this.scroll > 0) G.text(ctx, '^', L.x + L.w / 2, L.y + 1, C.gold, { align: 'center' });
    if (this.scroll + L.vis < this.items.length) G.text(ctx, 'v', L.x + L.w / 2, L.y + L.h - 8, C.gold, { align: 'center' });
    G.pointer(ctx, L.x + 3, L.top + (this.i - this.scroll) * L.rowH - 1);
    const it = this.items[this.i];
    if (it && it.help && o.helpBox !== false) {
      const lines = G.wrap(it.help, W() - 28).slice(0, 2);
      const hh = lines.length * 10 + 8;
      G.panel(ctx, 6, H() - hh - 4, W() - 12, hh);
      lines.forEach((l, k) => G.text(ctx, l, 12, H() - hh + k * 10, C.cream));
    }
  };
  AD.menu = (o) => AD.run(new AD.Menu(o));
  AD.confirm = (title, yes, no) => AD.menu({ title, items: [{ label: no || 'No', value: false }, { label: yes || 'Yes', value: true }] }).then((v) => v === true);

  // a few words in a box at the bottom, with who says them
  AD.Talk = function (who, text) { this.who = who; this.lines = G.wrap(text, W() - 28); this.t = 0; };
  AD.Talk.prototype.update = function () {
    this.t++;
    if (this.t > 6 && (I.pressed('a') || pressedBack() || I.consumeClick())) { sfx('cursor'); this.done(); }
  };
  AD.Talk.prototype.draw = function (ctx) {
    const lines = this.lines.slice(0, 4), h = lines.length * 10 + (this.who ? 20 : 10);
    const y = H() - h - 4;
    G.panel(ctx, 6, y, W() - 12, h);
    if (this.who) G.text(ctx, this.who, 12, y + 4, C.gold);
    lines.forEach((l, k) => G.text(ctx, l, 12, y + (this.who ? 15 : 5) + k * 10, C.cream));
  };
  AD.talk = (who, text) => AD.run(new AD.Talk(who, text));

  // the night sky behind the title and the summary, with the seam of light down the middle
  function sky(ctx, t, plain) {
    const g = ctx.createLinearGradient(0, 0, 0, H());
    g.addColorStop(0, '#0a0c1e'); g.addColorStop(1, '#1d1636');
    ctx.fillStyle = g; ctx.fillRect(0, 0, W(), H());
    for (let i = 0; i < 40; i++) { const x = (i * 97) % W(), y = (i * 53) % Math.round(H() * 0.6); ctx.globalAlpha = 0.3 + 0.3 * Math.sin(t / 30 + i); ctx.fillStyle = '#f6ecd4'; ctx.fillRect(x, y, 1, 1); }
    ctx.globalAlpha = 1;
    if (plain) return;
    const cx = Math.round(W() / 2);
    for (let y = 0; y < H(); y++) {
      const w = 1 + Math.round(1.5 + Math.sin(y / 9 + t / 20) * 1.2);
      ctx.globalAlpha = 0.18 + 0.12 * Math.sin(y / 5 + t / 12);
      ctx.fillStyle = '#c9b0ff'; ctx.fillRect(cx - w, y, w * 2, 1);
    }
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#ffe28a'; ctx.fillRect(cx, 0, 1, H());
  }
  const bigText = (ctx, s, y, c) => { const k = G.measure(s) * 2 <= W() - 16 ? 2 : 1; G.text(ctx, s, W() / 2, y, c, { align: 'center', scale: k }); };

  // ---------------------------------------------------------------- the title
  AD.Title = function () { this.opaque = true; this.t = 0; };
  AD.Title.prototype.enter = function () {
    if (AD.audio) AD.audio.play('title');
    const items = [];
    if (AD.save && AD.save.hasRun()) items.push({ label: 'Continue', value: 'continue' });
    items.push({ label: AD.meta && AD.meta.firstRun ? 'Begin' : 'The Garden', value: 'garden' }, { label: 'Settings', value: 'settings' });
    this.menu = new AD.Menu({ items, y: Math.round(H() * 0.62), cancel: false, helpBox: false, w: 110 });
    this.menu.done = (v) => this.pick(v);
  };
  AD.Title.prototype.pick = function (v) {
    if (v === 'continue') { const run = AD.save.loadRun(); if (run) { AD.goto(new AD.Play(run), { speed: FADE }); return; } AD.save.clearRun(); this.enter(); return; }
    if (v === 'garden') AD.goto(new AD.Garden(), { speed: FADE });
    if (v === 'settings') AD.run(new AD.Settings()).then(() => this.enter());
  };
  AD.Title.prototype.update = function () { this.t++; this.menu.update(); };
  AD.Title.prototype.draw = function (ctx) {
    sky(ctx, this.t);
    G.text(ctx, 'THE ALL-DIVINE', W() / 2, Math.round(H() * 0.12), C.rose, { align: 'center' });
    bigText(ctx, 'BETWEEN THE ROOMS', Math.round(H() * 0.12) + 12, C.gold);
    // Abarax at the seam, feet at the middle of the screen
    const T = AD.display.T, L = AD.lookFor('abarax'), f = AD.art.frames(L, 'idle', 'down', this.t), an = AD.art.anchor('abarax');
    ctx.drawImage(f, Math.round(W() / 2 - T * 1.5 + an.ox), Math.round(H() * 0.52 - T + an.oy));
    this.menu.draw(ctx);
    if (AD.meta && AD.meta.petals) { G.icon(ctx, 'rose', 6, H() - 13); G.text(ctx, AD.stat.short(AD.meta.petals), 17, H() - 13, C.cream); }
    // a run save that could not be read was set aside: say so, plainly
    if (AD.save && AD.save.problem) G.text(ctx, AD.save.problem, W() / 2, H() - 13, C.rose, { align: 'center' });
  };

  // ---------------------------------------------------------------- the Garden
  const GARDEN = [
    { n: "Selenne's Lawn", rows: ['###############', '#,,"",,G,,"",,#', '#,...........,#', '#.L....,....L.#', '#.............D', '#,..,.....,...#', '#..""....."",.#', '#.L.........L.#', '#,,..,,,,..,,,#', '###############'],
      folk: [{ id: 'selenne', x: 4, y: 4 }] },
    { n: "Lucien's Arbour", rows: ['###############', '#,,,"",,,,"",,#', '#,.P.......c.,#', '#.............#', 'D.............D', '#.L.........L.#', '#,....,,,....,#', '#.."".....""..#', '#,,,,,..,,,,,,#', '###############'],
      folk: [{ id: 'lucien', x: 3, y: 3 }, { id: 'midas', x: 11, y: 3 }] },
    { n: 'The Training Yard', rows: ['###############', '#,,"",,,,,"",,#', '#.............#', '#..L.......L..#', 'D.............#', '#.............#', '#.....f.......#', '#..L.......L..#', '#,,,,,,,,,,,,,#', '###############'],
      folk: [], dummy: { x: 9, y: 4 } },
  ];
  AD.GARDEN = GARDEN;
  const NAMES = { selenne: 'Selenne', lucien: 'Lucien', midas: 'Midas' };
  function gardenRoom(i) {
    const S = GARDEN[i];
    const room = {
      key: 'garden' + i, type: 'garden', biome: 'garden', night: false, name: S.n, grid: new AD.Grid(S.rows), bodies: new Map(), bus: new AD.Bus(),
      frame: 0, nextId: 0, rng: { combat: AD.rng.make(11 + i), loot: AD.rng.make(21 + i) }, attacks: [], projs: [], pickups: [], corpses: [], chests: {}, depth: 1,
      gateLook: { open: true }, folk: [],
    };
    for (const f of S.folk) {
      const e = AD.ent.make(room, { kind: 'npc', team: 'p', defId: f.id, look: f.id, x: f.x, y: f.y, hp: 1, speed: 0.001 });
      e.facing = [0, 1]; e.mhp = 1;
      room.folk.push(e);
    }
    if (S.dummy) {
      room.dummy = AD.ent.make(room, { kind: 'dummy', team: 'e', defId: 'dummy', look: 'dummy', x: S.dummy.x, y: S.dummy.y, hp: 1e9, speed: 0.001, immovable: true, heavy: true });
      room.dummy.mhp = 1e9;
    }
    return room;
  }
  AD.Garden = function (o) { this.opaque = true; this.t = 0; this.screen = (o && o.screen) || 0; this.at = (o && o.at) || [7, 5]; this.fadeT = FADE; this.hits = []; this.talkI = 0; };
  AD.Garden.prototype.enter = function () {
    if (AD.audio) AD.audio.play('garden');
    if (!this.rooms) this.rooms = GARDEN.map((_, i) => gardenRoom(i));
    this.go(this.screen, this.at);
  };
  AD.Garden.prototype.go = function (i, at) {
    const old = this.room;
    if (old && this.hero) { AD.ent.remove(old, this.hero); }
    this.screen = i; this.room = this.rooms[i];
    const room = this.room;
    this.hero = AD.hero.make(room, 'abarax', null, at[0], at[1]);
    this.hero.facing = [0, 1];
    room.onArrive = (e) => { if (e === this.hero) this.arrive(e); };
    AD.fx.bind({ events: room.bus, hero: this.hero });
    if (this.offHit) this.offHit();
    this.offHit = room.bus.on('hit', (p) => { if (p.tgt && p.tgt.kind === 'dummy') this.hits.push([room.frame, p.amount]); }, 90);
    this.fadeT = FADE; this.label = 90;
  };
  AD.Garden.prototype.arrive = function (h) {
    const ch = this.room.grid.at(h.x, h.y);
    if (ch !== 'D') return;
    if (h.x >= 14) this.next = [this.screen + 1, [1, 4]];
    else if (h.x <= 0) this.next = [this.screen - 1, [13, 4]];
  };
  // who or what the hero is next to and facing
  AD.Garden.prototype.nearby = function () {
    const h = this.hero, room = this.room;
    const near = (e) => Math.max(Math.abs(e.x - h.x), Math.abs(e.y - h.y)) <= 1;
    const folk = room.folk.find(near);
    if (folk) return { kind: 'folk', e: folk };
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if (room.grid.at(h.x + dx, h.y + dy) === 'G') return { kind: 'tear', x: h.x + dx, y: h.y + dy };
    return null;
  };
  AD.Garden.prototype.act = function (n) {
    if (n.kind === 'tear') { AD.run(new AD.Tear()); return; }
    const id = n.e.defId;
    n.e.facing = [Math.sign(this.hero.x - n.e.x), Math.sign(this.hero.y - n.e.y)];
    if (id === 'selenne') { const L = AD.LORE.selenne; AD.talk('Selenne', L[this.talkI++ % L.length]); }
    if (id === 'lucien') AD.talk('Lucien', AD.LORE.lucien).then(() => AD.run(new AD.Book()));
    if (id === 'midas') AD.run(new AD.Shop());
  };
  AD.Garden.prototype.update = function () {
    this.t++;
    if (this.fadeT > 0) this.fadeT--;
    if (this.label > 0) this.label--;
    const room = this.room, h = this.hero;
    const pad = Object.assign({}, AD.pad, { q: [false, false, false] });
    if (pad.start) { AD.run(new AD.Settings()); return; }
    // A beside someone (or the tear) talks instead of striking; so does a tap on them
    const n = !h.move && !h.busy ? this.nearby() : null;
    const click = I.consumeClick();
    if (n && (pad.a || (click && this.tapped(click, n)))) { pad.a = false; pad.aHeld = false; this.act(n); }
    AD.hero.control(room, h, pad);
    AD.combat.tick(room);
    for (const e of [...room.bodies.values()]) AD.ent.tick(room, e);
    for (const e of [...room.bodies.values()]) AD.status.tick(room, e);
    room.frame++;
    if (room.dummy) { room.dummy.hp = room.dummy.mhp; }
    AD.fx.tick();
    this.hits = this.hits.filter(([f]) => room.frame - f < 300);
    if (this.next) { const [i, at] = this.next; this.next = null; if (GARDEN[i]) this.go(i, at); }
  };
  AD.Garden.prototype.tapped = function (click, n) {
    const T = AD.display.T, x = n.kind === 'folk' ? n.e.x : n.x, y = n.kind === 'folk' ? n.e.y : n.y;
    return Math.floor(click.x / T) === x && Math.abs(Math.floor(click.y / T) - y) <= 1;
  };
  AD.Garden.prototype.draw = function (ctx) {
    const room = this.room, T = AD.display.T;
    AD.view.drawPlace(ctx, room, { ambient: 3 });
    // names over the folk the hero is near, and what A does
    const n = this.nearby();
    if (n) {
      const [x, y] = n.kind === 'folk' ? [n.e.x, n.e.y] : [n.x, n.y + 1];
      const label = n.kind === 'folk' ? NAMES[n.e.defId] + (n.e.defId === 'midas' ? ' - unlocks' : n.e.defId === 'lucien' ? ' - the Book' : '') : 'The tear: begin a run';
      G.text(ctx, label, (x + 0.5) * T, y * T - T * 0.75, C.gold, { align: 'center' });
      G.text(ctx, 'A', (x + 0.5) * T, y * T - T * 0.75 - 10, C.cream, { align: 'center' });
    }
    if (room.dummy && this.hits.length) {
      const dps = this.hits.reduce((s, [, a]) => s + a, 0) / 5;
      G.text(ctx, 'DPS ' + AD.stat.short(Math.round(dps)), (room.dummy.x + 0.5) * T, room.dummy.y * T - T * 0.8, C.gold, { align: 'center' });
    }
    if (this.label > 0) { ctx.globalAlpha = Math.min(1, this.label / 20); G.text(ctx, room.name, 6, 4, C.gold); ctx.globalAlpha = 1; }
    if (AD.meta) { G.icon(ctx, 'rose', W() - 40, 4); G.text(ctx, AD.stat.short(AD.meta.petals), W() - 29, 4, C.cream); }
    if (this.fadeT > 0) { ctx.globalAlpha = this.fadeT / FADE; ctx.fillStyle = '#05060c'; ctx.fillRect(0, 0, W(), H()); ctx.globalAlpha = 1; }
  };

  // ---------------------------------------------------------------- the tear: a run begins
  const DIFF = [{ n: 'Dawn', d: 1, help: 'The city notices you slowly.' }, { n: 'Dusk', d: 2, help: 'As the Seams were meant to be walked.' }, { n: 'Rose Hour', d: 3, help: 'The city knows you are here.' }];
  AD.Tear = function () { this.d = 1; this.seed = null; this.build(); };
  AD.Tear.prototype.build = function () {
    const items = [
      { label: 'Difficulty', right: '< ' + DIFF[this.d].n + ' >', value: 'diff', side: true, help: DIFF[this.d].help },
      { label: 'Seed', right: this.seed === null ? 'random' : AD.rng.seedText(this.seed), value: 'seed', help: 'The same seed makes the same floors. Pick to roll a new one.' },
      { label: 'Type a seed', value: 'type', help: 'A word and a number, as seeds read: rose-0042.' },
      { label: 'Step through', value: 'begin', color: C.gold, help: AD.LORE.tear },
    ];
    const i = this.menu ? this.menu.i : 3;
    this.menu = new AD.Menu({ title: 'The tear in the wall', items, start: i, onSide: (dx, it) => { if (it.value === 'diff') { this.d = AD.clamp(this.d + dx, 0, 2); sfx('cursor'); this.build(); } } });
    this.menu.done = (v) => this.pick(v);
  };
  AD.Tear.prototype.pick = function (v) {
    if (v === null) { this.done(); return; }
    if (v === 'diff') { this.d = (this.d + 1) % 3; this.build(); return; }
    if (v === 'seed') { this.seed = AD.rng.newSeed(); this.build(); return; }
    if (v === 'type') { askText('A seed', this.seed === null ? '' : AD.rng.seedText(this.seed), (s) => { const n = s && AD.rng.seedFromText(s); if (n !== null && n !== undefined && !isNaN(n)) this.seed = n; this.build(); }); this.build(); return; }
    if (v === 'begin') {
      const run = new AD.Run({ hero: 'abarax', difficulty: DIFF[this.d].d, seed: this.seed === null ? undefined : this.seed, meta: AD.meta });
      this.done();
      AD.goto(new AD.Play(run), { speed: FADE });
    }
  };
  AD.Tear.prototype.update = function () { this.menu.update(); };
  AD.Tear.prototype.draw = function (ctx) { this.menu.draw(ctx); };
  // a line of text from the keyboard (the phone's comes up for the hidden field)
  function askText(label, value, then) {
    if (typeof document === 'undefined') { then(null); return; }
    const el = document.createElement('input');
    el.type = 'text'; el.value = value; el.setAttribute('aria-label', label); el.autocapitalize = 'off'; el.spellcheck = false;
    Object.assign(el.style, { position: 'fixed', left: '50%', top: '30%', transform: 'translateX(-50%)', width: '220px', font: '16px monospace', padding: '8px', background: '#141a36', color: '#f6ecd4', border: '2px solid #c9a35d', zIndex: 10 });
    let finished = false;
    const end = (ok) => { if (finished) return; finished = true; const v = el.value; el.remove(); then(ok ? v.trim() : null); };
    el.addEventListener('keydown', (e) => { e.stopPropagation(); if (e.key === 'Enter') end(true); if (e.key === 'Escape') end(false); });
    el.addEventListener('blur', () => end(true));
    document.body.appendChild(el);
    el.focus(); el.select();
  }

  // ---------------------------------------------------------------- Lucien's Book
  AD.Book = function () { this.tab = 0; this.build(); };
  AD.Book.prototype.build = function () {
    const M = AD.meta;
    let items;
    if (this.tab === 0) {
      const ids = Object.keys(AD.MONSTERS).concat(Object.keys(AD.BOSSES));
      items = ids.map((id) => {
        const met = M.book.monsters.has(id), D = AD.MONSTERS[id] || AD.BOSSES[id];
        return { label: met ? D.n : '???', help: met ? AD.LORE.monster(id) : 'Not met yet.', enabled: true, color: met ? (AD.BOSSES[id] ? C.gold : C.cream) : C.dim };
      });
    } else {
      items = Object.values(AD.ITEMS).filter((it) => it.tier !== 'spent').map((it) => {
        const seen = M.book.items.has(it.id);
        return { label: seen ? it.n : '???', right: seen ? it.tier : '', help: seen ? it.desc : 'Not carried yet.', color: seen ? (AD.art.TIER_C[it.tier] || C.cream) : C.dim };
      });
    }
    const counts = this.tab === 0 ? M.book.monsters.size + '/' + (Object.keys(AD.MONSTERS).length + Object.keys(AD.BOSSES).length) : M.book.items.size + '/' + Object.values(AD.ITEMS).filter((it) => it.tier !== 'spent').length;
    this.menu = new AD.Menu({ title: (this.tab === 0 ? '< Bestiary >' : '< Items >') + '  ' + counts, items, max: 9, w: Math.min(W() - 16, 200), onSide: () => { this.tab = 1 - this.tab; sfx('cursor'); this.build(); } });
    this.menu.done = (v) => { if (v === null) this.done(); };
  };
  AD.Book.prototype.update = function () { this.menu.update(); };
  AD.Book.prototype.draw = function (ctx) { this.menu.draw(ctx); };

  // ---------------------------------------------------------------- Midas's unlocks
  AD.Shop = function () { this.build(0); };
  AD.Shop.prototype.build = function (i) {
    const M = AD.meta;
    const items = M.ORDER.map((id) => {
      const u = M.UNLOCKS[id], owned = M.owned(id), later = !!u.later;
      return { label: u.n, value: id, right: owned ? 'yours' : later ? 'later' : u.cost, rightColor: owned ? C.green : later ? C.dim : M.petals >= u.cost ? C.rose : C.dim, enabled: !owned && !later && M.petals >= u.cost, help: later ? u.later : u.desc };
    });
    items.push({ label: 'Leave', value: null });
    this.menu = new AD.Menu({ title: 'Midas   petals ' + AD.stat.short(M.petals), items, start: i, allowDisabled: true });
    this.menu.done = (v) => {
      if (v === null) { this.done(); return; }
      if (M.buy(v)) { sfx('item'); this.build(this.menu.i); } else { sfx('cantAfford'); this.build(this.menu.i); }
    };
  };
  AD.Shop.prototype.update = function () { this.menu.update(); };
  AD.Shop.prototype.draw = function (ctx) { this.menu.draw(ctx); };

  // ---------------------------------------------------------------- play
  AD.Play = function (run) { this.run = run; this.opaque = true; this.endT = 0; };
  AD.Play.prototype.enter = function () {
    if (this.bound) return;
    this.bound = true;
    const run = this.run, M = AD.meta;
    AD.view.bind(run);
    if (M) M.watch(run);
    // first-run hints, at the moment they apply
    const say = (id) => { if (M && !M.hints.has(id) && M.hint(id)) AD.hud.hint(AD.LORE.hints[id], 300); };
    run.events.on('wake', () => say('attack'), 99);
    run.events.on('enterRoom', (p) => { if (p.sealed) say('attack'); if (p.room && p.room.type === 'exit') say('gate'); }, 99);
    run.events.on('pickup', (p) => { if (p.p && p.p.kind === 'cons') say('quick'); }, 99);
    this.say = say;
    if (AD.audio) AD.audio.play(run.room.sealed ? 'fight' : run.region().id);
    // saved from the start: the run was built standing in its first room
    if (AD.save) { AD.save.watch(run); AD.save.run(run); }
  };
  AD.Play.prototype.pause = function () { AD.run(new AD.Pause(this.run)); };
  AD.Play.prototype.update = function () {
    const run = this.run;
    if (run.over) {
      AD.fx.tick();
      if (++this.endT > 50 || (this.endT > 15 && (I.pressed('a') || I.consumeClick()))) this.finish();
      return;
    }
    if (AD.paused) { AD.paused = false; this.pause(); return; }
    if (AD.pad.start) { this.pause(); return; }
    if (AD.pad.map) { AD.run(new AD.MapView(run)); return; }
    // a quickslot page that asks a choice first (Upgrade, with armour worn) asks it here
    const qi = (AD.pad.q || []).findIndex((on, i) => on && AD.cons && AD.cons.choices(run, run.quick[i]).length);
    if (qi >= 0) { AD.chooseThenUse(run, run.quick[qi]); return; }
    run.tick(AD.pad);
    AD.fx.tick();
    // the hints that are states rather than events
    const room = run.room, h = run.hero;
    if (AD.meta && room.sealed) {
      if (h.skillCd === 0 && AD.meta.hints.has('attack') && [...room.bodies.values()].some((e) => e.kind === 'monster' && !e.dead)) this.say('skill');
      if ((room.attacks || []).some((a) => a.owner && a.owner.kind !== 'hero' && a.frame <= a.def.wind && a.def.wind >= 18)) this.say('roll');
    }
  };
  AD.Play.prototype.finish = function () {
    if (this.finished) return;
    this.finished = true;
    const rec = AD.meta ? AD.meta.recordRun(this.run) : null;
    if (AD.save) AD.save.endRun(this.run);
    AD.goto(new AD.Summary(this.run, rec), { speed: FADE });
  };
  AD.Play.prototype.draw = function (ctx) {
    const run = this.run;
    AD.view.draw(ctx, run);
    AD.hud.draw(ctx, run);
    if (run.over) {
      const k = Math.min(1, this.endT / 30);
      ctx.globalAlpha = k * 0.5; ctx.fillStyle = '#05060c'; ctx.fillRect(0, 0, W(), H()); ctx.globalAlpha = k;
      bigText(ctx, run.over.won ? 'THE YARD IS QUIET' : 'FALLEN', Math.round(H() * 0.42), run.over.won ? C.gold : C.rose);
      ctx.globalAlpha = 1;
    }
  };

  // ---------------------------------------------------------------- the pause menu
  AD.Pause = function (run) { this.run = run; this.build(0); };
  AD.Pause.prototype.build = function (i) {
    const run = this.run;
    this.menu = new AD.Menu({
      title: 'Depth ' + run.depth + '  ' + AD.hud.clock(run.frames), start: i, w: 120,
      items: [
        { label: 'Resume', value: 'resume' }, { label: 'Items', value: 'items' }, { label: 'Map', value: 'map' },
        { label: 'Settings', value: 'settings' }, { label: 'Abandon the run', value: 'abandon', color: C.rose },
      ],
    });
    this.menu.done = (v) => this.pick(v);
  };
  AD.Pause.prototype.pick = function (v) {
    if (v === null || v === 'resume') { this.done(); return; }
    const i = this.menu.i;
    const back = () => this.build(i);
    if (v === 'items') AD.run(new AD.Items(this.run)).then(back);
    if (v === 'map') AD.run(new AD.MapView(this.run)).then(back);
    if (v === 'settings') AD.run(new AD.Settings()).then(back);
    if (v === 'abandon') AD.confirm('Leave this run?', 'Leave', 'Stay').then((yes) => { if (yes) { this.run.end(false, 'Walked away'); this.done(); } else back(); });
  };
  AD.Pause.prototype.update = function () { this.menu.update(); };
  AD.Pause.prototype.draw = function (ctx) {
    ctx.globalAlpha = 0.45; ctx.fillStyle = '#05060c'; ctx.fillRect(0, 0, W(), H()); ctx.globalAlpha = 1;
    // under the items, the map or the Settings, the menu steps aside
    if (AD.top() === this) this.menu.draw(ctx);
  };

  // ---------------------------------------------------------------- items: what is carried, and the bag
  // a page that asks first (Upgrade: the weapon or the armour), then is read
  const CHOICE = { weapon: 'The weapon: +10% damage', armour: 'The armour' };
  AD.chooseThenUse = function (run, id) {
    const items = AD.cons.choices(run, id).map((v) => ({ label: v === 'armour' ? CHOICE.armour + ' (' + AD.cons.armourName(run.armour) + ')' : CHOICE[v], value: v }));
    return AD.menu({ title: AD.cons.label(run, id) + ': which?', items }).then((v) => {
      if (!v) return false;
      const ok = AD.cons.useId(run, id, v);
      sfx(ok ? 'potion' : 'cancel');
      return ok;
    });
  };
  AD.Items = function (run) { this.run = run; this.i = 0; };
  AD.Items.prototype.cells = function () {
    const run = this.run, h = run.hero, out = [];
    for (const id of h.itemOrder || []) if (h.items[id] > 0) out.push({ kind: 'item', id, n: h.items[id] });
    if (h.equipment) out.push({ kind: 'item', id: h.equipment, n: 1, equip: true });
    if (run.armour) out.push({ kind: 'armour', id: run.armour.id, n: 1, piece: run.armour });
    for (const p of run.spareArmour || []) out.push({ kind: 'armour', id: p.id, n: 1, piece: p, spare: true });
    for (const [id, n] of Object.entries(run.bag || {})) if (n > 0) out.push({ kind: 'cons', id, n });
    return out;
  };
  AD.Items.prototype.update = function () {
    const cells = this.cells(), cols = AD.display.mode === 'gba' ? 7 : 10;
    const d = I.dir();
    if (d && cells.length) { this.i = AD.clamp(this.i + d[0] + d[1] * cols, 0, cells.length - 1); this.note = null; sfx('cursor'); }
    const click = I.consumeClick();
    if (click) {
      const L = this.layout(cells.length), cx = Math.floor((click.x - L.x) / L.c), cy = Math.floor((click.y - L.y) / L.c);
      const j = cy * L.cols + cx;
      if (cx >= 0 && cx < L.cols && cy >= 0 && j < cells.length) { if (j === this.i) this.use(cells[j]); else { this.i = j; sfx('cursor'); } return; }
      this.done(); return;
    }
    if (I.pressed('a') && cells[this.i]) this.use(cells[this.i]);
    if (pressedBack()) { sfx('cancel'); this.done(); }
  };
  AD.Items.prototype.use = function (c) {
    if (!AD.cons) return;
    if (c.kind === 'armour') {
      const r = AD.cons.toggleArmour(this.run, c.piece);
      if (r === 'cursed') { sfx('cancel'); this.note = 'The cursed piece will not come off.'; } else sfx('cursor');
      return;
    }
    if (c.kind !== 'cons') return;
    if (AD.cons.choices(this.run, c.id).length) { AD.chooseThenUse(this.run, c.id).then((ok) => { if (ok) this.done(); }); return; }
    if (AD.cons.useId(this.run, c.id)) { sfx('potion'); this.done(); } else sfx('cancel');
  };
  AD.Items.prototype.layout = function (n) {
    const c = AD.display.T + 4, cols = AD.display.mode === 'gba' ? 7 : 10;
    const w = cols * c, rows = Math.max(1, Math.ceil(n / cols));
    return { x: Math.round((W() - w) / 2), y: 22, c, cols, w, h: rows * c };
  };
  AD.Items.prototype.draw = function (ctx) {
    const run = this.run, cells = this.cells(), L = this.layout(cells.length);
    ctx.globalAlpha = 0.6; ctx.fillStyle = '#05060c'; ctx.fillRect(0, 0, W(), H()); ctx.globalAlpha = 1;
    G.panel(ctx, L.x - 6, L.y - 16, L.w + 12, L.h + 22);
    G.text(ctx, 'Carried', L.x, L.y - 12, C.gold);
    if (!cells.length) G.text(ctx, 'Nothing yet.', L.x, L.y + 4, C.dim);
    cells.forEach((c, j) => {
      const x = L.x + (j % L.cols) * L.c, y = L.y + Math.floor(j / L.cols) * L.c;
      const look = c.kind === 'item' ? { kind: 'item', tier: (AD.ITEMS[c.id] || {}).tier } : c.kind === 'armour' ? { kind: 'armour' } : AD.view.pickupLook(run, { kind: 'cons', id: c.id });
      if (c.spare) ctx.globalAlpha = 0.6;
      const s = AD.art.sprite('pickup', look, 0);
      ctx.fillStyle = j === this.i ? 'rgba(232,193,112,0.28)' : 'rgba(255,255,255,0.05)'; ctx.fillRect(x, y, L.c - 2, L.c - 2);
      ctx.drawImage(s.c, x + 1, y + 1);
      ctx.globalAlpha = 1;
      if (c.n > 1) G.text(ctx, AD.stat.short(c.n), x + L.c - 3, y + L.c - 11, C.cream, { align: 'right' });
    });
    const c = cells[this.i];
    if (c) {
      const name = c.kind === 'item' ? AD.ITEMS[c.id].n + (c.equip ? ' (L)' : '') : c.kind === 'armour' ? AD.cons.armourName(c.piece) + (c.spare ? ' (carried)' : '') : AD.cons.label(run, c.id);
      const desc = this.note || (c.kind === 'item' ? AD.ITEMS[c.id].desc : c.kind === 'armour' ? (c.piece.known && c.piece.curse ? AD.cons.CURSE_TEXT[c.piece.curse] + '  ' : '') + (c.spare ? 'A: wear it' : 'Worn where you can see it.  A: take it off') : AD.cons.desc(run, c.id) + '  A: use');
      const lines = G.wrap(desc, W() - 28).slice(0, 2), hh = lines.length * 10 + 18;
      G.panel(ctx, 6, H() - hh - 4, W() - 12, hh);
      G.text(ctx, name, 12, H() - hh, c.kind === 'item' ? AD.art.TIER_C[AD.ITEMS[c.id].tier] || C.cream : C.gold);
      lines.forEach((l, k) => G.text(ctx, l, 12, H() - hh + 10 + k * 10, C.cream));
    }
  };

  // ---------------------------------------------------------------- the map of this depth
  AD.MapView = function (run) { this.run = run; this.t = 0; };
  AD.MapView.prototype.update = function () { this.t++; if (this.t > 4 && (I.pressed('a') || pressedBack() || I.pressed('map') || I.consumeClick())) { sfx('cancel'); this.done(); } };
  AD.MapView.prototype.draw = function (ctx) {
    const run = this.run, F = run.floor, cw = AD.display.mode === 'gba' ? 18 : 28, ch = Math.round(cw * 0.7);
    ctx.globalAlpha = 0.7; ctx.fillStyle = '#05060c'; ctx.fillRect(0, 0, W(), H()); ctx.globalAlpha = 1;
    const ox = Math.round((W() - 9 * cw) / 2), oy = Math.round((H() - 8 * ch) / 2) + 6;
    G.text(ctx, AD.regionAt(run.depth).d.n + ' - depth ' + run.depth, W() / 2, oy - 14, C.gold, { align: 'center' });
    const known = run.knownRooms(), foes = run.foeRooms();
    for (const k of foes) known.add(k);
    const MARK = { exit: ['G', '#c9b0ff'], treasure: ['$', C.gold], rest: ['f', '#ffb347'], secret: ['?', C.violet], start: ['*', C.cream] };
    for (const k of known) {
      const R = F.rooms.get(k);
      if (!R) continue;
      const st = run.roomState.get(k).state, x = ox + R.gx * cw, y = oy + R.gy * ch, here = run.room && run.room.key === k;
      ctx.fillStyle = here ? ((this.t >> 4) % 2 ? '#ffffff' : C.gold) : st === 'unvisited' ? '#2a2e48' : st === 'entered' ? '#a84a4a' : '#5a5e7e';
      ctx.fillRect(x + 1, y + 1, cw - 2, ch - 2);
      ctx.fillStyle = '#9aa1c4';
      for (const [d, link] of Object.entries(R.doors)) if (link && link !== 'secret') {
        const [dx, dy] = AD.gen.DIRS[d];
        if (dx) ctx.fillRect(dx > 0 ? x + cw - 1 : x - 1, y + (ch >> 1) - 1, 2, 2); else ctx.fillRect(x + (cw >> 1) - 1, dy > 0 ? y + ch - 1 : y - 1, 2, 2);
      }
      // what each room is shows once it is visited, or the whole floor is revealed
      const m = (st !== 'unvisited' || run.revealed) && MARK[R.type];
      if (m) G.text(ctx, m[0], x + cw / 2, y + (ch - 9) / 2, m[1], { align: 'center' });
      if (foes.has(k) && !here) { ctx.fillStyle = '#ff4a4a'; ctx.fillRect(x + 2, y + 2, 3, 3); }
    }
  };

  // ---------------------------------------------------------------- the run's summary
  AD.Summary = function (run, rec) { this.run = run; this.rec = rec; this.opaque = true; this.t = 0; };
  AD.Summary.prototype.enter = function () { if (AD.audio) AD.audio.play(this.run.over && this.run.over.won ? 'victory' : 'gameover', { now: true }); };
  AD.Summary.prototype.update = function () {
    this.t++;
    if (this.t > 20 && (I.pressed('a') || pressedBack() || I.consumeClick())) { sfx('select'); AD.goto(new AD.Garden(), { speed: FADE }); }
  };
  AD.Summary.prototype.draw = function (ctx) {
    const run = this.run, o = run.over || {}, h = run.hero;
    sky(ctx, this.t, true);
    bigText(ctx, o.won ? 'THE FIRST KNUCKLE FALLS' : 'FALLEN AT DEPTH ' + run.depth, 14, o.won ? C.gold : C.rose);
    const rows = [
      ['Depth', run.depth], ['Time', AD.hud.clock(run.frames)], ['Kills', AD.stat.short(run.kills)],
      ['Taken by', o.won ? '-' : o.by || 'the Seams'], ['Petals', '+' + run.petals + (AD.meta ? '  (' + AD.stat.short(AD.meta.petals) + ')' : '')],
    ];
    const y0 = 40, x0 = Math.round(W() / 2 - 70);
    rows.forEach(([k, v], i) => { G.text(ctx, k, x0, y0 + i * 11, C.gray); G.text(ctx, String(v), x0 + 140, y0 + i * 11, C.cream, { align: 'right' }); });
    // the items taken, as icons
    const ids = (h && h.itemOrder) || [], c = AD.display.T, cols = Math.floor((W() - 24) / c);
    ids.forEach((id, j) => {
      const s = AD.art.sprite('pickup', { kind: 'item', tier: (AD.ITEMS[id] || {}).tier }, 0);
      ctx.drawImage(s.c, 12 + (j % cols) * c, y0 + 60 + Math.floor(j / cols) * c);
    });
    if (this.t > 20 && (this.t >> 5) % 2) G.text(ctx, 'tap to return to the Garden', W() / 2, H() - 12, C.dim, { align: 'center' });
  };

  // ---------------------------------------------------------------- Settings (spec 9.4)
  const S = () => AD.settings;
  const cycle = (list, v, dx) => list[(list.indexOf(v) + dx + list.length) % list.length];
  const SETTINGS = [
    { k: 'mode', n: 'Display', get: () => (AD.display.mode === 'gba' ? 'True GBA' : 'GBA shape HD'), side: (dx) => AD.display.set(AD.display.mode === 'gba' ? 'hd' : 'gba'), help: 'GBA shape HD looks best; True GBA (240x160) runs lightest.' },
    { k: 'effects', n: 'Bloom and lights', get: () => (S().effects ? 'on' : 'off'), side: () => { S().effects = !S().effects; } },
    { k: 'shake', n: 'Screen shake', get: () => S().shake, side: (dx) => { S().shake = cycle(['full', 'low', 'off'], S().shake, dx); } },
    { k: 'flashes', n: 'Flashes', get: () => S().flashes, side: (dx) => { S().flashes = cycle(['full', 'low'], S().flashes, dx); } },
    { k: 'numbers', n: 'Damage numbers', get: () => (S().numbers ? 'on' : 'off'), side: () => { S().numbers = !S().numbers; } },
    { k: 'ctlSize', n: 'Control size', get: () => S().ctlSize + '%', side: (dx) => { S().ctlSize = AD.clamp(S().ctlSize + dx * 10, 80, 130); } },
    { k: 'ctlAlpha', n: 'Control opacity', get: () => S().ctlAlpha + '%', side: (dx) => { S().ctlAlpha = AD.clamp(S().ctlAlpha + dx * 10, 30, 90); } },
    { k: 'leftHanded', n: 'Hand', get: () => (S().leftHanded ? 'left' : 'right'), side: () => { S().leftHanded = !S().leftHanded; } },
    { k: 'haptics', n: 'Haptics', get: () => (S().haptics ? 'on' : 'off'), side: () => { S().haptics = !S().haptics; } },
    { k: 'music', n: 'Music', get: () => S().music + '%', side: (dx) => { S().music = AD.clamp(S().music + dx * 10, 0, 100); } },
    { k: 'sfxVol', n: 'Effects', get: () => S().sfxVol + '%', side: (dx) => { S().sfxVol = AD.clamp(S().sfxVol + dx * 10, 0, 100); } },
  ];
  AD.applySettings = function () {
    const s = AD.settings;
    if (s.music === undefined) s.music = 50;
    if (s.sfxVol === undefined) s.sfxVol = 60;
    if (AD.input && AD.input.applyControls) AD.input.applyControls(s);
    if (AD.audio && AD.audio.setVolumes) AD.audio.setVolumes(s.music / 100, s.sfxVol / 100);
    if (s.mode && s.mode !== AD.display.mode) AD.display.set(s.mode);
  };
  AD.Settings = function () { AD.applySettings(); this.build(0); };
  AD.Settings.prototype.build = function (i) {
    const items = SETTINGS.map((it) => ({ label: it.n, right: '< ' + it.get() + ' >', value: it.k, side: true, help: it.help }));
    items.push({ label: 'Report a problem', value: 'report', help: 'Copies the error log, to paste into a message.' });
    items.push({ label: 'Back', value: null });
    this.menu = new AD.Menu({ title: 'Settings', items, start: i, max: 13, onSide: (dx, it) => this.change(it.value, dx) });
    this.menu.done = (v) => this.pick(v);
  };
  AD.Settings.prototype.change = function (k, dx) {
    const it = SETTINGS.find((s) => s.k === k);
    if (!it) return;
    it.side(dx);
    AD.settings.mode = AD.display.mode;
    AD.applySettings();
    sfx('cursor');
    if (AD.meta && AD.meta.onChange) AD.meta.onChange('settings');
    this.build(this.menu.i);
  };
  AD.Settings.prototype.pick = function (v) {
    if (v === null) { this.done(); return; }
    if (v === 'report') {
      const text = JSON.stringify(AD.errlog || [], null, 1);
      const ok = () => AD.talk('', AD.errlog && AD.errlog.length ? 'The error log is copied. Paste it into a message.' : 'No errors logged. Thank you for looking.');
      try { navigator.clipboard.writeText(text).then(ok, ok); } catch (e) { ok(); }
      this.build(this.menu.i);
      return;
    }
    this.change(v, 1);
  };
  AD.Settings.prototype.update = function () { this.menu.update(); };
  AD.Settings.prototype.draw = function (ctx) {
    ctx.globalAlpha = 0.6; ctx.fillStyle = '#05060c'; ctx.fillRect(0, 0, W(), H()); ctx.globalAlpha = 1;
    this.menu.draw(ctx);
  };
})(window.AD);
