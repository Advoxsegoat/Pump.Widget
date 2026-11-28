# The Menus Implementation Plan (the UI lane: pause, settings, controls)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the fight a pause menu that really stops it, a settings screen whose every setting takes effect at once and survives a restart, and a controls screen that shows and rebinds the buttons in the player's hands, all drawn in the HUD's own 640×360 pixel look.

**Architecture:** A new autoload `Settings` (core) holds every setting, applies each one to what it changes (the shared readability tuning, the camera's shake, the audio buses, the screen look, the window) and keeps them in `user://settings.cfg`. A new `Menu` control (`ui/`) lives in the `PixelStage`'s `Hud` viewport beside the `Hud`, runs while the tree is paused, is moved by fixed keys and buttons that rebinding cannot change, and draws pages of rows (pause, settings, controls) in whole picture pixels. The pause itself stays the existing `Game.State.PAUSE`; this lane makes what it freezes complete (the HUD's clocks, the effects' lifetimes) and keeps the press that closes a menu out of the fight.

**Tech Stack:** Godot 4.7.2, typed GDScript, the project's own test runner (`tools/test.sh`), `ConfigFile` for the settings file.

**Spec:** `docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md` (sections 2, 3.1, 3.5, 4.1, 7.3, 8; "Each can be turned down in Settings", "Every control can be rebound", "Settings can turn the camera dips off") and `docs/superpowers/specs/2026-11-10-all-divine-sway-defence-design.md` section 5 ("The slow-down and the afterimage each have a switch").

> **Built in a lane.** This plan is built in its own git worktree beside other lanes (combat, enemies, the world, cutscenes),
> under the lane rules in this plan's workspace (`lanes.md`): the lane never pushes; STATE.md's Done lines and the owner's
> checklist items named in each task's last step are given in the task's report and applied by the controller at the merge;
> the render suite is run as `TEST_TIMEOUT=3600 tools/test.sh --render`, because the machine is shared.

## Global Constraints

- Everything lives in `all-divine/`. Paths below are under it unless they start with `docs/` or `.superpowers/`.
- Content is data, never code. The rows' labels are constants in `ui/`; every number a setting changes is the tuning's or the render settings' own, never copied. The readability switches are read from `ReadabilityTuning.SWITCHES`, so a switch another lane adds appears in Settings by adding its name there.
- **The picture is 640×360** (`PixelSnap.INTERNAL`). The menu is drawn in the `Hud` viewport, which is exactly that picture, at the stage's whole-number scale (×3 at 1080p, ×4 at 1440p, ×6 at 2160p), with no grade and no sub-pixel shift. Every rect, text origin and line is a whole picture pixel (`Vector2i`/`Rect2i` in the queries), so it is as crisp as the pixels under it.
- **The menu's look is the HUD's own:** `ThemeDB.fallback_font` at `Hud.HINT_FONT_SIZE` (8), line pitch 10 px, colours `Hud.WHITE` (text), `Hud.GOLD` (headings, values), `Hud.ROSE` (the selected row), `Hud.POSTURE` (disabled text, footers), `Hud.INK` (panel, alpha 0.9, 1 px `Hud.GOLD` border). No new font, no new colour, no new asset.
- **The panel is a left column** at x 8, y 8, 224 px wide (right edge 232, left of the picture's centre where Abarax stands, clear of the wave pips at the top centre and of the bars at the bottom left: its lowest page ends above y 190). Nothing is dimmed outside it: the frozen fight stays fully readable.
- **Pad and keyboard both**, and the menu works with either alone. The menu's own controls are fixed (not read from the InputMap), so rebinding can never lock the player out: keyboard Up/W, Down/S, Left/A, Right/D move and adjust; Enter, Space and KP Enter choose; Esc and Backspace go back; pad D-pad and left stick move and adjust; A chooses; B goes back; and whatever the `menu` action is bound to also goes back (on the first page, resumes). Held directions repeat after 0.4 s every 0.1 s (key echo events are ignored). The mouse does nothing in a menu.
- **Settings are global, not part of a save** (the spec's saves are the world's): `user://settings.cfg`, a `ConfigFile`, written whenever a setting changes. The bindings keep their own file (`user://input.cfg`, `Inputs.save_bindings`).
- **Defaults leave the game as it is today:** every effect on, shake 100, dips on, look 100 each, sound 100 each, window as the project starts it. A player who never opens Settings sees no change.
- A missing, empty, binary or wrong-typed settings file gives the defaults (a bad value gives its own default, the rest are kept), prints nothing, and is rewritten whole at the next change.
- Frames are 1/60 s physics ticks. Green runs print no `ERROR:` or `WARNING:` lines (error paths are asserted through `quietly()` and returned data).
- Commit messages start `All-Divine UI: `, end with the attribution trailers the session specifies, and never name a model. Probes and scratch files live in the session's scratchpad, never in the project tree.
- **The numbers, in one place:**

| Setting | Key | Values | Default | What it changes |
|---|---|---|---|---|
| Nine effect switches | `effects/<name>` | on, off | the value in `data/tuning/readability.tres` (all on) | writes `<name>` on the shared `ReadabilityTuning` |
| Camera shake | `camera/shake` | 0 to 100, steps of 25 | 100 | `CameraRig.shake_offset()` is multiplied by the percent |
| Camera dips | `camera/dips` | on, off | on | read by the finisher's camera dip (F4); nothing dips yet |
| Screen look: Outline, Depth of field, Bloom, Fog, Colour grade, Vignette | `look/outline`, `look/dof`, `look/bloom`, `look/fog`, `look/grade`, `look/vignette` | 0 to 100, steps of 25 | 100 | each strength of `RenderSettings` (`outline`, `dof_strength`, `bloom_strength`, `fog_strength`, `grade_strength`, `vignette_strength`) times the percent |
| Sound: Master, Music, Effects, Voice, Interface | `sound/master`, `sound/music`, `sound/sfx`, `sound/voice`, `sound/ui` | 0 to 100, steps of 10 | 100 | buses `Master`, `Music`, `SFX`, `Voice`, `UI`: 0 mutes, else `linear_to_db(percent / 100)` |
| Window mode | `window/mode` | `"fullscreen"`, `"windowed"` | `"fullscreen"` (`"windowed"` on the web build) | `Window.MODE_FULLSCREEN` (borderless) or `MODE_WINDOWED` |
| Window size | `window/scale` | whole numbers 1 to 6 that fit the screen | 2 (1280×720, F11's size today) | the windowed size, 640k × 360k |

## Review Focus

Five conditions that would hurt a player first and that no task's main tests would reach on their own. Each is pinned by tests in the task named.

1. **Pausing at an awkward instant.** Mid hit-stop, mid slow-down, mid finisher or grab, while dead before Get Up, with a spark alive, with a foe's bars showing. A long pause must give back the same fight: the same frames of hit-stop and slow-down left, Get Up and the HUD's 3 s and blink clocks counted in play frames not wall frames, effects not expired behind the menu. Tests in Task 2.
2. **A press that leaks.** The press that confirms Resume (Space and A are the dash-step, LMB the palm, Esc and Start the menu button) must not also be a move on the first frame back; a button held across the close stays dead until let go; the press that opens the menu must not also navigate it; a stick already pushed when it opens must not move the selection; and debug keys (F5 to F9) must not reset or spawn while it is open. Tests in Task 2.
3. **A setting changed while its effect is on screen.** A slow-down in progress, an afterimage fading, a rim lit, a shake rolling, a sound playing. Rule: what is already in flight runs out (a slow-down is 12 frames, an afterimage 12, a wave 0.4 s) and the next one is not made; the chain rim, checked every frame, goes at once; shake and sound levels apply now. Tests in Tasks 1 and 3.
4. **The hardware changes under an open menu.** A pad unplugged (the controls page falls back to the keyboard's list; a pad capture is cancelled), a key pressed on the other device during a capture (ignored), the window resized or F11 pressed (the menu stays in the picture, stays open), a window size that no longer fits the screen. Tests in Tasks 2 and 4.
5. **A damaged settings file.** Empty, binary, half-written, wrong types, out of range, a newer version, unknown keys, a read-only folder. Defaults, per key, with no error line, and no half-file left by a failed save. Tests in Task 1.

---

## Decisions this plan makes where the spec leaves room

- **Rebinding is in** (spec 4.1: "Every control can be rebound"), and `Inputs.rebind`, `save_bindings` and `load_bindings` already exist; the UI is the only part missing. Rows are the actions F1 has: Move (four), Palm, Heavy, Guard, Dash-step, Lock on, Target left, Target right, Menu. Gift, item, interact and slot rows come with F2, which adds those actions' rows to the one list in `ui/controls_page.gd`. A capture replaces the first binding of the shown device's kind (so Dash-step's Space stays; there is no second-binding editor).
- **The pause menu replaces `PauseLabel`** ("Paused" becomes its heading). Any move into `Game.State.PAUSE` opens it, any move out closes it.
- **The screen look gets six sliders** (spec 3.1 says each effect can be turned down), as percentages of `data/render/default_settings.tres`; F4 stays the debug on/off over them.
- **The camera dips row exists and does nothing yet** (no dip is built; `Actor.combat_moment` is the hook F4 will use). Its page says so in one line. F4's task must read `Settings.get_value("camera/dips")`.
- **Menu sounds:** no new sound files. Moving is silent. A sound slider plays an existing cue on the row's own bus while it is set (Master and Effects: `impact_palm`; Interface: `stamina_refused`; Music and Voice: none, nothing plays on them yet). The sample uses the menu's own `AudioStreamPlayer` set to run while paused (`Sfx`'s voices pause with the tree).
- **Quit asks first** (a "Quit the game?" page with Cancel selected). On the web build the Quit row and the Window page are left out.
- **Not an accessibility feature set:** the spec has none beyond the switches, the dips and the look; text size, colour-blind modes and subtitles are not here.

## Facts the tasks rely on (read from the code, 2026-11-11)

- `Game.change(PAUSE)` sets `get_tree().paused`; `Main` and `Inputs` run always (`process_mode` 3), `PixelStage` is pausable, so the world, `Hud._process`, `Melee`, `Sfx`'s voices and the camera stop. `Main._unhandled_input` handles F1 and F3 to F9, F11, and the `menu` action (PLAY to PAUSE and back).
- `Inputs.pressed_this_frame()` reads `Input.is_action_just_pressed`, `Inputs.held()` reads `Input.is_action_pressed`; `PlayerBrain` is their only caller. `Inputs` keeps its direction latches fresh while paused, so a key that went down in a pause is not a sway.
- The `Hud` times three things with `Engine.get_physics_frames()` (hud.gd lines 175, 191, 473, 478: the stamina blink, and the 180-frame show of a foe's bars), and that counter keeps running while paused. `ActorFx` frees a shown effect with `create_timer(def.lifetime, true, true)`: its first `true` makes the timer run while paused, so a spark alive at the pause is freed behind the menu.
- `Melee` counts hit-stop (`Actor.freeze`) and the slow-down in physics ticks it runs, so both stop with the tree.
- `ActorFx.TUNING`, `ChainSlow.tuning` and every actor's `ActorFx.tuning` are the one preloaded `data/tuning/readability.tres`, read at use, so writing a switch on it takes effect everywhere at once. `ChainFx` checks `chain_rim_on` every frame, `afterimage_on` and `slowdown_on` when the chain starts one.
- `CameraRig.shake_offset()` is `shake_at(trauma, _shake_time)`; `trauma` is untouched by this lane.
- `Main._apply_look()` is `stage.apply_settings(DEFAULT_SETTINGS if look_on else DEFAULT_SETTINGS.off(), region.grade)`. `WindowToggle.target(mode)` returns a `WINDOWED_SIZE` (1280×720) window or fullscreen; F11 and Alt+Enter call `apply`.
- `Bindings.ACTIONS`, `defaults()`, `current()`, `apply()`, `event_to_data()`; `Inputs.rebind(action, event) -> StringName` (the action swapped with, or `&""`), `save_bindings()`, `load_bindings()`, `last_device()`; `ControlsList.ROWS`, `FINISHER_NOTE`, `event_name()`. `ControlsList.text()` is what the HUD's list shows and stays as it is.
- Tests: `TestCase` (`assert_*`, `quietly`, `frames`, `track`, `expect_error`), `get_viewport().push_input(event)`; `tests/main/test_main.gd` has `_main()`, `_press_action`, `_press_key`; `tests/render/test_hud_draw.gd` reads `main.stage.hud.get_texture().get_image()`.
- `tools/test.sh --render` takes about 15 minutes: run it as `TEST_TIMEOUT=1800 tools/test.sh --render`, at a task's end only.

## Working in a lane

This plan is built in its own git worktree beside lanes changing combat, enemies, the world and cutscenes.

**Must not touch:** `combat/`, `actors/` (the player's brain reads the quarantine through `Inputs`, so nothing there changes), `moves/`, `world/`, `data/actors/`, `data/brains/`, `data/moves/`, `data/pairs/`, `data/arena/waves.tres`, `assets/anim/`, `assets/audio/`, `tools/audio/make_sfx.py`, and the values in `data/tuning/*.tres`.

**Shared files, each changed by the smallest additive step** (take the other lane's side on any conflict and re-apply the step):

| File | The one change |
|---|---|
| `main/main.gd` | forward events to `menu` while paused and drop F5 to F9 then; `_apply_look` uses `Settings.look_of`; apply the window once at `_ready`; `Inputs.quarantine()` on PAUSE to PLAY; `Settings.note_window_mode` after F11; `menu.quit_requested` to `get_tree().quit()` |
| `main/main.tscn` | remove `PauseLabel`; add `Menu` under `PixelStage/Hud` after `Hud` (the `editable path` line stays) |
| `core/inputs.gd` | add `quarantine()` and the filter it implies in `pressed_this_frame()` and `held()` |
| `core/game.gd` | add `play_frames` and a `_physics_process` that counts it |
| `hud/hud.gd` | the four `Engine.get_physics_frames()` become `Game.play_frames`; nothing else, no menu code |
| `hud/controls_list.gd` | add constants and functions only; `text()` and `ROWS` unchanged |
| `fx/readability_tuning.gd` | add `const SWITCHES` (the nine names) |
| `fx/actor_fx.gd` | `create_timer(def.lifetime, true, true)` becomes `create_timer(def.lifetime, false, true)` |
| `render/camera_rig.gd` | `shake_offset()` returns `shake_at(...) * Settings.shake_scale()` |
| `main/window_toggle.gd` | `target()` takes the windowed size from `Settings.windowed_size()` (1280×720 by default) |
| `project.godot` | one autoload line, last in `[autoload]`: `Settings="*res://core/settings.gd"` |
| `STATE.md` | each task appends one Done line at the end of the Done list; the owner's items go in a new section "Owner checklist for the menus" (a merge keeps every line) |

## File structure

```
core/    settings.gd (new)   inputs.gd (quarantine)   game.gd (play_frames)
ui/      menu_nav.gd  menu_row.gd  menu.gd  menu_pages.gd  settings_pages.gd  controls_page.gd   (all new)
hud/     hud.gd (clock)   controls_list.gd (names, per-action lines)
fx/      readability_tuning.gd (SWITCHES)   actor_fx.gd (pausable timer)
render/  camera_rig.gd (shake_scale)
main/    main.gd  main.tscn  window_toggle.gd   pause_label.gd (deleted)
tests/   core/test_settings.gd  ui/test_menu_nav.gd  ui/test_pause.gd  ui/test_settings_screen.gd  ui/test_controls_screen.gd
         render/test_menu_draw.gd  render/test_menu_shots.gd   (and additions to core/test_game.gd, main/test_main.gd, main/test_window_toggle.gd, hud/test_hud.gd, hud/test_controls_list.gd)
```

---

### Task 1: Settings: the store, the file, and what each setting changes

**Files:**
- Create: `core/settings.gd`
- Modify: `project.godot` (autoload), `fx/readability_tuning.gd` (`SWITCHES`), `render/camera_rig.gd` (`shake_offset`), `main/main.gd` (look, window), `main/window_toggle.gd` (`target`)
- Test: `tests/core/test_settings.gd`, additions to `tests/main/test_main.gd` and `tests/main/test_window_toggle.gd`

**Interfaces:**
- Consumes: `ReadabilityTuning` (nine `*_on` exports, in groups "Switches" and "Chain switches"), `RenderSettings` (six strengths), `CameraRig.shake_offset`, `AudioServer` buses `Master`, `Music`, `SFX`, `Voice`, `UI`, `PixelSnap.INTERNAL`, `SelfTest.active`, `Main._apply_look`, `Main.window`, `WindowToggle.target/apply`.
- Produces:
  - **`ReadabilityTuning.SWITCHES: Array[StringName]`** = `[&"parry_aura_on", &"perilous_rim_on", &"heavy_wave_on", &"perilous_wave_on", &"perilous_icon_on", &"parry_burst_on", &"afterimage_on", &"slowdown_on", &"chain_rim_on"]`.
  - **The autoload `Settings`** (no `class_name`; tests make one with `load("res://core/settings.gd").new()`):
    - `signal changed(key: String)`; `var path := "user://settings.cfg"` (tests change it); `const VERSION := 1`.
    - `func keys() -> Array[String]`: every key of the table above, in the table's order (effects in `SWITCHES` order).
    - `func get_value(key: String) -> Variant`; `func default_of(key: String) -> Variant` (the effects' defaults are read from `data/tuning/readability.tres` once, at `_ready`, before any file is applied).
    - `func set_value(key: String, value: Variant) -> bool`: a wrong type or an unknown key returns false and changes nothing; a number is clamped to its range and snapped to its step; otherwise it stores, applies, saves (`save_file()`, its error ignored) and emits `changed(key)`.
    - `func reset_all() -> void`: every key to its default, applied, saved, `changed` for each key that moved.
    - `func load_file() -> bool`: reads `path`; false (silently) if the file is missing or not a `ConfigFile`; otherwise each key it understands is applied, a bad value leaves that key at its default, unknown keys and sections are ignored, a `[meta] version` above `VERSION` is read the same way. Never `push_error` or `push_warning`.
    - `func save_file() -> Error`: writes `path + ".tmp"` then renames it over `path`; a failure returns the error and leaves any old file whole.
    - `func shake_scale() -> float` (percent / 100); `func look_of(base: RenderSettings) -> RenderSettings` (a duplicate with each strength times its percent; `base` is not changed).
    - `func fitting_scales(screen: Vector2i) -> Array[int]` (every k in 1 to 6 with 640k ≤ screen.x and 360k ≤ screen.y; `[1]` if none); `func windowed_size(screen := DisplayServer.screen_get_usable_rect().size) -> Vector2i` (640k × 360k, k the stored scale or the largest that fits if it does not); `func window_target(screen: Vector2i) -> Dictionary` (`{mode, size}`, size `Vector2i.ZERO` for fullscreen); `func apply_window(window: Window) -> void` (sets mode and size, centres a windowed window; skips everything while `SelfTest.active`); `func note_window_mode(mode: Window.Mode) -> void` (F11 reports the mode it left the window in: stores `window/mode` as `"fullscreen"` for either fullscreen mode, else `"windowed"`).
  - **The file:**

```
[meta]
version=1
[effects]
parry_aura_on=true            ; one key per SWITCHES name
afterimage_on=false
[camera]
shake=100
dips=true
[look]
outline=100                   ; dof, bloom, fog, grade, vignette likewise
[sound]
master=100                    ; music, sfx, voice, ui likewise
[window]
mode="fullscreen"
scale=2
```

  - **Start-up:** `_ready` captures the defaults, then `load_file()` and applies the sound and effect keys, unless `SelfTest.active` (the self-test ignores the file and writes none). `Main._ready` calls `Settings.apply_window(window)` and `_apply_look()`, and connects `Settings.changed` so a `look/` key calls `_apply_look()` (which is `stage.apply_settings(Settings.look_of(DEFAULT_SETTINGS) or its .off(), region.grade)`). After F11 or Alt+Enter, `Main` calls `Settings.note_window_mode(window.mode)`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/core/test_settings.gd  (each test makes its own Settings with path "user://settings_test.cfg" and removes the file)
func test_defaults_match_the_tuning_resource_and_the_table() -> void:   # effects defaults == data/tuning/readability.tres values; shake 100; dips true; look 100 x6; sound 100 x5; window fullscreen, scale 2
func test_every_switch_in_the_tuning_is_listed_and_has_a_key() -> void: # every property of ReadabilityTuning ending "_on" is in SWITCHES, and keys() has "effects/<name>" for each (a switch another lane adds fails here until it is listed)
func test_keys_are_the_tables_keys_in_order() -> void:                 # 9 + 2 + 6 + 5 + 2 = 24 keys
func test_a_switch_takes_effect_at_once_on_the_shared_tuning() -> void: # set_value("effects/afterimage_on", false): ActorFx.TUNING.afterimage_on false, ChainSlow's tuning too; changed("effects/afterimage_on") emitted once; true again restores it
func test_a_value_of_the_wrong_type_or_an_unknown_key_is_refused() -> void: # false returned, value and file unchanged, no error line
func test_numbers_are_clamped_and_snapped_to_their_step() -> void:     # shake 130 -> 100, -5 -> 0, 60 -> 50 (step 25); sound 64 -> 60; window/scale 9 -> 6
func test_shake_scales_the_camera_now_and_a_shake_in_progress() -> void: # rig.shake(1.0): offset at 100; set camera/shake 50: offset is half, same noise time; 0: Vector2.ZERO; rig.trauma unchanged throughout
func test_sound_levels_set_the_buses() -> void:                        # each of the five: 50 -> volume_db ~ linear_to_db(0.5), unmuted; 0 -> muted; 100 -> 0 dB, unmuted
func test_the_look_scales_each_strength_and_nothing_else() -> void:    # look/bloom 50: bloom_strength half the base's, the other five strengths and focus_band, bloom_threshold equal; base untouched; look/outline 0 -> outline 0
func test_the_window_target_is_fullscreen_or_a_whole_multiple_of_the_picture() -> void: # mode windowed scale 3 on 2560x1440 -> {windowed, 1920x1080}; fullscreen -> {fullscreen, ZERO}
func test_a_scale_that_does_not_fit_the_screen_is_cut_to_the_largest_that_does() -> void: # scale 6 on 1920x1080 -> 3 (stored value stays 6); a screen under 640x360 -> 1
func test_fitting_scales() -> void:                                    # 1920x1080 -> [1,2,3]; 3840x2160 -> [1..6]; 500x300 -> [1]
func test_the_file_round_trips_every_key() -> void:                    # set a non-default for each key; a new Settings loads path: every key equal; the file has the sections above
func test_a_missing_file_gives_the_defaults_without_an_error_line() -> void:
func test_a_damaged_file_gives_the_defaults_without_an_error_line() -> void: # for each of: empty file, 4 KB of random bytes, "[effects" (unterminated), "shake=oops" with no section, shake="loud", shake=9999, afterimage_on=3, window/mode="sideways", scale=1.5: load_file never raises; a bad value is its own default and the good keys beside it are kept
func test_a_file_of_a_newer_version_is_read_as_far_as_it_is_understood() -> void: # version=99 plus an unknown [future] section: known keys loaded, no error
func test_a_failed_save_returns_an_error_and_leaves_no_half_file() -> void: # path under a missing folder: save_file() != OK, no error line, values still applied; with an old good file and a tmp that cannot be written: the old file is whole
func test_the_selftest_reads_and_writes_no_file() -> void:             # SelfTest.active true: defaults, no file made by set_value
func test_reset_all_restores_every_key_and_the_buses() -> void:
# tests/main/test_main.gd
func test_main_applies_the_look_from_the_settings_and_follows_changes() -> void: # look/vignette 0 -> stage.settings.vignette_strength == 0 at once; F4 off then on keeps it 0; restores
func test_main_applies_the_window_once_when_it_starts() -> void:       # a Main made with Settings window/mode "windowed" scale 2: apply_window's target is {windowed, 1280x720} (read from window_target, not the headless window)
# tests/main/test_window_toggle.gd
func test_f11_returns_to_the_chosen_window_size() -> void:             # window/scale 3 on a 1920x1080 screen: WindowToggle.target(fullscreen).size == 1920x1080; default stays 1280x720 (the existing tests pass unchanged)
func test_f11_records_the_mode_it_leaves() -> void:                    # Main after F11: Settings window/mode is "windowed", after F11 again "fullscreen"
```

- [ ] **Step 2: Run `tools/test.sh --filter=test_settings`, `--filter=test_main` and `--filter=test_window_toggle`.** Expected: FAIL.
- [ ] **Step 3: Build.** Write `core/settings.gd` and the additive changes in the shared-files table for this task. Print the saved file of a changed state in the scratchpad and read it against the format above (this task has no picture).
- [ ] **Step 4: Run `tools/test.sh` and `tools/godot.sh -- --selftest`.** Expected: all pass, exit 0, and `user://settings.cfg` is not made by the self-test.
- [ ] **Step 5: Commit.** `All-Divine UI: Settings, the store and what each setting changes`. STATE.md Done: "UI Task 1: `Settings` autoload: nine effect switches, shake, dips, screen look, sound buses, window; `user://settings.cfg`, a damaged one gives the defaults silently (`tools/test.sh`: N passed, 0 failed)". Owner's items: none yet (no screen).

---

### Task 2: The pause menu, a pause that gives the fight back, and presses that do not leak

**Files:**
- Create: `ui/menu_nav.gd`, `ui/menu_row.gd`, `ui/menu.gd`, `ui/menu_pages.gd`
- Modify: `main/main.tscn`, `main/main.gd`, `core/game.gd`, `core/inputs.gd`, `hud/hud.gd`, `fx/actor_fx.gd`
- Delete: `main/pause_label.gd` (and its `.uid`)
- Test: `tests/ui/test_menu_nav.gd`, `tests/ui/test_pause.gd`, `tests/render/test_menu_draw.gd`, `tests/render/test_menu_shots.gd`; modify `tests/main/test_main.gd` (the `PauseLabel` test becomes the menu's heading test), `tests/core/test_game.gd`, `tests/hud/test_hud.gd` (the clock)

**Interfaces:**
- Consumes: `Game.state_changed`, `Game.State`, `Inputs.GAMEPLAY`, `Bindings.FLICK_DEADZONE` (0.6) and `DIRECTION_RELEASE` (0.35), `Hud` constants (`HINT_FONT_SIZE`, `WHITE`, `GOLD`, `ROSE`, `POSTURE`, `INK`, `PICTURE`), `Settings` (Task 1), `Registry.fetch(&"sounds", id)`.
- Produces:
  - **`Game.play_frames: int`**: counts physics frames while the tree runs (the node is pausable, so it stops in a pause); `reset()` zeroes it. `Hud` uses it in place of `Engine.get_physics_frames()` for the blink and the foes' 180 frames. `ActorFx` timers stop with the tree.
  - **`Inputs.quarantine() -> void`**: records every action of `GAMEPLAY` down now and the physics frame; until each is let go, `pressed_this_frame()` leaves it out and `held()` says false for it; and for `QUARANTINE_FRAMES := 2` physics frames no press at all is reported. Movement (`move_vector`, direction presses) is not affected: a direction held through the close is a hold, not a press. `Main` calls it on every move from PAUSE to PLAY.
  - **`class_name MenuNav extends RefCounted`**: `enum Cmd { NONE, UP, DOWN, LEFT, RIGHT, CHOOSE, BACK }`; `func command(event: InputEvent) -> Cmd` (the fixed table in Global Constraints; key echo and releases give NONE; `menu` is recognised with `event.is_action_pressed(&"menu")`, so keys, buttons and test `InputEventAction`s all count; a stick past `FLICK_DEADZONE` gives one command and none again until it falls below `DIRECTION_RELEASE`); `func begin() -> void` (latches every stick direction already past the threshold, so a stick held when the menu opens moves nothing); `func tick(delta: float) -> Cmd` (the repeat: `REPEAT_DELAY := 0.4`, `REPEAT_EVERY := 0.1`, for a held direction of key, D-pad or stick).
  - **`class_name MenuRow extends RefCounted`**: `enum Kind { ACTION, TOGGLE, SLIDER, CHOICE, BINDING, TEXT }`; fields `kind`, `label: String`, `enabled := true`, `value_text: Callable` (returns the right-hand text), `on_choose: Callable`, `on_step: Callable` (takes -1 or +1). A TEXT row is never selected.
  - **`class_name Menu extends Control`** (full-rect in the Hud viewport, `process_mode` always, `mouse_filter` ignore, hidden until open):
    - `signal quit_requested`; `var window: Window` (Main sets it); `var web := OS.has_feature("web")`; `var page: StringName`; `var index := 0`; `var is_open: bool`.
    - `func handle(event: InputEvent) -> bool`: true when the menu consumed it (everything but the window toggle and F3, which `Main` handles first); `func press(cmd: MenuNav.Cmd) -> void` (what `handle` calls; tests call it).
    - `func rows() -> Array[Dictionary]`: what is drawn, each `{label, value, kind, enabled, selected, rect: Rect2i, text_at: Vector2i}`, plus `panel() -> Rect2i`; the drawing and the tests both use them.
    - It opens on `Game.state_changed(_, PAUSE)` at page `&"root"` with the first row selected, and closes on any move out of PAUSE.
  - **Pages** (`MenuPages`; each page is a heading and rows, text exactly as written):
    - `root`, heading `Paused`: rows `Resume`, `Quit` (Tasks 3 and 4 insert `Settings` and `Controls`: the final order is `Resume`, `Controls`, `Settings`, `Quit`). `Resume` and Back on this page do `Game.change(Game.State.PLAY)`. `Quit` is left out on the web.
    - `quit`, heading `Quit the game?`: rows `Cancel` (selected on arrival), `Quit`. `Quit` emits `quit_requested`; Back and `Cancel` return to `root`.
    - Footer line, by device in hand (`Inputs.last_device()`, the keyboard's if a pad is not connected): keyboard `Enter: choose   Esc: back`, pad `A: choose   B: back`. Selected row: text `Hud.ROSE` with a 3×5 chevron in rose cells to its left; headings `Hud.GOLD`; disabled `Hud.POSTURE`. Rows are 10 px apart; the panel is 6 px of padding around the heading, rows and footer.
  - **Main:** while `Game.state == PAUSE`, `_unhandled_input` gives the event to `menu.handle` after F11/Alt+Enter and F3, handles F1 and F4 as now, and ignores F5 to F9; the `menu` action opens from PLAY as now; the PAUSE-to-PLAY branch there is replaced by the menu's. `menu.quit_requested` calls `get_tree().quit()`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/ui/test_menu_nav.gd
func test_keys_and_pad_buttons_give_the_same_commands() -> void:       # table: Up/W/DpadUp UP; Down/S/DpadDown DOWN; Left/A/DpadLeft LEFT; Right/D/DpadRight RIGHT; Enter/Space/KP Enter/pad A CHOOSE; Esc/Backspace/pad B BACK; releases NONE
func test_a_stick_flicks_once_and_is_ready_again_below_the_release() -> void: # 0.7 -> UP; 0.65 -> NONE; 0.3 -> NONE (released); 0.7 -> UP
func test_a_held_direction_repeats_after_0_4_s_every_0_1_s() -> void:  # tick(0.39) NONE; tick(0.02) UP; then one UP per 0.1 s; release stops it; key echo events add none
func test_a_stick_already_pushed_when_the_menu_opens_moves_nothing() -> void: # begin() with axis at -0.9: the same push gives NONE; let go and push again gives UP
func test_the_menu_action_is_back_whatever_it_is_bound_to() -> void:   # rebind menu to F10: F10 -> BACK and so does Esc; restores the bindings
func test_rebinding_the_games_actions_never_changes_the_menus_keys() -> void: # palm to Enter, dodge to Esc, move_up to Down: the table above still holds
func test_selection_wraps_at_both_ends() -> void:                      # in Menu: UP on the first row selects the last; DOWN on the last the first; TEXT rows are skipped
# tests/ui/test_pause.gd
func test_pause_gives_back_a_trade_mid_hit_stop() -> void:             # a blow lands (hit-stop 5): pause with 3 frames left, 120 physics frames paused, resume: both fighters' freeze counters, positions, HP, move ids and frame counters unchanged by the pause, and equal to a control fight never paused at the same play frame
func test_pause_gives_back_a_slow_down_mid_way() -> void:              # Melee.slow(12, 0.4), pause after 5 of its frames, 200 frames paused: slowed() and the frames left unchanged; equal to a control after the same play frames
func test_pause_gives_back_a_finisher_pair_and_a_grab() -> void:       # pause on the 10th frame of the finisher: after resume the pair ends on the same play frame as in a control run
func test_pause_while_dead_keeps_get_up_counting_play_frames() -> void: # die, pause 1 s into the 3 s, 5 s paused, resume: Get Up begins after the remaining 2 s of play
func test_the_huds_clocks_count_play_frames() -> void:                 # a foe hit 10 play frames ago still shows its bars after 300 paused frames; the stamina blink continues from its phase; Game.play_frames is unchanged by the pause
func test_a_spark_alive_at_the_pause_is_still_there_after_a_long_pause() -> void: # ActorFx effect with lifetime 0.3 s, pause at 0.1 s, 2 s paused: still in the tree; gone 0.2 s of play after resume
func test_the_press_that_closes_the_menu_never_reaches_the_fight() -> void: # for each of Space, Enter, Esc, pad A, pad B, pad Start, LMB down: close the menu with it; Inputs.pressed_this_frame() is empty for the first 2 physics frames and the player's runner starts nothing in 10; held across the close it stays dead until let go
func test_a_deliberate_press_a_few_frames_after_the_close_still_acts() -> void: # 4 frames after the close a palm press starts the jab (the quarantine is brief, and released keys leave it)
func test_a_held_move_key_carries_on_through_the_close() -> void:      # W held across it: he walks; no sway, no dash-step
func test_the_press_that_opens_the_menu_does_not_navigate_it() -> void: # Esc opens: selection on the first row and still open 3 frames later; its release changes nothing
func test_debug_keys_do_nothing_while_paused() -> void:                # F5, F6, F7, F8, F9 in PAUSE: same region, same enemy count, arena untouched; F1 and F4 still work
func test_quit_asks_first() -> void:                                   # Quit -> page quit, Cancel selected; BACK -> root; Quit, Down, CHOOSE -> quit_requested once; Menu.web true leaves the row out
func test_resume_row_and_back_on_the_first_page_both_resume() -> void:
func test_any_move_into_pause_opens_the_menu_and_out_closes_it() -> void: # Game.change(PAUSE) shows panel with heading "Paused"; Game.change(PLAY) hides it
func test_the_menu_is_whole_pixels_inside_the_left_column() -> void:   # every rows() rect and text_at is int, inside (8,8)..(232,190), panel x 8, width 224
func test_the_menu_stays_in_the_picture_when_the_window_changes() -> void: # stage size 640x360, 1280x720, 1000x700, 500x300 while open: rows() identical, hud viewport 640x360, PixelStage.layout scale 1, 2, 1, 1; still open
func test_f11_while_paused_switches_the_window_and_keeps_the_menu_open() -> void:
func test_nothing_but_the_menu_moves_while_it_is_open() -> void:       # 60 frames open: player.frame, foes' frames, camera trauma, Game.play_frames unchanged
# tests/core/test_game.gd: test_play_frames_count_only_while_playing(); test_reset_zeroes_play_frames()
# tests/main/test_main.gd: the PauseLabel test now asserts the menu's heading row reads "Paused", hidden while playing, shown on PAUSE, runs while paused
# tests/hud/test_hud.gd: the tests that set _refused_at or _hit_at from Engine.get_physics_frames() use Game.play_frames
# tests/render/test_menu_draw.gd (render)
func test_the_panel_is_ink_with_a_gold_border_and_nothing_is_drawn_right_of_it() -> void: # hud.hints_visible false: pixel (10,10) INK alpha ~0.9, border pixels GOLD, every pixel with x >= 240 clear
func test_the_selected_row_has_a_rose_chevron_and_rose_text() -> void:
func test_the_text_is_drawn_at_whole_pixels() -> void:                 # the first column of a heading's pixels sits at text_at.x +- the glyph's own bearing, not on a half pixel (rendered twice, shifted 0.5 px in the query, differs)
# tests/render/test_menu_shots.gd (render): writes out/menu/<page>_640.png (the Hud picture) and out/menu/<page>_1080.png (the whole stage at 1920x1080, the world frozen mid-fight behind it) for every page that exists
```

- [ ] **Step 2: Run `tools/test.sh --filter=tests/ui`, `--filter=test_game`, `--filter=test_hud` and `--filter=test_main`.** Expected: FAIL.
- [ ] **Step 3: Build.** The files and shared-file steps above. Pausing at the instants Review Focus 1 lists is checked against a control run, not against hard-coded numbers.
- [ ] **Step 4: Look at it.** Run `TEST_TIMEOUT=1800 tools/test.sh --render --filter=test_menu_shots`; read `out/menu/root_640.png`, `root_1080.png` and the quit page; check that the panel is crisp at ×3, left of Abarax, clear of the bars and pips, and that the frozen fight behind it is undimmed. Show them to the owner.
- [ ] **Step 5: Run `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, `tools/godot.sh -- --selftest`.** Expected: all pass, exit 0. (The existing `test_sway_input` pause test still passes.)
- [ ] **Step 6: Commit.** `All-Divine UI: the pause menu, a pause that gives the fight back, presses that do not leak`. STATE.md Done: "UI Task 2: pause menu (Resume, Quit) in the HUD's picture; `Game.play_frames` for the HUD's clocks; `Inputs.quarantine`; F5 to F9 off while paused; `PauseLabel` replaced". Owner's items: pause mid-hit and mid-slow-down and see the fight come back unchanged; close the menu with the dash-step button and see he does not dash; try both pad and keyboard; resize the window while paused.

---

### Task 3: The settings screen

**Files:**
- Create: `ui/settings_pages.gd`
- Modify: `ui/menu_pages.gd` (the `Settings` row on `root`, between `Resume` and `Quit`), `ui/menu.gd` (the sample player, page registry)
- Test: `tests/ui/test_settings_screen.gd`; extend `tests/render/test_menu_draw.gd` and `tests/render/test_menu_shots.gd`

**Interfaces:**
- Consumes: `Settings` (Task 1: `get_value`, `set_value`, `reset_all`, `keys`, `fitting_scales`, `apply_window`), `ReadabilityTuning.SWITCHES`, `Menu`, `MenuRow`, `MenuPages` (Task 2), `Registry.fetch(&"sounds", id)`.
- Produces (pages and rows, text exactly as written; `value` is the right-hand text; a toggle shows `On` or `Off`; a slider shows a 40 px bar, gold fill of percent × 40 / 100 px, 1 px `Hud.INK` outline, and the percent, e.g. `75%`; choosing a toggle flips it, Left and Right set it off and on; a slider moves one step with Left and Right):
  - **`settings`**, heading `Settings`: `Effects`, `Camera`, `Screen look`, `Sound`, `Window` (the last left out on the web), `Restore defaults` (`Settings.reset_all()`), `Back`.
  - **`effects`**, heading `Effects`, one toggle per `SWITCHES` name, in this order and wording: `Parry aura` (`parry_aura_on`), `Perilous rim` (`perilous_rim_on`), `Heavy-attack wave` (`heavy_wave_on`), `Perilous wave` (`perilous_wave_on`), `Perilous icon` (`perilous_icon_on`), `Parry burst` (`parry_burst_on`), `Dodge afterimage` (`afterimage_on`), `Slow-down on a perfect dodge` (`slowdown_on`), `Chain rim` (`chain_rim_on`), then `Back`. A switch in `SWITCHES` with no label here shows its name with `_on` dropped, underscores as spaces and the first letter capitalised.
  - **`camera`**, heading `Camera`: slider `Camera shake` (`camera/shake`), toggle `Camera dips` (`camera/dips`), TEXT `Dips arrive with the finishers.` (in `Hud.POSTURE`), `Back`.
  - **`look`**, heading `Screen look`: sliders `Outline`, `Depth of field`, `Bloom`, `Fog`, `Colour grade`, `Vignette` (`look/outline`, `look/dof`, `look/bloom`, `look/fog`, `look/grade`, `look/vignette`), `Back`.
  - **`sound`**, heading `Sound`: sliders `Master`, `Music`, `Effects`, `Voice`, `Interface` (`sound/master`, `sound/music`, `sound/sfx`, `sound/voice`, `sound/ui`), `Back`. Each step plays that row's sample (Master and Effects: `impact_palm`; Interface: `stamina_refused`; Music and Voice: none) on the row's bus, at most once per 0.15 s, through the menu's own `AudioStreamPlayer` (`sample_player`, `process_mode` always).
  - **`window`**, heading `Window`: choice `Mode` (`Fullscreen`, `Window`; Left, Right and Choose cycle; applies at once through `Settings.apply_window(menu.window)`), choice `Size` (`x1 640x360` … one entry per `Settings.fitting_scales(screen)`, e.g. `x3 1920x1080`; disabled, in `Hud.POSTURE`, while Mode is `Fullscreen`), `Back`.
  - Every page keeps the footer of Task 2. Back returns to the page it came from (`settings` returns to `root`); the selection returns to the row it left.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/ui/test_settings_screen.gd
func test_the_settings_page_lists_its_rows_in_order() -> void:         # Effects, Camera, Screen look, Sound, Window, Restore defaults, Back; heading "Settings"
func test_the_effects_page_has_a_toggle_for_every_switch_with_its_label() -> void: # the nine labels above in that order, then Back; count == ReadabilityTuning.SWITCHES.size() + 1
func test_a_switch_without_a_label_shows_a_made_up_one() -> void:      # a test SWITCHES entry &"ghost_halo_on" -> "Ghost halo"
func test_choosing_a_toggle_flips_the_setting_and_the_file() -> void:  # Parry aura: Off in Settings and in the saved file; a new Settings reading it says false; Left sets off, Right on
func test_a_slider_moves_one_step_and_stops_at_its_ends() -> void:     # shake 100 -> Right stays 100; Left x5 -> 0 and stays; sound steps of 10; values 75% 50% ...
func test_each_row_changes_exactly_its_key() -> void:                  # for every row of every page: one Right/Choose changes one key in Settings and no other
func test_the_pages_show_what_is_stored_when_reopened() -> void:       # set, close, open: the rows read the stored values; after a restart (new Settings from the file) the same
func test_restore_defaults_resets_everything_and_stays_on_the_page() -> void:
func test_sound_rows_play_their_sample_on_their_bus_and_while_paused() -> void: # Effects step: sample_player.bus == "SFX", stream impact_palm's, playing while get_tree().paused; Music and Voice: nothing plays; no sample twice within 0.15 s
func test_the_window_page_disables_size_in_fullscreen_and_lists_only_fitting_scales() -> void: # screen 1920x1080 -> Size entries x1, x2, x3; Mode Window enables Size; choosing x3 stores window/scale 3 and window_target gives 1920x1080
func test_the_window_page_and_the_quit_row_are_left_out_on_the_web() -> void:
func test_a_slow_down_in_progress_runs_out_when_its_switch_is_turned_off() -> void: # Melee.slow(12, 0.4); pause after 4 frames; slowdown_on off; resume: slowed() still true, ends after the 8 left; the next chain's perfect dodge starts none
func test_an_afterimage_in_flight_fades_out_and_the_next_is_not_made() -> void:
func test_the_chain_rim_goes_at_once_when_its_switch_is_turned_off() -> void: # ChainFx checks it every frame: the frame after resume it is off
func test_a_shake_in_progress_follows_the_slider_the_moment_it_is_set() -> void:
func test_turning_every_effect_off_then_fighting_prints_no_error() -> void: # all nine off, a perilous attack, a parry, a flurry: runs, no ERROR or WARNING
# tests/render/test_menu_draw.gd: test_a_slider_is_drawn_with_a_gold_fill_of_its_percent(); test_a_toggle_shows_On_in_gold_and_Off_in_gold()
# tests/render/test_menu_shots.gd: effects, camera, look, sound and window pages (the Window page in fullscreen and in a window)
```

- [ ] **Step 2: Run `tools/test.sh --filter=test_settings_screen`.** Expected: FAIL.
- [ ] **Step 3: Build.** `ui/settings_pages.gd` builds each page from `Settings` and `ReadabilityTuning.SWITCHES`; no row holds a value of its own.
- [ ] **Step 4: Look at it.** `TEST_TIMEOUT=1800 tools/test.sh --render --filter=test_menu_shots`; read every settings page at 640×360 and at ×3. The longest label, `Slow-down on a perfect dodge`, and its value must fit the 224 px panel with a gap. Show them to the owner.
- [ ] **Step 5: Run `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, `tools/godot.sh -- --selftest`.** Expected: all pass, exit 0.
- [ ] **Step 6: Commit.** `All-Divine UI: the settings screen`. STATE.md Done: "UI Task 3: Settings screen: Effects, Camera, Screen look, Sound, Window; each setting at once and kept in `user://settings.cfg`". Owner's items: turn the afterimage and the slow-down off and fight a Flurry; set shake to 0 and take a hit; set Master to 0 and back; switch to a window at ×2 and ×3; quit and start again and find it all as left; delete `settings.cfg` by hand and start.

---

### Task 4: The controls screen and rebinding

**Files:**
- Create: `ui/controls_page.gd`
- Modify: `ui/menu_pages.gd` (the `Controls` row on `root`, between `Resume` and `Settings`), `ui/menu.gd` (capture state), `hud/controls_list.gd` (names, per-action lines)
- Test: `tests/ui/test_controls_screen.gd`, additions to `tests/hud/test_controls_list.gd`; extend `tests/render/test_menu_shots.gd`

**Interfaces:**
- Consumes: `ControlsList.ROWS`, `FINISHER_NOTE`, `event_name`, `Bindings.ACTIONS/current()/defaults()/apply()/is_gamepad()`, `Inputs.rebind/save_bindings/last_device()`, `Input.joy_connection_changed`, `Input.get_connected_joypads()`, `Menu`, `MenuRow` (kind `BINDING`).
- Produces:
  - **`ControlsList` additions** (nothing existing changes; `text()` is byte-for-byte what it was): `const ACTION_ROWS` (action, label, in order):

| Action | Label | Action | Label |
|---|---|---|---|
| `move_up` | `Move up` | `guard` | `Guard (tap: parry)` |
| `move_left` | `Move left` | `dodge` | `Dash-step (hold: sprint)` |
| `move_down` | `Move down` | `lock_on` | `Lock on` |
| `move_right` | `Move right` | `target_left` | `Target left` |
| `palm` | `Palm` | `target_right` | `Target right` |
| `heavy` | `Heavy (hold: charge)` | `menu` | `Menu / back` |

    plus `func shown(action: StringName, gamepad: bool) -> String` (the events of that device kind, `long_name`s joined with ` / `, or `Not bound`), `func long_name(event) -> String` (a stick says its direction: `L stick left`, `R stick right`; the triggers `LT`, `RT`), D-pad names `D-pad up/down/left/right` and `Back`, `Guide` added to `JOY_BUTTONS`; the HUD still says `Pad` for none it knows.
  - **`controls`** page, heading `Controls: Keyboard and mouse` or `Controls: Gamepad` (the device in hand: `Inputs.last_device()`, the keyboard when it says pad and `Input.get_connected_joypads()` is empty; it follows the hand while browsing). One `BINDING` row per `ACTION_ROWS` entry (label left, `shown` right-aligned), then TEXT rows `Sway / duck: hold guard + a direction` and `Palm on a broken foe: Open Hand` (those two are `ControlsList.ROWS`' and `FINISHER_NOTE`'s own text), then `Restore default controls` (`Bindings.apply(Bindings.defaults())`, saved), `Back`. Footer: keyboard `Enter: change   Esc: back`, pad `A: change   B: back`. The page ends above y 190.
  - **Capture:** Choose on a binding row starts it for the device shown at that moment; the footer becomes `Press a new key or mouse button for <label>. Esc cancels.` or `Press a new button for <label>. B cancels.`; the row shows `...`. The next press of that device's kind is bound with `Inputs.rebind(action, event)` (a key, a mouse button but not the wheel; a pad button, or a stick or trigger pushed past 0.6), and `Inputs.save_bindings()` is called. Esc (any device) and B (any device) cancel; so does 6 s of menu time and a pad being unplugged while a pad row waits (footer `Pad disconnected.`). An event of the other device is ignored and the shown device is held fixed until it ends. If `rebind` returns another action, the footer reads `Swapped with <its label, or its action name>.` for 3 s. While capturing, nothing else in the menu moves.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/ui/test_controls_screen.gd
func test_the_root_page_lists_resume_controls_settings_quit() -> void:  # exact order, exact text
func test_the_page_shows_the_bindings_of_the_device_in_hand() -> void:  # keyboard: Palm "LMB", Guard "Q", Dash-step "Shift / Space", Lock on "Tab", heading "Controls: Keyboard and mouse"; pad: Palm "RB", Guard "LB", Heavy "RT", Move up "L stick up", heading "Controls: Gamepad"
func test_a_pad_that_is_gone_shows_the_keyboards_list() -> void:        # last_device GAMEPAD, no joypads connected: keyboard list; Input.joy_connection_changed(0, false) while open rebuilds the page
func test_the_list_follows_the_hand_while_browsing() -> void:           # a pad button then a key press: the heading and rows flip each time
func test_capturing_a_key_rebinds_the_first_key_and_saves() -> void:    # Palm, capture, F: the first keyboard-or-mouse event of palm (LMB) is replaced by KEY_F, the pad's RB stays, file input.cfg holds it, footer back to the legend; restores bindings and file
func test_capturing_a_mouse_button_a_pad_button_a_trigger_and_a_stick() -> void: # each kind binds; the mouse wheel is ignored; a stick below 0.6 is ignored
func test_an_event_of_the_other_device_is_ignored_while_capturing() -> void: # pad row waiting: a key press changes nothing and the rows still show the pad
func test_escape_and_b_cancel_a_capture_and_nothing_changes() -> void:  # both devices' cancel keys, in both kinds of capture; Esc and B are never bound by a capture
func test_a_capture_gives_up_after_six_seconds_of_menu_time() -> void:  # paused tree, 6 s of process time
func test_unplugging_the_pad_during_a_pad_capture_cancels_it() -> void: # footer "Pad disconnected.", nothing bound, keyboard list shown
func test_a_key_another_action_owns_is_swapped_and_the_footer_says_so() -> void: # Guard to LMB: Palm gets Guard's old key; "Swapped with Palm." for 3 s
func test_an_action_left_without_a_binding_shows_not_bound_and_can_be_bound() -> void:
func test_menu_rebound_still_opens_and_closes_the_menu() -> void:       # menu to F10: F10 opens, F10 backs; Esc backs inside the menu but no longer opens it
func test_restore_default_controls_restores_and_saves() -> void:
func test_rebinding_never_changes_how_the_menu_is_moved() -> void:      # after rebinding palm to Enter and move_up to Down: the page still moves by the fixed table
func test_a_rebound_button_works_in_the_fight() -> void:                # palm on F: pressing F in play starts the jab (the whole path: capture, InputMap, PlayerBrain)
# tests/hud/test_controls_list.gd
func test_text_is_unchanged_by_the_additions() -> void:                 # ControlsList.text() equals the string it gave before this lane (copied into the test)
func test_dpad_and_back_buttons_have_names() -> void:
func test_sticks_say_their_direction() -> void:
func test_shown_joins_a_devices_events_and_says_not_bound_for_none() -> void:
# tests/render/test_menu_shots.gd: the controls page for each device, and mid-capture
```

- [ ] **Step 2: Run `tools/test.sh --filter=test_controls_screen` and `--filter=test_controls_list`.** Expected: FAIL.
- [ ] **Step 3: Build.** The row list is the one `ACTION_ROWS`; F2's rows are added there.
- [ ] **Step 4: Look at it.** `TEST_TIMEOUT=1800 tools/test.sh --render --filter=test_menu_shots`; read the controls page (both devices, and mid-capture) at 640×360 and ×3; all 12 rows and the footer must fit above y 190. Show them to the owner.
- [ ] **Step 5: Run `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, `tools/godot.sh -- --selftest`.** Expected: all pass, exit 0.
- [ ] **Step 6: Commit.** `All-Divine UI: the controls screen and rebinding`. STATE.md Done: "UI Task 4: Controls screen: the bindings of the device in hand, rebinding through `Inputs.rebind` kept in `user://input.cfg`; the pause menu is complete (Resume, Controls, Settings, Quit)". Owner's items: rebind Palm on the keyboard and on the pad and fight with it; bind a key another action has and read the swap line; unplug the pad on the controls page; press Esc during a capture; restore the defaults.

---

## Not in this plan, and who owns it

- **A title screen** (`Game.State.TITLE` exists, nothing shows it): the world milestone (F3). Until then Quit leaves the game.
- **Save slots, "Continue", a backup slot, saving settings per save:** F3 (spec section 6). Settings are global and stay in their own file.
- **Inventory, equipment, dyes, attributes and the level-up screen, the skill-equip screen, rebinding rows for item, Gift, interact and the slots:** F2 (and the shrine menus in F3). They open through `Game.State.MENU` and add pages and rows to `ui/`.
- **Dialogue boxes, portraits, letterboxing, subtitles:** F4 (the Director). The camera dip itself, which reads `camera/dips`, is F4's.
- **Mouse-driven menus, text size, colour-blind modes, difficulty, language, vibration:** nobody yet.
- **A true bitmap pixel font** for the HUD and the menu together: a later art pass (it needs a licence row in `ASSETS.md`). The menu uses the HUD's own font (the engine's fallback, 8 px) so the two change together.

## Self-review

- Every requirement has a task: the stopping pause, giving back mid-move, hit-stop and slow-down, and no leak (Task 2); Settings for the nine switches, shake, dips, sound buses and window, at once and kept, with a damaged file silent (Tasks 1 and 3); the controls screen with the present bindings and, since spec 4.1 asks for it, rebinding (Task 4); the HUD's font and colours, whole pixels, a left column that covers little (Global Constraints and Task 2's render tests); what is not here, and the lane's untouchable and shared files (above).
- Names agree between tasks: `Settings.get_value/set_value/reset_all/fitting_scales/apply_window/windowed_size/shake_scale/look_of/note_window_mode`; `Menu.handle/press/rows/panel/page/index`, `MenuRow.Kind`, `MenuNav.Cmd`, `Game.play_frames`, `Inputs.quarantine`; keys in the one table; page ids `root`, `quit`, `settings`, `effects`, `camera`, `look`, `sound`, `window`, `controls`.
- The root page grows one row in each of Tasks 3 and 4 (Tasks 3 and 4 run in that order; Task 4 pins the final order).
