# The Bilibara Stretch (backgrounds and lighting) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and light the first stretch of Bilibara as one place Abarax can walk from the first shrine site to the Tanneries yard, with a backdrop so the picture never ends at a wall top, and no new game systems.

**Architecture:** One region scene, `world/bilibara/bilibara.tscn`, made once by `tools/world/build_region.gd` from `world/bilibara/layout.txt`. The builder gains five small commands (`ground`, `block`, `water`, `vat`, `fill`) and two options; the new ground is three generated textures; the building fronts, props and backdrop are pieces of the Kenney kit already licensed. Everything the camera cannot see round is decided by the fixed camera's geometry (Facts), and tests hold that geometry.

**Tech Stack:** Godot 4.7.2, typed GDScript, the project's own test runner (`tools/test.sh`), the region builder, `tools/art/make_textures.gd`, `tools/assets/import_kenney.py`.

**Spec:** `docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md` (sections 2.2, 3.1, 3.4, 3.5, 3.6, 6, 9: this is the environment half of F3).

## The book's Bilibara (what the implementers build)

The repository holds the book's places in the two earlier games' data (there is no separate lore or script folder). What it says, with paths:

- `all-divine-tactics/web/index.html:5`: "One dark visual world: the Tanneries at night, rose-gold trim." Line 11606, the node text: "The northern city that never sleeps but does get cold. Neon on Beaux-Arts stone, roses on every lamppost." Line 11901: "Pink neon across baroque stonework, gold neon up wrought-iron balconies, and roses swallowing every lamppost, absurd for a city this far north."
- `index.html:12357` and map at 12370: chapter 3, "The Tanneries, Tuesday, 11:40 in the morning": `biome: 'city', weather: 'snow'` with **no** `night` flag. Chapter 6 (12592): "The Tanneries market square, the night of the rally", night and snow. Chapters 1 and 3 are on **Rue Caillou** and at the **Lazyman's** (a café with a pink neon sign, 6768-6790: `BG.lazymans`); Abarax's flat is "five floors up in the Tanneries" (12260). The skyline drawn behind the Tanneries is mansard roofs in `#262a4a` and `#181a34` under a `#0e1230` to `#3a3a6a` sky (6768-6773).
- `all-divine-seams/src/data/regions.js:11-15` (the five depths): Rue Caillou (`city`, night, "A week after his brother left"), The Harbor ("Behind the sardine cannery"), Under Bilibara (sewers), **The Tanneries** (`interior`, day, ambient 2, "Tuesday, 11:40 in the morning"), **The Tanneries Yard** (`city`, `night: false`, ambient 3, "Where the Hand collects").
- `seams/src/data/lore.js:34,42-44`: "The First Knuckle. Every debt in Bilibara is paid to him in the end." / "Tuesday, eleven forty in the morning, and the vats were already full of things that were not hides." / "Where the Hand collects. Nobody owes the First Knuckle once; they owe him every week after."
- `seams/src/data/templates.js:85-98,519-532`: rooms called "Tannery vats", "Drying racks", "Lamplit square", "Behind the Lazyman's" (the start room), "Lamp and a chair" and "Campfire under the bridge" (the rest rooms), "The seam in the wall"; the boss room "The Tanneries Yard" is 13 x 8 with two pairs of vats (`vv`) as cover.
- `docs/superpowers/specs/2026-10-19-between-the-rooms-design.md:557-566` and `plans/2026-10-19-between-the-rooms-m1-rulings.md:38`: First Knuckle's arena is "the Tanneries yard (15x10, two vats as cover)"; "Call the Hand: two Street Toughs enter from the doors", "the arena's doors are barred and the toughs come in at the door mouths"; `seams/README.md:43`: "Depth 5's gate opens onto the Tanneries yard".
- `seams/src/data/looks.js`: the Hand's Knuckles wear pale wraps; First Knuckle is tall, white-haired, in a pale robe (`#c8d0e8`).

So the place is a snowy northern city of Beaux-Arts fronts and wrought iron on a cobbled street (Caillou is "pebble"), a café with pink neon, a harbor behind it, and, further in, the Tanneries: wooden works, vats and drying racks, and a yard where the Hand collects. Its light in the book is **a cold, overcast snow-noon** (chapter 3, depths 4 and 5), with warm and neon accents; the night belongs to the training yard and chapters 1 and 6. The book gives no sizes: the 15 x 10 and 13 x 8 are tiles of the older games, kept here as proportions (the yard is 25 x 20 m). No cinematic or lore file describes the yard further; where this plan adds, it says so.

> **Built in a lane.** This plan is built in its own git worktree beside other lanes (combat, enemies, menus, cutscenes),
> under the lane rules in this plan's workspace (`lanes.md`): the lane never pushes; STATE.md's Done lines and the owner's
> checklist items are given in each task's report and applied by the controller at the merge; the render suite is run as
> `TEST_TIMEOUT=3600 tools/test.sh --render`, because the machine is shared. The debug key for entering the stretch is
> **F2** (F10 belongs to the cutscene lane's fixture scene).

## Global Constraints

- Everything lives in `all-divine/`. Paths below are under it unless they start with `docs/`.
- **The picture is 640 x 360**, scaled up by whole numbers, nearest neighbour (spec 3.1). The camera is orthographic, pitched -40 degrees, never turned (`CameraRig.PITCH_DEG`, `YAW_DEG`, `DISTANCE`, `ORTHO_SIZE`).
- **32 texels per metre** on every ground, wall and prop (spec 3.4): ground plates use `toon_world` with `world_uv` and `texels_per_metre = 32`; Kenney pieces stand at x2.5 with the colormap.
- Assets are free and openly licensed, or made by a tool in the repo (spec 3.3). Nothing is downloaded but pieces of the already-taken Kenney Fantasy Town Kit 2.0 (CC0). Every file under `assets/` has a row in `ASSETS.md`; the existing rows (`assets/env/kenney_town/`, `assets/env/textures/`) cover every file this plan adds, so `ASSETS.md` needs no new row (`tests/tools/test_ledger.gd` proves it).
- Content is data (spec 2.2): the place is a layout text and a built scene; lights, colours and the grade are data (`data/render/grades/bilibara_noon.tres`).
- Frames are 1/60 s physics ticks. Green runs print no `ERROR:` or `WARNING:` lines (error paths are asserted through `quietly()`).
- **The look's preconditions** (`render/shaders/display_colour.gdshaderinc`): the region's Environment has the linear tonemapper at exposure 1, no glow, SSAO, SSIL, SDFGI, adjustments, fog or volumetric fog (the screen look has its own fog).
- **Performance (spec 3.6):** 60 fps at 1920 x 1080 on a GTX 1060 / RX 580 class machine. The container has no GPU, so the budget is held by proxies, measured in Task 5: the physics step takes at most 2.0 ms on average over 600 frames (as `tests/perf/test_frame_budget.gd`); at most 450 draw calls and 400,000 primitives in any frame from the 12 reference viewpoints; at most 2,000 meshes, 24 lamps and 2 shadow-casting lamps in the scene; no mesh reached by more than 6 lamps. The owner's F3 overlay on the PC is the last check.
- Commit messages start `All-Divine F3: `, end with the attribution trailers the session specifies, and never name a model. Commit the `.uid` files Godot makes for new scripts.
- Probes and scratch files live in the session's scratchpad, never in the project tree. `out/` is git-ignored: shots go to `out/shots/`.
- Frames are for looking: a task's "look at it" step renders PNGs at 640 x 360, **the implementer reads each one** (the Read tool shows an image) and says in the commit what was wrong and fixed; the owner will be shown the Task 5 sheet.

## Review Focus

Five conditions the tasks' main tests would not reach on their own, most likely to hurt a player first:

1. **The camera's blind side.** A tall thing south of a body, in its column, hides it: a wall, a roof, a gate. Every place Abarax or a Knuckle can stand is checked against every piece of dressing: nothing above the line of sight between the camera and a head. Tests in Tasks 2 (the edges) and 3 (all dressing).
2. **The picture's edge.** From anywhere a camera can be, including the look-ahead and the lock-on's lean (3.8 m), no pixel of the picture is background: the picture never ends at a wall top or shows haze where a street should be. Test in Task 3.
3. **A body lost on its ground.** Abarax (rose, pale skin) and a tier III Knuckle (the darkest coat) must read on cobble, earth and slate, in a lamp's pool and out of it, at the same brightness everywhere. Test in Task 4.
4. **A leak at a corner, a junction or the gate.** The walkable set, found by flood fill with the body's own capsule, touches no void; the closed gate is a long way round, not a short cut; a shove, a dash-step, a lunge and a tier III body are all held, at every kind of edge (kerb, low wall, tall block, pillar post, gate). Tests in Task 2.
5. **Lights past the engine's limits.** The container (and the web build) draw in Compatibility, which lights a mesh with at most 8 omni lights and drops the rest, popping as a body walks. No mesh may be reached by more than 6 lamps and no point by more than 2 shadow-casting ones; the draw cost stays inside the budget. Tests in Tasks 4 and 5.

## Decisions this plan makes where the spec leaves room

- **One region, not several joined by doorways.** The shortcut loop must be walkable from its far side and seen from both ends as one place; there is no area-streaming or door system in this lane; the builder writes one scene; the camera shows 20 x 17.5 m of it at a time, so what is out of view costs only the frustum cull (Task 5 measures it). The places are separate groups with separate sealed edges, so the world lane can split the scene into streamed areas later by cutting at the lane mouths (`StreetEast`, `LaneMid`, `YardEntry`).
- **The light is the book's cold snow-noon, not night.** Overcast, flat: a cool ambient does most of the work and the sun is a gentle key (so shade is at least 70% as bright as sun, which keeps a body's ground even). Warm rose-gold lamps mark the places of rest and light the ground only. Bodies are lit by a bodies-only `Fill` light, as the training yard's moon does, so they are the same brightness on every ground.
- **The street runs east-west and its south side is low.** The camera is south of everything and looks north: a wall south of a body hides it. So every south-facing edge of walkable ground is the training yard's 0.3 m slate kerb (or a 1.25 m low wall, or the 1 m gate); tall masses stand north of the ground they flank, or at least 9 m south of it; beyond a south kerb lie unwalkable dressed ground and the harbor, kept under the line of sight.
- **The yard is 25 x 20 m** (10 x 8 of the kit's 2.5 m tiles, the older yard's proportions), entered from the south through the lane, with three barred doors in its north wall (the east and west walls are edge-on to the camera and would show nothing), two vats as cover, `KnuckleSpawn` and `HandDoor_1..3` markers. It is a plain `Region`, not an `Arena`: the boss lane attaches its fight.
- **The shortcut gate is low (1 m)** and closes the south end of the loop lane in the street's north row, so it never hides a body walking toward it from the far side, and from the street it reads as a closed gate in a tall front.
- **Lamps light the world only** (the layout's `lamps ... world`). The yard's lanterns light bodies too; in a daylit place that would make the bodies brighter in every pool.

## Facts the tasks rely on (read from the code, 2026-11-11)

- **The camera.** `CameraRig`: orthographic, pitch -40 degrees, yaw 0, `DISTANCE` 20 m, `ORTHO_SIZE` = 362/32 = 11.31 m. The picture shows 20 m across and 11.25 m up the screen: on the ground, 20 m wide and 11.25/sin 40 = 17.5 m deep, centred on the target, which sits 15.32 m south of the camera and 12.86 m below it. Extra reach from the follow: look-ahead 0.8 m plus lock-on lean 3.0 m = 3.8 m. The line from a head at height 2.0 m to the camera rises 0.709 m per metre going south: **a thing s metres south of a body, in its column (x within the body's 0.35 m radius), is clear of it if its top is at most `1.7 + 0.71 s` m** (0.3 m margin). A 7.83 m top (three storeys and a flat roof) must therefore be at least 8.6 m south of any ground in its column.
- **Edge-on faces.** The camera is orthographic and due north-facing: east, west and north faces are never drawn. A building mass shows its south face and its top only; a wall running north-south shows as a strip of top. So a `block` builds a south face and a roof, nothing else.
- **The kit.** Pieces are 1 x 1 tile modelled and scaled x2.5: a 2.5 m tile, a 2.5 m storey, a slab 0.25 m thick on one tile edge (`wall`, `wall-door`, `wall-window-*`, `wall-wood*`, `balcony-wall`, `poles*`: slab at local x 0.4 to 0.5), `roof-flat` 0.33 m high, `roof` 1.6 m, `roof-high` 2.9 m, `fence-gate` 1.0 m (read from the pack's glb bounds). The pack is cached at `all-divine/.cache/` in the main checkout only: **a lane's worktree has no `.cache`**; run `python3 -I tools/assets/fetch.py fetch kenney_town` (hash-checked) before `import_kenney.py`.
- **The builder** (650 lines): `floor` is one box centred on the origin; `edge` runs along x or z in whole 2.5 m tiles; `curb` is a solid box "as seen"; `_local_box` loads and frees a piece every call (a cache is needed at this scale); `lantern` needs a `lamps` line first; nothing sets a light's cull mask but `moon`. The built scene is the source afterwards (STATE.md): this plan rebuilds it from the layout at every task and stops at Task 5.
- **Bodies.** Capsule radius 0.35 m; jog 5.5 m/s, sprint 8.5; the training yard's tests (`tests/world/test_training_yard.gd`) shove at walls, hold a dash-step, a lunge and a tier III body at its kerb: this lane's tests copy those methods.
- **Compatibility** draws the container's renders and the web build; Forward+ is the PC's reference. `project.godot` sets no light limits, so Compatibility's default of 8 omni lights per mesh holds.
- **Test conventions:** `extends TestCase`, `track()`, `frames(n)`, `quietly()`, `assert_near`; render tests live in `tests/render/` and run with `--render` (about 15 minutes in all: run `--filter=` subsets in a task, the whole once at the end).

## The stretch at a glance

x east, z south, metres; one cell below is 5 m (the camera looks up the page). Everything is flat (y = 0): stairs and slopes are proven in the courtyard and not needed.

```
        x=-40            -20             0            20          40
 z=-75   .  .  .  .  .  .  .  .  .  .  .  Y  Y  Y  Y  Y      Y   the Tanneries yard 25 x 20 m, x 15..40, z -75..-55
 z=-55   .  .  .  .  .  .  .  .  .  .  .  .  .  L  .  .      L   the Tanneries lane, 5 m wide, x 25..30, z -55..-5
 z=-40   .  .  .  .  .  .  .  .  .  .  .  .  .  L  B  .      B   alcove B, x 30..37.5, z -37.5..-30: shrine site B
 z=-25   .  R  R  R  R  R  R  R  R  R  R  R  R  L  .  .      R   the Rack Walk, z -25..-20, x -35..25 (east end joins the lane)
 z=-20   .  l  d  d  d  d  d  d  d  d  d  d  d  L  .  .      l   the loop lane, x -35..-30, z -20..-5;  d = drying yard (dressed, unwalkable)
 z=-10   .  l  .  .  .  .  .  .  .  .  .  .  .  L  .  .
 z=-5    G  .                                      L          G = the shortcut gate (x -35..-30, z -5): the loop's far side
 z=-5..5 A  A  s  s  s  s  s  s  s  s  s  s  s  s  .          A = court A (shrine site A), s = Rue Caillou, x -30..32.5
 z=5..9  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~  ~          the harbor: apron, quay wall, water (dressed, unwalkable)
```

| Place | Rectangle (x0 x1 z0 z1) | Ground | Edges |
|---|---|---|---|
| W1 Court A, "Behind the Lazyman's" (shrine site A, `Spawn`) | -40..-30, -5..5 | slate | N: the Lazyman's back (tall); W: tall cap; S: kerb |
| W2 Rue Caillou | -30..32.5, -5..5 | cobble | N: tall row with the lane mouth (x 25..30) and the gate slot (x -35..-30); E: tall cap; S: kerb, harbor beyond |
| W3 Tanneries lane | 25..30, -55..-5 | tan earth | flanks low (1.25 m) where they stand south of other ground, tall elsewhere (Task 2's table) |
| W4 Rack Walk | -35..25, -25..-20 | tan earth | N: tall works; S: kerb (x -30..22.5), low wall (x 22.5..25); the drying yard beyond |
| W5 Loop lane | -35..-30, -20..-5 | tan earth | W: tall; E: low wall; S end: the gate (1 m) |
| W6 Alcove B, "Lamp and a chair" (shrine site B) | 30..37.5, -37.5..-30 | slate | N, E: tall; S: kerb (x 32.5..37.5), low wall (x 30..32.5) |
| W7 The Tanneries yard | 15..40, -75..-55 | tan earth | N, E, W tall (E, W two storeys); S: kerb x 15..22.5 and 32.5..40, low walls x 22.5..25 and 30..32.5, a 5 m open mouth (x 25..30) with a pillar post each side |

Walkable area 1,906.25 m² (100 + 625 + 250 + 300 + 75 + 56.25 + 500). The way from `ShrineSite_A` to `YardCentre` is about 62 (the street) + 50 (the lane) + 10 (the yard) = 122 m: about 25 s at a jog, so the stretch's 20 to 30 minutes are fights and looking, which later lanes fill. The loop (the lane to the Rack Walk, west along it, south down the loop lane to the gate) is about 155 m from the street's east end round to a gate 3 m from where it began, shut.

## Not in this plan (and who owns it)

- **Shrines** (the Rose shrine object, resting, levelling, travel), **petals and the corpse run**, **saves and world memory** (the gate opening and staying open): the world lane. This plan puts `ShrineSite_A/B`, `ShrinePlinth_A/B`, `ShortcutGate`, `GateNear`, `GateFar` in the scene and nothing behind them.
- **Enemies and their placement** (the 3-4 types, the Hand's Pack gank squad and its secret weakness, `EnemySpawn_*` markers), **the mini-boss**: the enemy lanes. The stretch has no `EnemySpawn_*` marker on purpose.
- **First Knuckle** (phases, perilous attacks, the fog gate that shuts at `YardGate`, "Call the Hand" at `HandDoor_1..3`), **his entrance and every cutscene**: F4 and F5.
- **Weather particles** (the book's snow), **music and ambience, neon as emissive light, roses on lampposts, doors that open, interiors, townsfolk and the Garden's folk**: later polish and art; the snow is carried by the ground textures and the grade.
- **Stairs, terraces and slopes** in this stretch; **area streaming**.
- The owner's PC comparison of Forward+ against the container's Compatibility.

## Working in a lane

This plan is built in its own worktree beside lanes that change combat, enemies and UI. **Do not touch:** `combat/`, `actors/`, `moves/`, `hud/`, `fx/`, `render/` (shaders, grade profile, pixel stage), `core/`, `data/arena/waves.tres`, `data/actors/`, `data/moves/`, `data/palettes/`, `data/tuning/`, `world/arena*.gd`, `world/region.gd`, `world/courtyard/`, `world/training_yard/`, `assets/anim/`, `assets/characters/`, `assets/audio/`, `project.godot`, `STATE.md`.

**Changed by addition only** (the controller merges): `tools/world/build_region.gd` (new commands and options; every old layout builds the same scene, Task 1 proves it), `tools/art/make_textures.gd` (three more textures), `tools/assets/kenney_town_pieces.txt` (17 names), `assets/env/kenney_town/` and `assets/env/textures/` (new files), `main/main.gd` (a constant, `enter_stretch()` and F2; F5 still toggles yard and courtyard) with `tests/main/test_main.gd`. `ASSETS.md` needs no row; if `test_ledger` disagrees, add rows only. `STATE.md`: do not edit it in the lane; each task's commit step gives the lines for the controller.

New files: `world/bilibara/{layout.txt,bilibara.tscn}`, `world/materials/{cobble,tan_earth,snow,liquor}.tres`, `data/render/grades/bilibara_noon.tres`, `tests/support/route_brain.gd`, and the tests named below.

---

### Task 1: The builder learns the stretch's words, and three ground textures

**Files:**
- Modify: `tools/world/build_region.gd`, `tools/art/make_textures.gd`, `tools/assets/kenney_town_pieces.txt`
- Create: `assets/env/textures/{cobble,tan_earth,snow}.png` (made by the tool), `world/materials/{cobble,tan_earth,snow,liquor}.tres`, the 17 new `assets/env/kenney_town/*.glb` (imported)
- Test: `tests/world/test_bilibara_textures.gd`, `tests/world/test_build_region.gd`

**Interfaces:**
- Consumes: the builder's `Builder` class, `FLAGSTONE`/`STONES`, `_edge`, `_curb`, `_piece`, `_moon`, `_share_the_bodies`; `MAKE_TEXTURES.flagstone()`, `_split`.
- Produces:
  - **Layout grammar** (one command a line, as the courtyard's header explains):
    - `ground X0 Z0 X1 Z1 STONE [visual]`: a box 1 m thick with its top at y = 0, in `STONE`, each side at most 12.5 m (a longer one is a problem). Without `visual` it is on `world` and `ik_surface`, in the node group `Walkable`. With `visual` it has no collider and is in the group `Backdrop`. `STONE` is one of `flagstone`, `slate`, `cobble`, `tan_earth`, `snow` (and `curb` takes the same five).
    - `block X0 Z0 X1 Z1 STOREYS STYLE ROOF [solid]`: a building mass over the rectangle (whole 2.5 m tiles, STOREYS 1 to 5). Its **south face** is a run of pieces on the line z = Z1, STOREYS storeys high, the pieces chosen by STYLE and the tile's index from the west end; its **roof** is one piece per tile of the footprint at y = STOREYS x 2.5. `solid`: one collision box over the footprint (the whole height) on `world` and `ik_surface`, nodes in the group `Blocks`, casting shadows. Without `solid`: no collider, nodes in `Backdrop`, `cast_shadow` off.
    - `water X0 Z0 X1 Z1 Y [liquor]`: a thin plane at height Y (no collider, group `Backdrop`) in `kenney_water.tres`, or with `liquor` in `liquor.tres`.
    - `vat X Z`: a 2.5 x 2.5 m slate box 1.0 m high, solid as seen, with a liquor top 2.1 x 2.1 m at y = 1.01.
    - `fill PITCH YAW COLOUR ENERGY`: the bodies-only directional light of `moon` (cull mask `RENDER_BODIES`, no shadows), named `Fill`; `_share_the_bodies` makes the sun leave the bodies to a `Moon` **or** a `Fill`.
    - `lamps COLOUR RANGE ENERGY UP [world]`: with `world`, each lantern's lamp has `light_cull_mask = RENDER_WORLD`.
  - **Styles** (pieces by storey, cycled by tile index): `frontage`: ground `wall-door, wall, wall-window-small, wall, wall-window-small, wall`, upper `wall-window-shutters, wall-window-shutters, wall, balcony-wall`; `tannery`: ground `wall-wood-door, wall-wood, wall-wood, wall-wood-window-small`, upper `wall-wood-window-shutters, wall-wood, wall-wood-window-small, wall-wood`; `shed`: `wall-wood`; `plain`: `wall`. **Roofs:** `flat` = `roof-flat`; `slope` = `roof` and `high` = `roof-high`, laid in rows that fall toward the south (the camera), the ridge on each row's north edge.
  - **Pieces added** (all from the pack already ledgered): `wall-window-shutters, wall-window-small, balcony-wall, wall-wood, wall-wood-door, wall-wood-window-shutters, wall-wood-window-small, roof, roof-flat, roof-high, chimney, poles, poles-horizontal, planks, fence-gate, pillar-wood, rock-large`. Collision when placed with `piece`: `planks` and `chimney` none, `pillar-wood` post, the rest box.
  - **Textures** (`MAKE_TEXTURES`, all 64 x 64 = 2 m, seeded, the same bytes every run): `cobble()` with `COBBLES` = `Color8(72,70,80)`, `(80,78,88)`, `(64,63,74)`, `(86,82,90)`, `SNOW_JOINT = Color8(176,186,198)`, `COBBLE_SEED = 13`: rows of cobbles 10 to 14 texels high and 9 to 15 long laid like the flagstones (a one-texel joint under each row and at each cobble's end, `_split` for the sizes); `tan_earth()` with `EARTHS` = `Color8(86,72,60)`, `(94,80,66)`, `(78,66,56)`, `LIME = Color8(124,114,100)`, `EARTH_SEED = 17`: blotches 4 to 8 texels across, a lattice that wraps, one earth each, 2 to 8% of the texels lime; `snow()` with `SNOWS` = `Color8(228,234,242)`, `(214,222,234)`, `SNOW_SEED = 19`, 10% speckle. These colours are **first values**: Task 4 may change them (and only them) to meet its measured band; the tests here hold structure and ranges.
  - **Materials** `cobble`, `tan_earth`, `snow` as `slate.tres` is (toon_world, `world_uv`, 32 texels per metre); `liquor.tres`: toon_world, a 1 x 1 gradient of `#4a3a2e`, `world_uv` false.
  - `_local_box` caches by piece name.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/world/test_bilibara_textures.gd   (the shape of test_flagstone.gd and test_slate.gd)
func test_cobble_is_a_2_m_tile_of_four_cobbles_with_snow_in_the_joints() -> void:
	# 64 x 64; exactly 5 colours: COBBLES (value 0.22..0.42, blue >= red) and SNOW_JOINT (value >= 0.6); joints 8..25% of the texels; each cobble colour > 64 texels
func test_cobble_joints_are_one_texel_wide_across_the_edges() -> void:
	# no two full joint rows touch (wrapping); no two joint texels side by side along a row (wrapping)
func test_cobble_is_made_the_same_every_time_and_has_its_material() -> void:
	# two makes equal; the committed png equals the make; world/materials/cobble.tres: toon_world, world_uv, 32
func test_tan_earth_is_three_earths_with_lime_stains_that_wrap() -> void:
	# 64 x 64; exactly 4 colours: EARTHS (warm: r > g > b, value 0.25..0.45) and LIME; lime 2..8% of texels; each earth > 1/8; the seam between column 63 and column 0 has no more colour changes than 1.5 x the average between neighbouring columns (same for rows)
func test_tan_earth_is_made_the_same_every_time_and_has_its_material() -> void:
func test_snow_is_two_whites_and_has_its_material() -> void:
	# 64 x 64; 2 colours, both value >= 0.85, the second 5..15% of texels; same every make; material
func test_liquor_is_a_dark_brown_flat_material() -> void:
	# liquor.tres: toon_world, world_uv false, albedo #4a3a2e, value <= 0.35

# tests/world/test_build_region.gd   (Builder.new().build(text, "T") on small layouts; problems through quietly())
func test_ground_is_a_box_with_its_top_at_zero_on_world_and_feet_and_walkable() -> void:
	# `ground 0 0 10 10 cobble`: collision_layer WORLD | IK_SURFACE, top y 0, thickness 1.0, group Walkable, material cobble, world_uv, 32
func test_a_ground_wider_than_12_5_m_is_a_problem() -> void:
	# `ground 0 0 12.5 10 slate` is fine; `ground 0 0 15 10 slate` is one problem naming the line
func test_visual_ground_has_no_collider_and_is_backdrop() -> void:
func test_a_block_stacks_its_front_by_storeys_and_roofs_its_footprint() -> void:
	# `block 0 0 10 5 3 frontage flat`: 4 tiles x 3 storeys = 12 front pieces at y = 0, 2.5, 5.0, all x2.5 with the colormap; 4 x 2 = 8 `roof-flat` at y = 7.5; the front's face is on z = 5
func test_a_solid_block_has_one_box_over_its_footprint_and_casts_shadows() -> void:
	# collision box 10 x 7.5 x 5 on WORLD | IK_SURFACE, group Blocks; non-solid: no collider, group Backdrop, cast_shadow OFF on every mesh
func test_a_block_that_is_not_whole_tiles_or_has_an_unknown_style_or_roof_is_a_problem() -> void:
func test_a_slope_roof_is_higher_at_its_north_edge() -> void:
	# `block 0 0 5 5 1 plain slope`: a ray down 0.5 m north of a roof tile's centre meets the mesh >= 0.2 m higher than one 0.5 m south of it
func test_a_vat_is_a_one_metre_solid_with_a_liquor_top() -> void:
func test_fill_is_a_bodies_only_light_called_fill_and_the_sun_leaves_the_bodies_to_it() -> void:
	# cull mask RENDER_BODIES, no shadow; with a sun the sun's mask excludes RENDER_BODIES; with only a `moon` it still does
func test_lamps_world_lights_only_the_world() -> void:
	# `lamps #ffb98a 6 0.5 3.45 world` + a lantern: the lamp's cull mask is RENDER_WORLD
func test_the_old_layouts_still_build_the_same_scenes() -> void:
	# build world/courtyard/layout.txt and world/training_yard/layout.txt into user://; the node trees (names, types, transforms, light settings) equal the committed scenes'
```

- [ ] **Step 2: Run** `tools/test.sh --filter=tests/world`. Expected: FAIL (no such commands, textures or materials).
- [ ] **Step 3: Build.**
  - The pack is already in the asset cache (a lane's `.cache` is a link to the shared one): fetch it (`python3 -I tools/assets/fetch.py fetch kenney_town`) only if `import_kenney.py` reports it missing. Add the 17 names to `kenney_town_pieces.txt`, run `python3 -I tools/assets/import_kenney.py` and `tools/godot.sh --import`.
  - Add the textures and run `tools/godot.sh -s res://tools/art/make_textures.gd`; write the four materials; `tools/godot.sh --import`.
  - Add the commands and options. The builder may grow past 800 lines: if it does, the new commands go in `tools/world/region_blocks.gd` as a helper class the builder calls.
  - Yaw for `slope`/`high` roofs and for the south faces is found by looking, not guessing: that is Step 4.
- [ ] **Step 4: Look at it.** In the scratchpad, build a scratch layout with every new piece in a row, one `block` of each style with each roof, and a `ground` of each stone, and render it from the game camera's angle (pitch -40, orthographic, 640 x 360). Read the PNG. Check: south faces face the camera, roofs fall toward it, each ground reads as stone, the cobble's snow joints show. Fix yaws and the textures' proportions (not their colours) until they do.
- [ ] **Step 5: Run** `tools/test.sh --filter=tests/world`, then `tools/test.sh --filter=tests/tools` (the ledger), then `tools/test.sh`. Expected: all pass, no `ERROR:` or `WARNING:` lines.
- [ ] **Step 6: Commit.** STATE.md line for the controller: "F3 Task 1 (stretch): the region builder's `ground`, `block`, `water`, `vat`, `fill` commands and the `lamps ... world` and `curb` stone options; the cobble, tan earth and snow textures (`tools/art/make_textures.gd`); 17 more pieces of the Kenney kit; old layouts build the same scenes."

---

### Task 2: The ground, the walls, the gate and the markers: a place Abarax can walk and cannot leave

**Files:**
- Create: `world/bilibara/layout.txt`, `world/bilibara/bilibara.tscn` (built), `tests/support/route_brain.gd`
- Modify: `main/main.gd`
- Test: `tests/world/test_bilibara.gd`, additions to `tests/main/test_main.gd`

**Interfaces:**
- Consumes: Task 1's grammar; `Region`; `TestCase`; the actor scene and `ABARAX`, `KNUCKLE_1`, `KNUCKLE_3` defs; `ScriptBrain`.
- Produces:
  - **The scene** `res://world/bilibara/bilibara.tscn`, root `Bilibara` (a plain `Region`, not an `Arena`), built by `tools/godot.sh -s res://tools/world/build_region.gd -- res://world/bilibara/layout.txt res://world/bilibara/bilibara.tscn`. In this task it has the ground, the solid masses (style `plain`, roof `flat`), kerbs, the gate, vats, markers, `sky #aebbcc` and a sun (`sun -60 30 #f4f7ff 0.25`); no grade yet.
  - **Ground**: the seven rectangles of the table above, each a `ground` plate split to at most 12.5 m a side, plates exactly tiling each place and never overlapping (the street is six plates of 10 m, the last 12.5). Stones: W1, W6 slate; W2 cobble; W3, W4, W5, W7 tan earth.
  - **Solid masses** (`block ... solid`, 3 storeys, style `plain`, `flat` unless noted; top 7.83 m): `T1 -40 -35 / -25 -5`, `T2 -30 25 / -10 -5`, `T3 30 32.5 / -20 -5` (lane east flank, south part), `T4 32.5 35 / -5 5`, `T5 -42.5 -40 / -5 5`, `T6 -40 25 / -45 -25`, `T7 30 40 / -45 -37.5` with `T7b 37.5 40 / -45 -30`, `T8 12.5 42.5 / -80 -75` (yard north wall), and two-storey `T9 12.5 15 / -75 -55`, `T10 40 42.5 / -75 -55` (yard west, east). Written as `X0 X1 / Z0 Z1`; the layout line order is `block X0 Z0 X1 Z1 ...`. **Low walls** (1 storey of `wall-half`, 1.25 m, thin, solid): `L1 22.5 25 / -55 -45`, `L2 30 32.5 / -55 -45`, `L3 30 32.5 / -30 -20`, `L4 22.5 25 / -20 -10`, `L5 -30 -27.5 / -20 -10` (the loop lane's east side). **Kerbs** (`curb ... 0.3 slate`, 0.4 m thick, south of the edge): street and court south `-40 5 32.5 5.4`; Rack Walk south `-30 -20 22.5 -19.6`; alcove south `32.5 -30 37.5 -29.6`; yard south `15 -55 22.5 -54.6` and `32.5 -55 40 -54.6`.
  - **The gate** (the shortcut): a solid box `-35 -5.5 -30 -4.5`, 1.2 m high, on `world` and `ik_surface`; dressed in Task 3. **Pillar posts** (`pillar-stone`) at `(24.875, -55.125)` and `(30.125, -55.125)` (the yard's mouth) and at `(-35.125, -5.1)` and `(-29.875, -5.1)` (the gate).
  - **Markers** (`Marker3D`, on the ground; yaw about +Y, 0 faces south, 90 east, 180 north, 270 west): `Spawn (-32.5, 1.25) 90`, `ShrineSite_A (-35, 0) 90`, `ShrineSite_B (35, -33.75) 270`, `StreetEast (27.5, 0) 0`, `LaneMid (27.5, -30) 0`, `RackEast (27.5, -22.5) 0`, `RackWest (-32.5, -22.5) 0`, `GateFar (-32.5, -6.5) 0`, `GateNear (-32.5, -3.5) 180`, `YardEntry (27.5, -57.5) 180`, `KnuckleSpawn (27.5, -68) 0`, `HandDoor_1 (20, -73.8) 0`, `HandDoor_2 (27.5, -73.8) 0`, `HandDoor_3 (35, -73.8) 0`. **Points of interest** (group `poi`, a `Marker3D` UP m above the ground): `ShrinePlinth_A (-35, 0) 1.0`, `ShrinePlinth_B (36.25, -33.75) 1.0`, `ShortcutGate (-32.5, -5) 1.0`, `YardGate (27.5, -55) 1.4`, `YardCentre (27.5, -65) 1.0`, `VatWest (20, -66.25) 1.0`, `VatEast (35, -66.25) 1.0`. Vats: `vat 20 -66.25` and `vat 35 -66.25`. No `EnemySpawn_*`.
  - **Clear lines**: no prop or lantern within 2 m of the street's middle (z -2..2), the lane's middle (x 26.5..28.5), the Rack Walk's middle (z -23.5..-21.5), the loop lane's middle (x -33.5..-31.5): the walking tests steer along them.
  - **`RouteBrain`** (`tests/support/route_brain.gd`, `class_name RouteBrain extends Brain`): `RouteBrain.new(waypoints: Array[Vector3])` steers straight at the first waypoint with the stick all the way and moves on to the next within 0.6 m; `done: bool`.
  - **`Main`**: `const BILIBARA := "res://world/bilibara/bilibara.tscn"`; `func enter_stretch() -> void` does what `switch_region` does with that scene; F2 calls it; F5 from the stretch goes to the yard (as it does from any region that is not the yard).

- [ ] **Step 1: Write the failing tests** in `tests/world/test_bilibara.gd` (the shape of `test_training_yard.gd` and `test_courtyard.gd`).

```gdscript
func test_the_stretch_is_a_plain_region_with_its_markers_pois_and_no_enemy_spawns() -> void:
	# a Region and not an Arena; every marker above exists as a Marker3D at its x, z (within 1e-3) and yaw (the marker's +Z); every poi is in group poi; no EnemySpawn_*
func test_ground_plates_tile_each_place_exactly() -> void:
	# the Walkable plates' rects: none overlap (intersection area 0); their union is the table's 7 rectangles, 1,906.25 m2 (within 0.01); each side <= 12.5
func test_every_ground_is_toon_world_at_32_texels_per_metre() -> void:
	# each Walkable plate: ShaderMaterial toon_world, world_uv true, 32.0; the stone is the table's for its place; tops at y = 0 (within 1e-6)
func test_the_walkable_ground_is_one_connected_sealed_set() -> void:
	# flood fill on 0.5 m cells from Spawn, a cell walkable when ik_surface is under it at y 0 and a 0.35 m capsule at 0.5 m overlaps no `world`:
	# reached cells >= 99% of 1,906.25 m2 / 0.25; every marker's cell is reached; for every reached cell and each of its 4 neighbours: reached, or a `world` collider overlaps the neighbour -- zero leaks (Review Focus 4)
func test_the_closed_gate_is_a_long_way_round() -> void:
	# GateNear and GateFar are 3.0 m apart in a straight line; the flood-fill path between them is >= 140 m (the street, the lane, the Rack Walk, the loop lane); shoved at the gate from each side for 3 s, a body stays on its side (z < -5 from the north, > -5 from the south), and does not vibrate (< 0.03 m a frame)
func test_abarax_walks_from_the_first_shrine_site_to_the_yard() -> void:
	# RouteBrain over ShrineSite_A, StreetEast, LaneMid, YardEntry, YardCentre: each leg within (leg length / 4 + 3) s, within 0.6 m, moving faster than 0.5 m/s on 90% of the frames
func test_abarax_walks_the_loop_from_its_far_side_up_to_the_gate() -> void:
	# LaneMid, RackEast, RackWest, GateFar the same way; he ends within 0.6 m of GateFar and not through the gate
func test_nobody_leaves_at_a_corner_a_junction_a_kerb_or_a_post() -> void:
	# 20 shoves (start point, direction), 120 frames at SHOVE 30, then 60 frames the other way (it walks off: >= 1.0 m): the 4 corners of the yard; both pillar posts of the yard mouth; the lane mouth's 2 corners at the street; the alcove's 3 corners; the street's two caps; the court's corner; the Rack Walk's west and east ends; the loop lane's corners; each ends inside a reached cell, y within -0.2..0.5, < 0.05 m past the capsule's reach
func test_a_big_body_is_held_in_too() -> void:
	# a tier III Knuckle at the yard's 4 corners and the alcove's 3: inside the walkable set after 60 frames of shove
func test_every_south_edge_is_a_kerb_a_low_wall_or_the_gate() -> void:
	# from every reached cell whose south neighbour is blocked, a ray south at 1.0 m (chest) for 6 m meets nothing taller than 1.3 m except a post narrower than 0.8 m; at 0.15 m (shin) it meets the kerb, a low wall or the gate; no `Barrier` node (Review Focus 1, the edges)
func test_the_kerbs_alone_hold_a_dash_step_a_lunge_and_a_shove() -> void:
	# the training yard's test (Abarax dash-stepping twice at it, the Knuckle's sweep and thrust, a 60-frame shove) at the street's kerb (x 3), the Rack Walk's (x -10) and the yard's (x 18): the centre stops 0.35 +- 0.05 m from the face, y < 0.05
# tests/main/test_main.gd, added
func test_f10_enters_the_stretch_and_f5_leaves_it_for_the_yard() -> void:
	# Main.enter_stretch(): region is Bilibara, the player is at its Spawn (within 0.01), no Arena (arena() is null), the Hud bound to none; F5 then loads the yard
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_bilibara` and `--filter=tests/main`. Expected: FAIL (no scene, no `enter_stretch`).
- [ ] **Step 3: Build.** Write `layout.txt` (a header like the training yard's: the commands, the plan above as a comment, the ASCII map) and build the scene; add `RouteBrain` and `Main.enter_stretch`/F2. Where a mass or a kerb is pinned by the tables, use them exactly; where the flood fill finds a pocket the capsule cannot enter, move the post or wall by 0.5 m rather than loosen the test.
- [ ] **Step 4: Look at it.** In the scratchpad, render the game camera (pitch -40, orthographic, 640 x 360, flat grey materials are fine) at `Spawn`, `StreetEast`, `LaneMid`, `RackWest`, `GateFar`, `YardEntry`. Read each PNG: the walls and kerbs are where the tables say, the low walls do not hide a body, the gate slot reads as an opening shut at the bottom. This is the only frame check before Task 3 dresses it.
- [ ] **Step 5: Run** `tools/test.sh --filter=tests/world`, `--filter=tests/main`, then `tools/test.sh`, then `tools/godot.sh -- --selftest` (exit 0: the game still boots into the yard). Expected: all pass.
- [ ] **Step 6: Commit.** STATE.md line: "F3 Task 2 (stretch): `world/bilibara/` is a flat 1,906 m2 place of seven walkable parts (court A, Rue Caillou, the Tanneries lane, the Rack Walk, the loop lane, alcove B, the 25 x 20 m yard) with a closed 1 m shortcut gate and every marker later lanes need; F2 enters it from the game; the walkable set is flood-filled and sealed, the loop is walkable to the gate and the gate is a 140 m way round."

---

### Task 3: The backdrop and the dressed places

**Files:**
- Modify: `world/bilibara/layout.txt`, `world/bilibara/bilibara.tscn` (rebuilt)
- Create: `tests/render/test_bilibara_view.gd`
- Test: `tests/world/test_bilibara.gd` (more), `tests/render/test_bilibara_view.gd`

**Interfaces:**
- Consumes: Task 2's scene and markers; the builder; `PixelSnap`, `CameraRig` constants.
- Produces:
  - **Fronts**: every `T*` mass takes its style and roof: `T1` frontage (the Lazyman's back: a `wall-door` and a `banner-red` as its pink neon, a `wall-window-small`; `Lazymans` poi at (-38.75, -5, 1.8 up)); `T2` frontage with shopfronts (`HatShop` poi at (-10, -5), up 1.6; two `banner-red` and one `banner-green` on its south face); `T3`, `T4`, `T5` frontage; `T6`, `T7`, `T7b`, `T8`, `T9`, `T10` tannery. All roofs `flat` on masses within 9 m south of ground in their columns (`T2`, `T6`, `T7`, `T3`), so their top is 7.83 m; the rings use `slope` and `high`.
  - **The gate**, dressed: two `fence-gate` pieces across x -35..-30 at z -5, its box 1.2 m; the two `pillar-stone` posts; poi `ShortcutGate` stays.
  - **Shrine sites as places**: site A, the slate court with a `pillar-stone` plinth at (-35, 0) and the Lazyman's back door behind it; site B, the slate alcove with a `stall-bench` at (35, -35.5), a `stall-stool` at (34, -33) and a `pillar-stone` plinth at (36.25, -33.75). The shrine object itself is not built.
  - **The yard**: three `wall-door` pieces in `T8`'s south face at x 20, 27.5, 35 (the doors, barred: no opening), three `banner-red` between them; the two vats; the mouth's pillar posts; poi `YardGate`.
  - **Street props**: `stall-red` x2 with a `stall-bench` and two `stall-stool` at the margins (z 3 to 4.4, off the clear line), a `cart`, Snow drifts (`curb ... snow`, 0.25 m high) only on unwalkable ground (the drying yard, the apron, the quay), never on a Walkable plate.
  - **The drying yard** (unwalkable, `visual` ground in `tan_earth` plates x -30..22.5, z -19.6..-10, under the line of sight): 3 `vat`s at (-20, -15), (-5, -15), (10, -15); at least 12 `poles-horizontal` and 12 `poles` in rows (racks), 6 `planks` on the ground (hides), 2 `rock-large`, `curb ... snow` drifts. Nothing there taller than `1.7 + 0.71 s` from the kerb: racks start 3 m from it.
  - **The harbor** (south): `ground ... cobble visual` plates x -40..32.5, z 5.4..9 (the apron); `edge wall-half -40 9 32.5 9 n` (the quay wall, 1.25 m); `water -45 9.25 40 32 -0.9`.
  - **The ring** (non-solid `block`s, 5 m deep rows of 10 to 20 m, 2 to 4 storeys stepping up by one storey every 5 m away from the camera, styles alternating `frontage`, `tannery`, `shed`, roofs `slope`, `high`, `flat`, `chimney` pieces only here) filling, with no gap wider than 2.5 m, the footprint `x -60..62.5, z -95..5` outside the walkable places and their solid masses and the south side's harbor; and the same on the south-of-yard works strip (x 15..22.5 and 32.5..40, z -54.6..-46: low `shed` blocks of one storey, 2 m set back from the kerbs) and east of the lane (x 32.5..45, z -29.6..-20 low `shed`s, x 32.5..45, z -20..-10 three-storey `tannery` flat). The tests are the arbiter of every height and gap.
  - **Groups**: `Backdrop` holds every non-solid mass, visual ground, water and chimney; `Blocks` the solid masses.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/world/test_bilibara.gd, added
func test_nothing_stands_between_the_camera_and_a_body_anywhere_it_can_stand() -> void:   # Review Focus 1
	# for every reached 0.5 m cell and the x offsets -0.35, 0, +0.35: the segment from the head (cell + 2.0 m up) to the camera (cell + (0, 12.86, 15.32)) meets no mesh AABB under Blocks, Backdrop, Props, Edges, Lanterns, except a mesh narrower than 0.8 m in x (a post or a pillar) and the ground plates; the failure message names the mesh and the cell
func test_the_backdrop_is_never_walkable_and_never_shades_the_ground() -> void:
	# nothing under Backdrop is a CollisionObject; every mesh under it has cast_shadow OFF; Blocks has no Backdrop children
func test_the_places_are_dressed() -> void:
	# poi Lazymans, HatShop exist; site A: a pillar-stone within 0.3 m of ShrinePlinth_A and a wall-door within 4 m of Lazymans; site B: >= 1 stall-bench, >= 1 stall-stool and a pillar-stone near ShrinePlinth_B; >= 2 stall-red, >= 1 cart, >= 3 banners in the street and yard
func test_the_gate_is_a_closed_low_shortcut_gate() -> void:
	# two fence-gate pieces across x -35..-30 at z -5 (within 0.3 m); a solid body 5 m wide, 1.0..1.3 m high; two pillar-stone posts; GateNear 3 m south, GateFar 3 m north; nothing taller than 1.3 m within 3 m north of it except the posts
func test_the_yard_has_three_barred_doors_two_vats_and_a_mouth() -> void:
	# a wall-door within 0.6 m of each HandDoor_k's x and on the wall's face; vats at VatWest and VatEast, each solid and 1.0 m high; two pillar posts 5.25 m apart at the mouth; KnuckleSpawn inside the walls, facing south
func test_the_drying_yard_and_the_harbor_are_dressed_and_unwalkable() -> void:
	# >= 12 poles-horizontal, >= 12 poles, >= 6 planks, 3 vats south of the Rack Walk's kerb; water at y -0.9 from z 9.25 to 32; none of it in a Walkable group, none reached by the flood fill
func test_every_piece_is_a_kenney_toon_piece_at_two_and_a_half_times() -> void:
	# as test_courtyard's: scale 2.5, toon_world with the colormap, for every instance under the region
# tests/render/test_bilibara_view.gd   (--render; the bare camera, a 642 x 362 SubViewport)
func test_the_picture_never_shows_the_void_from_any_walkable_point() -> void:   # Review Focus 2
	# ~120 viewpoints: every 5 m along the boundary of the flood-fill set; the camera a Camera3D built from CameraRig's PITCH_DEG, DISTANCE and ORTHO_SIZE, its target 3.8 m outside the boundary's normal; background colour #ff00ff; zero pixels with r > 0.95, b > 0.95, g < 0.05
func test_nine_views_are_saved_for_a_person_to_look_at() -> void:
	# out/shots/bilibara/<name>.png at 640 x 360 for Spawn, StreetEast, LaneMid, ShrineSite_B, RackWest, GateFar, GateNear, YardEntry, YardCentre; each a real picture (> 40 colours in a 3-px sample)
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_bilibara` and `tools/test.sh --render --filter=test_bilibara_view`. Expected: FAIL.
- [ ] **Step 3: Build** the layout's dressing and ring, rebuild the scene. The sight-line test names what to lower or move; do not exempt a mesh.
- [ ] **Step 4: Look at it.** Run the render test; read all nine PNGs and the ten worst viewpoints from the void test (save the three with the most background pixels while it fails). Check: the picture never ends at a wall top; the harbor reads as water; the gate reads as a low closed gate in a tall front; the yard reads as a walled yard with doors and vats; the lane reads as a canyon of roofs. Note what looks flat or crowded for the owner.
- [ ] **Step 5: Run** `tools/test.sh --filter=tests/world`, `tools/test.sh --render --filter=test_bilibara`, then `tools/test.sh`.
- [ ] **Step 6: Commit.** STATE.md line: "F3 Task 3 (stretch): the backdrop and the dressed places: building fronts of the kit (Beaux-Arts frontage, wooden tannery works) on every tall edge, a ring of roofs 15 m deep on three sides, the harbor to the south, the Lazyman's back, the gate with its fence-gate and posts, the drying yard with vats and racks, the yard's three barred doors and two vats; nothing stands between the camera and a body anywhere (a mesh-by-mesh sight-line test), and the picture never shows background from any of about 120 camera points." Owner-checklist item: "Walk Rue Caillou, the lane, the Rack Walk and the loop to the gate: does it look like the book's Bilibara (pink neon, stone, wood, snow), and does the picture ever end at a wall top?"

---

### Task 4: The snow-noon light, and bodies that read on every ground

**Files:**
- Modify: `world/bilibara/layout.txt`, `world/bilibara/bilibara.tscn` (rebuilt), and, within Task 1's ranges, `tools/art/make_textures.gd` colours (and the committed pngs)
- Create: `data/render/grades/bilibara_noon.tres`, `tests/render/test_bilibara_readability.gd`
- Test: `tests/world/test_bilibara.gd` (more), `tests/render/test_bilibara_readability.gd`

**Interfaces:**
- Consumes: Tasks 1 to 3; `GradeProfile`; `ShotMasks.silhouette` and `diff`; `Main.enter_stretch`; the actor defs.
- Produces (the layout's light lines, the grade, all data):
  - `sky #aebbcc` (the background; equal to the grade's fog colour, so any distant thing fades into the haze).
  - `ambient #bccadf 0.62` (a cool, soft sky light: blue at least red; the energy times the colour's red under 0.5).
  - `sun -60 30 #f4f7ff 0.25` (shadows on; a gentle key: the ratio (ambient + 0.35 x sun) / (ambient + sun), analytic over the toon shader's lowest step, is at least 0.7).
  - `fill -40 20 #f4f7ff 1.1` (bodies only, no shadows, cool, from the camera's side and above; energy within 1.0 to 1.3 as the training yard's moon; the sun leaves bodies to it).
  - `lamps #ffb98a 6 0.5 3.45 world` and **18 lanterns**, two with shadows: court A `(-36.5, -3.5) shadow` ("ShrineLampA") and `(-32.5, 3.5)`; the street `(-20, -4.3)`, `(-5, -4.3)`, `(10, -4.3)`, `(22, -4.3)`; the lane `(25.6, -15)`, `(29.4, -45)`; alcove B `(36, -36) shadow` ("ShrineLampB") and `(31, -31.5)`; the Rack Walk `(-20, -24.3)`, `(-2, -24.3)`, `(15, -24.3)`; the loop lane `(-34.4, -12)`; the yard `(17, -72)`, `(38, -72)`, `(24.2, -56.5)`, `(30.8, -56.5)`. The two shadowed lanterns are 60 m or more apart. Warm pools mark the places of rest in a cold street.
  - `grade res://data/render/grades/bilibara_noon.tres`: `lift` (0.05, 0.06, 0.09), `gamma` (1, 1, 1), `gain` (0.98, 0.99, 1.0), `saturation` 0.9, `tint` (1, 1, 1), `fog_color` `#aebbcc`, `fog_density` 0.015 (a body 12 m past the fog's start keeps about 84% of its own colour), `fog_height` 1.5.
  - **The readability band**, held by the render test: the drawn ground (the final picture, graded and fogged, mean luma of a ring 3 to 8 px outside a body's silhouette) is between 0.28 and 0.42 at every reference position; the contrast with Abarax and a tier I Knuckle is at least 0.08, with a tier III at least 0.08; each body's own mean luma varies by at most 0.08 across the 12 positions. If it fails, tune in this order, and no other: the textures' colours (within Task 1's ranges), the fog density (0.01 to 0.03), the grade's lift and saturation; never the fill's energy outside 1.0 to 1.3, never the bodies' palettes (a lane that does not own them). The training yard's own worst case, measured by the same method in Step 1, is the floor: the stretch is no worse than it.
  - **The 12 reference positions** (Abarax at `p`, a tier I Knuckle at `p + (2.4, 0, 0)`, a tier III at `p + (-2.4, 0, 0)`, all facing south): court A `(-35, 0)` (slate, in ShrineLampA's pool); the street `(0, 0)` (cobble, open); `(-5, -3)` (cobble in a lamp's pool); `(0, 4.5)` (cobble at the kerb); the lane `(27.5, -30)` (earth); alcove B `(35, -34)` (slate, pool); the Rack Walk `(-10, -22.5)`; the loop lane `(-32.5, -12)`; the yard `(27.5, -65)`, `(27.5, -73)` (under the north wall), `(20, -56.5)` (by the kerb); and `(27.5, -10)` (the lane's mouth). These twelve are also Task 5's cost viewpoints.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/world/test_bilibara.gd, added
func test_the_light_is_the_snow_noon() -> void:
	# Fill: cull mask RENDER_BODIES, no shadow, cool, energy 1.0..1.3, from the camera's side and above (basis.z.z > 0.5, z.y > 0.3); Sun: shadows on, energy 0.25, mask leaves the bodies out; ambient #bccadf 0.62; background #aebbcc == the grade's fog colour; grade is bilibara_noon
func test_shade_is_at_least_seventy_percent_of_sun() -> void:
	# (ambient_energy * ambient.v + 0.35 * sun_energy) / (ambient_energy * ambient.v + sun_energy) >= 0.7
func test_the_environment_meets_the_looks_preconditions() -> void:
	# as test_courtyard's (linear, exposure 1, no glow/SSAO/SSIL/SDFGI/adjustments/fog/volumetric fog), with a cool ambient (b >= r) that is soft (energy x r < 0.5)
func test_lamps_light_the_world_only_and_are_warm_and_few() -> void:
	# 18 OmniLight3D, each in a lantern, colour ffb98a, range 6, energy 0.5, light_cull_mask == RENDER_WORLD; exactly 2 shadow casters, >= 60 m apart; none inside a clear band (Task 2)
func test_no_mesh_is_reached_by_more_than_six_lamps_and_no_point_by_more_than_two_shadows() -> void:   # Review Focus 5
	# for every MeshInstance3D, the lamps whose range sphere meets its global AABB: <= 6; for a 1 m grid over the walkable set, the shadow-casting lamps whose range holds the point: <= 2
# tests/render/test_bilibara_readability.gd   (--render; Main in the stretch, 1920 x 1080 as test_yard_shot, the final picture)
func test_a_body_reads_on_every_ground_in_every_light() -> void:   # Review Focus 3
	# at each of the 12 positions: ground luma 0.28..0.42; |body luma - ground luma| >= 0.08 for Abarax, tier I and tier III; each body's luma spread across the 12 <= 0.08; every number to out/shots/bilibara_readability.txt, the 12 pictures on a sheet beside it
func test_the_yard_is_the_floor() -> void:
	# the same measure in the training yard at its dark ground (0, 3): its contrast is recorded in the file; the stretch's worst is >= min(0.08, the yard's worst)
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_bilibara` and `tools/test.sh --render --filter=test_bilibara_readability`. Expected: FAIL.
- [ ] **Step 3: Build** the lines and the grade; rebuild the scene.
- [ ] **Step 4: Look at it.** Read the 12 pictures on the sheet and the nine views again (re-run Task 3's view test with the light on). Check against the book: cold and pale, pink neon and warm lamps the only colour, snow in the joints; against the spec: every body outlined and clear, no body in a dark shape on a dark floor, no body lost on pale snow or pale stone. If a position fails, tune in the order above.
- [ ] **Step 5: Run** `tools/test.sh --filter=tests/world`, `TEST_TIMEOUT=1800 tools/test.sh --render --filter=bilibara`, then `tools/test.sh`.
- [ ] **Step 6: Commit.** STATE.md line: "F3 Task 4 (stretch): the light is the book's cold snow-noon (overcast: a cool ambient, a gentle sun, haze `#aebbcc`, grade `bilibara_noon`), bodies lit by a bodies-only `Fill` so they are the same brightness on cobble, earth and slate, 18 warm lanterns that light the world only, two shadow-casting at the shrine sites; no mesh has more than 6 lamps on it; every body reads on every ground (12 measured positions)." Owner-checklist items: "The stretch's light after the yard's night: too pale, too flat, too cold? Can you always see Abarax, and each Knuckle tier, on every ground and in every pool? Do the warm lamps tell you where the places of rest are?"

---

### Task 5: Cost, the owner's sheet, and handing the layout over

**Files:**
- Modify: `world/bilibara/layout.txt` (header only), `tests/render/test_bilibara_view.gd`
- Create: `tests/perf/test_bilibara_budget.gd`, `tests/render/test_bilibara_cost.gd`
- Test: the same

**Interfaces:**
- Consumes: everything above; `RouteBrain`; the 12 reference positions; `RenderingServer.get_rendering_info`.
- Produces:
  - `tests/perf/test_bilibara_budget.gd`: the stretch's physics step on average at most 2.0 ms over 600 frames with Abarax on `RouteBrain` over the walk of Task 2 (measured as `test_frame_budget.gd` does: from `physics_frame` to `process_frame`).
  - `tests/render/test_bilibara_cost.gd`: at each of the 12 positions, after 10 frames, the frame's `RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME` is at most 450 and `RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME` at most 400,000; the numbers go to `out/shots/bilibara_cost.txt`.
  - Static budget in `test_bilibara.gd`: at most 2,000 `MeshInstance3D`, 24 `OmniLight3D`, 400 `CollisionShape3D`, 2 shadow-casting lamps in the scene.
  - `out/shots/bilibara_sheet.png`: the nine views of Task 3 in a 3 x 3 sheet, 1,920 x 1,080, for the owner.
  - The layout's header says what the other two say: the scene is the source from now on; do not build again.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/perf/test_bilibara_budget.gd
func test_stretch_physics_frame_under_two_ms() -> void:
	# main in the stretch, Abarax on RouteBrain, 600 frames after 2: mean <= 2.0 ms
# tests/render/test_bilibara_cost.gd
func test_every_reference_view_is_inside_the_draw_budget() -> void:   # 12 positions; <= 450 draw calls, <= 400,000 primitives
# tests/world/test_bilibara.gd, added
func test_the_scene_is_inside_the_static_budget() -> void:   # <= 2,000 meshes, <= 24 omni lights, <= 400 collision shapes, 2 shadow-casting lamps
# tests/render/test_bilibara_view.gd, added
func test_the_owners_sheet_is_saved() -> void:   # out/shots/bilibara_sheet.png, 1920 x 1080, nine tiles of 640 x 360
```

- [ ] **Step 2: Run** them. Expected: FAIL (no files). Then, once written, they show the first real numbers: **if a budget fails, fix the scene, not the number**: merge each building's pieces into one `MeshInstance3D` in the builder's `block` (the one change that cuts draw calls without changing the picture), then thin the ring behind what the camera never reaches.
- [ ] **Step 3: Build** the three test files and the sheet, and mark the layout as built once.
- [ ] **Step 4: Look at it.** Read `out/shots/bilibara_sheet.png` at full size and the cost file. Say in the commit which view is the heaviest, and its numbers.
- [ ] **Step 5: Run the whole suites:** `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, `tools/godot.sh -- --selftest` (exit 0), `tools/godot.sh -s res://tools/clip_check.gd`, and, if lavapipe is installed, `tools/test.sh --forward-plus --filter=bilibara`. Expected: all pass, no `ERROR:` or `WARNING:` lines. Re-run `git status`: nothing under the "do not touch" list changed.
- [ ] **Step 6: Commit.** Lines for the controller: STATE.md Done: "F3 Task 5 (stretch): the stretch is inside the budget (physics step X ms, at most Y draw calls and Z primitives over 12 views, N meshes, 18 lamps, 2 shadowed), `world/bilibara/bilibara.tscn` is the source from now on (do not run `build_region.gd` on it again), F2 enters it." Owner checklist for the stretch: "1. Press F2 in the game, walk from Behind the Lazyman's to the yard with a pad and with a keyboard. 2. Walk the loop from the lane's far side to the shortcut gate: is it clear it is a closed gate you will open from this side? 3. Look at every wall top, every street end and the harbor: does the picture ever end at a wall? 4. Open F3 at 1920 x 1080 on your PC: 60 fps everywhere? 5. Shove into corners and kerbs: any leak? 6. Is the yard a place you want to fight a boss in (25 x 20 m, three doors, two vats)? 7. Write what you see in `all-divine/notes/f3-stretch.md`."
