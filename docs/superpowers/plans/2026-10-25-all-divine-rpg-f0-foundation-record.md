# F0 Foundation: rulings and deferred minors

This is the record of the F0 build (plan `2026-10-25-all-divine-rpg-f0-foundation.md`).
It was copied word for word from the build ledger before the scratch workspace was deleted. Model names were left out.

- **Rulings** are the calls made on the owner's behalf where the plan was silent, wrong or in conflict. Each says what it costs if it was the wrong call.
- **Deferred minors** are review findings left for later. Together they are the F1 polish backlog.

## Rulings (47, in the order they were made)

1. Ruling P1: Task 14's courtyard steps are built by build_courtyard.gd's own step helper, not by tests/support/terrain.gd (TestTerrain) — production code never depends on test support; the plan's "TestTerrain-style" means the same geometry — cost if wrong: a small duplicated step-mesh helper.
2. Ruling P2: Task 8's T-pose checker test uses a clip built in code that holds the skeleton's rest pose for its whole length, not the library's t_pose clip — "T-pose" in the spec means a clip that leaves the bind pose showing, and UAL's A_TPose may differ from the base's rest — cost if wrong: none; the real-data test still runs.
3. Task 1: Ruling: fix the plan-mandated noise — the error fixture runs in a child Godot process (run.gd via OS.execute, stderr captured), the self-test asserts on its PASS/FAIL lines and exit code; pass/fail/await fixtures stay in-process; the count "4 passed" stays — why: an always-noisy green run trains readers to skip ERROR lines and test.sh's import step greps ERROR — cost if wrong: one subprocess (~2 s) per run.
4. Task 1: Ruling: re-grade reviewer Minor 1 (quit(await _run()) hangs to the 900 s cap when _run hits a script error) to Important and fix it in the same round — why: this runner gates all 15 later tasks; a hang costs each implementer up to 15 min — cost if wrong: a 2-line change.
5. Ruling R1 (carried into Task 2 onward): tests that exercise an error or warning path assert on returned values / recorded problems, called inside a new TestCase helper `quietly(fn: Callable) -> Variant` (sets Engine.print_error_messages = false, calls, restores) — not via expect_error — so green runs print no ERROR/WARNING lines; production code that reports bad data also returns or records the problem (e.g. Registry.scan() -> PackedStringArray of problems). expect_error stays for the runner's own self-test. Why: probe showed print_error_messages=false also stops Logger callbacks, so silencing and capturing can't both happen in-process — cost if wrong: error paths are checked by their data rather than by the logged message.
6. Ruling R2: commit trailers name the model that wrote the commit — each subagent uses the attribution its own harness specifies; context.md updated. Task 1's pushed commit 555459b carries the controller's co-author line (controller amended it before learning this); left as is, not rewriting pushed history — cost if wrong: one commit's co-author line names the controller's model instead of the implementer's.
7. Task 3: Ruling: camera ortho size = 362/32 = 11.3125 m, not the plan's 11.25 — the World SubViewport is 362 px tall (1-px sub-pixel margin each side), so only 11.3125 keeps one texel = one internal pixel (32 texels/m, the spec's binding value); the visible 640×360 still spans 11.25 m — cost if wrong: one constant.
8. Task 3: Ruling R3: the `WARNING: Could not set V-Sync mode` line under --render comes from xvfb's GLX (present before Task 3) — the R1 noise gate for --render runs excludes exactly that line; tools/test.sh's render mode filters that one line from Godot's output so green render runs stay pristine — cost if wrong: one environmental engine warning hidden in container/CI render runs only.
9. Task 5: Ruling: keep the outfit's armature, not the base Superhero's — the outfit and hair are bound to it (inverse binds match to 1e-6), root→Head are identical, and the Superhero's limbs sit 2–3.4 cm wider; using it would bend sleeves/trousers off their joints — cost if wrong: limb proportions follow the regular-male skeleton rather than the superhero one.
10. Task 5: Ruling: accept the remaining deviations — scarf not decimated (its 4 bones need the cross-sections; others share 0.195 so the total is 3,790); strict head-face rule (every vertex leans on Head/neck_01); meshes/generate_lods=false (LODs would change the ~58 px silhouette and merge palette slots); smooth normals after decimation; weld 1e-5 m before decimation; part names Abarax_*/Male_Peasant_*, UV2.y = 0.5; scarf weighting; extra gltf_inspect helpers — each is a sound implementation choice the brief left open — cost if wrong: small, local reverts.
11. Ruling R4 (Task 6): ClipBuilder keeps rotation tracks for every bone but position tracks only for `root` and `pelvis`, and drops scale tracks that stay at identity — UAL clips were authored on the UAL mannequin, and other bones' position tracks would impose its bone lengths on Abarax's skeleton — cost if wrong: an animation that genuinely moves a non-root bone's position (none in F0's clip list) loses that motion.
12. Task 6: Ruling: widen test plausibility bounds to walk 0.9–2.2 and sprint 4.5–8.5 — the measurement is the prescribed one and the plan's ranges were estimates — cost if wrong: none (bounds only).
13. Task 6: Ruling R5: ClipBuilder scales the `pelvis` and `root` position tracks by hip_ratio = Abarax rest pelvis height / UAL mannequin rest pelvis height (each from its own skeleton's rest pose), so feet meet the ground and root motion and ground speeds match Abarax's longer legs — fixed in Task 6 before review because Tasks 7, 8, 9 and 13 build on these clips — cost if wrong: root motion and ground speeds shift by the ratio (~5%).
14. Ruling R6 (forward, Task 8): MoveData gets `@export var root_motion_scale := 1.0`; dodge_roll's data sets it so the roll covers about 3 m (Souls-standard), and Task 9's root-motion test checks displacement = clip root displacement × scale — content is data, so roll distance stays tunable without re-authoring clips — cost if wrong: one field the owner can set back to 1.0.
15. Task 6: Ruling: widen jog to 2.5–6.0 and sprint to 4.5–9.0 — consequence of R5's scaling — cost if wrong: none (test bounds).
16. Task 7: Ruling: accept `await ContactSheet.render(...)` (render must wait frames for labels/layout/skinning) — cost if wrong: none.
17. Task 7: Ruling: the scarf sinking into the back in idle/walk and through the body in jog/roll is Task 13's to fix (SpringBoneSimulator3D with the spine_03 collision capsule and test_scarf_stays_out_of_the_torso) — carry into Task 13's dispatch — cost if wrong: if the spring bone can't keep it out, Task 5's scarf rest angle needs a revisit.
18. Task 7: Ruling: fix it — sample only the actor region below the label band and assert it differs from the background colour; pose-difference check compares actor regions only — the plan's ">4 colours" check was meant to prove the actor is drawn — cost if wrong: none.
19. Task 8: Ruling: accept — same-frame marks on parallel `Marks` method tracks (Godot merges same-time method keys; Task 9 reads only via Marks.read); Marks.between ±1e-5 s tolerance for float32 key times; ClipChecker in tools/clip_checker.gd with the CLI loading it at run time; checker extras (cancel-reachable moves, unreachable moves); move costs/damage left 0 (F1 sets them) — sound choices the brief left open — cost if wrong: small, local.
20. Task 9: Ruling: the large-delta test uses two 0.3 s ticks, not 0.1 s — the plan's two 0.1 s ticks only reach jab f12, before hitbox_off at f15, so the plan's own assertion couldn't hold — cost if wrong: none (same property tested).
21. Task 9: Ruling: MoveRunner's `mark` signal fires for every mark kind, not only fx/sfx/shake/hitstop — the plan's large-delta test expects hitbox_on/off among the signals; listeners filter by kind — cost if wrong: listeners see more kinds than they need.
22. Task 9: Ruling: accept Locomotion.carry (locomotion inherits the move's speed so you leave a jab at 0, not popping back to jog), the move's last-step motion on its end frame, gravity off the floor, PlayerBrain.screen_move() as the drift-test hook — feel/robustness choices the brief left open — cost if wrong: small, tunable.
23. Task 10: Ruling: toon_character.gdshader keeps the brief's maths for Forward+ and Mobile; in Compatibility (CURRENT_RENDERER == RENDERER_COMPATIBILITY) it writes no EMISSION and each light writes compatibility_linear(srgb(deep + max(0, (tone − deep) × LIGHT_COLOR/PI))) / ALBEDO — GLES3's sRGB decode (cubic) and encode (1.055x^(1/2.4) − 0.055) aren't inverses (up to 6/255 off) and shadowed lights draw in separate passes added in sRGB, so emission must be 0 for one light to be exact in both pass types — result: exact palette tones under one white light and Forward+'s output for any single light — cost if wrong: in Compatibility only (web build, container renders), pixels no light reaches are black instead of the deep tone; several shadowed lights sum too bright; very saturated dyes can miss by a few steps.
24. Task 10: Ruling: accept contact-sheet sun energy 0.75 → 1.0 (cells show true tones), 8-bit-rounded tones, Palette.from_bases and Rig.toon_material helpers — cost if wrong: none.
25. Task 10: Ruling: the fallback was the controller's own dispatch instruction — withdrawn; the finding stands — ContactSheet CLI gains `--def <actor.tres>` (render() already accepts a def), FALLBACK_PALETTE is removed (a bare rig keeps its imported materials, as in the game), the sheet is regenerated from data/actors/abarax.tres, and the sheet test asserts the def's palette — a tool must not bake one character's colours into another's sheet — cost if wrong: none.
26. Task 11: Ruling: Forward+ parity of the post shaders is verified by Task 16's CI job (`--forward-plus --filter=test_screen_post`, lavapipe); in the container only the branches' compilation is checked — cost if wrong: a Forward+-only defect surfaces in CI or on the owner's PC.
27. Task 11: Ruling: accept that Compatibility over-brightens toon_world lighting (each shadowed light, the sun included, is added in sRGB by the engine) — affects container/web renders only; the owner's Forward+ build is the reference look; Task 14 judges the courtyard shot and records whether a toon_world Compatibility branch (like toon_character's) is needed — cost if wrong: washed-out container contact shots and web preview until that branch exists.
28. Task 11: Ruling: accept effects starting off until apply_settings is called; Task 14's main.gd calls apply_settings(default_settings, region.grade) as the plan says — cost if wrong: none.
29. Task 12: Ruling: accept — pose test compares against an unwarped rig (idle clip stands ~13° turned); hips ease in over 0.05 s; warp fades out while a move plays; sprinting ignores the face target (no reversed sprint); bone_turn.gd helper — feel/robustness choices the brief left open — cost if wrong: small, tunable.
30. Task 12: Ruling: fix it — keep OrientationWarp.solve pure; Rig.set_strafe applies hysteresis keyed on its last `backward`: switch to backward only past 115°, back to forward only below 105° (±5° around the plan's 110°) — the owner's "no robot mechanics" priority outweighs the plan's single threshold — cost if wrong: within the 10° band the legs keep their previous direction.
31. Task 13: Ruling: accept — the brief's foot formula applies only to planted feet (on lifted feet it dragged strides and hips 0.366 m down in a jog); ground floor on offsets; pelvis collision capsule; look point clamped to ±70°/±35° of facing; look modifiers always aim at LookTarget and fade by influence (a target-less LookAtModifier3D turns the neck 27–45° off the clip in 4.7.2; regression test); contact sheet ticks each cell in the physics step (IK/look aimed a frame late outside it with physics interpolation; Rig.tick documents the rule); scarf tests strengthened to check every scarf joint against the torso (the brief's passed with the spring off) — cost if wrong: small, local.
32. Task 13: Ruling: re-grade reviewer Minor 1 (hips pop up to 0.059 m in one tick walking up stairs at 0.45 stick — the floor removes upward smoothing and pelvis_offset inherits it) to Important by effect — it's the robotic pop the owner will feel on the courtyard stairs in Task 14, and the fix is cheap (take the pelvis drop from the pre-floor smoothed offsets, or smooth the pelvis separately; add a per-tick |Δpelvis| bound to the stairs test) — cost if wrong: one small extra fix round.
33. Task 13: Ruling: re-grade reviewer Minor 2 (scarf-out-of-torso test covers only idle/jog/turn/roll) to Important — Task 7's carried ruling requires every clip; add a loop over all 8 clips (reviewer measured min torso clearance 0.146 m roll, so it should pass) — cost if wrong: one test.
34. Task 13: Ruling: the stairs test's per-tick |Δpelvis| bound may be set from the smoothing cascade's stated bound (~0.022 m at 0.45 stick) rather than forcing 0.02 — the goal is no visible pop and 0.060 → 0.022 m meets it — cost if wrong: ~2 mm more hip rise per tick than the controller's first number.
35. Task 13: Ruling: keep the brief's 0.5 m foot-probe reach for F0 — a high-stepping foot near the bottom of stairs loses its ground and fades its offset, but the double smoothing removes the visible pop; probing from the foot's planted height is the better fix and is deferred (changes the brief's probe) — cost if wrong: slightly less accurate foot planting on the first stair.
36. Task 14: Ruling: accept the Compatibility washout for F0 (Forward+ on the owner's PC is the reference); a toon_world Compatibility branch (like toon_character's) is a follow-up before any web build — cost if wrong: the web/container preview looks pastel until then.
37. Task 14: Ruling: accept the shared-shader changes — toon_world lanterns light only what they reach (Compatibility lit everything in range), walls/risers show flagstones not stripes; toon_character in Compatibility gives nothing for a lantern too weak to lift a tone (was washing Abarax out) — each has a test that failed first — cost if wrong: small, local.
38. Task 14: Ruling: accept Kenney pieces getting toon_world + colormap via their import settings (data, not per-instance overrides); perf test times each physics step itself (TIME_PHYSICS_PROCESS updates once a second and reads 0 under --fixed-fps) — cost if wrong: none.
39. Task 15: Ruling: accept gltf_inspect animation readers (tests read the output independently of Blender), BVH positions read as absolute (cgspeed style), Y-up/+Z-facing BVH, output GLB = Abarax's model + the one animation — cost if wrong: small.
40. Task 16: Ruling: accept `[editable path="PixelStage"]` in main.tscn plus a guard test over every scene — the export dropped Region/Player/CameraRig hung under an instanced PixelStage/World (exported --selftest exit 139) — a real bug the plan missed — cost if wrong: none.
41. Task 16: Ruling: accept the extra "Python tools' tests" CI step — it runs only tools/assets/tests (stdlib, local fake site, no network/packs); bpy tests stay local — cost if wrong: a few seconds of CI.
42. Task 16: Ruling: keep the Forward+ job's three shader-test steps (test_screen_post, test_toon_palette, test_toon_world) rather than the brief's one — those Forward+ branches were never rendered before, so the coverage is the point — cost if wrong: a pixel-tolerance failure on the runner's Mesa (then narrow it).
43. Final: Ruling: fix Important 1 as the reviewer proposes (null-Object and freed-object equal null in _same; self-tests; every `if x == null: return` after an assert becomes fail()) — cost if wrong: none (suite verified green with the patch).
44. Final: Ruling: Important 2 — raise the radial deadzone to 0.28 (covers per-axis drift up to 0.19 on both axes: length 0.269) with remap (|v| − 0.28)/0.72, keeping the circular feel; the plan's 0.2 is superseded — cost if wrong: the first 0.28 of stick travel does nothing (Souls-typical), tunable in one constant.
45. Final: Ruling: Important 3 — start in borderless fullscreen (×3 at 1080p, ×4 at 1440p, ×6 at 4K) with F11 and Alt+Enter toggling a 1280×720 window (×2) — the spec names 1080p at ×3 and the owner's first impression is checklist step 1 — cost if wrong: owners who prefer windowed press F11 once.
46. Final: Ruling: also fix in this wave (cheap, owner-facing or enforcing the spec): CI export `needs: [test]` (spec: the build fails when the clip checker fails), uploads before the Linux runtime checks, `permissions: contents: read`; ASSETS.md assets/anim/ row text (R4/R5, our clips.cfg); a PathCheck negative test; project.godot stale TestLogger comment; a "Paused" label on Esc; contact_sheet test null from_rig; STATE.md F1 notes (self-hit filter, crossfade guard for cancels inside blend_in, cancel-reset tests at F1 start), Forward+ now CI-verified, how to serve the web build, fullscreen/F11 in the checklist — cost if wrong: a slightly bigger fix wave.
47. Final: Ruling: accept `display/window/size/mode.web=0` (windowed on web — browsers refuse fullscreen at boot) — cost if wrong: the web build opens windowed.

## Deferred minors (106)

- Task 1: minor (deferred): no committed tests for hook order, track() freeing, warnings ignored, (load) failure path, assert_near/ne/vec_near, update_golden, --expect-method; PathCheck has no negative test. **Since then:** the PathCheck negative test came in 2d077ab; the rest of this line is still open.
- Task 1: minor (deferred): --filter=<file>::test_x hides that file's load failure (shows "no tests ran").
- Task 1: minor (deferred): no per-test timeout; a never-firing await stalls to the shell cap.
- Task 1: minor (deferred): setup.sh doesn't pin the known SHA-512 prefixes (9aa00f7a zip, ca4d71c4 templates); it trusts SHA512-SUMS.txt from the same origin.
- Task 1: minor (deferred): run_crashes child check asserts only exit code, not the SCRIPT ERROR line; run.gd unknown arg exits 1 (was 2); nested-runner error routing no longer covered in-process.
- Task 2: minor (deferred): rebind() with an unknown action crashes (no ACTIONS guard).
- Task 2: minor (deferred): trigger deadzone 0.5 chosen by action name (heavy/gift), not by event type.
- Task 2: minor (deferred): `name` shadows Node.name in inputs.gd:398 and test_audio.gd:671 (editor SHADOWED_VARIABLE_BASE_CLASS warning).
- Task 2: minor (deferred): test name "…does_not_warn" can't assert the no-warning part (warnings never fail tests).
- Task 2: minor (deferred): registry.gd:558 StringName(resource.get(&"id")) errors on a non-string id; report as a problem instead.
- Task 2: minor (deferred): quietly() also hides genuine script errors in the callable — keep callables to the single call under test; doc comment.
- Task 2: minor (deferred): duplicated same_event lambda in rebind (inputs.gd:390, :402).
- Task 2: minor (deferred): rebind swap hands the other action the old event (e.g. move_left → D-pad left gives slot_left the left-stick X) — specified semantics, but a rebind UI must expect it.
- Task 3: minor (deferred): Review Focus 3 (interpolated follow) only tested via the project setting; swapping to global_position passes all tests.
- Task 3: minor (deferred): World size stated twice (WORLD_SIZE const vs tscn 642×362) — set world.size = WORLD_SIZE in _ready or assert.
- Task 3: minor (deferred): PixelStage.world is @onready (null before the stage enters the tree) — carry a pointer into Tasks 7, 11, 14.
- Task 3: minor (deferred): only 1366×768 (k=2) rendered; k=4 side bars and sub-640×360 crop untested at render level.
- Task 3: minor (deferred): test_follow_eases_instead_of_jumping bound (0.95 vs 0.931 at 6 frames) is coupled to frame count.
- Task 3: minor (deferred): reassigning CameraRig.target doesn't reset _has_follow; snap_now needs reset_physics_interpolation on teleported targets (documented).
- Task 3: minor (deferred): with stdout piped through the awk filter, Godot may block-buffer, so render-run progress may arrive in bursts (content and exit codes unaffected).
- Task 4: minor (deferred): loopback http allowance for tests lives in the production URL gate (redirects/itch JSON url could target local services; low impact).
- Task 4: minor (deferred): retry/_transient, short-read and redirect-guard paths untested.
- Task 4: minor (deferred): hash recorded before extraction succeeds; RuntimeError/NotImplementedError from safe_extract escape main's except and abort `fetch all`.
- Task 4: minor (deferred): no zip-bomb cap (entry count / uncompressed size) on first fetch.
- Task 4: minor (deferred): --accept-new can't refresh a pack whose cached zip matches the old hash (needs cache delete or --refresh).
- Task 4: minor (deferred): import_kenney doesn't check the extract's hash marker.
- Task 4: minor (deferred): sha256 normalisation repeated 3× in fetch.py; Ledger.scanned static out-param in test_ledger.gd.
- Task 5: minor (deferred): head-only crop has no test (a broken keep_head would still pass budget/slot tests) — assert Abarax_Head min y ≥ ~1.5 m.
- Task 5: minor (deferred): scarf clearance computed before decimation; no post-decimation guard (check neck/back on Task 7 sheet).
- Task 5: minor (deferred): armature world matrix assumed identity (head_local vs world_coords) — assert in build().
- Task 5: minor (deferred): build() doesn't fail outside 1,500–4,000 tris (only the unit test does).
- Task 5: minor (deferred): export() loses captured exporter stdout on exception.
- Task 5: minor (deferred): gltf_inspect._buffers reads path.parent/uri without containment or percent-decoding.
- Task 5: minor (deferred): no drift test comparing committed abarax.glb to a fresh build.
- Task 5: minor (deferred): nits — unused k in build_scarf; build_scarf ~80 lines; test_abarax_model.gd:20 indexes skeletons[0] after a size assert; build error/main paths untested.
- Task 6: minor (deferred): ASSETS.md assets/anim/ row's Changes text omits R4/R5 modifications, says "marks added" before Task 8, and the CC0 row also covers our own clips.cfg. **Since then:** fixed in f1fa8c5.
- Task 6: minor (deferred): clip_builder.gd:30 points to moves/marks.gd (Task 8) — "Marks" track name will be defined twice; make Marks.TRACK the owner in Task 8.
- Task 6: minor (deferred): clips.cfg values unvalidated (negative length silently ignored; step_fps unchecked). **Since then:** F1 Task 2 reports a negative or non-numeric `length` and a `step_fps` that is not 0, 12 or 24, with every other problem in the list, through `ClipBuilder.check`.
- Task 6: minor (deferred): build() doc comment run-on line (clip_builder.gd:179); stale clip files not removed when a section leaves clips.cfg.
- Task 6: minor (deferred): Abarax skeleton loading repeated 6× in tests; hard-coded 0.9491 should say "rebuild the library" on failure.
- Task 7: minor (deferred): play_move during an unfinished crossfade reuses the fading slot (pop ≤ leftover blend; plan-mandated two slots) — doc + test; stop_move with nothing playing / set_move_time before play_move untested.
- Task 7: minor (deferred): negative gameplay time → no seek (slot free-runs); clamp with maxf(time, 0).
- Task 7: minor (deferred): stop_move freezes the current slot's clock during blend-out (note for Task 9).
- Task 7: minor (deferred): set_hitbox_active assigns monitoring directly — use set_deferred if called from area/body callbacks (note for Task 9).
- Task 7: minor (deferred): hold test lacks an unstepped control; crossfade/backward tests check parameters not poses.
- Task 7: minor (deferred): contact sheet CLI exits 0 on a partial sheet when a --clips name is unknown; instantiate() as Rig not null-checked; render() error paths untested.
- Task 7: minor (deferred): rig.gd silently leaves skeleton null when the model has no Skeleton3D.
- Task 7: minor (deferred): test_contact_sheet.gd comment nits (line 39 centre comment unclear; line 8 "picture of the actor" includes ground/shadow).
- Task 8: minor (deferred): clip_checker skips the T-pose rule silently when the rig has no Skeleton3D — report it.
- Task 8: minor (deferred): hitstop frames 3.5 passes via int(frames) — require whole numbers. **Since then:** F1 Task 3 removed the `hitstop` mark; hit-stop is `HitProfile.hitstop_frames`, an int, so a half frame cannot be written.
- Task 8: minor (deferred): _check_actor does four jobs + `reached` out-param — extract the BFS; _angle duplicated from test_rig.gd; reads Rig Hitboxes children by name (add Rig.hitbox_ids()).
- Task 8: minor (deferred): clip_check tests pin "3 moves, 1 actors" (will break in F1). **Since then:** F1 Task 1 took the counts from the Registry.
- Task 8: minor (deferred): InputBuffer same-frame tie rule (later push wins) untested.
- Task 8: minor (deferred): contact_sheet.gd keeps FRAME_RATE := 60 beside Marks.RATE.
- Task 8: minor (deferred): suite time 12 s → 24 s from 8 child-Godot tests; watch it.
- Task 9: minor (deferred): runner error paths (missing move id / missing clip) untested under quietly.
- Task 9: minor (deferred): drift test covers only 0.15 on +x; sweep 0.10/0.15/0.19 and a diagonal (0.13, 0.13).
- Task 9: minor (deferred): "vertical ignored" not asserted (root-motion test zeroes moved.y).
- Task 9: minor (deferred): carry puts the roll's ~10 m/s into locomotion.speed → rig.set_locomotion shows a run/sprint blend under the move layer during blend-in; pass 0 while runner.busy(). **Since then:** F1 Task 1 does that.
- Task 9: minor (deferred): runner writes actor.locomotion.facing_yaw / rotation.y directly (dodge snap) — add Actor.snap_facing(yaw). **Since then:** F1 Task 1 added it.
- Task 9: minor (deferred): re-entrancy guard compares by identity (same-move restart from a mark listener; start() from a move_ended listener overwritten).
- Task 9: minor (deferred): press-to-motion test's before-press equality loop skips missing frames silently.
- Task 10: minor (deferred): test_contact_sheet.gd:56 returns silently when from_rig is null. **Since then:** fixed in 2e88b43 (null guards now fail loudly).
- Task 10: minor (deferred): shader slot decode unclamped — clamp(…, 0, 15) so bad UV2 shows magenta not black (black pixels are skipped by _match_pixels).
- Task 10: minor (deferred): to_texture hides a short tones array (transparent black instead of magenta); no size check on load.
- Task 10: minor (deferred): apply_palette builds a fresh ImageTexture/material per actor (cache per palette for crowds).
- Task 10: minor (deferred): clamp test misses the shade's s × 1.1; wiring tests live in test_palette.gd (move to tests/actors).
- Task 10: minor (deferred): contact-sheet CLI (--def/--rig, exit codes 0/1/2) has no automated test; plan doc lines 721/762 still show the --rig form for Task 7.
- Task 11: minor (deferred): DOF test doesn't pin band/ramp (sample ground at two known ramp depths).
- Task 11: minor (deferred): compile test should assert the renderer is forward_plus (or skip loudly).
- Task 11: minor (deferred): post_uniforms map lives in pixel_stage.gd and CameraRig calls PixelStage statics for its material (coupling).
- Task 11: minor (deferred): PostQuad on the default visual layer — another camera/probe would draw screen_post over its view; give it a dedicated layer later.
- Task 11: minor (deferred): outline strength < 1.0 untested (dropping the outline factor in weight survives); diagonal creases have no render test.
- Task 12: minor (deferred): no hysteresis at the 110° forward/backward boundary (legs could flip on a held path); all actors breathe in sync (randomise phase per actor later). **Since then:** the hysteresis came in Task 12's fix round (115°/105°); the breathing-phase half came in F1 Task 1.
- Task 12: minor (deferred): strafe computed during moves (no runner.busy() guard) — a future backstep could show loco_scale −1 under the move layer during blends.
- Task 12: minor (deferred): breathing/hit react run smooth at 60 Hz over stepped moves (an 11° lean glides across held frames) — rule in F1 if it reads wrong.
- Task 12: minor (deferred): hit lean unbounded (kicks accumulate, no clamp); dir_world not normalised (length scales the kick) — normalise or document. **Since then:** F1 Task 1 capped the lean (HitReact.MAX_TILT) and normalised the direction.
- Task 12: minor (deferred): rig.gd:214-218 comment should name the 4.7.2 update-flag dependency.
- Task 12: minor (deferred): shown-pose copy every skeleton update even without modifiers; no test that breathing/hit react stay on over a move.
- Task 12: minor (deferred): orientation_warp.gd:5-6 class doc says "past 110°" (rig switches at 115°/105°); each band crossing swaps hips ±70° eased over 0.05 s (deliberate).
- Task 13: minor (deferred): walking up stairs an ankle can sit inside a step for one frame where it crosses a riser, then pops up.
- Task 13: minor (deferred): the scarf shows its old sunk pose for one frame right after spawn.
- Task 13: minor (deferred): look logic (7 fields, 3 functions) lives in Rig — extract a liveliness helper.
- Task 13: minor (deferred): foot-angle correction uses last tick's calf turn (one tick wrong after a pose jump).
- Task 13: minor (deferred): a POI's look point is its node origin (feet for actors) — add a look-point offset/head bone before speakers exist. **Since then:** F1 Task 1 added Actor.head_point() (ActorDef.look_height), which an actor POI is looked at by.
- Task 13: minor (deferred): structure test doesn't assert pole_node → IKPole_*; report miscounted new tests (31, not 34).
- Task 13: minor (deferred): a stepping foot that leaves the 0.5 m probe reach still fades its own offset at up to ~0.054 m/tick (foot in the air; only the hips are eased) — see the probe-reach ruling; no descending-stairs test.
- Task 14: minor (deferred): self-test circuit's last leg steers from the assumed roll end, not Abarax's real position (fragile to roll/locomotion tuning).
- Task 14: minor (deferred): layer_bit duplicated (Builder vs TestArena) — shared helper in core/. **Since then:** F1 Task 1 added core/layers.gd.
- Task 14: minor (deferred): test_courtyard.gd:145 exempts meshes named "(_ignore)" (Kenney's (%ignore) water) without a comment.
- Task 14: minor (deferred): builder parser error paths untested; lenient parsing (`solidd` builds a wall without collision; fractional step counts truncated); Region.spawn() with no marker untested.
- Task 14: minor (deferred): toon_world uses mat3(MODEL_MATRIX)*NORMAL (not the normal matrix) — wrong plane choice under non-uniform scale near 45°.
- Task 14: minor (deferred): layout.txt:35 says "models/<PIECE>" (it's the MODELS constant, not a path).
- Task 14: minor (deferred): green self-test child check looks only for "ERROR" (add WARNING); assert_ne(code, 124) doesn't name the KILL case (137).
- Task 15: minor (deferred): hips never rotate in the test BVHs (hip translation+rotation branch untested).
- Task 15: minor (deferred): NaN/inf/huge numbers escape RetargetError (bare ValueError/OverflowError traceback; NaN frame time passes the <= 0 guard) — untrusted input; check math.isfinite and whole counts.
- Task 15: minor (deferred): fps_base != 1 and 120 fps paths untested; channel-order test asserts only rotation_order, not FK.
- Task 15: minor (deferred): implicit identity armature matrix_world assumption — assert it.
- Task 15: minor (deferred): STATE.md line landed in c2d2b62 not the final commit; bpy_test.sh header omits ual1; `reference = changes` rebinding; setUpClass temp-dir leak (use addClassCleanup); retarget.py ~500 lines (plan's single file).
- Task 15: minor (deferred): bpy_common.export_glb needs a pathlib.Path (undocumented); the byte-identity check wrote into the committed asset path rather than a scratch file (bytes identical).
- Task 16: minor (deferred): Linux runtime checks run before the artifact uploads — a harmless log line would withhold the Windows artifact (upload first, or if: !cancelled()). **Since then:** fixed in 44fcdad.
- Task 16: minor (deferred): STATE.md's Forward+ bullet says "They pass" from a local lavapipe run — reword after the first CI run. **Since then:** reworded in 94e70a8; CI run 41248829211 is green on Forward+.
- Task 16: minor (deferred): no "serve out/web with python3 -m http.server" line for the Web build; no `permissions: contents: read`; test_every_export_goes_under_out_which_git_ignores overclaims; push+pull_request double-runs; duplicated job preamble; a red export job never saves the trimmed templates cache (re-downloads 1.3 GB). **Since then:** the serve line (94e70a8) and `permissions: contents: read` (44fcdad) are done; the rest is still open.
- Final: minor (deferred): STATE.md's Forward+ parity claim ("and it is green") rests on the earlier CI run until CI on 94e70a8 confirms it **Since then:** confirmed: CI run 41248829211 on 94e70a8 is green on all 4 jobs.
- Final: minor (deferred): web build — mode.web=0 and Alt+Enter in a browser are expectations, untested in a browser
- Final: minor (deferred): gamepad feel — the 0.28 deadzone weakens light pushes (0.35 → 0.097); owner checklist step 3 covers it
