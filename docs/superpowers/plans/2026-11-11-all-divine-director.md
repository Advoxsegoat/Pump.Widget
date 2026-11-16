# The Director Implementation Plan (events lane: storyboard, animatic, playable scene)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A written scene becomes a checked shot list, a storyboard sheet of real engine frames, an animatic video and a playable scene (cutscene, mini-cutscene or combat moment) that glides out of play and back with no cut, proven on one fixture scene.

**Architecture:** A scene is data (`scenes/story/<scene>/shots.tres`: a `SceneShots` of `Shot`s). A pure `ShotChecker` reports what the data names that does not exist. A pure `TimelineBuilder` turns the data into an editable `AnimationPlayer` timeline; a `Director` node plays it: it hands cast actors a `DirectorBrain`, drives the existing `CameraRig` through one new additive "cine layer", and draws letterbox and dialogue in its own overlay in the HUD viewport. The tools run the same Director over the real yard and photograph or record it.

**Tech Stack:** Godot 4.7.2, typed GDScript, the project's own test runner (`tools/test.sh`), Movie Maker plus ffmpeg for the animatic, Node and Playwright (as `all-divine-tactics/tools/render-icons.mjs` already uses) to bring the book's portraits in.

**Spec:** `docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md`, sections 7 (all), 2, 3.1, 8, 9. This plan is the tool half of F4.

> **Built in a lane.** This plan is built in its own git worktree beside other lanes (combat, enemies, the world, menus),
> under the lane rules in this plan's workspace (`lanes.md`): the lane never pushes; STATE.md's Done lines and the owner's
> checklist items are given in each task's report and applied by the controller at the merge; the render suite is run as
> `TEST_TIMEOUT=3600 tools/test.sh --render`, because the machine is shared. The menus lane adds a `camera/dips` setting:
> Task 4's switch for the dip is wired to it by the controller when both lanes are merged.

## Global Constraints

- Everything lives in `all-divine/`. Paths below are under it unless they start with `docs/`.
- **Scene folder (spec 7.1):** `scenes/story/<scene>/` holds `script.md` (the owner's words), `shots.tres` (a `SceneShots`, `id` equal to the folder name) and `notes.md` (the owner's notes, one `## Rev N` entry per revision, the last line `Status: draft|in review|approved`). These three are all that is committed per scene. Storyboard sheets and animatics go to `out/story/<scene>/` (git-ignored, like all of `out/`).
- **The picture is 640×360**, drawn at whole-number scale. The Director's camera zoom is a whole number 1 to 4 at rest (one world pixel becomes `zoom`×`zoom` picture pixels); the camera snaps to `TEXEL / zoom`. Letterbox is 2.35:1: bars of exactly 44 px top and bottom (picture 640×272). Dialogue and bars are drawn in whole picture pixels in the HUD viewport.
- **Time is in frames, 1/60 s physics ticks.** Every time in the shot data is an `int` frame count. Shots are back to back: shot N starts on the frame shot N-1 ends.
- **Content is data, never code.** A scene is a `.tres` and two text files. A new scene needs no code change. The `timeline` the Director builds is an `AnimationPlayer` animation that the owner can open and edit in the Godot editor; a `SceneShots.timeline` scene, when set, plays instead of the generated one.
- **No cuts to black, no loading screens.** Between play and scene the camera glides; the only shapes that cover the picture are the two bars (at most 88 of 360 rows, 0.245). Nothing fades the picture to a colour.
- **One way to animate:** a cast actor is posed by its rig and clips (`Rig.play_move`), moved by its brain's `Intent`. Nothing in `story/` draws or moves a body any other way.
- **Layers:** `story/` is the Cinematics layer (spec 2.1, 7). It talks downward through public APIs only: `Actor.set_brain`, `Actor.place`, `Actor.rig`, `Rig.play_move/stop_move/set_move_time`, `MoveRunner.stop`, `CameraRig` (the cine layer), `Sfx.play`, `Game.change`, `Registry`, and the read-only `Melee.slowed()`. It never writes stats, hit events or combat state, and no other layer calls into `story/` except `Main`'s one debug key.
- **Assets:** free and open only; every file under `assets/` has a row in `ASSETS.md` (`tests/tools/test_ledger.gd`). Portraits and the voice blip are `ours`.
- **Green runs print no `ERROR:` or `WARNING:` lines.** A scene that cannot start is returned as data (`Director.play` returns null and the `refused` reason is a `StringName`), never `push_error` or `push_warning`; `Game.change` is only called from a state it allows.
- Commit messages start `All-Divine F4: `, end with the attribution trailers the session specifies, and never name a model. Probes and scratch files live in the session's scratchpad.
- **The numbers of this plan (change them in one place each: `Director` constants, the overlay's constants, `data/tuning/story.tres`):**

| What | Value |
|---|---|
| Glide in / out (frames) | `lead_in` and `lead_out` on the scene: default 30 and 30 (mini), 45 and 30 (cutscene); allowed 20 to 90 |
| Scene length incl. glides | cutscene: 120 frames or more; mini: 180 to 360 (3 to 6 s); combat moment: 90 at most (1.5 s) |
| Wait to start (settle) | 36 frames at most; 90 if a required actor is in a pair (a finisher is 90 at most) |
| Return blend (clip to locomotion) | 15 frames before the last shot ends |
| Skip: glide out | 20 frames |
| Pose match at hand-back | every bone within 4 degrees of the same actor standing in locomotion idle |
| Arrival at a mark | within 0.12 m |
| Camera | pitch -15 to -65 degrees (gameplay -40), yaw any, zoom 1 to 4, glide eased by smoothstep |
| Framing defaults (zoom) | wide 1, medium 2, close 3, over-the-shoulder 2, insert 4 |
| Letterbox | bars 44 px, slide in over 30 frames |
| Dialogue | box 620×64 px at 10 px from the sides and 10 px above the bars (or the picture's bottom), portrait 48×48 at 8 px inside it, typewriter 30 characters a second, one blip every 2 characters, at most 160 characters, 3 lines |
| A line's minimum hold | its typing time plus 20 frames |

## Review Focus

Five conditions the tasks' main tests would not reach on their own, most likely to hurt first:

1. **A scene that starts at a bad moment for Abarax:** mid-jab, charging a heavy, in a hop, in a sway, with the guard up, on the dodge-chain, mid-finisher, or off the floor. His move ends cleanly (no hitbox left on, no iframes or window left open, no stance left), his pose does not pop at the first frame, and he is where he stood. Tests in Task 3.
2. **A cast actor who is dead, absent, or paired.** A required actor who is missing or dead refuses the scene (play returns null, game state, brains and nodes untouched); an optional one drops out with its beats and the scene plays; one that is paired in a finisher is waited for (at most 90 frames) and then the scene starts, or is refused. Names that resolve to nothing are caught earlier, by the checker. Tests in Tasks 1 and 3.
3. **A skip pressed at the worst frame:** the first (inside the glide in), the last (after hand-back), twice, on a first viewing (refused), and during the wait to start. One end state (cast at their last marks within 0.15 m, brains handed back, the camera back on play, `finished` emitted once, the game in PLAY) however the scene ended. Tests in Task 3.
4. **A scene that starts in a hit-stop or the slow-down.** `Melee.slow` and hit-stop are freezes of the actors' own frames, so a Director that started its clock then would stutter every clip and arrive late. The clock starts when no cast actor is frozen and no slow is running (36 frames at most), and the world hold (non-cast actors frozen by the Director) never lengthens a freeze already on. Tests in Task 3.
5. **A shot list with a gap, an overlap, a line that cannot finish, or a walk that cannot fit.** Reported by the checker with the frames and metres, and the timeline builder refuses to build one. Tests in Tasks 1 and 2.

---

## Facts the tasks rely on (read from the code, 2026-11-11)

- **There is no camera dip yet.** `Actor.combat_moment(kind)` (`&"finisher"` or `&"grab"`, emitted on both fighters by `Actor.start_paired`) exists as a hook "for F4's camera dip and slow-motion beat"; nothing listens. Task 4 builds the dip on the cine layer. The slow-motion beat already exists as `Melee.slow(frames, share)`.
- `CameraRig` is an orthographic camera at pitch -40, yaw 0, `ORTHO_SIZE` 11.3125 m (362 px at 32 texels per metre), snapped to `PixelSnap.TEXEL`, with the sub-pixel handed to `PixelStage.subpixel`; its depth of field focus is `focus_distance()` to its `target`; `shake(strength)`/`trauma` exist; `yaw()` is read by the player's brain. The rig joins group `camera_rig`.
- `Game.State.CUTSCENE` exists (PLAY goes to it, it goes only to PLAY). `Main` handles `menu` only in PLAY and PAUSE, so `menu` is free during a scene: it is the skip key. No saving exists yet.
- `Actor.set_brain(b)` hands an actor over from the next frame; one handed before the actor is ready is kept (the def's enemy brain does not replace it). An enemy def's own brain is `EnemyBrain.new(def.brain, hash("%s#%d" % [name, spawn_count]))`.
- `Rig.play_move(clip, blend_in)` plays any clip of the rig's library, not only moves; nothing advances its time except `Rig.set_move_time(t)`, which `MoveRunner` calls for moves. Marks only fire from `MoveRunner`, so a raw clip never makes a hitbox or a sound. `Rig.stop_move(blend_out)` fades back to locomotion. `MoveRunner.stop(blend_out)` ends a move cleanly (hitboxes off, windows closed, airborne off).
- A body walks by `Intent.move` (a push 0 to 1; the reel walks at 0.45 and runs at 1.0), and faces by `Intent.face_target`. `Main._leg` has the formula for the frames a push takes to cover a distance.
- `Melee.slow` and hit-stop both work by `Actor.freeze`. `Melee.slowed()` says whether a slow is running. `Actor.paired_with` and `pair` say an actor is in a finisher or grab.
- `Registry` reads only `res://data/`; `Registry.fetch(&"sounds", id)` finds cues; a new kind is a new folder under `data/` (`speakers`).
- The HUD is drawn in the `PixelStage` hud viewport (exactly 640×360, drawn at the stage's integer scale), with `ThemeDB.fallback_font` at size 8, outline 3 in `Hud.INK`, `Hud.WHITE` text.
- `tools/sheets/contact_sheet.gd`, `tests/support/clip_shots.gd` (a stage built under a host, a camera, `await RenderingServer.frame_post_draw`), `demo/demo_reel.gd` (`extends Main`, scene `demo/demo_reel.tscn` instances `main/main.tscn`, ScriptBrain choreography, `--reel-log`) and `tools/record_reel.sh` (temporary `override.cfg` makes the window 640×360, `--write-movie ... --fixed-fps 30`, ffmpeg nearest-neighbour ×2) are the patterns the tools follow.
- The training yard (`world/training_yard/training_yard.tscn`) is 25×25 m inside walls, `Spawn` at (0, 0, 7) facing north, `EnemySpawn_1..4` in the north arc, a low kerb on the south. The clip library has `idle`, `walk`, `jog`, `guard_raise` (14 frames), `guard_hold` (a loop), `knuckle_idle` (a loop, arms folded), `knuckle_feint` (30 frames); the Knuckle shares Abarax's skeleton and library.
- **The book's portraits are code, not files.** `all-divine-tactics/web/index.html` (the earlier Tactics game, one bundled file) draws every portrait procedurally: `AD.spr.portrait(look, expression)` returns a 48×48 canvas, with no randomness. Looks are in `AD.PORTS[id]` (the playable cast by id: `abarax` (the cook look), `noella`, `sierra`, `kesra`, and story-only looks such as `goldtooth`). Expressions in the painter: `neutral`, `smile`, `smirk`, `grin`, `serious`, `angry`, `sad`, `cry`, `surprise`, `blush`. The game's text blip is `case 'text'` in its sound table: a 12 ms pulse near 990 Hz (plus up to 60 Hz of jitter). The Tactics game has no Knuckle. Nothing here can be loaded by Godot as it stands, so Task 1 renders PNGs through the asset ledger.

## Decisions this plan makes where the spec leaves room

- **Framing is a whole-number zoom of the orthographic camera.** In a fixed-pitch ortho view a dolly changes nothing and a zoom by a fraction blurs the pixel grid, so wide/medium/close/insert are zooms 1/2/3/4, a "dolly" is a zoom ramp between whole numbers, a crane a pitch ramp, an orbit a yaw ramp, a pan an aim ramp, handheld a trauma level. Over-the-shoulder is a yaw placed behind the foreground actor. No `Path3D` is generated: with the pitch fixed and the camera orthographic, a path with look-at is exactly aim, yaw, pitch and zoom tracks, and those are what the editable timeline holds. (Zoom is eased as a float during a glide and is a whole number at rest; Task 2 pins both.)
- **A raw clip, not a move, is what a shot plays.** A shot names clips of the rig's library (`guard_raise`), so a scene may use clips that are no move (`knuckle_idle`) and never fires a mark. Walking is `move_to` on the brain, and a walk's duration comes from the locomotion numbers, not from the shot: the checker proves it fits.
- **A scene is kind CUTSCENE, MINI or MOMENT and differs only in data and in what the Director does at the edges:** CUTSCENE letterboxed, state CUTSCENE; MINI no bars, state CUTSCENE; MOMENT no bars, no state change, no cast taken, one shot, 90 frames at most.
- **Control returns when the camera starts to glide out**, not when it has arrived, so a mini-cutscene never stalls; `CameraRig.yaw()` keeps answering the gameplay yaw during the glide so the sticks do not turn with it.
- **First viewing is unskippable, later viewings skippable by `menu`.** "Seen" is `StoryLog`, held in memory for the run; saving it is the save task's job.
- **Music is recorded and signalled, not played** (`Director.music_cue`): there is no music system yet. The animatic is silent (Movie Maker under a dummy audio driver); sound and music cues show as captions in its burn-in.
- **The fixture's Knuckle has no portrait in the book;** `fixture_knuckle` borrows `goldtooth`'s look and says so in its name.
- **Placeholder clips are allowed in drafts:** a beat marked `placeholder` may name a clip the library lacks (the animatic holds idle and captions it); a scene with status `approved` may have none.

## Working in this lane

This plan is built in its own git worktree beside lanes changing combat, enemies, the world and UI.

**Must not touch:** `combat/`, `moves/`, `data/moves/`, `data/brains/`, `data/actors/` (read only: the Director uses them), `actors/enemy_brain.gd` and the enemy brain files, `world/` (every region scene, `arena.gd`), `data/arena/waves.tres`, `assets/anim/` and `tools/anim/` (no clip is made here), `project.godot` (no autoload is added), `.github/`. Where a scene needs a mark in the world it names a position in `shots.tres`; the region scene is not edited.

**Shared files changed with care (smallest additive change; do not reformat or reorder anything):**
- `render/camera_rig.gd` (Task 2): add `var cine: CinePose`, `var cine_weight := 0.0`, `func gameplay_pose() -> CinePose`, and in `_apply`, `yaw`, `focus_distance` a branch taken only when `cine_weight > 0.0`. With the weight at 0 every existing line behaves as now; `tests/look/test_camera_rig.gd` and `test_camera_shake.gd` must pass unchanged.
- `hud/hud.gd` (Task 2): one member `var suppressed := false` and one line at the top of `_draw`: `if suppressed: return`. The letterbox and the dialogue are not in this file: they are in the new `hud/cine_overlay.gd`, added as a sibling of the Hud in the same viewport at run time (`hud.get_parent().add_child`), so `hud.tscn` and `main.tscn` are not edited.
- `main/main.gd` (Task 4): one `KEY_F10:` arm in `_unhandled_input` that calls `Director.play(&"fixture_yard_entrance", self)`, and nothing else; the self-test and the arena are untouched.
- `ASSETS.md` (rows appended at the end of the table) and `STATE.md` (Done lines under their own sub-heading `### The Director` and an owner checklist `## Owner checklist for the Director`; never edit the other lanes' lines). Test support files are new files prefixed `story_` in `tests/support/`.
- New top-level folders: `story/` (runtime), `scenes/story/` (content), `tools/story/` (tool scripts), `tests/story/`, `assets/portraits/`, `data/speakers/`.

## File structure

```
story/       scene_shots.gd shot.gd actor_beat.gd dialogue_line.gd cue_event.gd cast_entry.gd scene_mark.gd speaker.gd   (data)
             shot_checker.gd   timeline_builder.gd   cine_pose.gd   cine_camera.gd   (T1, T2)
             director.gd director_brain.gd story_log.gd   (T3)   moment_cam.gd story_tuning.gd   (T4)
hud/         cine_overlay.gd (new)   hud.gd (suppressed)
render/      camera_rig.gd (the cine layer)
data/        speakers/*.tres   sounds/voice_blip.tres   tuning/story.tres   story/moments/finisher.tres
assets/      portraits/<id>/<expression>.png   audio/sfx/voice_blip.wav
scenes/story/fixture_yard_entrance/   script.md shots.tres notes.md
tools/       story_check.gd   storyboard.sh   animatic.sh   portraits/export_portraits.mjs   audio/make_blips.py
             story/story_reel.gd story_reel.tscn storyboard_page.gd
tests/       story/ (all tests of T1 to T4)   render/test_story_shots.gd   tools/test_storyboard_page.gd
```

---

### Task 1: Shot data, speakers and the shot checker

**Files:**
- Create: `story/scene_shots.gd`, `shot.gd`, `actor_beat.gd`, `dialogue_line.gd`, `cue_event.gd`, `cast_entry.gd`, `scene_mark.gd`, `speaker.gd`, `shot_checker.gd`
- Create: `tools/story_check.gd`, `tools/portraits/export_portraits.mjs`, `assets/portraits/<id>/<expression>.png` (30 files), `data/speakers/{abarax,noella,sierra,kesra,fixture_knuckle}.tres`
- Create: `scenes/story/fixture_yard_entrance/{script.md,shots.tres,notes.md}`
- Modify: `ASSETS.md`, `STATE.md`
- Test: `tests/story/test_shot_data.gd`, `tests/story/test_shot_checker.gd`, `tests/story/test_speakers.gd`

**Interfaces:**
- Consumes: `Registry.fetch/ids`, `ActorDef` (`rig_scene`, `locomotion`, `team`), `Rig.tree`, `Locomotion.new(tuning).target_speed(push, sprint)`, the `sounds` kind.
- Produces (all `Resource`s with `class_name`; frames are `int`, metres `float`, degrees `float`):
  - `SceneShots`: `enum Kind {CUTSCENE, MINI, MOMENT}`, `enum Status {DRAFT, IN_REVIEW, APPROVED}`; `id: StringName`, `kind: Kind`, `status: Status`, `revision: int = 1`, `region: String` (a scene path, or `""` for the live region), `letterbox: bool`, `lead_in: int = 30`, `lead_out: int = 30`, `cast: Array[CastEntry]`, `marks: Array[SceneMark]`, `shots: Array[Shot]`, `timeline: PackedScene` (null: built from the shots). `func length() -> int` (sum of shot lengths), `func total_frames() -> int` (`lead_in + length() + lead_out`), `func shot_at(frame: int) -> int` (index of the shot a scene frame, counted from the first shot, is in, -1 outside), `func cast_entry(actor: StringName) -> CastEntry`, `func mark(name: StringName) -> SceneMark`.
  - `CastEntry`: `actor: StringName` (the name shots use), `source: Source {LIVE_PLAYER, LIVE_NAMED, SPAWN}`, `node_name: StringName` (LIVE_NAMED: the actor node's name), `def: ActorDef` and `spawn_mark: StringName` (SPAWN), `required: bool = true`, `after: After {KEEP, FREE, ENEMY_BRAIN}` (what a spawned or live actor is left doing: `KEEP` gets the brain it had, or none if spawned; `FREE` removes it; `ENEMY_BRAIN` gives it its def's brain), `speaker: StringName`.
  - `SceneMark`: `name: StringName`, `space: Space {REGION, ACTOR_START}`, `actor: StringName` (ACTOR_START: the position is in that actor's own space, +Z the way it faced, as it stood when the scene began), `position: Vector3` (m), `yaw_deg: float`. A name starting `rehearsal.` (`rehearsal.abarax`) is where the tools stand that LIVE actor before the scene begins; it is not a place a shot may name.
  - `Shot`: `enum Framing {WIDE, MEDIUM, CLOSE, OVER_SHOULDER, INSERT}`, `enum CamMove {STATIC, PAN, DOLLY, CRANE, ORBIT, HANDHELD}`; `id: StringName`, `start: int`, `length: int`, `framing`, `move`, `action: String` (the storyboard's words), `aim: StringName`, `aim_to: StringName` (PAN), `aim_height: float = 1.0` (m above the feet), `zoom: int = 0` (0: the framing's default), `zoom_to: int = 0` (DOLLY), `yaw_deg: float`, `yaw_to_deg: float` (ORBIT), `pitch_deg: float = -40.0`, `pitch_to_deg: float = -40.0` (CRANE), `shake: float` (HANDHELD, 0 to 1), `over_shoulder: StringName` (the foreground actor), `focus: StringName` (default `aim`), `focus_to: StringName` (a pull), `blend_in: int = 0` (frames the camera glides from the last shot's end; 0 is a cut), `key_frame: int = -1` (frames into the shot the storyboard photographs; -1 the middle), `beats: Array[ActorBeat]`, `lines: Array[DialogueLine]`, `cues: Array[CueEvent]`. A target name is an actor, a mark, or `name@start` (where that actor or mark's actor stood at the start).
  - `ActorBeat`: `enum Pace {WALK, JOG}` (pushes 0.45 and 1.0); `actor`, `at: int` (frames into the shot), `clip: StringName` (a clip of the rig; held at its last frame if not `loop`), `loop: bool`, `blend: float = 0.1` (s), `move_to: StringName`, `pace: Pace`, `face: StringName`, `look: StringName`, `placeholder: bool`.
  - `DialogueLine`: `speaker: StringName`, `text: String`, `expr: StringName = &"neutral"`, `at: int`, `hold: int` (0: typing time plus 45).
  - `CueEvent`: `enum Kind {SOUND, MUSIC}`, `at: int`, `kind`, `id: StringName`, `at_ref: StringName` (a sound plays there; "" is not placed).
  - `Speaker` (`data/speakers/<id>.tres`, Registry kind `speakers`): `id`, `display_name: String`, `portraits: Dictionary` (expression `StringName` to `Texture2D`; must include `neutral`), `blip_pitch: float = 1.0`.
  - `ShotChecker` (`RefCounted`): `func check(scene: SceneShots, folder: String = "") -> PackedStringArray` (a line is `"<scene>/<shot or ->: <problem>"`; none is empty array); `func check_all(root := "res://scenes/story") -> PackedStringArray`; `const PLACEHOLDER := "placeholder: "` (lines that begin so are listed, and are errors only for an approved scene or with `--final`); `static func travel_seconds(def: ActorDef, pace: ActorBeat.Pace, metres: float) -> float` (from rest, with the def's accel and decel, the formula of `Main._leg` solved the other way). Rules: the folder has a non-empty `script.md` and `notes.md` whose last `Status:` line matches `status`, and `shots.tres`'s `id` equals the folder name; shots start at 0 and each starts exactly where the one before ends (the line names the gap or overlap in frames); a shot is 12 frames or more and `blend_in` is at most its length; beats, lines and cues lie inside their shot, a line fits (its `at + hold` at most the shot's length, `hold` at least typing time plus 20, at most 160 characters) and lines of one shot do not overlap; every target, actor, spawn mark, `ACTOR_START` actor, speaker (Registry `speakers`), cast `def` and sound cue (Registry `sounds`) resolves, and a mark never has an actor's name; a clip exists in the actor's rig (a LIVE_PLAYER's def is `abarax`), else it is a `placeholder:` line if the beat says so and an error if not; camera fields fit the move (STATIC none set, PAN `aim_to`, DOLLY `zoom_to` different from `zoom`, CRANE `pitch_to_deg` different, ORBIT `yaw_to_deg` different, HANDHELD `shake` above 0; OVER_SHOULDER has `over_shoulder` and no other framing has), zoom 0 to 4 and pitch within -15 to -65; a MINI is 180 to 360 frames in all, a MOMENT has one shot, at most 90 frames in all, no letterbox and no beats; a CUTSCENE is 120 frames or more; a `move_to` between two region marks must fit before that actor's next beat or the scene's end by `travel_seconds`; an approved scene has no placeholder.
  - `tools/story_check.gd`: `tools/godot.sh -s res://tools/story_check.gd [-- --scene=<id>] [--final]`; prints each problem as `story_check: <line>`, exits 1; otherwise prints `story_check: N scenes OK (P placeholders)` and exits 0; 2 for a wrong command line.
  - `tools/portraits/export_portraits.mjs`: `node tools/portraits/export_portraits.mjs`: opens the Tactics game with Playwright as `render-icons.mjs` does, and for each of `abarax, noella, sierra, kesra, goldtooth` and each of `neutral, smile, serious, angry, sad, surprise` writes `assets/portraits/<id>/<expression>.png` (48×48, the canvas as drawn, no scaling); the PNGs are committed, so only a re-render needs Node.
  - `ASSETS.md` row: `assets/portraits/` | `ours: rendered from the earlier Tactics game's procedural portraits (all-divine-tactics/web/index.html, AD.spr.portrait) by tools/portraits/export_portraits.mjs` | `ours` | `none: 48x48, one PNG a look and expression, as drawn`.
  - **The fixture**, `scenes/story/fixture_yard_entrance/`: kind MINI, status DRAFT, region the yard, 330 frames in all (lead 30, shots 270, lead 30). Cast: `abarax` (LIVE_PLAYER, required, KEEP) and `knuckle` (SPAWN, def `knuckle_1`, spawn mark `foe_in`, required, ENEMY_BRAIN, speaker `fixture_knuckle`). Marks: `foe_in` ACTOR_START abarax (4.5, 0, 2.6), `foe_stop` ACTOR_START abarax (1.2, 0, 2.6), `rehearsal.abarax` REGION (0, 0, 5) yaw 180. Shots: S1 "The foe walks in" WIDE PAN `abarax` to `foe_stop`, 90 frames, knuckle `move_to foe_stop` WALK at 0, abarax `face foe_stop` at 0; S2 "He stops and folds his arms" MEDIUM DOLLY zoom 2 to 3, aim `knuckle`, 60 frames, focus `knuckle`, a SOUND `cloth_move` at 0 at `knuckle`, knuckle clip `knuckle_idle` loop at 0, abarax `guard_raise` at 0 then `guard_hold` loop at 14; S3 "A line" CLOSE STATIC aim `abarax` height 1.5, 60 frames, focus `abarax`, a MUSIC `fixture_sting` at 0, knuckle's line "Fixture line one." (hold 54); S4 "The answer" OVER_SHOULDER foreground `knuckle`, aim `abarax`, 60 frames, abarax's line "Fixture line two." (hold 54). `script.md` begins "FIXTURE: not story. It exists to prove the pipeline." and says what happens and the feeling in two sentences; `notes.md` has `## Rev 1` and `Status: draft`. If the checker says a walk does not fit, lengthen S1 or shorten the foe's `foe_in` offset until it does: the numbers are the plan's first guess.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/story/test_shot_data.gd
func test_a_scene_saves_and_loads_with_every_field() -> void:   # build a SceneShots in code, ResourceSaver to a temp path, load: equal field by field, nested resources included
func test_total_frames_and_shot_at() -> void:   # lead 30, shots 90+60: total 180; shot_at(0)=0, shot_at(89)=0, shot_at(90)=1, shot_at(150)=-1
func test_the_fixture_loads_and_is_a_mini_of_330_frames() -> void:
# tests/story/test_shot_checker.gd   (each test starts from the fixture duplicated, breaks one thing, and expects exactly that line)
func test_the_fixture_is_clean() -> void:   # no lines
func test_a_gap_between_shots_names_the_frames() -> void:   # shot 2 start moved 10 later: "gap of 10 frames between S1 and S2" (Review Focus 5)
func test_an_overlap_names_the_frames() -> void:   # shot 2 start 10 earlier: "overlap of 10 frames"
func test_a_first_shot_not_at_zero_and_a_short_shot() -> void:
func test_a_beat_line_or_cue_outside_its_shot() -> void:
func test_a_line_that_cannot_finish_or_overlaps_another_or_is_too_long() -> void:   # hold 10; two lines at 0 and 5; 161 characters
func test_an_unknown_clip_is_reported_like_a_move_and_a_placeholder_is_listed() -> void:   # a clip 'no_such_clip': "<scene>/S2: knuckle has no clip 'no_such_clip'"; with placeholder true it is a PLACEHOLDER line and not an error
func test_an_unknown_actor_mark_speaker_sound_def_or_spawn_mark_is_reported() -> void:   # one case each (Review Focus 2)
func test_a_mark_with_an_actors_name_and_a_rehearsal_mark_named_in_a_shot() -> void:
func test_camera_fields_must_fit_the_move_and_the_framing() -> void:   # DOLLY with zoom_to == zoom, OVER_SHOULDER without a foreground actor, zoom 5, pitch -10
func test_the_kinds_have_their_lengths_and_their_rules() -> void:   # MINI 120 frames, MINI 400, MOMENT with 2 shots, MOMENT 100 frames, MOMENT with a letterbox, CUTSCENE 60
func test_a_walk_that_does_not_fit_before_the_next_beat_is_reported() -> void:   # 3.3 m at WALK with 30 frames left: the line gives the seconds needed and the seconds left
func test_an_approved_scene_with_a_placeholder_and_a_notes_status_that_disagrees_are_errors() -> void:
func test_check_all_walks_the_scene_folders() -> void:   # the real scenes/story folder: clean
# tests/story/test_speakers.gd
func test_every_speaker_has_neutral_and_the_six_expressions_as_48_by_48_with_transparent_corners() -> void:
func test_the_expressions_differ() -> void:   # per speaker the six images are pairwise unequal
func test_every_portrait_file_has_a_ledger_row() -> void:   # the existing ledger test covers it; assert assets/portraits/ is in ASSETS.md
```

- [ ] **Step 2: Run** `tools/test.sh --filter=tests/story`. Expected: FAIL (no classes).
- [ ] **Step 3: Implement the Interfaces.** Write the classes and the checker; run the portrait exporter (`node tools/portraits/export_portraits.mjs`; if Playwright or Chromium is missing in the container, say so in the report and run it where they exist, then commit the PNGs); write the five speaker resources and the fixture's three files; add the ledger row; run `tools/godot.sh --import` so the new `class_name`s and PNGs are known.
- [ ] **Step 4: Look at it.** Read three portraits (`assets/portraits/abarax/neutral.png`, `.../noella/smile.png`, `.../fixture_knuckle/angry.png`) and confirm they are faces; run `tools/godot.sh -s res://tools/story_check.gd` and read its output, then break a copy of the fixture three ways (gap, bad clip, unknown mark) in the scratchpad and read what the checker says about each. A line a person cannot act on is a defect: fix its words.
- [ ] **Step 5: Run** `tools/test.sh`, `tools/godot.sh -s res://tools/clip_check.gd` (counts unchanged), `tools/godot.sh -s res://tools/story_check.gd`. Expected: all pass, no ERROR or WARNING lines.
- [ ] **Step 6: Commit.** STATE.md Done: "Director Task 1: the shot list as data (`SceneShots`, `Shot`, beats, lines, cues, cast, marks), the book's portraits as PNGs through the ledger, speakers, and the shot checker (`tools/story_check.gd`) with the fixture scene `fixture_yard_entrance` clean". Owner checklist: none yet.

---

### Task 2: The timeline and what it drives: the cine camera layer, letterbox and dialogue box

**Files:**
- Create: `story/cine_pose.gd`, `story/cine_camera.gd`, `story/timeline_builder.gd`, `hud/cine_overlay.gd`, `data/sounds/voice_blip.tres`, `assets/audio/sfx/voice_blip.wav`, `tools/audio/make_blips.py`, `tools/audio/tests/test_blips.py`, `tools/story/bake_timeline.gd`
- Modify: `render/camera_rig.gd`, `hud/hud.gd`, `ASSETS.md`, `STATE.md`
- Test: `tests/story/test_cine_pose.gd`, `tests/story/test_timeline_builder.gd`, `tests/look/test_camera_cine.gd`, `tests/hud/test_cine_overlay.gd` (no existing test is edited)

**Interfaces:**
- Consumes: Task 1's data; `CameraRig` (`_follow`, `_lean`, `PITCH_DEG`, `YAW_DEG`, `ORTHO_SIZE`, `DISTANCE`, `PixelSnap.snap/subpixel/TEXEL`); `Sfx.play(id, at, pitch)`; `Hud.INK/WHITE`; `Speaker`.
- Produces:
  - `CinePose` (`RefCounted`): `aim: Vector3`, `yaw_deg: float`, `pitch_deg: float`, `zoom: float`, `focus: Vector3`; `static func blend(a: CinePose, b: CinePose, t: float) -> CinePose` (smoothstep-eased `t`, angles by shortest turn; `t` 0 returns `a`'s values exactly, 1 `b`'s); `static func solve(shot: Shot, progress: float, world: Callable) -> CinePose` where `world.call(name: StringName) -> Variant` gives a Vector3 for a target name (an actor's `chest_point()` raised to `aim_height`, a mark, or `name@start`) or null: framing defaults, ramps by `progress` (0 to 1, linear), OVER_SHOULDER yaw from the foreground actor to the aim point, pitch clamped to -15..-65, zoom rounded to a whole number when `progress` is 0 or 1.
  - `CameraRig` additive: `var cine: CinePose = null`, `var cine_weight := 0.0` (0 to 1), `func gameplay_pose() -> CinePose` (the follow point, -40, yaw 0, zoom 1, the target as focus). While `cine_weight > 0.0`: `_apply` places the follow at `CinePose.blend(gameplay_pose(), cine, cine_weight)`, turns the rig to its yaw and pitch, sets `camera.size = ORTHO_SIZE / zoom` and snaps to `TEXEL / zoom`, hands `PixelStage.subpixel` the loss in that grid, and `focus` is the distance to the pose's focus point along the view; `yaw()` returns the gameplay yaw (`deg_to_rad(YAW_DEG)`) whatever the weight; when the weight is exactly 0 the rig sets rotation, size and snap to the constants and is as it was before this task.
  - `CineCamera` (`Node3D`, the node the timeline animates): animated properties `shot: int` (discrete), `progress: float`, `letterbox: float` (0 to 1), `shake: float`; `var scene: SceneShots`, `var world: Callable`, `var rig: CameraRig`, `var overlay: CineOverlay`. Each physics frame it writes `rig.cine = CinePose.solve(...)` for `scene.shots[shot]` (a `blend_in` glide from the last shot's end pose for that many frames), sets `overlay.letterbox`, and lifts `rig.trauma` to `shake` (handheld). It never sets `rig.cine_weight` (the Director does: lead in and out).
  - `TimelineBuilder`: `static func build(scene: SceneShots) -> Animation` (null for a scene the checker would reject for timing: gap, overlap, short shot; the reason in `static var last_error: String`); length `scene.total_frames() / 60.0`; tracks: value `CineCamera:shot` (discrete, a key at each shot's start plus `lead_in`), value `CineCamera:progress` (linear, 0 at a shot's start and 1 at its end, discrete cut between shots), value `CineCamera:letterbox` (bars slide in over 30 frames from 0 and out over the last 30 when `scene.letterbox`), and a method track on `Director` calling `_cue(kind: StringName, payload: Dictionary)` with kinds `&"beat"`, `&"line"`, `&"sound"`, `&"music"` at the frame each happens, and `&"end"` at the last shot's end minus the return blend; `static func player_for(scene: SceneShots) -> AnimationPlayer` (the generated animation, or, when `scene.timeline` is set, that scene's `AnimationPlayer` instead). `tools/story/bake_timeline.gd` (`-- --scene=<id>`) writes `scenes/story/<id>/timeline.tscn` (a `Cutscene` node holding the `AnimationPlayer` and a `CineCamera`) to open in the editor; `SceneShots.timeline` is then pointed at the owner's edited copy by hand.
  - `CineOverlay` (`Control`, in the HUD viewport, mouse ignored): `var letterbox := 0.0`; `const BAR := 44`, `BOX := Vector2i(620, 64)`, `MARGIN := 10`, `PORTRAIT := 48`, `CPS := 30`, `BLIP_EVERY := 2`, `MAX_LINES := 3`; `func show_line(speaker: Speaker, text: String, expr: StringName, hold_frames: int) -> void`; `func advance(frames := 1) -> void` (types characters, blips `Sfx.play(&"voice_blip", null, speaker.blip_pitch)`, ends the line after `hold_frames`); `func close() -> void`; `var burn_in := ""` (small caption top left, for the animatic); queries in picture pixels: `func bar_rects() -> Array[Rect2i]`, `func bar_height() -> int` (`round(letterbox * BAR)`), `func box_rect() -> Rect2i` (its bottom 10 px above the bars, or above the picture's bottom with none), `func portrait_rect() -> Rect2i`, `func visible_text() -> String`, `func covered_fraction() -> float`. Drawn with `ThemeDB.fallback_font` size 8, outline 3 in `Hud.INK`, text `Hud.WHITE`, box fill `Hud.INK`, 1 px `Hud.WHITE` border, the speaker's name on a tab at the box's top left, the portrait as drawn (no scaling).
  - `Hud.suppressed: bool`: while true `_draw` draws nothing.
  - `data/sounds/voice_blip.tres` (a `SoundCue`, `bus` `Voice`, `pitch_jitter` 0.03) and `assets/audio/sfx/voice_blip.wav` made by `tools/audio/make_blips.py` (a 12 ms pulse of 0.5 duty near 990 Hz, 16-bit mono 44.1 kHz, seeded, the same bytes every run) with its `ASSETS.md` row (`ours`).

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/story/test_cine_pose.gd
func test_blend_returns_its_ends_exactly_and_eases_between() -> void:   # t 0 -> a, 1 -> b (==), 0.5 -> the midpoint of aim; the shortest turn across 350 -> 10 degrees
func test_framing_defaults_set_the_zoom() -> void:   # wide 1, medium 2, close 3, over-the-shoulder 2, insert 4; an explicit zoom wins
func test_a_dolly_is_a_zoom_ramp_that_is_whole_at_its_ends_and_a_crane_a_pitch_ramp() -> void:
func test_a_pan_ramps_the_aim_and_an_orbit_the_yaw() -> void:   # progress 0.5 is the midpoint, linear
func test_over_the_shoulder_puts_the_camera_behind_the_foreground_actor() -> void:   # yaw = the direction from the foreground actor to the aim point
func test_pitch_is_clamped_and_a_missing_target_falls_back_to_the_last_aim() -> void:
# tests/look/test_camera_cine.gd   (as test_camera_rig.gd: a rig in a stage with a plain target)
func test_with_no_cine_the_rig_is_exactly_as_before() -> void:   # weight 0, a cine pose set: camera transform, size and subpixel equal a rig that never had one, over 30 frames of a moving target
func test_full_weight_looks_at_the_pose_and_zoom_two_halves_the_view() -> void:   # camera.size == ORTHO_SIZE / 2; the aim point projects to the middle of the picture
func test_at_a_whole_zoom_the_camera_sits_on_the_zoomed_pixel_grid() -> void:   # the camera's basis.x and basis.y parts are multiples of TEXEL / zoom, for zoom 1, 2, 3, 4
func test_yaw_is_the_gameplay_yaw_through_a_glide() -> void:   # cine yaw 90, weights 0, 0.5, 1: yaw() == 0
func test_the_weight_returning_to_zero_restores_the_gameplay_pose_exactly() -> void:   # no leftover rotation, size or offset: == the pose of a fresh rig
func test_focus_follows_the_cine_focus_point() -> void:   # the post quad's `focus` is the distance to it along the view
# tests/story/test_timeline_builder.gd
func test_the_timeline_is_as_long_as_the_scene() -> void:   # fixture: 330 / 60 s
func test_shot_keys_fall_on_each_shots_start_plus_the_lead_in() -> void:   # 30, 120, 180, 240
func test_every_beat_line_and_cue_is_one_call_at_its_frame_in_order() -> void:
func test_building_twice_gives_equal_animations() -> void:
func test_a_letterboxed_scene_slides_the_bars_in_and_out_and_a_mini_has_none() -> void:
func test_a_list_with_a_gap_or_an_overlap_is_not_built() -> void:   # null, last_error names the frames (Review Focus 5); wrap in quietly()
func test_a_scene_timeline_scene_plays_instead_when_set() -> void:
# tests/hud/test_cine_overlay.gd
func test_bars_are_whole_pixels_at_every_weight_and_44_at_one() -> void:   # letterbox 0, 0.1 ... 1: bar_height is an int, 2 * bar_height / 360 <= 0.245
func test_the_box_stays_in_the_picture_above_the_bars_and_clears_them() -> void:   # with and without bars
func test_a_line_types_30_characters_a_second_and_blips_every_second_character() -> void:   # frames 0, 2, 30, 60 against visible_text; Sfx.last_played() counts
func test_a_line_ends_after_its_hold_and_closing_clears_the_box() -> void:
func test_every_fixture_line_fits_in_three_lines_of_the_box() -> void:   # measured with the font, as drawn
func test_the_portrait_is_the_speakers_expression_at_48_by_48() -> void:
func test_the_overlay_never_covers_more_than_the_bars() -> void:   # covered_fraction <= 0.245 at every weight with a line showing
func test_a_suppressed_hud_draws_nothing_and_an_unsuppressed_one_is_unchanged() -> void:   # tests/hud/test_hud.gd's own checks still pass
# tools/audio/tests/test_blips.py
# test_the_blip_is_12_ms_16_bit_mono_and_the_same_bytes_every_run
```

- [ ] **Step 2: Run** `tools/test.sh --filter=tests/story`, `--filter=test_camera_cine`, `--filter=test_cine_overlay`. Expected: FAIL.
- [ ] **Step 3: Implement the Interfaces.** Make the blip with `python3 -I tools/audio/make_blips.py`; write the rig's cine layer as the smallest branch (see Working in this lane); write the overlay; write the builder and the bake tool.
- [ ] **Step 4: Look at it.** In a render run, put the fixture's four shot poses on the yard with the overlay and a line showing, capture 640×360 frames (as `tests/support/clip_shots.gd` does), Read the PNGs: bars exactly 44 px, the box clear of them, text and portrait sharp at 1:1, the four framings visibly different in scale. Bake the fixture's timeline and open `scenes/story/fixture_yard_entrance/timeline.tscn` through `tools/godot.sh --headless --check-only`-style load (it must load without errors); delete the baked file afterwards (it is not committed until the owner wants an override).
- [ ] **Step 5: Run** `tools/test.sh` (the camera, HUD and shake tests unchanged and green), `TEST_TIMEOUT=1800 tools/test.sh --render`, `python3 -I -m unittest discover -s tools/audio/tests`, `tools/godot.sh -s res://tools/story_check.gd`. Expected: all pass, no ERROR or WARNING lines.
- [ ] **Step 6: Commit.** STATE.md Done: "Director Task 2: the timeline builder, the camera's cine layer (whole-number zoom, yaw, pitch, aim, focus), the letterbox and dialogue overlay with the voice blip".

---

### Task 3: The Director: cast, brains, the seamless rule, skipping

**Files:**
- Create: `story/director.gd`, `story/director_brain.gd`, `story/story_log.gd`, `tests/support/story_stage.gd`
- Modify: `STATE.md`
- Test: `tests/story/test_director_start.gd`, `tests/story/test_director_cast.gd`, `tests/story/test_director_seamless.gd`, `tests/story/test_director_skip.gd`, `tests/story/test_director_play.gd`

**Interfaces:**
- Consumes: Tasks 1 and 2; `Actor` (`set_brain`, `place`, `snap_facing`, `rig`, `runner`, `frozen`, `freeze`, `paired_with`, `dead`, `is_on_floor()`, `chest_point()`, `def`), `ActorDef.brain`, `EnemyBrain`, `Rig` (`play_move`, `stop_move`, `set_move_time`, `tree`, `shown_pose`), `MoveRunner.stop`, `Melee.slowed()`, `Game`, `Inputs`, `Sfx.play`, `Region`, `Intent`, `Brain`, `PlayerBrain`.
- Produces:
  - `StoryLog` (`RefCounted`, statics): `static func seen(id: StringName) -> bool`, `mark_seen(id)`, `forget_all()` (tests).
  - `DirectorBrain extends Brain`: `var move_to: Variant` (Vector3 or null), `var push := 0.0`, `var face: Variant`, `var look: Variant`; `think()` returns an `Intent` that walks toward `move_to` at `push` until within 0.12 m (then `arrived` is true and the push is 0), faces `face`, looks at `look`; no presses.
  - `Director` (`Node`, `process_physics_priority = -10`, so it runs before the actors it drives):
    - `enum Phase {WAITING, LEAD_IN, PLAY, LEAD_OUT, DONE}`; `signal started(scene_id: StringName)`, `signal refused(reason: StringName)`, `signal finished(skipped: bool)`, `signal music_cue(id: StringName)`, `signal line_shown(speaker: StringName, text: String)`.
    - `const START_WAIT := 36`, `PAIR_WAIT := 90`, `RETURN_BLEND := 15`, `SKIP_LEAD_OUT := 20`, `POSE_MATCH_DEG := 4.0`, `ARRIVE := 0.12`.
    - `static func play(scene_id: StringName, host: Node) -> Director`: loads `res://scenes/story/<id>/shots.tres`, finds the `CameraRig` (group `camera_rig`), the `PixelStage` and `Hud` under `host` (a `Main`), and begins; null if refused or unknown (the `refused` reason is returned through `Director.last_refusal: StringName`, a static). `func begin(scene: SceneShots, region: Node3D, rig: CameraRig, hud: Hud, host: Node) -> bool` is the same with the parts given (tests and tools call it).
    - Begin refuses (no state, brain, node or camera change, no error line) with `&"not_playing"` (a non-MOMENT scene unless `Game.state` is PLAY; `Director.allow_any_state` overrides it for the tools), `&"already_playing"`, `&"cast_absent:<actor>"`, `&"cast_dead:<actor>"`, `&"cast_busy:<actor>"` (still in a pair after PAIR_WAIT), `&"no_def:<actor>"`. An optional (`required` false) absent or dead actor is dropped with its beats and the scene plays.
    - Phases: WAITING until no cast actor is frozen, no slow is running (`Melee.slowed()`), every LIVE cast actor is on the floor and out of a pair (START_WAIT frames, PAIR_WAIT for a pair, then it begins anyway except for a pair); then each LIVE actor's move is stopped (`runner.stop(0.1)`), brains are swapped (the old brain kept for hand-back), SPAWN actors are made at their marks (`Actor` scene `res://actors/actor.tscn` with `def`, a `DirectorBrain` set before it is in the tree), the overlay is added beside the Hud and the Hud suppressed, `Game.change(CUTSCENE)` (not for MOMENT), and the scene's clock starts at frame 0. LEAD_IN: `rig.cine_weight` rises 0 to 1 over `lead_in` frames (the first frame's picture is the gameplay picture within 1 px) while the timeline runs from frame `lead_in`. PLAY: the timeline's `_cue(...)` calls drive the beats (`DirectorBrain.move_to/face/look`, `Rig.play_move` on the actor's rig with `set_move_time` advanced each frame before the actors tick, looped by `fposmod` when `loop`), lines (`CineOverlay.show_line`), sounds (`Sfx.play(id, at_ref's point, 1.0)`) and `music_cue`; non-cast actors are held with `freeze(2)` each frame (never shortening a longer freeze). At `end` (the last shot's end minus RETURN_BLEND) every cast actor's move layer fades to locomotion (`stop_move(RETURN_BLEND / 60.0)`). At the last shot's end: hand-back and LEAD_OUT together: LIVE actors get their old brains back, SPAWN actors their `after` (KEEP: none, FREE: removed once the camera has arrived, ENEMY_BRAIN: `EnemyBrain.new(def.brain, hash("%s#%d" % [name, spawn_count]))`), `Game.change(PLAY)`, the Hud shown, `rig.cine_weight` falls 1 to 0 over `lead_out` frames from the last shot's pose to the live gameplay pose, the bars slide out; at weight 0 the overlay is freed, `StoryLog.mark_seen`, `finished(false)`.
    - `func skip() -> bool`: true if it did something. Refused (false) when `StoryLog.seen(scene.id)` is false (unless `Director.skip_always`), when phase is WAITING or DONE, or when already skipping. Otherwise: cast actors are placed at their last `move_to` marks facing their last `face` (a LIVE actor keeps its place if it has none), clips released, line closed, and LEAD_OUT starts at once over SKIP_LEAD_OUT frames from the pose the camera is showing now (no jump, wherever in the glide in it is). `menu` pressed while skippable calls it.
    - `func is_skippable() -> bool`; `var frame: int` (scene frames since the clock started, not counting the wait); `var phase: Phase`; `var cast: Dictionary` (actor name to `Actor`); `func total_frames() -> int`.
    - A MOMENT takes no cast, changes no state, never waits, cannot be skipped and has no letterbox: Task 4.
  - `tests/support/story_stage.gd` (`StoryStage`): builds, under a `TestCase`, a `PixelStage` with a floor (`TestTerrain`), a `CameraRig` on Abarax, a Hud, Abarax with `PlayerBrain`, and returns them in a Dictionary with `static func pose_of(rig: Rig) -> Dictionary` (bone to local rotation) and `static func angle_between(a: Dictionary, b: Dictionary) -> float` (the largest bone angle, degrees).

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/story/test_director_start.gd   (Review Focus 1 and 4)
func test_a_scene_starts_from_the_live_state() -> void:   # Abarax placed at (3, 0, 4) facing 200 degrees: his position at frame 0 is unchanged to 1 mm, the camera's first picture puts his head within 1 px of where the gameplay camera had it
func test_a_scene_started_mid_move_ends_the_move_cleanly() -> void:   # for palm_jab, palm_cross, palm_hook, charging palm_heavy (held), hop, sway_left_slip, duck_slip, dash_step, guard_raise, parry: after begin no hitbox is on, no iframes, evade, guard, parry or airborne window is open, runner.current is null, and a Knuckle in reach takes no damage from the stopped swing
func test_the_first_frames_do_not_pop() -> void:   # across the start, the head's screen position moves at most 12 px a frame, and no bone turns more than 25 degrees between two frames
func test_started_in_a_hop_or_off_the_floor_waits_for_the_floor() -> void:   # a body pushed off a ledge (TestTerrain.ledge): phase WAITING until is_on_floor, then begins; at most START_WAIT frames
func test_started_during_hit_stop_waits_it_out() -> void:   # both fighters frozen 5 frames by a blow: the clock (frame) is 0 until frozen is 0 for all cast actors
func test_started_during_the_slow_down_waits_it_out_and_never_stutters() -> void:   # Melee.slow(12, 0.4) running: frame stays 0 until slowed() is false; then every cast actor acts on every scene frame
func test_the_world_hold_does_not_shorten_a_freeze_already_on() -> void:   # a non-cast Knuckle frozen 6 frames stays frozen 6, then is held
func test_the_wait_gives_up_after_start_wait_unless_paired() -> void:   # a freeze of 100 frames: begins at 36 anyway; no error line
# tests/story/test_director_cast.gd   (Review Focus 2)
func test_a_required_actor_who_is_absent_dead_or_busy_refuses_the_scene() -> void:   # reasons cast_absent:knuckle, cast_dead:abarax, cast_busy:abarax; play returns null; Game.state, brains, children of the region and the camera's weight are as before; no ERROR or WARNING
func test_an_optional_actor_who_is_absent_drops_out_with_its_beats() -> void:   # the scene plays to finished; the absent actor's lines still show
func test_a_paired_actor_is_waited_for_and_the_scene_then_starts() -> void:   # a finisher in progress (90 frames at most): the scene begins after it ends; the pair's result is unchanged
func test_a_spawned_actor_stands_at_its_mark_with_a_director_brain_and_is_never_the_enemy_brain_until_hand_back() -> void:
func test_after_keep_free_and_enemy_brain() -> void:   # KEEP: still there, no brain; FREE: gone when the camera has arrived; ENEMY_BRAIN: an EnemyBrain, and a different seed for a second spawn
func test_a_scene_that_is_not_in_play_state_is_refused() -> void:   # Game.state PAUSE and MENU: not_playing; PLAY ok
func test_a_second_scene_while_one_plays_is_refused() -> void:
# tests/story/test_director_seamless.gd   (the seamless rule, measured)
func test_control_returns_at_the_start_of_the_glide_out_with_his_old_brain() -> void:   # at the frame lead_out begins, abarax.brain is the PlayerBrain object he had, Game.state is PLAY
func test_the_pose_at_hand_back_matches_idle_within_four_degrees() -> void:   # fixture ends with abarax in guard_hold: the largest bone angle between his pose then and the same body in locomotion idle <= POSE_MATCH_DEG
func test_he_keeps_his_facing_at_hand_back() -> void:
func test_the_camera_returns_to_the_live_gameplay_pose_with_no_jump() -> void:   # over lead_out the head's screen position moves at most 12 px a frame and ends at the gameplay camera's value for where he now stands (within 1 px); cine_weight == 0 exactly at the end
func test_no_frame_covers_more_than_the_bars() -> void:   # overlay.covered_fraction() <= 0.245 on every frame of the fixture (kind CUTSCENE and MINI); the Hud is suppressed exactly while the scene runs
func test_the_sticks_do_not_turn_with_the_glide() -> void:   # a last shot at yaw 90: rig.yaw() is 0 during the glide out
func test_the_world_holds_and_resumes() -> void:   # a non-cast Knuckle does not move or animate during the scene and acts in the first frame after it
func test_the_three_kinds_differ_only_as_specified() -> void:   # CUTSCENE: bars 44 and Game CUTSCENE; MINI: no bars, Game CUTSCENE; both end in PLAY; a MINI of 300 frames is 5.0 s
# tests/story/test_director_skip.gd   (Review Focus 3)
func test_a_first_viewing_cannot_be_skipped_and_a_later_one_can() -> void:   # skip() false, then StoryLog.mark_seen, true; menu pressed (Input.action_press) does it too
func test_skip_on_the_first_frame_glides_back_from_where_the_camera_is() -> void:   # frame 0: no jump (head <= 12 px a frame), ends in PLAY
func test_skip_on_the_last_frame_and_after_the_end_is_harmless() -> void:   # at hand-back and a frame later: a second finished is never emitted, nothing is placed twice
func test_skip_twice_and_skip_during_the_wait() -> void:   # second is false; during WAITING false and the scene still plays
func test_a_skipped_and_a_played_scene_end_in_the_same_state() -> void:   # cast within 0.15 m of each other and within 10 degrees of facing; brains, Game.state, camera weight 0, nodes left (FREE removed), StoryLog seen
func test_skip_closes_the_line_and_stops_the_clips() -> void:
# tests/story/test_director_play.gd
func test_the_fixture_plays_to_the_end_in_330_frames_after_the_wait_with_no_errors() -> void:
func test_every_beat_happens_at_its_frame() -> void:   # the knuckle's first step in shot 1, guard_hold from frame 14 of shot 2 (Rig current clip), the lines on their frames (line_shown), the cloth_move cue (Sfx.last_played), the music cue signalled and nothing played
func test_the_fixture_marks_stand_on_the_yard_floor() -> void:   # with the yard's floor: each REGION mark and each ACTOR_START mark for the rehearsal start has the floor within 0.5 m under it
func test_a_clip_is_driven_by_the_director_and_fires_no_mark() -> void:   # knuckle_feint played raw in a scene: no hitbox on, no sfx from its marks
func test_the_walk_arrives_within_arrive_of_its_mark_by_the_shots_end() -> void:   # the checker's travel promise, as played
```

- [ ] **Step 2: Run** `tools/test.sh --filter=tests/story`. Expected: FAIL.
- [ ] **Step 3: Implement the Interfaces.** The Director is one node and a brain; keep `_cue` handlers one line each; do the arithmetic of a phase in small functions named for what they decide (`_settled()`, `_hand_back()`, `_arrive_at()`), so each test reads one.
- [ ] **Step 4: Look at it.** Run the fixture on a `Main` instance in a render run with a scripted Abarax (standing; mid-jab; in a hop), capture a frame every 15 scene frames across the whole scene, make a contact strip, Read it: no black frame, the glide in and out continuous, Abarax where he stood, the Knuckle walks in and stops, bars absent (mini). Do it again with the scene's kind set to CUTSCENE in a copy: bars slide in and out. Read what you see and fix what looks wrong.
- [ ] **Step 5: Run** `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, `tools/godot.sh -s res://tools/clip_check.gd`, `tools/godot.sh -s res://tools/story_check.gd`, and the self-test (`tools/godot.sh -- --selftest`, exit 0). Expected: all pass, no ERROR or WARNING lines.
- [ ] **Step 6: Commit.** STATE.md Done: "Director Task 3: the Director: cast and brains, the seamless rule (live start, camera glide in and out, hand-back with a matching pose, no cut), skipping after a first viewing, the fixture playing end to end".

---

### Task 4: The combat moment and the debug key

**Files:**
- Create: `story/moment_cam.gd`, `story/story_tuning.gd`, `data/tuning/story.tres`, `data/story/moments/finisher.tres`
- Modify: `story/director.gd` (the MOMENT kind), `main/main.gd` (F10), `STATE.md`
- Test: `tests/story/test_moment.gd`, additions to `tests/main/test_main.gd`

**Interfaces:**
- Consumes: Task 3's Director and `CameraRig` cine layer; `Actor.combat_moment(kind)`; `Melee.slow`; `Actor.chest_point()`.
- Produces:
  - `StoryTuning` (`Resource`): `moment_dip_on := true` (Settings will turn it off), `moment_zoom := 2`, `moment_frames := 60`, `moment_slow_frames := 0` (the slow-motion beat is off until the owner asks; 12 is `Melee.slow(12, 0.4)`'s weight in the chain), `moment_hold_share := 0.4` (the share of the frames the dip holds at full). `data/tuning/story.tres` holds the defaults.
  - `data/story/moments/finisher.tres`: a `SceneShots` of kind MOMENT, one shot, MEDIUM, aim `@pair` (the target name `@pair` is the middle of the two fighters' chests, filled by the Director for a MOMENT), 60 frames, `lead_in` 15, `lead_out` 15 (90 in all, the spec's 1.5 s).
  - `MomentCam` (`Node`): made by `Director.watch_moments(player: Actor, rig: CameraRig, hud: Hud)` (called from `Main` once; idempotent); it listens to the player's `combat_moment`; for `&"finisher"` it plays the moment scene through the same Director and cine layer, taking no cast and no brains, not touching `Game.state`, the Hud or the world; the camera dips toward the pair's middle and returns to the live gameplay pose with `cine_weight` exactly 0. `&"grab"` has no dip. With `moment_dip_on` false it does nothing. A second moment while one runs restarts it from the pose the camera shows (no jump).
  - The finisher, its clips, `Pairing`, `PairedMove` and `Melee` are not touched: the dip only watches the signal.
  - `Main`: `KEY_F10:` plays the fixture (`Director.play(&"fixture_yard_entrance", self)`), consuming the key; `_ready` calls `Director.watch_moments(player, camera_rig, hud)`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/story/test_moment.gd
func test_a_finisher_dips_the_camera_and_gives_it_back_in_ninety_frames() -> void:   # cine_weight rises, falls, is exactly 0 on frame 90; zoom 2 at the top; the pair's middle is at the picture's middle at the top
func test_the_dip_changes_nothing_of_the_finisher() -> void:   # the same duel with the dip on and off: equal frames to the end, equal damage, equal state_hash of both fighters, equal Melee freezes (Review Focus 4: the dip never touches a freeze)
func test_a_moment_takes_no_brain_no_state_and_no_hud() -> void:   # Game.state stays PLAY, both fighters keep their brains, Hud.suppressed false, no overlay bars
func test_a_grab_has_no_dip_and_an_off_switch_has_none() -> void:
func test_a_second_finisher_during_a_dip_does_not_jump() -> void:   # head <= 12 px a frame
func test_the_moment_is_no_more_than_ninety_frames_and_the_checker_agrees() -> void:   # story_check on data/story/moments/finisher.tres
# tests/main/test_main.gd (additions)
func test_f10_plays_the_fixture_and_the_game_returns_to_play() -> void:
func test_pressing_f10_while_a_scene_plays_or_when_paused_does_nothing() -> void:
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_moment` and `--filter=tests/main`. Expected: FAIL.
- [ ] **Step 3: Implement the Interfaces.** The MOMENT path in the Director is a branch at `begin` (no cast, no wait, no state, no overlay), the rest is shared.
- [ ] **Step 4: Look at it.** In a render run, stage the finisher (`tests/support/posture_breaker.gd`, as the finisher tests do) with the dip on, capture every 6th frame of the 90, Read the strip: a dip that reads, no pop at either end.
- [ ] **Step 5: Run** `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, the self-test, and the demo reel (`tools/record_reel.sh`, then Read two stills: the reel's finisher now dips; that is expected and shown to the owner).
- [ ] **Step 6: Commit.** STATE.md Done: "Director Task 4: the finisher is a combat moment (a 1.5 s camera dip on the cine layer, no stall, off by `moment_dip_on`); F10 plays the fixture in the yard". Owner checklist (the lane's, added here): 1. Press F10 in the yard standing still, mid-jab, mid-hop and with a wave on: the camera glides out and back with no cut, the Knuckle walks in and stops, you get control with your pose right, the Knuckle then fights. 2. The second F10 can be skipped with Esc; the first cannot. 3. Is a finisher's dip welcome (`moment_dip_on`, `moment_zoom`, `moment_frames` in `data/tuning/story.tres`)? Would you like a slow-motion beat with it (`moment_slow_frames`)?

---

### Task 5: The storyboard sheet and the animatic

**Files:**
- Create: `tools/story/story_reel.gd`, `tools/story/story_reel.tscn`, `tools/story/storyboard_page.gd`, `tools/storyboard.sh`, `tools/animatic.sh`
- Modify: `STATE.md` (the lane's checklist)
- Test: `tests/tools/test_storyboard_page.gd`, `tests/render/test_story_shots.gd`

**Interfaces:**
- Consumes: Tasks 1 to 3 (`SceneShots`, `ShotChecker`, `Director.begin`, `CineOverlay.burn_in`), `Main` (the reel `extends Main`, as `DemoReel` does), `ContactSheet`'s habit of drawing a page from a SubViewport.
- Produces:
  - `StoryReel extends Main` (`tools/story/story_reel.gd`, scene `story_reel.tscn` instancing `main/main.tscn`): reads user args `--scene=<id>` and optionally `--capture` and `--out=<dir>`; sets the arena off (`automatic` false, no wave), puts Abarax at the scene's `rehearsal.<actor>` mark or the region's spawn, standing, waits 30 frames, then `Director.begin` (with `allow_any_state`, `skip_always` off) and quits `total_frames + 60` frames later. With `--capture` it saves, at each shot's key frame (`start + (key_frame` or `length / 2)` counted from the first shot), the exact 640×360 window image to `<out>/frames/shot-NN.png`, after `await RenderingServer.frame_post_draw`. Without it, it sets `overlay.burn_in` to `S2/4 MEDIUM DOLLY 2>3 f090 0:01.50` and any placeholder (`PLACEHOLDER knuckle_roar`), and cue captions (`SFX cloth_move`, `MUSIC fixture_sting`) so the video says what a silent run cannot.
  - `ShotText` (a static class inside `storyboard_page.gd`): `static func describe(scene: SceneShots, index: int) -> PackedStringArray` (the sheet's text for one shot, deterministic): header `S2  MEDIUM · DOLLY 2>3  ·  1.00 s  (frames 90 to 150, 1.50 s to 2.50 s)`, `ACTION: ...`, one `BEAT: knuckle clip knuckle_idle (loop) at +0` per beat (`move_to foe_stop WALK`), `LINE: FIXTURE KNUCKLE: "Fixture line one." (+0, 54 f)`, `SOUND: cloth_move at knuckle +0`, `MUSIC: fixture_sting +0`, `FOCUS: knuckle`. `static func key_frame(shot: Shot) -> int` (as above, clamped inside the shot).
  - `StoryboardPage` (`SceneTree` script, `tools/story/storyboard_page.gd`): `tools/godot.sh --render -s res://tools/story/storyboard_page.gd -- --scene=<id> --out=<dir>` lays the captured frames out: pages of 1280 px wide; a header (title, kind, revision, status, total seconds, region, a warning band listing `placeholder:` lines from the checker); per shot a row 380 px high with the frame at 1:1 (640×360, no scaling) at x 16 and the text column from x 672 in a 14 px font, three rows to a page; `<out>/storyboard-1.png`, `-2.png`, ... Exits 0, 1 if a frame is missing, 2 for a wrong command line. `static func layout(shot_count: int) -> Array[Dictionary]` (`{page, rect}` per frame) is pure.
  - `tools/storyboard.sh <scene> [out dir]` (default `out/story/<scene>`): runs the checker (stop on errors), writes the temporary `override.cfg` that makes the window 640×360 (as `record_reel.sh` does, removed at exit), runs `StoryReel --capture` with `--render --fixed-fps 60` so each frame is one physics tick, then the page script; prints the page paths.
  - `tools/animatic.sh <scene> [out dir]`: the same `override.cfg`, runs `StoryReel` under Movie Maker (`--write-movie ... --fixed-fps 30 --quit-after (total_frames + 90) / 2`), and encodes `<out>/animatic.mp4` (H.264, yuv420p, 1280×720, nearest-neighbour ×2, 30 fps) with ffmpeg; prints the path and its length. It is silent (the dummy audio driver); the burn-in is its sound track.
  - What is committed per scene stays `script.md`, `shots.tres`, `notes.md`; `notes.md`'s format is a `## Rev N: <date>` heading, then `Owner:` and `Changes:` paragraphs, last line `Status: draft|in review|approved` (the checker reads it).

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/tools/test_storyboard_page.gd   (headless, pure)
func test_the_text_for_each_fixture_shot_names_framing_move_action_line_sound_and_timing() -> void:   # exact strings for S2 and S3
func test_the_key_frame_defaults_to_the_middle_and_is_clamped_inside_the_shot() -> void:   # -1 -> length / 2; 500 -> length - 1
func test_the_layout_is_three_rows_a_page_with_frames_at_one_to_one() -> void:   # 4 shots: 2 pages; every frame rect 640 x 360, none overlapping the text column or the page edge
func test_the_key_frames_are_distinct_frames_of_the_scene() -> void:   # one per shot, increasing, all before total_frames
# tests/render/test_story_shots.gd   (render; runs the tool the way the owner's reviewer does)
func test_the_storyboard_tool_writes_a_frame_per_shot_of_exactly_640_by_360() -> void:   # runs tools/storyboard.sh on the fixture into a temp dir: four frames, 640x360, exit 0
func test_the_frames_show_the_framings() -> void:   # the CLOSE shot's Abarax silhouette (pixels unlike the empty stage, as ClipShots counts them) is at least 1.8 times the WIDE shot's; no frame is blank or identical to another
func test_no_frame_is_black_and_the_mini_has_no_bars() -> void:   # the middle row of every frame is not black; the first and last rows of the MINI frames are the world's
func test_the_page_is_made_and_the_animatic_has_the_right_length() -> void:   # storyboard-1.png is 1280 px wide; animatic.mp4 exists and ffprobe says 5.5 s (the scene's 330 frames at 60 per second, plus the 90-frame tail the tool records) within 0.1 s of (330 + 30 + 90) / 60 minus the wait the tool cuts: assert the duration is at least 5.5 s and under 8 s
```

- [ ] **Step 2: Run** `tools/test.sh --filter=test_storyboard_page` and `tools/test.sh --render --filter=test_story_shots`. Expected: FAIL.
- [ ] **Step 3: Implement the Interfaces.** The reel is one script with two modes; the page script reads the frames from disk and lays out with `ShotText`/`layout`.
- [ ] **Step 4: Look at it.** Run `tools/storyboard.sh fixture_yard_entrance` and `tools/animatic.sh fixture_yard_entrance`. Read every page PNG and each frame; read three stills out of the mp4 (`ffmpeg -ss`) in the scratchpad. Fix what does not read: text cut off, a frame that does not show the shot's point, a caption in the wrong place. The sheet and two frames at full size are what the owner is shown with the report.
- [ ] **Step 5: Run** `tools/test.sh`, `TEST_TIMEOUT=1800 tools/test.sh --render`, `tools/godot.sh -s res://tools/story_check.gd --final` (the fixture is a draft with no placeholder: passes), the self-test. Expected: all pass, no ERROR or WARNING lines.
- [ ] **Step 6: Commit.** STATE.md Done: "Director Task 5: the storyboard sheet (`tools/storyboard.sh <scene>`) and the animatic (`tools/animatic.sh <scene>`), outputs under `out/story/<scene>/`; F4's tool half is done on the fixture; the first real scene and First Knuckle's entrance wait for the owner's script". Under `## Owner checklist for the Director`, items 4 on: 4. Run `tools/storyboard.sh fixture_yard_entrance` and open `out/story/fixture_yard_entrance/storyboard-1.png`: does each row tell you enough to judge the shot (framing, action, line, timing)? 5. Watch `animatic.mp4`: is the burn-in the right amount of information? 6. The 2.35:1 bars and the dialogue box at your window's scale: readable? 7. Which portrait should the Knuckle wear (the book has none: the fixture borrows Gold Tooth's)? 8. Write your notes in `scenes/story/fixture_yard_entrance/notes.md` as `## Rev 2`.

---

## What is not in this plan, and who owns it

- **The first real cutscene and First Knuckle's entrance:** they need the owner's `script.md`; they go through this pipeline in F4's second half (the approval loop: sheet, animatic, notes, revision, approved).
- **Music:** cue ids are recorded and signalled (`music_cue`); a music system, stingers and mixing are later. **Voice:** blips only; no acting. **Localisation:** strings are inline in `shots.tres` for now; moving them to the CSV importer is a later pass.
- **Triggers in the world:** volumes, interact prompts, region entry that call `Director.play`, and the Arena handshake (pausing waves while a scene plays) belong to the world lane's F3 work; today only F10 plays a scene.
- **Saving:** `StoryLog.seen` lives in memory; the save task persists it. **Settings:** the screen that turns the dip and the bars off; `moment_dip_on` is the switch it will bind.
- **Portraits of the rest of the cast and the other expressions** (`grin`, `smirk`, `cry`, `blush`, Abarax's later looks): `export_portraits.mjs` takes a list; adding one is a data change and a ledger-row edit.
- **Real clips for scenes** (a bow, a roar, a kneel): made by the animation lane; until then a draft uses `placeholder` beats.
- **The finisher's own look** (clips, hit-stop): the combat lane's; this plan only watches `combat_moment`.

## Self-review

- Every tool part of spec 7 has a task: 7.1 the folder, shot data and notes (Task 1, notes in 5), the sheet and animatic (5); 7.2 the Director, timeline, camera, actors, letterbox, dialogue with portraits and blips, sound and music cues, focus (2, 3); 7.3 the three kinds (1 rules, 3 behaviour, 4 the moment); 7.4 the seamless rule, measured (3); spec 8's contact-sheet-style tools (5). The depth-of-field focus pull is in `Shot.focus_to` and the cine layer's `focus`.
- Names agree: `SceneShots`, `Shot`, `ActorBeat`, `DialogueLine`, `CueEvent`, `CastEntry`, `SceneMark`, `Speaker` (T1); `CinePose`, `CineCamera`, `TimelineBuilder`, `CineOverlay` (T2); `Director`, `DirectorBrain`, `StoryLog` (T3); `MomentCam`, `StoryTuning` (T4); `StoryReel`, `ShotText`, `StoryboardPage` (T5). Frames are `int`, seconds `float`, metres `float`, degrees `float` throughout; `bar_height` 44 and `BAR` agree with the Global Constraints.
- Each Review Focus item has its tests named in the task that owns it.
