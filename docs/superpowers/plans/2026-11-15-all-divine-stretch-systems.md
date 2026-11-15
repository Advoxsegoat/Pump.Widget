# The Stretch's Systems (shrines, petals, saves, foes, the Pack, the Collector) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the built Bilibara stretch into a level that can be played, lost and won: rose shrines to rest at, petals that drop and wait where Abarax fell, a save that keeps up with him, one shortcut loop, four kinds of foe standing where they should, one gank squad with a secret weakness, and a mini-boss whose fall opens the way on.

**Architecture:** One node, `StretchRun`, is added under the stretch's region when it is entered; it owns the world's memory (`WorldMemory`), the petals, the encounters, the gates and the boss, and reads everything about the place from data (`data/stretch/*.tres`, `data/items/`, `data/squads/`, `data/bosses/`). Places are marker names and coordinates in that data, not code and not new layout lines: the layout and the built scene are not touched. The save is a small JSON file written through a temporary file with a backup, never touched by a test, a recording, a replay or the bot. Foes are the six that exist, placed by data and given a few new, optional habits (home and leash, sleeping, squad hints) in `EnemyBrain`.

**Tech Stack:** Godot 4.7.2, typed GDScript, the project's own test runner (`tools/test.sh`), the Registry (`data/<kind>/`), the combat bot (`tools/bot`), the replay seam (`core/replay`).

**Spec:** `docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md` (sections 4.5, 5, 6, 8 and 9: the world half of F3; the place is `docs/superpowers/plans/2026-11-11-all-divine-bilibara-stretch.md`).

## Decisions for the owner

Each line is my choice first, then the other way. Every number is data (named below) and can be changed without code.

1. **Petals last until you die again, not on a clock.** You drop all the petals you carry where you fall; if you reach them they are yours again; if you die before you reach them, they wilt for good (the spec's "one chance"). Other way: they also wilt after some minutes of play (the number `wilt_seconds` in `data/stretch/petals.tres` is there, set to 0 = off).
2. **Foes come back only when you rest at a shrine, die, or load the game.** Not on a timer, not when you walk away. Other way: they also return after a few minutes. Foes you killed stay dead while you walk about; the mini-boss stays dead for good.
3. **A shrine rest is instant** (bars full, foes back, respawn point set, game saved): no kneeling clip, no menu yet (levelling and skills are F2's). The Rose Flask does not exist yet, so there is nothing to refill beyond the bars.
4. **Death:** three seconds after you fall (the yard's own delay) you stand up at the last shrine you rested at, or at the start if you have rested at none. Your petals wait where you fell, marked by a glowing pile and a count in the corner.
5. **Petals per foe:** Knuckle I 10, Knuckle II 20, blade Knuckle 30, Drummer 30, heavy Knuckle 60, the Collector 400. They are credited the moment a foe falls (no petals to pick up from a foe).
6. **The saved game** is one file with a backup, written at every rest, every world change (gate opened, item taken, mini-boss down), every death and petal pickup, every 30 seconds of play when something changed, and when the game ends. It remembers the last shrine, petals, the pile, what you carry and what you changed in the world; not where you stood: loading puts you at your last shrine with full bars, foes back. Other way: save the position too.
7. **How you start the stretch:** `-- --stretch` (or F2 in the game) continues your saved game, or begins one. `-- --stretch=new` begins afresh and neither reads nor writes the save: it is what the bot, a recording and a replay use. The game still boots into the training yard, so nothing that works today moves. Other way: boot into the stretch (a title screen is not built).
8. **The gank squad is "the Hand's Pack":** three Knuckles of tier II on the Rack Walk (the long alley with the drying racks), with no attack-token limit: they spread round you, start their attacks one after another a beat apart, and chain. **Its secret weakness is the Rose Bell**, lying behind the stall bench in the far corner of the second shrine's alcove, where most people rest and leave. Pressing the item button (R, or X on the pad) with the Bell, with the Pack awake within 16 m, scatters it: they fall back for a few seconds and then fight as ordinary foes (two at a time) from then on, even after you die and rest. A posted notice at the Rack Walk's entrance and the Bell's own words hint at it (placeholder lines: the owner writes the real ones). Other way: the Bell must be rung every fight.
9. **The mini-boss is "the Collector" (a working name):** the Hand's tithe-taker, "where the Hand collects" in the book's words. A Knuckle with a blade, a head taller (1.15 of the size), 300 HP and 140 posture, in three phases: his blade string; then the lunge (a perilous thrust, answered by the catch) and quicker feints; then the ground slam (a perilous low ring: hop it) and a blade that follows your dodges. He waits in the street's east end, in front of a toll gate that bars the Tanneries lane.
10. **The shortcut:** the gate at the street's west end (beside the first shrine) is barred from the street side ("It will not lift from this side"); from the loop lane's side a latch lifts the bar. It joins the first shrine to the Rack Walk (about 30 m instead of 85 m). Other way: it opens by a key found in the stretch.
11. **What the mini-boss's fall opens:** the toll gate across the lane's mouth (a low slate gate like the shortcut's, put there by the run, not by the layout). The yard beyond stays plain: First Knuckle's door is F5's.

## Global Constraints

- Everything lives in `all-divine/`. Paths below are under it unless they start with `docs/`. Godot 4.7.2, typed GDScript (every `var`, parameter and return typed; no `Variant` where a type will do).
- **Everything gameplay is deterministic and seeded.** A replay of a recorded session plays `as recorded`. The stretch's foes roll their dice from `hash("%s#%d" % [name, spawn_count])` with `spawn_count` taken from `StretchRun.serial` (`StretchRun.start_seed(n)` starts it at n × 1000, as `Arena.start_seed` does), and nothing in the stretch reads the wall clock, the engine's frame count or a random number outside a seeded generator. Timers count `Game.play_frames`, so a pause and a scene stand them still.
- **The bot's state-hash constants must not move.** No task here changes a byte of what the training yard's fights hash to or of what the bot records in the yard: Task 2 pins that with a test written before the code. The stretch has its own hash (`StretchRun.state_hash`).
- **Every change test-first with the failing line seen.** Each task's first step writes the tests, the second runs them and names the failure expected.
- **Data over code:** encounters, shrines, gates, squads, items, notes, the boss's phases and the petal numbers are resources (`.tres`) or marker names; no script per place. A new kind of thing gets a class, a resource and a test, never an `if` on an id.
- **Nothing sticky or robotic** (the owner's rule for feel): no menu, kneel, load wait or locked camera is put between Abarax and the next fight; a rest, a pickup and a latch take a press and give the control back that frame; a foe that gives up walks home, it does not teleport.
- **The fighters must be seen** (spec 3.5): every new foe attack keeps its tell; the Collector's phase change shows (rose rim, a cue, a beat of standing); his perilous attacks wear the rose flash and icon as every perilous attack does; the pile and the shrines are drawn in the world, not only on the HUD.
- **No new third-party assets.** New sounds are made by `tools/audio/make_sfx.py` (ours) and need an `ASSETS.md` row; new textures by `tools/art/make_textures.gd`; models are the existing ones, re-coloured and re-sized (as the heavy Knuckle was). `tests/tools/test_ledger.gd` is the arbiter.
- **A test's made-up paths are never written as `res://` literals** (a file that must not exist is `user://...` under a folder the test makes and removes). Save tests use `user://save_test/<name>/` and never `user://save/`.
- **Tests run headless through `tools/test.sh`**; render tests only by `--filter` with `--render`. A new test file that takes more than 10 s in a render run, or 5 s headless (times eight), gets a line in `tests/shard_weights.txt`.
- Frames are 1/60 s physics ticks; green runs print no `ERROR:` or `WARNING:` lines (error paths are asserted through `quietly()`).
- Commit messages start `All-Divine F3: `, end with the attribution trailers the session specifies, and never name a model. Commit the `.uid` files Godot makes for new scripts. Probes and scratch files live in the session's scratchpad. STATE.md gets one Done line per task and the owner's checklist items at the task that earns them.
- **The save never fights a replay.** A recording (`--record`) or a replay (`--replay`) in the stretch is of a new game (`--stretch=new`); it never reads or writes the player's save, and neither does a test, a `-s` script, the self-test or the bot (`SaveStore.may_use`, as `Settings._may_use`).

## Review Focus

Conditions the tasks' main tests would not reach by themselves, most likely to hurt a player first (each has its test in the task named):

1. **A save that cannot be read** (empty, garbage, cut short, edited, from a newer game, the main file bad and the backup bad too, the folder unwritable): the game starts a new one without a word or a crash, uses the backup when it can, never overwrites a newer game's file. Task 1.
2. **Dying again before the petals are reached, dying with none, and quitting in the three seconds after a death**: the second death wilts the first pile and leaves one new pile; no petals means no pile; the file written at the moment of death has the pile and the shrine, so a quit then loses nothing twice. Task 3.
3. **Leaving the Collector's fight any way** (dying, running past his leash, a pause, F5, a scene): he is whole and in his first phase when you come back, the toll gate is still shut and no flag is set; and once he is down, a saved game loads with him dead and the gate open. Task 7.
4. **Foes or petals where no one can stand or where the player wakes**: every post, shrine respawn, pickup and pile is standing ground for the body's capsule; no post is within 12 m of a respawn point; a foe never begins awake inside the respawn's reach. Tasks 3, 4 and 8's checker.
5. **A stretch session recorded and a save in the same game**: a recorded `--stretch=new` session replays `as recorded` with the player's save file untouched (written bytes compared before and after), and the yard's recordings and the bot's constants replay as before. Task 2 and Task 8.

---

## Not in this plan (and who owns it)

- **First Knuckle, his arena (the Tanneries yard), his fog gate and "Call the Hand"**: F5. The yard stays an empty, walkable room here.
- **Attributes, levels, equipment, the Rose Flask and its upgrades, found skills, changing skills at a shrine, travel between shrines**: F2. Seams left: `StretchRun.rested(shrine_id)` (F2's level-up menu opens from it), `SaveData.items` (F2 adds equipment beside it, and a quick-item selection beside Task 6's one-item rule), `ShrineDef` (F2 adds what a shrine offers).
- **Cutscenes**: the Director exists. The Collector's entrance is a seam only: `BossDef.entrance_scene` (empty) and the signal `BossFight.entrance_requested(scene_id)`, which `Main` forwards to `Director.play`; a scene needs a script, shots, a cast and marks, which is not trivially small. Task 7 proves the seam with the fixture scene.
- **New art.** The Collector is the blade Knuckle's model, re-coloured and 1.15 of the size; shrines and the pile are pixel particles; the gates are the layout's slate board and the kit's pieces.
- **A title screen, a save-slot menu, a "you died" banner, a map**: later. The petal count and the pile's marker are the only new HUD.
- **Real words.** Every line the player reads (the notice, the Bell's words, the latch's) is a placeholder written to show the system; each `NoteDef` and `ItemDef` has `placeholder = true` until the owner writes it, and Task 8's checker lists them.

## Facts the tasks rely on (read from the code, 2026-11-15)

- **The place.** `world/bilibara/bilibara.tscn` (built from `layout.txt`; the layout is its source) is a plain `Region` named `Bilibara`; the stretch plan's Task 2 is in, Tasks 3 to 5 may not be. It has markers (`Spawn` (-32.5, 1.25) yaw 90, `ShrineSite_A` (-35, 0), `ShrineSite_B` (35, -33.75) yaw 270, `StreetEast`, `LaneMid`, `RackEast` (27.5, -22.5), `RackWest` (-32.5, -22.5), `GateFar` (-32.5, -6.5), `GateNear` (-32.5, -3.5), `YardEntry`, `KnuckleSpawn`), pois (`ShrinePlinth_A` (-35, 0), `ShrinePlinth_B` (36.25, -33.75), `ShortcutGate`, `YardGate`), no `EnemySpawn_*`, and `StaticBody3D` nodes `Gate` (board, x -35..-30, z -5.5..-4.5) and `GateRail` (2.4 m up). Everything is flat at y = 0. Walkable plates are in the group `Walkable`. The walkable parts: court A x -40..-30 z -5..5; the street x -30..32.5 z -5..5; the lane x 25..30 z -55..-5; the Rack Walk x -35..25 z -25..-20; the loop lane x -35..-30 z -20..-5; alcove B x 30..37.5 z -37.5..-30; the yard x 15..40 z -75..-55 (x east, z south, the camera looks north).
- **The region is not an arena.** `Arena` owns waves, `AttackTokens`, resets and `state_hash()`; `InputRecorder.arena`, `InputReplayer.arena`, `CombatBot.begin(player, arena: Arena, ...)`, `BotWatch.bounds_of(arena)` and `Hud.bind(..., fight: Arena)` are typed on it, and a recording with no hash at its end is refused (`InputRecording.problem`). A stretch session cannot be recorded until Task 2 gives the recorder and replayer a hash source.
- **Foes.** An ENEMY `ActorDef` with a `brain` (`BrainDef`) gets an `EnemyBrain` of it on ready, dice `hash("%s#%d" % [name, spawn_count])`, unless `Actor.set_brain` was called first. `BrainDef.ignores_tokens` already exists (a brain with it never takes a token). `EnemyBrain` goes IDLE when its target is beyond `sight_range * LOSE_FACTOR` (2.0), and has `Mode { IDLE, NOTICING, ENGAGED, ATTACKING, RETREATING }`, `rest_for(seconds)` and `stand_down_for_scene`; it has no home, no leash, no sleep. `Arena._send` places a foe with `foe.place(Transform3D(Basis(Vector3.UP, yaw), at))`, facing +Z at yaw 0; `Locomotion.yaw_of(Vector2)` gives a yaw.
- **The player.** `Actor.die()`, `died`, `revive(at)` (full bars, plays `getup`), `place`, `stats.refill()`, `runner.stop()`, `frozen`, `paired_with`, `dead`. Presses of every gameplay action (`palm heavy guard gift dodge item interact lock_on ...`) are in `Inputs.pressed_this_frame()`, which a recording stores and `InputFeed.apply(entry)` replays; a node of the world may read them (nothing in the player's moveset uses `item` or `interact`). `ControlsList.shown(action, gamepad)` names a binding.
- **Files.** `Settings` writes `user://settings.cfg` through `path + ".tmp"` and a rename, reads it line by line, never errors, and does not touch the player's file in the self-test, a `-s` script (`Settings.scripted_run`) or with `--no-player-settings` (`Settings.user_args`); `tools/test.sh` gives each headless run its own `user://` folder, a render run shares one.
- **Hud.** `Hud` is a `Control` in the 640 x 360 picture; `shown_alpha()`, `picture_point(world_point)`, `PICTURE`, `ROSE`, `GOLD`, `INK`, `WHITE` and the fallback font at `HINT_FONT_SIZE` are what a drawing next to it uses. A scene hides it.
- **Registry.** `data/<kind>/*.tres`, each with an `id`; `Registry.fetch(kind, id)`, `ids(kind)`.
- **Director.** `Director.play(scene_id: StringName, host: Node) -> Director` (null with `Director.last_refusal` when it cannot).
- **Sounds and effects.** `SoundCue` in `data/sounds/` (made by `tools/audio/make_sfx.py` into `assets/audio/sfx/`; `Sfx.play(id, at, pitch)`); `FxDef` in `data/fx/` shown by `ActorFx.show_fx(id, at, bone) -> Node3D`.
- **Tests.** `extends TestCase`, `track()`, `frames(n)`, `quietly()`, `assert_eq`, `assert_near`; `tests/world/test_bilibara.gd` has the flood fill (0.5 m cells, a 0.35 m capsule at 0.5 m overlapping no `world`) that Task 2 lifts into `tests/support/stretch_ground.gd`. `Main.parse_arguments` returns exactly `{record, replay, replaying}` and three tests compare it whole: leave it alone.

## Files at a glance

| New | Job |
|---|---|
| `core/save/{save_data,world_memory,save_store,save_migrations}.gd` | the saved game: what it holds, the file, the backup, the version |
| `world/stretch/{stretch_def,shrine_def,stretch_run,interactable,interactor,shrine}.gd`, `shrine.tscn` | the run and the rose shrines |
| `world/stretch/{petal_tuning,petals,petal_pile}.gd` | petals and the corpse run |
| `world/stretch/{placement,encounter_def,encounter_host}.gd` | foes placed as encounters |
| `world/stretch/{gate_def,gate_door,latch}.gd` | gates and the shortcut |
| `world/stretch/{squad_def,squad,item_def,note_def,item_pickup,note_post}.gd` | the Pack, the Bell and the notice |
| `world/stretch/{boss_def,boss_phase,boss_fight}.gd` | the Collector |
| `hud/stretch_hud.gd` | prompt, petals, the pile's marker, notes, the boss's bar |
| `data/stretch/`, `data/items/`, `data/squads/`, `data/bosses/` | everything the place says, as resources |
| `tests/support/stretch_ground.gd` | standing ground and the flood fill, shared by the tests |

Modified (by addition): `main/main.gd`, `core/replay/{recorder,replayer}.gd`, `actors/enemy_brain.gd`, `actors/actor_def.gd` (`petals`), `tools/bot/{combat_bot,bot_watch,run_bot,bot_runner}.gd`, `tools/audio/make_sfx.py`, `ASSETS.md`.

---

### Task 1: The saved game and the world's memory

**Files:**
- Create: `core/save/world_memory.gd`, `core/save/save_data.gd`, `core/save/save_migrations.gd`, `core/save/save_store.gd`
- Test: `tests/core/test_world_memory.gd`, `tests/core/test_save_store.gd`, `tests/core/test_save_migrations.gd`

**Interfaces:**
- Consumes: `Settings.scripted_run`, `Settings.user_args`, `Settings.NO_PLAYER_SETTINGS`, `SelfTest.active` (the rule for when the player's own file is left alone).
- Produces:
  - `class WorldMemory extends RefCounted`: `signal flagged(flag: StringName)`; `func has(flag: StringName) -> bool`; `func set_flag(flag: StringName) -> bool` (true and `flagged` only the first time); `func names() -> Array[StringName]` (sorted); `func to_dict() -> Dictionary` (flag name String -> true, keys sorted); `static func from_dict(d: Variant) -> WorldMemory` (anything not a dictionary is empty; a value that is not `true` drops that key).
  - `class SaveData extends RefCounted`: `const VERSION := 1`; `var rest_shrine: StringName = &""` ("" is the start); `var petals := 0`; `var pile := {}` (empty, or `{x: float, y: float, z: float, amount: int, frames: int}`: where it lies, how many petals, play frames since it was dropped); `var items := {}` (StringName -> int); `var memory := WorldMemory.new()`; `var deaths := 0`; `var play_frames := 0`; `static func new_game() -> SaveData`; `func to_dict() -> Dictionary` (no `version`, no `check`); `static func from_dict(d: Dictionary) -> SaveData` (a missing or mistyped field takes its default, an unknown key is ignored, negative counts are 0, a pile with a missing part is empty).
  - `class SaveMigrations extends RefCounted`: `const STEPS: Array[Callable] = []` (`STEPS[i]` takes a version i+1 dictionary and returns the version i+2 one); `static func upgrade(d: Dictionary, steps: Array[Callable] = STEPS) -> Dictionary` (a dictionary whose `version` is missing, not a whole number, below 1 or above `steps.size() + 1` gives `{}`; otherwise each step from its version up runs once in order and the result carries the new `version`; a step that returns a non-dictionary or one whose `version` is not the next gives `{}`).
  - `class SaveStore extends RefCounted`: `const PLAYER_DIR := "user://save"`, `const MAIN := "save.json"`, `const BACKUP := "save.bak.json"`, `const TEMP := "save.tmp"`; `enum Source { NONE, MAIN, BACKUP }`; `var dir: String`; `var last_source := Source.NONE`; `var last_problem := ""` (one line, "" when the last read found nothing wrong); `func _init(save_dir: String = PLAYER_DIR)`; `func may_use() -> bool` (false for `PLAYER_DIR` under the self-test, a `-s` script or `--no-player-settings`; true for any other folder); `func write(data: SaveData) -> Error` (OK and nothing written when `may_use()` is false); `func read() -> SaveData` (null when there is nothing usable; sets `last_source` and `last_problem`); `static func encode(data: SaveData) -> String`; `static func decode(text: String) -> Variant` (a `SaveData` or null).
  - **The file**: JSON text, keys sorted, `{"check": <sha256 of the text of everything else>, "version": 1, ...SaveData.to_dict()}`; `decode` refuses text that does not parse as a dictionary, has no integer `version` >= 1, whose `check` does not match, or whose version is newer than `SaveData.VERSION`; an older one goes through `SaveMigrations.upgrade` first.
  - **Writing**: encode, write `TEMP`, read `TEMP` back and decode it (a temp that does not decode is removed and the error returned, the old files untouched); then, if `MAIN` is a usable save, rename it over `BACKUP`; if `MAIN` is a newer game's, rename it to `save.v<its version>.json` (never to the backup, never overwritten); then rename `TEMP` over `MAIN`. At every step at least one usable file is on disk.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/core/test_world_memory.gd
func test_a_flag_is_new_once_and_announced_once() -> void:
	# set_flag(&"shortcut_open") true then false; `flagged` emitted once with that name; has() true
func test_names_are_sorted_and_to_dict_round_trips() -> void:
	# set &"b", &"a" -> names() == [&"a", &"b"]; from_dict(to_dict()).names() equal
func test_from_dict_takes_only_true_values_and_survives_junk() -> void:
	# {"a": true, "b": false, "c": "yes", "d": 1} -> [&"a"]; from_dict(null), from_dict([1]), from_dict("x") -> no flags

# tests/core/test_save_store.gd   (folders under user://save_test/, removed in after_each)
func test_a_save_round_trips_every_field() -> void:
	# rest "rose_b", petals 120, pile {x 27.5, y 0.0, z -30.0, amount 80, frames 600}, items {rose_bell: 1}, flags shortcut_open + collector_down, deaths 3, play_frames 7200
	# write -> read: to_dict() equal field by field; last_source == MAIN; last_problem == ""
func test_the_text_is_the_same_every_time_and_says_its_version_and_check() -> void:
	# encode twice equal; parses; "version" == 1; "check" is 64 hex characters
func test_a_second_write_keeps_the_first_as_the_backup_and_leaves_no_temp_file() -> void:
	# write A (petals 1), write B (petals 2): MAIN decodes to B, BACKUP to A, TEMP absent
func test_a_cut_short_main_file_falls_back_to_the_backup() -> void:
	# write A, write B, cut MAIN to half its bytes: read() is A, last_source == BACKUP, last_problem non-empty
func test_an_edited_file_fails_its_check() -> void:
	# replace `"petals":120` by `"petals":999` in MAIN's text, check untouched: with a backup it reads the backup; without, null
func test_nothing_usable_reads_as_null_and_never_errors() -> void:
	# no folder; MAIN of 0 bytes; of random bytes; a JSON list; MAIN and BACKUP both bad: read() null each time, no ERROR line
func test_a_newer_games_file_is_not_read_and_not_lost() -> void:
	# MAIN = a valid file of version 99 (its check right): read() null (a usable BACKUP is used instead); then write(data): `save.v99.json` has the old bytes exactly, MAIN decodes to data, BACKUP is not the v99 file
func test_a_missing_or_mistyped_field_is_its_default_and_unknown_fields_are_ignored() -> void:
	# a dictionary with petals "many", deaths -4, an unknown "mood", flags {"x": true, "y": 3}, a pile lacking `amount`, encoded by hand with a right check: petals 0, deaths 0, flags [x], pile empty
func test_an_unwritable_folder_is_an_error_and_leaves_the_old_files() -> void:
	# a folder path whose parent is a regular file: write() != OK, no crash; with good files present elsewhere, they are untouched
func test_the_players_folder_is_left_alone_by_a_test_run_and_other_folders_are_not() -> void:
	# SaveStore.new().may_use() false and write() returns OK with nothing created under user://save; SaveStore.new("user://save_test/x").may_use() true
# tests/core/test_save_migrations.gd
func test_a_chain_of_steps_runs_each_once_in_order() -> void:
	# made-up steps v1->v2 (adds "a": 1) and v2->v3 (copies "a" to "b"): upgrade({version 1}, steps) has version 3, a and b; a version 3 dictionary is returned unchanged; steps ran 2 times in all
func test_a_missing_or_future_version_is_refused() -> void:
	# {} , {"version": "1"}, {"version": 0}, {"version": 4} (2 steps) -> {}
func test_a_step_that_returns_rubbish_refuses_the_file() -> void:
func test_the_real_chain_has_one_step_fewer_than_the_version() -> void:
	# SaveMigrations.STEPS.size() == SaveData.VERSION - 1
```

- [ ] **Step 2: Run** `tools/test.sh --filter=tests/core/test_world_memory`, then `--filter=tests/core/test_save`. Expected: FAIL (`WorldMemory`, `SaveData`, `SaveStore`, `SaveMigrations` are not declared).
- [ ] **Step 3: Implement** the four files as the interface says. `Settings.save_file` is the model for the rename dance (temp, close, rename, remove the temp on failure); the check is `String.sha256_text()` of the encoded text with `check` left out (`JSON.stringify(dict, "", true)` sorts keys); integers come back from JSON as floats, so `SaveData.from_dict` rounds whole numbers (`is_equal_approx(floorf(v), v)`) and treats anything else as mistyped.
- [ ] **Step 4: Run** the three files, then `tools/test.sh`. Expected: all pass, no `ERROR:` or `WARNING:` lines; `tools/test.sh --filter=test_ledger` passes (no asset added).
- [ ] **Step 5: Commit.** STATE.md Done line: "F3 Task 1 (systems): the saved game and the world's memory: `SaveData`, `WorldMemory`, `SaveStore` (one JSON file, its backup, a check, a version and migration steps; never the player's file in a test, a script or the self-test; a newer game's file is moved aside, not overwritten)."

---

### Task 2: The run, the shrines, resting and the way back after death

**Files:**
- Create: `world/stretch/{stretch_def,shrine_def,stretch_run,interactable,interactor,shrine}.gd`, `world/stretch/shrine.tscn`, `hud/stretch_hud.gd`, `data/stretch/bilibara.tres`, `data/stretch/rose_a.tres`, `data/stretch/rose_b.tres`, `fx/petal_burst.tscn`, `fx/shrine_glow.tscn`, `data/fx/petal_burst.tres`, `data/sounds/shrine_rest.tres`, `tests/support/stretch_ground.gd`
- Modify: `main/main.gd`, `core/replay/recorder.gd`, `core/replay/replayer.gd`, `tools/audio/make_sfx.py` (the cue `shrine_rest` and its WAV), `ASSETS.md` (its row), `tests/world/test_bilibara.gd` (uses `StretchGround`)
- Test: `tests/world/test_stretch_run.gd`, `tests/world/test_shrines.gd`, `tests/hud/test_stretch_hud.gd`, `tests/main/test_main_stretch.gd`, `tests/replay/test_replay_stretch.gd`, `tests/replay/test_yard_hash_pin.gd`

**Interfaces:**
- Consumes: Task 1's `SaveData`, `SaveStore`, `WorldMemory`; `Region`, `Actor`, `Stats.refill`, `Game.play_frames`, `AttackTokens`, `CameraRig.GROUP` and `snap_now()`, `ActorFx.show_fx`, `Sfx.play`, `ControlsList.shown`, `Inputs.pressed_this_frame`, `Inputs.last_device`, `Hud.shown_alpha`, `Hud.picture_point`.
- Produces:
  - `class ShrineDef extends Resource` (Registry kind `stretch`): `@export var id: StringName`, `title: String`, `plinth: Vector3`, `respawn: Vector3`, `respawn_yaw_deg: float` (about +Y: 0 faces south, 90 east, 180 north, 270 west), `radius := 2.0`. Data: `rose_a` (title "Rose shrine, behind the Lazyman's", plinth (-35, 0, 0), respawn (-32.5, 0, 1.25) yaw 90) and `rose_b` ("Rose shrine, the lamp and the chair", plinth (36.25, 0, -33.75), respawn (35, 0, -33.75) yaw 270).
  - `class StretchDef extends Resource` (kind `stretch`, id `bilibara`): `@export var id: StringName`, `region: String`, `shrines: Array[ShrineDef]`, `start_shrine: StringName` (`rose_a`); later tasks add their own exports.
  - `class Interactable extends Node3D`: `const GROUP := &"interactables"`; `@export var radius := 1.8`; `func prompt(actor: Actor) -> String` (virtual, "" for none now); `func interact(actor: Actor) -> void` (virtual); `func in_reach(actor: Actor) -> bool` (flat distance to the actor <= radius); it adds itself to `GROUP` when ready.
  - `class Interactor extends Node`: priority after every actor (`process_physics_priority = 10`); `signal interacted(what: Interactable)`; `var current: Interactable` (the nearest in reach whose prompt is not empty, or null); `func prompt_line() -> String` (`"<key>  <prompt>"`, the key from `ControlsList.shown(&"interact", Inputs.last_device() == Inputs.Device.GAMEPAD)`, "" when none); each frame it finds `current` and, when `interact` was pressed that frame, calls `current.interact(player)` and emits; it does nothing in a state other than `Game.State.PLAY`, with the player dead, frozen, in a move, paired, or while a `Director` scene is on.
  - `class Shrine extends Interactable`: `var def: ShrineDef`; `prompt` = "Rest"; `interact` calls `StretchRun.rest(def)`; `shrine.tscn` has `shrine_glow` (a looping pixel-particle rose glow, no light: the stretch's lamp budget is spent).
  - `class StretchRun extends Node`:
    - `signal rested(shrine_id: StringName)`, `signal world_changed(flag: StringName)`, `signal world_reset`, `signal player_fell`, `signal respawned`
    - `const DEATH_DELAY := 3.0`, `const AUTOSAVE_FRAMES := 1800`
    - `static func start(region: Region, player: Actor, stretch_def: StretchDef, store: SaveStore, data: SaveData) -> StretchRun` (adds the run as a child named `StretchRun`, an `AttackTokens` and an `Interactor` beside its shrines under it, places the player at the rest shrine's respawn with full bars; `store` null: nothing is ever written)
    - `static func start_seed(n: int) -> void`; `var serial := 0`
    - `var def: StretchDef`, `var data: SaveData`, `var store: SaveStore`, `var player: Actor`, `var region: Region`, `var tokens: AttackTokens`, `var interactor: Interactor`
    - `func rest_shrine() -> ShrineDef` (the one in `data.rest_shrine`, else `def.start_shrine`)
    - `func rest(shrine: ShrineDef) -> void`: bars full (`stats.refill()`), `data.rest_shrine = shrine.id`, flag `shrine:<id>`, a petal-burst effect on the player, the cue `shrine_rest`, `world_reset`, `rested`, save
    - `func flag(name: StringName) -> bool`; `func set_flag(name: StringName) -> void` (memory, `world_changed` once, save)
    - `func respawn() -> void` (`world_reset`, `player.runner.stop()`, `player.revive(spawn_point(rest_shrine()))`, the camera snaps, `respawned`, save)
    - `func spawn_point(shrine: ShrineDef) -> Transform3D`; `func save_now() -> Error` (OK when `store` is null)
    - `func state_hash() -> int`: the frames lived, the player and every actor under the region in tree order (position to the millimetre, HP, posture and stamina to a tenth, the move id), `data.rest_shrine`, the flags sorted; later tasks add their parts.
    - Timers count `Game.play_frames`; the run saves on the autosave tick only when something changed, and when it leaves the tree.
  - `class StretchHud extends Control` (a child of the `Hud`; `hud/stretch_hud.gd`): `var run: StretchRun`; `func bind(hud: Hud, run: StretchRun) -> void`; `func prompt_line() -> String` (the interactor's); draws the prompt line at the bottom centre (the HUD's fallback font, outlined in `Hud.INK`) and nothing while `hud.shown_alpha() <= 0`.
  - `InputRecorder.hash_of: Callable` and `InputReplayer.hash_of: Callable`: when valid, called for the hash instead of `arena.state_hash()` (nothing else about them changes).
  - `Main`: `var stretch: StretchRun`, `var save_dir := SaveStore.PLAYER_DIR`, `var stretch_start := ""` (a seam for tests and the bot, set before the node is ready: `""`, `"continue"` or `"new"`; `_ready` reads the user arguments only while it is empty); `static func parse_stretch(args: PackedStringArray) -> String` (`""`, `"continue"` for `--stretch`, `"new"` for `--stretch=new`; anything else after `=` is `""`); `func enter_stretch(new_game := false) -> void`.
  - `StretchGround` (`tests/support/stretch_ground.gd`): `static func stands(region: Region, point: Vector3) -> bool` (an `ik_surface` ray down meets y = 0 within 0.01 and a 0.35 m capsule at 0.5 m overlaps no `world` body); `static func reached(region: Region) -> Dictionary` (the flood fill from `Spawn`, 0.5 m cells, keyed by `Vector2i(round(x / 0.5), round(z / 0.5))`); `static func clearance(region: Region, point: Vector3) -> float` (the flat distance to the nearest `world` collider, found by rays at 16 angles, capped at 6 m).

- [ ] **Step 1: Pin the yard before touching it.** With no code changed, write a scratchpad probe that starts `Main` through `BotWorld.make(host, 1)`, plays `CombatBot` (counter policy, seed 1, reaction 14) for 120 frames and prints `game.arena().state_hash()` and `recorder.recording().frames.hash()`. Put both numbers in `tests/replay/test_yard_hash_pin.gd` as `YARD_STATE_HASH` and `YARD_FRAMES_HASH`, with the test `test_the_yards_seeded_bot_fight_hashes_as_it_did_before_the_stretch_work` asserting a fresh run equals them. It passes now and must pass at the end of every task.
- [ ] **Step 2: Write the failing tests.**

```gdscript
# tests/world/test_stretch_run.gd   (the stretch region with Abarax as a child of it and a StretchRun started, store null unless said)
func test_a_new_game_stands_at_the_first_shrines_respawn_with_full_bars() -> void:
	# player within 0.01 m of (-32.5, 0, 1.25), facing 90 degrees; hp, stamina, posture full; data.rest_shrine == &"" and rest_shrine().id == &"rose_a"
func test_resting_fills_the_bars_sets_the_respawn_and_flags_the_shrine() -> void:
	# hp 10, posture broken, stamina 0: rest(rose_b) -> all full, not exhausted, data.rest_shrine == &"rose_b", flag(&"shrine:rose_b"), `rested` once with &"rose_b", `world_reset` once, `world_changed` once with &"shrine:rose_b"; resting there again: `rested` again, `world_changed` not again
func test_a_press_of_interact_within_a_shrines_radius_rests_and_one_outside_does_not() -> void:
	# the player 1.9 m from rose_b's plinth: interactor.current is the shrine, prompt_line() == "%s  Rest" % ControlsList.shown(&"interact", false); one InputFeed press of "interact" -> one rest; at 2.1 m: current null, the press does nothing
func test_nothing_is_interacted_with_while_dead_frozen_in_a_move_or_paired() -> void:
	# each state, a press, no `interacted`
func test_death_stands_him_up_at_the_last_shrine_after_three_seconds() -> void:
	# player.die(): `player_fell` once; alive false at 179 frames, true at 181; within 0.01 m of rose_a's respawn with full bars; `respawned` once; with rose_b rested first: at rose_b's respawn
func test_the_three_seconds_stand_still_in_a_pause_and_in_a_scene() -> void:
	# Game.change(PAUSE) for 120 frames, back: still dead until 180 more play frames; the same with Game.State.CUTSCENE
func test_every_shrine_is_standing_ground_and_clear_of_the_foes() -> void:
	# for both shrines: StretchGround.stands(respawn) and stands(plinth point 1.0 m toward the respawn); respawn within 2.0 m of its plinth; both in StretchGround.reached(region)
func test_set_flag_saves_through_the_store_and_announces_once() -> void:
	# a store in user://save_test/run: set_flag(&"x") twice: `world_changed` once; read() has flag x; with store null set_flag writes nothing and does not error
func test_the_state_hash_changes_with_the_world_and_not_with_the_clock() -> void:
	# equal runs hash equal; a rest, a flag, a moved player each change it; 120 paused frames do not
# tests/world/test_shrines.gd
func test_the_shrine_data_loads_through_the_registry() -> void:
	# Registry.fetch(&"stretch", &"rose_a") is a ShrineDef with the plinth above; Registry.fetch(&"stretch", &"bilibara") is a StretchDef whose shrines are rose_a, rose_b
# tests/hud/test_stretch_hud.gd
func test_the_prompt_line_is_the_interactors_and_is_empty_with_nothing_near() -> void:
func test_it_draws_nothing_while_the_hud_is_hidden_by_a_scene() -> void:
	# hud.suppressed = true -> the hud's shown_alpha() 0 and the stretch hud's draw list is empty (it exposes `draws() -> bool`)
# tests/main/test_main_stretch.gd
func test_parse_stretch_reads_the_three_forms() -> void:
	# [] "", ["--stretch"] "continue", ["--stretch=new"] "new", ["--stretch=old"] ""; and Main.parse_arguments of ["--stretch=new"] is still {"record": "", "replay": "", "replaying": false}
func test_f2_continues_the_saved_game_and_new_reads_and_writes_nothing() -> void:
	# main.save_dir = "user://save_test/main"; a saved game with petals 5 and rest rose_b: enter_stretch() -> run.data.petals == 5 and the player at rose_b's respawn; enter_stretch(true) -> petals 0, rose_a, and the files byte for byte unchanged after 60 frames
func test_the_yards_arena_never_begins_when_the_game_starts_in_the_stretch() -> void:
	# a Main with `stretch_start = "new"` set before it is ready: region is Bilibara, arena() null, no Enemy nodes anywhere
func test_leaving_the_stretch_saves_what_changed() -> void:
	# enter, set_flag(&"x"), switch_region(): the file has x; the run is gone with the region
func test_the_hud_follows_no_arena_and_has_a_stretch_hud_in_the_stretch_only() -> void:
# tests/replay/test_replay_stretch.gd
func test_a_stretch_session_replays_as_recorded_and_leaves_the_players_save_alone() -> void:
	# main.save_dir holds a valid save; --stretch=new with a recorder: ~300 frames (walk to rose_a's plinth, one interact, walk east); replay: finished, "as recorded"; the save folder's bytes equal before and after
func test_a_recording_made_in_the_stretch_is_refused_without_its_hash() -> void:
	# a stretch recording with `hashes` emptied: Main.replay_refusal is non-empty (the existing rule, now reachable)
```

- [ ] **Step 3: Run** `tools/test.sh --filter=test_stretch`, `--filter=test_shrines`, `--filter=test_main_stretch`, `--filter=test_replay_stretch` and `--filter=test_yard_hash_pin`. Expected: the first four FAIL (classes undeclared, `parse_stretch` missing); the pin passes.
- [ ] **Step 4: Implement.**
  - `ShrineDef`, `StretchDef`, `Interactable`, `Interactor`, `Shrine`, `StretchRun` as above; write `data/stretch/{rose_a,rose_b,bilibara}.tres` (the shrines referenced by the def).
  - `StretchGround`: lift the flood fill and the capsule test out of `tests/world/test_bilibara.gd` (same results; that file then calls `StretchGround`).
  - `shrine_glow.tscn` and `petal_burst.tscn`: pixel particles copied from `fx/hit_spark.tscn`'s setup, rose and gold, no light; `data/fx/petal_burst.tres` (`FxDef`, lifetime 0.8).
  - The cue: `make_sfx.py` gains `shrine_rest` (a low two-partial bell, 0.9 s, peak -12 dBFS, seeded like the others); run the tool, commit the WAV, add the `data/sounds/shrine_rest.tres` and the `ASSETS.md` row ("ours", made by `tools/audio/make_sfx.py`).
  - `InputRecorder`/`InputReplayer`: the two `arena.state_hash()` calls (recorder `close` and `_physics_process`, replayer `_physics_process`) go through one private helper that prefers `hash_of`.
  - `Main`: `_ready` takes `stretch_start` (else `parse_stretch` of the user arguments) and, when it is not empty or when a `--replay` recording's `region` is `BILIBARA`, goes to the stretch (a new game for `new` and for a replay) instead of starting the yard's fight; `_enter_region` makes the `StretchRun` (a `SaveStore.new(save_dir)` and its read, or none for a new game), puts a `StretchHud` under the Hud, and gives the recorder and replayer `stretch.state_hash`; `enter_stretch(new_game)` replaces F2's call; the camera snap on `respawned` is the run's own (it finds the rig by group).
- [ ] **Step 5: Look at it.** In the scratchpad, render the game's camera at `ShrineSite_A` and `ShrineSite_B` with the shrines in (`tools/godot.sh --render`, 640 x 360), read both PNGs: the glow is seen on the slate and not hidden by the lamp pools; note what is too faint for the owner.
- [ ] **Step 6: Run** the five filters again, `tools/test.sh --filter=tests/world`, `tools/test.sh --filter=tests/replay`, `tools/test.sh --filter=test_ledger`, then `tools/test.sh` and `tools/godot.sh -- --selftest` (exit 0). Expected: all pass, the pin included.
- [ ] **Step 7: Commit.** STATE.md Done line: "F3 Task 2 (systems): `StretchRun` (the stretch's run: the world's memory, rest, respawn), two rose shrines (rest: bars full, respawn point set, foes back, saved), `Interactor`, a stretch HUD line, death three seconds from the last shrine, `-- --stretch[=new]` and F2, and a hash source for the recorder and replayer so a stretch session replays `as recorded`; the yard's hashes are pinned." Owner checklist item: "Rest at both shrines, die, and stand up at the one you last rested at: is a press and no kneeling the right amount? Is the rose glow seen at the window's size?"

---

### Task 3: Petals and the corpse run

**Files:**
- Create: `world/stretch/{petal_tuning,petals,petal_pile}.gd`, `fx/petal_pile.tscn`, `data/stretch/petals.tres`, `data/sounds/{petal_gain,petal_wilt}.tres`
- Modify: `actors/actor_def.gd` (`petals`), `data/actors/{knuckle_1,knuckle_2,knuckle_3,knuckle_drummer,knuckle_blade,knuckle_heavy}.tres`, `world/stretch/{stretch_def,stretch_run}.gd`, `hud/stretch_hud.gd`, `tools/audio/make_sfx.py`, `ASSETS.md`
- Test: `tests/world/test_petals.gd`, `tests/hud/test_stretch_hud.gd` (more), `tests/actors/test_actor_petals.gd`

**Interfaces:**
- Consumes: Task 2's `StretchRun` (`data`, `player`, `region`, `respawn`, `player_fell`, `save_now`, `world_reset`), `SaveData.petals`, `.pile`, `.deaths`; `ActorFx.show_fx`; `Sfx.play`; `StretchGround.stands`; `Hud.picture_point`.
- Produces:
  - `ActorDef.petals: int` (`@export var petals := 0`: what the foe gives when it falls). Values: `knuckle_1` 10, `knuckle_2` 20, `knuckle_3` 40, `knuckle_drummer` 30, `knuckle_blade` 30, `knuckle_heavy` 60; every other def 0.
  - `class PetalTuning extends Resource` (kind `stretch`, id `petals`; `data/stretch/petals.tres`): `@export var drop_share := 1.0` (the share of carried petals left where he falls), `@export var wilt_seconds := 0.0` (0 = no clock), `@export var reach := 1.2` (metres: how near he comes to take them back). `StretchDef.petals: PetalTuning`.
  - `class Petals extends RefCounted`: `func _init(data: SaveData, tuning: PetalTuning)`; `signal gained(amount: int)`, `signal dropped(amount: int, at: Vector3)`, `signal taken(amount: int)`, `signal wilted(amount: int)`; `func carried() -> int`; `func gain(amount: int) -> void` (ignores amounts below 1); `func fall_at(at: Vector3) -> void` (an old pile wilts first, `wilted`; then `floori(carried * drop_share)` of the carried petals become the pile at `at` if that is above 0, `dropped`; `data.deaths` goes up by one in every case); `func pile_at() -> Variant` (a `Vector3` or null); `func pile_amount() -> int`; `func take_back() -> int` (the pile joins the carried petals, `taken`, returns the amount; 0 with no pile); `func tick(frames := 1) -> void` (ages the pile; with `wilt_seconds` above 0 it wilts at that many play seconds).
  - `class PetalPile extends Node3D` (`fx/petal_pile.tscn`: a slow rising column of pixel petals, rose and gold, no light, drawn on the world layer): `var amount: int`; freed by the run when the pile is taken or wilts.
  - `StretchRun` gains: `var petals: Petals`; `func watch_foe(foe: Actor) -> void` (when `foe.died` is emitted, once, `petals.gain(foe.def.petals)` and the dirty mark); `func mark_dirty() -> void` (the autosave tick writes the file when it was marked); `var last_stand: Vector3` (the last point the player stood on the floor alive, kept every frame, `y` 0 in the stretch). On `player.died`: `petals.fall_at(last_stand)`, a `PetalPile` at the pile, `player_fell`, and `save_now()` that very frame. Each frame the player, alive and in `PLAY`, within `tuning.reach` (flat) of the pile takes it back: the cue `petal_gain`, a `petal_burst` on him, a save. A pile in the loaded `SaveData` is drawn again at start. The state hash includes carried petals, the pile, the deaths.
  - `StretchHud` gains: `func petal_text() -> String` (the carried count as a plain number), `func gain_popup() -> String` ("+<n>" for 90 play frames after a gain, else ""), `func pile_marker() -> Dictionary` (`{}` with no pile; else `{point: Vector2i, arrow: bool}`: the pile's picture point from `Hud.picture_point(pile + Vector3.UP * 0.8)` when it is inside the picture inset by 6 px, otherwise that point clamped to the inset edge with `arrow` true); it draws the count at the top right in `Hud.GOLD` with a 5 x 5 rose diamond beside it, the popup under it, and the marker (a rose diamond, or a small arrow at the edge).
  - Cues `petal_gain` (a soft rising two-note chime, 0.5 s) and `petal_wilt` (a falling one, 0.6 s) from `make_sfx.py`, peak -14 dBFS.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/world/test_petals.gd   (the stretch with a started run, a store in user://save_test/petals; Abarax with the stretch's tuning)
func test_a_death_leaves_all_the_carried_petals_where_he_fell() -> void:
	# carried 120, die at (10, 0, 0): pile_amount() 120 within 0.01 m of that point, carried() 0, `dropped` once with (120, point), data.deaths 1, one PetalPile node there
func test_no_petals_means_no_pile_and_the_death_is_still_counted() -> void:
	# carried 0: pile_at() null, `dropped` never, deaths 1
func test_walking_into_the_pile_takes_it_back_and_clears_it() -> void:
	# after the respawn put him 1.1 m away: carried 120 on the next frame, `taken` once with 120, the PetalPile freed; at 1.3 m nothing is taken; dead, nothing is taken; in a pause, nothing
func test_a_second_death_before_the_pile_is_reached_wilts_it_for_good() -> void:
	# die at A with 120; respawn; kill two foes worth 10 and 20 (watch_foe); die at B: pile at B is 30, `wilted` once with 120, exactly one PetalPile, none at A
func test_dying_with_none_carried_still_wilts_the_old_pile() -> void:
func test_reaching_the_pile_then_dying_again_leaves_a_new_pile_of_everything() -> void:
func test_a_foe_gives_its_defs_petals_once_when_it_falls() -> void:
	# watch_foe on a knuckle_1: die() twice: carried 10 and `gained` once with 10
func test_the_petal_values_are_the_decided_ones() -> void:
	# knuckle_1 10, knuckle_2 20, knuckle_3 40, knuckle_drummer 30, knuckle_blade 30, knuckle_heavy 60, abarax 0
func test_the_clock_is_off_by_default_and_wilts_the_pile_when_set() -> void:
	# default tuning: 100000 frames later the pile is there; with wilt_seconds 2.0: wilted at 120 play frames, not at 119; a pause of 600 frames does not count
func test_the_file_written_at_the_moment_of_death_has_the_pile_and_the_shrine() -> void:
	# die with 120 carried, rested at rose_b: read the store that same frame: pile amount 120 at the point, rest_shrine rose_b, petals 0; a new run started from that read stands him at rose_b's respawn with the PetalPile drawn at the point and 0 carried; reaching it gives 120 (a quit in the three seconds loses nothing twice)
func test_dying_in_the_air_leaves_the_pile_on_the_ground() -> void:
	# die during a hop (the player's y above 0.3): the pile's y is 0 and StretchGround.stands(pile)
func test_a_pile_is_standing_ground_wherever_he_falls() -> void:
	# die at the 8 points next to a kerb, the gate board, the lane's mouth, a corner of the yard...: StretchGround.stands(pile) for each
func test_petals_gained_are_saved_by_the_next_event_or_the_autosave() -> void:
	# gain 20; no file change at once; after AUTOSAVE_FRAMES the file says 20; with nothing marked, no write (the file's modified time does not move)
# tests/hud/test_stretch_hud.gd, added
func test_petal_text_popup_and_marker() -> void:
	# carried 120 -> "120"; a gain of 20 -> popup "+20", gone after 90 play frames; a pile on screen -> {point near picture_point, arrow false}; one off screen -> point within the 6 px inset, arrow true; no pile -> {}
# tests/actors/test_actor_petals.gd
func test_every_def_has_a_petals_value_and_only_enemies_give_any() -> void:
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_petals`, `--filter=test_stretch_hud`, `--filter=test_actor_petals`. Expected: FAIL (`Petals`, `PetalTuning`, `ActorDef.petals` do not exist).
- [ ] **Step 3: Implement** as above. `Petals` holds no nodes and no clock of its own (the run ticks it with `Game.play_frames` deltas); the run owns the `PetalPile` node; the pickup check uses flat distance and the same gating as the interactor (alive, `PLAY`, no scene). Cues: `make_sfx.py`, WAVs, `data/sounds/*.tres`, `ASSETS.md` rows.
- [ ] **Step 4: Look at it.** In the scratchpad, render the game camera with a pile on cobble, on tan earth and on slate (640 x 360) and read the PNGs: the column is seen on each ground, not hidden by a lamp's pool; note for the owner whether it is too faint.
- [ ] **Step 5: Run** the three filters, `tools/test.sh --filter=tests/world`, `--filter=test_ledger`, `--filter=test_yard_hash_pin`, then `tools/test.sh`. Expected: all pass.
- [ ] **Step 6: Commit.** STATE.md Done line: "F3 Task 3 (systems): petals and the corpse run: foes give petals when they fall (`ActorDef.petals`), a death leaves what he carries where he fell, one chance to touch the pile before a second death wilts it (`PetalTuning`: no clock unless set), the count and the pile's marker on the HUD, saved at death, at pickup and on the autosave tick." Owner checklist item: "Die with petals, then run for them; die once more on the way: do the petals wilt as you expect, and can you see where the pile lies from across the street?"

---

### Task 4: Foes placed as encounters

**Files:**
- Create: `world/stretch/{placement,encounter_def,encounter_host}.gd`, `data/stretch/enc_street_pair.tres`, `enc_street_watch.tres`, `enc_lane_south.tres`, `enc_lane_north.tres`, `enc_rack_keeper.tres`, `enc_loop_straggler.tres`
- Modify: `actors/enemy_brain.gd` (home, leash, sleep, alarm), `world/stretch/{stretch_def,stretch_run}.gd`
- Test: `tests/actors/test_enemy_brain_home.gd`, `tests/world/test_encounters.gd`

**Interfaces:**
- Consumes: Task 2's run (`world_reset`, `tokens`, `serial`, `player`), Task 3's `watch_foe`; `Actor` (`place`, `die`, `got_hit`), `EnemyBrain`, `BrainDef`, `Locomotion.yaw_of`, `Melee.end_pairs_of`, `CameraRig.GROUP`, `StretchGround`.
- Produces:
  - `EnemyBrain` (new, all inert at their defaults, so the yard's fights do not move): `signal engaged` (emitted once each time it goes from noticing to engaged); `signal arrived_home`; `var home: Variant = null` (a `Vector3` post, or none); `var leash := INF` (metres, flat, from `home`); `var asleep := false`; `func wake() -> void` (awake, with the notice already built: it engages on its next think if it has a target, which it turns to face); `func engage_now() -> void` (an alarm: straight to ENGAGED, no noticing); `func going_home() -> bool`. Rules: asleep, `think` returns an empty intent (no turning, no looking, no perceiving); past `leash` from `home` while not idle it stands down (`_go_idle`), then walks home at the jog, ignoring the target, for at most 8 s, and on arriving (within 0.6 m) emits `arrived_home` and is idle again.
  - `class Placement extends Resource` (inline in an encounter): `@export var def: ActorDef`, `at: Vector3`, `facing_deg: float` (about +Y: 0 faces south, 90 east, 180 north, 270 west), `brain: BrainDef` (optional: handed to the foe in place of its def's), `brain_broken: BrainDef` (Task 6: handed instead once the encounter's squad is broken).
  - `class EncounterDef extends Resource` (kind `stretch`): `@export var id: StringName`, `placements: Array[Placement]`, `spawn_radius := 30.0` and `despawn_radius := 44.0` (metres from the mean of the posts), `sleeping := false`, `wake_radius := 7.0`, `alarm := true` (one member engaging engages the rest), `leash := 24.0`, `gone_if: StringName` (a world flag that keeps it from ever standing). Tasks 6 and 7 add `squad` and `boss`. `StretchDef.encounters: Array[EncounterDef]`.
  - `class EncounterHost extends Node` (child of the run, `name = "Encounters"`): `signal spawned(id: StringName, foes: Array[Actor])`, `signal despawned(id: StringName)`, `signal cleared(id: StringName)`; `func foes(id: StringName) -> Array[Actor]`; `func all_foes() -> Array[Actor]`; `func killed(id: StringName) -> PackedInt32Array` (the indices of the placements that fell since the last reset); `func reset_all() -> void` (every live foe is removed as `Arena.clear_foes` removes one: pairs ended through `Melee.end_pairs_of`, the player's move stopped if he was in one, his lock and the camera's lean let go, `remove_child` then `queue_free`; the killed lists are cleared; run on `world_reset`); `func hash_part() -> Array`. Every 15 play frames it streams: an encounter with no live foes whose centre is within `spawn_radius` of the player stands its placements that are not in `killed` and not `gone_if`-flagged; one whose foes are all unengaged and whose centre is beyond `despawn_radius` is removed (the killed stay killed). A foe is named `<encounter id>_<index>`, takes `spawn_count = run.serial` (then `run.serial += 1`), is placed at `at` facing `facing_deg`, is watched for petals (`run.watch_foe`), has `home = at` and `leash`, and is `asleep` when the encounter sleeps. A sleeper wakes (its encounter with it) when the player comes within `wake_radius` of any member or any member is hit; with `alarm`, a member's `engaged` calls `engage_now` on the rest.
  - **Data (the plan's placements, x east, z south; `facing` as above):**

| Encounter | Who | Posts (x, z) | Facing | Notes |
|---|---|---|---|---|
| `street_pair` | 2 x `knuckle_1` | (-14, -1.5), (-12, 2.0) | 270 | the street's first foes, 18 m from the first shrine |
| `street_watch` | `knuckle_2`, `knuckle_1` | (3, 2.0), (5.5, -2.0) | 270 | before the Collector's end of the street |
| `lane_south` | `knuckle_blade` | (27.5, -14) | 0 | in the lane, beyond the toll gate |
| `lane_north` | `knuckle_drummer` | (27.5, -46) | 0 | `sleeping`, `wake_radius` 6; 14 m from the second shrine |
| `rack_keeper` | `knuckle_heavy` | (8, -22.5) | 90 | the Rack Walk |
| `loop_straggler` | `knuckle_1` | (-32.5, -14) | 180 | the loop lane, before the latch |

  (the Pack is Task 6's, the Collector Task 7's.) Every `at` has y 0.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/actors/test_enemy_brain_home.gd   (a bare Region with ground; a knuckle_1 with an EnemyBrain; the target an Actor with Brain.new())
func test_an_asleep_foe_notices_nothing_and_wakes_into_the_fight() -> void:
	# target 2 m ahead in plain sight, asleep: 120 frames later mode IDLE, position and facing unchanged, no presses; wake(): ENGAGED within 2 frames
func test_a_foe_past_its_leash_gives_up_and_walks_home_and_ignores_the_target_on_the_way() -> void:
	# home (0,0,0), leash 6; the target runs to 10 m; `going_home()` within 2 frames; no attack started while going home even with the target 1 m away; back within 0.6 m of home in (distance / 5.5 + 2) s; `arrived_home` once; then IDLE, and engages again when the target is in sight
func test_the_walk_home_gives_up_after_eight_seconds() -> void:
	# a foe walled off from home: going_home() false by 8.1 s, no error
func test_engage_now_skips_the_noticing() -> void:
	# IDLE, target behind it out of sight: engage_now(): ENGAGED on the next think; `engaged` once
func test_the_signal_engaged_comes_once_per_engagement() -> void:
func test_with_no_home_and_no_leash_nothing_is_different() -> void:
	# the existing brain tests are the proof (run them); plus: a default brain never emits arrived_home, going_home() false
# tests/world/test_encounters.gd   (the stretch region, a run, Abarax a child of the region with Brain.new())
func test_the_encounter_data_loads_and_uses_only_the_existing_foes() -> void:
	# six encounters by id above; every placement's def in {knuckle_1, knuckle_2, knuckle_blade, knuckle_drummer, knuckle_heavy} at this task; 4 archetypes (Knuckle, blade, Drummer, heavy)
func test_the_posts_are_where_the_table_says() -> void:
	# each placement's at within 1e-3 of the table, facing_deg equal
func test_every_post_is_standing_ground_and_far_from_every_respawn() -> void:
	# StretchGround.stands(post), StretchGround.clearance(post) >= 0.6, post in reached(region) (the toll gate is Task 5's: reached from a region with no gate boards), flat distance to every shrine's respawn >= 12 m, and no two posts of different encounters within 3 m
func test_foes_stand_in_when_he_comes_near_and_out_when_he_goes_far() -> void:
	# at 31 m from street_pair's centre: no foes after 30 frames; at 29 m: two within 15 frames, each at its post within 0.05 m and 1 degree of its facing; at 46 m, unengaged: none within 15 frames
func test_a_foe_is_named_for_its_post_takes_the_serial_and_is_watched() -> void:
	# names street_pair_0, street_pair_1; spawn_count 0 and 1 from a fresh serial; killing one pays 10 petals
func test_the_killed_stay_dead_while_he_walks_about() -> void:
	# kill street_pair_0, go beyond despawn_radius, come back: one foe (index 1) at its post, killed(id) == [0]
func test_rest_and_death_bring_every_foe_back_healed() -> void:
	# kill one, hurt the other; rest(rose_a): after the streaming tick two full-HP foes at their posts, killed(id) empty; the same after die + the three seconds
func test_a_sleeper_wakes_by_nearness_by_a_blow_or_by_the_alarm() -> void:
	# lane_north asleep: at 6.5 m for 120 frames nothing; at 5.9 m it engages; a fresh one hit from 10 m engages; with alarm, a member that engages engages the other (use street_pair, awake)
func test_a_foe_that_leaves_its_leash_walks_home_and_is_healed() -> void:
	# lure street_pair_0 past 24 m; arrived_home: hp == max, within 0.6 m of its post
func test_the_dice_are_seeded_and_a_respawn_rolls_new_ones() -> void:
	# two runs with start_seed(1) and the same walk: equal state_hash after 300 frames; start_seed(2) differs; a second spawn of the same post has a different spawn_count than the first
func test_the_hash_includes_the_encounters() -> void:
	# a killed foe, a despawned encounter each change state_hash
func test_the_hud_shows_a_stretch_foes_bars_and_the_lock_finds_it() -> void:
	# a foe hit by the player: Hud.foe_bars() has it (no arena needed); LockOn picks it within 3.5 m
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_enemy_brain_home` and `--filter=test_encounters`. Expected: FAIL (`home`, `asleep`, `wake`, `Placement`, `EncounterHost` do not exist).
- [ ] **Step 3: Implement** the brain's additions first (the six brain tests), then the data classes and the host, then the six `.tres` files. The host's removal copies `Arena.clear_foes`'s steps (do not edit the arena: the yard is pinned); streaming and the despawn test use `Game.play_frames` so a pause stands them still.
- [ ] **Step 4: Run** the two filters, then `tools/test.sh --filter=tests/actors` (the existing brain, ranges and token tests are the proof that nothing moved), `--filter=test_yard_hash_pin`, `tools/clip_check.gd` (unchanged: 67 moves, 7 actors OK or whatever the tree says before), then `tools/test.sh`. Expected: all pass.
- [ ] **Step 5: Commit.** STATE.md Done line: "F3 Task 4 (systems): foes placed as encounters (`EncounterDef`, `Placement`, `EncounterHost`): they stand in as the player nears and out beyond, wake by sight, nearness, a blow or an alarm, walk home past their leash and are healed, come back on a rest or a death and stay dead otherwise; six encounters of the four kinds of foe in the street, the lane and the Rack Walk; `EnemyBrain` has a home, a leash, sleep and an alarm (inert by default)." Owner checklist item: "Walk the stretch with no fight in mind: does each foe stand where you would expect it, with room to see it coming, and does one that loses you walk home rather than vanish?"

---

### Task 5: Gates and the shortcut loop

**Files:**
- Create: `world/stretch/{gate_def,gate_door,latch}.gd`, `data/stretch/gate_shortcut.tres`, `data/stretch/gate_toll.tres`, `data/sounds/gate_unlatch.tres`
- Modify: `world/stretch/{stretch_def,stretch_run}.gd`, `hud/stretch_hud.gd`, `tools/audio/make_sfx.py`, `ASSETS.md`, `tests/world/test_encounters.gd` (opens the gates before its flood fill)
- Test: `tests/world/test_gates.gd`, `tests/world/test_shortcut_loop.gd`

**Interfaces:**
- Consumes: Task 2's `Interactable`, `StretchRun.set_flag`, `flag`, `world_changed`; the layout's `Gate` node (a `StaticBody3D` on `world` and `ik_surface`, the 0.6 m slate board at x -35..-30, z -5.5..-4.5) and the markers `GateFar` (-32.5, -6.5) and `GateNear` (-32.5, -3.5); `res://world/materials/slate.tres`; `Layers`.
- Produces:
  - `class GateDef extends Resource` (kind `stretch`): `@export var id: StringName`; `opens_on: StringName` (the world flag that opens it); `nodes: PackedStringArray` (existing nodes of the region it lowers, by name); `board: Rect2` (x, z, width, depth: when not empty the gate builds its own slate board here, 0.6 m high, a `StaticBody3D` named `<id>` on `world | ik_surface`, no rail, no posts); `drop := 1.3` (metres a board sinks); `latch_centre: Vector3` and `latch_radius := 3.0` (a gate with `latch_radius` above 0 has a latch); `open_side: Vector2` (the unit direction, x and z, from the gate toward the side it can be lifted from); `latch_prompt := "Lift the bar"` and `barred_prompt := "Barred from the other side"`. `StretchDef.gates: Array[GateDef]`.
  - `class GateDoor extends Node` (one per gate, children of the run named `Gate_<id>`): `func open(animated := true) -> void` (the board's collision layer is 0 at once; it sinks `drop` over 45 play frames, then is hidden; unanimated it is open now); `func is_open() -> bool`; opened on `world_changed(opens_on)` and, with no animation, at start when the flag is already set.
  - `class Latch extends Interactable`: `prompt` is `latch_prompt` on the open side and `barred_prompt` on the other; `interact` on the open side sets the gate's flag (the cue `gate_unlatch`) and on the other does nothing.
  - `StretchRun.gates: Array[GateDoor]`; the `StretchHud` shows the barred prompt as it shows any prompt.
  - **Data:** `gate_shortcut` (`opens_on` `shortcut_open`, `nodes` ["Gate"], no board, `latch_centre` (-32.5, 0, -5), `open_side` (0, -1), the loop lane's side); `gate_toll` (`opens_on` `collector_down`, `board` Rect2(25, -5.5, 5, 1.0), no latch: nothing lifts it but the flag).
  - The cue `gate_unlatch` (a dry wooden clunk and a slide, 0.5 s, peak -14 dBFS).

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/world/test_gates.gd
func test_the_gate_data_loads() -> void:
	# gates shortcut and toll by id; flags shortcut_open and collector_down; the toll board is Rect2(25, -5.5, 5, 1.0)
func test_a_gate_whose_flag_is_set_loads_open_and_one_without_loads_shut() -> void:
	# data.flags {shortcut_open}: `Gate`'s collision_layer 0 and hidden at the first frame, the toll board shut (layer WORLD | IK_SURFACE, top at y 0.6); with no flags both shut
func test_setting_the_flag_opens_a_gate_over_forty_five_frames_without_a_pop() -> void:
	# collision layer 0 on the very frame; the board's y falls every frame by at most 0.04 m to -1.3 at frame 45, hidden after; is_open() true
func test_the_latch_lifts_only_from_the_open_side() -> void:
	# at GateFar: interactor.current is the latch, prompt "Lift the bar", one `interact` press sets shortcut_open, `world_changed` once; at GateNear: prompt "Barred from the other side", a press sets nothing
func test_a_built_board_holds_a_shove_and_a_dash_step_until_its_flag() -> void:
	# the toll board: shoved from the street for 3 s, the centre stays south of z = -5.0 + 0.35 + 0.05 and y < 0.05; with collector_down set and 60 frames, the same shove goes through to z < -8
func test_an_open_gate_changes_the_walkable_set_by_no_more_than_the_gate_board() -> void:
	# StretchGround.reached(region) with every gate open equals the plain scene's reached set plus the lane and everything past it (and nothing outside the seven places)
func test_the_gates_survive_a_rest_a_death_and_a_load() -> void:
	# open; rest; die + 3 s; a new run from the saved file: both still open as they were
# tests/world/test_shortcut_loop.gd
func test_the_shortcut_cuts_the_first_shrines_way_to_the_rack_walk() -> void:
	# flood-fill path length (0.5 m cells, 4-neighbour, metres) from rose_a's respawn to RackWest with the toll gate open: shut shortcut >= 135 m, open <= 30 m
func test_abarax_walks_the_loop_from_its_far_side_and_opens_the_gate() -> void:
	# collector_down set; RouteBrain over LaneMid, RackEast, RackWest, GateFar (each leg within leg / 4 + 3 s, 0.6 m), then one `interact` press: shortcut_open set within 2 frames, and he walks GateFar -> GateNear through the gate (a leg of 3 m in under 3 s); the same walk shut stops at the board
func test_after_it_is_open_the_first_shrine_to_the_rack_walk_is_a_short_walk() -> void:
	# from rose_a's respawn over GateNear, GateFar, RackWest: RouteBrain done within 12 s
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_gates` and `--filter=test_shortcut_loop`. Expected: FAIL (`GateDef`, `GateDoor`, `Latch` do not exist).
- [ ] **Step 3: Implement.** `GateDoor` finds the named nodes under the region; a built board uses `slate.tres` and a `BoxShape3D` of the rect by 0.6 m (the same box the layout's `Gate` is); `Latch` and the doors are made by the run from `def.gates`. Update the Task 4 flood-fill test to call `door.open(false)` on every gate first.
- [ ] **Step 4: Look at it.** In the scratchpad, render the camera at `GateNear`, `GateFar` and the lane's mouth with the toll board shut and open; read the PNGs: the toll board reads as the shortcut's twin and hides no body behind it (the stretch plan's low-gate rule: nothing taller than 1.3 m).
- [ ] **Step 5: Run** both filters, `tools/test.sh --filter=tests/world`, `--filter=test_ledger`, `--filter=test_yard_hash_pin`, then `tools/test.sh`.
- [ ] **Step 6: Commit.** STATE.md Done line: "F3 Task 5 (systems): gates and the shortcut loop: `GateDef`/`GateDoor`/`Latch`; the street's west gate lifts from the loop lane's side only and joins the first shrine to the Rack Walk (about 24 m instead of 142 m); a slate toll board across the lane's mouth waits for the mini-boss's flag; open gates stay open through rest, death and load." Owner checklist item: "Walk the loop, lift the bar at the gate and run back to the shrine: is the shortcut a relief, and does the barred prompt from the street say enough?"

---
