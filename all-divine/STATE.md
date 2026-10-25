# The All-Divine: STATE

What is done, what is next, and where the decisions live. Every task's final commit adds a line under Done.

## Done

- F0 Task 1: toolchain, project skeleton and the headless test runner (`tools/test.sh`: 4 passed, 0 failed).
- F0 Task 2: Core autoloads: Game, Inputs (§4.1 bindings, rebinding, deadzone), Registry, audio buses (`tools/test.sh`: 93 passed, 0 failed).
- F0 Task 3: Pixel stage: 640×360 → integer upscale, texel-snapped ortho camera, sub-pixel offset (`tools/test.sh`: 108 passed, 0 failed; with `--render`: 111 passed, 0 failed).
- F0 Task 4: Asset intake (itch/Kenney fetch with hashes) and the ASSETS.md ledger check (`tools/test.sh`: 114 passed, 0 failed; with `--render`: 117 passed, 0 failed; Python tools: 28 passed).
- F0 Task 5: Abarax model: Quaternius head + peasant outfit + scarf bones, palette slots in UV2, ≤4,000 tris (`tools/test.sh`: 120 passed, 0 failed; with `--render`: 123 passed, 0 failed; `tools/bpy_test.sh`: 14 passed).
- F0 Task 6: Animation library: UAL clips extracted to text .tres, retimed, ground speeds measured, marks preserved on rebuild (`tools/test.sh`: 158 passed, 0 failed; with `--render`: 161 passed, 0 failed).
- F0 Task 7: Rig: AnimationTree (speed-blended locomotion, two-slot move layer, stepped playback), hitboxes, contact sheets (`tools/test.sh`: 175 passed, 0 failed; with `--render`: 181 passed, 0 failed).
- F0 Task 8: Moves: MoveData, marks on the Marks track, 9-frame input buffer, clip checker; jab, cross, roll (`tools/test.sh`: 274 passed, 0 failed; with `--render`: 280 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 9: Actor, brains (player, script), locomotion, move runner reading marks; buffer and cancel rules; press-to-motion ≤ 2 frames (`tools/test.sh`: 305 passed, 0 failed; with `--render`: 311 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).
- F0 Task 10: Character look: palette resource (ramps, dyes), toon shader held to the palette (`tools/test.sh`: 317 passed, 0 failed; with `--render`: 327 passed, 0 failed; `tools/clip_check.gd`: 3 moves, 1 actors OK).

## Next

F0 Task 11

## Decisions

- Spec: [`docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md`](../docs/superpowers/specs/2026-10-25-all-divine-rpg-foundation-design.md)
- Plan: [`docs/superpowers/plans/2026-10-25-all-divine-rpg-f0-foundation.md`](../docs/superpowers/plans/2026-10-25-all-divine-rpg-f0-foundation.md)
- Rulings made while building: [`.superpowers/sdd/2026-10-25-all-divine-rpg-f0-foundation/progress.md`](../.superpowers/sdd/2026-10-25-all-divine-rpg-f0-foundation/progress.md)

## How to run

From the repository root:

```bash
bash all-divine/tools/setup.sh                 # once: Godot into all-divine/.tools/godot/ (add --templates, --bpy)
all-divine/tools/test.sh                       # every headless test; --filter=<part of a test id>
all-divine/tools/test.sh --render              # also the tests that need a display (xvfb, gl_compatibility)
all-divine/tools/godot.sh --render <args...>   # any Godot call with a display; without --render it is --headless
python3 -I all-divine/tools/assets/fetch.py fetch all   # download, hash-check and extract the asset packs into .cache/ (--accept-new records a changed hash)
python3 -I all-divine/tools/assets/import_kenney.py     # copy the listed Kenney town pieces into assets/env/kenney_town/
python3 -I -m unittest discover -s all-divine/tools/assets/tests   # the Python tools' tests
all-divine/tools/bpy_test.sh                   # the bpy tools' tests (tools/anim/tests; builds Abarax into a temp file)
all-divine/tools/.venv/bin/python -I all-divine/tools/anim/build_abarax.py \
    --ubc "$(python3 -I all-divine/tools/assets/fetch.py path ubc)" --outfits "$(python3 -I all-divine/tools/assets/fetch.py path outfits)" \
    --out all-divine/assets/characters/abarax/abarax.glb   # rebuild Abarax's model (same bytes every time), then tools/test.sh reimports it
all-divine/tools/godot.sh -s res://tools/anim/build_library.gd -- --ual1 "$(python3 -I all-divine/tools/assets/fetch.py path ual1)"
                                               # rebuild assets/anim/abarax/ from assets/anim/clips.cfg (marks on existing clips are kept), then godot.sh --import
all-divine/tools/godot.sh -s res://tools/clip_check.gd   # every move's marks and every actor's required clips against the rules; prints "clip_check: N moves, M actors OK" or each problem, exit 1
all-divine/tools/godot.sh -s res://tools/anim/set_marks.gd -- res://assets/anim/abarax/palm_jab.tres marks.json
                                               # write a clip's marks from [{"frame": 10, "kind": "hitbox_on", "args": {"id": "palm_l"}}, ...]; replaces its Marks tracks
all-divine/tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- --rig res://actors/abarax/abarax_rig.tscn --out out/sheets/abarax.png
                                               # a contact sheet of the rig's clips (--clips a,b for some); a relative --out lands under all-divine/
```

Every file under `assets/` needs a row in [`ASSETS.md`](ASSETS.md); `tests/tools/test_ledger.gd` checks it.

A test is a method named `test_*` in a `tests/**/test_*.gd` file that extends `TestCase`. Its id is `res://tests/area/test_x.gd::test_y`.

## Toolchain

- Godot 4.7.2-stable (`4.7.2.stable.official.ed1daf0bf`), downloaded by `tools/setup.sh` and checked against the release's `SHA512-SUMS.txt`.
- bpy 5.2.3 on Python 3.13, in `tools/.venv` (`tools/setup.sh --bpy`).
