# The All-Divine: STATE

What is done, what is next, and where the decisions live. Every task's final commit adds a line under Done.

## Done

- F0 Task 1: toolchain, project skeleton and the headless test runner (`tools/test.sh`: 4 passed, 0 failed).
- F0 Task 2: Core autoloads: Game, Inputs (§4.1 bindings, rebinding, deadzone), Registry, audio buses (`tools/test.sh`: 85 passed, 0 failed).

## Next

F0 Task 3

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
```

A test is a method named `test_*` in a `tests/**/test_*.gd` file that extends `TestCase`. Its id is `res://tests/area/test_x.gd::test_y`.

## Toolchain

- Godot 4.7.2-stable (`4.7.2.stable.official.ed1daf0bf`), downloaded by `tools/setup.sh` and checked against the release's `SHA512-SUMS.txt`.
- bpy 5.2.3 on Python 3.13, in `tools/.venv` (`tools/setup.sh --bpy`).
