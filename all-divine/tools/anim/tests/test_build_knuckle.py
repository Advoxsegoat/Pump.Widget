"""Tests for tools/anim/build_knuckle.py: the real build, run once into a temporary GLB, and the guard of the build
steps it shares with build_abarax.py (bpy_common.py): Abarax's model is rebuilt byte for byte.

Needs bpy (run with tools/bpy_test.sh) and the ubc and outfits packs extracted by
`python3 -I tools/assets/fetch.py fetch ubc` / `... fetch outfits`. Each build takes a few seconds.
"""
import hashlib
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_inspect  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_build_abarax import BASE, pack_path  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]  # the all-divine folder
BUILD = ROOT / "tools" / "anim" / "build_knuckle.py"
BUILD_ABARAX = ROOT / "tools" / "anim" / "build_abarax.py"
ABARAX_GLB = ROOT / "assets" / "characters" / "abarax" / "abarax.glb"
KNUCKLE_GLB = ROOT / "assets" / "characters" / "knuckle" / "knuckle.glb"

# The slot table (tools/anim/build_knuckle.py): which slots each mesh may carry, and those it must.
SKIN, HAIR, EYES, MAIN, SEC, PANTS, BOOTS, HOOD, METAL = range(9)
SLOTS_BY_MESH = {
    "Knuckle_Head": {SKIN, HAIR, EYES},
    "Knuckle_Hair": {HAIR},
    "Knuckle_Beard": {HAIR},
    "Knuckle_Body": {MAIN, SEC, METAL},
    "Knuckle_Legs": {PANTS, SEC, METAL},
    "Knuckle_Arms": {SKIN, MAIN, SEC, METAL},
    "Knuckle_Boots": {BOOTS, METAL},
    "Knuckle_Hood": {HOOD, SEC},
    "Knuckle_Pauldron": {METAL, SEC},
}
MUST_HAVE = {
    "Knuckle_Head": {SKIN, HAIR, EYES},
    "Knuckle_Hair": {HAIR},
    "Knuckle_Beard": {HAIR},
    "Knuckle_Body": {MAIN, SEC},
    "Knuckle_Legs": {PANTS},
    "Knuckle_Arms": {SKIN},
    "Knuckle_Boots": {BOOTS},
    "Knuckle_Hood": {HOOD},
    "Knuckle_Pauldron": {METAL},
}


def run(script, out):
    """Runs a model build into `out` and returns (exit status, combined output)."""
    done = subprocess.run(
        [sys.executable, "-I", str(script), "--ubc", pack_path("ubc"), "--outfits", pack_path("outfits"), "--out", str(out)],
        capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class BuildKnuckle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = Path(cls.tmp.name) / "knuckle.glb"
        status, cls.output = run(BUILD, cls.path)
        if status != 0 or not cls.path.is_file():
            cls.tmp.cleanup()
            raise AssertionError(f"build_knuckle.py failed (exit {status}):\n{cls.output}")
        cls.j = gltf_inspect.load(cls.path)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_triangle_budget_with_every_part(self):
        # Every part is in the model (a tier hides some in the game, never in the file), all of it within the budget.
        tris = gltf_inspect.triangle_count(self.j)
        self.assertTrue(1500 <= tris <= 4000, tris)
        drawn = {self.j["meshes"][n["mesh"]]["name"] for n in self.j["nodes"] if "mesh" in n}
        self.assertEqual(drawn, set(SLOTS_BY_MESH), "every part is drawn once")

    def test_parts_slots_and_skeleton(self):
        self.assertEqual(sorted(m["name"] for m in self.j["meshes"]), sorted(SLOTS_BY_MESH))
        for mesh, allowed in SLOTS_BY_MESH.items():
            slots = gltf_inspect.uv2_slots(self.j, self.path, mesh=mesh)
            self.assertTrue(slots <= allowed, f"{mesh}: {sorted(slots)} not within {sorted(allowed)}")
            self.assertTrue(MUST_HAVE[mesh] <= slots, f"{mesh}: {sorted(slots)} lacks {sorted(MUST_HAVE[mesh] - slots)}")
        self.assertEqual(gltf_inspect.uv2_slots(self.j, self.path), set(range(9)), "all nine slots are used")
        names = gltf_inspect.joint_names(self.j)
        self.assertEqual(len(names), 65, "no scarf: the 65 joints of the base")
        self.assertEqual(set(names), set(BASE))
        self.assertEqual(len(self.j["skins"]), 1, "one skeleton")
        # The rest pose is Abarax's, so the one clip library plays on both.
        abarax = gltf_inspect.joint_positions(gltf_inspect.load(ABARAX_GLB))
        knuckle = gltf_inspect.joint_positions(self.j)
        parents_a = gltf_inspect.joint_parents(gltf_inspect.load(ABARAX_GLB))
        parents_k = gltf_inspect.joint_parents(self.j)
        for name in BASE:
            self.assertLess(math.dist(abarax[name], knuckle[name]), 1e-4, f"{name} stands where Abarax's does")
            self.assertEqual(parents_k[name], parents_a[name], f"{name}'s parent")

    def test_no_textures_one_material_and_skinned(self):
        self.assertEqual(self.j.get("images", []), [])
        self.assertEqual(self.j.get("textures", []), [])
        self.assertEqual([m["name"] for m in self.j["materials"]], ["toon"])
        self.assertEqual(self.j.get("animations", []), [])
        for mesh in self.j["meshes"]:
            for prim in mesh["primitives"]:
                attrs = set(prim["attributes"])
                self.assertTrue({"POSITION", "NORMAL", "TEXCOORD_0", "TEXCOORD_1", "JOINTS_0", "WEIGHTS_0"} <= attrs,
                                f"{mesh['name']}: {sorted(attrs)}")
                self.assertFalse(any(a.startswith("COLOR_") for a in attrs), f"{mesh['name']}: {sorted(attrs)}")
        skinned = [n for n in self.j["nodes"] if "mesh" in n]
        self.assertTrue(skinned and all(n.get("skin") == 0 for n in skinned), "every mesh node uses the one skin")

    def test_build_is_deterministic_and_is_the_committed_model(self):
        again = Path(self.tmp.name) / "again.glb"
        status, output = run(BUILD, again)
        self.assertEqual(status, 0, output)
        self.assertEqual(again.read_bytes(), self.path.read_bytes())
        self.assertEqual(sha256(KNUCKLE_GLB), sha256(self.path), "assets/characters/knuckle/knuckle.glb is this build")


class SharedSteps(unittest.TestCase):
    def test_abarax_rebuild_is_byte_identical(self):
        # The build steps the two scripts share (bpy_common.py) were moved out of build_abarax.py: the committed model
        # comes out of it byte for byte.
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "abarax.glb"
            status, output = run(BUILD_ABARAX, out)
            self.assertEqual(status, 0, output)
            self.assertEqual(sha256(out), sha256(ABARAX_GLB))


if __name__ == "__main__":
    unittest.main()
