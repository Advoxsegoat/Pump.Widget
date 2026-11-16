#!/usr/bin/env python3
"""Copies the Kenney Fantasy Town Kit pieces listed in kenney_town_pieces.txt, and the shared
Textures/colormap.png, from the fetched pack into assets/env/kenney_town/.

    python3 -I tools/assets/import_kenney.py

Run `python3 -I tools/assets/fetch.py fetch kenney_town` first. The pieces are copied unchanged.
The .glb files point at Textures/colormap.png relatively, so that layout is kept. Only the listed
pieces are copied; one the pack lacks is an error and nothing is copied.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # tools/assets itself, our own code
import fetch  # noqa: E402

PACK_ID = "kenney_town"
MODELS = Path("Models") / "GLB format"
TEXTURE = Path("Textures") / "colormap.png"  # relative to both MODELS and the destination
PIECES = HERE / "kenney_town_pieces.txt"
DEST = fetch.ROOT / "assets" / "env" / "kenney_town"


def read_pieces(pieces_file):
    """Piece names from the list file; blank lines and # comments are skipped."""
    names = []
    for line in Path(pieces_file).read_text(encoding="utf-8").splitlines():
        name = line.strip()
        if not name or name.startswith("#"):
            continue
        if not re.fullmatch(r"[a-z0-9-]+", name):
            raise ValueError(f"{pieces_file}: '{name}' is not a piece name")
        if name not in names:
            names.append(name)
    return names


def import_pieces(src, dest, pieces_file):
    """Copies the listed pieces and the texture from the pack folder `src` into `dest`. Returns
    the copied paths relative to `dest`."""
    src, dest = Path(src), Path(dest)
    plan = [(Path(f"{name}.glb"), src / MODELS / f"{name}.glb") for name in read_pieces(pieces_file)]
    plan.append((TEXTURE, src / MODELS / TEXTURE))
    missing = [str(source.relative_to(src)) for _, source in plan if not source.is_file()]
    if missing:
        raise FileNotFoundError("missing from the Kenney pack: " + ", ".join(missing))
    for relative, source in plan:
        target = dest / relative
        if target.is_file() and target.read_bytes() == source.read_bytes():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
    return [relative.as_posix() for relative, _ in plan]


def main():
    src = fetch.extract_dir(fetch.ROOT, PACK_ID)
    if not src.is_dir():
        print(f"import_kenney.py: {src} is missing; run: python3 -I tools/assets/fetch.py fetch {PACK_ID}", file=sys.stderr)
        return 1
    try:
        copied = import_pieces(src, DEST, PIECES)
    except (OSError, ValueError) as error:
        print(f"import_kenney.py: {error}", file=sys.stderr)
        return 1
    print(f"copied {len(copied)} files to {DEST}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
