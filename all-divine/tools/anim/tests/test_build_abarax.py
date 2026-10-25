"""Tests for tools/anim/build_abarax.py: the real build, run once into a temporary GLB.

Needs bpy (run with tools/bpy_test.sh) and the ubc and outfits packs extracted by
`python3 -I tools/assets/fetch.py fetch ubc` / `... fetch outfits`. Each build takes a few seconds.
"""
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_inspect  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]  # the all-divine folder
BUILD = ROOT / "tools" / "anim" / "build_abarax.py"
FETCH = ROOT / "tools" / "assets" / "fetch.py"

BASE = [
    "root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
    "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
    "index_01_l", "index_02_l", "index_03_l", "index_04_leaf_l",
    "middle_01_l", "middle_02_l", "middle_03_l", "middle_04_leaf_l",
    "pinky_01_l", "pinky_02_l", "pinky_03_l", "pinky_04_leaf_l",
    "ring_01_l", "ring_02_l", "ring_03_l", "ring_04_leaf_l",
    "thumb_01_l", "thumb_02_l", "thumb_03_l", "thumb_04_leaf_l",
    "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
    "index_01_r", "index_02_r", "index_03_r", "index_04_leaf_r",
    "middle_01_r", "middle_02_r", "middle_03_r", "middle_04_leaf_r",
    "pinky_01_r", "pinky_02_r", "pinky_03_r", "pinky_04_leaf_r",
    "ring_01_r", "ring_02_r", "ring_03_r", "ring_04_leaf_r",
    "thumb_01_r", "thumb_02_r", "thumb_03_r", "thumb_04_leaf_r",
    "thigh_l", "calf_l", "foot_l", "ball_l", "ball_leaf_l",
    "thigh_r", "calf_r", "foot_r", "ball_r", "ball_leaf_r",
]
SCARF = ["scarf_01", "scarf_02", "scarf_03", "scarf_04"]

# The slot table (tools/anim/build_abarax.py): which slots each mesh may carry.
SLOTS_BY_MESH = {
    "Abarax_Head": {0},
    "Abarax_Brows": {1},
    "Abarax_Hair": {1},
    "Abarax_Eyes": {2},
    "Male_Peasant_Arms": {0, 3},
    "Male_Peasant_Body": {3, 4},
    "Male_Peasant_Legs": {5},
    "Male_Peasant_Feet": {6},
    "Abarax_Scarf": {7},
}


def pack_path(pack_id):
    done = subprocess.run([sys.executable, "-I", str(FETCH), "path", pack_id], capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(f"the {pack_id} pack is not extracted ({done.stderr.strip()}); "
                           f"run: python3 -I tools/assets/fetch.py fetch {pack_id}")
    return done.stdout.strip()


def run_build(out):
    """Runs the build into `out` and returns (exit status, combined output)."""
    done = subprocess.run(
        [sys.executable, "-I", str(BUILD), "--ubc", pack_path("ubc"), "--outfits", pack_path("outfits"), "--out", str(out)],
        capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


class BuildAbarax(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = Path(cls.tmp.name) / "abarax.glb"
        status, cls.output = run_build(cls.path)
        if status != 0 or not cls.path.is_file():
            cls.tmp.cleanup()
            raise AssertionError(f"build_abarax.py failed (exit {status}):\n{cls.output}")
        cls.j = gltf_inspect.load(cls.path)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_skeleton_is_base_plus_scarf(self):
        names = gltf_inspect.joint_names(self.j)
        self.assertEqual(set(names), set(BASE) | set(SCARF))
        self.assertEqual(len(names), 69, "no joint is listed twice")
        self.assertEqual(len(self.j["skins"]), 1, "one skeleton")

    def test_scarf_chain_hangs_from_neck_down_the_back(self):
        parents = gltf_inspect.joint_parents(self.j)
        self.assertEqual([parents[n] for n in SCARF], ["neck_01", "scarf_01", "scarf_02", "scarf_03"])
        at = gltf_inspect.joint_positions(self.j)
        for upper, lower in zip(SCARF, SCARF[1:]):
            self.assertAlmostEqual(math.dist(at[upper], at[lower]), 0.175, places=4, msg=f"{upper} → {lower}")
            self.assertLess(at[lower][1], at[upper][1], f"{lower} hangs below {upper}")
        for name in SCARF:  # glTF faces +Z, so the back is -Z
            self.assertLess(at[name][2], at["neck_01"][2], f"{name} is behind the neck")
            self.assertAlmostEqual(at[name][0], 0.0, places=4, msg=f"{name} is on the spine's plane")

    def test_triangle_budget(self):
        self.assertTrue(1500 <= gltf_inspect.triangle_count(self.j) <= 4000, gltf_inspect.triangle_count(self.j))

    def test_every_primitive_has_uv2_slots_in_range(self):
        self.assertTrue(gltf_inspect.uv2_slots(self.j, self.path) <= set(range(9)))
        self.assertTrue({0, 1, 3, 5, 6, 7} <= gltf_inspect.uv2_slots(self.j, self.path))

    def test_each_mesh_carries_the_slots_of_the_table(self):
        self.assertEqual(sorted(m["name"] for m in self.j["meshes"]), sorted(SLOTS_BY_MESH))
        for mesh, slots in SLOTS_BY_MESH.items():
            self.assertEqual(gltf_inspect.uv2_slots(self.j, self.path, mesh=mesh), slots, mesh)

    def test_no_textures_and_one_material(self):
        self.assertEqual(self.j.get("images", []), [])
        self.assertEqual(self.j.get("textures", []), [])
        self.assertEqual([m["name"] for m in self.j["materials"]], ["toon"])

    def test_skinned_without_vertex_colours_or_animations(self):
        self.assertEqual(self.j.get("animations", []), [])
        for mesh in self.j["meshes"]:
            for prim in mesh["primitives"]:
                attrs = set(prim["attributes"])
                self.assertTrue({"POSITION", "NORMAL", "TEXCOORD_0", "TEXCOORD_1", "JOINTS_0", "WEIGHTS_0"} <= attrs,
                                f"{mesh['name']}: {sorted(attrs)}")
                self.assertFalse(any(a.startswith("COLOR_") for a in attrs), f"{mesh['name']}: {sorted(attrs)}")
        skinned = [n for n in self.j["nodes"] if "mesh" in n]
        self.assertTrue(skinned and all(n.get("skin") == 0 for n in skinned), "every mesh node uses the one skin")

    def test_build_is_deterministic(self):
        again = Path(self.tmp.name) / "again.glb"
        status, output = run_build(again)
        self.assertEqual(status, 0, output)
        self.assertEqual(again.read_bytes(), self.path.read_bytes())


if __name__ == "__main__":
    unittest.main()
