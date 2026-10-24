# Between the Rooms — M1 Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable, phone-first M1 of *The All-Divine: Between the Rooms*: Abarax in Bilibara,
depths 1–5, ending at First Knuckle. It ships as one offline HTML page (the artifact) and an
Android APK.

**Architecture:** A new `all-divine-seams/` project. Sources live in `src/` as plain-script
modules on one global `AD`, and `tools/build.mjs` joins them into `web/index.html`, in the same way
Tactics is built. The simulation (`sim/`, `gen/`, `game/run`) is deterministic and has no DOM
dependency, so Node unit-tests it through a `vm` loader. Drawing (`art/`, `view/`, `ui/`) reads the
simulation and is checked in Chromium with Playwright: contact sheets, smoke runs, a bot sweep, and
phone layouts.

**Tech Stack:** Plain ES2020 browser JavaScript, Canvas 2D, WebAudio. Node 22 (`node --test`).
Playwright with the preinstalled Chromium. Android WebView shell (Java) built by the existing
offline Maven Central toolchain.

**Spec:** `docs/superpowers/specs/2026-10-19-between-the-rooms-design.md` (sections are cited as
§n below).

## Global Constraints

- Simulation runs at a fixed 60 Hz step. Nothing in play stops for an intro, an attack cut-in or a
  boss cutscene (§3).
- Rooms are 15×10 tiles in both display modes. Game logic is in tiles and fractions of a tile and
  never reads the screen size (§9.1).
- Display modes: `hd` = 360×240 canvas, 24 px tiles, 24×32 figures, bloom, light pools, full
  particles. `gba` = 240×160 canvas, 16 px tiles, 16×21 figures, light pools without blur, half the
  particles. `hd` is the default (§9.1).
- Phone buttons: A 48 CSS px; B and R 44; L 40; Start 32. Half transparent; hit areas 1.5× the
  drawn size; size 80–130%; opacity 30–90%; left-handed layout; haptics (§9.3).
- Android application ID `com.advoxsegoat.alldivineseams`, app name *Between the Rooms*. It
  installs next to Tactics (§10.1).
- One offline HTML file with no network requests. The same file is the artifact and the APK's
  `assets/index.html`.
- The simulation is deterministic. All of its randomness comes from seeded streams (`layout`,
  `combat`, `loot`). `Math.random` may only be used by drawing and sound (§10.3).
- Performance: 60 fps on a mid-range phone. Simulation ≤ 3 ms a frame with 40 monsters; drawing
  ≤ 8 ms in `hd` (§10.3).
- Storage keys are prefixed `seams.`, so Tactics' `alldivine.` data is never touched.
- No model identifiers in code, commits or the PR. Commit trailers per the session's attribution
  rules.

## Review Focus

1. **App sent to the background mid-fight** (Android pause, a tab switch). The clock and the
   simulation must stop, held buttons and the stick must be released, and on return the game is
   paused rather than running into a fight. Pinned in Task 18 (`input releases on blur and
   visibility change`) and Task 12 (`clock does not advance while paused`).
2. **A thumb that slides off the stick or button and is cancelled** (`pointercancel`, a finger
   leaving the screen edge). Movement must not stick on. Pinned in Task 18 (`pointercancel
   releases the stick`).
3. **Quitting or crashing mid-room, then resuming.** The room must be restored at its entry with
   nothing duplicated: pickups already taken stay taken, coins aren't doubled, and a half-charged
   gate restarts. Pinned in Task 20 (`resume does not duplicate pickups or coins`).
4. **Storage unavailable or full** (private mode, quota). The game must run, show a single
   one-line notice, and never throw. Pinned in Task 20 (`saving without storage notices once and
   keeps playing`).
5. **A very late clock** (an hour or more at Rose Hour). Spawn budgets grow without limit, but at
   most 40 monsters may be alive in a room, and HUD numbers shorten to `12.3k`. Pinned in Task 9
   (`never more than 40 alive`) and Task 16 (`big numbers shorten`).

---

## File structure

    all-divine-seams/
      src/order.txt            module order for the build
      src/head.html            page shell: <title>, style, #app, #stage, canvas, #controls
      src/tail.html            closing tags
      src/engine/core.js       loop, scenes, storage, error log, rescue, display size (from Tactics core)
      src/engine/input.js      keys, gamepad, touch stick + buttons -> virtual pad
      src/engine/gfx.js        font, panels, bars, icons, flash/shake, lighting (from Tactics gfx)
      src/engine/audio.js      synth (from Tactics), M1 sound table, region + fight tracks
      src/art/raster.js        Ras raster (from Tactics sprites.js)
      src/art/figures.js       paper-doll figures (from Tactics) + top-down attack frames
      src/art/monsters.js      goblins, wyvern whelp, rat
      src/art/tiles.js         dungeon tile painter (Tactics tile painter + new tiles)
      src/art/downscale.js     3:2 reducer for gba mode
      src/art/atlas.js         per-mode frame and tile caches
      src/data/looks.js        looks: Abarax, the book's enemies, the Garden folk
      src/data/heroes.js       Abarax
      src/data/items.js        M1 items and equipment
      src/data/consumables.js  potions, scrolls, armour, curses
      src/data/monsters.js     Bilibara roster, mini-bosses, First Knuckle
      src/data/regions.js      Bilibara: depth names, spawn weights, palette, music
      src/data/templates.js    Bilibara room templates
      src/data/lore.js         lore pages and hints
      src/sim/rng.js           seeded streams, seed text
      src/sim/events.js        event bus
      src/sim/stats.js         formulas
      src/sim/grid.js          tiles, occupancy, sight, distance maps
      src/sim/entity.js        bodies, glide, push
      src/sim/combat.js        damage records, shapes, telegraphs
      src/sim/status.js        statuses
      src/sim/items.js         item behaviours
      src/sim/hero.js          hero control and kit
      src/sim/ai.js            monster brains
      src/sim/boss.js          mini-boss and boss pattern runner
      src/sim/director.js      spawner, waves, elites
      src/sim/world.js         gas, fire, water, traps, destructibles, pits, bombs
      src/sim/room.js          room runtime: seal/clear, doors, pickups
      src/gen/floor.js         room grid, special rooms, locks and keys, validation
      src/gen/room.js          templates -> room rows, dressing
      src/game/run.js          run state, depth flow, gate, transitions
      src/game/save.js         run and meta saves, schema versions
      src/game/meta.js         petals, unlocks
      src/view/render.js       room layers, bodies, telegraphs, lighting
      src/view/fx.js           numbers, sparks, trails, hit-stop, shake
      src/view/hud.js          HP, XP, coins, keys, bombs, clock, minimap, quickslots, boss bar
      src/ui/menus.js          title, Garden, pause, inventory, map, settings, summary, hints
      src/main.js              boot
    all-divine-seams/tests/    node:test files and load.mjs
    all-divine-seams/tools/build.mjs, build-apk-offline.sh, SignApk.java, render-icons.mjs
    all-divine-seams/tools/playtest/  smoke.mjs, sheets.mjs, bot.js, sweep.mjs, mobile.mjs, perf.mjs
    all-divine-seams/web/index.html
    all-divine-seams/android/  (the Tactics shell, renamed)
    all-divine-seams/README.md
    .github/workflows/all-divine-seams-apk.yml

---

### Task 1: Project scaffold, build, test loader, boot

**Files:**
- Create: `all-divine-seams/src/{order.txt,head.html,tail.html,main.js}`, `src/engine/{core.js,gfx.js}`, `src/art/raster.js`
- Create: `all-divine-seams/tools/build.mjs`, `tests/load.mjs`, `tests/build.test.mjs`, `tools/playtest/smoke.mjs`

**Interfaces:**
- Produces: `node tools/build.mjs` → writes `web/index.html` (head + `// ---- src/<path>` + module + … + tail) and prints the byte count. `node tools/build.mjs --page out.html` writes the artifact page: the build with everything up to `<body>\n` and from `\n</body></html>` stripped.
- Produces: `tests/load.mjs` `load(files: string[]): AD`. It evaluates each `src/` file in a fresh `vm` context where `window` is the context, and returns `window.AD`.
- Produces: `AD.display = { mode, W, H, T }` and `AD.display.set(mode: 'hd'|'gba')`, which resizes the canvas and fires `AD.display.onChange` listeners. `AD.store.get/set/del` with the `seams.` prefix. `AD.push/pop/run/goto/top`, `AD.boot(start)`, `AD.debugStep(n)`, `AD.report(e, where)`, `AD.errlog`, `AD.rescue(scene, why)` (falls back to `AD.Garden`, then `AD.Title`).
- Consumes: Tactics `core.js`, `gfx.js`, and `sprites.js` (Ras only) from `all-divine-tactics/web/index.html` (cut out by their `// ---- js/` markers).

- [ ] **Step 1: Write the failing tests** — `tests/build.test.mjs`:

```js
test('build joins modules in order and the page boots in node', () => {
  execFileSync('node', ['tools/build.mjs'], { cwd: ROOT });
  const html = fs.readFileSync(path.join(ROOT, 'web/index.html'), 'utf8');
  const order = fs.readFileSync(path.join(ROOT, 'src/order.txt'), 'utf8').split(/\s+/).filter(Boolean);
  let at = -1;
  for (const f of order) { const i = html.indexOf('// ---- src/' + f + '\n'); assert.ok(i > at, f); at = i; }
  assert.ok(html.startsWith('<!doctype html>')) && assert.ok(html.trimEnd().endsWith('</html>'));
});
test('display modes', () => {
  const AD = load(['engine/core.js']);
  assert.deepEqual([AD.display.W, AD.display.H, AD.display.T], [360, 240, 24]);
  AD.display.set('gba');
  assert.deepEqual([AD.display.W, AD.display.H, AD.display.T, AD.display.mode], [240, 160, 16, 'gba']);
});
```

- [ ] **Step 2: Run them and confirm they fail.** `cd all-divine-seams && node --test tests/` → FAIL (`tools/build.mjs` missing).
- [ ] **Step 3: Implement.**
  - Copy core, gfx and the Ras raster out of Tactics.
  - Strip from core every reference to battles and `GM`, and the `fast` button.
  - Make `W`/`H` come from `AD.display`, and make `AD.display.set` resize `AD.canvas` when there is one (it must be a no-op without a DOM).
  - Change the storage prefix to `seams.`.
  - `head.html`: `<title>Between the Rooms</title>`, the `viewport-fit-sides` meta, a single dark theme (`color-scheme: dark`), `#app > #stage > canvas#screen` plus an empty `#controls`.
  - `main.js`: boots to a placeholder `AD.Title` that draws the name.
- [ ] **Step 4: Run them and confirm they pass.** `node --test tests/` → PASS.
- [ ] **Step 5: Browser smoke.**
  - `tools/playtest/smoke.mjs <html>` loads the page with `requestAnimationFrame` stubbed, steps 30 frames, and checks the canvas is 360×240, then 240×160 after `AD.display.set('gba')`. It also checks there are no page errors.
  - Run `node tools/playtest/smoke.mjs web/index.html` → prints `smoke ok`.
- [ ] **Step 6: Commit** — `git add all-divine-seams && git commit -m "Between the Rooms: scaffold, build and boot"`

### Task 2: Seeded randomness, event bus, formulas

**Files:**
- Create: `src/sim/{rng.js,events.js,stats.js}`, `tests/stats.test.mjs`

**Interfaces:**
- Produces:
  - `AD.rng.make(seed:uint32) → () → [0,1)` (mulberry32)
  - `AD.rng.streams(runSeed, depth) → {layout, combat, loot}`, three independent generators seeded by `hash(runSeed, depth, name)`
  - `AD.rng.int(r, lo, hi)` (inclusive), `AD.rng.pick(r, arr)`, `AD.rng.weighted(r, [{w, v}]) → v`
  - `AD.rng.seedText(uint32) → 'WORD-1234'`, `AD.rng.seedFromText(str) → uint32`
- Produces: `new AD.Bus()`, `.on(name, fn, order = 50) → off()`, `.emit(name, payload) → payload`. Handlers run by ascending `order`, then by registration. A handler that throws is reported, and the other handlers still run.
- Produces `AD.stat`:
  - `linear(base, per, n)`, `hyperbolic(k, n)`, `diminish(m, n)`
  - `coefficient(d, minutes, cleared)`, `enemyLevel(coef)`, `scaleHp(base, lvl)`, `scaleDmg(base, lvl)`
  - `mitigate(amount, armour)`, `chestCost(base, coef)`, `coinsFor(cost, coef)`
  - `xpFor(cost)`, `xpToNext(level)`
  - `band(minutes, d) → 0..6`, `BANDS = ['Calm','Restless','Hunted','Haunted','Unbound','Between','It has noticed']`
  - `short(n) → '950' | '12.3k' | '4.1m'`

- [ ] **Step 1: Write the failing tests** (spec §2.3, §4.1, §5.1, §5.2):

```js
const S = AD.stat;
assert.equal(S.linear(25, 25, 3), 75);
assert.equal(+S.hyperbolic(0.15, 1).toFixed(4), 0.1304);
assert.equal(+S.hyperbolic(0.15, 10).toFixed(4), 0.6);
assert.equal(+S.diminish(0.9, 2).toFixed(2), 0.81);
assert.equal(+S.coefficient(2, 10, 0).toFixed(3), 2.012);           // (1 + 0.0506*2*10)
assert.equal(+S.coefficient(2, 10, 2).toFixed(3), 2.661);           // × 1.15^2
assert.equal(S.enemyLevel(1), 1); assert.equal(S.enemyLevel(2.012), 4);
assert.equal(S.scaleHp(60, 4), 114); assert.equal(S.scaleDmg(10, 4), 16);
assert.equal(S.mitigate(100, 100), 50); assert.equal(+S.mitigate(100, -50).toFixed(2), 133.33);
assert.equal(S.chestCost(25, 1), 25); assert.equal(S.chestCost(25, 2), 59);
assert.equal(S.coinsFor(8, 1), 4); assert.equal(S.coinsFor(8, 2), 6);
assert.equal(S.xpFor(8), 4); assert.equal(S.xpToNext(1), 20); assert.equal(Math.round(S.xpToNext(3)), 48);
assert.equal(S.band(0, 2), 0); assert.equal(S.band(5, 2), 1); assert.equal(S.band(60, 2), 6);
assert.equal(S.short(950), '950'); assert.equal(S.short(12345), '12.3k');
// rng
const a = AD.rng.streams(42, 1), b = AD.rng.streams(42, 1);
assert.equal(a.layout(), b.layout()); assert.notEqual(AD.rng.streams(42, 1).layout(), AD.rng.streams(42, 2).layout());
assert.equal(AD.rng.seedFromText(AD.rng.seedText(123456)), 123456);
// bus order and isolation
const bus = new AD.Bus(), seen = [];
bus.on('hit', () => seen.push('b'), 60); bus.on('hit', () => { throw new Error('x'); }, 10); bus.on('hit', () => seen.push('a'), 50);
bus.emit('hit', {}); assert.deepEqual(seen, ['a', 'b']);
```

- [ ] **Step 2: Run** `node --test tests/stats.test.mjs` → FAIL.
- [ ] **Step 3: Implement** the three modules. The spec fixes the formulas:
  - `band`: minutes per band = 5 × 2 / d, capped at 6.
  - `seedText`: one of 64 book words (Bilibara, Rose, Garden, Tide, Lantern, Ivory, …) + `-` + a 4-digit number.
  - `seedFromText`: inverts it for generated texts, and hashes any other text (FNV-1a) into a uint32.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: seeded streams, event bus, formulas"`

### Task 3: The tile grid

**Files:**
- Create: `src/sim/grid.js`, `tests/grid.test.mjs`

**Interfaces:**
- Produces: `AD.TILES[glyph] = {walk, fly, sight, flammable, water, slow, pit, door, solidProp}`. Glyphs:

  | Glyph | Tile | Glyph | Tile |
  |---|---|---|---|
  | `.` | floor | `"` | tall grass (blocks sight) |
  | `,` | grass (flammable) | `-` | shallow water (slow 30%) |
  | `~` | deep water (fly only) | `O` | pit (fly only) |
  | `#` | wall | `%` | cracked wall |
  | `D` | door | `+` | locked door |
  | `p` | pot | `c` | crate |
  | `b` | powder barrel | `L` | lamp (blocks) |
  | `v` | vat (blocks) | `^` | trap (walkable) |
  | `G` | Seam Gate (walkable) | `C` | chest (blocks) |
  | `P` | item pedestal (walkable) | `B` | block (pushable later; solid in M1) |
  | `f` | campfire (blocks) | | |

- Produces: `new AD.Grid(rows: string[10])` with `w = 15`, `h = 10`, and:
  - `at`, `set`
  - `passable(x, y, mode: 'walk'|'fly')`, `opaque(x, y)`, `los(x0, y0, x1, y1) → bool` (Bresenham; the end tiles are excluded from the opaque test)
  - `distanceMap(goals: [x,y][], mode) → Int16Array` (−1 = unreachable; 8-way, with diagonals only if both orthogonals are passable)
  - `fleeMap(dist: Int16Array) → Float32Array` (`−1.2 × dist`, relaxed once)
  - `claim(id, x, y) → bool`, `release(id, x, y)`, `bodyAt(x, y) → id | 0`

- [ ] **Step 1: Write the failing tests:**

```js
const rows = ['###############','#.............#','#..#..........#','#..#...~~.....#','#..#...~~.....#','D.............D','#......O......#','#.....""......#','#.............#','#######D#######'];
const g = new AD.Grid(rows);
assert.equal(g.passable(7, 3, 'walk'), false); assert.equal(g.passable(7, 3, 'fly'), true);
assert.equal(g.los(1, 3, 6, 3), false);            // the wall at x=3 blocks
assert.equal(g.los(4, 7, 9, 7), false);            // tall grass blocks sight
const d = g.distanceMap([[1, 1]], 'walk'); assert.equal(d[1 * 15 + 2], 1); assert.equal(d[3 * 15 + 7], -1);
assert.equal(d[2 * 15 + 2], 1);                    // diagonal allowed: both orthogonals open
assert.equal(d[3 * 15 + 4], 3);                    // no corner cutting past the wall at (3,2)/(3,3)
assert.ok(g.claim(5, 4, 4) && !g.claim(6, 4, 4)); g.release(5, 4, 4); assert.ok(g.claim(6, 4, 4));
```

- [ ] **Step 2: Run** `node --test tests/grid.test.mjs` → FAIL.
- [ ] **Step 3: Implement** `grid.js`. The distance map is a breadth-first search with unit cost (diagonal = 1); occupancy is an `Int32Array(150)`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: tile grid, sight, distance maps"`

### Task 4: Bodies and the tile glide

**Files:**
- Create: `src/sim/entity.js`, `tests/entity.test.mjs`

**Interfaces:**
- Consumes: `AD.Grid` (Task 3).
- Produces: `AD.ent.make(room, {kind, team, x, y, speed, mode, hp, …}) → e`. Every body has `id, kind, team, x, y` (the tile it holds), `fx, fy` (drawn position in tiles, as floats), `move: null | {x0, y0, x1, y1, t, dur}`, `facing: [dx, dy]`, `hp, mhp`, `statuses`, `iframes`, `hitstop`.
- Produces: `AD.ent.framesPerTile(speed) = Math.round(60 / speed)` (7.5 → 8).
- Produces: `AD.ent.tryStep(room, e, dx, dy) → bool`. It claims the destination when the step starts and releases the old tile when the step ends, and it refuses a diagonal unless both orthogonals are passable and free.
- Produces: `AD.ent.tick(room, e)`, which advances the glide and fires `room.onArrive(e)`. Also `AD.ent.push(room, e, dx, dy, tiles)`: a knock-back glide of 6 frames per tile that stops at the first blocked tile.
- Produces: `AD.ent.buffer(e, dx, dy)`, which stores the last direction pressed during a step and takes it on the frame the step ends.

- [ ] **Step 1: Write the failing tests:**

```js
const room = AD.testRoom();                        // helper in tests/load.mjs: open 15×10 room with walls
const e = AD.ent.make(room, { kind: 'hero', team: 'p', x: 5, y: 5, speed: 7.5, mode: 'walk', hp: 110 });
assert.equal(AD.ent.framesPerTile(7.5), 8);
assert.ok(AD.ent.tryStep(room, e, 1, 0)); assert.equal(room.grid.bodyAt(6, 5), e.id);
for (let i = 0; i < 4; i++) AD.ent.tick(room, e); assert.equal(e.fx, 5.5);
AD.ent.buffer(e, 0, 1);
for (let i = 0; i < 4; i++) AD.ent.tick(room, e);
assert.deepEqual([e.x, e.y], [6, 5]); assert.equal(room.grid.bodyAt(5, 5), 0);
assert.ok(e.move && e.move.y1 === 6);              // the buffered step began on the arrival frame
const m = AD.ent.make(room, { kind: 'monster', team: 'e', x: 8, y: 5, speed: 5, mode: 'walk', hp: 60 });
assert.equal(AD.ent.tryStep(room, m, -1, 0), true); assert.equal(AD.ent.tryStep(room, AD.ent.make(room, { kind: 'monster', team: 'e', x: 6, y: 4, speed: 5, mode: 'walk', hp: 1 }), 1, 0), false);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `entity.js`, and add the `AD.testRoom()` helper to `tests/load.mjs`. The helper returns `{grid, bodies: Map, bus: new AD.Bus(), frame: 0, run: {coins: 0, coef: () => 1}}`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: bodies and the tile glide"`

### Task 5: Combat core and statuses

**Files:**
- Create: `src/sim/combat.js`, `src/sim/status.js`, `tests/combat.test.mjs`

**Interfaces:**
- Consumes: `AD.stat`, `AD.Bus`, `AD.ent`.
- Produces: `AD.combat.tiles(shape, x, y, facing) → [x, y][]`. Shapes are `{k: 'adjacent'}`, `{k: 'line', n}`, `{k: 'cone', n}` (rows widening 1, 3, 5 …), `{k: 'ring', r}`, `{k: 'square', r}` (r = 1 is the 3×3), `{k: 'plus', r, at}` (`at` = tiles ahead), `{k: 'arc3'}` (the tile ahead and both tiles beside it), and `{k: 'wave', w, n}`.
- Produces: `AD.combat.deal(room, rec) → {amount, crit, blocked, killed}` with `rec = {src, tgt, pct, type, proc, mask: string[], status?, push?, flat?}`. It applies, in order:
  1. base damage × pct;
  2. crit (`rec.forceCrit`, or a roll on `combat`);
  3. damage bonuses from `room.bus.emit('dealMods')`;
  4. block (`emit('block')`);
  5. armour (`AD.stat.mitigate`);
  6. flat reduction (minimum 1).

  It then emits `hit`, `hurt`, and `kill` when HP reaches 0 (so `death` can be cancelled by Get Up or the Rose Divine Heart through `emit('lethal')`). It sets 3 frames of hit-stop on both sides (5 on a crit).
- Produces: `AD.combat.attack(room, owner, def) → tele`, with `def = {shape, wind, act, rec, pct, proc, status?, push?, noise?}`. `AD.combat.tick(room)` advances every attack: the tiles show during `wind`, damage lands on the first `act` frame on hostile bodies whose `iframes` are 0, and the owner can't act during `rec`.
- Produces: `AD.status.apply(e, kind, {dur, pct, src})`, `AD.status.tick(room, e)` and `AD.status.mods(e) → {move, atk, dmg, armour, miss, rooted, stunned, noHeal}` with the §7.5 values:
  - Burn: 50% of the burner's base damage per second, 3 s, refreshes.
  - Bleed: 240% over 3 s, stacks.
  - Chill: −40% move and attack for 2 s.
  - Root: 2 s.
  - Blind: 50% miss for 3 s.
  - Weaken: −30% damage and −20 armour for 4 s.
  - Stun.
  - Poison: from gas.

- [ ] **Step 1: Write the failing tests:**

```js
assert.deepEqual(AD.combat.tiles({ k: 'arc3' }, 5, 5, [1, 0]), [[6, 5], [6, 4], [6, 6]]);
assert.deepEqual(AD.combat.tiles({ k: 'plus', r: 1, at: 2 }, 5, 5, [0, 1]).length, 5);
assert.equal(AD.combat.tiles({ k: 'square', r: 1 }, 5, 5, [1, 0]).length, 9);
// damage pipeline
const room = AD.testRoom(), h = hero(room, 5, 5), g = goblin(room, 6, 5, { hp: 60 });
const r1 = AD.combat.deal(room, { src: h, tgt: g, pct: 1, type: 'normal', proc: 1, mask: [] });
assert.equal(r1.amount, 12); assert.equal(g.hp, 48); assert.equal(h.hitstop, 3);
g.armour = 100; assert.equal(AD.combat.deal(room, { src: h, tgt: g, pct: 1, type: 'normal', proc: 1, mask: [] }).amount, 6);
// telegraph: a roll's iframes dodge it, standing in it hurts
const t = AD.combat.attack(room, g, { shape: { k: 'adjacent' }, wind: 24, act: 3, rec: 18, pct: 1, proc: 1 });
h.iframes = 30; for (let i = 0; i < 27; i++) AD.combat.tick(room); assert.equal(h.hp, 110);
// burn ticks
AD.status.apply(g, 'burn', { dur: 180, src: h }); const before = g.hp;
for (let i = 0; i < 60; i++) AD.status.tick(room, g); assert.equal(before - g.hp, 6);      // 50% of 12 per second
// a lethal hit can be cancelled
room.bus.on('lethal', (p) => { p.cancel = true; p.tgt.hp = 1; });
const r2 = AD.combat.deal(room, { src: g, tgt: h, pct: 50, type: 'normal', proc: 1, mask: [] });
assert.equal(r2.killed, false); assert.equal(h.hp, 1);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `combat.js` and `status.js`. Crit doubles damage. `proc` and `mask` are carried on the record for the item handlers (Task 6).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: combat pipeline, telegraphs, statuses"`

### Task 6: Items and equipment

**Files:**
- Create: `src/data/items.js`, `src/sim/items.js`, `tests/items.test.mjs`

**Interfaces:**
- Consumes: `AD.Bus` events `hit`, `kill`, `hurt`, `roomClear`, `dealMods`, `block`, `lethal`; `AD.stat`; `AD.combat.deal`.
- Produces: `AD.ITEMS[id] = {id, n, tier: 'common'|'uncommon'|'legendary'|'boss'|'equipment', desc, icon, cd?}`, containing exactly the §5.3 M1 catalogue (15 common, 7 uncommon, 2 legendary, 1 boss, 4 equipment).
- Produces: `AD.items.give(run, hero, id)`, `AD.items.count(hero, id)`, `AD.items.install(room, hero)` (registers handlers on the room's bus), and `AD.items.totals(hero) → {maxHp, move, atkSpeed, crit, regenOOC, rolls, cdMul, flat, armourAttacking, …}`.
- Produces: `AD.items.useEquipment(room, hero) → bool` (refuses while on cooldown).
- Proc rule: a chance item rolls `chance × rec.proc` on `combat` and adds its id to the child record's `mask`. It never triggers when `rec.mask` already contains its id.

- [ ] **Step 1: Write the failing tests** (values from §5.3):

```js
give('lazyman', 3); assert.equal(AD.items.totals(h).maxHp, 75);
give('tinring', 1); assert.equal(+blockChance(h).toFixed(4), 0.1304);
give('lucienswatch', 2); assert.equal(+AD.items.totals(h).cdMul.toFixed(2), 0.81);
give('warmmitts', 1); assert.equal(AD.combat.deal(room, rec(h, freshGoblin)).amount, 21);   // 12 × 1.75
give('brassbuttons', 1); assert.equal(AD.combat.deal(room, rec(goblinHitFor(4), h)).amount, 1);
// proc chains terminate: Spark Coil + Throwing Knives + Petal Storm all at 100%
forceChances(1); give('sparkcoil', 1); give('throwingknives', 1); give('petalstorm', 1);
const hits = countEmits(room, 'hit', () => AD.combat.deal(room, rec(h, crowdOf(10))));
assert.ok(hits > 3 && hits < 200);                   // it chains, and it ends
// Rose Divine Heart revives once and wilts
give('roseheart', 1); kill(h); assert.equal(h.hp, h.mhp); assert.equal(AD.items.count(h, 'roseheart'), 0); assert.equal(AD.items.count(h, 'wiltedrose'), 1);
// Brass Moon: every third hit crits
give('brassmoon', 1); const crits = [1, 2, 3, 4, 5, 6].map(() => AD.combat.deal(room, rec(h, dummy)).crit);
assert.deepEqual(crits, [false, false, true, false, false, true]);
// equipment cooldown
h.equipment = 'anchor'; assert.ok(AD.items.useEquipment(room, h)); assert.ok(!AD.items.useEquipment(room, h)); assert.equal(h.eqCd, 1800);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the catalogue and its behaviours. Each item is a `{stat?: fn(totals, n), on?: {event: handler}}` record; the Brass Moon counter lives on the hero. Equipment effects use `AD.combat.attack`/`deal` and the world helpers (Powder Barrel calls `AD.world.explode`, which is a no-op stub until Task 10).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: M1 items and equipment"`

### Task 7: Abarax

**Files:**
- Create: `src/data/heroes.js`, `src/sim/hero.js`, `tests/hero.test.mjs`

**Interfaces:**
- Consumes: Tasks 4–6.
- Produces: `AD.HEROES.abarax`. Base stats §4.4: 110 HP, regen 1.0, damage 12, armour 0, crit 1%, attack speed 1.0, move 7.5, rolls 2. Kit definitions:
  - `combo`: three hits of 100, 100 and 180%. Frames 4/2/8; the chain window is the recovery; 20 frames of pause resets the combo. Hits 1 and 2 use `adjacent`; hit 3 uses `arc3` and pushes 1. Proc 1.0.
  - `spin`: hold for 40 frames, 300% on `ring r=1`, 2 shield damage.
  - `gifts`: cooldown 240 frames.
    - flame: the tile ahead and the three tiles beyond it, 220%, burn;
    - bloom: `plus r=1 at=2`, 150%, root 120;
    - tide: `wave w=3 n=4`, 120%, push 2.
  - `roll`: 2 tiles over 14 frames, iframes 1–12, 180 frames to recharge each charge.
  - `getup`: once per depth: 1 HP, heal 20% over 60 frames, 120 iframes.
- Produces: `AD.hero.make(room, id, run) → h` and `AD.hero.control(room, h, pad)`. `pad = {sx, sy, a, aHeld, aReleased, b, r, l, q: [b, b, b]}`; `sx`/`sy` are each −1, 0 or 1.
- Produces: `AD.hero.gainXp(h, n)` (levels per §4.1: +30% base HP and +20% base damage per level) and `AD.hero.nextGift(h) → 'flame'|'bloom'|'tide'`.

- [ ] **Step 1: Write the failing tests:**

```js
// combo damage and timing: A, A, A in rhythm
pressA(); run(14); pressA(); run(14); pressA(); run(14);
assert.deepEqual(dealtTo(dummy), [12, 12, 22]);       // 100%, 100%, 180% (21.6 rounds to 22)
run(30); pressA(); run(14); assert.equal(lastDealt(dummy), 12);   // reset after a pause
// spin
holdA(40); releaseA(); run(4); assert.equal(dealtTo(ringOf8).length, 8); assert.equal(dealtTo(ringOf8)[0], 36);
// gifts cycle, cooldown 240
pressB(); assert.equal(AD.hero.nextGift(h), 'bloom'); pressB(); assert.equal(AD.hero.nextGift(h), 'bloom'); run(240); pressB(); assert.equal(AD.hero.nextGift(h), 'tide');
// roll: two tiles, iframes, two charges, 3 s recharge
pressR(); run(14); assert.deepEqual([h.x, h.y], [7, 5]); pressR(); pressR(); assert.equal(h.rolls, 0); run(180); assert.equal(h.rolls, 1);
// get up once per depth
lethalHit(h); assert.equal(h.hp > 0, true); lethalHit(h, { afterIframes: true }); assert.equal(h.dead, true);
// levelling: 20 xp → level 2: max HP 143, damage 14.4
AD.hero.gainXp(h, 20); assert.equal(h.level, 2); assert.equal(h.mhp, 143); assert.equal(+h.dmg.toFixed(1), 14.4);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `heroes.js` and `hero.js`. Attack speed divides the wind-up and recovery frames (rounded, with a minimum of 1). An A pressed mid-glide is queued and fires on arrival.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: Abarax's kit"`

### Task 8: Monsters and their logic

**Files:**
- Create: `src/data/monsters.js` (the Bilibara roster; mini-bosses and the boss arrive in Task 13), `src/sim/ai.js`, `tests/ai.test.mjs`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: `AD.MONSTERS[id] = {n, hp, dmg, speed, cost, mode, attacks: [def], brain, from}`, holding the §7.3 table exactly: rat, grunt, slinger, bomber, shaman, pickpocket, whelp, tough, hound, fusilier, brassmask, knuckle. `from` is the first depth the monster appears.
- Produces: `AD.ai.spawn(room, id, x, y, {level, elite, asleep}) → m` and `AD.ai.think(room, m)`, a state machine with the states `asleep`, `wander`, `hunt` and `flee`. Brains:
  - `melee`: follows the distance map, attacks when the target is in its shape.
  - `ranged`: keeps 3–4 tiles away using the flee map.
  - `bomber`: throws to a tile 3 ahead.
  - `shaman`: heals goblins within 3 tiles for 15 every 240 frames, hastes +30% for 180.
  - `thief`: steals 10% of coins (min 5, max 50), flees, despawns after 600 frames; if killed it drops 1.5×.
  - `pack`: a hound brain.
  - `flyer`: a whelp brain using the fly map.
  - `shield`: Brass Mask; −80% damage from the front.
- Produces: noise. `AD.ai.noise(room, x, y, radius)` wakes sleepers within the radius on a 50% roll each. Morale: a goblin below 25% HP flees on a 50% roll, toward a living shaman if there is one.

- [ ] **Step 1: Write the failing tests:**

```js
const grunt = AD.ai.spawn(room, 'grunt', 10, 5); for (let i = 0; i < 120; i++) tickAll(room);
assert.ok(Math.abs(grunt.x - h.x) + Math.abs(grunt.y - h.y) <= 2);                  // it closed in
const sl = AD.ai.spawn(room, 'slinger', 8, 5); for (let i = 0; i < 180; i++) tickAll(room);
const dist = Math.max(Math.abs(sl.x - h.x), Math.abs(sl.y - h.y)); assert.ok(dist >= 3 && dist <= 4);
const sleeper = AD.ai.spawn(room, 'tough', 12, 2, { asleep: true }); tickAll(room); assert.equal(sleeper.state, 'asleep');
assert.equal(AD.combat.deal(room, rec(h, sleeper)).crit, true);                    // a surprise always crits
const mask = AD.ai.spawn(room, 'brassmask', 6, 5); mask.facing = [-1, 0];
assert.equal(AD.combat.deal(room, rec(h, mask)).amount, 2);                        // 12 × 0.2, front blocked
room.run.coins = 100; const thief = AD.ai.spawn(room, 'pickpocket', 6, 5); forceHit(thief, h);
assert.equal(room.run.coins, 90); assert.equal(thief.state, 'flee');
// a whelp crosses a pit row the grunt can't
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `monsters.js` and `ai.js`.
  - Distance maps are rebuilt only when the hero changes tile, and cached per mode on the room.
  - The red tiles of a monster attack use Task 5 telegraphs.
  - Monster levels come from `AD.stat.enemyLevel(run.coef())`, with HP and damage scaled by `scaleHp` and `scaleDmg`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: Bilibara roster and monster logic"`

### Task 9: The spawner and elites

**Files:**
- Create: `src/sim/director.js`, `src/data/regions.js` (Bilibara spawn weights by depth, §7.3), `tests/director.test.mjs`

**Interfaces:**
- Consumes: `AD.MONSTERS`, `AD.stat`, `AD.rng`.
- Produces: `AD.director.budget(coef, kind: 'room'|'challenge'|'gate')`:
  - room: `20 + 10 × coef`;
  - challenge: ×1.5;
  - gate: `15 + 8 × coef`.
- Produces: `AD.director.plan(r, region, depth, budget) → wave[]`. There are at most 3 waves, and each wave is `[{id, elite: null | affix}]`. A monster becomes an elite when the remaining budget is ≥ 6 × its cost and the depth is ≥ 3.
- Produces: `AD.director.spawnTiles(room, n, r)`: walkable tiles at least 4 tiles from the hero, not on a door, and free.
- Produces: `AD.director.tick(room)`. It releases the next wave when the alive cost falls below 30% of the current wave's cost, and never lets more than 40 monsters be alive (the rest of the wave waits).
- Produces: `AD.ELITES[affix]` for Gold-flame, Ivory, Spark-struck, Thorned and Seam-touched (§7.4). An elite has ×4 HP and ×2 damage, costs ×6, and drops a petal 25% of the time.

- [ ] **Step 1: Write the failing tests:**

```js
assert.equal(AD.director.budget(1, 'room'), 30); assert.equal(AD.director.budget(2, 'gate'), 31);
const waves = AD.director.plan(AD.rng.make(7), 'bilibara', 1, 30);
assert.ok(waves.length >= 1 && waves.length <= 3);
assert.ok(waves.flat().every((s) => AD.MONSTERS[s.id].from <= 1 && !s.elite));      // no elites before depth 3
assert.ok(waves.flat().reduce((t, s) => t + AD.MONSTERS[s.id].cost, 0) <= 30);
const late = AD.director.plan(AD.rng.make(7), 'bilibara', 4, 400);
assert.ok(late.flat().some((s) => s.elite));
// review focus 5: never more than 40 alive
const room = bigRoom(); room.waves = [Array.from({ length: 120 }, () => ({ id: 'rat' }))];
for (let i = 0; i < 600; i++) AD.director.tick(room);
assert.ok(maxAliveSeen(room) <= 40);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `director.js` and the Bilibara weights in `regions.js`. An elite multiplies the HP and damage of the spawned body; its affix behaviour lives in the elite handlers (bus `hit` and `kill` for the monster).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: spawner, waves, elites"`

### Task 10: World systems

**Files:**
- Create: `src/sim/world.js`, `tests/world.test.mjs`

**Interfaces:**
- Consumes: `AD.Grid`, `AD.combat`, `AD.status`, `AD.rng` (`combat` stream).
- Produces: `room.gas: Float32Array(150)` with `room.gasKind`, and `AD.world.addGas(room, x, y, kind, vol)`. Each tick:
  - the gas spreads evenly to the tile and its open neighbours;
  - walls block it, and closed doors pass 10%;
  - it decays 2%;
  - poison deals 1% of max HP per second per 100 volume.
- Produces: `room.fire: Uint8Array(150)` (frames left), `AD.world.ignite(room, x, y)` and `AD.world.tickFire(room)`:
  - each tick, a burning tile lights each flammable neighbour with a 12% chance;
  - a tile burns for 120–180 frames and becomes ash (`.`);
  - bodies on a burning tile gain Burn;
  - water and Frost put it out.
- Produces: `AD.world.explode(room, x, y, r, pct, src)`. It deals damage on the `square r` (3×3 for r = 1), breaks pots and crates, chains powder barrels, opens cracked walls (`%` becomes `D`) and makes noise of radius 6.
- Produces: `AD.world.breakAt(room, x, y)`. Pots and crates drop coins (60%), a heart (15%) or nothing.
- Produces: traps (`^`), hidden until spotted. The hero spots one within 2 tiles with a 20% chance per second. The M1 kinds are spike (60% damage), alarm (wakes the room), fire, gas (300 volume) and pit.
- Produces: pits. A walker who ends a step on `O` loses 10% of max HP and returns to the room's entry tile. Water (`-`) slows walkers by 30% and clears Burn on entry.
- Produces: `room.light: Uint8Array(150)`, the region's ambient level plus lamps (`L`), fire and the campfire (`f`). `AD.world.sightRange(room, x, y)` is 8 tiles in light and 4 in the dark. Monster sight (Task 8) and the hero's view (Task 16) use it.

- [ ] **Step 1: Write the failing tests:**

```js
AD.world.addGas(room, 5, 5, 'poison', 600); for (let i = 0; i < 30; i++) AD.world.tick(room);
const total = sum(room.gas); assert.ok(total < 600 && total > 300); assert.equal(room.gas[idx(0, 0)], 0);   // walls block
assert.ok(room.gas[idx(6, 5)] > 0);
// fire spreads only on grass, leaves ash
grassRow(room, 3); AD.world.ignite(room, 2, 3); for (let i = 0; i < 400; i++) AD.world.tick(room);
assert.equal(room.grid.at(2, 3), '.'); assert.ok(countAsh(room) >= 2);
// explosion opens a cracked wall and chains a barrel
room.grid.set(5, 0, '%'); room.grid.set(6, 2, 'b'); AD.world.explode(room, 5, 1, 1, 3, h);
assert.equal(room.grid.at(5, 0), 'D'); assert.equal(room.grid.at(6, 2), '.');
// pit: −10% and back to the entry
room.entry = [1, 5]; room.grid.set(6, 5, 'O'); walkInto(h, 6, 5); assert.deepEqual([h.x, h.y], [1, 5]); assert.equal(h.hp, 99);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `world.js`, and replace the explode stub from Task 6.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: gas, fire, water, traps, explosions"`

### Task 11: Floor and room generation

**Files:**
- Create: `src/gen/floor.js`, `src/gen/room.js`, `src/data/templates.js`, `tests/gen.test.mjs`

**Interfaces:**
- Consumes: `AD.rng`, `AD.TILES`.
- Produces: `AD.gen.floor(depth, r) → F`.
  - `F.rooms` is a `Map` keyed `"gx,gy"` → `{gx, gy, type, doors: {n, e, s, w: null|'open'|'locked'|'secret'}, dist}`.
  - `F.start`, `F.exit`, `F.keys: [{room, lock}]`.
  - `type` is one of `start`, `combat`, `treasure`, `secret`, `rest`, `exit`, or `boss` (on depth 5, where the exit leads to the arena).
  - Algorithm per §6.1: a 9×8 slot grid; count = `min(16, 8 + floor(0.4 × depth) + rand(0..2))`; a queue walk; the exit on the farthest dead end; treasure on another dead end, behind a locked door 50% of the time; the secret on the empty slot touching the most rooms (at least 2, never beside the exit); one rest room. If there are too few dead ends, it retries with the next seed.
- Produces: `AD.gen.validate(F) → {ok, why}`. Every room must be reachable, and every lock's key must be reachable without passing that lock.
- Produces: `AD.gen.room(F, key, region, r) → {rows: string[10], spawnable: [x, y][], decor}`. It picks a template of the right type (combat templates ≥ 18; treasure, rest and secret ≥ 3 each; start 2; exit 3; boss arena 1 — the Tanneries yard with two vats). It mirrors or flips at random, punches the doors, and dresses the room by the region's rules (grass, pots, crates, lamps, rubble, shallow water, and traps from depth 2).
- Template format: 15×10 strings using the Task 3 glyphs. Door positions are fixed: top (7,0), bottom (7,9), left (0,4), right (14,4). Templates use `#` in those positions, and `room()` opens the ones the floor needs.

- [ ] **Step 1: Write the failing tests:**

```js
test('10,000 seeds generate valid floors', () => {
  for (let s = 1; s <= 10000; s++) for (const depth of [1, 3, 5]) {
    const F = AD.gen.floor(depth, AD.rng.make(s * 7 + depth));
    const v = AD.gen.validate(F); assert.ok(v.ok, s + '/' + depth + ' ' + v.why);
    assert.ok(F.rooms.size >= 8 && F.rooms.size <= 16);
    assert.equal([...F.rooms.values()].filter((r) => r.type === 'exit' || r.type === 'boss').length, 1);
  }
});
test('every template is 15×10, walls its border except doors, and its floor is connected', () => {
  for (const t of AD.TEMPLATES.bilibara) { assert.equal(t.rows.length, 10); t.rows.forEach((r) => assert.equal(r.length, 15)); assert.ok(connected(t.rows)); }
});
test('the same seed gives the same floor', () => { assert.deepEqual(dump(AD.gen.floor(2, AD.rng.make(9))), dump(AD.gen.floor(2, AD.rng.make(9)))); });
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the generator and write the Bilibara templates. The templates draw on the book's places: alleys and stoops of Rue Caillou, harbour sheds with crates and shallows, the Tanneries' vats and drying racks, sewer channels with pits.
- [ ] **Step 4: Run** `node --test tests/gen.test.mjs` → PASS (it runs in under 30 s).
- [ ] **Step 5: Commit** `"Between the Rooms: floor and room generation"`

### Task 12: The run: rooms, doors, pickups, gate, depths

**Files:**
- Create: `src/sim/room.js`, `src/game/run.js`, `tests/run.test.mjs`

**Interfaces:**
- Consumes: Tasks 2–11.
- Produces: `new AD.Run({hero: 'abarax', difficulty: 1|2|3, seed}) → run`, with:
  - `run.depth`, `run.minutes` (sim frames inside depths ÷ 3600), `run.coef()`, `run.coins`, `run.keys`, `run.bombs` (start 1), `run.petals`, `run.paused`
  - `run.floor`, `run.room` (the live room), `run.roomState: Map key → {state: 'unvisited'|'entered'|'cleared', taken: Set}`
  - `run.events: AD.Bus` and `run.hero`
- Produces: `run.tick(pad)`, one 60 Hz step. It does nothing while `run.paused`, which is the review-focus guard for the clock. It handles:
  - the hero's control, AI, combat, statuses, world, the director;
  - pickups: coins drift within 2 tiles; hearts heal 10%; keys; bombs; a pedestal item fires a 90-frame pickup banner;
  - doors: walking out of a door tile slides to the next room over 20 frames;
  - the room state machine.
- Room state machine:
  - `enterRoom`: a combat room seals its doors (`D` → `=` sealed bars) and plans its waves; spawns get a 18-frame shimmer during which they cannot act or be hit.
  - `roomClear`: the doors open, and a reward rolls on `loot`: 30% coins, 10% a key or consumable. Sardine Tin and similar items react.
- Locked doors (`+`) and locked chests use a small key on contact.
- Treasure chest: a small chest costs `chestCost(25, coef)` coins and opens on A when affordable. It rolls common 79, uncommon 20, legendary 1 on `loot`.
- Seam Gate (§6.4):
  - A touches it and emits `gateStart`; it charges 1/1800 per frame while the hero is within 3 tiles.
  - The guardian is the region's mini-boss: one not yet met this run, or any of them once all are met.
  - Waves come every 480 frames from the gate budget.
  - When it is charged and the guardian is dead, it emits `gateCharged`. The guardian drops an item (uncommon or better) and 3 petals, and the exit opens.
  - Stepping in moves to the next depth: `depthStart`, the clock's `depthsCleared` rises, and Get Up resets.
  - On depth 5 the exit opens onto the boss arena.
- Secret rooms hold either an equipment barrel (`chestCost(25, coef)`, one random equipment item) or a large chest (`chestCost(50, coef)`, uncommon 80, legendary 20), at even odds. This is M1's source of equipment.
- Rest rooms: a campfire (no monsters), plus the depth's lore page as a pickup that adds it to the Book.
- Petals: +1 on reaching each new depth (§5.5).
- Run end: `death` → `run.over = {won: false, by}`; the First Knuckle's `kill` → `run.over = {won: true}`.

- [ ] **Step 1: Write the failing tests:**

```js
const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 4821 });
assert.equal(run.depth, 1); assert.equal(run.roomState.get(run.floor.start).state, 'entered');
// clock runs in play, not while paused (review focus 1)
tickN(run, 3600); assert.equal(+run.minutes.toFixed(2), 1); run.paused = true; tickN(run, 3600); assert.equal(+run.minutes.toFixed(2), 1);
// entering a combat room seals it; clearing opens it and rolls a reward
gotoRoomOfType(run, 'combat'); assert.ok(sealed(run.room)); killAll(run); tickN(run, 2); assert.ok(!sealed(run.room));
assert.equal(run.roomState.get(run.room.key).state, 'cleared');
// a locked door takes a key
run.keys = 1; walkIntoLocked(run); assert.equal(run.keys, 0);
// the gate: charge only near it; guardian; exit opens only when both are done
gotoRoomOfType(run, 'exit'); touchGate(run); stepAway(run, 5); tickN(run, 600); assert.equal(run.gate.charge, 0);
standAtGate(run); tickN(run, 1800); assert.equal(run.gate.charge, 1); assert.equal(run.gate.open, false);
killGuardian(run); tickN(run, 2); assert.equal(run.gate.open, true); enterGate(run); assert.equal(run.depth, 2);
// determinism: same seed and inputs, same state hash after 5,000 frames
assert.equal(hashAfter(4821, script, 5000), hashAfter(4821, script, 5000));
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `room.js` and `run.js`. `run.hash()` hashes the hero, the bodies, the room state and the stream positions, for the replay tests.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: the run — rooms, doors, pickups, gate, depths"`

### Task 13: Mini-bosses and First Knuckle

**Files:**
- Create: `src/sim/boss.js`; Modify: `src/data/monsters.js` (add `goldtooth`, `fixer`, `marais`, `firstknuckle`); Test: `tests/boss.test.mjs`

**Interfaces:**
- Consumes: `AD.ai.spawn`, `AD.combat.attack`, the run.
- Produces: a boss definition: `{hp, dmg, shield, phases: [1, 0.66, 0.33], patterns: [{id, weight, phase, def}], onPhase: {2: fn, 3: fn}, arena}`. Then `AD.boss.think(room, b)` picks a weighted pattern for the current phase. After each pattern it waits a gap of 30–50 frames, and it never repeats the same pattern three times in a row.
- Shields and Break (§7.6): heavy hits remove pips (charged spin 2, bomb 1, Powder Barrel 2, Knuckle Brass +1). At 0 pips the boss is staggered for 180 frames and takes +50% damage, and the shield refills at the next phase. Bosses emit `bossPhase`.
- Mini-bosses (§7.3): 900 HP at level 1, 20 damage, 3 pips, four patterns each:
  - **Gold Tooth**: knife fan (cone 3), charge (line 6), cleaver (arc3), whistle (calls 2 rats).
  - **Yaska's Fixer**: sword arc, brass jab (adjacent, ×2), call two Toughs (once per phase), lunge (line 3).
  - **Lt. Marais**: musket line 8 (45 frames), sword arc, volley (three parallel lines), sidestep (a 2-tile step and reload).
- **First Knuckle** (§7.6): 2,800 HP at level 1, 22 damage, 4 pips.
  - *Knuckle Dash*: line 6, 36-frame telegraph, 160%. If his path hits a wall or vat he is stunned 90 frames.
  - *Three-Count*: three 3×3 squares, 24 frames each, 120% each.
  - *Uppercut*: adjacent, 18 frames, 200%, knock-back 2.
  - *Call the Hand*, at 66%: two Toughs from the doors.
  - *Debts Paid*, at 33%: 8 random marked tiles, 40 frames, 100%; each leaves a 5-coin pickup.
  - Reward: Knuckle Brass, +10% max HP, 10 petals.

- [ ] **Step 1: Write the failing tests:**

```js
const b = spawnBoss(run, 'firstknuckle'); assert.equal(b.mhp, 2800); assert.equal(b.pips, 4);
spinHit(b); spinHit(b); assert.equal(b.pips, 0); assert.equal(b.stagger, 180);
assert.equal(AD.combat.deal(room, rec(h, b)).amount, 18);                        // +50% while staggered
dropTo(b, 0.65); tickN(run, 2); assert.equal(countBodies(run, 'tough'), 2); assert.equal(b.pips, 4);
forcePattern(b, 'dash'); placeVatInLine(b); tickN(run, 60); assert.ok(b.stunned > 0);
dropTo(b, 0.3); forcePattern(b, 'debts'); tickN(run, 60); assert.equal(coinPickups(run), 8);
kill(b); tickN(run, 2); assert.equal(AD.items.count(h, 'knucklebrass'), 1); assert.ok(run.over && run.over.won);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `boss.js` and the four definitions.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: Bilibara's mini-bosses and First Knuckle"`

### Task 14: Potions, scrolls, bombs, armour and curses

**Files:**
- Create: `src/data/consumables.js`; Modify: `src/game/run.js` (quickslots, the identify table); Test: `tests/consumables.test.mjs`

**Interfaces:**
- Produces: `AD.POTIONS` (Healing, Haste, Toughness, Fire, Frost, Toxic Gas, Mind Vision, Experience) and `AD.SCROLLS` (Identify, Upgrade, Remove Curse, Magic Mapping, Teleport, Rage, Recharging, Lullaby), with the §5.4 effects.
- Produces: `run.idTable = {potions: {id → colour}, scrolls: {id → rune}, known: Set}`, shuffled on `loot` at the start of the run. `AD.cons.label(run, id)` returns the colour or rune name until the item is known, and its real name after.
- Produces: `run.quick = [slot, slot]` (3 with the unlock); each slot is `{id, n}`, and identical items stack in a slot. `AD.cons.use(run, slot)`: Fire, Frost and Toxic Gas are thrown 3 tiles ahead; the rest are drunk or read. Using one identifies it. Bombs go on the tile ahead: 90-frame fuse, 300% on the 3×3 (max 9 carried). Keys max 9.
- Produces: armour. `AD.ARMOUR`:

  | Armour | Effect |
  |---|---|
  | jerkin | +5 armour, +5% move |
  | hauberk | +12 armour |
  | plate | +22 armour, −6% move |

  Each piece is `{level, cursed, curse, known}`. +3 armour per level. A found piece is cursed with probability 1/5: level −1 to −3 and one of heavy, loud, brittle or fickle. It is identified by wearing it through one depth or reading Identify. A cursed piece cannot be removed until Remove Curse is read. Armour is drawn on the hero's look (Task 15).
- Produces: the signature weapon's level. Upgrade gives +10% damage per level and asks for weapon or armour through a small chooser in the menus.

- [ ] **Step 1: Write the failing tests:**

```js
const run = newRun(77); const lbl = AD.cons.label(run, 'healing'); assert.ok(/ draught$/.test(lbl));       // e.g. 'Amber draught'
assert.notEqual(AD.cons.label(newRun(78), 'healing'), lbl);                                             // shuffled per run (with a fixed second seed)
give(run, 'healing'); run.hero.hp = 10; AD.cons.use(run, 0); tickN(run, 60); assert.equal(run.hero.hp, 76);    // +60% of 110
assert.equal(AD.cons.label(run, 'healing'), 'Draught of Healing');
const p = AD.cons.makeArmour(run, 'plate', { cursed: true, curse: 'heavy', level: -2 }); wear(run, p);
assert.equal(armourOf(run.hero), 16); assert.equal(AD.cons.unwear(run), false);                         // 22 − 6, and stuck
read(run, 'removecurse'); assert.equal(AD.cons.unwear(run), true);
read(run, 'upgrade', 'weapon'); assert.equal(+run.hero.dmgMul.toFixed(2), 1.1);
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `consumables.js` and the run hooks.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: potions, scrolls, bombs, armour and curses"`

### Task 15: Art — tiles, figures, monsters, the gba downscale

**Files:**
- Create: `src/art/{figures.js,monsters.js,tiles.js,downscale.js,atlas.js}`, `src/data/looks.js`, `tools/playtest/sheets.mjs`; Test: `tests/downscale.test.mjs`

**Interfaces:**
- Consumes: the Tactics `figures.js` (24×32 paper dolls in 48×40 canvases, with front, back and side walk cycles and side attack poses) and the Tactics `tiles.js` painter and its biome palettes.
- Produces: `AD.art.frames(look, action, dir, t) → canvas`, cached per display mode.
  - `action` is one of `idle`, `walk`, `attack1`, `attack2`, `attack3`, `spin`, `cast`, `roll`, `hurt`, `dead`.
  - `dir` is one of `down`, `up`, `left`, `right`.
  - Side views reuse the Tactics `punch` and `cast` poses.
  - Down and up attacks are new front and back arm reaches: `drawFront` gains `reach: [near, far]`, which draws the forearm and fist toward or away from the viewer.
- Produces: `AD.art.monster(id, action, dir, t)`. Goblins (grunt, slinger, bomber, shaman, pickpocket) are small paper dolls: a 20×24 body with green skin, big ears, and a per-type kit (cleaver, sling, bomb sack, bone staff, hood). The wyvern whelp and the rat are drawn top-down with a two-frame flap or scurry. The book's enemies use Tactics looks for the thug, hound, fusilier, brass mask and knuckle classes.
- Produces: `AD.art.room(rows, region, night) → {ground: canvas[4], props: canvas[10], lights: []}`. It reuses `TL.bake` with the city, dungeon and interior biomes per depth, plus new props: pot, crate, powder barrel, cracked wall, pit, tall grass, trap (faint and revealed), Seam Gate (charging ring), pedestal, chest (small and large), campfire, and sealed bars.
- Produces: `AD.art.down32(canvas) → canvas`, the 3:2 reducer. Each 3×3 block becomes a 2×2 block. Every output pixel takes the most common opaque colour of its 2×2 source quarter, with ties broken toward darker outline colours. If the outline colour `#120c1a` appears in the quarter, the result is the outline colour, and the most saturated pixel in the block is kept in its nearest output cell. Transparency wins only if the whole quarter is transparent.
- `atlas.js`: `AD.art.build(mode)` rebuilds every cache for the mode. It runs on `AD.display.onChange`.
- Produces: `AD.art.reduce(pixels: (string|null)[], w, h) → {w, h, get(x, y)}`, the DOM-free core that `down32` wraps.

- [ ] **Step 1: Write the failing test** (`tests/downscale.test.mjs`, which runs the reducer on plain pixel arrays, so the core logic is DOM-free):

```js
const px = grid(6, 6, (x, y) => (x === 0 || y === 0 || x === 5 || y === 5) ? OUT : (x === 2 && y === 2) ? '#ffd27a' : '#8a5e3e');
const o = AD.art.reduce(px, 6, 6);                    // the pure core of down32
assert.equal(o.w, 4); assert.equal(o.h, 4);
assert.equal(o.get(0, 0), OUT); assert.equal(o.get(3, 3), OUT);       // the outline survives
assert.ok(cells(o).includes('#ffd27a'));                               // the eye pixel survives
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the art modules.
- [ ] **Step 4: Run** → PASS. Then render the contact sheets with `node tools/playtest/sheets.mjs web/index.html out/sheets`:
  - `hero.png`: every Abarax action in 4 directions, in hd and gba.
  - `monsters.png`: every monster, walking and attacking.
  - `rooms.png`: 12 generated Bilibara rooms, in hd and gba.
  - `tiles.png`: every new prop.

  Open each image and check it by eye: figures are readable at both sizes, outlines are unbroken, nothing is clipped, and attack frames point the right way.
- [ ] **Step 5: Commit** `"Between the Rooms: art — tiles, figures, monsters, gba downscale"`

### Task 16: Drawing the room, effects and the HUD

**Files:**
- Create: `src/view/{render.js,fx.js,hud.js}`; Test: `tests/hud.test.mjs` (layout maths, pure), plus browser checks in `tools/playtest/smoke.mjs`

**Interfaces:**
- Consumes: `AD.art`, the run, `AD.display`.
- Produces: `AD.view.draw(ctx, run)`:
  - the baked ground, plus a redraw of tiles whose content changed (`room.dirty`);
  - bodies sorted by `fy`;
  - telegraph tiles filling red from 20% to 70% alpha across the wind-up;
  - gas tinting (poison green, smoke grey) and fire animation;
  - light pools: the region's ambient light, plus lamps and fire, plus a 4-tile radius around the hero. Bloom only in hd.
  - the room slide (20 frames): both rooms drawn offset.
- Produces `AD.fx`:
  - `number(x, y, amount, type)`. Numbers merge per source within 10 frames. Colours: normal white, crit gold, burn orange, bleed red, chill blue, spark purple, heal green.
  - `spark(x, y, size)`, `trail(owner, shape)`.
  - `hitstop` is driven by the bodies' `hitstop`; `shake(amount)` is scaled by the Settings (full 1, low 0.4, off 0); `flash(color)` is capped at 30%.
  - Particle count is halved in gba.
  - Enemy bars appear once a monster has been damaged, with the elite icon beside them.
- Produces `AD.hud.draw(ctx, run)`:
  - top left: HP bar plus number, the level, an XP sliver;
  - top right: coins, keys, bombs, the clock `m:ss` and the band name, and the minimap (known rooms, current room highlighted);
  - quickslots under the minimap;
  - bottom: the boss bar (name, HP, pips, phase marks), sliding in over 20 frames while the fight runs;
  - the pickup banner (90 frames) and the first-run hint line.
  - Every position is computed from `AD.display` by `AD.hud.layout(mode) → rects`.
- Produces: `AD.hud.coinsText(n)` and every other HUD number go through `AD.stat.short` (review focus 5).
- Produces: a slow-frame suggestion (§9.1). If the first 300 frames of play average more than 20 ms, a one-line notice suggests True GBA, and only in hd mode.

- [ ] **Step 1: Write the failing tests:**

```js
for (const mode of ['hd', 'gba']) {
  const L = AD.hud.layout(mode), W = mode === 'hd' ? 360 : 240, H = mode === 'hd' ? 240 : 160;
  for (const r of Object.values(L)) { assert.ok(r.x >= 0 && r.y >= 0 && r.x + r.w <= W && r.y + r.h <= H, mode + ' ' + JSON.stringify(r)); }
  assert.ok(!overlap(L.hp, L.coins) && !overlap(L.minimap, L.hp));
}
assert.equal(AD.hud.coinsText(12345), '12.3k');                           // review focus 5: big numbers shorten
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `render.js`, `fx.js` and `hud.js`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Browser checks.** Extend `smoke.mjs`: start a seeded run, step 600 frames with a scripted pad (walk into a combat room, attack), then screenshot both modes to `out/smoke-hd.png` and `out/smoke-gba.png`. Check by eye: HUD, damage numbers, enemy bars and telegraphs are readable in both. Also check the timing: `perf.mjs` with 40 monsters, gas and fire must show simulation ≤ 3 ms and drawing ≤ 8 ms (hd) at the 95th percentile in headless Chromium.
- [ ] **Step 6: Commit** `"Between the Rooms: room drawing, effects, HUD"`

### Task 17: Sound and music

**Files:**
- Create: `src/engine/audio.js` (the Tactics synth plus the M1 sound table and tracks); Test: `tests/audio.test.mjs` (the event → sound mapping is pure)

**Interfaces:**
- Produces: `AD.audio.sfx(name, {pitch, vol})` for the names:

  | Category | Sound names |
  |---|---|
  | Hero attacks | `palm1`, `palm2`, `palm3`, `spinCharge`, `spin` |
  | Gifts | `flame`, `bloom`, `tide` |
  | Movement | `roll` |
  | Impacts | `hit`, `crit`, `block`, `hurt` |
  | Monster attacks | `goblinSwing`, `sling`, `fuse`, `boom`, `bite`, `musket`, `clang` |
  | Rooms | `doorSlam`, `doorOpen`, `chime`, `gateHum`, `gateDone` |
  | Pickups | `coin`, `heart`, `key`, `item`, `potion`, `scroll` |
  | Get Up | `getup` |
  | Bosses | `bossIn`, `pip`, `break` |
  | Footsteps | `step_stone`, `step_wood`, `step_water`, `step_grass` |

- Produces: `AD.audio.play(track)` for the tracks `bilibara`, `fight`, `boss`, `garden` and `title`. A track switch waits for the next bar.
- Produces: `AD.audio.bind(run.events)`. It maps simulation events to sounds:
  - hit → `hit` or `crit`, scaled by the share of HP lost;
  - enterRoom (sealed) → `doorSlam` plus the fight track;
  - roomClear → `chime` plus the region track;
  - gateStart → `gateHum` (pitch rising with charge);
  - and so on.

  Attack sounds play on the attack's own frames: the wind-up whoosh at frame 0, the impact on the first active frame. Footsteps play once per step and depend on the floor glyph.

- [ ] **Step 1: Write the failing test:**

```js
const heard = []; AD.audio.sfx = (n) => heard.push(n); AD.audio.bind(bus);
bus.emit('hit', { amount: 20, crit: true, tgt: { mhp: 100 } }); bus.emit('enterRoom', { sealed: true }); bus.emit('roomClear', {});
assert.deepEqual(heard, ['crit', 'doorSlam', 'chime']);
assert.equal(AD.audio.stepSound(','), 'step_grass'); assert.equal(AD.audio.stepSound('-'), 'step_water');
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the sound table and tracks in the Tactics synth's note format.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: sound table and music"`

### Task 18: Phone controls and input

**Files:**
- Create: `src/engine/input.js`; Modify: `src/head.html` (the `#controls` markup and CSS); Test: `tests/input.test.mjs` (stick maths), `tools/playtest/mobile.mjs`

**Interfaces:**
- Produces: `AD.pad` (read each frame) `{sx, sy, a, aHeld, aReleased, b, r, l, q: [bool, bool, bool], start}`.
  - Keyboard (§4.2): arrows or WASD; Z or J attack; X or K skill; C or L roll; V or ; equipment; 1–3 quickslots; Enter or Esc for Start; M for the map.
  - Gamepad: the stick or D-pad; south face attack, west skill, east or RB roll, LB equipment, LT and RT quickslots 1 and 2, Start.
  - Touch.
- Produces: `AD.input.stickDir(dx, dy, dead = 0.28) → [sx, sy]` (8 directions; 22.5° sectors).
- Touch layout:
  - The floating stick appears where a thumb lands on the left half. Its base radius is 40 CSS px, and its knob is clamped to that radius.
  - The A, B and R buttons sit in an arc on the right; L and Start sit in the top corners. Sizes come from the Global Constraints, and each hit area is `::before` at 1.5×.
  - It uses pointer events with pointer ids, so multi-touch works.
  - Layouts: `@media (orientation: landscape)` puts the controls either side; `portrait` puts them below the screen like a GBA SP.
  - CSS variables `--ctl-scale` and `--ctl-alpha` are set from the Settings, and `.left-handed` mirrors the layout.
  - Quickslots are tapped on the canvas HUD (hit-tested with `AD.hud.layout`).
- Safety (review focus 1 and 2): `pointercancel`, `pointerup` and lost pointer capture release the stick or button. `blur`, `visibilitychange` (hidden) and `pagehide` release everything and set `AD.paused = true`, which the play scene turns into the pause menu.

- [ ] **Step 1: Write the failing tests:**

```js
assert.deepEqual(AD.input.stickDir(0.1, 0.1), [0, 0]);
assert.deepEqual(AD.input.stickDir(1, 0.1), [1, 0]); assert.deepEqual(AD.input.stickDir(0.7, 0.7), [1, 1]);
assert.deepEqual(AD.input.stickDir(-0.2, -1), [0, -1]);
// mobile.mjs (browser): for 360×780, 412×915 portrait and 780×360, 915×412 landscape:
//   every control inside the viewport, drawn sizes A 48 / B 44 / R 44 / L 40 / Start 32 at 100%, no control over the canvas
//   pointerdown on the stick + pointerdown on A (two ids) → pad.sx and pad.a both set
//   'pointercancel releases the stick': pointerdown at the stick, then pointercancel → pad.sx === 0 next frame
//   'input releases on blur and visibility change': hold right, dispatch visibilitychange(hidden) → pad.sx === 0 and AD.paused
```

- [ ] **Step 2: Run** `node --test tests/input.test.mjs` → FAIL.
- [ ] **Step 3: Implement** `input.js`, the `head.html` controls and their CSS.
- [ ] **Step 4: Run** the node tests → PASS, then `node tools/playtest/mobile.mjs web/index.html` → `mobile ok` for all four sizes.
- [ ] **Step 5: Commit** `"Between the Rooms: phone controls and input"`

### Task 19: Title, the Garden, menus and settings

**Files:**
- Create: `src/ui/menus.js`, `src/game/meta.js`, `src/data/lore.js`; Test: `tests/meta.test.mjs`

**Interfaces:**
- Produces scenes:
  - `AD.Title`: the name, Continue (if there is a run save), Garden, Settings.
  - `AD.Garden`: three walkable screens built from rooms with the `garden` biome, joined by doors. Selenne gives hints; Lucien keeps the Book (the bestiary of monsters met and the item log, M1-basic); Midas sells unlocks; the tear in the wall opens the run start: difficulty (Dawn, Dusk, Rose Hour; Dusk is the default), seed (random, or typed), Begin.
  - `AD.Play`: wraps a `Run`. Each frame it builds `AD.pad`, calls `run.tick`, and draws the view and the HUD. When `run.over` is set it goes to the summary; Start or `AD.paused` opens the pause menu.
  - `AD.Pause`: Resume; Items (a grid with stack counts and descriptions); Map; Settings; Abandon run.
  - `AD.Summary`: depth, time, kills, the item icon grid, what killed the hero, petals earned. One tap skips it.
  - `AD.Settings`:
    - display mode (hd or gba, with the live switch);
    - effects on or off;
    - shake full, low or off; flashes full or low; damage numbers on or off;
    - control size, opacity and handedness; haptics;
    - music and effects volume;
    - Report a problem (copies the error log).
- Produces: `AD.meta` `{petals, unlocks: Set, book: {monsters: Set, items: Set}, best, settings, firstRun}`, with `AD.meta.buy(id) → bool`. The Midas prices are from §5.5: healing start 30, third quickslot 40, extra roll 60, chest reroll 80, stalls −10% 60, and starting depths 50, 80 and 120 (the starting depths are not available in M1, since only one region exists; they show as locked).
- First-run hints come from `lore.js`. They show once each, at the moment they apply: A when the first monster wakes, B when the skill is first ready in a fight, R when the first telegraph appears, the gate on the first exit room, quickslots on the first pickup.

- [ ] **Step 1: Write the failing tests:**

```js
AD.meta.reset(); AD.meta.petals = 35; assert.equal(AD.meta.buy('startHealing'), true); assert.equal(AD.meta.petals, 5);
assert.equal(AD.meta.buy('thirdSlot'), false);
const run = new AD.Run({ hero: 'abarax', difficulty: 2, seed: 1, meta: AD.meta }); assert.equal(run.quick[0].id, 'healing');
assert.equal(AD.meta.hint('attack'), true); assert.equal(AD.meta.hint('attack'), false);   // once only
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the menus, the Garden and `meta.js`. Menus use the Tactics panel and font, are driven by `AD.pad` and taps, and have no animations longer than 8 frames.
- [ ] **Step 4: Run** → PASS. Extend `smoke.mjs`: Title → Garden → walk to the tear → Begin → play 300 frames → Start → Settings → switch to gba → Resume. No page errors, and the canvas is 240×160.
- [ ] **Step 5: Commit** `"Between the Rooms: title, Garden, menus, settings"`

### Task 20: Saving

**Files:**
- Create: `src/game/save.js`; Test: `tests/save.test.mjs`

**Interfaces:**
- Produces: `AD.save.run(run)`, called by `enterRoom`. It writes `seams.run = {v: 1, seed, difficulty, depth, frames, cleared, streams (positions), hero (stats, items, armour, weapon level, xp, getUpUsed), coins, keys, bombs, petals, quick, idTable, floor (rooms + roomState with taken pickups), at: {room, entry}}`.
- Produces: `AD.save.loadRun() → Run | null`. It rebuilds the floor from the seed, applies the room states, and places the hero at the room's entry. A sealed room that was not cleared is entered fresh; a gate that was charging restarts.
- Produces: `AD.save.clearRun()` (called on death and on victory). `AD.save.meta()` saves on every change.
- Versioning: `migrate(data)` converts `v < current`. Data it cannot read moves to `seams.run.bad` and returns `null`, and the Title shows *"Your last run couldn't be restored."*
- Storage failure: when `AD.store.set` returns false, `AD.save.warned` is set and the HUD shows *"Progress can't be saved on this device."* once; play continues.

- [ ] **Step 1: Write the failing tests:**

```js
test('resume does not duplicate pickups or coins', () => {
  const run = playTo(4821, 'second room after taking its coins and a key');
  const coins = run.coins, keys = run.keys; AD.save.run(run);
  const back = AD.save.loadRun(); assert.equal(back.coins, coins); assert.equal(back.keys, keys);
  enterRoom(back, firstRoomKey(back)); assert.equal(pickupsIn(back.room), 0);
});
test('a half-charged gate restarts', () => { const run = atGateHalfCharged(); AD.save.run(run); assert.equal(AD.save.loadRun().gate, null); });
test('saving without storage notices once and keeps playing', () => {
  AD.store.set = () => false; const run = newRun(); AD.save.run(run); AD.save.run(run);
  assert.equal(noticeCount(run), 1); tickN(run, 60); assert.ok(!run.crashed);
});
test('unreadable save is set aside', () => { rawSet('seams.run', '{bad'); assert.equal(AD.save.loadRun(), null); assert.ok(rawGet('seams.run.bad')); });
test('replay: same seed and input log give the same hash', () => { assert.equal(replay(91, LOG), replay(91, LOG)); });
```

- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `save.js`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Between the Rooms: run and meta saves"`

### Task 21: Playtest bot, sweep and full checks

**Files:**
- Create: `tools/playtest/{bot.js,sweep.mjs,perf.mjs}`; Modify: `smoke.mjs`, `sheets.mjs`

**Interfaces:**
- `bot.js` is injected into the page and drives `AD.pad` exactly as a player would. Each frame it:
  - moves toward the nearest monster (the distance map from its own tile);
  - attacks when one is adjacent and facing it;
  - rolls out of red tiles;
  - uses B when it's ready;
  - picks up items;
  - pays for chests;
  - goes to the exit when the room is clear, and touches and holds the gate;
  - uses Healing below 30% HP.
- `sweep.mjs <html> <seeds> <frames> <parallel> [touch|keys]` runs the bot from the tear to death, victory or the frame limit. It reports per run: depth reached, won or lost, frames, errors (`AD.errlog`), soft-locks (no change of hero tile, room or monster HP for 3,600 frames), and the 95th-percentile frame time. It exits non-zero on any error or soft-lock.

- [ ] **Step 1: Run** the full Node suite: `node --test tests/` → all pass.
- [ ] **Step 2: Run** `node tools/playtest/sweep.mjs web/index.html 20 72000 4` (20 seeds × keys and touch). Expected: `0 problem runs of 40`, and at least one run reaches depth 5.
- [ ] **Step 3: Run** `node tools/playtest/perf.mjs web/index.html` → simulation p95 ≤ 3 ms and drawing p95 ≤ 8 ms (hd), and the heap is flat (±15%) across 30 rooms.
- [ ] **Step 4: Run** `node tools/playtest/sheets.mjs` and `mobile.mjs` once more on the final build, and check the sheets by eye.
- [ ] **Step 5: Fix** anything they find (each fix follows the TDD cycle in the task that owns the code), then commit `"Between the Rooms: playtest bot and sweep"`.

### Task 22: Android app, CI, icon, README, artifact, APK, PR

**Files:**
- Create: `all-divine-seams/android/` (a copy of the Tactics shell), `tools/render-icons.mjs`, `tools/build-apk-offline.sh`, `tools/SignApk.java`, `README.md`, `.github/workflows/all-divine-seams-apk.yml`

**Interfaces:**
- Android:
  - Package `com.advoxsegoat.alldivineseams`, with `MainActivity` in that package; app name *Between the Rooms*.
  - Same minSdk 24 and targetSdk 36. The committed sideload keystore is reused (the package is different, so it doesn't clash with Tactics).
  - The key map follows Task 18: A z, B x, X c (roll), Y v (equipment), L1 q, R1 e (roll), L2 `1`, R2 `2`, Start and Select Escape.
  - The shell keeps the renderer-recovery and audio pause and resume. `onPause` dispatches `visibilitychange` so the game pauses (review focus 1).
  - `android-shell.js` only provides the clipboard and haptics: the page's own controls replace the Tactics pad.
- Icon: `render-icons.mjs` draws Abarax top-down in front of a rose-gold tear, in the adaptive, mono and legacy sizes.
- CI: the Tactics workflow, with paths `all-divine-seams/**` and the tag prefix `all-divine-seams-v`.

- [ ] **Step 1: Build** `node tools/build.mjs`, then `node --test tests/` → all pass.
- [ ] **Step 2: Build the APK:** `VERSION_CODE=1 VERSION_NAME=0.1.0 OFFLINE_TOOLS=… bash tools/build-apk-offline.sh out/between-the-rooms-0.1.0.apk` → `signed and verified (v2=true)`.
- [ ] **Step 3: Verify with androguard:** the package and version are as above; there are no permissions; the bundled `assets/index.html` is identical to `web/index.html`.
- [ ] **Step 4: Publish the artifact** from `node tools/build.mjs --page <scratch>/seams-page.html`. This is a new artifact; Tactics' artifact is left alone.
- [ ] **Step 5: Write the README:** how to play, the controls, the build, tests and playtest commands, and the milestone list.
- [ ] **Step 6: Commit, push, and open a draft PR** for the branch (or update PR #1 if the session can only push there), with the spec, the plan, the test results and the APK verification in the body.
