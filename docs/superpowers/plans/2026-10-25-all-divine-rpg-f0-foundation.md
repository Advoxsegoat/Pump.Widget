# The All-Divine F0 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Godot 4.7.2 project, `all-divine/`, that has:
- the HD-2D pixel render pipeline;
- the actor, brain and move system, read from animation marks;
- our own test harness and clip checker;
- the asset and licence pipeline;
- Abarax rigged with locomotion and liveliness layers, in a lit courtyard where walking already feels good.

**Architecture:** The project follows the spec's eight layers.
- *Core* autoloads: game state, inputs, registry.
- *Data*: `.tres` resources.
- *Actors*: a `CharacterBody3D` body, a `Rig` with an `AnimationTree` and skeleton modifiers, and a swappable `Brain`.
- *Moves*: a clip plus `MoveData`, with marks on a `Marks` method track.
- *Presentation*: a 640×360 SubViewport drawn at an integer scale, a snapped orthographic camera, toon and palette shading, and the post effects as our own full-screen shaders, so the Compatibility and Forward+ renderers match.
- *Tools*: GDScript, plus Python and `bpy` for asset intake and motion.
Gameplay runs at a fixed 60 Hz physics tick. Animation is advanced by hand from that tick, so gameplay time and clip time are the same clock.

**Tech Stack:**
- Godot 4.7.2-stable, typed GDScript.
- Python 3.13 with `bpy` 5.2.3 (Blender as a module) via `uv`.
- The Python standard library: `unittest`, `zipfile`, `urllib`.
- Xvfb with Mesa llvmpipe for software renders.
- GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md` (approved 2026-10-25). F0 is the first row of its §9.

## Global Constraints

- Engine: Godot **4.7.2-stable**. `--version` prints exactly `4.7.2.stable.official.ed1daf0bf`. Gameplay is typed GDScript; use GDExtension only where profiling demands it.
- The project lives in `all-divine/` at the repository root. Scenes and resources are plain text (`.tscn`, `.tres`). Binary files are only imported assets (`.glb`, `.png`).
- Internal resolution is **640×360**. It is scaled by whole numbers (×3 to 1920×1080, ×4 to 2560×1440, ×6 to 3840×2160) with nearest-neighbour filtering. The camera snaps to the texel grid, and a sub-pixel offset is applied at the upscale.
- **32 texels per metre** in the world. The orthographic camera size is 11.25 m (360 px ÷ 32), so one internal pixel is 1/32 m in the camera plane.
- Characters have **about 1,500–4,000 triangles**, a toon light ramp of 3–4 steps, and their own palette. Clips play smoothly or stepped at 12 or 24 fps per clip.
- Frames are 1/60 s physics ticks. Input response is **2 frames at most**. The input buffer is **9 frames (150 ms)**. Dodges have about 13 invulnerable frames out of 30. Hit-stop is 3–6 frames.
- Content is data, never code. There is one way to animate anything: through a rig and clips. Layers talk downward or through signals, never sideways into another layer's internals.
- Every system ships with tests that run headless in the container. No third-party test framework: we use our own GDScript runner, and Python's standard-library `unittest` for Python tools.
- Assets are free and openly licensed only: Quaternius and Kenney (CC0), CMU motion capture, and Blender's Python module. No Mixamo. **Every file under `all-divine/assets/` has a row in `ASSETS.md`.**
- Performance target: a steady 60 fps at 1920×1080 on a GTX 1060 / RX 580, a 4-core CPU and 8 GB of RAM.
- `STATE.md` always says what is done, what is next, and where the decisions live. Every task's final commit appends one line under `STATE.md → Done`.
- Commit messages end with the attribution trailers this session specifies, and never contain a model name.

## Review Focus

Five conditions no task's main tests reach on their own, ordered by how likely each is to hurt the person playing or editing:

1. **Odd window sizes:** 1366×768, ultrawide 3440×1440, 1280×800, or a window smaller than 640×360. The scale is never 0, the image stays centred with black bars, and it is never blurred. The test is in Task 3.
2. **Gamepad and keyboard used together, and stick drift:** a resting stick reading 0.1–0.19 never moves Abarax. When both devices are in use, the larger input wins. The tests are in Tasks 2 and 9.
3. **Frame hitches and high-refresh displays:** a long frame, or several physics ticks in one rendered frame, never skips a mark such as a hitbox or invulnerability. The camera stays smooth at 144 Hz through physics interpolation. The tests are in Tasks 3 and 9.
4. **Paths whose case differs:** the owner edits on Windows, where `res://Assets/x.png` loads, but the Linux and CI exports break. Every `res://` reference must match the file's exact case. The test is in Task 1.
5. **Ledges, steep slopes and stairs:** foot IK whose rays miss the ground fades out without NaN or snapping. Abarax can't leave the courtyard or stick in its corners. The tests are in Tasks 13 and 14.

## Environment facts (probed 2026-10-25)

| Fact | Value |
|---|---|
| Godot binary | `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`, SHA-512 `9aa00f7a…ed54c65` (from `SHA512-SUMS.txt` in the same release) |
| Export templates | `…/Godot_v4.7.2-stable_export_templates.tpz` (1.28 GB), SHA-512 `ca4d71c4…cb84079` |
| Renderers in the container | No Vulkan. `forward_plus` falls back to `gl_compatibility`. The Compatibility renderer works under `xvfb-run` and draws shadows, custom `light()` functions, and full-screen quads that read `hint_depth_texture` and `hint_screen_texture` (checked with a depth-edge outline) |
| Godot classes present | `SkeletonModifier3D` (with `_process_modification_with_delta`), `LookAtModifier3D`, `SpringBoneSimulator3D`, `TwoBoneIK3D`, `Logger` with `OS.add_logger`, `AnimationNodeTimeSeek.explicit_elapse`, `ResourceLoader.list_directory`, `GLTFDocument`, `Vector3.MODEL_FRONT = (0,0,1)` |
| itch.io download flow | GET the page and read the `csrf_token` input. POST `{page}/download_url` with the token to get JSON `{url}`. GET that download page; it lists `data-upload_id`. POST `{page}/file/{id}?source=game_download&key={key}` with the token to get JSON `{url}` (a signed R2 link). GET it |
| `ubc` | `quaternius.itch.io/universal-base-characters`. Use `Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf` with its `.bin` and textures. Meshes: `Face` (`MI_Hair_1`, 984 tris), `Face.001` (`MI_Eyes`, 768) and `Sphere.005_Retopology.004` (body, `MI_Superhero_Male`, 12,566). Hairstyles are in `Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/` |
| `ual1` | `quaternius.itch.io/universal-animation-library`. Use `Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb`, which is in place, and `UAL1_Standard_RM.glb`, which has root motion baked in. It has 43 clips, including `A_TPose`, `Idle_Loop`, `Walk_Loop`, `Jog_Fwd_Loop`, `Sprint_Loop`, `Roll`, `Punch_Jab`, `Punch_Cross`, `Hit_Chest`, `Hit_Head`, `Jump_Start`, `Jump_Loop`, `Jump_Land`, `Death01` and `Interact`. There are no strafe or backpedal clips, in this pack or in UAL2 |
| `outfits` | `quaternius.itch.io/modular-character-outfits-fantasy`. Use `…/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf`, whose meshes are `Male_Peasant_Arms`, `_Body`, `_Feet` and `_Legs`, with materials `MI_Peasant` and `MI_Regular_Male` (skin); 12,894 tris. Its readme says to use only the base character's head with outfits |
| Skeleton | Base, UAL and outfits share one 65-joint skeleton: `root, pelvis, spine_01–03, neck_01, Head, clavicle_*, upperarm_*, lowerarm_*, hand_*`, the fingers, `thigh_*, calf_*, foot_*, ball_*, ball_leaf_*` |
| `kenney_town` | `https://kenney.nl/assets/fantasy-town-kit`. The zip link is scraped from the page (now `…/kenney_fantasy-town-kit_2.0.zip`). Use `Models/GLB format/<piece>.glb` and `Models/GLB format/Textures/colormap.png`. A tile is 1 unit and a wall is 1 unit tall |
| Licences | Every pack above is CC0 1.0 |
| Reachable | itch.io and its R2 mirror, kenney.nl, quaternius.com, GitHub release assets, raw.githubusercontent.com, pypi.org. **Not reachable:** mocap.cs.cmu.edu, codeload.github.com |
| Abarax's palette (from *Between the Rooms* `looks.js`, plus Tactics' `--rose`) | skin `#c98a5a`, hair `#4a2e1e`, eyes `#5a2e14`, main `#efe6d6`, sec `#3a4a7a`, pants `#3a3a4a`, boots `#5a3a2a`, rose `#e8607e`, gold `#e8c170` |

## File structure

```
all-divine/
  project.godot  export_presets.cfg  default_bus_layout.tres  .gitignore  .gitattributes
  STATE.md  ASSETS.md
  core/        game.gd  inputs.gd  bindings.gd  registry.gd                      (autoloads + bindings table)
  data/        actors/abarax.tres  moves/*.tres  palettes/abarax.tres  tuning/abarax_locomotion.tres
               render/default_settings.tres  render/grades/courtyard_dusk.tres
  actors/      actor.gd actor.tscn  actor_def.gd  intent.gd  brain.gd player_brain.gd script_brain.gd
               locomotion.gd locomotion_tuning.gd  stats.gd  rig.gd  mark_sink.gd
               abarax/abarax_rig.tscn
               liveliness/ orientation_warp.gd breathing.gd hit_react.gd foot_planter.gd
  moves/       move_data.gd  marks.gd  input_buffer.gd  move_runner.gd
  render/      pixel_snap.gd  pixel_stage.gd pixel_stage.tscn  camera_rig.gd  palette.gd
               render_settings.gd  grade_profile.gd
               shaders/ toon_character.gdshader toon_world.gdshader screen_post.gdshader screen_final.gdshader
  world/       region.gd  courtyard/layout.txt  courtyard/courtyard.tscn
  main/        main.gd main.tscn debug_overlay.gd
  assets/      characters/abarax/abarax.glb  anim/clips.cfg  anim/abarax/*.tres
               env/kenney_town/*.glb + Textures/colormap.png  env/textures/flagstone.png
  tests/       <area>/test_*.gd (headless)   render/test_*.gd (needs a display)   support/   fixtures/
  tools/       setup.sh godot.sh test.sh  test/{test_case,test_logger,test_runner,run}.gd
               clip_check.gd  sheets/contact_sheet.gd  world/build_courtyard.gd  art/make_textures.gd
               assets/{fetch.py,sources.json,import_kenney.py,kenney_town_pieces.txt,tests/}
               anim/{build_abarax.py,gltf_inspect.py,clip_builder.gd,build_library.gd,set_marks.gd,
                     retarget.py,bonemap_cmu.json,tests/}   bpy_test.sh
.github/workflows/all-divine.yml
```

Git-ignored: `all-divine/.godot/`, `.tools/` (Godot), `.cache/` (downloads and extracts), `out/` (sheets, shots and exports) and `tools/.venv/`. Godot skips dot-folders. `out/` gets a `.gdignore`.

Physics layers (in `project.godot`, `layer_names/3d_physics`):
1. `world`: walk collision; stairs are ramps here.
2. `ik_surface`: the exact visible geometry, steps included; foot IK rays use it.
3. `actor`
4. `hurtbox`
5. `hitbox`
6. `interact`

---

### Task 1: Toolchain, project skeleton and the test runner

**Files:**
- Create: `all-divine/project.godot`, `.gitignore`, `.gitattributes` (`* text=auto eol=lf`), `STATE.md`, `out/.gdignore`
- Create: `all-divine/tools/setup.sh`, `tools/godot.sh`, `tools/test.sh`
- Create: `all-divine/tools/test/test_case.gd`, `test_logger.gd`, `test_runner.gd`, `run.gd`
- Test: `all-divine/tests/tools/test_runner_self.gd`, `tests/tools/test_paths.gd`, `tests/fixtures/runner/fixture_{pass,fail,error,await}.gd`

**Interfaces:**
- Produces:
  - `tools/setup.sh [--templates] [--bpy]`:
    - downloads Godot into `all-divine/.tools/godot/` and checks it against `SHA512-SUMS.txt`;
    - `--templates` installs the templates into `~/.local/share/godot/export_templates/4.7.2.stable/`;
    - `--bpy` makes `tools/.venv` with `uv venv --python 3.13` and `uv pip install bpy==5.2.3`;
    - it is safe to run again.
  - `tools/godot.sh [--render|--forward-plus] <args…>` runs `$GODOT`, or else the pinned binary, with `--path all-divine`.
    - By default it adds `--headless`.
    - `--render` wraps the call in `xvfb-run -a -s "-screen 0 1920x1080x24"` and adds `--rendering-method gl_compatibility --audio-driver Dummy`.
    - `--forward-plus` adds `--rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy`, also under xvfb.
  - `tools/test.sh [--render|--forward-plus] [--filter=<s>] [--update-golden]` runs `godot.sh --import` first, then `godot.sh [mode] --fixed-fps 60 -s res://tools/test/run.gd -- <same flags>`. It exits 0 only when every test passes.
  - `class_name TestCase extends Node`:
    - hooks `before_each()` and `after_each()`;
    - assertions `assert_true(c, msg := "")`, `assert_false`, `assert_eq(actual, expected, msg := "")`, `assert_ne`, `assert_near(a: float, b: float, eps: float, msg := "")` and `assert_vec_near(a: Vector3, b: Vector3, eps: float, msg := "")`;
    - `expect_error(fragment: String)`, `fail(msg: String)`;
    - `frames(n: int)`, a coroutine that awaits n physics frames;
    - `track(node: Node) -> Node`, which adds the node under the test and frees it after the test;
    - `update_golden() -> bool`, true when the run was given `--update-golden`.
    - A test is any method named `test_*`. Assertions record a failure and the test carries on.
  - `class_name TestReport extends RefCounted` with `passed: int`, `failed: int` and `results: Array[Dictionary]`. Each result is `{id: "res://…gd::test_x", ok: bool, message: String}`.
  - `class_name TestRunner extends RefCounted`:
    - `func run_files(paths: PackedStringArray, filter := "") -> TestReport` is a coroutine;
    - `static func discover(root := "res://tests", include_render := false) -> PackedStringArray` finds files named `test_*.gd`, skips `fixtures/`, and skips `render/` unless asked.
  - `class_name TestLogger extends Logger`:
    - `push_context()` and `pop_context() -> PackedStringArray` (the errors captured);
    - an error goes only to the top context;
    - only errors of type ERROR, SCRIPT and SHADER count. Warnings never fail a test.
  - `run.gd`:
    - prints `PASS <id>` or `FAIL <id>: <message>` for each test, then `N passed, M failed`;
    - quits 1 if anything failed or no test ran;
    - `--expect-method=<m>` fails the run when `RenderingServer.get_current_rendering_method() != m`. `test.sh` passes `gl_compatibility` with `--render` and `forward_plus` with `--forward-plus`.

- [ ] **Step 1: Write `tools/setup.sh`, `tools/godot.sh` and `tools/test.sh`, and run `bash all-divine/tools/setup.sh`.**
  Expected: the last line is `Godot 4.7.2.stable.official.ed1daf0bf ready`. If the checksum doesn't match, it exits 1.

- [ ] **Step 2: Write the fixtures and the failing self-test.**
  The fixtures:
  - `fixture_pass.gd`: two passing tests, `test_a` and `test_b`.
  - `fixture_fail.gd`: `test_fails` does `assert_eq(1, 2)`.
  - `fixture_error.gd`:
    - `test_unexpected_error` calls `push_error("boom")`;
    - `test_expected_error` does `expect_error("boom")`, then `push_error("boom here")`;
    - `test_missing_expected_error` does `expect_error("never")`.
  - `fixture_await.gd`: `test_waits` awaits `frames(3)` and checks that `Engine.get_physics_frames()` rose by 3.

```gdscript
# tests/tools/test_runner_self.gd
extends TestCase
const F := "res://tests/fixtures/runner/"
func test_counts_passes_failures_and_errors() -> void:
	var r: TestReport = await TestRunner.new().run_files([F + "fixture_pass.gd", F + "fixture_fail.gd", F + "fixture_error.gd", F + "fixture_await.gd"])
	assert_eq(r.passed, 4)
	assert_eq(r.failed, 3)
	var fail := r.results.filter(func(x): return x.id.ends_with("::test_fails"))[0]
	assert_true(fail.message.contains("expected 2, got 1"), fail.message)
func test_filter_selects_one_test() -> void:
	var r: TestReport = await TestRunner.new().run_files([F + "fixture_pass.gd"], "fixture_pass.gd::test_a")
	assert_eq([r.passed, r.failed], [1, 0])
func test_discover_skips_fixtures_and_render() -> void:
	var files := TestRunner.discover()
	assert_true(files.has("res://tests/tools/test_runner_self.gd"))
	assert_false(Array(files).any(func(p): return p.contains("/fixtures/") or p.contains("/render/")))
```

- [ ] **Step 3: Run `all-divine/tools/test.sh`.**
  Expected: FAIL. `run.gd` is missing, so the run exits non-zero.

- [ ] **Step 4: Implement `test_case.gd`, `test_logger.gd`, `test_runner.gd` and `run.gd` as in Interfaces.**
  - The runner instantiates each script, adds it under the root, and awaits each `test_*` method between `before_each` and `after_each`. Awaiting a plain function returns at once.
  - It pushes a `TestLogger` context around each test and frees tracked nodes.
  - A script that fails to load is reported as one failure.

- [ ] **Step 5: Write `tests/tools/test_paths.gd`.**
  It scans every `.tscn`, `.tres`, `.gd`, `.gdshader`, `.cfg` and `project.godot` file under `res://` for `res://` strings, and asserts that each one names an existing file with exactly that case, comparing against `DirAccess` listings.

```gdscript
func test_every_res_path_matches_case_exactly() -> void:
	var bad := PathCheck.mismatches("res://")   # helper class inside the test file
	assert_eq(bad, PackedStringArray(), "\n".join(bad))
```

- [ ] **Step 6: Set `project.godot` and write the starting `STATE.md`.**
  `project.godot`:
  - `config/name="The All-Divine"`, `config/features=PackedStringArray("4.7")`;
  - `display/window/size/viewport_width=1920`, `viewport_height=1080`, `window/stretch/mode="disabled"`, `resizable=true`;
  - `rendering/renderer/rendering_method="forward_plus"`, with `.mobile` and `.web` set to `"gl_compatibility"`;
  - `rendering/textures/canvas_textures/default_texture_filter=0`;
  - `rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality=0` and `positional_shadow/soft_shadow_filter_quality=0`;
  - `rendering/anti_aliasing/quality/msaa_3d=0`;
  - `physics/common/physics_ticks_per_second=60`, `physics/common/physics_interpolation=true`;
  - the six physics layer names.

  `STATE.md` has these sections:
  - `Done` (empty);
  - `Next` ("F0 Task 2");
  - `Decisions` (links to the spec, this plan, and `.superpowers/sdd/…/progress.md` for rulings);
  - `How to run` (`setup.sh`, `test.sh`, `godot.sh --render`);
  - `Toolchain` (Godot 4.7.2-stable, bpy 5.2.3 on Python 3.13).

- [ ] **Step 7: Run `all-divine/tools/test.sh`.**
  Expected: `4 passed, 0 failed`. That is three self-tests and the paths test.

- [ ] **Step 8: Commit.**

```bash
git add all-divine
git commit -m "All-Divine F0: toolchain, project skeleton and the headless test runner"
```

### Task 2: Core autoloads: game state, inputs, registry, audio buses

**Files:**
- Create: `all-divine/core/game.gd`, `core/inputs.gd`, `core/bindings.gd`, `core/registry.gd`, `default_bus_layout.tres`
- Modify: `all-divine/project.godot`, adding the autoloads `Game`, `Inputs` and `Registry`
- Test: `all-divine/tests/core/test_game.gd`, `test_bindings.gd`, `test_inputs.gd`, `test_registry.gd`, `test_audio.gd`, `tests/fixtures/registry/{fixture_item.gd,data/items/a.tres,b.tres,dup.tres}`

**Interfaces:**
- Produces:
  - `Game` (autoload, `core/game.gd`):
    - `enum State { BOOT, TITLE, PLAY, CUTSCENE, MENU, PAUSE }`, `var state := State.BOOT`, `signal state_changed(from: State, to: State)`;
    - `func change(to: State) -> bool`. The allowed moves are BOOT→TITLE, BOOT→PLAY, TITLE→PLAY, PLAY→PAUSE, PAUSE→PLAY, PLAY→MENU, MENU→PLAY, PLAY→CUTSCENE, CUTSCENE→PLAY, PAUSE→TITLE and MENU→TITLE. Any other move raises `push_warning` and returns false;
    - entering PAUSE sets `get_tree().paused = true`, and leaving it sets false;
    - `func reset() -> void` (for tests) returns to BOOT.
  - `class_name Bindings` (`core/bindings.gd`, static):
    - `const ACTIONS: Array[StringName]` = `move_left, move_right, move_up, move_down, palm, heavy, guard, gift, dodge, item, interact, slot_up, slot_right, slot_down, slot_left, slot_next, slot_prev, lock_on, menu`;
    - `static func defaults() -> Dictionary` maps each action to an `Array[InputEvent]`;
    - `static func apply(map: Dictionary) -> void` writes the `InputMap`.

    | Action | Gamepad | Keyboard and mouse |
    |---|---|---|
    | `move_left`, `move_right` | `JOY_AXIS_LEFT_X` −, + | `KEY_A`, `KEY_D` |
    | `move_up`, `move_down` | `JOY_AXIS_LEFT_Y` −, + | `KEY_W`, `KEY_S` |
    | `palm` | `JOY_BUTTON_RIGHT_SHOULDER` | `MOUSE_BUTTON_LEFT` |
    | `heavy` | `JOY_AXIS_TRIGGER_RIGHT` + | `MOUSE_BUTTON_RIGHT` |
    | `guard` | `JOY_BUTTON_LEFT_SHOULDER` | `KEY_Q` |
    | `gift` | `JOY_AXIS_TRIGGER_LEFT` + | `KEY_E` |
    | `dodge` | `JOY_BUTTON_A` | `KEY_SHIFT`, `KEY_SPACE` |
    | `item` | `JOY_BUTTON_X` | `KEY_R` |
    | `interact` | `JOY_BUTTON_Y` | `KEY_F` |
    | `slot_up`, `slot_right`, `slot_down`, `slot_left` | D-pad up, right, down, left | `KEY_1`, `KEY_2`, `KEY_3`, `KEY_4` |
    | `slot_next`, `slot_prev` | — | `MOUSE_BUTTON_WHEEL_DOWN`, `MOUSE_BUTTON_WHEEL_UP` |
    | `lock_on` | `JOY_BUTTON_RIGHT_STICK` | `KEY_TAB` |
    | `menu` | `JOY_BUTTON_START` | `KEY_ESCAPE` |

    Trigger actions use an action deadzone of 0.5.
  - `Inputs` (autoload):
    - `const DEADZONE := 0.2`;
    - `const GAMEPLAY := [&"palm", &"heavy", &"guard", &"gift", &"dodge", &"item", &"interact", &"lock_on", &"slot_up", &"slot_right", &"slot_down", &"slot_left", &"slot_next", &"slot_prev", &"menu"]`;
    - `static func shape_stick(raw: Vector2) -> Vector2`: a radial deadzone, giving 0 below 0.2 and remapping as `(|v|−0.2)/0.8`, clamped to 1;
    - `static func combine(stick: Vector2, keys: Vector2) -> Vector2`: whichever is longer, with keys normalized;
    - `func move_vector() -> Vector2`: in screen space, where up is −y;
    - `func pressed_this_frame() -> Array[StringName]` and `func held(action: StringName) -> bool`;
    - `func rebind(action: StringName, event: InputEvent) -> StringName`: if another action owns an equal event, the two swap (that action receives the rebound action's old event of the same device kind) and its name is returned; otherwise it returns `&""`;
    - `func save_bindings(path := "user://input.cfg") -> Error`;
    - `func load_bindings(path := "user://input.cfg") -> bool`: on a missing or corrupt file, or an unknown action, it raises `push_warning`, applies the defaults and returns false.
  - `Registry` (autoload):
    - `func scan(root := "res://data") -> void` uses `ResourceLoader.list_directory` recursively, so exported builds work;
    - `func fetch(kind: StringName, id: StringName) -> Resource` loads `res://data/<kind>/…` and matches the resource's `id` property. When nothing matches it returns null with `push_error("Registry: no <kind> '<id>'")`;
    - `func ids(kind: StringName) -> PackedStringArray`;
    - a duplicate id calls `push_error("Registry: duplicate id …")` and keeps the first.
  - Audio buses: `Master`, `Music`, `SFX`, `Voice`, `UI`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_game.gd
func before_each() -> void: Game.reset()
func test_boot_to_play_emits_and_changes() -> void:
	var seen := []
	Game.state_changed.connect(func(a, b): seen.append([a, b]))
	assert_true(Game.change(Game.State.PLAY))
	assert_eq(seen, [[Game.State.BOOT, Game.State.PLAY]])
func test_disallowed_change_is_refused() -> void:
	assert_false(Game.change(Game.State.CUTSCENE))
	assert_eq(Game.state, Game.State.BOOT)
func test_pause_pauses_tree_and_play_resumes() -> void:
	Game.change(Game.State.PLAY); Game.change(Game.State.PAUSE)
	assert_true(get_tree().paused)
	Game.change(Game.State.PLAY)
	assert_false(get_tree().paused)
# test_bindings.gd: table-driven over the table above. For example:
func test_palm_binds_rb_and_left_mouse() -> void:
	var ev: Array = Bindings.defaults()[&"palm"]
	assert_true(ev.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER))
	assert_true(ev.any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT))
func test_every_action_but_wheel_slots_has_pad_and_kbm() -> void: ...
# test_inputs.gd
func test_stick_drift_below_deadzone_is_still() -> void:
	for v in [Vector2(0.1, 0), Vector2(0.12, -0.1), Vector2(0, 0.19)]:
		assert_eq(Inputs.shape_stick(v), Vector2.ZERO)
func test_stick_remaps_past_deadzone() -> void:
	assert_vec_near(Vector3(Inputs.shape_stick(Vector2(0.6, 0)).x, 0, 0), Vector3(0.5, 0, 0), 1e-4)
	assert_eq(Inputs.shape_stick(Vector2(1, 0)), Vector2(1, 0))
func test_stick_and_keys_combine_to_the_longer() -> void:
	assert_eq(Inputs.combine(Vector2(0.3, 0), Vector2(0, -1)), Vector2(0, -1))
	assert_eq(Inputs.combine(Vector2(0.9, 0), Vector2.ZERO), Vector2(0.9, 0))
func test_rebind_conflict_swaps() -> void:
	var q := InputEventKey.new(); q.physical_keycode = KEY_Q
	assert_eq(Inputs.rebind(&"palm", q), &"guard")
	assert_true(InputMap.action_get_events(&"guard").any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT))
func test_bindings_round_trip_and_corrupt_file_falls_back() -> void:
	# save to user://test_input.cfg and load: events are equal. Write garbage: load_bindings is false and the defaults apply.
func test_pressed_this_frame_reports_action_press() -> void:
	Input.action_press(&"palm"); await frames(1)
	assert_true(Inputs.pressed_this_frame().has(&"palm")); Input.action_release(&"palm")
# test_registry.gd uses the fixtures. The fixture item script has `@export var id: StringName`.
func test_fetch_by_id_and_duplicate_reports_error() -> void:
	expect_error("duplicate id")
	Registry.scan("res://tests/fixtures/registry/data")
	assert_eq(Registry.fetch(&"items", &"b").id, &"b")
	assert_eq(Registry.ids(&"items").size(), 2)
func test_missing_id_errors_and_returns_null() -> void: ...
# test_audio.gd
func test_bus_layout() -> void:
	assert_eq(range(AudioServer.bus_count).map(func(i): return AudioServer.get_bus_name(i)), ["Master", "Music", "SFX", "Voice", "UI"])
```

- [ ] **Step 2: Run `all-divine/tools/test.sh --filter=tests/core`.**
  Expected: FAIL, because the autoloads are missing (`Identifier "Game" not declared`).

- [ ] **Step 3: Implement `game.gd`, `bindings.gd`, `inputs.gd`, `registry.gd` and the bus layout.**
  Register the autoloads. `Inputs._ready()` applies the defaults, then calls `load_bindings()`. `Registry._ready()` calls `scan()`. Tests that change bindings or the registry restore them in `after_each`, with `Bindings.apply(Bindings.defaults())` and `Registry.scan()`.

- [ ] **Step 4: Run `all-divine/tools/test.sh`.**
  Expected: every test passes, including Task 1's.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Core autoloads: Game, Inputs (§4.1 bindings, rebinding, deadzone), Registry, audio buses".

### Task 3: The pixel stage: 640×360, integer upscale, snapped camera

**Files:**
- Create: `all-divine/render/pixel_snap.gd`, `render/pixel_stage.gd`, `render/pixel_stage.tscn`, `render/camera_rig.gd`
- Test: `all-divine/tests/look/test_pixel_snap.gd`, `tests/look/test_camera_rig.gd`, `tests/render/test_pixel_stage.gd`

**Interfaces:**
- Produces:
  - `class_name PixelSnap`:
    - `const TEXEL := 1.0 / 32.0`, `const INTERNAL := Vector2i(640, 360)`, `const MARGIN := 1`;
    - `static func snap(pos: Vector3, basis: Basis, texel := TEXEL) -> Vector3` rounds the `basis.x` and `basis.y` components of `pos` to multiples of `texel` and keeps the `basis.z` component. It is not called `snapped`, which would shadow GDScript's built-in function;
    - `static func subpixel(pos: Vector3, basis: Basis, texel := TEXEL) -> Vector2` returns `(dot(pos − snap(pos), basis.x), dot(pos − snap(pos), basis.y)) / texel`, each in [−0.5, 0.5].
  - `class_name PixelStage extends Control` (full rect, `texture_filter = NEAREST`):
    - a child `World: SubViewport` of size **642×362**, with its own `World3D`;
    - `var subpixel := Vector2.ZERO`;
    - `static func scale_for(window: Vector2i) -> int` is `max(1, min(window.x / 640, window.y / 360))` in integer division;
    - `static func layout(window: Vector2i) -> Rect2i` is the destination rect of the 640×360 image at that scale, centred (its position may be negative when the window is smaller than 640×360);
    - `static func draw_offset(subpixel: Vector2, k: int) -> Vector2i` is `Vector2i(roundi((-1.0 - subpixel.x) * k), roundi((-1.0 + subpixel.y) * k))`;
    - `_draw()` draws the World texture at `layout.position + draw_offset`, at size 642×362×k, clipped to the layout rect (`clip_contents`). The area outside is black.
  - `class_name CameraRig extends Node3D`:
    - a child `Camera3D` with `projection = ORTHOGONAL` and `size = 11.25`;
    - `const PITCH_DEG := -40.0`, `const YAW_DEG := 0.0`, `const DISTANCE := 20.0`;
    - `@export var target: Node3D`, `@export var smooth_time := 0.15`, `@export var look_ahead := 0.8`, `var stage: PixelStage`;
    - `func yaw() -> float`;
    - in `_process`, it follows `target.get_global_transform_interpolated().origin`, plus a look-ahead of `look_ahead × clamp(speed / 4.0, 0, 1)` along the target's velocity when the target has a `velocity`. The follow uses a critically damped spring with `smooth_time`. It then sets `camera.global_position = PixelSnap.snap(...)` and `stage.subpixel = PixelSnap.subpixel(...)`;
    - `func snap_now() -> void` moves straight to the target, for spawns and tests.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_pixel_snap.gd
func test_layout_for_standard_sizes() -> void:
	for c in [[Vector2i(1920,1080),3,Vector2i(0,0)], [Vector2i(2560,1440),4,Vector2i(0,0)], [Vector2i(3840,2160),6,Vector2i(0,0)]]:
		assert_eq(PixelStage.scale_for(c[0]), c[1]); assert_eq(PixelStage.layout(c[0]).position, c[2])
func test_layout_for_odd_window_sizes() -> void:
	for c in [[Vector2i(1366,768),2,Vector2i(43,24)], [Vector2i(3440,1440),4,Vector2i(440,0)], [Vector2i(1280,800),2,Vector2i(0,40)], [Vector2i(600,300),1,Vector2i(-20,-30)]]:
		assert_eq(PixelStage.scale_for(c[0]), c[1]); assert_eq(PixelStage.layout(c[0]).position, c[2])
		assert_eq(PixelStage.layout(c[0]).size, Vector2i(640, 360) * c[1])
func test_snap_keeps_depth_and_reports_subpixel() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(-40), 0, 0))
	var p := Vector3(0.3 * PixelSnap.TEXEL, 0, 0)
	assert_vec_near(PixelSnap.snap(p, b), Vector3.ZERO, 1e-6)
	assert_near(PixelSnap.subpixel(p, b).x, 0.3, 1e-4)
	var q := b.z * 3.7
	assert_vec_near(PixelSnap.snap(q, b), q, 1e-6)
func test_draw_offset_signs() -> void:
	assert_eq(PixelStage.draw_offset(Vector2.ZERO, 3), Vector2i(-3, -3))
	assert_eq(PixelStage.draw_offset(Vector2(0.3, 0), 3), Vector2i(-4, -3))
	assert_eq(PixelStage.draw_offset(Vector2(0, 0.5), 4), Vector2i(-4, -2))
# test_camera_rig.gd (headless; a stage with a Node3D target)
func test_camera_is_fixed_ortho_three_quarter() -> void: # pitch −40°, yaw 0, ORTHOGONAL, size 11.25
func test_camera_follows_and_lands_on_texel_grid() -> void:
	# Move the target 1 m along +X, await frames(120), then:
	# the camera's dot(pos, basis.x) / TEXEL is an integer within 1e-3, and the follow point is within one texel of the target.
func test_physics_interpolation_enabled() -> void:
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation"))
```

```gdscript
# tests/render/test_pixel_stage.gd (render: a checker plane and a box in World; window 1920×1080)
func test_upscale_is_crisp_three_by_three_blocks() -> void:
	# Await frames(5) with subpixel 0 and capture get_viewport().get_texture().get_image().
	# Pick 300 seeded-random 3×3 blocks aligned to the layout and assert all 9 pixels are identical.
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/look`, then `tools/test.sh --render --filter=test_pixel_stage`.**
  Expected: both FAIL because the classes are missing.

- [ ] **Step 3: Implement `pixel_snap.gd`, `pixel_stage.gd`/`.tscn` and `camera_rig.gd` as in Interfaces.**
  The spring is `x += (target − x) × (1 − exp(−delta × 4.0 / smooth_time))`. That is critically damped close enough to tune later; the constant lives in the script.

- [ ] **Step 4: Run both commands again.**
  Expected: PASS.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Pixel stage: 640×360 → integer upscale, texel-snapped ortho camera, sub-pixel offset".

### Task 4: Asset intake and the licence ledger

**Files:**
- Create: `all-divine/tools/assets/fetch.py`, `tools/assets/sources.json`, `tools/assets/import_kenney.py`, `tools/assets/kenney_town_pieces.txt`, `tools/assets/tests/test_fetch.py`
- Create: `all-divine/ASSETS.md`, `assets/env/kenney_town/*.glb`, `assets/env/kenney_town/Textures/colormap.png`
- Test: `all-divine/tests/tools/test_ledger.gd`, `tools/assets/tests/test_fetch.py`

**Interfaces:**
- Produces:
  - `python3 -I tools/assets/fetch.py fetch <id|all> [--accept-new]`:
    - downloads to `all-divine/.cache/downloads/<id>.zip` and checks it against the `sha256` in `sources.json`;
    - a mismatch exits 2 unless `--accept-new`, which records the new hash;
    - extracts safely to `.cache/extract/<id>/`.
  - `fetch.py path <id>` prints that extract directory.
  - Library functions, kept pure for tests:
    - `parse_csrf(html) -> str`
    - `parse_upload_ids(html) -> list[str]`
    - `parse_kenney_zip(html) -> str`
    - `safe_extract(zip_path, dest) -> list[str]`, which raises `ValueError` on an absolute member or one containing `..`
    - `verify(path, sha256, accept_new) -> str`
  - `sources.json` has the ids:
    - `ubc`, `ual1`, `outfits`: `{"kind": "itch", "page": "https://quaternius.itch.io/<slug>", "sha256": ""}`;
    - `kenney_town`: `{"kind": "kenney", "page": "https://kenney.nl/assets/fantasy-town-kit"}`.
    The first real fetch fills each hash with `--accept-new`.
  - `import_kenney.py` copies each piece listed in `kenney_town_pieces.txt` from the extract's `Models/GLB format/` into `assets/env/kenney_town/`, along with `Textures/colormap.png`, keeping the relative texture path. The pieces are:
    - walls: `wall`, `wall-corner`, `wall-door`, `wall-doorway-round`, `wall-half`, `pillar-stone`;
    - stairs and slopes: `stairs-stone`, `stairs-wide-stone`, `stairs-stone-handrail`, `road-slope`;
    - the fountain and lantern: `fountain-round`, `fountain-round-detail`, `lantern`;
    - greenery: `tree`, `tree-high-round`, `hedge`, `hedge-large`;
    - the market: `stall-red`, `stall-bench`, `stall-stool`, `banner-red`, `banner-green`, `cart`;
    - other props: `rock-small`, `fence`.
  - `ASSETS.md` is a table, `| Path | Source | Licence | Changes |`.
    - A path ending in `/` covers everything under it.
    - Allowed licences are `CC0 1.0`, `ours`, and `CMU (free for any use)`.
    - Downloads run with `python3 -I` and the tool's own paths as arguments, never from inside the extract folder.

- [ ] **Step 1: Write the failing tests.**

```python
# tools/assets/tests/test_fetch.py (stdlib unittest; no network)
class SafeExtract(unittest.TestCase):
    def test_refuses_parent_and_absolute_members(self):
        # Build a zip in a temp dir with '../evil.txt', then with '/abs.txt': each raises ValueError, and nothing is written outside dest.
    def test_extracts_paths_with_spaces_and_brackets(self):
        # 'Universal Base Characters[Standard]/a b.txt' extracts to dest/… with its bytes intact.
class Parsing(unittest.TestCase):
    def test_csrf_and_upload_ids(self):
        html = '<input name="csrf_token" value="T0K"> <a data-upload_id="123">x</a><a data-upload_id="456">'
        self.assertEqual(fetch.parse_csrf(html), "T0K"); self.assertEqual(fetch.parse_upload_ids(html), ["123", "456"])
    def test_kenney_zip_link(self):
        html = '<a href="https://kenney.nl/media/pages/assets/fantasy-town-kit/efe948d309-1754222374/kenney_fantasy-town-kit_2.0.zip">'
        self.assertTrue(fetch.parse_kenney_zip(html).endswith("kenney_fantasy-town-kit_2.0.zip"))
class Verify(unittest.TestCase):
    def test_mismatch_raises_unless_accept_new(self): ...
```

```gdscript
# tests/tools/test_ledger.gd
func test_every_asset_file_has_a_ledger_row() -> void:
	var missing := Ledger.unlisted("res://assets", "res://ASSETS.md")   # helper in the test file; skips *.import
	assert_eq(missing, PackedStringArray(), "\n".join(missing))
func test_ledger_rows_name_existing_paths_and_allowed_licences() -> void: ...
```

- [ ] **Step 2: Run `python3 -I -m unittest discover -s all-divine/tools/assets/tests -v` and `tools/test.sh --filter=test_ledger`.**
  Expected: the Python tests FAIL because `fetch` won't import. The ledger test FAILS because `ASSETS.md` is missing.

- [ ] **Step 3: Implement `fetch.py` and `import_kenney.py`, then fetch and import.**
  Run `python3 -I tools/assets/fetch.py fetch all --accept-new` and `python3 -I tools/assets/import_kenney.py`. Write `ASSETS.md` with the row `assets/env/kenney_town/ | Kenney Fantasy Town Kit 2.0, https://kenney.nl/assets/fantasy-town-kit | CC0 1.0 | pieces copied unchanged`.

- [ ] **Step 4: Run both commands again, then the whole `tools/test.sh`.**
  Expected: PASS. Godot imports the `.glb` files without errors.

- [ ] **Step 5: Commit** `sources.json` (with its hashes), the tools, `ASSETS.md` and the Kenney pieces with their `.import` files. Add to STATE.md Done: "Asset intake (itch/Kenney fetch with hashes) and the ASSETS.md ledger check".

### Task 5: Abarax's model, built with `bpy`

**Files:**
- Create: `all-divine/tools/anim/build_abarax.py`, `tools/anim/gltf_inspect.py`, `tools/bpy_test.sh`, `tools/anim/tests/test_build_abarax.py`
- Create: `all-divine/assets/characters/abarax/abarax.glb` (+ `.import`, animation import off)
- Modify: `all-divine/ASSETS.md`
- Test: `all-divine/tests/actors/test_abarax_model.gd`, `tools/anim/tests/test_build_abarax.py`

**Interfaces:**
- Consumes: `fetch.py path ubc|outfits` (Task 4).
- Produces:
  - `tools/.venv/bin/python -I tools/anim/build_abarax.py --ubc <dir> --outfits <dir> --out <glb>`, a deterministic build.
  - `gltf_inspect.py`, a stdlib glTF/GLB reader: `load(path) -> dict`, `joint_names(j) -> list[str]`, `triangle_count(j) -> int`, `uv2_slots(j, path) -> set[int]`.
  - `tools/bpy_test.sh` runs `tools/.venv/bin/python -I -m unittest discover -s tools/anim/tests -v`.
  - Palette slots live in **UV2.x = (slot + 0.5) / 16**. Vertex colours are never used; the importer may convert them.

    | Slot | Name | Taken from |
    |---|---|---|
    | 0 | skin | the base head region of the body mesh, and outfit faces using `MI_Regular_Male` |
    | 1 | hair | the hairstyle mesh, and `Face` (`MI_Hair_1`: brows and stubble) |
    | 2 | eyes | `Face.001` (`MI_Eyes`) |
    | 3 | main | `Male_Peasant_Body` and `Male_Peasant_Arms` faces using `MI_Peasant` |
    | 4 | sec | faces of `Male_Peasant_Body` whose texture luminance, sampled at the face's UV centroid, is below `SPLIT_LUMA` |
    | 5 | pants | `Male_Peasant_Legs` |
    | 6 | boots | `Male_Peasant_Feet` |
    | 7 | rose | the scarf |
    | 8 | gold | reserved, unused in F0 |

    `SPLIT_LUMA` is a constant in the script, chosen by looking at `T_Peasant` base colour and commented there.
  - Bones: the 65 base joints, plus `scarf_01`→`scarf_04`. `scarf_01`'s parent is `neck_01`, and each bone is 0.175 m long, hanging down the back.

- [ ] **Step 1: Run `bash all-divine/tools/setup.sh --bpy`.**
  Expected: `tools/.venv/bin/python -I -c "import bpy; print(bpy.app.version_string)"` prints `5.2.3`.

- [ ] **Step 2: Write the failing tests.**

```python
# tools/anim/tests/test_build_abarax.py. setUpClass runs the build into a temp glb, using fetch.py's extract paths.
BASE = ["root","pelvis","spine_01","spine_02","spine_03","neck_01","Head", ...]   # all 65, from the Environment facts
def test_skeleton_is_base_plus_scarf(self):
    names = gltf_inspect.joint_names(self.j)
    self.assertEqual(set(names), set(BASE) | {"scarf_01","scarf_02","scarf_03","scarf_04"})
def test_triangle_budget(self):
    self.assertTrue(1500 <= gltf_inspect.triangle_count(self.j) <= 4000)
def test_every_primitive_has_uv2_slots_in_range(self):
    self.assertTrue(gltf_inspect.uv2_slots(self.j, self.path) <= set(range(9)))
    self.assertTrue({0, 1, 3, 5, 6, 7} <= gltf_inspect.uv2_slots(self.j, self.path))
def test_no_textures_and_one_material(self):
    self.assertEqual(self.j.get("images", []), []); self.assertEqual([m["name"] for m in self.j["materials"]], ["toon"])
```

```gdscript
# tests/actors/test_abarax_model.gd
const MODEL := "res://assets/characters/abarax/abarax.glb"
func test_imports_with_one_skeleton_and_scarf_chain() -> void:
	var s: Skeleton3D = track(load(MODEL).instantiate()).find_children("*", "Skeleton3D")[0]
	assert_eq(s.get_bone_count(), 69)
	assert_eq(s.get_bone_name(s.get_bone_parent(s.find_bone("scarf_01"))), "neck_01")
func test_triangles_in_budget() -> void:   # sum of surface index counts / 3 over MeshInstance3D: 1500..4000
func test_faces_model_front_and_human_height() -> void:
	# In the rest pose, ball_l's global z is greater than foot_l's (toes toward +Z = Vector3.MODEL_FRONT), and Head's global y is in 1.5–1.9 m.
```

- [ ] **Step 3: Run `tools/bpy_test.sh` and `tools/test.sh --filter=test_abarax_model`.**
  Expected: both FAIL because the script and the model are missing.

- [ ] **Step 4: Implement `build_abarax.py`.** In order:
  1. Import the base glTF, `Male_Peasant.gltf` and the hairstyle `Hair_SimpleParted.gltf` (rigged to head bone).
  2. Delete the body faces whose vertices' strongest weight is not `Head` or `neck_01`, keeping only the head, as the outfit readme says.
  3. Parent the outfit and hair meshes to the base armature by bone name, and drop the extra armatures.
  4. Add the scarf: a neck loop of 8 segments plus a ribbon 0.12 m wide and 0.7 m long down the back, weighted linearly between neighbouring scarf bones.
  5. Assign slots into UV2 by the table.
  6. Triangulate, then decimate each mesh (collapse) with the ratio `3800 / total`, at least 12 triangles per mesh.
  7. Replace all materials with one called `toon`, and remove the images.
  8. Export a GLB with skinning, no animations, and UV2 kept.

  Then run it for real into `assets/characters/abarax/abarax.glb`. Add an `ASSETS.md` row: the Quaternius sources (UBC head, Fantasy Outfits `Male_Peasant`, `Hair_SimpleParted`) under CC0 1.0, with the changes "head-only, parts assembled on one skeleton as separate meshes, scarf bones added, palette slots in UV2, decimated to ≤4,000 tris, textures removed (tools/anim/build_abarax.py)".

- [ ] **Step 5: Run `tools/bpy_test.sh` and `tools/test.sh`.**
  Expected: all pass. If the decimated face looks broken on Task 7's contact sheet, change the per-mesh shares, keeping the total within 4,000, and record a ruling.

- [ ] **Step 6: Commit**, adding to STATE.md Done: "Abarax model: Quaternius head + peasant outfit + scarf bones, palette slots in UV2, ≤4,000 tris".

### Task 6: The animation library

**Files:**
- Create: `all-divine/tools/anim/clip_builder.gd`, `tools/anim/build_library.gd`, `assets/anim/clips.cfg`
- Create: `all-divine/assets/anim/abarax/{idle,walk,jog,sprint,dodge_roll,palm_jab,palm_cross,t_pose}.tres`, `assets/anim/abarax/library.tres`
- Modify: `all-divine/ASSETS.md`, adding the row `assets/anim/` (Quaternius UAL, CC0 1.0, "extracted, renamed, retimed, track paths rewritten; marks added")
- Test: `all-divine/tests/anim/test_clip_builder.gd`, `tests/anim/test_library.gd`

**Interfaces:**
- Consumes: `abarax.glb` (Task 5); `fetch.py path ual1` (Task 4).
- Produces:
  - `class_name ClipBuilder extends RefCounted`:
    - `static func load_gltf_animations(path: String) -> Dictionary`, name → Animation, through `GLTFDocument.append_from_file` and `generate_scene`, with no import;
    - `static func skeleton_path(model: PackedScene) -> NodePath`, the path from the model root to its `Skeleton3D`;
    - `static func rewrite_paths(anim: Animation, skel: NodePath, bones: PackedStringArray) -> Animation`: every bone track becomes `Model/<skel>:<bone>`, and tracks for unknown bones are dropped;
    - `static func retime(anim: Animation, length: float) -> Animation`, which scales key times;
    - `static func ground_speed(rm_anim: Animation, skel: NodePath) -> float`, the horizontal displacement of the `root` bone over the clip divided by its length;
    - `static func merge_kept_tracks(new_anim: Animation, old_anim: Animation) -> void` copies every non-bone track (the `Marks` method track first) from the old clip;
    - `static func build(cfg_path: String, sources: Dictionary, out_dir: String, model_path: String) -> Error` writes `<out_dir>/<name>.tres` for each section and `library.tres`. When a clip file already exists, its kept tracks are merged into the new one.
  - CLI: `tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 <dir>` maps the source keys `ual1` and `ual1_rm` to the two GLBs.
  - Animation metadata: `step_fps` (int, 0 = smooth) on every clip; `ground_speed` (float, m/s) on `walk`, `jog` and `sprint`.
  - `clips.cfg`, exactly:

```ini
[idle]
source="ual1"
clip="Idle_Loop"
loop=true
[walk]
source="ual1"
clip="Walk_Loop"
loop=true
ground_speed_from="ual1_rm"
[jog]
source="ual1"
clip="Jog_Fwd_Loop"
loop=true
ground_speed_from="ual1_rm"
[sprint]
source="ual1"
clip="Sprint_Loop"
loop=true
ground_speed_from="ual1_rm"
[dodge_roll]
source="ual1_rm"
clip="Roll"
length=0.5
step_fps=0
[palm_jab]
source="ual1_rm"
clip="Punch_Jab"
length=0.583333
step_fps=12
[palm_cross]
source="ual1_rm"
clip="Punch_Cross"
length=0.666667
step_fps=12
[t_pose]
source="ual1"
clip="A_TPose"
```

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_clip_builder.gd (in memory)
func test_retime_scales_key_times() -> void:   # a 1.0 s clip with a key at 0.5, retimed to 0.5, has its key at 0.25
func test_rewrite_paths_drops_unknown_bones() -> void:
func test_merge_keeps_marks_track() -> void:
	var old := Animation.new(); var t := old.add_track(Animation.TYPE_METHOD); old.track_set_path(t, "Marks")
	old.track_insert_key(t, 0.1, {"method": "sfx", "args": [{"name": "x"}]})
	var fresh := Animation.new(); ClipBuilder.merge_kept_tracks(fresh, old)
	assert_eq(fresh.track_get_path(0), NodePath("Marks")); assert_eq(fresh.track_get_key_count(0), 1)
# test_library.gd (the committed files)
const LIB := "res://assets/anim/abarax/library.tres"
func test_has_all_clips() -> void:
	var lib: AnimationLibrary = load(LIB)
	for n in ["idle", "walk", "jog", "sprint", "dodge_roll", "palm_jab", "palm_cross", "t_pose"]: assert_true(lib.has_animation(n), n)
func test_loops_and_lengths_and_steps() -> void:
	# idle, walk, jog and sprint use LOOP_LINEAR. dodge_roll is 0.5, palm_jab 0.5833 and palm_cross 0.6667, each ±0.001.
	# step_fps: palm_jab and palm_cross 12, dodge_roll 0.
func test_ground_speeds_are_plausible_and_ordered() -> void:
	# walk 1.0–2.2, jog 2.5–5.5, sprint 4.5–8.0, and walk < jog < sprint.
func test_every_track_targets_a_real_bone() -> void:   # each bone track's subname is a bone of abarax.glb's skeleton
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/anim`.**
  Expected: FAIL because `ClipBuilder` is missing.

- [ ] **Step 3: Implement `clip_builder.gd` and `build_library.gd`, then run the build.**
  Run `tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 "$(python3 -I tools/assets/fetch.py path ual1)"`. Reimport with `tools/godot.sh --import`.

- [ ] **Step 4: Run `tools/test.sh`.**
  Expected: all pass.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Animation library: UAL clips extracted to text .tres, retimed, ground speeds measured, marks preserved on rebuild".

### Task 7: The rig and the contact sheets

**Files:**
- Create: `all-divine/actors/rig.gd`, `actors/mark_sink.gd`, `actors/abarax/abarax_rig.tscn`, `tools/sheets/contact_sheet.gd`
- Test: `all-divine/tests/actors/test_rig.gd`, `tests/render/test_contact_sheet.gd`

**Interfaces:**
- Consumes: `library.tres` and its metadata (Task 6); `PixelStage` and `CameraRig` (Task 3).
- Produces:
  - `abarax_rig.tscn`:
    - root `Rig` (`rig.gd`);
    - `Model`, the `abarax.glb` instance with editable children;
    - `AnimationTree`, with `root_node = ".."`, the Abarax library, `callback_mode_process = MANUAL`, and `root_motion_track = "Model/<skel>:root"`;
    - `Marks` (`MarkSink`);
    - `Hitboxes`, with `palm_l` and `palm_r`: each a `BoneAttachment3D` (external skeleton) on `hand_l` or `hand_r`, holding an `Area3D` named `zone` on layer `hitbox`, with a 0.18 m sphere and monitoring off;
    - `Hurtbox`: an `Area3D` on layer `hurtbox`, with a capsule of radius 0.35 and height 1.7 at y 0.9.
  - The tree (`AnimationNodeBlendTree`), with these node names:
    - `loco`: `BlendSpace1D`, with points idle at 0 and walk, jog and sprint at their `ground_speed` metadata, sync on;
    - `loco_scale`: `TimeScale`;
    - `move_a` and `move_b`: `Animation`;
    - `seek_a` and `seek_b`: `TimeSeek`;
    - `move_ab`: `Blend2`;
    - `move_blend`: `Blend2`, between `loco_scale` and `move_ab`, feeding the output.
  - `MarkSink extends Node` has one no-op method per mark kind, so the editor can preview clips: `func hitbox_on(args: Dictionary) -> void: pass`, and the same for `hitbox_off`, `iframes_on`, `iframes_off`, `hyperarmour_on`, `hyperarmour_off`, `cancel_open`, `cancel_close`, `recovery`, `fx`, `sfx`, `shake` and `hitstop`.
  - `class_name Rig extends Node3D`:
    - `var skeleton: Skeleton3D`, `var tree: AnimationTree`;
    - `func set_locomotion(speed: float, backward: bool) -> void`;
    - `func play_move(clip: StringName, blend_in: float) -> void` uses the other slot and crossfades `move_ab` over `blend_in`; `move_blend` goes to 1 over `blend_in`;
    - `func set_move_time(t: float) -> void` stores gameplay time; the visual time is `stepped_time(t, step_fps)`;
    - `func stop_move(blend_out: float) -> void`;
    - `func tick(delta: float) -> void` sets the seek requests, updates the blend amounts, then calls `tree.advance(delta)`;
    - `func move_weight() -> float`;
    - `func bone_global(bone: StringName) -> Vector3`;
    - `func set_hitbox_active(id: StringName, on: bool) -> void`, `func active_hitboxes() -> Array[StringName]`;
    - `static func stepped_time(t: float, fps: int) -> float` returns t when `fps <= 0` or `t <= 0`, else `maxf(floorf(t * fps + 1e-4), 1.0) / fps`. The first step shows at once, for input response, and the rest sit on the step grid, so marks line up.
  - `class_name ContactSheet`:
    - `static func render(def_or_rig: Variant, clips: PackedStringArray, cell := Vector2i(160, 120)) -> Image`;
    - the CLI is `tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- --rig res://actors/abarax/abarax_rig.tscn --out out/sheets/abarax.png [--clips a,b]`;
    - each clip gets one cell per mark frame, or 6 even frames when the clip has no marks;
    - cells are cropped around the actor from a `PixelStage` render with the gameplay `CameraRig`, drawn ×2 in a `GridContainer` of 6 columns with a `Label` "`clip fN`", and captured from a SubViewport.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_rig.gd
func rig() -> Rig: return track(load("res://actors/abarax/abarax_rig.tscn").instantiate())
func test_stepped_time() -> void:
	assert_near(Rig.stepped_time(0.13, 12), 1.0 / 12, 1e-6); assert_near(Rig.stepped_time(0.25, 12), 0.25, 1e-6)
	assert_near(Rig.stepped_time(0.01, 12), 1.0 / 12, 1e-6); assert_eq(Rig.stepped_time(0.0, 12), 0.0)
	assert_near(Rig.stepped_time(0.13, 0), 0.13, 1e-9)
func test_locomotion_points_are_clip_ground_speeds() -> void:
func test_root_motion_track_set() -> void:
func test_move_pose_matches_clip_time_and_holds_between_steps() -> void:
	var r := rig(); r.play_move(&"palm_jab", 0.0); r.set_move_time(0.25); r.tick(0.0)
	var a: Animation = r.tree.get_animation(&"palm_jab")
	var tr := a.find_track(NodePath("Model/%s:hand_l" % ClipBuilder.skeleton_path(load("res://assets/characters/abarax/abarax.glb"))), Animation.TYPE_ROTATION_3D)
	var want := a.rotation_track_interpolate(tr, 0.25)
	var got := r.skeleton.get_bone_pose_rotation(r.skeleton.find_bone("hand_l"))
	assert_true(got.is_equal_approx(want) or got.angle_to(want) < 0.002)
	r.set_move_time(0.27); r.tick(1.0 / 60)
	assert_true(r.skeleton.get_bone_pose_rotation(r.skeleton.find_bone("hand_l")).angle_to(want) < 0.002)
func test_crossfade_between_moves() -> void:   # three ticks into a 0.1 s blend_in, the new slot's weight is 0.5 ± 0.05
func test_hitbox_toggle() -> void:
	var r := rig(); r.set_hitbox_active(&"palm_r", true)
	assert_eq(r.active_hitboxes(), [&"palm_r"]); assert_true((r.get_node("Hitboxes/palm_r/zone") as Area3D).monitoring)
# tests/render/test_contact_sheet.gd
func test_sheet_has_a_cell_per_frame_and_content() -> void:
	var img := ContactSheet.render(load("res://actors/abarax/abarax_rig.tscn"), ["idle", "palm_jab"])
	# Six cells for idle, plus one per unique palm_jab mark frame (or six when it has no marks yet). Width is 6 × 320.
	# Each cell has more than 4 distinct colours.
```

- [ ] **Step 2: Run `tools/test.sh --filter=test_rig` and `tools/test.sh --render --filter=test_contact_sheet`.**
  Expected: FAIL because `Rig` is missing.

- [ ] **Step 3: Implement `rig.gd`, `mark_sink.gd`, `abarax_rig.tscn` and `contact_sheet.gd`.**
  If `TimeSeek` with manual advance doesn't put the move exactly at the seek time, set `explicit_elapse` the way the pose test needs, and record a ruling.

- [ ] **Step 4: Run both commands again, then `tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- --rig res://actors/abarax/abarax_rig.tscn --out out/sheets/abarax.png`.**
  Expected: PASS, and the PNG exists. Look at it: Abarax reads at 640×360, the scarf hangs, and the face isn't broken.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Rig: AnimationTree (speed-blended locomotion, two-slot move layer, stepped playback), hitboxes, contact sheets".

### Task 8: Moves: MoveData, marks, the input buffer and the clip checker

**Files:**
- Create: `all-divine/moves/move_data.gd`, `moves/marks.gd`, `moves/input_buffer.gd`, `actors/actor_def.gd`, `actors/locomotion_tuning.gd`, `tools/clip_check.gd`, `tools/anim/set_marks.gd`
- Create: `all-divine/data/moves/palm_jab.tres`, `palm_cross.tres`, `dodge_roll.tres`, `data/actors/abarax.tres`, `data/tuning/abarax_locomotion.tres`
- Modify: `all-divine/assets/anim/abarax/{palm_jab,palm_cross,dodge_roll}.tres`, writing marks with `set_marks.gd`
- Test: `all-divine/tests/moves/test_input_buffer.gd`, `test_marks.gd`, `test_clip_checker.gd`

**Interfaces:**
- Consumes: `Rig` hitbox names (Task 7); `Registry` (Task 2).
- Produces:
  - `class_name MoveData extends Resource`:
    - `enum Kind { ATTACK, DODGE, OTHER }`;
    - `@export var id: StringName`, `@export var kind: Kind`, `@export var clip: StringName`;
    - `@export var root_motion := true`;
    - `@export var stamina_cost := 0.0`, `@export var posture_damage := 0.0`, `@export var poise_damage := 0.0`;
    - `@export var blend_in := 0.05`, `@export var blend_out := 0.15`.
  - `class_name Marks extends RefCounted`. Marks are keys on a method track at path `Marks`; the method is the kind and `args[0]` is a Dictionary.
    - `const KINDS := [&"hitbox_on", &"hitbox_off", &"iframes_on", &"iframes_off", &"hyperarmour_on", &"hyperarmour_off", &"cancel_open", &"cancel_close", &"recovery", &"fx", &"sfx", &"shake", &"hitstop"]`
    - `static func read(anim: Animation) -> Array[Dictionary]` returns `{time, kind, args}` sorted by time.
    - `static func write(anim: Animation, marks: Array) -> void` replaces the track.
    - `static func between(marks: Array, t0: float, t1: float) -> Array` returns marks with `t0 < time <= t1`.
    - `static func frame_of(t: float) -> int` is `roundi(t * 60)`, and `static func time_of(f: int) -> float` is `f / 60.0`.
  - Mark arguments:
    - `hitbox_on`/`hitbox_off`: `{id}` (plus `profile` from F1);
    - `cancel_open`: `{into: {action: move_id}}`. A new `cancel_open` replaces the open window, and windows don't stack. A window closes at `cancel_close` or at the clip's end;
    - `fx` and `sfx`: `{name}`;
    - `shake`: `{strength}`;
    - `hitstop`: `{frames}`, which must be 3–6.
  - `class_name InputBuffer extends RefCounted`:
    - `const WINDOW := 9`;
    - `func push(action: StringName, frame: int) -> void`;
    - `func consume(allowed: Array, frame: int) -> StringName` returns the newest press in `allowed` with an age (`frame − press frame`) of 0–9, removes it, and returns `&""` when there is none;
    - `func clear() -> void`.
  - `class_name LocomotionTuning extends Resource`:
    - `walk_speed`, `jog_speed`, `sprint_speed`: the defaults in `abarax_locomotion.tres` are the `ground_speed` metadata of `walk`, `jog` and `sprint`, rounded to 0.1;
    - `accel := 18.0`, `decel := 24.0`, `turn_rate_deg := 720.0`, `walk_threshold := 0.5`.
  - `class_name ActorDef extends Resource`:
    - `@export var id: StringName`, `@export var rig_scene: PackedScene`;
    - `@export var moveset: Dictionary`: for Abarax, `{&"palm": &"palm_jab", &"dodge": &"dodge_roll"}`;
    - `@export var locomotion: LocomotionTuning`;
    - `@export var max_hp := 100.0`, `max_stamina := 100.0`, `max_posture := 100.0`, `poise := 10.0`;
    - `@export var required_clips := PackedStringArray(["idle", "walk", "jog", "sprint"])`.
  - `class_name ClipChecker extends RefCounted`:
    - `func check_move(move: MoveData, anim: Animation, hitbox_ids: PackedStringArray, move_ids: PackedStringArray) -> PackedStringArray`;
    - `func check_actor(def: ActorDef) -> PackedStringArray`;
    - `func check_all() -> PackedStringArray`;
    - its rules:
      - an ATTACK has, for each id, `hitbox_on` before `hitbox_off`, at least one `cancel_open`, and exactly one `recovery` at or after the last `hitbox_off`;
      - a DODGE has `iframes_on` before `iframes_off`;
      - every move has at least one `sfx` and one `fx`;
      - every mark lies within [0, length];
      - `cancel_open.into` names existing move ids;
      - hitbox ids exist in the rig;
      - hitstop frames are 3–6;
      - on a stepped clip, every mark is on the `1/step_fps` grid (±1e-3);
      - each required clip exists and is not a T-pose (every bone's rotation within 1° of rest for the whole clip).
  - `tools/clip_check.gd` (CLI) prints each problem as `clip_check: <id>: <problem>` and exits 1. Otherwise it prints `clip_check: N moves, M actors OK` and exits 0.
  - `tools/anim/set_marks.gd -- <clip.tres> <marks.json>`, where the JSON is `[{"frame": f, "kind": k, "args": {...}}]`, writes the marks with `Marks.write`.

  F0 marks, in frames at 60 Hz. These are the first values; check them against the contact sheet, move a hitbox to the frame where that hand is at full extension, and record a ruling:

  | Move (length) | Marks |
  |---|---|
  | `palm_jab` (35 f, stepped 12) | `sfx{name:palm_whoosh}` f5 · `hitbox_on{id:<lead hand: palm_l or palm_r from the sheet>}` f10 · `fx{name:palm_trail}` f10 · `hitstop{frames:3}` f10 · `hitbox_off` f15 · `cancel_open{into:{palm:palm_cross}}` f15 · `recovery` f20 · `cancel_open{into:{palm:palm_cross, dodge:dodge_roll}}` f20 |
  | `palm_cross` (40 f, stepped 12) | `sfx{palm_whoosh}` f5 · `hitbox_on{id:<rear hand>}` f15 · `fx{palm_trail}` f15 · `hitstop{frames:4}` f15 · `hitbox_off` f20 · `cancel_open{into:{palm:palm_jab}}` f20 · `recovery` f25 · `cancel_open{into:{palm:palm_jab, dodge:dodge_roll}}` f25 |
  | `dodge_roll` (30 f, smooth) | `sfx{roll_cloth}` f0 · `iframes_on` f3 · `fx{roll_dust}` f14 · `sfx{roll_land}` f14 · `iframes_off` f16 · `recovery` f20 · `cancel_open{into:{palm:palm_jab, dodge:dodge_roll}}` f22 |

  `palm_jab` and `palm_cross` are ATTACK, and `dodge_roll` is DODGE. The 13 invulnerable frames are [3, 16).

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_input_buffer.gd
func test_press_within_nine_frames_is_consumed() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100)
	assert_eq(b.consume([&"palm"], 109), &"palm")
func test_press_older_than_nine_frames_expires() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100)
	assert_eq(b.consume([&"palm"], 110), &"")
func test_newest_allowed_wins_and_is_removed() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100); b.push(&"dodge", 103)
	assert_eq(b.consume([&"palm", &"dodge"], 105), &"dodge"); assert_eq(b.consume([&"dodge"], 105), &"")
	assert_eq(b.consume([&"palm"], 105), &"palm")
# test_marks.gd
func test_write_then_read_round_trips_sorted() -> void:
func test_between_is_half_open_and_includes_time_zero_from_negative() -> void:
	var m := [{"time": 0.0, "kind": &"sfx", "args": {}}, {"time": 10 / 60.0, "kind": &"hitbox_on", "args": {}}]
	assert_eq(Marks.between(m, -1.0, 0.0).size(), 1); assert_eq(Marks.between(m, 0.0, 10 / 60.0).size(), 1)
# test_clip_checker.gd: fixture moves and animations built in code with Marks.write
func test_valid_attack_has_no_problems() -> void:
func test_hitbox_never_turned_off_is_reported() -> void:      # message contains "never off"
func test_dodge_without_iframes_is_reported() -> void:        # "iframes"
func test_move_without_sfx_is_reported() -> void:             # "sfx"
func test_mark_off_the_step_grid_is_reported() -> void:       # stepped 12, a mark at f12: "12 fps step grid"
func test_cancel_into_unknown_move_is_reported() -> void:     # "unknown move"
func test_hitstop_out_of_range_is_reported() -> void:         # frames 8: "hitstop"
func test_t_pose_required_clip_is_reported() -> void:         # the library's t_pose as a required clip: "T-pose"
func test_real_data_passes() -> void:
	assert_eq(ClipChecker.new().check_all(), PackedStringArray())
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/moves`.**
  Expected: FAIL because the classes are missing.

- [ ] **Step 3: Implement the classes as in Interfaces, and write the data.**
  Write the data files and the marks (with `set_marks.gd`, from JSON in the workspace). Re-render the contact sheet to check the hitbox frames.

- [ ] **Step 4: Run `tools/test.sh` and `tools/godot.sh -s res://tools/clip_check.gd`.**
  Expected: every test passes, and the checker prints `clip_check: 3 moves, 1 actors OK`.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Moves: MoveData, marks on the Marks track, 9-frame input buffer, clip checker; jab, cross, roll".

### Task 9: Actor, brains, locomotion and the move runner

**Files:**
- Create: `all-divine/actors/actor.gd`, `actors/actor.tscn`, `actors/intent.gd`, `actors/brain.gd`, `actors/player_brain.gd`, `actors/script_brain.gd`, `actors/locomotion.gd`, `actors/stats.gd`, `moves/move_runner.gd`
- Create: `all-divine/tests/support/test_arena.gd`
- Test: `all-divine/tests/actors/test_locomotion.gd`, `test_actor.gd`, `tests/moves/test_move_runner.gd`, `tests/feel/test_press_to_motion.gd`

**Interfaces:**
- Consumes: `Rig` (Task 7); `MoveData`, `Marks`, `InputBuffer`, `ActorDef` and `LocomotionTuning` (Task 8); `Registry` and `Inputs` (Task 2).
- Produces:
  - `class_name Intent extends RefCounted`:
    - `var move := Vector2.ZERO`, in world XZ with length 0–1;
    - `var pressed: Array[StringName]`, `var held: Array[StringName]`;
    - `var face_target: Variant = null`, a Vector3 or null;
    - `var look_target: Variant = null`, a Vector3 or null.
  - `class_name Brain extends RefCounted`: `func think(actor: Actor, delta: float) -> Intent` returns an empty Intent.
  - `class_name PlayerBrain extends Brain`:
    - `var view_yaw := 0.0`;
    - `Inputs.move_vector()` (screen x, y with up as −y) is rotated by `view_yaw` into world `(x, z)`;
    - `pressed` comes from `Inputs.pressed_this_frame()`, and `held` from `Inputs.held` over `Inputs.GAMEPLAY`.
  - `class_name ScriptBrain extends Brain`:
    - `func _init(steps: Array)`, where each step is `{frames: int, move := Vector2.ZERO, press := [], hold := [], face_target := null, look_target := null}`;
    - presses fire on a step's first frame only;
    - `func done() -> bool`.
  - `class_name Locomotion extends RefCounted`:
    - `var tuning: LocomotionTuning`, `var speed := 0.0`, `var facing_yaw := 0.0` (yaw 0 faces +Z), `var sprinting := false`;
    - `func target_speed(m: float, sprint: bool) -> float`: `sprint_speed` when sprinting and `m > walk_threshold`; `jog_speed` when `m > walk_threshold`; otherwise `walk_speed × m / walk_threshold`;
    - `func tick(move: Vector2, sprint: bool, delta: float) -> Vector3`:
      - the velocity's direction is the input direction, at once;
      - its magnitude ramps up by `accel` and down by `decel`;
      - with no input it slows along the last direction;
      - `facing_yaw` turns toward the move direction at `turn_rate_deg`;
    - `static func yaw_of(dir: Vector2) -> float` is `atan2(dir.x, dir.y)`.
  - `class_name Stats extends RefCounted`: `hp`, `stamina`, `posture`, `poise` and `resistances: Dictionary`, with `static func from_def(def: ActorDef) -> Stats`. Data only in F0.
  - `class_name MoveRunner extends Node`:
    - `var actor: Actor`, set by `Actor._ready`; the runner reads `actor.buffer`, `actor.def`, `actor.frame` and `actor.rig`;
    - signals `move_started(move: MoveData)`, `move_ended(move: MoveData, cancelled: bool)` and `mark(kind: StringName, args: Dictionary)`;
    - state: `var current: MoveData`, `var time := 0.0`, `var iframes := false`, `var hyperarmour := false`, `var window := {}`, `var in_recovery := false`;
    - `func start(move: MoveData) -> void` fires the marks at time 0 on the start tick;
    - `func tick(intent: Intent, delta: float) -> Vector3`, in this order:
      1. advance `time`;
      2. handle each mark in `Marks.between(prev, time)` in order, toggling hitboxes and flags and emitting `mark` for fx, sfx, shake and hitstop;
      3. if a window is open, `buffer.consume(window.keys())` and start that move in the same tick;
      4. at the clip's end, end the move;
      5. if there is no move, `buffer.consume(def.moveset.keys())` and start the move.
      It returns the root-motion velocity: the root track sampled at the previous and current time, the horizontal part, turned into the actor's facing, divided by delta.
    - `func busy() -> bool`.
    - Moves are resolved with `Registry.fetch(&"moves", id)`.
    - A dodge snaps the facing to the stick direction when the stick is deflected.
  - `class_name Actor extends CharacterBody3D` (`actor.tscn`: a capsule of radius 0.35 and height 1.8, on layer `actor` with mask `world`, plus a child `MoveRunner`):
    - `@export var def: ActorDef`;
    - `var brain: Brain`, `var stats: Stats`, `var buffer := InputBuffer.new()`, `var frame := 0`, `var locomotion: Locomotion`, `var rig: Rig`, `@onready var runner: MoveRunner`;
    - `signal brain_changed(brain: Brain)`;
    - `func set_brain(b: Brain) -> void`, `func facing() -> Vector3` (`basis.z`), `func is_invulnerable() -> bool`.
    - `_ready` instantiates `def.rig_scene` as the child `Rig`.
    - `_physics_process`, in this order:
      1. `frame += 1`;
      2. get the intent;
      3. push the presses into the buffer;
      4. `runner.tick`;
      5. run locomotion when no move is busy, with sprint meaning dodge is held and the last dodge has ended;
      6. `move_and_slide`;
      7. turn toward `facing_yaw`;
      8. `rig.set_locomotion(speed, false)`, then `rig.tick(delta)`.
  - `class_name TestArena`:
    - `static func make(t: TestCase) -> Node3D` builds a 40×40 m floor on layers `world` and `ik_surface`, with a `DirectionalLight3D`;
    - `static func spawn(arena: Node3D, def: ActorDef, brain: Brain, at := Vector3.ZERO) -> Actor`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_locomotion.gd (pure; tuning walk 1.6, jog 4.0, sprint 6.0, accel 18, decel 24, turn 720)
func test_reaches_jog_in_fourteen_frames() -> void:   # full stick: speed < 3.99 at frame 13 and ≥ 3.99 at frame 14
func test_stops_in_about_ten_frames() -> void:              # from jog, release: speed 0 at frame 10 ±1
func test_light_tilt_walks() -> void:                       # m = 0.25 (after shaping): target 0.8 m/s
func test_turns_half_circle_in_fifteen_frames() -> void:    # facing goes from 0 to PI in 15 ±1 frames
func test_sprint_only_when_held_and_moving() -> void:
# test_actor.gd
func test_brain_swap_emits() -> void:
func test_script_brain_walks_and_faces_east() -> void:
	# 60 frames with move (1, 0): x ≥ 1.5 m, and facing_yaw within 0.05 of PI/2.
func test_drift_does_not_move_actor() -> void:
	# A PlayerBrain-like brain feeding Inputs.shape_stick(Vector2(0.15, 0)) for 60 frames: moved < 0.01 m, facing unchanged.
# test_move_runner.gd (an arena, Abarax and a ScriptBrain)
func test_palm_when_idle_starts_jab_the_same_frame() -> void:   # press at actor frame 11: move_started frame == 11
func test_jab_hitbox_active_frames_10_to_14() -> void:          # move frames where the lead hand's hitbox is active == range(10, 15)
func test_roll_iframes_are_13_frames() -> void:                 # move frames with is_invulnerable() == range(3, 16)
func test_buffered_palm_comes_out_on_window_open() -> void:     # palm at jab f11: palm_cross starts at jab f15
func test_buffered_dodge_comes_out_on_recovery() -> void:       # dodge at jab f14: dodge_roll at jab f20
func test_too_early_dodge_expires() -> void:                    # dodge at jab f10: no roll; jab runs to f35
func test_large_delta_fires_every_mark_once() -> void:
	# Call runner.start(jab), then runner.tick(intent, 0.1) twice: the mark signals arrive in clip order, and hitbox_on and hitbox_off each arrive exactly once.
func test_roll_root_motion_matches_clip() -> void:              # displacement along facing equals the clip root displacement ±0.02 m
func test_roll_snaps_to_stick_direction() -> void:
func test_sprint_after_held_roll() -> void:                     # hold dodge plus stick through the roll: speed reaches sprint_speed; release: jog
# tests/feel/test_press_to_motion.gd
func test_jab_moves_the_hand_within_two_frames() -> void:
	# Run twice from the same start, once with palm pressed at frame 11 and once without.
	# The lead hand's global position differs by ≥ 0.01 m at frame 13 at the latest.
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/actors`, then `--filter=tests/moves`, then `--filter=tests/feel`.**
  Expected: FAIL because the classes are missing.

- [ ] **Step 3: Implement the classes as in Interfaces.**
  Set `abarax_locomotion.tres` to the measured ground speeds.

- [ ] **Step 4: Run `tools/test.sh` and `tools/godot.sh -s res://tools/clip_check.gd`.**
  Expected: all pass. If press-to-motion fails, the fix belongs in the rig or the move (blend or stepping), never in the test; record a ruling.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Actor, brains (player, script), locomotion, move runner reading marks; buffer and cancel rules; press-to-motion ≤ 2 frames".

### Task 10: The character look: palettes and the toon shader

**Files:**
- Create: `all-divine/render/palette.gd`, `render/shaders/toon_character.gdshader`, `data/palettes/abarax.tres`
- Modify: `all-divine/actors/actor_def.gd` (adding `@export var palette: Palette`), `actors/rig.gd` (adding `apply_palette`), `actors/actor.gd` (calling it in `_ready`), `tools/sheets/contact_sheet.gd` (applying the def's palette), `data/actors/abarax.tres`
- Test: `all-divine/tests/look/test_palette.gd`, `tests/render/test_toon_palette.gd`

**Interfaces:**
- Produces:
  - `class_name Palette extends Resource`:
    - `@export var id: StringName`;
    - `@export var slot_names: PackedStringArray` (16);
    - `@export var tones: PackedColorArray`: 64 colours, at index `slot × 4 + t`, where t is 0 highlight, 1 base, 2 shade, 3 deep;
    - `func tone(slot: int, t: int) -> Color`;
    - `static func ramp_from_base(base: Color) -> PackedColorArray`, worked in HSV, where "toward" means along the shorter arc of hue by at most that many degrees:
      - highlight: hue toward 60° by ≤ 8°, s × 0.85, v = min(1, v × 1.18);
      - base: unchanged;
      - shade: hue toward 240° by ≤ 12°, s = min(1, s × 1.1), v × 0.72;
      - deep: hue toward 240° by ≤ 20°, s = min(1, s × 1.2), v × 0.48;
    - `func with_dye(slot: int, base: Color) -> Palette` returns a copy with that slot's ramp replaced;
    - `func to_texture() -> ImageTexture`, a 4×16 RGBA8 image with x as the tone and y as the slot.
  - `abarax.tres`: slots 0–8 come from `ramp_from_base` of skin `#c98a5a`, hair `#4a2e1e`, eyes `#5a2e14`, main `#efe6d6`, sec `#3a4a7a`, pants `#3a3a4a`, boots `#5a3a2a`, rose `#e8607e` and gold `#e8c170`. Slots 9–15 are `#ff00ff` in every tone, so a wrong slot shows.
  - `toon_character.gdshader` (spatial; `render_mode ambient_light_disabled, specular_disabled`):
    - uniforms: `palette` (`source_color, filter_nearest`) and `ramp = vec3(0.1, 0.4, 0.85)`;
    - `slot = int(UV2.x × 16)`;
    - `fragment`: `ALBEDO = tone(slot, 1)` and `EMISSION = tone(slot, 3)`;
    - `light()`:
      1. `i = clamp(dot(NORMAL, LIGHT), 0, 1) × ATTENUATION`;
      2. the tone is 3 when `i < ramp.x`, 2 when `i < ramp.y`, 1 when `i < ramp.z`, and 0 otherwise;
      3. `DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, (tone(slot, t) − tone(slot, 3)) / max(ALBEDO, vec3(0.001)) × LIGHT_COLOR / PI)`.
      Under one white light of energy 1, every pixel is exactly a palette tone.
  - `func apply_palette(p: Palette) -> void` on `Rig` sets a shared `ShaderMaterial` as `material_override` on every `MeshInstance3D` under `Model`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_palette.gd
func test_ramp_keeps_base_and_darkens_shades() -> void:
	var r := Palette.ramp_from_base(Color("#c98a5a"))
	assert_eq(r[1], Color("#c98a5a"))
	assert_near(r[2].v, Color("#c98a5a").v * 0.72, 0.005); assert_near(r[3].v, Color("#c98a5a").v * 0.48, 0.005)
	assert_true(_hue_dist(r[2].h, 240.0 / 360) < _hue_dist(Color("#c98a5a").h, 240.0 / 360))
func test_texture_layout() -> void:   # to_texture().get_image().get_pixel(1, 3) == tone(3, 1)
func test_dye_copies() -> void:       # with_dye(7, Color.RED) changes slot 7 and leaves the original alone
func test_abarax_palette_slots() -> void:   # the base tones of slots 0–8 equal the hex table; slots 9–15 are magenta
```

```gdscript
# tests/render/test_toon_palette.gd. Environment: black background, no ambient, tonemap linear, exposure 1, no post.
func test_sphere_pixels_are_palette_tones() -> void:
	# A sphere mesh with UV2.x = 3.5 / 16, under a white DirectionalLight3D of energy 1 with shadows, filling the view.
	# Every non-black pixel is within 2/255 per channel of one of slot 3's four tones, and at least 3 distinct tones appear.
func test_abarax_pixels_are_his_palette() -> void:
	# The Abarax rig in idle, lit the same way: every non-background pixel is within 2/255 of a tone of slots 0–8.
```

- [ ] **Step 2: Run `tools/test.sh --filter=test_palette` and `tools/test.sh --render --filter=test_toon_palette`.**
  Expected: FAIL because `Palette` is missing.

- [ ] **Step 3: Implement `palette.gd`, `toon_character.gdshader` and the palette data, and wire up the rig, actor and sheet.**
  If the colours come out wrong in the Compatibility renderer (sRGB versus linear), fix it in the shader so the render test passes, and record a ruling.

- [ ] **Step 4: Run both commands again, then the full `tools/test.sh`, and regenerate the contact sheet.**
  Expected: PASS. In the sheet, Abarax shows in his own colours: cream shirt, blue, rose scarf.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Character look: palette resource (ramps, dyes), toon shader held to the palette".

### Task 11: The screen look: outlines, tilt-shift, fog, bloom, grading, vignette

**Files:**
- Create: `all-divine/render/shaders/screen_post.gdshader`, `render/shaders/screen_final.gdshader`, `render/shaders/toon_world.gdshader`, `render/render_settings.gd`, `render/grade_profile.gd`, `data/render/default_settings.tres`, `data/render/grades/courtyard_dusk.tres`
- Modify: `all-divine/render/pixel_stage.gd` (adding the final material and `apply_settings`), `render/camera_rig.gd` (adding the post quad)
- Test: `all-divine/tests/look/test_render_settings.gd`, `tests/render/test_screen_post.gd`, `tests/render/golden/` (written by `--update-golden`)

**Interfaces:**
- Consumes: `PixelStage` and `CameraRig` (Task 3).
- Produces:
  - `class_name RenderSettings extends Resource`. Each effect can be turned down:
    - `outline := 1.0`;
    - `dof_strength := 1.0`, `focus_band := 2.0`;
    - `bloom_strength := 0.35`, `bloom_threshold := 0.8`;
    - `fog_strength := 0.5`;
    - `grade_strength := 1.0`;
    - `vignette_strength := 0.35`;
    - `func off() -> RenderSettings` returns a copy with every strength at 0.
  - `class_name GradeProfile extends Resource`:
    - `lift := Color(0,0,0)`, `gamma := Color(1,1,1)`, `gain := Color(1,1,1)`, `saturation := 1.0`, `tint := Color(1,1,1)`;
    - `fog_color := Color("#c9a4a0")`, `fog_density := 0.04`, `fog_height := 1.5`.
    `courtyard_dusk.tres` is warm and rose: gain `#fff0e0`, lift `#0a0612`, saturation 1.05.
  - `PixelStage.apply_settings(s: RenderSettings, g: GradeProfile) -> void`.
  - `CameraRig` builds a child `PostQuad` (a 2×2 `QuadMesh` with `flip_faces`, `extra_cull_margin = 16384`, in group `post_quad`) using `screen_post`. The focus distance is the camera's distance to its target.
  - `screen_post` (spatial: unshaded, `depth_draw_never`, `depth_test_disabled`, `fog_disabled`; `POSITION = vec4(VERTEX.xy, 1, 1)`), using linear depth from `hint_depth_texture` through `INV_PROJECTION_MATRIX`:
    - **DOF:** `coc = smoothstep(band/2, band/2 + 4.0, |depth − focus|) × dof_strength`, then `col = mix(sharp, 12-tap disc blur of radius 2 px, coc)`.
    - **Outline:** a silhouette where a 4-neighbour is more than 0.25 m deeper than the centre. Only the nearer pixel draws it, in centre colour × 0.35. A crease is where normals rebuilt from neighbour depths differ by more than 40°, at a depth gap under 0.25 m, in colour × 0.7. The far plane is never outlined. `col = mix(col, line, outline × (1 − coc))`.
    - **Fog:** `f = fog_strength × (1 − exp(−density × max(depth − 8, 0))) × exp(−max(world_y − fog_height, 0) × 0.5)`, where `world_y` comes from `INV_VIEW_MATRIX`; `col = mix(col, fog_color, f)`.
  - `screen_final` (`canvas_item`; it samples the 642×362 texture at texel centres, so the pixels stay crisp):
    - **Bloom:** `c += bloom_strength × Σ w·max(s − threshold, 0)` over a 3×3 of taps 2 texels apart (weights 0.25 centre, 0.125 edges, 0.0625 corners);
    - **Grade:** `c = pow(max(c × gain + lift × (1 − c), 0), 1 / gamma)`, then saturation around the luma, × tint, mixed by `grade_strength`;
    - **Vignette:** `c *= 1 − vignette_strength × smoothstep(0.45, 0.85, length(uv − 0.5) × 1.414)`.
  - `toon_world.gdshader` (spatial):
    - uniforms `albedo_tex` (`filter_nearest`), `world_uv := false` and `texels_per_metre := 32.0`;
    - with `world_uv`, the UV is `world XZ × texels_per_metre / textureSize`;
    - `light()` steps `i` at 0.15 and 0.55 to the factors 0.35, 0.7 and 1.0, times `LIGHT_COLOR / PI`;
    - ambient is kept.
  - Volumetric fog is the depth-and-height fog above in both renderers, not Forward+'s own volumetric fog, so the two renderers match.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_render_settings.gd
func test_off_zeroes_every_strength() -> void:
# tests/render/test_screen_post.gd (a box over a plane, a far box, a CameraRig over the target, 640×360 internal)
func test_all_off_equals_raw() -> void:          # with settings.off(), the output matches a render with no post quad and no final material, ±1/255
func test_outline_rings_the_silhouette() -> void: # ≥ 90% of the box-edge pixels are darker than raw × 0.5; flat-face pixels are unchanged
func test_dof_keeps_focus_sharp_blurs_far() -> void:
func test_fog_shifts_far_pixels_toward_fog_color() -> void:
func test_vignette_darkens_corners() -> void:
func test_forward_plus_matches_compatibility() -> void:
	# Only when the rendering method is forward_plus; otherwise it returns at once.
	# Compare with golden/post_scene_compat.png (written by `--render --update-golden`): mean |diff| ≤ 3/255, and 99% of pixels within 8/255.
```

- [ ] **Step 2: Run `tools/test.sh --render --filter=test_screen_post`.**
  Expected: FAIL because the shaders are missing.

- [ ] **Step 3: Implement the shaders, the settings and their wiring.** Write the golden file with `tools/test.sh --render --update-golden --filter=test_screen_post`.

- [ ] **Step 4: Run `tools/test.sh` and `tools/test.sh --render`.**
  Expected: all pass. The Forward+ parity test is skipped here and runs in CI (Task 16).

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Screen look: depth outlines, tilt-shift DOF, depth+height fog, bloom, grading, vignette; renderer-agnostic".

### Task 12: Liveliness I: 8-way locomotion, breathing, hit reactions

**Files:**
- Create: `all-divine/actors/liveliness/orientation_warp.gd`, `liveliness/breathing.gd`, `liveliness/hit_react.gd`
- Modify: `all-divine/actors/abarax/abarax_rig.tscn` (the three modifiers as children of `Model/…/Skeleton3D`, in this order: warp, breathing, hit react), `actors/rig.gd`, `actors/actor.gd`
- Test: `all-divine/tests/actors/test_orientation_warp.gd`, `test_breathing.gd`, `test_hit_react.gd`

**Interfaces:**
- Consumes: `Rig` and `Actor` (Tasks 7 and 9).
- Produces:
  - `class_name OrientationWarp extends SkeletonModifier3D`:
    - `@export var max_angle_deg := 70.0`, `var angle := 0.0` (move direction relative to facing, in radians);
    - `static func solve(angle: float, max_angle: float) -> Dictionary` returns `{warp: float, backward: bool}`. Up to 110° from facing, `warp = clamp(angle, ±max)` and `backward = false`. Beyond that, `backward = true` and `warp = clamp(wrap(angle − PI), ±max)`;
    - it turns `pelvis` by `warp` about up, and `spine_01`, `spine_02` and `spine_03` by `−warp × (0.4, 0.3, 0.3)`, so the chest stays on the facing.
  - `Rig.set_strafe(angle: float) -> bool` sets the warp from `solve` and returns `backward`.
  - In `Actor`: with `intent.face_target` set, `facing_yaw` turns toward the target at `turn_rate`, and the strafe angle is the move yaw minus the facing yaw. Without it the angle is 0. Each tick does `var back := rig.set_strafe(angle)`, then `rig.set_locomotion(speed, back)`. `set_locomotion` with `backward = true` sets `loco_scale` to −1.
  - `class_name Breathing extends SkeletonModifier3D`:
    - `@export var idle_rate_hz := 0.25`, `max_rate_hz := 0.6`, `amplitude_deg := 1.5`;
    - `var exertion := 0.0`, which decays by `delta / 6.0`;
    - `static func rate(exertion: float) -> float` is the lerp from the idle to the maximum rate;
    - `static func step(phase: float, exertion: float, delta: float) -> float` returns the new phase;
    - it pitches `spine_02` by `amp × sin(phase)` and `spine_03` by 0.6 of that, and lifts the clavicles by 0.5 of it.
  - `Actor` sets `exertion = 1` while sprinting.
  - `class_name HitReact extends SkeletonModifier3D`:
    - `func react(dir_world: Vector3, strength: float) -> void` adds a tilt velocity of `dir_local.xz × strength × 6 rad/s`, tilting away from the hit;
    - a spring-damper with stiffness 180 and damping 14;
    - the tilt is shared as `spine_01` 0.3, `spine_02` 0.3, `spine_03` 0.2, `neck_01` 0.1 and `Head` 0.1;
    - `Rig.hit_react(dir: Vector3, strength: float)` forwards to it.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_orientation_warp.gd
func test_solve_table() -> void:
	var m := deg_to_rad(70.0)
	assert_near(OrientationWarp.solve(0.0, m).warp, 0.0, 1e-6)
	assert_near(OrientationWarp.solve(deg_to_rad(45), m).warp, deg_to_rad(45), 1e-6)
	assert_near(OrientationWarp.solve(deg_to_rad(90), m).warp, m, 1e-6)
	var b := OrientationWarp.solve(PI, m); assert_true(b.backward); assert_near(b.warp, 0.0, 1e-6)
	var c := OrientationWarp.solve(deg_to_rad(150), m); assert_true(c.backward); assert_near(c.warp, deg_to_rad(-30), 1e-5)
func test_pose_turns_hips_and_keeps_chest() -> void:
	# Rig in idle, set_strafe(45°), a few ticks: the pelvis forward yaw relative to the rig is 45° ± 2°, and spine_03's is 0° ± 3°.
func test_backward_plays_locomotion_in_reverse() -> void:   # set_strafe(PI) returns true; after set_locomotion(jog, true), the loco_scale parameter is −1
# test_breathing.gd
func test_rate_range() -> void:   # rate(0) == 0.25, rate(1) == 0.6
func test_idle_period_is_four_seconds() -> void:   # step 600 ticks at exertion 0; the zero crossings of sin give a period of 4.0 ± 0.1 s
func test_exertion_decays_over_six_seconds() -> void:
# test_hit_react.gd
func test_front_hit_tilts_back_then_settles() -> void:
	# react(-facing, 1): spine_02 pitches backward and peaks within 0.12 s; it is under 5% of the peak by 0.6 s.
func test_left_hit_tilts_right() -> void:
func test_zero_direction_is_safe() -> void:   # react(Vector3.ZERO, 1): no NaN in any bone pose
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/actors`.**
  Expected: the three new files FAIL because the classes are missing.

- [ ] **Step 3: Implement the modifiers in `_process_modification_with_delta`, and wire them through `Rig` and `Actor`.**

- [ ] **Step 4: Run `tools/test.sh`.**
  Expected: all pass.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Liveliness I: 8-way locomotion by orientation warping, breathing, procedural hit reactions".

### Task 13: Liveliness II: foot IK, look-at and the scarf

**Files:**
- Create: `all-divine/actors/liveliness/foot_planter.gd`, `tests/support/terrain.gd`
- Modify: `all-divine/actors/abarax/abarax_rig.tscn`, adding under the skeleton, after Task 12's modifiers and in this order:
  1. `FootPlanter`;
  2. `TwoBoneIK3D` ×2 (`thigh_*` → `calf_*` → `foot_*`, with targets `IKTarget_l`/`_r` and poles ahead of the knees);
  3. `LookAtModifier3D` ×2 (`neck_01` at influence 0.4, `Head` at 1.0);
  4. `SpringBoneSimulator3D` (`scarf_01` → `scarf_04`, end extended, with a collision capsule on `spine_03` of radius 0.16).
- Modify: `all-divine/actors/rig.gd`, `actors/actor.gd`
- Test: `all-divine/tests/actors/test_foot_ik.gd`, `test_look_at.gd`, `test_scarf.gd`

**Interfaces:**
- Consumes: `Actor` and `Rig` (Tasks 9 and 12); physics layer `ik_surface`.
- Produces:
  - `class_name FootPlanter extends SkeletonModifier3D`:
    - `var ground := {&"foot_l": null, &"foot_r": null}`; each value is `{position: Vector3, normal: Vector3}` or null;
    - `@export var max_drop := 0.45`, `@export var blend_speed := 12.0`, `@export var ankle_height := 0.08`;
    - each foot's offset is `ground.y + ankle_height − animated foot y`;
    - the pelvis drops by `min(offsets, 0)`, clamped to `−max_drop`;
    - each IK target, in world space, is the animated foot position plus that foot's offset, which puts it on the ground point. The pelvis drop is what lets the lower foot reach it;
    - a missing hit blends that foot's offset to 0;
    - every offset is smoothed with `blend_speed`;
    - it is turned off while a root-motion move is airborne. None exists in F0, so the flag sits on `Rig`.
  - In `Actor._physics_process`, for each foot, cast a ray from the animated foot position + 0.5 m up, 1.0 m down, on `ik_surface`, and give the results to `rig.set_foot_ground(foot: StringName, hit: Variant)`.
  - `Rig.look_at_point(target: Variant) -> void` sets both modifiers' target node, a `Marker3D` under `Rig`, or blends them off when null. The modifiers use:
    - an angle limit of 70° yaw and 35° pitch;
    - `duration` 0.3, with `transition_type` SINE and `ease_type` OUT.
  - The look target in `Actor` is `intent.look_target`; failing that, the nearest node in group `poi` within 6 m and within ±100° of facing; failing that, none.
  - `TestTerrain`:
    - `static func slope(parent: Node3D, deg: float) -> void`;
    - `static func stairs(parent: Node3D, rise: float, run: float, count: int) -> void`, a visible step mesh on `ik_surface` plus a ramp on `world`;
    - `static func ledge(parent: Node3D) -> void`, a platform that ends at x = 0.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_foot_ik.gd
func test_flat_ground_leaves_pelvis_alone() -> void:     # pelvis offset 0 ± 0.01 after 1 s idle
func test_feet_on_a_twenty_degree_slope() -> void:       # after 1 s idle across the slope, each foot bone is within 0.04 m of the surface below it
func test_feet_on_stairs() -> void:                      # rise 0.2, run 0.35, straddling two steps: same tolerance
func test_foot_ik_ray_miss_fades_without_nan() -> void:
	# Stand with one foot past the ledge: that foot's offset falls to |x| < 0.01 within 0.3 s, and no bone pose has NaN at any frame.
# test_look_at.gd
func test_head_turns_to_target_left() -> void:           # a target 45° left at head height: after 0.6 s, the Head forward yaw is 45° ± 6°
func test_target_behind_is_limited() -> void:            # a target behind: |head yaw| ≤ 72°
func test_cleared_target_returns_head() -> void:         # back to the animated yaw ± 3° within 0.6 s
func test_actor_picks_nearest_poi() -> void:
# test_scarf.gd
func test_scarf_trails_when_running_and_settles() -> void:
	# Jog +X for 1 s: (scarf_04 tip − neck)·forward is less than its rest value − 0.05.
	# Stop and wait 2 s: the tip is within 0.05 m of its rest offset, and no frame has NaN.
func test_scarf_stays_out_of_the_torso() -> void:        # every frame of the run: the tip is ≥ 0.14 m from the spine_02–spine_03 segment
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/actors`.**
  Expected: the three new files FAIL.

- [ ] **Step 3: Implement `FootPlanter`, add the engine modifiers to the rig scene, and add the probes and the look-target choice to `Actor`.**

- [ ] **Step 4: Run `tools/test.sh`, then regenerate the contact sheet.**
  Expected: all pass, and the sheet still reads.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Liveliness II: foot IK on slopes and stairs, head and neck look-at, spring-bone scarf".

### Task 14: The courtyard and the main scene

**Files:**
- Create: `all-divine/world/region.gd`, `world/courtyard/layout.txt`, `world/courtyard/courtyard.tscn`, `tools/world/build_courtyard.gd`, `tools/art/make_textures.gd`, `assets/env/textures/flagstone.png`
- Create: `all-divine/main/main.gd`, `main/main.tscn`, `main/debug_overlay.gd`
- Modify: `all-divine/project.godot` (`run/main_scene="res://main/main.tscn"`), `ASSETS.md` (the row `assets/env/textures/ | ours | generated by tools/art/make_textures.gd`)
- Test: `all-divine/tests/world/test_courtyard.gd`, `tests/main/test_main.gd`, `tests/perf/test_frame_budget.gd`, `tests/render/test_courtyard_shot.gd`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `class_name Region extends Node3D`:
    - `@export var grade: GradeProfile`;
    - `func spawn() -> Transform3D`, from the child `Marker3D` named `Spawn`.
  - `make_textures.gd` writes `flagstone.png`, deterministically:
    - 64×64 px, a 2 m tile at 32 texels per metre;
    - a seeded RNG (seed 7);
    - four stone greys warmed toward rose, plus a darker mortar.
  - `build_courtyard.gd` turns `layout.txt` into `courtyard.tscn`.
    - The `.tscn` is the source afterwards; `STATE.md` says so.
    - Kenney pieces are scaled ×2.5 (a 2.5 m tile), with `toon_world` and the colormap.
    - The floor is a `toon_world` box with `world_uv` and the flagstone texture.
    - The courtyard is about 30×25 m with walls on all sides, on `world` and `ik_surface`. It must contain:
      - `fountain-round` at the centre;
      - at least 4 `lantern`s, each with an `OmniLight3D` (`#ffb060`, range 6 m, shadows on at least two);
      - a staircase of at least 6 steps (rise ≤ 0.25 m, run ≥ 0.3 m) up to a terrace at least 1.25 m high, built from `TestTerrain`-style steps with the flagstone texture where the Kenney stairs are too steep;
      - a 15–25° ramp;
      - trees and hedges in the corners;
      - a stall and banners;
      - at least 2 `Marker3D`s in group `poi`;
      - the markers `Spawn`, `StairsTop` and `RampTop`;
      - a `DirectionalLight3D` with shadows (pitch −50°, yaw 35°, warm `#ffd9b0`, energy 1.0);
      - a `WorldEnvironment` with tonemap linear and soft rose ambient;
      - `grade = courtyard_dusk.tres`.
  - `main.tscn`: `Main` (`main.gd`) → `PixelStage` → `World`: `Region` (the courtyard), `Player` (`actor.tscn` with `abarax.tres`) and `CameraRig`; plus `DebugOverlay` (a hidden `CanvasLayer`).
  - In `main.gd`:
    - `_ready` calls `Game.change(PLAY)`, puts the player at `Region.spawn()`, gives it a `PlayerBrain` with `view_yaw = CameraRig.yaw()`, sets the camera target and calls `snap_now()`, then `apply_settings(default_settings, region.grade)`;
    - F3 toggles the overlay (fps, physics ms, the current move and speed);
    - F4 toggles `RenderSettings.off()`;
    - Esc goes PLAY↔PAUSE;
    - **`--selftest`** (a user argument) installs a `TestLogger`, swaps in a `ScriptBrain` circuit (walk to the fountain, roll, jab, climb to `StairsTop`), runs 600 physics frames, then quits 0, or 1 if any error was logged.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# test_courtyard.gd
func test_markers_lights_and_poi() -> void:   # Spawn, StairsTop and RampTop exist; ≥ 4 OmniLight3D (≥ 2 with shadows); ≥ 2 in poi; a DirectionalLight3D with shadows
func test_floor_is_32_texels_per_metre() -> void:   # the floor material's world_uv is true and texels_per_metre is 32
func test_walks_from_spawn_to_stairs_top() -> void:
	# A ScriptBrain steers straight at StairsTop each frame: it gets within 0.6 m within 12 s, moving > 0.5 m/s on 90% of frames.
func test_walks_from_spawn_to_ramp_top() -> void:
func test_actor_cannot_leave_courtyard() -> void:   # push into each wall and corner for 3 s: it stays within the courtyard bounds and is never stuck
# test_main.gd
func test_main_boots_into_play_with_player_and_camera() -> void:
# tests/perf/test_frame_budget.gd
func test_courtyard_physics_frame_under_two_ms() -> void:   # mean Performance.TIME_PHYSICS_PROCESS ≤ 2.0 ms over 600 frames, headless
# tests/render/test_courtyard_shot.gd
func test_courtyard_shot() -> void:   # main at 1920×1080: save out/shots/courtyard.png; > 40 distinct colours; Abarax's palette tones appear near the centre
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/world` and `--filter=tests/main`.**
  Expected: FAIL because the scenes are missing.

- [ ] **Step 3: Implement it.**
  Run `tools/godot.sh -s res://tools/art/make_textures.gd`, then `tools/godot.sh -s res://tools/world/build_courtyard.gd`, then write `main.gd` and its scene.

- [ ] **Step 4: Run `tools/test.sh`, `tools/test.sh --render` and `tools/godot.sh -- --selftest`.**
  Expected: every test passes, and the self-test exits 0. Look at `out/shots/courtyard.png`: lit, warm, readable, and Abarax clear at 640×360.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "The courtyard (Kenney town kit, flagstones at 32 texels/m, lanterns) and the main scene; --selftest".

### Task 15: The motion retargeting tool

**Files:**
- Create: `all-divine/tools/anim/retarget.py`, `tools/anim/bonemap_cmu.json`, `tools/anim/tests/test_retarget.py`
- Test: `all-divine/tools/anim/tests/test_retarget.py`

**Interfaces:**
- Consumes: `abarax.glb` (Task 5); `UAL1_Standard.glb`'s `A_TPose` as the target's reference pose (Task 4).
- Produces:
  - `retarget.py --bvh <in> --map <json> --target <glb> --tpose <glb> --tpose-clip A_TPose --out <glb> --name <clip>`, run under `bpy`.
  - `load_bonemap(path) -> dict[str, str]`.
  - `retarget(bvh, bonemap, target, tpose, tpose_clip, out, name) -> None`:
    - each mapped target bone takes the source bone's world-space rotation change from the source's rest pose, applied on top of the target's T-pose reference;
    - root translation is scaled by the target's hip height over the source's hip height (from the BVH rest offsets);
    - the result is baked to one action and exported as a GLB holding that one animation.
  - The result is a clip that `clips.cfg` can name as a source in later milestones. Its ledger row is added with the first real CMU clip, which is not in F0.
  - `bonemap_cmu.json`, for the cgspeed BVH names:
    - torso: `Hips→pelvis`, `LowerBack→spine_01`, `Spine→spine_02`, `Spine1→spine_03`, `Neck→neck_01`, `Head→Head`;
    - arms: `LeftShoulder→clavicle_l`, `LeftArm→upperarm_l`, `LeftForeArm→lowerarm_l`, `LeftHand→hand_l`;
    - legs: `LeftUpLeg→thigh_l`, `LeftLeg→calf_l`, `LeftFoot→foot_l`, `LeftToeBase→ball_l`;
    - the same for `Right*` → `*_r`.

- [ ] **Step 1: Write the failing test.**

```python
# tools/anim/tests/test_retarget.py. The test writes a synthetic BVH into a temp dir:
# a Hips → LowerBack → Spine → Spine1 → Neck → Head chain, plus the legs, rest Hips height 0.9.
# 20 frames at 30 fps: Spine rotates 0→30° about X, and Hips translates z 0→1.0.
def test_spine_rotation_carries_over(self):
    # out.glb has one animation named "probe". At its last frame, spine_02's world rotation differs from the reference by 30° ± 2° about the same world axis.
def test_root_translation_scales_by_hip_height(self):
    # pelvis z at the end ≈ 1.0 × target_hip / 0.9, within ±2%
def test_unmapped_bones_keep_reference_pose(self):
```

- [ ] **Step 2: Run `tools/bpy_test.sh`.**
  Expected: `test_retarget` FAILS because `retarget` is missing.

- [ ] **Step 3: Implement `retarget.py` and `bonemap_cmu.json`.**

- [ ] **Step 4: Run `tools/bpy_test.sh`.**
  Expected: all Python tests pass.

- [ ] **Step 5: Commit**, adding to STATE.md Done: "Retargeting tool: BVH (CMU names) → our skeleton via bpy; ready for CMU strafes".

### Task 16: CI, exports and the handover in STATE.md

**Files:**
- Create: `.github/workflows/all-divine.yml`, `all-divine/export_presets.cfg`
- Modify: `all-divine/STATE.md` (the full F0 status, next steps, and the owner's checklist)
- Test: `all-divine/tests/tools/test_export_presets.gd`

**Interfaces:**
- Consumes: `tools/setup.sh`, `tools/test.sh`, `tools/clip_check.gd` and `--selftest`.
- Produces:
  - Export presets:
    - `Linux` → `out/linux/all-divine.x86_64`;
    - `Windows Desktop` → `out/windows/all-divine.exe`;
    - `Web` → `out/web/index.html`, with `variant/thread_support=false`.
  - The workflow runs on pushes and PRs touching `all-divine/**` or the workflow itself. It caches `.tools` and the templates by version. Its jobs:
    - `test`: setup, `tools/test.sh`, `godot.sh -s res://tools/clip_check.gd`;
    - `render`: apt `xvfb mesa-utils libgl1-mesa-dri`, then `tools/test.sh --render`;
    - `render-forward-plus`: apt `xvfb mesa-vulkan-drivers`, then `tools/test.sh --forward-plus --filter=test_screen_post`;
    - `export`: setup `--templates`, the three exports, then `out/linux/all-divine.x86_64 --headless -- --selftest` (which must exit 0), then upload the three builds as artifacts.
  - If the runner can't give Forward+ a Vulkan device (lavapipe), drop the `render-forward-plus` job, and record a ruling plus a line in STATE.md so the owner checks parity on their PC instead.

- [ ] **Step 1: Write the failing test.**

```gdscript
func test_presets_exist_with_paths_and_single_threaded_web() -> void:
	var cfg := ConfigFile.new(); assert_eq(cfg.load("res://export_presets.cfg"), OK)
	# The presets named Linux, Windows Desktop and Web exist with the export paths above, and Web has variant/thread_support=false.
```

- [ ] **Step 2: Run `tools/test.sh --filter=test_export_presets`.**
  Expected: FAIL because the file is missing.

- [ ] **Step 3: Write the presets and the workflow, then export locally.**
  Run `bash all-divine/tools/setup.sh --templates`, then `tools/godot.sh --export-release "Linux" out/linux/all-divine.x86_64` (and likewise for Windows and Web), then `all-divine/out/linux/all-divine.x86_64 --headless -- --selftest; echo $?`.
  Expected: three builds, and `0`.

- [ ] **Step 4: Run `tools/test.sh` and `tools/test.sh --render`.**
  Expected: all pass. Commit, push, and check the workflow with the GitHub tools until every job is green, fixing anything red.

- [ ] **Step 5: Finish `STATE.md` and commit.**
  - `Done`: every F0 line.
  - `Next`: "F1 Combat core (spec §9): write its plan".
  - `Owner checklist for F0`: download the Windows build from the latest CI run. Walk the courtyard with a gamepad and with the keyboard and mouse. Check the roll, the jab→cross chain, the stairs and ramp, and the scarf. Press F4 to compare the post effects off. Write notes in `all-divine/notes/f0.md`.
  - `Known limits`: no strafe clips yet (orientation warping covers 8-way); Forward+ parity status.

---

## Spec coverage (self-review)

| Spec item | Task |
|---|---|
| §2 Godot pinned and typed GDScript; the layers; content as data; one way to animate; headless tests; `STATE.md` | 1, 2, 7–9; constraints |
| §2.1 Core: state machine, input with rebinding and buffer, audio buses, registry | 2, 8 |
| §2.1 Data `.tres`, the CSV importer | 8 (the CSV importer is F2 by the spec's §9) |
| §2.1 Actors: body, rig, stats, hit and hurt zones, swappable brain | 7, 9 |
| §2.1 Moves: clip + MoveData; marks for hitbox, invulnerability, cancels, root motion, costs, effects, sound, shake, hit-stop | 8, 9 |
| §3.1 640×360, integer upscale, snapping, sub-pixel; DOF, bloom, fog, grading, vignette, adjustable | 3, 11 |
| §3.2 Low-poly toon, 3–4 steps, outlines, palettes, stepped clips; the liveliness layers; outfits and dyes | 5, 7, 10–13 (dyes by `with_dye`; outfit swapping is F2 equipment) |
| §3.3 Quaternius, Kenney, the retarget tool, `bpy`; `ASSETS.md` | 4, 5, 6, 15 |
| §3.4 32 texels per metre, real lights and shadows | 11, 14 (weather and day/night belong to F3 regions) |
| §3.6 Performance | 14 (CPU budget), constraints; GPU on the owner's PC |
| §8 Test runner, clip checker, feel metric (press to motion), contact sheets, CI | 1, 7, 8, 9, 16 |
| §9 F0: "a lit courtyard to walk in, where walking already feels good" | 14, plus the owner's checklist in 16 |

Not in F0, as the spec's §9 sets out: combat damage, stamina rules, lock-on, enemies, the CSV importer, the combat bot, input replay, the Director, animatics and storyboard sheets.
