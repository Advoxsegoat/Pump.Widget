# The Sway-and-Duck Defence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Abarax's dodge roll with sways and ducks on the held guard key, a dash-step, a chain that climbs from weighty slips to a flurry, and counters that cash the chain in.

**Architecture:** An evade is a new outcome of the rules of a blow (`Combat.resolve`), opened by a mark window on a move, like a parry. A small `DodgeChain` on the actor counts defences that succeed in a row and sets the tempo; the move runner asks the actor which sway, duck or counter an action means now. Everything the player sees and hears of the chain hangs off its signals.

**Tech Stack:** Godot 4.7.2, typed GDScript, the project's own test runner (`tools/test.sh`), clips built by `tools/anim/build_library.gd` from `assets/anim/clips.cfg`.

**Spec:** `docs/superpowers/specs/2026-11-10-all-divine-sway-defence-design.md` (it amends `2026-10-25-all-divine-rpg-foundation-design.md`).

## Global Constraints

- Everything lives in `all-divine/`. Paths below are under it unless they start with `docs/`.
- Content is data, never code. One way to animate: a rig and clips. Layers talk downward or through signals.
- Frames are 1/60 s physics ticks. Input response is 2 frames at most. The input buffer is 9 frames. Hit-stop is 3–6 frames.
- Green runs print no `ERROR:` or `WARNING:` lines (error paths are asserted through `quietly()` and returned data).
- Every file under `assets/` has a row in `ASSETS.md`.
- Commit messages start `All-Divine F1: `, end with the attribution trailers the session specifies, and never name a model.
- A tell never tints or covers a body's interior: rims on the silhouette's edge, waves on the ground, icons above the head.
- Probes and scratch files live in the session's scratchpad, never in the project tree.
- **The spec's numbers, verbatim:**

| Tempo | Chain | Sway: length, window | Duck: length, window | Stamina (sway, duck) | Posture an evade takes from its attacker |
|---|---|---|---|---|---|
| Slip | 0–2 | 22 frames, 10 | 26 frames, 12 | 6, 8 | 0 |
| Quick | 3–6 | 16 frames, 8 | 18 frames, 9 | 4, 5 | 4 |
| Flurry | 7 and up | 12 frames, 6 | 14 frames, 7 | 3, 4 | 8 |

  - Every evade window opens on the move's frame 2.
  - An evade adds 1 to the chain, a parry or catch 1, a perfect dodge 2. A perfect dodge gives back its stamina cost and 4 more.
  - Straight blows are matched by a sway, round ones by a duck, a grab by either.
  - The chain ends on an attack (cashed in), a walk, a dash-step or hop, 60 frames without a defence that succeeds, a broken guard, or a blow that lands. A guarded blow neither builds nor ends it.
  - A blow that lands at Quick or Flurry staggers Abarax whatever its weight.
  - After a dodge that avoided nothing, another sway or duck cannot start until twice the window's length (frames 20, 16, 12 for sways; 24, 18, 14 for ducks).
  - A counter follows an evade within 24 frames. Cashed in at Slip, Quick, Flurry it is worth ×1, ×1.5, ×2; a clear-out throws 2, 2.5, 3 m; a Flurry counter staggers whatever the poise. A clear-out costs 20 stamina.
  - Dash-step: 1.3 m along the stick over 10 frames, 18 frames long, never invulnerable, 8 stamina, cancels from frame 10. Hop: unchanged.
  - The slow-down: 40% for 12 frames, on a chain's first perfect dodge and on the dodge that enters Flurry, and never otherwise.
  - Sweep: hopped. Thrust: caught with a parry. Grab: slipped by any sway or duck, a perfect dodge.

## Review Focus

Five conditions the tasks' main tests would not reach on their own, most likely to hurt first:

1. **Blows from several attackers around one dodge.** One blow lands on the frame the window closes, or from behind in the dodge's other frames, or two land on the same frame and only one can be evaded (a sweep with a jab). The evadable ones are evaded, the others land, and a landed blow wins: Abarax is hit and knocked out of the chain. A blow that was evaded never lands later in the same swing. Tests in Tasks 1 and 4.
2. **Presses that arrive at awkward moments.** A direction held before guard goes down; guard and a direction on one frame; a sway buffered during hit-stop, the slow-down or a stagger; sways mashed; a counter pressed without stamina. One outcome, the same every time: no sway from a held direction, a buffered sway comes out or expires by the buffer's rule, mashing never lengthens a window or builds the chain, a refused counter cashes nothing. Tests in Tasks 3, 4 and 5.
3. **The chain across freezes.** Frozen frames (hit-stop, the slow-down) do not count toward the 60-frame timeout or the 24-frame counter window; a chain neither times out nor a counter window closes because the fight was slowed. Tests in Tasks 4 and 6.
4. **Clear-outs against the world.** A clear-out near a wall, in a corner, against three bodies at once, a paired body, a corpse, a foe whose posture is broken. Nobody passes through a wall or another body, the paired and the dead are not thrown, a broken foe stays finishable. Tests in Task 5.
5. **The answers that are not evades.** A thrust or sweep thrown into a chain (it lands, and at Quick or Flurry it staggers); a grab slipped on the frame its pair would start; a hop or dash-step during a chain (it ends); a blow during a dash-step (it lands). Tests in Tasks 1, 3 and 4.

---

## Decisions this plan makes where the spec leaves room

- **The tempo lengths are held by tests, not by the clip checker.** The checker holds the structure (one evade window, opening on frame 2; none on a dash-step); `tests/anim/test_sway_clips.gd` holds each tempo's frames, since the checker knows nothing of tempos.
- **Wherever the roll could cancel a move, a sway, a duck and a dash-step now can.** Every cancel window that named the roll takes `sway`, `duck` and `dodge`. The guard raise and the parry, catch and guard-hit reactions open a window into `sway` and `duck`, so a parry flows into a sway.
- **The counters' own numbers** (damage, posture, stamina) are first values for tuning; the spec gives only how they scale.
- **The back-palm throws to Abarax's right**, the way the turn goes. The wave throws straight away from him.
- **The roll's dust and cloth cues go to the dash-step.**

## Facts the tasks rely on (read from the code, 2026-11-10)

- `MoveRunner.tick` consumes buffered actions twice: from the open cancel `window` (action → move id) and, with no move playing, from `actor.def.moveset`. It fetches moves by id from `Registry.fetch(&"moves", id)`.
- A move with a `neutral_variant` starts that variant when the intent's stick is at rest (the hop today).
- `MoveRunner._start` snaps a DODGE move's facing to the stick. Only the roll needed that.
- Marks live in each clip (`Marks.KINDS`); windows are opened and closed by mark pairs (`parry_on/off`, …). The clip checker's `WINDOW_PAIRS` names them.
- `Defense.of(actor)` snapshots what the rules read; `Combat.resolve(e, d, tuning)` is pure; `Melee` judges every blow of a frame against the snapshot taken before any actor moved, forgets a WHIFF so it can land later in the swing, and applies freezes and pushes in `_weigh`.
- `HitIntake.take` applies results to stats and starts reactions; a parried attacker gets its result through the `turned` lists.
- Missing clips are made by hand-keyed bone layers: `assets/anim/layers/<name>.json`, bone → `[[frame, x°, y°, z°], …]`, laid over a clip by `layer=` in `clips.cfg`. `clips.cfg` also takes `then=` (joins), `length=` (retime), `warp=` and `step_fps=`.
- Marks are written with `tools/godot.sh -s res://tools/anim/set_marks.gd -- <clip.tres> <marks.json>` (a JSON list of `{frame, kind, args}`) and survive rebuilds.
- The packs hold no sway or duck. Useful clips: `ual1` `Crouch_Idle_Loop`, `Punch_Cross`, `Punch_Jab`; `ual2` `Idle_Shield_Loop` (the guard stance), `Shield_Dash`, `Melee_Hook`, `Sword_Regular_A/B/C` (+`_Rec`), `Sword_Heavy_Combo`.
- `tools/test.sh --render` takes about 15 minutes: run it as `TEST_TIMEOUT=1800 tools/test.sh --render`, at a task's end only.

## File structure

```
moves/        hit_profile.gd (line, arc_deg, throw, throw_way)   move_data.gd (evade, directional, redodge_frame, counters, cashes)
              marks.gd (evade_on, evade_off)   move_runner.gd (evading, evaded, whiff rule, counter window)
combat/       defense.gd (evading, chain_tempo, evade_chip)   hit_result.gd (EVADED, perfect)   combat.gd (the rules)
              hit_event.gd (power, always_staggers, throw)   hit_scanner.gd (arc; cash values)   melee.gd (EVADED; throw; slow)
              chain_tuning.gd (new)   dodge_chain.gd (new)   combat_tuning.gd (guard_planted)
actors/       actor.gd (move_for, evade_dir, chain, planted guard)   intent.gd (evade_dir)   player_brain.gd (sway and duck presses)   script_brain.gd (evade_dir)
              hit_intake.gd (an evade's posture chip)   stats.gd (refund_stamina)   actor_def.gd (chain)   abarax/abarax_rig.tscn (clear_arc, clear_ring)
core/         inputs.gd (direction_pressed_this_frame)   bindings.gd (move flicks)   sfx.gd (pitch)
fx/           chain_fx.gd (new)   afterimage.gd (new)   readability_tuning.gd (chain look, switches)
hud/          hud.gd (the grab's glyph)   controls_list.gd (rows)
data/         moves/*.tres (sways, ducks, dash-steps, counters; dodge_roll deleted)   tuning/chain_open_hand.tres   tuning/combat_abarax.tres
              actors/abarax.tres   sounds/{evade_whoosh,perfect_dodge,knocked_out}.tres
assets/       anim/clips.cfg   anim/layers/*.json   anim/abarax/*.tres   audio/sfx/*.wav
tools/        clip_checker.gd   anim/clip_builder.gd   audio/make_sfx.py
tests/        combat/test_evade.gd test_dodge_chain.gd test_counters.gd   anim/test_sway_clips.gd   actors/test_sway_input.gd
              feel/test_sway_flow.gd   fx/test_chain_fx.gd   render/test_chain_shots.gd   world/test_clearout_walls.gd
```

---

### Task 1: The rules of an evade

**Files:**
- Modify: `moves/hit_profile.gd`, `moves/move_data.gd`, `moves/marks.gd`, `moves/move_runner.gd`, `combat/defense.gd`, `combat/hit_result.gd`, `combat/combat.gd`, `combat/melee.gd`, `actors/hit_intake.gd`, `tools/clip_checker.gd`
- Modify (data): `data/moves/knuckle_hook.tres`, `knuckle_hook_2.tres`, `palm_hook.tres`, `palm_heavy.tres` (their profiles' `line = ROUND`)
- Test: `tests/combat/test_evade.gd`, additions to `tests/moves/test_clip_checker.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `HitProfile.Line { STRAIGHT, ROUND }` and `@export var line: Line = Line.STRAIGHT`.
  - `MoveData.Evade { NONE, SWAY, DUCK }` and `@export var evade: Evade = Evade.NONE`.
  - Marks `evade_on` and `evade_off` (no arguments).
  - `MoveRunner.evading: MoveData.Evade`: the current move's `evade` while its evade window is open, else `NONE`; cleared when the move ends.
  - `MoveRunner.evaded: bool`: true once a blow was evaded during the current move; false again at the next move's start.
  - `Defense.evading: MoveData.Evade`, copied from the runner by `Defense.of`.
  - `HitResult.Outcome.EVADED` and `HitResult.perfect: bool`.
  - `static func Combat.is_perfect(evade: MoveData.Evade, p: HitProfile) -> bool`: a grab with any evade; a SWAY with a STRAIGHT line; a DUCK with a ROUND line.
  - `Combat.resolve`, a new rule after "a LOW blow on the airborne" and before the grab: an evading target avoids a blow whose `perilous` is `NONE` or `GRAB`: `EVADED`, with `perfect` set. A sweep or thrust goes on down the rules.
  - `Melee`: an EVADED blow is spent. The scanner does not forget it (a WHIFF is forgotten), nobody freezes, nobody is pushed, no grab pair starts. `got_hit` on the target and `hit_landed` on the attacker carry it. `HitIntake.take` sets `runner.evaded = true` on the target and starts no reaction.
  - Clip checker: `"evade": [&"evade_on", &"evade_off"]` in `WINDOW_PAIRS`; a move with `evade != NONE` has exactly one evade window and it opens on frame 2; a move with `evade == NONE` has no evade marks.

- [ ] **Step 1: Write the failing tests** in `tests/combat/test_evade.gd`. The rule tests build `Defense` and `HitEvent` values by hand, as `tests/combat/` does for parries.

```gdscript
func test_an_evading_body_avoids_an_ordinary_blow() -> void:
	# d.evading = SWAY, a jab's profile (perilous NONE, line STRAIGHT): outcome EVADED, perfect true, no damage, no reaction
func test_the_other_dodge_still_avoids_but_is_not_perfect() -> void:
	# DUCK against STRAIGHT and SWAY against ROUND: EVADED, perfect false
func test_a_grab_is_slipped_by_either_dodge_and_is_perfect() -> void:
	# SWAY and DUCK against perilous GRAB: EVADED, perfect true (never GRABBED)
func test_a_sweep_and_a_thrust_land_on_an_evading_body() -> void:
	# SWAY and DUCK against SWEEP and THRUST: outcome HIT
func test_an_evade_beats_a_guard_and_a_parry_loses_to_nothing() -> void:
	# evading and guarding at once: EVADED. The dead, the paired and the invulnerable still WHIFF first.
func test_the_window_avoids_only_its_own_frames() -> void:
	# a fixture move (evade SWAY, evade_on f2, evade_off f12): runner.evading is NONE on f0–1, SWAY on f2–11, NONE from f12
func test_three_blows_inside_one_window_are_all_evaded_and_a_fourth_after_it_lands() -> void:
func test_an_evaded_blow_does_not_land_later_in_the_same_swing() -> void:
	# a hitbox on for 5 frames meets the window's last frame: EVADED once, and no HIT on the frames after the window
func test_a_sweep_and_a_jab_on_the_same_frame_one_evaded_one_lands() -> void:   # Review Focus 1
func test_an_evade_freezes_and_pushes_no_one_and_sets_evaded() -> void:
```

  and in `tests/moves/test_clip_checker.gd`:

```gdscript
func test_an_evade_move_needs_one_window_opening_on_frame_two() -> void:
func test_a_move_that_is_no_evade_may_not_carry_evade_marks() -> void:
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_evade` and `--filter=test_clip_checker`. Expected: FAIL (the enum, the outcome and the rule do not exist).
- [ ] **Step 3: Implement the Interfaces above.** Set `line = 1` (ROUND) on the hook, second hook, `palm_hook` and `palm_heavy` profiles; every other profile keeps the default.
- [ ] **Step 4: Run** `tools/test.sh` and `tools/godot.sh -s res://tools/clip_check.gd`. Expected: all pass; `clip_check: 30 moves, 4 actors OK`.
- [ ] **Step 5: Commit.**

---

### Task 2: The sway, duck and dash-step clips and moves

**Files:**
- Create: `assets/anim/layers/sway_left.json`, `sway_right.json`, `sway_back.json`, `duck.json`, and layers for the three off-axis dash-steps as needed
- Modify: `assets/anim/clips.cfg`, `tools/anim/clip_builder.gd` (only if a root track has to be turned or written), `moves/move_data.gd`, `ASSETS.md`, `tests/anim/test_no_pops.gd` (exceptions, if any, named and justified)
- Create (built or data): `assets/anim/abarax/<clip>.tres` for each clip below; `data/moves/<id>.tres` for each move below
- Test: `tests/anim/test_sway_clips.gd`

**Interfaces:**
- Consumes: `MoveData.evade`, marks `evade_on/off` and the checker's rules (Task 1).
- Produces:
  - `MoveData.directional: Dictionary` (`&"left" | &"right" | &"back"` → move id): the move started instead when the direction asked for is on that side. Empty by default.
  - `MoveData.redodge_frame: int` (0 by default): after a dodge that avoided nothing, the frame before which another sway or duck cannot start.
  - Sixteen moves, each with a clip of the same name. All are `kind = DODGE`; sways and ducks have `root_motion = false`.

| Move | Frames | `evade` | evade_on, evade_off | `redodge_frame` | Stamina | `directional` |
|---|---|---|---|---|---|---|
| `sway_left_slip` | 22 | SWAY | 2, 12 | 20 | 6 | right → `sway_right_slip`, back → `sway_back_slip` |
| `sway_right_slip`, `sway_back_slip` | 22 | SWAY | 2, 12 | 20 | 6 | |
| `sway_left_quick` | 16 | SWAY | 2, 10 | 16 | 4 | right, back → the Quick ones |
| `sway_right_quick`, `sway_back_quick` | 16 | SWAY | 2, 10 | 16 | 4 | |
| `sway_left_flurry` | 12 | SWAY | 2, 8 | 12 | 3 | right, back → the Flurry ones |
| `sway_right_flurry`, `sway_back_flurry` | 12 | SWAY | 2, 8 | 12 | 3 | |
| `duck_slip` | 26 | DUCK | 2, 14 | 24 | 8 | |
| `duck_quick` | 18 | DUCK | 2, 11 | 18 | 5 | |
| `duck_flurry` | 14 | DUCK | 2, 9 | 14 | 4 | |
| `dash_step` (forward) | 18 | NONE | none | 0 | 8 | left, right, back → `dash_step_left`, `_right`, `_back`; `neutral_variant = hop` |
| `dash_step_left`, `_right`, `_back` | 18 | NONE | none | 0 | 8 | |

  - **Marks on every sway and duck:** `evade_on`, `evade_off`, and at the `evade_off` frame a `recovery` and a `cancel_open` into `{sway: sway_left_slip, duck: duck_slip, guard: guard_raise, palm: palm_jab, heavy: palm_heavy, dodge: dash_step}`. Window values for `sway`, `duck` and `dodge` are always these three base moves; Task 3 resolves the real one.
  - **Marks on every dash-step:** at frame 1 `fx roll_dust` and `sfx roll_cloth`; at frame 10 a `recovery` and a `cancel_open` into `{palm: palm_jab, heavy: palm_heavy, guard: guard_raise, sway: sway_left_slip, duck: duck_slip}`. No evade or iframes marks.
  - **The shapes** (the spec's section 5; `step_fps=0`, smooth):
    - Sways start and end in the guard stance (`guard_hold`'s pose). A sway is a slip and a dip. At its peak the head is off the body's centre line by 0.30–0.36 m at Slip, 0.24–0.28 m at Quick and 0.20–0.24 m at Flurry, and lower than in the guard stance by 0.12–0.18 m, 0.10–0.14 m and 0.08–0.12 m; the shoulders tilt with it; the weight goes onto the leg on that side at Slip. A pull back folds the spine away and tucks the chin as well. (Amended after the first review: the first band, 0.18–0.25 m and 0.12–0.20 m with no dip, moved the head 2–7 pixels and did not read.)
    - **On screen**, at 640×360 from the game camera, at each clip's peak against the guard stance, with Abarax facing up, down, left and right: the head moves at least 5 px (Slip), 4 px (Quick) and 3.5 px (Flurry) in every facing and at least 9, 7 and 6 px in the best one; the silhouette changes by at least 200 px (Slip) and 150 px (Quick, Flurry) in every facing.
    - A duck's head drops at least 0.35 m at Slip and 0.25 m at Quick and Flurry.
    - The feet stay planted in every sway and duck: neither foot moves more than 3 cm.
    - Each tempo is the same shape made shorter and smaller, not the Slip clip played fast.
    - A dash-step's root travels 1.30 m (±0.02) in its own direction (forward, left, right, back, in the body's frame), all within frames 0–10, eased in and out, and not at all after; the body stays low and leans the way it goes. It is a step, not a slide: by frame 4 the leading foot is at least 0.25 m ahead of the pelvis along the travel and the trailing foot at least 0.20 m behind it, and by frame 12 both are back under him. On screen its head moves at least 5 px in every facing.

- [ ] **Step 1: Write the failing tests** in `tests/anim/test_sway_clips.gd` (use `tests/support/clip_motion.gd` for bone travel):

```gdscript
func test_every_sway_duck_and_dash_step_has_its_move_its_clip_and_its_length() -> void:   # the table above, frame for frame
func test_each_evade_window_and_redodge_frame_matches_its_tempo() -> void:
func test_the_head_leaves_the_line_and_the_feet_stay() -> void:       # the head and foot numbers above, per clip
func test_a_sway_and_a_duck_start_and_end_in_the_guard_stance() -> void:
func test_each_tempo_is_smaller_and_shorter_than_the_one_before() -> void:
func test_a_dash_step_travels_1_3_m_its_own_way_by_frame_ten() -> void:
func test_the_slip_bases_name_their_sides_and_the_dash_its_hop() -> void:   # directional and neutral_variant
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_sway_clips`. Expected: FAIL (no such moves).
- [ ] **Step 3: Key the layers, add the `clips.cfg` entries, build the library** (`tools/godot.sh -s res://tools/anim/build_library.gd`), write the marks with `set_marks.gd`, and write the moves' `.tres`. If a dash-step's root track cannot be had from a pack clip, give `clip_builder` the smallest new option that writes or turns one, with its own test under `tools/anim/tests`.
- [ ] **Step 4: Look at them.** Render a contact sheet of every clip (`tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- --def data/actors/abarax.tres --clips <names> --out out/sheets/sways.png`), Read the PNGs, and fix what looks stiff or wrong before going on. The report says what was seen and changed.
- [ ] **Step 5: Run** `tools/test.sh`, `tools/godot.sh -s res://tools/clip_check.gd` and `tools/test.sh --render --filter=tests/anim`. Expected: all pass; the checker counts 46 moves. If `test_no_pops` flags a Flurry clip's head, slow that clip's lean inside its frames first; list it as an exception only if the spec's length cannot hold it, and say so in the report.
- [ ] **Step 6: Commit.** Add the clips' sources to the `assets/anim/abarax/` row of `ASSETS.md`.

---

### Task 3: Sway and duck from the pad and the keys, the planted guard, the dash-step in the roll's place

**Files:**
- Modify: `core/inputs.gd`, `core/bindings.gd`, `actors/intent.gd`, `actors/player_brain.gd`, `actors/script_brain.gd`, `actors/actor.gd`, `moves/move_runner.gd`, `combat/combat_tuning.gd`, `tools/clip_checker.gd`, `hud/controls_list.gd`, `main/main.gd`
- Modify (data): `data/actors/abarax.tres`, `data/tuning/combat_abarax.tres`; the marks of every clip whose cancel windows name `dodge_roll`, and of `guard_raise`, `parry`, `catch` and `guard_hit`
- Delete: `data/moves/dodge_roll.tres`, `assets/anim/abarax/dodge_roll.tres`, the `[dodge_roll]` entry of `clips.cfg`
- Test: `tests/actors/test_sway_input.gd`; `tests/moves/test_move_runner.gd` and `test_open_hand.gd` (the roll's tests become the dash-step's); `tests/main/test_selftest.gd`

**Interfaces:**
- Consumes: the moves, `MoveData.directional` and `neutral_variant` (Task 2); `MoveRunner.evading` (Task 1).
- Produces:
  - `Inputs.direction_pressed_this_frame() -> Vector2`: the screen direction (x right, y down, length 1) of a move key that went down this physics frame, or of the left stick flicked past 0.6 (down again only after it falls below 0.35); `Vector2.ZERO` if none.
  - `Intent.evade_dir: Vector2`: the world (x, z) direction of a sway or duck press; zero otherwise.
  - `PlayerBrain.think`: when guard is held or pressed this frame and a direction was pressed this frame, the intent presses `&"duck"` if the screen direction is within 45° of straight down, else `&"sway"`, with `evade_dir` set (turned by `view_yaw`); a `&"guard"` press of the same frame is dropped. A direction held before guard went down presses nothing.
  - `Actor.evade_dir: Vector2`: the direction of the latest sway or duck press, kept with the buffered press.
  - `ScriptBrain` steps take `evade_dir` (a world Vector2), set on the intent with the step's presses.
  - **Marks:** every `cancel_open` that named `dodge_roll` now names `dodge: dash_step`, `sway: sway_left_slip` and `duck: duck_slip` beside what it already had. `guard_raise` opens a window into `{sway, duck}` at its `parry_off`. The `parry`, `catch` and `guard_hit` reactions take `sway` and `duck` into the window they have, or open one at frame 8 if they have none.
  - `static func MoveData.side_of(dir: Vector2, facing: Vector3) -> StringName`: `&""` within 30° of the facing, `&"back"` at 150° or more from it, else `&"left"` or `&"right"`.
  - `Actor.move_for(action: StringName, intent: Intent, named: StringName = &"") -> MoveData`: the move the action starts now. It takes `named` (a cancel window's value) or the moveset's move, then that move's `directional` variant for the side of `evade_dir` (a sway) or of the intent's stick (a dodge), when it has one. `MoveRunner.tick` calls it at both places it starts a consumed action.
  - `MoveRunner._start` no longer turns a DODGE move's body to the stick: a dash-step keeps its facing.
  - `CombatTuning.guard_planted: bool` (false by default; true in `combat_abarax.tres`): while the guard stance is up, the actor's legs get no stick; it still turns to its `face_target`.
  - Abarax's moveset: `sway → sway_left_slip`, `duck → duck_slip`, `dodge → dash_step`.
  - Clip checker: it follows a move's `directional` values as it follows `neutral_variant`; a DODGE move with `evade == NONE` carries no `evade_*` and no `iframes_*` marks.
  - Controls list rows: `"Guard (tap to parry)"`, `"Sway / duck: hold guard + a direction"`, `"Dash-step (hop if still)"`.
  - The self-test circuit: approach, jab, cross, hook, sway, duck, dash-step, guard, heavy.

- [ ] **Step 1: Write the failing tests** in `tests/actors/test_sway_input.gd` (drive `Inputs` as `tests/core/` does; drive actors with `ScriptBrain`):

```gdscript
func test_a_direction_pressed_with_guard_held_sways_within_two_frames() -> void:
func test_guard_and_a_direction_on_the_same_frame_is_a_sway_not_a_parry() -> void:
func test_a_direction_already_held_when_guard_goes_down_starts_nothing() -> void:      # Review Focus 2
func test_down_ducks_whatever_way_he_faces() -> void:                                   # four facings
func test_the_side_follows_the_screen_against_his_facing() -> void:
	# facing +x: a press toward +z is sway_right_slip, toward -z sway_left_slip, toward -x sway_back_slip, toward +x sway_left_slip
func test_the_stick_flicks_past_point_six_and_rearms_below_point_three_five() -> void:
func test_a_sway_buffered_during_hit_stop_comes_out_when_it_ends() -> void:             # Review Focus 2
func test_he_stands_his_ground_while_guard_is_held_and_walks_when_it_is_let_go() -> void:
func test_dodge_with_the_stick_dash_steps_that_way_and_keeps_his_facing() -> void:
func test_dodge_with_the_stick_at_rest_hops() -> void:
func test_a_blow_during_a_dash_step_lands() -> void:                                    # Review Focus 5
func test_a_dash_step_stops_at_a_wall_and_at_a_body() -> void:
func test_holding_dodge_after_a_dash_step_sprints() -> void:
func test_a_parry_flows_into_a_sway() -> void:      # guard tapped, the blow parried, a sway pressed: it starts by the parry reaction's frame 8
func test_every_window_that_took_the_roll_takes_a_sway_a_duck_and_a_dash_step() -> void:
func test_no_clip_or_move_names_the_roll_any_more() -> void:
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_sway_input`. Expected: FAIL.
- [ ] **Step 3: Implement the Interfaces above.** Find the clips to re-mark with a search of every clip's marks for `dodge_roll` (a scratchpad script), and re-mark them with `set_marks.gd`. Delete the roll. Rewrite the roll's tests in `test_move_runner.gd` and `test_open_hand.gd` for the dash-step, deleting the ones that tested invulnerability and the snap to the stick.
- [ ] **Step 4: Run** `tools/test.sh`, `tools/godot.sh -s res://tools/clip_check.gd`, and the self-test (`tools/godot.sh -- --selftest --fixed-fps 60`). Expected: all pass; the checker counts 45 moves; `selftest: 600 frames, 0 errors`.
- [ ] **Step 5: Commit.**

---

### Task 4: The chain

**Files:**
- Create: `combat/chain_tuning.gd`, `combat/dodge_chain.gd`, `data/tuning/chain_open_hand.tres`
- Modify: `actors/actor_def.gd`, `actors/actor.gd`, `actors/stats.gd`, `actors/hit_intake.gd`, `combat/defense.gd`, `combat/combat.gd`, `combat/melee.gd`, `moves/move_runner.gd`, `data/actors/abarax.tres`
- Test: `tests/combat/test_dodge_chain.gd`, `tests/feel/test_sway_flow.gd`

**Interfaces:**
- Consumes: `EVADED`, `perfect`, `MoveRunner.evaded` (Task 1); the tempo moves and `redodge_frame` (Task 2); `Actor.move_for` (Task 3).
- Produces:
  - `class_name ChainTuning extends Resource` with `@export`s: `quick_at := 3`, `flurry_at := 7`, `timeout_frames := 60`, `perfect_links := 2`, `perfect_refund := 4.0`, `posture_chip := PackedFloat32Array([0, 4, 8])`, `cash_scale := PackedFloat32Array([1.0, 1.5, 2.0])`, `clearout_throw := PackedFloat32Array([2.0, 2.5, 3.0])`, `sway_moves: Array[StringName]` and `duck_moves: Array[StringName]` (the base move of each tempo: `sway_left_slip`, `sway_left_quick`, `sway_left_flurry`; `duck_slip`, `duck_quick`, `duck_flurry`).
  - `class_name DodgeChain extends RefCounted`:
    - `enum Tempo { SLIP, QUICK, FLURRY }`
    - `var count := 0`; `func tempo() -> Tempo`
    - `signal changed(count: int, tempo: Tempo)`, `signal linked(perfect: bool)`, `signal knocked_out(from: Tempo)`, `signal cashed(at: Tempo)`
    - `func link(perfect: bool, frame: int) -> void`, `func knock_out() -> void`, `func cash() -> Tempo` (returns the tempo reached and empties the chain), `func end() -> void`, `func tick(frame: int) -> void` (the timeout; `frame` is the actor's `buffer_frame`, which does not advance while it is frozen).
  - `ActorDef.chain: ChainTuning` (null by default; `chain_open_hand.tres` on Abarax). `Actor.chain: DodgeChain`, null for an actor whose def has none.
  - `Actor.cashed_tempo: DodgeChain.Tempo`: the tempo the chain had when the attack now playing started (SLIP for any other move).
  - What feeds the chain: an EVADED blow he took links (perfect or not); a PARRIED or CAUGHT blow he took links; a HIT, a GRABBED or a GUARD_BREAK knocks him out; a GUARDED blow does nothing. An ATTACK move starting cashes it; a dash-step or hop starting ends it; walking (no move playing and the legs moving) ends it; `tick` ends it after `timeout_frames`.
  - `Defense.chain_tempo: int` and `Defense.evade_chip: float` (the chip at the defender's tempo), both 0 without a chain.
  - `Combat.resolve`: a HIT on a target whose `chain_tempo >= 1` staggers whatever the poise. An EVADED result carries `attacker_posture_damage = evade_chip`, doubled when perfect.
  - `Melee` and `HitIntake`: an EVADED blow with `attacker_posture_damage > 0` reaches its attacker as posture damage with no reaction of its own; a posture that breaks from it reels as any broken posture does.
  - `Stats.refund_stamina(amount: float) -> void`: adds up to the maximum and does not restart the regeneration wait. A perfect dodge refunds the dodge's cost plus `perfect_refund`.
  - `Actor.move_for`: for `sway` and `duck` the move is first the chain's base for the present tempo (`sway_moves[tempo]`, `duck_moves[tempo]`), then its side.
  - `MoveRunner`, the whiff rule: while the current move has `evade != NONE`, has evaded nothing, and its frame is below its `redodge_frame`, presses of `sway`, `duck` and `dodge` are left in the buffer. Once a blow is evaded, the move's own cancel window (at its `evade_off`) lets them through.

- [ ] **Step 1: Write the failing tests** in `tests/combat/test_dodge_chain.gd`:

```gdscript
func test_an_evade_and_a_parry_add_one_and_a_perfect_dodge_adds_two() -> void:
func test_the_tempo_is_slip_to_two_quick_to_six_flurry_from_seven() -> void:
func test_each_tempo_starts_its_own_sway_and_duck() -> void:                 # move ids and stamina spent: 6/4/3 and 8/5/4
func test_a_perfect_dodge_gives_its_cost_back_and_four_more() -> void:
func test_an_evade_takes_posture_from_its_attacker_from_quick_on() -> void:  # 0, 4, 8; doubled when perfect; no reaction on the attacker
func test_a_string_dodged_through_can_break_the_attacker() -> void:
func test_a_blow_landing_at_quick_or_flurry_staggers_whatever_its_weight() -> void:
func test_a_blow_landing_at_slip_is_an_ordinary_hit() -> void:
func test_what_ends_the_chain() -> void:   # an attack (cashed, cashed_tempo set), a dash-step, a hop, walking, 60 frames, a broken guard
func test_a_guarded_blow_neither_builds_nor_ends_it() -> void:
func test_frozen_frames_do_not_run_the_timeout() -> void:                    # Review Focus 3
func test_a_thrust_into_a_flurry_lands_and_staggers() -> void:               # Review Focus 5
func test_an_evaded_jab_and_a_landed_sweep_on_one_frame_knock_him_out() -> void:   # Review Focus 1
func test_after_a_miss_the_next_sway_waits_for_the_redodge_frame() -> void:  # 20, 16, 12; 24, 18, 14
func test_after_an_evade_the_next_sway_starts_when_the_window_closes() -> void:
```

  and in `tests/feel/test_sway_flow.gd` (blows are posted to `Melee` from a dummy attacker at scripted frames, so the string is exact):

```gdscript
func test_seven_blows_gathering_speed_are_climbed_to_flurry_without_a_scratch() -> void:
	# blows at frames 40, 70, 96, 118, 136, 150, 162, lines S S R S R S R; the matching dodges; hp unchanged, tempo FLURRY,
	# the attacker's posture broken or within one counter of breaking
func test_parry_sway_sway_duck_takes_no_damage_from_jab_cross_hook() -> void:   # a real tier I Knuckle on a ScriptBrain
func test_mashed_sways_evade_at_most_half_the_frames_at_every_tempo() -> void:  # and never build the chain  (Review Focus 2)
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_dodge_chain` and `--filter=test_sway_flow`. Expected: FAIL.
- [ ] **Step 3: Implement the Interfaces above.**
- [ ] **Step 4: Run** `tools/test.sh` and the self-test. Expected: all pass.
- [ ] **Step 5: Commit.**

---

### Task 5: Counters and clear-outs

**Files:**
- Modify: `moves/move_data.gd`, `moves/hit_profile.gd`, `moves/move_runner.gd`, `combat/hit_event.gd`, `combat/hit_scanner.gd`, `combat/combat.gd`, `combat/melee.gd`, `actors/abarax/abarax_rig.tscn`, `assets/anim/clips.cfg`, `ASSETS.md`
- Create: clips and moves `counter_hook`, `counter_rise`, `clear_backpalm`, `clear_wave`; layers as needed; `data/fx/clear_ring.tres` if the ground ring needs its own def
- Modify (data): each sway and duck move's `counters`
- Test: `tests/combat/test_counters.gd`, `tests/world/test_clearout_walls.gd`

**Interfaces:**
- Consumes: `MoveRunner.evaded`; `Actor.chain`, `Actor.cashed_tempo`, `ChainTuning.cash_scale` and `clearout_throw` (Task 4); `GroundWave` (`fx/ground_wave.gd`).
- Produces:
  - `MoveData.counters: Dictionary` (action → move id): sways `{palm: counter_hook, heavy: clear_backpalm}`, ducks `{palm: counter_rise, heavy: clear_wave}`.
  - `MoveData.cashes: bool` (true on the four counter moves): its blows carry what the chain was worth.
  - `MoveRunner.COUNTER_FRAMES := 24`: for that many of the actor's `buffer_frame`s after a blow is evaded during move M, a consumed `palm` or `heavy` starts `M.counters[action]`, from M's cancel window or from rest. A counter refused for stamina cashes nothing: the chain stays.
  - `HitProfile.arc_deg := 360.0` (a target further than half of it from the attacker's facing is not hit), `HitProfile.throw := 0.0` (metres the target is thrown; 0 leaves the profile's `knockback`), and `HitProfile.ThrowWay { ALONG_BLOW, RADIAL, SIDEWAYS }` with `@export var throw_way: ThrowWay = ThrowWay.ALONG_BLOW` (RADIAL: straight away from the attacker; SIDEWAYS: to the attacker's right).
  - `HitEvent.power := 1.0`, `HitEvent.always_staggers := false`, `HitEvent.throw := 0.0`. The scanner fills them for a move that `cashes`: `power = cash_scale[cashed_tempo]`; `always_staggers` at FLURRY for a profile with no `throw`; `throw = clearout_throw[cashed_tempo]` for a profile with one.
  - `Combat.resolve`: a HIT's `hp_damage` and `posture_damage` are times `e.power`; `e.always_staggers` staggers whatever the poise.
  - `Melee._weigh`: a blow with `e.throw > 0` pushes its target so that it travels `e.throw` metres in the open (the push travels its speed over `knockback_decay`), the way its profile's `throw_way` says.
  - Two hitboxes on Abarax's rig, at the root: `clear_arc` (a cylinder of radius 1.8 m) and `clear_ring` (radius 2.0 m), each 1.4 m high.

| Move | Blow | Hitbox, profile | Length | Stamina |
|---|---|---|---|---|
| `counter_hook` | `hitbox_on` by frame 8 | a palm; damage 12, posture 18, poise damage 12 (it flinches), line ROUND | 34 frames at most | 8 |
| `counter_rise` | by frame 9 | a palm; damage 14, posture 22, `staggers` | 38 at most | 8 |
| `clear_backpalm` | frames 12–16 | `clear_arc`, `arc_deg` 150, `throw` 2.0, `throw_way` SIDEWAYS, damage 4, posture 8 | 44 at most | 20 |
| `clear_wave` | frames 14–18 | `clear_ring`, `throw` 2.0, `throw_way` RADIAL, damage 3, posture 6, height MID (it is a shove, not a sweep) | 48 at most | 20 |

  - Each counter has a `recovery` mark and a `cancel_open` into `{dodge: dash_step, guard: guard_raise}` from its recovery, and `palm → palm_jab` so a string can go on.
  - `clear_wave` shows a pale gold ground ring from his feet (`GroundWave`, radius 2 m, colour `#f2dea0`) at its `hitbox_on`.
  - Shapes: `counter_hook` is a short hook to the body from the sway's side; `counter_rise` rises from the duck's crouch; `clear_backpalm` turns the body through the arc; `clear_wave` drops a palm to the ground and sweeps round.

- [ ] **Step 1: Write the failing tests** in `tests/combat/test_counters.gd`:

```gdscript
func test_palm_after_an_evade_is_the_dodges_counter_and_heavy_its_clear_out() -> void:   # all four pairings
func test_palm_after_a_dodge_that_avoided_nothing_is_the_jab() -> void:
func test_the_counter_window_is_twenty_four_frames_and_frozen_frames_do_not_count() -> void:   # Review Focus 3
func test_each_counters_blow_comes_by_its_frame() -> void:
func test_a_counter_is_worth_what_its_tempo_says() -> void:        # damage and posture x1, x1.5, x2 on a still target
func test_a_flurry_counter_staggers_a_foe_whose_poise_would_shrug_it_off() -> void:
func test_a_clear_out_throws_two_two_and_a_half_and_three_metres() -> void:   # in the open, within 0.1 m
func test_the_back_palm_hits_only_inside_its_arc_and_the_wave_all_round() -> void:   # three bodies each
func test_a_counter_refused_for_stamina_cashes_nothing() -> void:               # Review Focus 2
func test_a_counter_that_misses_leaves_him_open() -> void:
```

  and in `tests/world/test_clearout_walls.gd` (Review Focus 4):

```gdscript
func test_a_clear_out_by_a_wall_and_in_a_corner_puts_no_one_through_it() -> void:   # the yard's four walls and corners
func test_bodies_thrown_into_each_other_do_not_overlap() -> void:
func test_the_paired_and_the_dead_are_not_thrown_and_a_broken_foe_stays_finishable() -> void:
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_counters` and `--filter=test_clearout_walls`. Expected: FAIL.
- [ ] **Step 3: Build the four clips and moves, then implement the Interfaces above.** Choose each clip's source by a contact sheet of the candidates (`Melee_Hook`, `Punch_Cross`, `Sword_Regular_A/B/C`, `Sword_Heavy_Combo`, with layers), and say in the report which was chosen and why.
- [ ] **Step 4: Look at them** on contact sheets and in a rendered fight frame, as in Task 2.
- [ ] **Step 5: Run** `tools/test.sh`, `tools/godot.sh -s res://tools/clip_check.gd`, `tools/test.sh --render --filter=tests/anim` and the self-test. Expected: all pass; the checker counts 49 moves.
- [ ] **Step 6: Commit.**

---

### Task 6: What the chain looks and sounds like, the slow-down, the HUD

**Files:**
- Create: `fx/chain_fx.gd`, `fx/afterimage.gd`, `data/sounds/evade_whoosh.tres`, `perfect_dodge.tres`, `knocked_out.tres`, `assets/audio/sfx/` the three `.wav` files
- Modify: `combat/melee.gd`, `core/sfx.gd`, `fx/readability_tuning.gd`, `data/tuning/readability.tres`, `hud/hud.gd`, `actors/actor.gd` (it makes the ChainFx), `tools/audio/make_sfx.py`, `ASSETS.md`, `demo/demo_reel.gd`, `STATE.md`, `docs/superpowers/plans/2026-11-01-all-divine-rpg-f1-combat-core.md` (the dodge's Global Constraint line)
- Test: `tests/fx/test_chain_fx.gd`, `tests/render/test_chain_shots.gd`, `tests/combat/test_slow.gd`, additions to `tests/render/test_hud_draw.gd`

**Interfaces:**
- Consumes: `DodgeChain`'s signals (Task 4); `Rig.hold_aura`/the rim (Task 14 of F1); `GroundWave`; `HitResult.perfect`.
- Produces:
  - `Melee.slow(frames: int, share: float) -> void`: for `frames` physics frames every living actor acts on `share` of them, spread evenly, and is frozen on the others. A call while one runs starts over. `Melee.slowed() -> bool`. It uses the actors' own `freeze`, so recorded input replays to the same state.
  - `Sfx.play(id: StringName, at: Variant = null, pitch := 1.0) -> void`.
  - `class_name ChainFx extends Node`, made by the actor when its def has a chain. It listens to the chain and to `got_hit`:
    - every evade: `evade_whoosh` at pitch `2^(min(count, 12) / 12)`;
    - a perfect dodge at any tempo, and every evade at Flurry: an afterimage; a perfect dodge also plays `perfect_dodge`;
    - from Quick on, a white-gold rim on Abarax (`#fff1c8`) at half strength, full at Flurry, off when the chain ends;
    - the chain's first perfect dodge, and the link that enters Flurry: `Melee.slow(12, 0.4)`;
    - knocked out: the rim off, `knocked_out`, no afterimage;
    - cashed in: the counter's palm trail is 1, 1.25 or 1.5 times its size for Slip, Quick or Flurry.
  - `class_name Afterimage extends Node3D` with `static func spawn(rig: Rig, color: Color, frames: int) -> Afterimage`: a still copy of the body's silhouette where it stood, fading over `frames` (8), drawn behind every body and never over one.
  - `ReadabilityTuning`: `afterimage_on := true`, `slowdown_on := true`, `chain_rim_on := true`, `chain_rim_color`, `afterimage_color`, `afterimage_frames := 8`, `slow_frames := 12`, `slow_share := 0.4`.
  - The Hud's icon for a grab is a new 9×9 glyph, a body leaning off a line, in `ICON_CELLS`.
  - Three new cues, made by `make_sfx.py` from seeds, each with a row in `ASSETS.md`.
  - The reel shows a parry, two sways and a duck against a Knuckle's combo, then a counter.
  - `STATE.md` Done gains "F1: the sway-and-duck defence: sways, ducks, the chain, counters and clear-outs, the dash-step", and the owner checklist gains: the three tempos' feel, the screen-relative sways when he faces sideways, the slow-down, being knocked out, the dash-step's reach.
  - The F1 plan's Global Constraints line about the roll's 13 invulnerable frames is replaced by a pointer to this plan's table.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/combat/test_slow.gd
func test_twelve_slowed_frames_let_actors_act_on_forty_percent_of_them() -> void:
func test_a_slow_restarts_and_does_not_stack() -> void:
func test_the_chains_timeout_and_the_counter_window_do_not_run_out_inside_a_slow() -> void:   # Review Focus 3
func test_a_slowed_fight_replays_to_the_same_state() -> void:   # the same ScriptBrain steps twice: equal positions, hp and move ids
# tests/fx/test_chain_fx.gd
func test_the_whoosh_climbs_a_semitone_a_link() -> void:
func test_the_slow_down_comes_on_the_first_perfect_dodge_and_on_entering_flurry_and_no_other_time() -> void:
func test_afterimages_mark_perfect_dodges_and_every_flurry_dodge() -> void:
func test_the_rim_is_off_at_slip_half_at_quick_full_at_flurry_and_gone_when_knocked_out() -> void:
func test_the_counters_trail_grows_with_the_tempo_cashed_in() -> void:
func test_each_switch_turns_its_effect_off() -> void:
# tests/render/test_chain_shots.gd
func test_the_afterimage_and_the_chain_rim_change_no_pixel_inside_his_body() -> void:   # the exact silhouette, as test_rim_matrix does
func test_the_afterimage_is_gone_after_its_frames() -> void:
# tests/render/test_hud_draw.gd
func test_the_grabs_icon_draws_its_new_glyph() -> void:
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_slow`, `--filter=test_chain_fx`, and `tools/test.sh --render --filter=test_chain_shots`. Expected: FAIL.
- [ ] **Step 3: Implement the Interfaces above.**
- [ ] **Step 4: Look at it.** Render a Flurry dodge, a perfect dodge and a knocked-out frame at 640×360 and at the window's scale, Read the PNGs, and fix what does not read. Re-record the reel (`tools/record_reel.sh`) and look at its stills.
- [ ] **Step 5: Run** `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, `tools/godot.sh -s res://tools/clip_check.gd`, the audio tool's tests (`python3 -I -m unittest discover -s tools/audio/tests`), and the self-test from source and from the exported Linux build. Expected: all pass, no ERROR or WARNING lines.
- [ ] **Step 6: Commit.**
