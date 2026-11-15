# The Stretch's Systems (shrines, petals, saves, foes, the Pack, the Collector) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the built Bilibara stretch into a level that can be played, lost and won: rose shrines to rest at, petals that drop and wait where Abarax fell, a save that keeps up with him, one shortcut loop, four kinds of foe standing where they should, one gank squad with a secret weakness, and a mini-boss whose fall opens the way on.

**Architecture:** One node, `StretchRun`, is added under the stretch's region when it is entered; it owns the world's memory (`WorldMemory`), the petals, the encounters, the gates and the boss, and reads everything about the place from data (`data/stretch/*.tres`, `data/items/`, `data/squads/`, `data/bosses/`). Places are marker names and coordinates in that data, not code and not new layout lines (one exception, Task 5's toll gate). The save is a small JSON file written through a temporary file with a backup, never touched by a test, a recording, a replay or the bot. Foes are the six that exist, placed by data and given a few new, optional habits (home and leash, sleeping, squad hints) in `EnemyBrain`.

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
11. **What the mini-boss's fall opens:** the toll gate across the lane's mouth (a low gate like the shortcut's, built in the layout). The yard beyond stays plain: First Knuckle's door is F5's.

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
