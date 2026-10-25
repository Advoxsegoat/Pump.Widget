# Asset ledger

Every file under `assets/` has a row here, and `tests/tools/test_ledger.gd` checks it. Assets are free and openly licensed only.

- **Path** is relative to the project folder. A path ending in `/` covers everything under that folder; any other path is one file. `.import` files are Godot's own and need no row.
- **Licence** is one of `CC0 1.0`, `ours` or `CMU (free for any use)`.
- **Changes** says what was done to the files after they were downloaded.
- Downloaded packs are fetched, hash-checked and extracted by `tools/assets/fetch.py`; the hashes are in `tools/assets/sources.json`.

| Path | Source | Licence | Changes |
|---|---|---|---|
| assets/env/kenney_town/ | Kenney Fantasy Town Kit 2.0, https://kenney.nl/assets/fantasy-town-kit | CC0 1.0 | pieces copied unchanged |
