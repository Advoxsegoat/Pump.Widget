# The All-Divine: STATE

What is done, what is next, and where the decisions live. Every task's final commit adds a line under Done.

## Done

F0 (Foundation) is built: a lit courtyard to walk in, with Abarax moving, rolling and chaining a jab and a cross. What is left for F0 is the owner's checklist below.

- F0 Task 1: toolchain, project skeleton and the headless test runner (`tools/test.sh`: 4 passed, 0 failed).
- F0 Task 2: Core autoloads: Game, Inputs (§4.1 bindings, rebinding, deadzone), Registry, audio buses (`tools/test.sh`: 93 passed, 0 failed).
- F0 Task 3: Pixel stage: 640×360 → integer upscale, texel-snapped ortho camera, sub-pixel offset (`tools/test.sh`: 108 passed, 0 failed; with `--render`: 111 passed, 0 failed).
- F0 Task 4: Asset intake (itch/Kenney fetch with hashes) and the ASSETS.md ledger check (`tools/test.sh`: 114 passed, 0 failed; with `--render`: 117 passed, 0 failed; Python tools: 28 passed).
- F0 Task 5: Abarax model: Quaternius head + peasant outfit + scarf bones, palette slots in UV2, ≤4,000 tris (`tools/test.sh`: 120 passed, 0 failed; with `--render`: 123 passed, 0 failed; `tools/bpy_test.sh`: 14 passed).
- F0 Task 6: Animation library: UAL clips extracted to text .tres, retimed, ground speeds measured, marks preserved on rebuild (`tools/test.sh`: 158 passed, 0 failed; with `--render`: 161 passed, 0 failed).
- F0 Task 7: Rig: AnimationTree (speed-blended locomotion, two-slot move layer, stepped playback), hitboxes, contact sheets (`tools/test.sh`: 175 passed, 0 failed; with `--render`: 181 passed, 0 failed).
- F0 Task 8: Moves: MoveData, marks on the Marks track, 9-frame input buffer, clip checker; jab, cross, roll (`tools/test.sh`: 274 passed, 0 failed; with `--render`: 280 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 9: Actor, brains (player, script), locomotion, move runner reading marks; buffer and cancel rules; press-to-motion ≤ 2 frames (`tools/test.sh`: 305 passed, 0 failed; with `--render`: 311 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 10: Character look: palette resource (ramps, dyes), toon shader held to the palette (`tools/test.sh`: 317 passed, 0 failed; with `--render`: 328 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 11: Screen look: depth outlines, tilt-shift DOF, depth+height fog, bloom, grading, vignette; renderer-agnostic (`tools/test.sh`: 328 passed, 0 failed; with `--render`: 354 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 12: Liveliness I: 8-way locomotion by orientation warping, breathing, procedural hit reactions (`tools/test.sh`: 351 passed, 0 failed; with `--render`: 377 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 13: Liveliness II: foot IK on slopes and stairs, head and neck look-at, spring-bone scarf (`tools/test.sh`: 383 passed, 0 failed; with `--render`: 409 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 14: The courtyard (Kenney town kit, flagstones at 32 texels/m, lanterns) and the main scene; --selftest (`tools/test.sh`: 409 passed, 0 failed; with `--render`: 439 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK; `tools/godot.sh -- --selftest`: exit 0). `world/courtyard/courtyard.tscn` is the source now: `tools/world/build_courtyard.gd` made it once from `layout.txt`; edit the scene, and do not build it again (that would overwrite the edits).
- F0 Task 15: Retargeting tool: BVH (CMU names) → our skeleton via bpy; ready for CMU strafes (`tools/bpy_test.sh`: 44 passed; `tools/test.sh`: 409 passed, 0 failed). No CMU clip is in the project yet; the first one brings its `ASSETS.md` row and its `clips.cfg` source.
- F0 Task 16: CI and exports. `.github/workflows/all-divine.yml` has four jobs (test, render, render-forward-plus, export); export presets for Linux, Windows Desktop and Web (single-threaded); the exported Linux build passes `--selftest` (exit 0) and starts and quits cleanly. Found and fixed on the way: the export dropped the nodes under `PixelStage/World` in `main.tscn` (it lacked `[editable path="PixelStage"]`), and `tests/tools/test_export_presets.gd` now checks every scene for that (`tools/test.sh`: 417 passed, 0 failed; with `--render`: 447 passed, 0 failed; the same suite under `--forward-plus` on lavapipe: 447 passed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 review fixes: the test framework counts the engine's Object-typed and freed nulls as null, and null guards in tests fail instead of skipping; the stick's radial deadzone is 0.28, so a pad drifting up to 0.19 on both axes leaves Abarax still; the game starts in borderless fullscreen (×3 at 1080p) with F11 or Alt+Enter for a 1280×720 window; "Paused" shows while paused; CI builds wait for the tests and upload before the run checks, with a read-only token; the clips' ledger row says what was done and `clips.cfg` is ours (`tools/test.sh`: 445 passed, 0 failed; with `--render`: 475 passed, 0 failed; with `--forward-plus` on lavapipe: 475 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK; `--selftest` exit 0, and of the exported Linux build too).
- F1 Task 1: F0 debts: `Layers` (the physics layers by name, one place), `TestLogger` in `core/` so the exports leave out `tools/` as well as `tests/`, a move cancelled while the move before it is still fading holds the pose in a one-key snapshot clip instead of jumping, a per-actor breath phase, a capped hit lean (`HitReact.MAX_TILT`), `Actor.snap_facing` and `head_point` (actors are looked at in the head), the locomotion layer keeping its pre-move speed while a move blends in and resting after (so a roll's carried speed never shows as a run, and a move from a jog does not pop the legs), and cancel-reset tests (`tools/test.sh`: 467 passed, 0 failed; with `--render`: 497 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK; `--selftest` exit 0, and of the exported Linux build too).
- F1 Task 2: clip sources: UAL2, warps, joins, keyed layers (`clips.cfg` keys `then`, `warp`, `layer`, checked as a whole by `ClipBuilder.check`; `tools/test.sh`: 494 passed, 0 failed; Python tools: 31 passed; a rebuild of the library changes no committed clip).
- F1 Task 3: combat data: `HitProfile` (a move's `hits`), the REACTION kind, `ActorDef` team, combat tuning and reactions, `CombatTuning` with Abarax's numbers, nine new mark kinds (the `hitstop` mark is gone: hit-stop is the profile's, on contact), and the clip checker's rules for them, including tells for team ENEMY (`tools/test.sh`: 527 passed, 0 failed; with `--render`: 557 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F1 Task 4: stats in play: stamina gates and regen, posture, poise. `Stats` spends, drains and regenerates stamina (a wait of 0.6 s, then 45 a second; exhausted at zero until 20), wears posture down and mends it after 1.5 s unless broken, and reports the blow that empties HP or posture; an attack or a dodge is refused when the actor cannot act (the press is used up), moves spend their `stamina_cost` (jab 12, cross 14, roll 18), and a sprint spends 12 a second and does not begin when exhausted (`tools/test.sh`: 558 passed, 0 failed; with `--render`: 588 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK; `--selftest` exit 0).
- F1 Task 5: hits: swept hitbox scans, Melee resolves trades, Combat.resolve rules, flinch, stagger, death. Each actor's `HitScanner` sweeps its live hitboxes' shapes from tick to tick (steps of half the radius; on and off between ticks still looked for once; never its own hurtbox; each body once per activation); the `Melee` autoload snapshots every actor's `Defense` before any moves and judges every hit of a frame against it after all have moved, so a trade lands both ways in either order; `Combat.resolve` holds the six rules (whiff, airborne, grab, parry and catch, guard and guard break, hit with flinch or stagger by poise); actors take blows (`apply_hit`, the additive flinch on every hit), flinch (UAL1 Hit_Chest), stagger (UAL2 Hit_Knockback) and die once (UAL1 Death01: hurtbox off, brain ignored, off the actor layer when the clip ends, lying where it left them) (`tools/test.sh`: 580 passed, 0 failed; with `--render`: 610 passed, 0 failed; `tools/clip_check.gd`: 6 moves, 1 actors OK; `--selftest` exit 0).

## Next

F1 Combat core (spec §9). Its plan is written, awaiting the owner's review: [`docs/superpowers/plans/2026-11-01-all-divine-rpg-f1-combat-core.md`](../docs/superpowers/plans/2026-11-01-all-divine-rpg-f1-combat-core.md).

## Owner checklist for F0

1. Download the Windows build from the latest CI run: GitHub, Actions, "The All-Divine (Godot)", the newest run, Artifacts, `all-divine-windows`. Unzip it and run `all-divine.exe`. Windows may warn that the file is unsigned: More info, then Run anyway.
2. The game starts in fullscreen. F11 (or Alt+Enter) switches to a 1280×720 window and back.
3. Walk the courtyard with a gamepad, then with the keyboard and mouse (WASD or the left stick to move, Space or A to roll and hold to sprint, left mouse or RB to jab). Leave the stick alone for a while: a pad that drifts a little should not move him.
4. Check the roll, the jab then cross chain, the stairs and the ramp, and the scarf.
5. Press F4 to compare with the post effects off (F3 shows the debug overlay; Esc pauses and shows "Paused").
6. If you want to try the web build: download `all-divine-web` from the same run and unzip it. In that folder run `python3 -m http.server 8000`, then open http://localhost:8000 in a browser. Opening `index.html` straight from the folder does not work, because a browser will not load the game's `.wasm` file from a `file://` page.
7. Write what you see, good and bad, in `all-divine/notes/f0.md`.

## Known limits / notes for later

- **Forward+ parity.** Forward+ is the reference look, but the container has no GPU. CI now checks the Forward+ branches on every push, not only on a local run: the `render-forward-plus` job installs lavapipe (a software Vulkan driver) and runs `test_screen_post` (which includes the Forward+ against Compatibility check), `test_toon_palette` and `test_toon_world` in the real Forward+ renderer, and it is green. The whole suite also passes under `tools/test.sh --forward-plus` with lavapipe here. So the branches work and agree with Compatibility. That says nothing about speed or about how it looks on a real GPU, so your F4 comparison on the PC is still the last check.
- **Compatibility is washed out.** The container and a web build use Compatibility, which draws the world pastel and washed out: the engine adds shadowed light passes in sRGB. Forward+ on the PC is the reference look. A `toon_world` Compatibility branch is a follow-up before any web build. The web build is made by CI but has never been opened in a browser (see the owner checklist for how to serve it). It starts in its page, not fullscreen, because a browser refuses fullscreen until the player has pressed a key or clicked (`display/window/size/mode.web` in `project.godot`); the browser's own fullscreen works. Whether the game's Alt+Enter works there is untried.
- **No strafe clips.** Orientation warping covers 8-way movement. `tools/anim/retarget.py` is ready for CMU clips; check the legs on the first one (the CMU rest splay).
- **Liveliness uses engine internals.** It is applied once per tick through Godot 4.7.2 internals: the skeleton's manual callback plus `NOTIFICATION_UPDATE_SKELETON`. Re-check it on any engine upgrade.
- **`courtyard.tscn` is the source** after generation. Do not run `build_courtyard.gd` again; edit the scene.
- **Nodes under an instance need `[editable path="..."]`.** A scene that hangs nodes under a child of an instanced scene (as `main.tscn` does under `PixelStage/World`) must list that instance as editable, or the export drops those nodes and the build fails at startup. In the editor this is "Editable Children". The test `test_every_scene_keeps_all_its_nodes_through_the_exports_repack` catches it.
- **Exports.** Godot does not create the output folder: `mkdir -p out/linux out/windows out/web` first. The builds leave out `tests/` and `tools/`: nothing the game loads may live there (the game starts with `TestLogger` from `core/test_logger.gd`; `tests/tools/test_export_presets.gd` checks it). A zip from CI loses the Linux build's executable bit: `chmod +x`. No icon and no code signing yet.

## Decisions

- Spec: [`docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md`](../docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md)
- Plan: [`docs/superpowers/plans/2026-10-25-all-divine-rpg-f0-foundation.md`](../docs/superpowers/plans/2026-10-25-all-divine-rpg-f0-foundation.md)
- CI: [`.github/workflows/all-divine.yml`](../.github/workflows/all-divine.yml) (jobs: `test`, `render`, `render-forward-plus`, `export`; `export` waits for `test`, and uploads the builds before it runs the Linux one)
- Rulings made while building, and the deferred review minors (the F1 polish backlog): [`docs/superpowers/plans/2026-10-25-all-divine-rpg-f0-foundation-record.md`](../docs/superpowers/plans/2026-10-25-all-divine-rpg-f0-foundation-record.md)

## How to run

From the repository root:

```bash
bash all-divine/tools/setup.sh                 # once: Godot into all-divine/.tools/godot/ (add --templates, --bpy)
all-divine/tools/test.sh                       # every headless test; --filter=<part of a test id>
all-divine/tools/test.sh --render              # also the tests that need a display (xvfb, gl_compatibility)
all-divine/tools/test.sh --render --update-golden --filter=test_screen_post
                                               # rewrite tests/render/golden/post_scene_compat.png, the screen look in
                                               # Compatibility, which a --forward-plus run compares Forward+ against
all-divine/tools/godot.sh --render <args...>   # any Godot call with a display; without --render it is --headless
python3 -I all-divine/tools/assets/fetch.py fetch all   # download, hash-check and extract the asset packs into .cache/ (--accept-new records a changed hash)
python3 -I all-divine/tools/assets/import_kenney.py     # copy the listed Kenney town pieces into assets/env/kenney_town/
python3 -I -m unittest discover -s all-divine/tools/assets/tests   # the Python tools' tests
all-divine/tools/bpy_test.sh                   # the bpy tools' tests (tools/anim/tests; builds Abarax and retargets synthetic BVHs into temp files)
all-divine/tools/.venv/bin/python -I all-divine/tools/anim/build_abarax.py \
    --ubc "$(python3 -I all-divine/tools/assets/fetch.py path ubc)" --outfits "$(python3 -I all-divine/tools/assets/fetch.py path outfits)" \
    --out all-divine/assets/characters/abarax/abarax.glb   # rebuild Abarax's model (same bytes every time), then tools/test.sh reimports it
all-divine/tools/.venv/bin/python -I all-divine/tools/anim/retarget.py --bvh clip.bvh --map all-divine/tools/anim/bonemap_cmu.json \
    --target all-divine/assets/characters/abarax/abarax.glb --tpose-clip A_TPose --name clip --out all-divine/out/retarget/clip.glb \
    --tpose "$(python3 -I all-divine/tools/assets/fetch.py path ual1)/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
                                               # a CMU BVH (cgspeed joint names) onto Abarax's skeleton, by world-space rotation change from rest on top
                                               # of the T-pose reference; the hips travel is scaled by hip height. Writes Abarax's model with the one clip
all-divine/tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 "$(python3 -I all-divine/tools/assets/fetch.py path ual1)" \
    --ual2 "$(python3 -I all-divine/tools/assets/fetch.py path ual2)"   # fetch.py fetch ual2 first
                                               # rebuild assets/anim/abarax/ from assets/anim/clips.cfg (marks on existing clips are kept), then godot.sh --import
all-divine/tools/godot.sh -s res://tools/clip_check.gd   # every move's marks and every actor's required clips against the rules; prints "clip_check: N moves, M actors OK" or each problem, exit 1
all-divine/tools/godot.sh -s res://tools/anim/set_marks.gd -- res://assets/anim/abarax/palm_jab.tres marks.json
                                               # write a clip's marks from [{"frame": 10, "kind": "hitbox_on", "args": {"id": "palm_l"}}, ...]; replaces its Marks tracks
all-divine/tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- --def res://data/actors/abarax.tres --out out/sheets/abarax.png
                                               # a contact sheet of the actor's clips in its palette (--clips a,b for some; --rig <rig.tscn>
                                               # instead of --def for a bare rig in its imported materials); a relative --out lands under all-divine/
all-divine/tools/godot.sh -s res://tools/art/make_textures.gd   # write assets/env/textures/flagstone.png (seeded: the same bytes every run)
all-divine/tools/godot.sh -s res://tools/world/build_courtyard.gd
                                               # how world/courtyard/courtyard.tscn was made from layout.txt, once: the scene is the
                                               # source now, and building again would overwrite whatever was changed in it
all-divine/tools/godot.sh -- --selftest        # the game (main/main.tscn) runs a scripted circuit of the courtyard for 600 physics
                                               # frames and exits 0, or 1 if anything logged an error from startup on, or if the
                                               # circuit never began (core/self_test.gd); add --fixed-fps 60 for full speed
bash all-divine/tools/setup.sh --templates     # once, for exports: the export templates (1.3 GB download, cached in .cache/)
mkdir -p all-divine/out/linux all-divine/out/windows all-divine/out/web
all-divine/tools/godot.sh --export-release "Linux" out/linux/all-divine.x86_64   # likewise "Windows Desktop" out/windows/all-divine.exe
                                               # and "Web" out/web/index.html (presets in export_presets.cfg; paths are relative to all-divine/)
all-divine/out/linux/all-divine.x86_64 --headless -- --selftest   # the built game's own self-test: exit 0
(cd all-divine/out/web && python3 -m http.server 8000)  # then open http://localhost:8000; the .wasm does not load from file://
all-divine/tools/test.sh --forward-plus --filter=test_screen_post # the real Forward+ renderer; needs Vulkan (a GPU, or lavapipe: apt install mesa-vulkan-drivers)
all-divine/.tools/godot/Godot_v4.7.2-stable_linux.x86_64 --path all-divine
                                               # play (starts fullscreen; F11 or Alt+Enter for a 1280×720 window and back):
                                               # WASD or the left stick to move, Space/Shift (A) to roll and hold to
                                               # sprint, left mouse (RB) to jab; F3 the debug overlay, F4 the screen look
                                               # off and on, Esc (Start) to pause
```

Every file under `assets/` needs a row in [`ASSETS.md`](ASSETS.md); `tests/tools/test_ledger.gd` checks it.

A test is a method named `test_*` in a `tests/**/test_*.gd` file that extends `TestCase`. Its id is `res://tests/area/test_x.gd::test_y`.

## Toolchain

- Godot 4.7.2-stable (`4.7.2.stable.official.ed1daf0bf`), downloaded by `tools/setup.sh` and checked against the release's `SHA512-SUMS.txt`.
- bpy 5.2.3 on Python 3.13, in `tools/.venv` (`tools/setup.sh --bpy`).
