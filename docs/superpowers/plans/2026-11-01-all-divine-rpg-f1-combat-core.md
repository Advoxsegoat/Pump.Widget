# The All-Divine F1 (Combat core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn F0's walking courtyard into a fight: the Open Hand moveset, dodge and hop, guard and parry, stamina, poise and posture, finishers, perilous attacks, hit feel and lock-on. Add one enemy, the Knuckle of the Hand, in tiers I–III, and a training yard to fight it in. The combat bot and input replay check all of it.

**Architecture:** F1 builds on F0's layers.
- **Moves:** a hit is a `HitProfile` named by a clip's `hitbox_on` mark. Hitboxes are found by swept shape queries each tick, not by Area overlaps.
- **Hits:** a new autoload, `Melee`, gathers every hit of a physics frame. It resolves them all against the defenders as they stood at the start of the frame, then applies them, so trades don't depend on node order. It also keeps paired moves (finishers, grabs) in step.
- **Rules:** `Combat.resolve` is a pure function holding every rule of §4.2–4.4, so a table of tests pins the rules.
- **Actors:** `Stats` gains behaviour (stamina, posture, poise). Guard is an upper-body stance layer in the rig. Enemies get a data-driven `EnemyBrain` with attack tokens.
- **Clips:** new clips come from Quaternius's second CC0 animation library (UAL2), retimed with piecewise time warps and joined end to end. Where no clip fits, a hand-keyed additive layer is added on top. All of it is driven by `clips.cfg`.
- **Sound:** sounds are made by our own seeded synthesiser.

**Tech Stack:**
- Godot 4.7.2-stable, typed GDScript.
- Python 3.13 with the standard library for the sound tool.
- `bpy` 5.2.3 via `uv` for the Knuckle's model.
- Xvfb with Mesa for renders.
- GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md` (approved 2026-10-25). F1 is the second row of its §9. The rules come from §4 (Combat and controls), §3.5 (Readability rules), §7.3 (Combat moments) and §8 (Testing and tools).

Read with it:
- `all-divine/STATE.md`: what F0 left, including its "For F1" notes;
- `docs/superpowers/plans/2026-10-25-all-divine-rpg-f0-foundation-record.md`: F0's rulings, and the deferred minors this plan folds in.

## Global Constraints

**Carried over from F0, unchanged:**
- Engine: Godot **4.7.2-stable** (`4.7.2.stable.official.ed1daf0bf`), with typed GDScript.
- Everything lives in `all-divine/`. Scenes and resources are plain text.
- Content is data, never code. There is one way to animate anything: through a rig and clips. Layers talk downward or through signals.
- Frames are 1/60 s physics ticks:
  - input response is **2 frames at most**;
  - the input buffer is **9 frames (150 ms)**;
  - the dodge: the roll and its 13 invulnerable frames are gone; sways and ducks have evade windows of 6 to 12 frames by tempo, and the dash-step is never invulnerable (see the table in [`2026-11-10-all-divine-sway-defence.md`](2026-11-10-all-divine-sway-defence.md), Global Constraints);
  - hit-stop is **3–6 frames**.
- Every system has tests that run headless in the container, with our own runner.
- Green runs print no `ERROR:` or `WARNING:` lines (Ruling R1: error paths are asserted through `quietly()` and returned data).
- Assets are free and openly licensed only, or made by us. **Every file under `all-divine/assets/` has a row in `ASSETS.md`.**
- `STATE.md` says what is done and what is next. Every task's final commit appends one line under `STATE.md → Done`.
- Commit messages start `All-Divine F1: `, end with the attribution trailers this session specifies, and never name a model.

**From the spec, for F1:**
- **Controls (§4.1):**
  - Palm strike (combo): RB / left mouse.
  - Heavy (hold to charge): RT / right mouse.
  - Guard, where a timed tap parries: LB / Q.
  - Dodge (hold to sprint): A / Shift or Space.
  - Lock on and switch target: R3 and the right stick / Tab, and the mouse wheel while locked.
  - When not locked on, keyboard and mouse face the cursor.
- **Feel (§4.2):**
  - Cancels are marked per clip. Attacks cancel into dodge from their recovery, and combo steps chain inside their windows.
  - **Aim assist** turns an attack toward a target within **30°** of the stick during wind-up.
- **Stamina (§4.2):**
  - It is spent by attacks, dodges, sprinting and guarding.
  - It regenerates after a **0.6 s** pause.
  - At zero you can still move, but can't attack or dodge until it refills a little.
- **Hit weight (§4.2):** every hit lands with hit-stop scaled by the move's weight, camera shake and knockback, sparks, an additive flinch on the target, and layered sound (impact, voice, surface).
- **Poise (§4.4):** enemies flinch unless a move's poise damage is lower than their poise. Heavy and charged strikes break poise into a stagger. Hyper-armour frames are marked on the clip.
- **Posture (§4.4):**
  - It is a second bar beside HP.
  - Parries, guards against heavy attacks, and heavy hits wear it down.
  - It recovers when the fighter is not under pressure.
  - Broken posture opens an **Open Hand finisher of 1.5 s at most**.
- **Perilous attacks (§4.4):**
  - They are marked with a **red rose flash** and their own sound.
  - Each has one counter: a **sweep** is jumped or stepped over, a **thrust** is countered by an **Open Hand catch** (a parry variant), and a **grab** is dodged.
- **Readability (§3.5):** every enemy attack has anticipation frames and a tell (a glint, a colour flash, a sound).
- **Enemies (§4.5):**
  - Brains are data-driven state machines: perception, spacing, attack choice, reactions.
  - **Attack tokens:** only one or two enemies commit at a time.
  - Tiers I–III add new tells, feints, delayed swings and combo extensions, not just bigger numbers.
- **Tools (§8):**
  - the clip checker fails the build;
  - the **combat bot** plays encounters through real input actions, reports errors, soft-locks and broken encounters, and records replays of failures;
  - input recording and replay;
  - feel metrics (press-to-motion, the frame-time budget, animation coverage).

**Decisions this plan makes where the spec leaves room, for the owner to see:**
- **Hand-keyed moves are built by GDScript, not `bpy`.** Where no CC0 clip fits, a move is hand-keyed as an additive bone layer (a JSON of key rotations) that the library builder lays over a clip. The spec names `bpy` for hand-keying. This keeps keyed moves in the same tool that builds every other clip, and its tests run headless. `bpy` stays for models and retargeting.
- **Sounds are made by our own seeded synthesiser** (`tools/audio/make_sfx.py`). The Kenney asset pages no longer carry a `.zip` link that `fetch.py` can read (see Environment facts). Every cue is data, so recorded sounds can replace any of them later.
  - The **voice** layer of a hit's sound is wired and tested. No CC0 grunts are in the project, so every actor's voice cue is empty until there are some.
- **"Jump or step over" is a neutral dodge.** The controls table has no jump button, so the dodge with the stick at rest is a hop (Souls' backstep slot). With the stick pushed, it stays the roll.
- **No Rose Flask in F1.** The Flask belongs with shrines (F3). The arena refills Abarax between waves.
- **Finishers in F1 are gameplay only.** The camera dip and slow-motion beat are F4's "finishers as combat moments". F1 emits `Actor.combat_moment` for them to hook into.
- **A combat autoload, `Melee`.** Hits are gathered and resolved once per frame by one node that runs after every actor (`process_physics_priority = 100`). Without it, a trade's result would depend on which actor's script ran first.

## Review Focus

Five conditions the tasks' main tests don't reach on their own, ordered by how likely each is to hurt the person playing:

1. **Trades: two fighters hit each other on the same frame.** Both hits land and both react, whatever order the actors' scripts ran in. Hit-stop is the longer of the two, not their sum. The test is in Task 5.
2. **Hits mid-state.** This covers being hit during hit-stop, mid-cancel, mid-charge, while guarding with the back turned, inside a paired move, or after death.
   - A flinch cancels a charge, and the next heavy starts uncharged.
   - Actors in a paired move are never hit by anyone else.
   - The dead are never hit, never attack and never die twice.
   - The tests are in Tasks 5, 7 and 10.
3. **Lock-on with an awkward target.** The target dies mid-combo, walks past 20 m, or is the only enemy and is behind Abarax. Lock-on is pressed with no enemy at all. The lock drops cleanly, aim assist falls back to the stick, and nothing errors. The tests are in Task 11.
4. **Pressing several buttons at once, or mashing.** This covers guard and palm pressed on the same frame, a mashed dodge, a mashed guard, and heavy held through a flinch.
   - One outcome is chosen, the same way every time (guard wins a same-frame tie with an attack).
   - Mashing never extends a parry window or invulnerability.
   - A held heavy never charges across a reaction.
   - The tests are in Tasks 7 and 8.
5. **Walls and corners.** This covers knockback into a wall or corner, and enemies spacing near walls.
   - Nobody leaves the yard or sticks in geometry.
   - An enemy that can't reach its spacing for 3 s picks another angle.
   - The tests are in Tasks 13 and 14.

## Environment facts (probed 2026-11-01)

| Fact | Value |
|---|---|
| Test counts at F1 start | `tools/test.sh`: 445 passed, 0 failed. `--render`: 475. `--forward-plus`: 475. `clip_check: 3 moves, 1 actors OK` |
| `ual2` | `https://quaternius.itch.io/universal-animation-library-2`, itch flow as for `ual1`. The zip's sha256 is `4008ea208a604773a2b2177d965f0f5d3195498b5bf838c3f5785d68e95f2a68` (18.7 MB). CC0 1.0 (`License.txt`). Use `Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb` and `UAL2_Standard_RM.glb` (root motion). It has the same 65-joint skeleton as UAL1 and 43 clips |
| UAL2 clips F1 uses (seconds) | `Melee_Hook` 0.467, `Melee_Hook_Rec` 0.6, `OverhandThrow` 1.333, `Idle_Shield_Loop` 2.5, `Idle_Shield_Break` 1.067, `Sword_Block` 1.233, `Shield_OneShot` 0.833, `Hit_Knockback` 0.833, `NinjaJump_Start` 0.967, `NinjaJump_Land` 1.267, `Slide_Start` 0.833, `Slide_Exit`, `Sword_Dash` 1.567, `Zombie_Scratch` 1.8, `LayToIdle` 1.533, `Idle_FoldArms_Loop` 2.5. Others: `Hit_Knockback`, `Shield_Dash`, `Idle_No_Loop`, `Consume`, the sword combos |
| UAL1 clips F1 adds | `Hit_Chest`, `Hit_Head`, `Death01` (already in the pack F0 fetched) |
| The Knuckle's parts | All are CC0. From `outfits`: `Male_Ranger_Body`, `_Legs`, `_Arms`, `_Feet_Boots`, `_Head_Hood` and `_Acc_Pauldron`. From `ubc`: hairstyles `Hair_Buzzed` and `Hair_Beard`, and the `Superhero_Male` base (Abarax's, so the skeleton and rest pose are identical) |
| Kenney packs | kenney.nl's asset pages (`impact-sounds`, `fantasy-town-kit`) now have no `.zip` link that `fetch.py`'s `parse_kenney_zip` finds. The town kit is cached; new Kenney packs can't be fetched without changing the fetcher |
| Lore | From *Between the Rooms* `lore.js`: "A Knuckle of the Hand: three blows in a row, then open." Its look is `knuckle`, and First Knuckle is the Hand's boss (F5) |

## File structure

New and changed files. Paths are under `all-divine/` unless they start with `docs/` or `.github/`.

```
core/        layers.gd (new: physics-layer bits)  test_logger.gd (moved from tools/test/)  sfx.gd (new autoload Sfx)
             bindings.gd inputs.gd (target_left/right, last device)
combat/      hit_event.gd defense.gd hit_result.gd combat.gd combat_tuning.gd hit_scanner.gd
             melee.gd (autoload Melee)  attack_tokens.gd
moves/       move_data.gd (hits, kinds, neutral_variant)  hit_profile.gd  marks.gd (kinds)  move_runner.gd
             paired_move.gd
actors/      actor.gd actor_def.gd stats.gd intent.gd rig.gd player_brain.gd mark_sink.gd
             lock_on.gd  enemy_brain.gd brain_def.gd attack_option.gd
             knuckle/knuckle_rig.tscn  liveliness/{breathing,hit_react}.gd
audio/       sound_cue.gd
fx/          fx_def.gd actor_fx.gd  hit_spark.tscn palm_trail.tscn roll_dust.tscn glint.tscn perilous_rose.tscn
             charge_glow.tscn
hud/         hud.gd hud.tscn
world/       arena.gd arena_wave.gd  training_yard/{layout.txt,training_yard.tscn}
render/      camera_rig.gd (shake, lock lean, cursor_ground)  pixel_stage.gd/.tscn (Hud viewport)
             shaders/toon_character.gdshader (flash)
data/        moves/*.tres (Abarax, shared reactions, knuckle_*)  pairs/*.tres  brains/knuckle_{1,2,3}.tres
             actors/knuckle_{1,2,3}.tres  palettes/knuckle_{1,2,3}.tres  tuning/combat_{abarax,knuckle}.tres
             sounds/*.tres  fx/*.tres  arena/waves.tres  render/grades/training_yard.tres
assets/      anim/clips.cfg  anim/layers/*.json  anim/abarax/*.tres (new clips)  audio/sfx/*.wav
             characters/knuckle/knuckle.glb
tools/       anim/{clip_builder.gd,build_library.gd,build_knuckle.py,bpy_common.py}  world/build_region.gd
             audio/{make_sfx.py,tests/}  replay/{input_recording.gd,recorder.gd,replayer.gd}
             bot/{combat_bot.gd,run_bot.gd}  clip_checker.gd  assets/sources.json
tests/       combat/ (new)  hud/ (new)  replay/ (new)  bot/ (new), plus additions under actors/ moves/ anim/ feel/ perf/ world/ main/
```

`assets/anim/abarax/` stays the one library: the Knuckle's rig has the same skeleton path and rest pose, so it plays the same clips (Task 12 tests this).

Physics layers are unchanged from F0 and are now named in one place, `core/layers.gd`: `world` 1, `ik_surface` 2, `actor` 3, `hurtbox` 4, `hitbox` 5, `interact` 6.

---

### Task 1: F0 debts and shared helpers

STATE.md's "For F1" notes and the deferred minors that F1's work runs into.

**Files:**
- Create: `core/layers.gd`
- Move: `tools/test/test_logger.gd` → `core/test_logger.gd` (update `core/self_test.gd`, `tools/test/run.gd` or wherever it is loaded, and `export_presets.cfg`, which now excludes `tools/*`)
- Modify: `actors/actor.gd`, `actors/rig.gd`, `actors/liveliness/{breathing,hit_react}.gd`, `actors/actor_def.gd`, `moves/move_runner.gd`, `tests/support/test_arena.gd`, `tools/world/build_courtyard.gd`, `tests/tools/test_export_presets.gd`, `tests/moves/test_clip_checker.gd`
- Test: `tests/core/test_layers.gd`, `tests/actors/test_cancel_reset.gd`, additions to `tests/actors/test_rig.gd`, `test_breathing.gd`, `test_hit_react.gd` and `test_look_at.gd`

**Interfaces:**
- Produces:
  - `class_name Layers extends RefCounted`:
    - `const WORLD := 1, IK_SURFACE := 2, ACTOR := 4, HURTBOX := 8, HITBOX := 16, INTERACT := 32`;
    - `static func bit(layer_name: String) -> int`, which reads `layer_names/3d_physics` and returns 0 for an unknown name.
  - Every former `layer_bit` helper calls `Layers.bit` (in `TestArena` and the courtyard builder), and `Actor.IK_SURFACE_MASK` becomes `Layers.IK_SURFACE`.
  - `Actor.snap_facing(yaw: float) -> void` sets `locomotion.facing_yaw` and `rotation.y`. MoveRunner's dodge uses it and no longer writes either field itself.
  - `Actor.head_point() -> Vector3` is the global position plus `UP × def.look_height`. `@export var look_height := 1.6` goes on `ActorDef`. `Actor._choose_look_target` looks at a POI that is an `Actor` at its `head_point()`.
  - `Rig.SNAPSHOT_CLIP := &"__snapshot"`. When `play_move` runs while a crossfade between the move slots is still under way, the slot being faded out is loaded with a one-key snapshot clip of the pose shown this tick, and the crossfade restarts from it. A cancel inside `blend_in` can't jump the pose (F0 note).
  - `Rig.set_breath_phase(phase: float) -> void` (radians). `Actor._ready` sets it to `float(hash(name) % 6283) / 1000.0`, so actors don't breathe in step (F0 minor).
  - `HitReact.react` normalises `dir_world`, and `HitReact.MAX_TILT := 0.35` (radians) caps the lean (F0 minor).
  - While `runner.busy()`, the actor gives `rig.set_locomotion` a speed of 0, so the roll's carried speed no longer shows as a run under the move layer (F0 minor).

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/core/test_layers.gd
func test_constants_match_project_layer_names() -> void:
	for pair in [["world", Layers.WORLD], ["ik_surface", Layers.IK_SURFACE], ["actor", Layers.ACTOR],
			["hurtbox", Layers.HURTBOX], ["hitbox", Layers.HITBOX], ["interact", Layers.INTERACT]]:
		assert_eq(Layers.bit(pair[0]), pair[1], pair[0])
func test_unknown_layer_is_zero() -> void:
	assert_eq(Layers.bit("nope"), 0)
# tests/actors/test_cancel_reset.gd (TestArena, Abarax, ScriptBrain)
func test_jab_cancelled_into_cross_turns_its_hitbox_off() -> void:
	# press palm, then palm again on frame 15 (the window): on the frame cross starts, palm_l is inactive
	# and runner.current.id == &"palm_cross"
func test_jab_cancelled_into_roll_at_its_recovery_window() -> void:
	# palm, then dodge with the stick pushed at f20: no hitbox active, iframes on from the roll's f3
func test_roll_cancelled_into_jab_clears_iframes_and_the_window() -> void:
	# dodge, then palm at f22: iframes false, window replaced by the jab's (empty until f15)
# test_rig.gd
func test_cancel_inside_blend_in_does_not_jump_the_pose() -> void:
	# play_move(jab, 0.1); 2 ticks; play_move(cross, 0.1): the largest change of any bone's shown
	# position over the cancel tick is no more than 1.5x that bone's change over the tick before it
# test_breathing.gd
func test_two_actors_do_not_breathe_in_step() -> void:   # chest offsets of "A" and "B" differ at the same frame
# test_hit_react.gd
func test_lean_is_capped_and_direction_length_does_not_matter() -> void:
	# ten kicks of strength 1 in a row: |tilt| <= MAX_TILT; react(dir * 5, 1) == react(dir, 1)
# test_look_at.gd
func test_actor_poi_is_looked_at_head_height() -> void:   # rig.looking_at() y == other.head_point().y (±0.01)
```

- [ ] **Step 2: Run `tools/test.sh --filter=test_layers` and then the other files.**
  Expected: FAIL. `Layers` is missing, the pose jumps, the breaths are equal, the lean is unbounded, and the actor POI is looked at the feet.

- [ ] **Step 3: Implement the Interfaces above, and move TestLogger.**
  - Change `tests/moves/test_clip_checker.gd` and `tests/tools/test_ci_workflow.gd` so that they no longer pin "3 moves, 1 actors". They compare against `Registry.ids(&"moves").size()` and `Registry.ids(&"actors").size()` (F0 minor).
  - Update `test_export_presets.gd`: the exports now leave out `tools/*`, and the self-test still finds `core/test_logger.gd`.

- [ ] **Step 4: Run `tools/test.sh` and `tools/test.sh --render`, then export Linux and run its `--selftest`.**
  Expected: all pass with no noise, and the exported self-test exits 0.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 1: F0 debts: Layers, TestLogger in core/, snapshot crossfade, breath phase, capped hit lean, head-height looks". Remove the F1 notes it covers from STATE.md's "For F1" list.

### Task 2: Clip sources: UAL2, time warps, joins and keyed layers

**Files:**
- Modify: `tools/assets/sources.json` (`ual2`), `tools/anim/clip_builder.gd`, `tools/anim/build_library.gd`, `assets/anim/clips.cfg`, `ASSETS.md`
- Test: `tests/anim/test_clip_builder.gd`, `tests/anim/test_library.gd`, `tools/assets/tests/test_fetch.py` (sources)

**Interfaces:**
- Consumes: `ClipBuilder.build(cfg_path, sources, out_dir, model_path)` and its source keys `ual1` and `ual1_rm` (F0).
- Produces:
  - **Source keys** `ual2` and `ual2_rm` map to `UAL2_Standard.glb` and `UAL2_Standard_RM.glb` under `.cache/extract/ual2/`. Fetch them with `python3 -I tools/assets/fetch.py fetch ual2`; the hash is in Environment facts.
  - **New `clips.cfg` keys** (sections are as in F0):
    - `then=PackedStringArray([...])`: clips appended end to end after `clip`.
      - Each entry is `"Clip"` (same source) or `"source:Clip"`.
      - Every track of an appended clip starts where the previous one ended in time.
      - Root and pelvis positions of an appended clip are offset so the root continues from where the last one stopped, with no jump.
    - `warp=PackedFloat32Array([out0, src0, out1, src1, ...])`: a piecewise-linear map from output time to source time over the joined clip.
      - Output times start at 0 and increase. Source times may stay the same (a hold) or go back (a reverse).
      - The clip's length is the last output time.
      - Every track is resampled at 60 Hz.
      - `warp` and `length` together is a config problem.
    - `layer="res://assets/anim/layers/<name>.json"`: additive bone rotations, laid on after warping.
      - The JSON is `{"bone": [[frame, x_deg, y_deg, z_deg], ...]}`, as Euler degrees in the bone's local space (YXZ order).
      - Rotations are linear between keys and zero before the first key and after the last.
      - Each one post-multiplies the clip's rotation at that frame.
  - **Config problems** (each is a returned error line, and nothing is written):
    - `length` and `warp` together;
    - an odd-sized or non-increasing `warp`;
    - a `then` clip or a layer bone that doesn't exist;
    - a negative `length`;
    - a `step_fps` that isn't 0, 12 or 24 (F0 minor).
  - `static func warp_time(warp: PackedFloat32Array, out_t: float) -> float`, which is public for tests.

- [ ] **Step 1: Write the failing tests** (in memory, on `GltfFixture` clips as F0's builder tests do).

```gdscript
func test_warp_hold_keeps_the_pose() -> void:
	# warp [0,0, 0.1,0.1, 0.3,0.1]: the pose at out 0.2 equals the source pose at 0.1 (every bone, 1e-4)
func test_warp_can_play_backward() -> void:
	# warp [0,0, 0.2,0.2, 0.4,0.0]: out 0.3 equals source 0.1
func test_warp_time_is_piecewise_linear() -> void:
	assert_near(ClipBuilder.warp_time(PackedFloat32Array([0,0, 1,2]), 0.5), 1.0, 1e-6)
func test_join_continues_root_motion_without_a_jump() -> void:
	# A (root 0 -> 1 m on z) then B (root 0 -> 1 m): joined root at A's end == 1.0, at the end == 2.0
func test_layer_adds_its_rotation_between_keys_only() -> void:
	# layer {"hand_r": [[10, 0, 0, 0], [20, 30, 0, 0], [30, 0, 0, 0]]}: f20 is the clip's rotation times
	# 30° about local Y; f5 and f35 equal the unlayered clip
func test_config_problems_are_reported_not_written() -> void:
	# length+warp; warp [0,0,0.5]; then="Nope"; a layer bone "nope"; length=-1; step_fps=10: one problem each
# test_library.gd
func test_library_holds_every_clips_cfg_section() -> void:   # unchanged rule; it now covers the new sections
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/anim`.**
  Expected: FAIL, because the keys aren't read yet.

- [ ] **Step 3: Implement `then`, `warp`, `layer` and the validation in `ClipBuilder`.**
  - Add `ual2` to `sources.json`, and add `ual2`/`ual2_rm` to `build_library.gd`'s source map.
  - Run `fetch.py fetch ual2` (the recorded hash must match the one above).
  - Add the ASSETS.md row: `assets/anim/abarax/` now also comes from UAL2 Standard and Standard_RM; Changes says "retimed by warps, joined, some with keyed layers (assets/anim/layers/)". The layers folder gets its own row (`ours`) in Task 8, with its first file.

- [ ] **Step 4: Run `tools/test.sh`, `tools/godot.sh -s res://tools/anim/build_library.gd`, and `tools/test.sh` again.**
  Expected: all pass. A rebuild with no new sections changes no committed clip byte, because existing sections don't use the new keys.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 2: clip sources: UAL2, warps, joins, keyed layers".

### Task 3: Combat data: hit profiles, marks, tuning and the checker

**Files:**
- Create: `moves/hit_profile.gd`, `combat/combat_tuning.gd`, `data/tuning/combat_abarax.tres`
- Modify: `moves/move_data.gd`, `moves/marks.gd`, `actors/mark_sink.gd`, `actors/actor_def.gd`, `tools/clip_checker.gd`, `tools/anim/set_marks.gd` (no change to its format), `data/moves/{palm_jab,palm_cross,dodge_roll}.tres`, `data/actors/abarax.tres`, the marks of `assets/anim/abarax/{palm_jab,palm_cross}.tres`
- Test: `tests/moves/test_hit_profile.gd`, `tests/moves/test_clip_checker.gd`, `tests/moves/test_move_data.gd`, `tests/moves/test_marks.gd`

**Interfaces:**
- Produces:
  - **`class_name HitProfile extends Resource`:**
    - `enum Height { MID, LOW }` and `enum Perilous { NONE, SWEEP, THRUST, GRAB }`;
    - `@export var damage := 0.0`, `poise_damage := 0.0`, `posture_damage := 0.0`, and `guard_stamina := 0.0` (what a guard spends to block it);
    - `@export var knockback := 0.0` (m/s, along the hit) and `@export_range(3, 6) var hitstop_frames := 3`;
    - `@export var shake := 0.0` (0–1) and `@export var staggers := false`;
    - `@export var height: Height = Height.MID` and `@export var perilous: Perilous = Perilous.NONE`;
    - `@export var impact_sound := &"impact_palm"`;
    - `func guardable() -> bool` is true for `NONE`;
    - `func parryable() -> bool` is true for `NONE` and `THRUST` (a parried thrust is a catch).
  - **`MoveData`:**
    - `enum Kind { ATTACK, DODGE, OTHER, REACTION }`;
    - `posture_damage` and `poise_damage` are removed (they were unused and 0);
    - `@export var hits: Dictionary = {}`, mapping a profile name (StringName) to a HitProfile, inline in the move's `.tres`;
    - `@export var aim := true` turns toward the intent's aim target during wind-up (Task 7);
    - `@export var neutral_variant: StringName` is the move started instead when the stick is at rest (Task 9).
  - **`Marks.KINDS`:**
    - `hitstop` is removed; hit-stop now comes from the profile, on contact (F0 note);
    - added: `parry_on`, `parry_off`, `guard_on`, `guard_off`, `airborne_on`, `airborne_off`, `tell`, `charge_hold` and `pair_hit`;
    - `MarkSink` gets one method per kind and loses `hitstop`.
  - **Mark arguments:**
    - `hitbox_on {id, profile}`, where `profile` is a key of `move.hits`;
    - `tell {kind}`, where `kind` is `&"glint"` or `&"perilous"`;
    - `charge_hold {action, frames, profile}`: while `action` is held, the clip waits at this mark for up to `frames`. Held to the end, the move's later hits use `profile` (Task 7);
    - `pair_hit {profile}` (Task 10).
  - **`class_name CombatTuning extends Resource`.** Each value has a doc comment. The defaults are `combat_abarax.tres`'s values:

    | Group | Values |
    |---|---|
    | Stamina | `stamina_regen_rate := 45.0` (per s), `stamina_regen_delay := 0.6`, `guard_regen_scale := 0.4`, `exhausted_until := 20.0`, `sprint_stamina := 12.0` (per s) |
    | Posture | `posture_regen_delay := 1.5`, `posture_regen_rate := 20.0`, `broken_time := 2.0` |
    | Guard, parry and catch | `guard_arc_deg := 75.0`, `guard_speed_scale := 0.45`, `parry_posture_scale := 2.0`, `catch_posture := 50.0` |
    | Finisher | `finisher_range := 1.6`, `finisher_arc_deg := 60.0` |
    | Aim assist | `aim_assist_deg := 30.0`, `aim_assist_range := 3.5`, `aim_turn_rate_deg := 540.0` |
    | Knockback | `knockback_decay := 10.0` (per s) |

  - **`ActorDef`:**
    - `enum Team { PLAYER, ENEMY }` and `@export var team: Team`;
    - `@export var combat: CombatTuning`;
    - `@export var reactions: Dictionary = {}`, mapping each reaction name to a move id. The names are `flinch`, `stagger`, `guard_hit`, `guard_break`, `parried`, `caught`, `posture_broken`, `death` and `getup`, plus the defender's answers `parry` and `catch`. Each task that adds one sets it in every def that has the clip (Tasks 5, 8, 10 and 14 for Abarax, and Task 12 for the Knuckles);
    - `@export var surface_sound := &"surface_cloth"` and `@export var hurt_voice := &""`.
  - **`ClipChecker`, new rules:**
    - an ATTACK has at least one entry in `hits`, and every `hitbox_on.profile` is one of its keys;
    - `parry_on`/`parry_off`, `guard_on`/`guard_off` and `airborne_on`/`airborne_off` come in on-then-off pairs;
    - a REACTION other than `death` has one `recovery`;
    - `tell.kind` is `glint` or `perilous`;
    - **for actors of team ENEMY:** every ATTACK has a `tell` at least **12 frames** before its first `hitbox_on`, and a move with any perilous profile has a `perilous` tell;
    - `charge_hold` is only in an ATTACK, and names a profile it has;
    - check_all's reachability now also follows `reactions`, `neutral_variant`, pairs and brain attacks. The last two are reported once those kinds exist (Tasks 10 and 13).

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_hit_profile.gd
func test_guardable_and_parryable_by_kind() -> void:
	# NONE: guardable, parryable · SWEEP: neither · THRUST: parryable only · GRAB: neither
# test_move_data.gd
func test_move_data_has_hits_and_no_old_fields() -> void:
	assert_false("posture_damage" in MoveData.new()); assert_true("hits" in MoveData.new())
func test_abarax_jab_and_cross_have_a_palm_profile() -> void:   # jab hits[&"palm"].hitstop_frames == 3; cross == 4
# test_marks.gd
func test_kinds_drop_hitstop_and_add_the_combat_kinds() -> void:
# test_clip_checker.gd
func test_hitbox_profile_must_exist() -> void:              # "unknown profile"
func test_attack_without_hits_is_reported() -> void:        # "no hits"
func test_enemy_attack_needs_a_tell_twelve_frames_ahead() -> void:   # tell at f10, hitbox_on at f15: "tell"
func test_perilous_hit_needs_a_perilous_tell() -> void:
func test_unpaired_parry_window_is_reported() -> void:
func test_reaction_without_recovery_is_reported() -> void:  # death is exempt
func test_real_data_passes() -> void:                       # check_all() is empty
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/moves`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above, and migrate the data.**
  - `palm_jab` gets `hits = {&"palm": HitProfile(damage 8, poise 6, posture 4, guard_stamina 8, hitstop 3, knockback 1.0)}`.
  - `palm_cross` gets `{&"palm": (10, 8, 6, 10, hitstop 4, knockback 1.5)}`.
  - Their `hitbox_on` marks get `profile: palm`, and their `hitstop` marks are removed (rewrite them with `set_marks.gd` from F0's table, minus hitstop, plus the profile).
  - `abarax.tres` gets `team = PLAYER` and `combat = combat_abarax.tres`.
  - Set `reactions = {}` for now; Task 5 fills it.

- [ ] **Step 4: Run `tools/test.sh` and `tools/godot.sh -s res://tools/clip_check.gd`.**
  Expected: all pass, and clip_check is OK.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 3: combat data: HitProfile, mark kinds, CombatTuning, checker rules".

### Task 4: Stats in play: stamina, posture and poise

**Files:**
- Modify: `actors/stats.gd`, `actors/actor.gd`, `moves/move_runner.gd`, `data/moves/*.tres` (stamina costs)
- Test: `tests/actors/test_stats.gd`, `tests/actors/test_stamina.gd`

**Interfaces:**
- Consumes: `CombatTuning` and `ActorDef.combat` (Task 3).
- Produces:
  - **`Stats`** (still a RefCounted, made by `from_def`):
    - `var max_hp`, `max_stamina` and `max_posture`;
    - `var tuning: CombatTuning`, `var exhausted := false` and `var posture_broken := false`.
  - **Its functions:**
    - `func can_act() -> bool` is `stamina > 0.0 and not exhausted`;
    - `func spend_stamina(amount: float) -> void` floors at 0, sets `exhausted` at 0, and restarts the regen delay;
    - `func drain_stamina(rate: float, delta: float) -> void` is for sprinting; it also restarts the delay;
    - `func take_damage(amount: float) -> bool` floors HP at 0 and returns true on the hit that empties it;
    - `func damage_posture(amount: float) -> bool` floors at 0 and restarts the posture delay. On the hit that empties it, it returns true and sets `posture_broken`;
    - `func restore_posture() -> void` sets posture to full and `posture_broken` to false;
    - `func tick(delta: float, guarding: bool) -> void`:
      - after `stamina_regen_delay`, stamina regenerates at `stamina_regen_rate`, scaled by `guard_regen_scale` while guarding;
      - `exhausted` clears once stamina is at least `exhausted_until`;
      - after `posture_regen_delay`, and not while broken, posture regenerates at `posture_regen_rate`;
      - poise, the threshold a hit must reach to flinch, is the def's `poise` and doesn't change.
  - **`MoveRunner._start`:**
    - an ATTACK or DODGE when `not stats.can_act()` is refused, and the press is used up;
    - a started move spends `move.stamina_cost` at once.
  - **`Actor`:**
    - a sprint drains `sprint_stamina` per second;
    - an exhausted actor doesn't sprint;
    - `stats.tick` runs once per physics frame.
  - **Stamina costs:** `palm_jab` 12, `palm_cross` 14, `dodge_roll` 18.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_stats.gd (pure)
func test_stamina_waits_point_six_seconds_then_regenerates() -> void:
	# spend 50; tick 0.59 s in 1/60 steps: still 50; by 1.6 s: 50 + 45 x (1.6 - 0.6) = 95 (±1)
func test_exhausted_at_zero_until_twenty() -> void:   # spend 200: can_act false until stamina >= 20
func test_guarding_slows_regen() -> void:              # same as the first, guarding: +45 x 0.4 per second
func test_posture_breaks_once_and_recovers_after_its_delay() -> void:
	# damage_posture(100) is true once; a second call is false; restore_posture refills
func test_take_damage_reports_the_killing_blow_once() -> void:
# test_stamina.gd (TestArena)
func test_roll_costs_eighteen() -> void:
func test_no_attack_or_dodge_at_zero_but_walking_works() -> void:
	# stats.spend_stamina(999); press palm and dodge: runner stays idle; the stick still moves him
func test_sprint_drains_then_stops_when_exhausted() -> void:
```

- [ ] **Step 2: Run `tools/test.sh --filter=stats` and `--filter=stamina`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.**

- [ ] **Step 4: Run `tools/test.sh`.**
  Expected: all pass. F0's feel tests still pass, because a full bar always allows the first move.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 4: stats in play: stamina gates and regen, posture, poise".

### Task 5: Hits: scanning, resolving and reacting

**Files:**
- Create: `combat/{hit_event,defense,hit_result,combat,hit_scanner,melee}.gd`; register the `Melee` autoload in `project.godot`
- Create: `data/moves/{flinch,stagger,death}.tres`, and their sections in `assets/anim/clips.cfg`
- Modify: `actors/actor.gd`, `moves/move_runner.gd`, `actors/rig.gd` (`hitbox_shape(id)`, `hurtbox`), `data/actors/abarax.tres` (reactions)
- Test: `tests/combat/test_combat.gd`, `tests/combat/test_hit_scanner.gd`, `tests/combat/test_hits.gd`

**Interfaces:**
- Consumes: `HitProfile`, `MoveData.hits`, `CombatTuning`, `Stats` (Tasks 3–4), `Layers` (Task 1).
- Produces:
  - **`class_name HitEvent extends RefCounted`:**
    - `var attacker: Actor`, `target: Actor`, `move: MoveData` and `profile: HitProfile`;
    - `var hitbox: StringName`, `point: Vector3`, and `direction: Vector3` (flat, normalised, from the attacker through the target).
  - **`class_name Defense extends RefCounted`:**
    - `static func of(actor: Actor) -> Defense` is a snapshot of `invulnerable`, `airborne`, `guarding`, `parrying`, `hyperarmour`, `facing: Vector3`, `poise: float`, `stamina: float`, `posture_broken`, `dead` and `paired`;
    - `guarding` and `parrying` are false until Task 8 sets them.
  - **`class_name HitResult extends RefCounted`:**
    - `enum Outcome { WHIFF, HIT, GUARDED, GUARD_BREAK, PARRIED, CAUGHT, GRABBED }`;
    - `enum Reaction { NONE, FLINCH, STAGGER }`;
    - `var outcome`, `reaction`, `hp_damage`, `posture_damage`, `stamina_cost` and `attacker_posture_damage`.
  - **`class_name Combat extends RefCounted`.** `static func resolve(e: HitEvent, d: Defense, tuning: CombatTuning) -> HitResult` is pure. The first rule that applies wins:
    1. `d.dead`, `d.paired` or `d.invulnerable`: WHIFF.
    2. A LOW profile against `d.airborne`: WHIFF.
    3. A `GRAB` profile: GRABBED (in this task, it is applied as a HIT with STAGGER; Task 10 makes it paired).
    4. `d.parrying`, with the attacker inside `guard_arc_deg` of `d.facing`:
       - a NONE profile is PARRIED, with `attacker_posture_damage = posture_damage × parry_posture_scale`;
       - a THRUST profile is CAUGHT, with `attacker_posture_damage = catch_posture`;
       - a SWEEP falls through.
    5. `d.guarding`, with the attacker inside the arc and `profile.guardable()`:
       - if `d.stamina >= guard_stamina`, GUARDED, with `stamina_cost = guard_stamina` and `posture_damage`;
       - otherwise GUARD_BREAK, with `stamina_cost = d.stamina` and `posture_damage`.
    6. Otherwise HIT, with `hp_damage = damage` and `posture_damage`. The reaction is NONE if `d.hyperarmour`, else STAGGER if `poise_damage >= d.poise and staggers`, else FLINCH if `poise_damage >= d.poise`, else NONE.
  - **`Rig`:** `func hitbox_shape(id: StringName) -> CollisionShape3D` (the shape under that hitbox's `zone`), and `var hurtbox: Area3D`. The hitbox Areas stop monitoring; they only hold shapes now.
  - **`class_name HitScanner extends RefCounted`** (one per actor, `Actor.scanner`):
    - `func begin(hitbox: StringName, profile: StringName) -> void` and `func end(hitbox: StringName) -> void`;
    - `func scan(actor: Actor) -> Array[HitEvent]`:
      - for each active hitbox, and each one begun and ended within this tick, it sweeps the hitbox's shape from last tick's transform to this tick's, in steps no longer than half the shape's radius;
      - it uses `PhysicsDirectSpaceState3D.intersect_shape` with mask `Layers.HURTBOX`, excluding the actor's own hurtbox;
      - each target is hit at most once per activation, and an activation begun and ended in one tick is scanned once at this tick's pose (F0 note);
      - a hurtbox is mapped to its actor through `hurtbox.get_meta(&"actor")`, which `Actor._ready` sets.
  - **`Melee`** (autoload, `combat/melee.gd`, `process_physics_priority = 100`, so it runs after every actor):
    - its child node `Snapshot` runs at `process_physics_priority = -100`, before any actor moves. It takes `Defense.of` every actor in the group `actors` (actors join it on ready), so every hit of a frame is judged against the defenders as they stood when the frame began, whatever order the actors ran in;
    - `func post(event: HitEvent) -> void` records the event;
    - in `_physics_process`, it resolves every posted event against the snapshots, then applies them all through `target.apply_hit(e, result)` and `attacker.hit_landed.emit(result, e)`;
    - in a trade, each side gets the other's result.
  - **`Actor`:**
    - `signal got_hit(result: HitResult, event: HitEvent)`, `signal hit_landed(result, event)` and `signal died`;
    - `var dead := false` and `var scanner := HitScanner.new()`;
    - `func apply_hit(e: HitEvent, r: HitResult) -> void`: damage, posture, stamina, and the reaction move (`runner.start` of `def.reactions[&"flinch"]` or `[&"stagger"]`); death at 0 HP;
    - every HIT and GUARDED also calls `rig.hit_react(e.direction, 0.5 + e.profile.poise_damage / 20.0)`, the additive flinch §4.2 asks for on every hit, whether the hit interrupts or not;
    - `func die() -> void`: plays `reactions[&"death"]`, turns the hurtbox off, takes the body off the `actor` layer when the clip ends, emits `died` once, and ignores the brain from then on;
    - in the physics frame, after `rig.tick`, it posts `scanner.scan(self)` to `Melee`;
    - the runner calls `scanner.begin`/`end` from `hitbox_on`/`hitbox_off`, and every activation ends when a move ends.
  - **Reaction clips and moves** (REACTION kind, shared):
    - `flinch` from `ual1` `Hit_Chest`, length 0.45, with `recovery` f20 and `cancel_open {dodge}` f22;
    - `stagger` from `ual2_rm` `Hit_Knockback`, length 0.8, with `recovery` f40 and `cancel_open {dodge}` f42;
    - `death` from `ual1` `Death01`, with no recovery;
    - their sound and effect marks: `flinch` and `stagger` get `sfx{surface_cloth}` f0 and `fx{roll_dust}` f0; `death` gets `sfx{body_fall}` and `fx{roll_dust}` at the frame the body lands. Task 6 adds those names to the Registry and the rule that checks them.
    - `abarax.tres` gets reactions for `flinch`, `stagger` and `death`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_combat.gd: table-driven over Combat.resolve with hand-made Defense and HitProfile values
func test_resolve_table() -> void:
	# rows: [defense flags, profile, expected outcome, reaction]; one row per rule above, including
	# invulnerable WHIFF, LOW vs airborne WHIFF, MID vs airborne HIT, hyperarmour HIT/NONE, poise 5 vs 6 FLINCH,
	# poise 10 vs 6 NONE, staggers STAGGER, paired WHIFF, dead WHIFF
# test_hit_scanner.gd (TestArena; a bare Area-free target actor and a hitbox moved by hand)
func test_fast_swing_between_ticks_hits_once() -> void:   # moved 2 m through the target in one tick: 1 event
func test_on_and_off_in_one_tick_still_hits() -> void:
func test_own_hurtbox_is_never_hit() -> void:
func test_each_target_once_per_activation_and_again_after_a_new_begin() -> void:
# test_hits.gd (TestArena, two Abarax-def actors facing, 1.0 m apart; the target's def a copy with team ENEMY, poise 5)
func test_jab_lands_damage_and_flinches() -> void:      # target hp 100 -> 92, runner.current.id == &"flinch"
func test_every_hit_kicks_the_additive_flinch() -> void:   # a poise-20 target: no reaction move, but hit_reaction.tilt_velocity > 0
func test_roll_iframes_whiff() -> void:
func test_trade_lands_both_ways_in_either_order() -> void:
	# both press palm on the same frame, in both tree orders: both lose 8 hp and both flinch (Review Focus 1)
func test_dead_are_not_hit_and_die_once() -> void:      # hp 8 target: jab kills; died emitted once; a second jab whiffs
func test_dead_do_not_attack() -> void:                 # presses after death start nothing (Review Focus 2)
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/combat`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above, add the clips, and rebuild the library.**
  Mark each reaction clip with `set_marks.gd`. Check them on a contact sheet (`tools/sheets/contact_sheet.gd --def data/actors/abarax.tres --clips flinch,stagger,death`).

- [ ] **Step 4: Run `tools/test.sh`, then clip_check.**
  Expected: all pass.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 5: hits: swept hitbox scans, Melee resolves trades, Combat.resolve rules, flinch, stagger, death". Remove the self-hit and on-contact notes from STATE.md's "For F1".

### Task 6: Hit feel: hit-stop, knockback, shake, sparks, flashes and sound

**Files:**
- Create: `core/sfx.gd` (autoload `Sfx`), `audio/sound_cue.gd`, `fx/fx_def.gd`, `fx/actor_fx.gd`, `fx/{hit_spark,palm_trail,roll_dust,glint,perilous_rose,charge_glow}.tscn`
- Create: `tools/audio/make_sfx.py`, `tools/audio/tests/test_make_sfx.py`, `assets/audio/sfx/*.wav`, `data/sounds/*.tres`, `data/fx/*.tres`
- Modify: `actors/actor.gd` (`freeze`, `push`, an ActorFx child in `actor.tscn`), `render/camera_rig.gd` (shake), `render/shaders/toon_character.gdshader` and `actors/rig.gd` (`flash`), `tools/clip_checker.gd` (name rule), `default_bus_layout.tres` (an `sfx` bus if missing), `ASSETS.md`, `.github/workflows/all-divine.yml` (the sound tool's tests)
- Test: `tests/combat/test_hit_stop.gd`, `tests/combat/test_knockback.gd`, `tests/look/test_camera_shake.gd`, `tests/fx/test_actor_fx.gd`, `tests/look/test_flash.gd`, `tests/moves/test_clip_checker.gd`

**Interfaces:**
- Consumes: `Melee` and `HitResult` (Task 5), `MoveRunner.mark` (F0).
- Produces:
  - **`Actor.freeze(frames: int) -> void`** (hit-stop):
    - while frozen, the brain still thinks and its presses are buffered;
    - the runner's time, locomotion, velocity and `rig.tick` all stop;
    - a second freeze keeps the longer of the two.
    - `Melee` freezes both sides of a HIT, GUARDED, PARRIED or CAUGHT for `profile.hitstop_frames`.
  - **`Actor.push(velocity: Vector3) -> void`** (knockback): added to the planar velocity, decaying by `knockback_decay` per second, and colliding through `move_and_slide`. `Melee` pushes the target by `direction × profile.knockback`.
  - **`CameraRig.shake(strength: float) -> void`:**
    - trauma is clamped to 1 and decays at 2.5 per second;
    - the offset is `trauma² × MAX_SHAKE` (0.25 m) along smooth noise;
    - it is applied before the texel snap, so the picture still moves in whole texels;
    - `CameraRig` joins the group `camera_rig` in `_ready`, and others find it there.
  - **`Rig.flash(color: Color, seconds: float) -> void`:** the toon shader's `flash_color` and `flash_amount` mix over the palette tone and fade linearly. A hit gives white for 2 frames, and a perilous tell gives rose `#e8607e` for 0.25 s.
  - **Sound:**
    - `class_name SoundCue extends Resource`: `id`, `streams: Array[AudioStream]`, `volume_db := 0.0`, `pitch_jitter := 0.08`, `bus := &"sfx"`. It is in the Registry kind `sounds`;
    - the `Sfx` autoload has `func play(id: StringName, at: Variant = null) -> void`, with a pool of 16 voices: 3D players at a Vector3, 2D otherwise. An empty id plays nothing, and an unknown one warns;
    - `func last_played() -> Array[StringName]` is for tests and is cleared each frame.
  - **Fx:**
    - `class_name FxDef extends Resource`: `id`, `scene: PackedScene`, `bone: StringName` (empty means the actor's origin), `lifetime := 0.5`. It is in the Registry kind `fx`;
    - `hit_spark.tscn` is a GPUParticles3D of 12 one-texel quads in gold `#e8c170` and white over 0.2 s;
    - the other scenes are small pixel particle or Sprite3D effects named for what they show.
  - **`class_name ActorFx extends Node`** (in `actor.tscn`), listening to its actor's marks and hits:
    - `fx` spawns the FxDef, and `sfx` calls `Sfx.play`;
    - `shake` shakes the camera by `strength`;
    - `tell` shows `glint` (FxDef `glint` with sound `tell_glint`), or `perilous` (FxDef `perilous_rose`, the rose flash and sound `perilous_sting`);
    - when its actor is hit, it shows `hit_spark` at the point, flashes white and shakes by `profile.shake`. It plays three layers: the profile's `impact_sound`, the target's `surface_sound`, and the target's `hurt_voice`, which is empty for now.
  - **`make_sfx.py`:**
    - it uses only the standard library (`wave`, `math`, `random.Random(seed)`) and writes 44.1 kHz 16-bit mono WAVs. Each one is at most 1.5 s, peaks at −1 dBFS or lower, and is the same bytes on every run;
    - the set is `impact_palm_1..3`, `impact_heavy_1..2`, `whoosh_light_1..3`, `whoosh_heavy`, `guard_block_1..2`, `parry_ring`, `catch_snap`, `perilous_sting`, `tell_glint`, `roll_cloth`, `roll_land`, `surface_cloth_1..2`, `body_fall` and `charge_hum`;
    - impacts are a low sine thump with a pitch drop and a band-passed noise crack. Whooshes are swept filtered noise. The parry is inharmonic partials with a fast decay. The perilous sting is a low stab plus a high bell;
    - the cues in `data/sounds/`, one per name, each grouping its variants: `impact_palm`, `impact_heavy`, `palm_whoosh` and `whoosh_light` (both the `whoosh_light_*` files), `whoosh_heavy`, `guard_block`, `parry_ring`, `catch_snap`, `perilous_sting`, `tell_glint`, `roll_cloth`, `roll_land`, `surface_cloth`, `body_fall` and `charge_hum`;
    - the FxDefs in `data/fx/`: `hit_spark`, `palm_trail`, `roll_dust`, `glint`, `perilous_rose` and `charge_glow`. Every name an F0 or F1 mark uses is one of these.
  - **ClipChecker:** every `fx` name exists in the Registry `fx`, and every `sfx` name in `sounds`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_hit_stop.gd
func test_landed_jab_freezes_both_for_its_frames() -> void:
	# after contact: attacker runner.time and target's unchanged for 3 ticks, then advancing
func test_press_during_hit_stop_comes_out_after() -> void:   # palm pressed while frozen starts cross on the window
func test_trade_hit_stop_is_the_longer_not_the_sum() -> void:   # 3 and 4 frames -> both frozen 4 (Review Focus 1)
# test_knockback.gd
func test_knockback_moves_the_target_away_and_fades() -> void:   # cross (1.5 m/s): ~0.15 m away after 1 s, then still
func test_knockback_into_a_wall_does_not_pass_it() -> void:      # Review Focus 5
# test_camera_shake.gd
func test_shake_is_bounded_decays_and_stays_on_the_texel_grid() -> void:
# test_actor_fx.gd
func test_marks_spawn_their_fx_and_sounds() -> void:     # a jab: Sfx.last_played has whoosh at f5; one palm_trail
func test_a_hit_plays_impact_surface_and_voice_layers() -> void:   # three play calls; voice empty -> nothing
func test_tells_show_glint_or_rose() -> void:            # a fixture move with tell perilous: rose fx + sting + flash
# test_flash.gd
func test_flash_sets_and_fades_the_shader_parameter() -> void:
# test_clip_checker.gd
func test_unknown_fx_or_sfx_name_is_reported() -> void:
```

```python
# tools/audio/tests/test_make_sfx.py
def test_every_file_is_written_the_same_twice(self): ...
def test_peaks_and_lengths(self): ...   # every file: peak <= -1 dBFS, 0.03 s <= length <= 1.5 s, 44100 Hz mono 16-bit
```

- [ ] **Step 2: Run the tests.** Run `tools/test.sh --filter=hit_stop` and the others, then `python3 -I -m unittest discover -s tools/audio/tests`.
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above. Run `make_sfx.py`, write the cues and FxDefs, and add the ASSETS.md row** (`assets/audio/sfx/`, ours, generated by tools/audio/make_sfx.py, seeded). Put each file's length, peak and RMS in the task report. The owner judges how they sound (F1 checklist).

- [ ] **Step 4: Run `tools/test.sh`, `tools/test.sh --render`, clip_check and the Python tests.**
  Expected: all pass. Add the sound tool's tests to the CI headless job's "Python tools' tests" step.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 6: hit feel: hit-stop, knockback, shake, sparks, flashes, layered sound (our synthesiser)".

### Task 7: The Open Hand moveset, charge and aim

**Files:**
- Modify: `assets/anim/clips.cfg` (`palm_hook`, `palm_heavy`), `data/moves/{palm_jab,palm_cross,palm_hook,palm_heavy}.tres`, `data/actors/abarax.tres` (moveset), `moves/move_runner.gd` (charge, aim), `actors/intent.gd` (`aim_target`, `track`), `actors/player_brain.gd`, `core/inputs.gd` (last device), `render/camera_rig.gd` (`cursor_ground`)
- Test: `tests/moves/test_open_hand.gd`, `tests/feel/test_press_to_motion.gd`, `tests/actors/test_aim.gd`, `tests/core/test_inputs.gd`

**Interfaces:**
- Consumes: `charge_hold`, `HitProfile` and `MoveData.aim` (Task 3); stamina (Task 4); hits (Task 5).
- Produces:
  - **The palm chain.** `palm_jab` (f15) chains to `palm_cross`, and `palm_cross` at f20 now chains to `palm_hook` instead of the jab. `palm_hook` chains back to `palm_jab` after its long recovery. Every recovery window also takes `dodge`.
  - **`palm_hook`:**
    - clip: `ual2_rm` `Melee_Hook`, `then=["Melee_Hook_Rec"]`, length 0.75, `step_fps=12`;
    - marks: `sfx{palm_whoosh}` f5 · `hitbox_on{id:palm_r, profile:hook}` f15 · `fx{palm_trail}` f15 · `hitbox_off` f20 · `recovery` f30 · `cancel_open{into:{palm:palm_jab, dodge:dodge_roll}}` f30;
    - profile `hook`: damage 13, poise 12, posture 10, guard_stamina 14, hitstop 5, shake 0.3, knockback 2.0;
    - stamina 16.
  - **`palm_heavy`:**
    - clip: `ual2_rm` `OverhandThrow`, `warp=[0,0, 0.333,0.55, 0.417,0.75, 0.95,1.333]`, `step_fps=12`;
    - marks: `hyperarmour_on` f10 · `sfx{whoosh_heavy}` f15 · `charge_hold{action:heavy, frames:40, profile:charged}` f20 · `hitbox_on{id:palm_r, profile:heavy}` f25 · `fx{palm_trail}` f25 · `hitbox_off` f30 · `hyperarmour_off` f30 · `recovery` f40 · `cancel_open{into:{palm:palm_jab, dodge:dodge_roll}}` f45;
    - profile `heavy`: 22, poise 25, posture 22, guard 24, hitstop 6, shake 0.5, knockback 3.0, `staggers`, `impact_sound=impact_heavy`;
    - profile `charged`: 34, poise 40, posture 35, guard 34, hitstop 6, shake 0.8, knockback 5.0, `staggers`, `impact_sound=impact_heavy`;
    - stamina 24;
    - check every contact frame on the contact sheet, move it to the frame of full extension, and record a ruling.
  - **The moveset:** `{palm: palm_jab, heavy: palm_heavy, dodge: dodge_roll}`. Task 8 adds `guard`.
  - **Charge (MoveRunner):**
    - at `charge_hold`, if `args.action` is in `intent.held`, the runner stops advancing `time` (the pose holds at the mark) until the action is let go or `frames` frames pass;
    - when `frames` pass, `charge_profile = args.profile`, and the later `hitbox_on` marks of this move use it;
    - `ActorFx` shows `charge_glow` with `charge_hum` at full charge;
    - a reaction or any other move clears the charge (Review Focus 2/4).
  - **Aim:**
    - `Intent.aim_target: Variant = null` (a Vector3), and `Intent.track := false`;
    - during an ATTACK with `aim` and `time` before its first `hitbox_on` (through its last `hitbox_off` when `intent.track`), the runner turns the body toward `aim_target` at `aim_turn_rate_deg` through `actor.snap_facing`.
  - **The `lockable` group:** actors of team ENEMY join it on ready and leave it when they die. Aim assist uses it here, and lock-on in Task 11.
  - **PlayerBrain:**
    - `aim_target` is the lock target (Task 11). Otherwise it is the nearest live enemy (group `lockable`) within `aim_assist_range` and within `aim_assist_deg` of the stick, or of the facing when the stick rests. Otherwise null;
    - with the keyboard and mouse as the last device and no lock, `face_target` and the aim direction come from `camera_rig.cursor_ground(get_viewport().get_mouse_position(), actor.global_position.y)`.
  - **`Inputs.last_device() -> int`:** `enum Device { GAMEPAD, KEYBOARD_MOUSE }`, set in `_input` by the kind of the last event that is pressed or moved past the deadzone.
  - **`CameraRig.cursor_ground(screen: Vector2, plane_y: float) -> Variant`:** the ray through the PixelStage-mapped screen point meets `y = plane_y` at a Vector3. It returns null when the ray is parallel.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_open_hand.gd
func test_three_presses_chain_jab_cross_hook() -> void:   # presses 1 frame early each: ids in order, no idle frame
func test_every_recovery_takes_a_dodge() -> void:
func test_heavy_released_early_uses_heavy() -> void:       # tap heavy: target hp -22, stagger
func test_heavy_held_forty_frames_charges() -> void:       # hold 60 frames: runner.time waits at f20 for 40; hp -34
func test_flinch_clears_a_charge() -> void:                # hit while holding: next heavy, tapped, does 22 (Review Focus 2)
# test_aim.gd
func test_aim_assist_turns_to_a_target_inside_thirty_degrees() -> void:   # target 25° off: facing ends on it
func test_aim_assist_ignores_a_target_outside_thirty_degrees() -> void:   # 40° off: facing unchanged
func test_no_targets_means_no_turn() -> void:              # Review Focus 3
func test_keyboard_mouse_faces_the_cursor() -> void:       # last device KBM, cursor_ground stubbed: face_target set
# test_press_to_motion.gd (extended)
func test_hook_and_heavy_show_motion_within_two_frames() -> void:
# test_inputs.gd
func test_last_device_follows_the_last_event() -> void:
```

- [ ] **Step 2: Run `tools/test.sh --filter=open_hand`, `--filter=aim` and `--filter=press_to_motion`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.** Add the clips, rebuild the library, write the marks, then check the contact sheet.

- [ ] **Step 4: Run `tools/test.sh`, clip_check and `tools/test.sh --render --filter=contact_sheet`.**
  Expected: all pass.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 7: Open Hand moveset: jab-cross-hook, charged heavy, aim assist, cursor facing".

### Task 8: Guard, parry and the catch

**Files:**
- Modify: `actors/rig.gd` (the stance layer and tree), `actors/actor.gd` (guard stance), `moves/move_runner.gd` (guard and parry marks), `combat/defense.gd`, `combat/melee.gd` (applying the guard outcomes), `data/actors/abarax.tres` (moveset `guard: guard_raise`; reactions `guard_hit`, `guard_break`, `parry`, `parried`, `catch` and `caught`), `ASSETS.md` (the `assets/anim/layers/` row, ours)
- Create: clips and moves `guard_raise`, `guard_hold` (a stance clip only), `guard_hit`, `guard_break`, `parry`, `parried`, `catch`, `caught`, and `assets/anim/layers/catch.json`
- Test: `tests/combat/test_guard.gd`, `tests/combat/test_parry.gd`, `tests/actors/test_rig.gd`

**Interfaces:**
- Consumes: `Combat.resolve` rules 4–5, which come alive here; Stats (Task 4).
- Produces:
  - **The rig's stance layer:**
    - `func set_stance(clip: StringName, on: bool) -> void`, which fades over 0.08 s;
    - the tree becomes `loco → loco_scale → stance_blend.in` and `stance (looping) → stance_blend.blend`, then `stance_blend → move_blend.in`;
    - `stance_blend` filters to the upper body: `spine_01` and every bone under it (`spine_02`, `spine_03`, `neck_01`, `Head`, both clavicles, arms, hands and fingers);
    - the legs keep locomotion.
  - **`guard_raise`** (OTHER, smooth, 14 f):
    - clip: `ual2` `Sword_Block`, `warp=[0,0, 0.233,0.25]`;
    - marks: `parry_on` f0 · `sfx{whoosh_light}` f0 · `fx{glint}` f2 · `guard_on` f4 · `parry_off` f10 · `recovery` f10 · `cancel_open{into:{palm:palm_jab, heavy:palm_heavy, dodge:dodge_roll}}` f10 · `guard_off` f14;
    - the parry window is frames 0–9, 167 ms;
    - `guard_raise` can't cancel into itself, so mashing never reopens the window (Review Focus 4).
  - **The guard stance:**
    - when `guard_raise` ends with `guard` still held, the actor sets `guarding = true`, calls `rig.set_stance(&"guard_hold", true)` (`ual2` `Idle_Shield_Loop`, looping), and walks at `guard_speed_scale` without sprinting;
    - stamina regen is scaled by `guard_regen_scale`;
    - letting go of guard, or pressing palm or heavy, ends the stance.
  - **A same-frame tie:** when guard and an attack are pressed on the same frame from rest, guard wins and the attack stays buffered (Review Focus 4).
  - **`Defense`:**
    - `guarding` is a `guard_on` mark active or the guard stance;
    - `parrying` is the parry window;
    - the arc is `guard_arc_deg` about `facing`.
  - **Outcomes, in `Melee`:**
    - GUARDED: the target plays `guard_hit` (`ual2` `Shield_OneShot`, warp to 0.35 s, REACTION, `recovery` f12, `cancel_open{palm, dodge}` f14) and stays guarding afterwards if guard is still held. It spends `stamina_cost`, takes `posture_damage`, and plays sound `guard_block`.
    - GUARD_BREAK: `guard_break` (`ual2` `Idle_Shield_Break`, 1.0 s, REACTION, `recovery` f50), with stamina at 0.
    - PARRIED: the defender plays `parry` (`ual2` `Sword_Block`, `warp=[0,0.25, 0.4,1.0]`, OTHER, `cancel_open{palm, heavy}` f8, which is the riposte). The attacker plays `parried` (`ual2` `Hit_Knockback`, `warp=[0,0, 0.7,0.833]`, REACTION, `recovery` f36) and takes `attacker_posture_damage`. The sound is `parry_ring`, with a spark at the point.
    - CAUGHT: the defender plays `catch` (the `parry` clip with `layer=catch.json`: the right hand forward to grip, about 30° on `upperarm_r` and `lowerarm_r` over f4–f16; 30 f; `cancel_open{palm, heavy}` f14). The attacker plays `caught` (`ual2` `Hit_Knockback`, length 0.9, REACTION, `recovery` f45) and takes `catch_posture`. The sound is `catch_snap`.
  - **Posture breaking here** (`damage_posture` returns true) plays `reactions[&"posture_broken"]` when the def has it; until Task 10, it plays `stagger`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_guard.gd
func test_frontal_jab_is_blocked() -> void:        # hp unchanged, stamina -8, posture -4, guard_hit plays
func test_jab_from_behind_hits_a_guard() -> void:
func test_guard_walks_slower_with_the_stance_on_the_upper_body() -> void:
	# held guard + stick: speed ~ walk x 0.45; the hips follow locomotion, spine_03 follows guard_hold
func test_empty_stamina_breaks_the_guard() -> void:
func test_perilous_sweep_is_not_blocked() -> void: # Combat row; integration with a fixture sweep
func test_guard_and_palm_same_frame_guard_wins() -> void:   # Review Focus 4
# test_parry.gd
func test_guard_tapped_five_frames_before_the_hit_parries() -> void:
	# attacker posture -2 x posture_damage, attacker plays parried, defender's palm within 8 frames starts the jab
func test_guard_pressed_twelve_frames_early_only_guards() -> void:
func test_mashing_guard_does_not_reopen_the_window() -> void:   # Review Focus 4
func test_parried_thrust_is_caught() -> void:      # fixture THRUST: CAUGHT, attacker posture -50, catch plays
func test_parried_sweep_still_hits() -> void:
```

- [ ] **Step 2: Run `tools/test.sh --filter=guard` and `--filter=parry`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.** Add the clips (and the layer JSON), rebuild, and write the marks. Check the guard, parry and catch on contact sheets, and tune `catch.json` once by eye.

- [ ] **Step 4: Run `tools/test.sh`, `--render` and clip_check.**
  Expected: all pass. F0's locomotion, warp and foot tests still pass with the stance off.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 8: guard stance (walkable, upper-body layer), timed parry, guard break, the catch".

### Task 9: The hop: stepping over sweeps

**Files:**
- Create: clip and move `hop`
- Modify: `moves/move_runner.gd` (`neutral_variant`, `airborne`), `data/moves/dodge_roll.tres` (`neutral_variant = &"hop"`), `actors/actor.gd`/`rig.gd` (`rig.airborne` from the marks), `combat/defense.gd`
- Test: `tests/moves/test_hop.gd`

**Interfaces:**
- Produces:
  - **`hop`** (OTHER, smooth, 36 f):
    - clip: `ual2_rm` `NinjaJump_Start`, `then=["NinjaJump_Land"]`, length 0.6;
    - marks: `sfx{roll_cloth}` f0 · `airborne_on` f6 · `airborne_off` f26 · `fx{roll_dust}` f26 · `sfx{roll_land}` f26 · `recovery` f28 · `cancel_open{into:{palm:palm_jab, dodge:dodge_roll}}` f30;
    - stamina 12.
  - **`MoveRunner`:**
    - starting a move whose `neutral_variant` is set, with `intent.move` at rest, starts the variant instead, from rest and from cancel windows alike;
    - `var airborne := false` follows the marks, and `Defense.airborne` and `rig.airborne` read it.
  - A LOW profile whiffs an airborne target (rule 2, Task 5).

- [ ] **Step 1: Write the failing tests.**

```gdscript
func test_neutral_dodge_hops_and_pushed_dodge_rolls() -> void:
func test_low_sweep_through_the_airborne_frames_whiffs() -> void:   # fixture LOW attack timed to f10 of the hop
func test_mid_hit_during_the_hop_lands() -> void:
func test_feet_are_not_planted_while_airborne() -> void:            # foot_planter influence 0 between the marks
func test_mashing_dodge_does_not_extend_iframes() -> void:          # Review Focus 4: iframes never exceed 13 per roll
```

- [ ] **Step 2: Run `tools/test.sh --filter=hop`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.** Add the clip, rebuild, write the marks, and check the sheet.

- [ ] **Step 4: Run `tools/test.sh` and clip_check.**
  Expected: all pass.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 9: hop on a neutral dodge; sweeps miss the airborne".

### Task 10: Posture breaks, finishers and paired moves

**Files:**
- Create: `moves/paired_move.gd`, `data/pairs/{finisher_open_hand,knuckle_grab}.tres`
- Create: clips and moves `posture_broken`, `finisher`, `finisher_victim`, `knuckle_grab_hold`, `grabbed`
- Modify: `actors/actor.gd` (`start_paired`, the finisher check, `combat_moment`), `combat/melee.gd` (placing followers, `pair_hit`, GRABBED), `moves/move_runner.gd` (`pair_hit`), `actors/actor_def.gd` (`@export var finisher: PairedMove` and `@export var grab_pair: PairedMove`), `data/actors/abarax.tres` (`finisher`, reaction `posture_broken`), `tools/clip_checker.gd` (pairs), `tools/sheets/contact_sheet.gd` (`--pair`)
- Test: `tests/combat/test_posture.gd`, `tests/combat/test_finisher.gd`, `tests/combat/test_paired.gd`

**Interfaces:**
- Consumes: `Stats.damage_posture` and `restore_posture` (Task 4), `Melee` (Task 5), and the GRABBED outcome.
- Produces:
  - **`class_name PairedMove extends Resource`:**
    - `id`, `lead_move: StringName`, `follow_move: StringName`;
    - `follow_offset: Transform3D`: the follower relative to the lead, defaulting to 1.1 m in front and facing the lead;
    - `align_frames := 4` and `max_length := 1.5`;
    - `hits: Dictionary` (profile name to HitProfile) for the `pair_hit` marks.
    - The Registry kind is `pairs`. The checker reports a pair whose lead clip is longer than `max_length` (finishers) and a `pair_hit` profile that doesn't exist.
  - **`Actor.start_paired(other: Actor, pair: PairedMove) -> bool`:**
    - it refuses (returns false) when either actor is dead, already paired, or invulnerable;
    - otherwise both actors get `paired_with` and `pair`, both brains are ignored, and both runners start their move on the same frame;
    - `Melee`, after every actor has moved, slides the follower to the offset over `align_frames`, then holds it there;
    - the lead's `pair_hit {profile}` marks apply that profile's damage and posture to the follower directly (no scan, no defense);
    - the pair ends when both moves end;
    - it emits `combat_moment(&"finisher")` (or `&"grab"`) on both actors, for F4.
  - **A posture break:**
    - the actor plays `posture_broken` (`ual2` `Hit_Knockback`, `warp=[0,0, 0.4,0.6, 1.8,0.62, 2.0,0.833]`: a dazed hold, REACTION, `recovery` f115) and joins the group `finishable`;
    - when the clip ends without a finisher, it calls `restore_posture` and leaves the group.
  - **The finisher:**
    - a `palm` press, with a `finishable` actor within `finisher_range` and inside `finisher_arc_deg` of the facing, starts `def.finisher` (`finisher_open_hand`) instead of the jab;
    - `Actor.finishable_target() -> Actor` answers which one, for the HUD;
    - after the pair, the follower calls `restore_posture`, and dies if its HP is 0.
  - **`finisher`** (1.4 s, `step_fps=12`):
    - clip: `ual1_rm` `Punch_Jab`, `then=["ual2_rm:Melee_Hook", "ual2_rm:OverhandThrow"]`, length 1.4;
    - marks: `pair_hit{profile:f1}` f10 · `pair_hit{f2}` f35 · `pair_hit{f3}` f65, plus sfx and fx at each, `recovery` f75;
    - the pair's hits are `f1` damage 15 · `f2` 15 · `f3` 30 (60 in all), each with hitstop 4, 4 and 6.
    - `finisher_victim`: `ual1` `Hit_Head`, `then=["Hit_Chest", "ual2:Hit_Knockback"]`, length 1.4.
  - **GRABBED** (from Task 5's rule 3) now starts the attacker's `def.grab_pair` (`knuckle_grab`):
    - lead `knuckle_grab_hold`: `ual2_rm` `OverhandThrow`, length 1.0, `pair_hit{throw}` f40 (damage 30, posture 20, hitstop 6, shake 0.6);
    - follow `grabbed`: `ual2` `Hit_Knockback`, length 1.0;
    - an actor without a grab pair applies it as a HIT with STAGGER, as before.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_posture.gd
func test_guarded_heavies_wear_posture_to_a_break() -> void:   # four guarded heavies (22) on 80 posture: broken
func test_break_lasts_its_clip_then_posture_refills() -> void:
func test_posture_regenerates_after_its_delay() -> void:
# test_finisher.gd (Abarax vs an Abarax-def ENEMY copy with 60 hp)
func test_palm_near_a_broken_foe_starts_the_finisher() -> void:
func test_finisher_is_at_most_one_and_a_half_seconds() -> void:
func test_follower_holds_the_offset_after_aligning() -> void:   # every frame after 4: distance to offset <= 0.05 m
func test_three_pair_hits_kill_a_sixty_hp_foe() -> void:
func test_palm_behind_or_far_from_a_broken_foe_is_a_jab() -> void:
# test_paired.gd
func test_cannot_pair_with_the_dead_or_the_already_paired() -> void:
func test_paired_actors_are_not_hit_by_others() -> void:        # Review Focus 2
func test_brains_are_ignored_while_paired() -> void:
func test_grab_connects_into_the_grab_pair() -> void:           # a fixture GRAB attack on a non-dodging Abarax
```

- [ ] **Step 2: Run `tools/test.sh --filter=posture`, `--filter=finisher` and `--filter=paired`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.** Add the clips, rebuild, write the marks, and check both actors of each pair on one contact sheet (the sheet tool takes `--pair data/pairs/<id>.tres`: both rigs side by side at the offset).

- [ ] **Step 4: Run `tools/test.sh`, `--render` and clip_check.**
  Expected: all pass.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 10: posture breaks, the Open Hand finisher (1.4 s), paired moves, the grab".

### Task 11: Lock-on and the combat camera

**Files:**
- Create: `actors/lock_on.gd`
- Modify: `actors/player_brain.gd`, `core/bindings.gd` and `core/inputs.gd` (`target_left`, `target_right`), `actors/actor.gd` (the group `lockable`), `render/camera_rig.gd` (`lock_target`)
- Test: `tests/actors/test_lock_on.gd`, `tests/core/test_bindings.gd`, `tests/look/test_camera_rig.gd`

**Interfaces:**
- Produces:
  - **`class_name LockOn extends RefCounted`:**
    - `const PICK_RANGE := 15.0` and `const LOSE_RANGE := 20.0`;
    - `var target: Actor`;
    - `static func pick(from: Actor, candidates: Array, view_dir: Vector3) -> Actor`:
      - it chooses within `PICK_RANGE`, by the smallest `angle_deg(view_dir, to_candidate) + 4 × distance`;
      - a candidate more than 90° from `view_dir` is chosen only when there is none in front;
      - it returns null for an empty list;
    - `static func next(from: Actor, current: Actor, candidates: Array, clockwise: bool) -> Actor` goes to the nearest neighbour by angle around `from`, seen from above;
    - `func update(from: Actor) -> void` drops a target that is dead, out of the tree, or past `LOSE_RANGE`.
  - **PlayerBrain:**
    - `var lock := LockOn.new()`;
    - `lock_on` toggles the lock (picking along the camera's forward when the stick rests, else along the stick);
    - while locked:
      - `target_left`, `target_right`, `slot_prev` and `slot_next` switch targets (the wheel switches only while locked);
      - `face_target` is `target.head_point()`;
      - `aim_target` is the target's position.
  - **Bindings:**
    - `target_left` and `target_right` are the right stick's X axis (− and +). They are in `GAMEPLAY`, with an action deadzone of 0.6, so a flick is one press. There are no keys for them; Tab and the wheel cover the keyboard;
    - add them to `ACTIONS` after `lock_on`.
  - **The `lockable` group:** team ENEMY actors join on ready and leave on death.
  - **`CameraRig.lock_target: Node3D`:** when it is set, the follow goal leans toward it: `goal += clamp_length((lock_pos − goal) × 0.35, 3.0)`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_lock_on.gd
func test_pick_prefers_the_foe_in_front_over_a_nearer_one_behind() -> void:
func test_pick_takes_the_only_foe_behind() -> void:              # Review Focus 3
func test_pick_with_no_foes_is_null_and_lock_on_does_nothing() -> void:   # Review Focus 3
func test_switch_right_takes_the_clockwise_neighbour() -> void:
func test_lock_drops_on_death_and_past_twenty_metres() -> void:  # Review Focus 3: mid-combo death keeps the combo going
func test_locked_strafe_keeps_facing_the_target() -> void:
func test_wheel_switches_only_while_locked() -> void:
# test_camera_rig.gd
func test_lock_leans_the_camera_toward_the_target_at_most_three_metres() -> void:
# test_bindings.gd
func test_target_actions_are_right_stick_x_only() -> void:
```

- [ ] **Step 2: Run `tools/test.sh --filter=lock_on`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.**

- [ ] **Step 4: Run `tools/test.sh`.**
  Expected: all pass, including F0's binding and rebinding tests with the two new actions.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 11: lock-on (pick, switch, lose), camera lean".

### Task 12: The Knuckle of the Hand: model, rig and moves

**Files:**
- Create: `tools/anim/build_knuckle.py`, `tools/anim/tests/test_build_knuckle.py`, `assets/characters/knuckle/knuckle.glb`, `actors/knuckle/knuckle_rig.tscn`, `data/palettes/knuckle_{1,2,3}.tres`, `data/actors/knuckle_{1,2,3}.tres`, `data/tuning/combat_knuckle.tres`, `data/moves/knuckle_*.tres`
- Modify: `tools/anim/bpy_common.py` (shared build steps moved out of `build_abarax.py`), `tools/anim/build_abarax.py`, `actors/rig.gd` and `actors/actor_def.gd` (`hidden_parts`, `scale`), `assets/anim/clips.cfg`, `ASSETS.md`, `tools/bpy_test.sh`
- Test: `tests/actors/test_knuckle.gd`, `tests/feel/test_coverage.gd`

**Interfaces:**
- Consumes: the library (Tasks 2–10); `ClipChecker` enemy rules (Task 3).
- Produces:
  - **`build_knuckle.py`**, using the build steps shared with `build_abarax.py` (moved into `bpy_common.py`):
    - base `Superhero_Male`, head only;
    - hair `Hair_Buzzed` and `Hair_Beard`;
    - outfit `Male_Ranger_Body`, `_Legs`, `_Arms`, `_Feet_Boots`, plus `_Head_Hood` and `_Acc_Pauldron`;
    - meshes named `Knuckle_Head`, `Knuckle_Hair`, `Knuckle_Beard`, `Knuckle_Body`, `Knuckle_Legs`, `Knuckle_Arms`, `Knuckle_Boots`, `Knuckle_Hood` and `Knuckle_Pauldron`;
    - palette slots in UV2: skin, hair, eyes, main, sec, pants, boots, hood, metal;
    - **at most 4,000 triangles** with every part shown;
    - no scarf, so 65 bones.
  - **The refactor's guard:** `build_abarax.py` rebuilds `abarax.glb` byte for byte (sha256 unchanged).
  - **`knuckle_rig.tscn`:**
    - the Rig script, Model `knuckle.glb`, and the same AnimationTree setup and library as Abarax;
    - hitboxes `palm_l`, `palm_r` and `foot_r`, and the Hurtbox;
    - liveliness: the warp, breathing, hit react, feet and looks, but no spring bone.
  - **`ActorDef`:**
    - `@export var hidden_parts := PackedStringArray()` (Rig hides MeshInstance3Ds of those names);
    - `@export var model_scale := 1.0`.
  - **The moveset**, shared by the tiers: `{palm: knuckle_jab, heavy: knuckle_thrust, gift: knuckle_sweep, interact: knuckle_grab, dodge: knuckle_feint}`. The actions are only names here: an enemy's brain presses them (Task 13), and enemies never read the player's controls. Every knuckle move is then reachable for the checker.
  - **The tiers** (`team = ENEMY`, `reactions` all set, `grab_pair = knuckle_grab`):

    | | HP | Poise | Posture | Hidden parts | Scale | Palette |
    |---|---|---|---|---|---|---|
    | `knuckle_1` | 60 | 5 | 60 | `Knuckle_Hood`, `Knuckle_Pauldron` | 1.0 | drab browns and ochre |
    | `knuckle_2` | 90 | 10 | 80 | `Knuckle_Pauldron` | 1.0 | the Hand's red hood `#9a2a2a` |
    | `knuckle_3` | 130 | 20 | 100 | none | 1.06 | black and brass `#c8a04a` |

  - **Enemy moves** (`step_fps=12`; marks on the 5-frame grid; first values, checked on the sheet as in F0). The profile columns are damage, poise, posture, guard stamina and hit-stop.

    | Move | Clip | Profile | Marks |
    |---|---|---|---|
    | `knuckle_jab` | `ual1_rm` `Punch_Jab`, warp `[0,0, 0.25,0.1, 0.333,0.167, 0.8,0.583]` | 10/6/6/10/3 | `tell{glint}` f5 · `hitbox_on{palm_l}` f20 · `hitbox_off` f25 · `cancel_open{palm:knuckle_cross}` f25 · `recovery` f30 · `charge_hold{palm, 12, jab}` f10 (the delayed swing) |
    | `knuckle_cross` | `ual1_rm` `Punch_Cross`, warp `[0,0, 0.3,0.17, 0.417,0.25, 0.9,0.667]` | 12/8/8/12/4 | `tell{glint}` f5 · `hitbox_on{palm_r}` f25 · `hitbox_off` f30 · `cancel_open{palm:knuckle_hook}` f30 · `recovery` f35 |
    | `knuckle_hook` | `ual2_rm` `Melee_Hook` + `Melee_Hook_Rec`, warp `[0,0, 0.35,0.2, 0.45,0.3, 1.25,1.067]` | 15/12/12/15/5 | `tell{glint}` f5 · `hitbox_on{palm_r}` f25 · `hitbox_off` f30 · `recovery` f35 · `cancel_open{palm:knuckle_hook_2}` f30 (tier III only, through its brain); the rest of the clip is the opening ("three blows, then open") |
    | `knuckle_hook_2` | `palm_hook`'s clip | 15/12/12/15/5 | a tier III combo extension; `tell` f0, `hitbox_on` f15 |
    | `knuckle_sweep` | `ual2_rm` `Slide_Start` + `Slide_Exit`, length 1.2 | 20/20/15/–/5, LOW, SWEEP | `tell{perilous}` f0 · `hitbox_on{foot_r}` f30 · `hitbox_off` f50 (20 f, more than the roll's 13 iframes) · `recovery` f55 |
    | `knuckle_thrust` | `ual2_rm` `Sword_Dash`, warp `[0,0, 0.55,0.45, 0.7,0.65, 1.1,1.567]` | 24/20/25/–/6, THRUST | `tell{perilous}` f0 · `hitbox_on{palm_r}` f35 · `hitbox_off` f40 · `recovery` f50 |
    | `knuckle_grab` | `ual2_rm` `Zombie_Scratch`, warp `[0,0, 0.5,0.6, 0.667,0.9, 1.0,1.8]` | 0, GRAB | `tell{perilous}` f0 · `hitbox_on{palm_l}` and `{palm_r}` f30 · `hitbox_off` f40 · `recovery` f45 |
    | `knuckle_feint` (OTHER) | `ual1_rm` `Punch_Jab`, warp `[0,0, 0.25,0.1, 0.5,0.0]` | – | `tell{glint}` f5 · `recovery` f20 · `cancel_open{palm:knuckle_jab, heavy:knuckle_thrust}` f20 |
    | `knuckle_idle` (a stance-free loop for the unalerted) | `ual2` `Idle_FoldArms_Loop` | – | – |

    Every move also gets `sfx`/`fx` marks: whooshes, and a dust puff at the sweep's start.

- [ ] **Step 1: Write the failing tests.**

```python
# tools/anim/tests/test_build_knuckle.py
def test_triangle_budget_with_every_part(self): ...   # 1,500 <= tris <= 4,000
def test_parts_slots_and_skeleton(self): ...          # the nine parts; slots in UV2; 65 bones; rest == Abarax's 65
def test_abarax_rebuild_is_byte_identical(self): ...
```

```gdscript
# test_knuckle.gd
func test_knuckle_plays_the_shared_library() -> void:   # every library clip's tracks resolve on the knuckle skeleton
func test_tiers_hide_their_parts_and_scale() -> void:
func test_tiers_have_their_numbers() -> void:
# test_coverage.gd (spec §8: animation coverage)
func test_every_actor_has_every_clip_it_needs() -> void:
	# for every actor def: required_clips, every reaction move's clip, every moveset move and its cancels, and
	# (Task 13) every brain attack move exist in its rig and none is a T-pose
```

- [ ] **Step 2: Run `tools/bpy_test.sh`, `tools/test.sh --filter=knuckle` and `--filter=coverage`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.**
  - Refactor first and prove the Abarax bytes are unchanged, then build the Knuckle.
  - Add the clips and moves, rebuild the library, and write the marks.
  - Render contact sheets of the three tiers and every knuckle move (`--def data/actors/knuckle_3.tres`). Check the silhouettes at 640×360 (§3.5).
  - Add the ASSETS.md row for `assets/characters/knuckle/`.

- [ ] **Step 4: Run `tools/bpy_test.sh`, `tools/test.sh`, `--render` and clip_check.**
  Expected: all pass, with the enemy tell rules met.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 12: the Knuckle of the Hand: model, rig, tiers I–III, moves with tells and perilous attacks".

### Task 13: The enemy brain and attack tokens

**Files:**
- Create: `actors/brain_def.gd`, `actors/attack_option.gd`, `actors/enemy_brain.gd`, `combat/attack_tokens.gd`, `data/brains/knuckle_{1,2,3}.tres`
- Modify: `actors/actor_def.gd` (`@export var brain: BrainDef`), `data/actors/knuckle_{1,2,3}.tres` (`brain`), `actors/actor.gd` (an ENEMY def with a brain gets an `EnemyBrain` on ready, seeded from its name), `tools/clip_checker.gd` (brain moves reachable), `tests/feel/test_coverage.gd` (brain moves)
- Test: `tests/actors/test_enemy_brain.gd`, `tests/combat/test_attack_tokens.gd`

**Interfaces:**
- Produces:
  - **`class_name AttackOption extends Resource`:**
    - `action: StringName`: the moveset action the brain presses to start the attack (the move is `def.moveset[action]`, which the checker and the coverage test follow);
    - `min_range := 0.0`, `max_range := 2.0`, `max_angle_deg := 45.0`;
    - `cooldown := 1.5`, `weight := 1.0`, `needs_token := true`;
    - `combo: PackedStringArray`: actions pressed in turn as each cancel window opens (for example `["palm", "palm"]` for jab, cross, hook).
  - **`class_name BrainDef extends Resource`:**
    - perception: `sight_range := 12.0`, `sight_fov_deg := 120.0`, `hearing_range := 6.0`, `notice_time := 0.6`;
    - spacing: `preferred_range := 2.2`, `range_tolerance := 0.6`, `circle_speed := 0.5`;
    - attacks: `attacks: Array[AttackOption]`;
    - tier behaviour: `feint_chance := 0.0`, `delay_chance := 0.0`, `delay_frames := Vector2i(6, 12)`, `track_dodges := false`, `extend_combo_chance := 0.0`;
    - retreat: `retreat_below := 0.0` (of max HP), `regroup_time := 2.0`;
    - gank squads: `ignores_tokens := false`;
    - `reangle_after := 3.0`.
  - **`class_name EnemyBrain extends Brain`:**
    - `func _init(def: BrainDef, seed: int)`, with `var rng := RandomNumberGenerator.new()` seeded from it;
    - `var target: Actor` is found on its own: the nearest PLAYER-team actor;
    - `enum Mode { IDLE, NOTICING, ENGAGED, ATTACKING, RETREATING }` and `var mode`.
  - **What `think` does:**
    - **Perception:** the target is seen inside the cone and range with a clear ray on `Layers.WORLD`, or heard within `hearing_range` while it sprints or attacks. After `notice_time`, the mode is ENGAGED.
    - **Spacing:** move toward or away to `preferred_range ± range_tolerance`, otherwise circle at `circle_speed`, with `face_target` on the target. When spacing has failed for `reangle_after` seconds, switch the circling direction and add a 60° offset (Review Focus 5).
    - **Attack choice:** among options in range and angle, off cooldown, and holding a token when `needs_token`, pick by weight with `rng`. Then press the option's `action`, and its combo presses as the windows open:
      - `delay_chance`: hold `palm` through the jab's `charge_hold` for a random number of frames in `delay_frames`;
      - `feint_chance`: press `dodge` (the feint) first, then the option's action into the feint's window;
      - `extend_combo_chance`: add the fourth blow;
      - `track_dodges`: set `intent.track` with `aim_target` on the target.
    - **Reactions:** after `parried`, `caught` or `stagger`, back off one preferred range. When HP is below `retreat_below`, retreat for `regroup_time`.
  - **Attack options** are pressed through the Knuckle's moveset (Task 12).
  - **`class_name AttackTokens extends Node`** (group `attack_tokens`):
    - `const PER_TARGET := 2`;
    - `func take(attacker: Actor, target: Actor) -> bool` and `func give_back(attacker: Actor) -> void`;
    - tokens are given back by themselves when the attacker's move ends, when it dies, or after 3 s;
    - with no `AttackTokens` in the tree, `take` always succeeds.
  - **The three brains:**
    - **I:** jab with combo `[palm, palm]` (the three blows), a sweep at 2–3 m with weight 0.4. No feints, no delays.
    - **II:** adds the thrust (2.5–4 m), `feint_chance` 0.25 and `delay_chance` 0.3.
    - **III:** adds the grab (0–1.5 m), `extend_combo_chance` 0.4, `track_dodges`, `delay_chance` 0.5 (it baits parries), and preferred range 1.8.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_enemy_brain.gd (TestArena; the player a ScriptBrain Abarax)
func test_notices_in_its_cone_but_not_behind() -> void:
func test_hears_a_sprint_behind_it() -> void:
func test_holds_its_preferred_range() -> void:              # after 3 s engaged: distance within 2.2 ± 0.6
func test_attacks_only_in_range_and_angle_and_off_cooldown() -> void:
func test_same_seed_same_choices() -> void:                 # two runs, 600 frames: equal move logs
func test_tier_one_throws_three_blows_then_opens() -> void: # jab, cross, hook in a row, then idle >= 30 frames
func test_tier_two_sometimes_feints_and_delays() -> void:   # seeded: a feint and a delayed jab within 1,200 frames
func test_tier_three_tracks_a_roll() -> void:               # a roll past its side during the hook: facing follows
func test_reangles_when_its_spacing_fails_near_a_wall() -> void:   # Review Focus 5
# test_attack_tokens.gd
func test_only_two_of_four_commit_at_once() -> void:
func test_tokens_come_back_on_move_end_death_and_timeout() -> void:
func test_squads_that_ignore_tokens_take_none() -> void:
```

- [ ] **Step 2: Run `tools/test.sh --filter=enemy_brain` and `--filter=attack_tokens`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above, and write the brain data.**

- [ ] **Step 4: Run `tools/test.sh` and clip_check.**
  Expected: all pass. Every move a brain can use is reachable.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 13: enemy brain (perception, spacing, attack choice, tiers), attack tokens".

### Task 14: The training yard, the HUD and dying

**Files:**
- Create: `tools/world/build_region.gd` (the courtyard builder, generalised: `-- <layout.txt> <out.tscn>`; `build_courtyard.gd` calls it with the courtyard's paths), `world/training_yard/{layout.txt,training_yard.tscn}`, `world/arena.gd`, `world/arena_wave.gd`, `data/arena/waves.tres`, `data/render/grades/training_yard.tres`, `hud/hud.gd`, `hud/hud.tscn`
- Create: clip and move `getup` (`ual2` `LayToIdle`, OTHER)
- Modify: `render/pixel_stage.gd` and `pixel_stage.tscn` (the `Hud` SubViewport), `main/main.gd` and `main.tscn` (the yard by default; F5 switches to the courtyard; the self-test circuit), `actors/actor.gd` (the player's death and respawn through the arena), `data/actors/abarax.tres` (reaction `getup`)
- Test: `tests/world/test_arena.gd`, `tests/world/test_training_yard.gd`, `tests/hud/test_hud.gd`, `tests/actors/test_player_death.gd`, `tests/main/test_main.gd`, `tests/main/test_selftest.gd`, `tests/render/test_yard_shot.gd`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - **The training yard** (layout commands as in the courtyard):
    - a 24 × 24 m walled yard of the Kenney kit with a half-wall gate on the south;
    - six lanterns, two with shadows, and posts as `poi`;
    - markers `Spawn` (south, facing north) and `EnemySpawn_1` to `EnemySpawn_4` (north arc);
    - grade `training_yard.tres` (night: cool blue fog, warm lanterns).
  - **`class_name ArenaWave extends Resource`:** `defs: Array[ActorDef]` and `count: PackedInt32Array`.
  - **`class_name Arena extends Region`:**
    - `@export var waves: Array[ArenaWave]` (`data/arena/waves.tres`: 1× tier I; 2× tier I; 1× tier II; tier II + tier I; 1× tier III; tier III + tier II);
    - it has an `AttackTokens` child;
    - `signal wave_started(index: int)` and `signal wave_cleared(index: int)`;
    - `func start_wave(index: int) -> void` spawns at the enemy spawns in turn;
    - `func reset() -> void` frees the enemies, places the player at `Spawn` with full stats, then restarts the current wave;
    - three seconds after `wave_cleared`, the next wave starts and the player's bars refill;
    - debug keys F6, F7 and F8 spawn one tier I, II or III, and F9 resets;
    - `func state_hash() -> int` hashes, in tree order, every actor's position (rounded to mm), HP, posture, stamina (rounded to 0.1) and current move id, plus the wave and the physics frame (for Task 15).
  - **The player's death:** the death clip, then after 3 s `Arena.reset()`, and the player plays `getup` at `Spawn` ("Get Up").
  - **The HUD.** `PixelStage.hud: SubViewport` is 640×360 with a transparent background. It is drawn after the world at the same integer scale, with no sub-pixel shift and no grade. `class_name Hud extends Control` draws:
    - the player's bars, bottom left: HP in rose `#e8607e` (1 px per 1 HP, up to 120 px), stamina in gold `#e8c170` below it, and a thin posture bar above HP, shown only while it isn't full;
    - an enemy's posture and HP bars (24 px wide) over its head point while it is locked on, or for 3 s after it is hit;
    - the lock reticle, a 5×5 rose diamond at the lock target's projected head point;
    - the finisher prompt, a 7×7 rose glyph over `finishable_target()`;
    - the wave as pips, top centre.
  - **Main:**
    - the yard is the default region, and F5 switches to the courtyard;
    - `--selftest` runs in the yard: Abarax, through a ScriptBrain, fights one tier I (approach, jab-cross-hook, roll, guard, heavy) for `SELFTEST_FRAMES`, with no errors.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_arena.gd
func test_waves_spawn_their_defs_at_the_enemy_spawns() -> void:
func test_a_cleared_wave_starts_the_next_after_three_seconds() -> void:
func test_reset_clears_and_refills() -> void:
func test_state_hash_changes_with_play_and_repeats_with_the_same_state() -> void:
# test_training_yard.gd
func test_yard_walls_hold_and_nobody_leaves() -> void:   # knockback toward each wall and corner: inside, not stuck (Review Focus 5)
func test_spawns_and_pois_exist() -> void:
# test_hud.gd
func test_bars_track_the_stats() -> void:
func test_reticle_follows_the_lock_target() -> void:
func test_prompt_shows_only_for_a_finishable_foe_in_reach() -> void:
func test_hud_is_not_shifted_by_the_subpixel() -> void:
# test_player_death.gd
func test_death_then_reset_then_getup_at_spawn() -> void:
# test_main.gd / test_selftest.gd
func test_default_region_is_the_yard_and_f5_switches() -> void:
func test_selftest_fights_in_the_yard_and_exits_zero() -> void:
# tests/render/test_yard_shot.gd (render): the yard at night with a tier I in view renders without errors;
# the lantern-lit ground is brighter than the shadowed corner (as F0's courtyard shot test checks)
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/world`, `--filter=hud`, `--filter=player_death` and `--filter=tests/main`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.**
  - Write the layout and build the yard (`tools/godot.sh -s res://tools/world/build_region.gd -- res://world/training_yard/layout.txt res://world/training_yard/training_yard.tscn`).
  - Check that the courtyard still builds the same scene from its layout.
  - Add the `getup` clip.

- [ ] **Step 4: Run `tools/test.sh`, `--render`, and the exported Linux `--selftest`.**
  Expected: all pass, and the self-test exits 0.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 14: the training yard, waves, HUD, the player's death and Get Up".

### Task 15: Input recording, replay and the combat bot

**Files:**
- Create: `tools/replay/{input_recording,recorder,replayer}.gd`, `tools/bot/{combat_bot,run_bot}.gd`
- Modify: `main/main.gd` (`--record=<path>` and `--replay=<path>` user arguments), `.github/workflows/all-divine.yml` (a bot step in the headless job), `.gitignore` (`out/replays/` is already under `out/`)
- Test: `tests/replay/test_replay.gd`, `tests/bot/test_combat_bot.gd`

**Interfaces:**
- Consumes: `Arena.state_hash` and `reset` (Task 14); the PlayerBrain read path (F0, Task 7).
- Produces:
  - **`class_name InputRecording extends Resource`:**
    - `@export var frames: Array`, one entry per physics frame: `{move: Vector2 (screen), pressed: PackedStringArray, held: PackedStringArray}`;
    - `@export var region: String`, `@export var seed: int` and `@export var start_frame: int`;
    - it is saved as text `.tres`.
  - **`class_name InputRecorder extends Node`:** it records `Inputs.move_vector()`, `Inputs.pressed_this_frame()` and the held gameplay actions every physics frame. Its `process_physics_priority` is −110, so it runs before `Melee`'s snapshot and the actors. It has `func save(path: String) -> Error`.
  - **`Inputs.inject_move(move: Variant) -> void`:** a Vector2 that `move_vector()` returns in place of the devices' reading until it is given null. A headless run has no connected pad to read a stick from, so this is the one seam for movement. Buttons go through the real actions.
  - **`class_name InputReplayer extends Node`** (priority −110):
    - `func play(rec: InputRecording) -> void` feeds each frame through the input path: `Input.action_press` and `action_release` for the actions, and `Inputs.inject_move` for the stick, so the PlayerBrain reads it as it would a player's input;
    - `signal finished`.
  - **Determinism:** the same recording, seed and region give the same `state_hash` at the end.
  - **`class_name CombatBot extends Node`.** It plays the player through the same injection as the replayer (real input actions):
    - it locks on, approaches, and attacks in openings (an enemy's `recovery` or `parried`), with a combo of 1–3;
    - it answers tells: a perilous sweep gets a hop, a thrust gets a parry tap timed from the tell, and a grab gets a roll away;
    - against other attacks it guards or rolls (seeded); it backs off when out of stamina; it presses the finisher when the prompt shows.
  - **Problems the bot reports**, each as `bot: seed S frame F: <problem>`:
    - any engine error or warning (through `TestLogger`);
    - a **soft-lock**: any actor in one move longer than its clip's length plus 1 s, the player unable to act (no move or movement accepted) for 10 s while alive, or no wave progress for 90 s;
    - a **broken encounter**: an actor outside the yard's bounds or below y = −5, or an enemy that never engages within 15 s of spawning.
    - On any problem, it saves the run's recording to `out/replays/seed_<S>.tres`.
  - **`run_bot.gd`:** `tools/godot.sh -s res://tools/bot/run_bot.gd -- --seeds=1-4 --frames=7200` prints one line per seed (`bot seed 3: waves 4, deaths 1, problems 0`) and exits 1 if any seed has a problem.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_replay.gd
func test_record_then_replay_gives_the_same_state_hash() -> void:   # 600 frames of a ScriptBrain-driven input fixture
func test_replay_goes_through_the_player_brain() -> void:           # a recorded palm press starts palm_jab
# test_combat_bot.gd
func test_bot_two_seeds_no_problems() -> void:                      # 2 seeds x 3,600 frames
func test_bot_reports_a_soft_lock_and_saves_its_replay() -> void:   # a fixture enemy whose move never ends
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/replay` and `--filter=tests/bot`.**
  Expected: FAIL.

- [ ] **Step 3: Implement the Interfaces above.** Run `run_bot.gd` for seeds 1–10 at 7,200 frames. Fix what it finds, each with a test that fails first, and record each find in the task report.

- [ ] **Step 4: Run `tools/test.sh` and `run_bot.gd --seeds=1-10 --frames=7200`.**
  Expected: all pass and 0 problems. Add `run_bot.gd --seeds=1-2 --frames=3600` to the CI headless job.

- [ ] **Step 5: Commit.** Add to STATE.md Done: "F1 Task 15: input recording and replay, the combat bot (seeds 1–10 clean)".

### Task 16: Feel metrics, performance, CI, exports and STATE

**Files:**
- Modify: `tests/feel/test_press_to_motion.gd` (every Abarax move), `tests/perf/` (a combat test), `.github/workflows/all-divine.yml`, `export_presets.cfg` if needed, `ASSETS.md`, `STATE.md`
- Test: `tests/feel/test_press_to_motion.gd`, `tests/perf/test_combat_perf.gd`, `tests/tools/test_ledger.gd`, `tests/tools/test_ci_workflow.gd`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - **Press-to-motion:** palm, heavy, dodge (roll), dodge at rest (hop) and guard each show motion within 2 frames, from rest and from each cancel window that takes them.
  - **The combat performance test:** in the yard, Abarax (driven by the bot) and four Knuckles (two tier I, one each of II and III) fight for 1,200 frames. The mean physics step must be at most 4 ms and the 99th percentile at most 8 ms in the container, headless. Record the numbers in STATE.md as F1's frame budget.
  - **CI:** the headless job runs the tests, clip_check, the Python tools' tests (with the sound tool) and the 2-seed bot. The render jobs are unchanged. The export job builds the three platforms and runs the Linux `--selftest` in the yard.
  - **STATE.md:**
    - F1 Done lines;
    - "Next: F2 Flame and builds (spec §9): write its plan";
    - an **F1 owner checklist**: fight each tier, try parry timing, walk while guarding, hop over sweeps, catch thrusts, roll grabs, the finisher, lock-on and switching, keyboard and mouse cursor facing, the heavy's charge, hit feel (hit-stop, shake, sound). Note what feels wrong in `all-divine/notes/f1.md`;
    - Known limits: the voice layer is empty; no Flask; the camera dip on finishers waits for F4; the sounds are synthesised placeholders; UAL2 clips are close but not tailored to the Open Hand.

- [ ] **Step 1: Write the failing tests** (the extended press-to-motion cases and `test_combat_perf.gd`), plus the CI-workflow and ledger checks for the new step and assets.

- [ ] **Step 2: Run `tools/test.sh --filter=press_to_motion` and `--filter=combat_perf`.**
  Expected: FAIL until the cases and test exist and pass.

- [ ] **Step 3: Implement what fails.** Profile the frame budget with Godot's `Performance` monitors if the perf test misses it, and fix what is hot.

- [ ] **Step 4: Run everything:** `tools/test.sh`, `--render`, `--forward-plus`, clip_check, `tools/bpy_test.sh`, the Python tests, `run_bot.gd --seeds=1-10 --frames=7200`, the three exports, and the exported Linux `--selftest`.
  Expected: all green with no noise, and the bot reports 0 problems.

- [ ] **Step 5: Commit, push, and check CI on the pushed head.** Add to STATE.md Done: "F1 Task 16: feel metrics, combat frame budget, CI with the bot; F1 is built". Update PR #1's description with an F1 section.
