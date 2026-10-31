"""Tests for tools/anim/retarget.py. Synthetic BVH files (CMU joint names, 20 frames at 30 fps) are
retargeted onto Abarax into temporary GLBs by the command line, and each GLB is read back with the
standard-library glTF reader, which shares nothing with Blender: the expected values are worked out here.

Needs bpy (run with tools/bpy_test.sh) and the ual1 pack extracted by
`python3 -I tools/assets/fetch.py fetch ual1` (its A_TPose is the T-pose reference). Four retargetings
of about four seconds each run: the brief's probe (Spine 0 to 30 degrees about X, Hips z 0 to 1), a
second one that tells left from right, one with another reference pose, and one more for determinism.

The BVHs follow the CMU/cgspeed files: Y up, the character faces +Z (so its left is +X), the root's
OFFSET is 0 and its position channels hold its position. Hips is 0.9 m above the lowest point of the legs
(the rest Hips height); LowerBack, Spine, Spine1, Neck and Head go up from it, and there are no arms.
glTF and the BVH share their axes, so a rotation about the BVH's X is a rotation about glTF's X.
"""
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_inspect  # noqa: E402
import retarget  # noqa: E402  (imports bpy, which is what makes mathutils importable)
from mathutils import Vector  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]  # the all-divine folder
SCRIPT = ROOT / "tools" / "anim" / "retarget.py"
BONEMAP = ROOT / "tools" / "anim" / "bonemap_cmu.json"
FETCH = ROOT / "tools" / "assets" / "fetch.py"
TARGET = ROOT / "assets" / "characters" / "abarax" / "abarax.glb"
UAL1_GLB = Path("Universal Animation Library[Standard]", "Unreal-Godot", "UAL1_Standard.glb")

FRAMES, FPS = 20, 30
HIPS_HEIGHT = 0.9
SPINE_DEGREES = 30.0
TRAVEL = 1.0
SIDE_TRAVEL, START_X, START_Z = 0.5, 1.5, -2.0
LEG_DEGREES, TURN_DEGREES = 20.0, 25.0
CLIP = "probe"

# CMU (cgspeed) joints in the order the BVH lists them: (name, parent, offset)
JOINTS = [
    ("Hips", None, (0.0, 0.0, 0.0)),
    ("LeftUpLeg", "Hips", (0.09, -0.05, 0.0)),
    ("LeftLeg", "LeftUpLeg", (0.0, -0.4, 0.0)),
    ("LeftFoot", "LeftLeg", (0.0, -0.4, 0.0)),
    ("LeftToeBase", "LeftFoot", (0.0, -0.05, 0.12)),
    ("RightUpLeg", "Hips", (-0.09, -0.05, 0.0)),
    ("RightLeg", "RightUpLeg", (0.0, -0.4, 0.0)),
    ("RightFoot", "RightLeg", (0.0, -0.4, 0.0)),
    ("RightToeBase", "RightFoot", (0.0, -0.05, 0.12)),
    ("LowerBack", "Hips", (0.0, 0.1, 0.0)),
    ("Spine", "LowerBack", (0.0, 0.12, 0.0)),
    ("Spine1", "Spine", (0.0, 0.14, 0.0)),
    ("Neck", "Spine1", (0.0, 0.2, 0.0)),
    ("Head", "Neck", (0.0, 0.1, 0.0)),
]
END_SITES = {"LeftToeBase": (0.0, 0.0, 0.08), "RightToeBase": (0.0, 0.0, 0.08), "Head": (0.0, 0.15, 0.0)}
BVH_JOINTS = [name for name, _, _ in JOINTS]


def spine_motion(t):
    """The brief's probe, at t in [0, 1]: Spine bends 0 to 30 degrees about X while Hips goes from z = 0 to z = 1."""
    return (0.0, HIPS_HEIGHT, TRAVEL * t), {"Spine": (0.0, 0.0, SPINE_DEGREES * t)}


def sideways_motion(t):
    """Left and right told apart: Hips goes from x = 1.5 (a long way from the origin) 0.5 to its left, LeftUpLeg
    swings out 20 degrees about Z, and Head turns 25 degrees about Y (towards +X, over its left shoulder)."""
    return (START_X + SIDE_TRAVEL * t, HIPS_HEIGHT, START_Z), {"LeftUpLeg": (LEG_DEGREES * t, 0.0, 0.0),
                                                              "Head": (0.0, TURN_DEGREES * t, 0.0)}


def bvh_text(frames=FRAMES, fps=FPS, motion=spine_motion):
    """A BVH of JOINTS; `motion(t)` gives, for t = 0 to 1 over the frames, the root's position and the
    (Zrotation, Yrotation, Xrotation) degrees of the joints that turn."""
    lines = ["HIERARCHY"]

    def write(name, depth):
        _, parent, offset = next(j for j in JOINTS if j[0] == name)
        pad = "\t" * depth
        lines.append(f"{pad}{'ROOT' if parent is None else 'JOINT'} {name}")
        lines.append(pad + "{")
        lines.append(f"{pad}\tOFFSET {offset[0]} {offset[1]} {offset[2]}")
        if parent is None:
            lines.append(f"{pad}\tCHANNELS 6 Xposition Yposition Zposition Zrotation Yrotation Xrotation")
        else:
            lines.append(f"{pad}\tCHANNELS 3 Zrotation Yrotation Xrotation")
        for child, parent_of_child, _ in JOINTS:
            if parent_of_child == name:
                write(child, depth + 1)
        if name in END_SITES:
            lines.append(f"{pad}\tEnd Site")
            lines.append(pad + "\t{")
            lines.append(f"{pad}\t\tOFFSET {END_SITES[name][0]} {END_SITES[name][1]} {END_SITES[name][2]}")
            lines.append(pad + "\t}")
        lines.append(pad + "}")

    write("Hips", 0)
    lines += ["MOTION", f"Frames: {frames}", f"Frame Time: {1.0 / fps:.6f}"]
    # JOINTS lists the joints depth first, which is the order of their channels in a frame
    for f in range(frames):
        position, turns = motion(f / max(frames - 1, 1))
        values = [*position, 0.0, 0.0, 0.0]
        for name, _, _ in JOINTS[1:]:
            values += turns.get(name, (0.0, 0.0, 0.0))
        lines.append(" ".join(f"{v:.6f}" for v in values))
    return "\n".join(lines) + "\n"


def pack_path(pack_id):
    done = subprocess.run([sys.executable, "-I", str(FETCH), "path", pack_id], capture_output=True, text=True)
    if done.returncode != 0:
        raise RuntimeError(f"the {pack_id} pack is not extracted ({done.stderr.strip()}); "
                           f"run: python3 -I tools/assets/fetch.py fetch {pack_id}")
    return done.stdout.strip()


def ual1_glb():
    return Path(pack_path("ual1")) / UAL1_GLB


def run_cli(bvh, out, tpose_clip="A_TPose"):
    """Runs retarget.py as a command; returns (exit status, combined output)."""
    done = subprocess.run(
        [sys.executable, "-I", str(SCRIPT), "--bvh", str(bvh), "--map", str(BONEMAP), "--target", str(TARGET),
         "--tpose", str(ual1_glb()), "--tpose-clip", tpose_clip, "--out", str(out), "--name", CLIP],
        capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


# --- rotations as 3x3 nested lists, from the 4x4 world matrices of gltf_inspect ---

def rotation_of(matrix):
    """The rotation part of a 4x4 world matrix, with its (near 1) scale taken out."""
    columns = [[matrix[r][c] for r in range(3)] for c in range(3)]
    lengths = [math.sqrt(sum(v * v for v in col)) for col in columns]
    return [[columns[c][r] / lengths[c] for c in range(3)] for r in range(3)]


def mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


def transpose(a):
    return [[a[c][r] for c in range(3)] for r in range(3)]


def angle_and_axis(r):
    """(angle in degrees, unit axis) of a rotation matrix."""
    cos = max(-1.0, min(1.0, (r[0][0] + r[1][1] + r[2][2] - 1.0) / 2.0))
    angle = math.acos(cos)
    axis = [r[2][1] - r[1][2], r[0][2] - r[2][0], r[1][0] - r[0][1]]
    norm = math.sqrt(sum(v * v for v in axis))
    if norm < 1e-9:
        return math.degrees(angle), (1.0, 0.0, 0.0)
    return math.degrees(angle), tuple(v / norm for v in axis)


def degrees_between(a, b):
    return angle_and_axis(mul(a, transpose(b)))[0]


def world_change(matrices, reference, joint):
    """(angle in degrees, axis) of the world rotation `joint` has in `matrices`, relative to the reference."""
    return angle_and_axis(mul(rotation_of(matrices[joint]), transpose(reference[joint])))


def position_of(matrix):
    return tuple(matrix[r][3] for r in range(3))


def t_pose_reference(target_j, target_rest, clip="A_TPose"):
    """The world rotation of every joint of Abarax in the T-pose reference, worked out from the glTF files
    alone: the world rotation change the first frame of `clip` makes to each joint of the Quaternius
    mannequin (UAL1_Standard.glb), applied on top of Abarax's rest rotation. A joint the mannequin lacks
    (the scarf) keeps its rest rotation relative to its parent."""
    path = ual1_glb()
    ual = gltf_inspect.load(path)
    ual_rest = gltf_inspect.joint_world_matrices(ual)
    ual_pose = gltf_inspect.joint_world_matrices(ual, gltf_inspect.animation_tracks(ual, path, clip), 0)
    parents = gltf_inspect.joint_parents(target_j)
    found = {}

    def of(joint):
        if joint not in found:
            if joint in ual_rest:
                change = mul(rotation_of(ual_pose[joint]), transpose(rotation_of(ual_rest[joint])))
                found[joint] = mul(change, target_rest[joint])
            else:
                parent = parents[joint]
                found[joint] = mul(of(parent), mul(transpose(target_rest[parent]), target_rest[joint]))
        return found[joint]

    return {joint: of(joint) for joint in parents}


class Retarget(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls.tmp.name)
        cls.bvh = cls.dir / "probe.bvh"
        cls.bvh.write_text(bvh_text())
        cls.path = cls.dir / "out.glb"
        status, cls.output = run_cli(cls.bvh, cls.path)
        if status != 0 or not cls.path.is_file():
            cls.tmp.cleanup()
            raise AssertionError(f"retarget.py failed (exit {status}):\n{cls.output}")
        cls.j = gltf_inspect.load(cls.path)
        cls.tracks = gltf_inspect.animation_tracks(cls.j, cls.path, CLIP)
        cls.target_j = gltf_inspect.load(TARGET)
        cls.rest = {n: rotation_of(m) for n, m in gltf_inspect.joint_world_matrices(cls.target_j).items()}
        cls.first = gltf_inspect.joint_world_matrices(cls.j, cls.tracks, 0)
        cls.last = gltf_inspect.joint_world_matrices(cls.j, cls.tracks, -1)
        cls.mapped = {target for source, target in retarget.load_bonemap(BONEMAP).items()
                      if source in BVH_JOINTS}
        cls.reference = t_pose_reference(cls.target_j, cls.rest)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def world_change(self, joint):
        """The world rotation `joint` has at the last frame, relative to the T-pose reference."""
        return world_change(self.last, self.reference, joint)

    # --- the file ---

    def test_one_animation_named_after_the_clip(self):
        self.assertEqual(gltf_inspect.animation_names(self.j), [CLIP])

    def test_clip_has_the_bvh_frames_at_its_rate(self):
        times, values = self.tracks["pelvis"]["translation"]
        self.assertEqual(len(times), FRAMES)
        self.assertEqual(len(values), FRAMES)
        self.assertAlmostEqual(times[0], 0.0, places=5)
        self.assertAlmostEqual(times[-1], (FRAMES - 1) / FPS, places=4)

    def test_model_comes_through_the_round_trip(self):
        self.assertEqual(gltf_inspect.joint_names(self.j), gltf_inspect.joint_names(self.target_j))
        self.assertEqual(gltf_inspect.triangle_count(self.j), gltf_inspect.triangle_count(self.target_j))
        self.assertEqual(gltf_inspect.uv2_slots(self.j, self.path), gltf_inspect.uv2_slots(self.target_j, TARGET))
        was, now = gltf_inspect.joint_positions(self.target_j), gltf_inspect.joint_positions(self.j)
        for name, position in was.items():
            self.assertLess(math.dist(position, now[name]), 1e-4, f"{name} rests where it did")

    # --- the retargeting ---

    def test_spine_rotation_carries_over(self):
        angle, axis = self.world_change("spine_02")
        self.assertAlmostEqual(angle, SPINE_DEGREES, delta=2.0)
        self.assertGreater(axis[0], math.cos(math.radians(2.0)), f"about the world X axis, not {axis}")

    def test_rotation_is_a_world_change_so_it_follows_the_chain_not_the_rest(self):
        # What is above the spine and below it in the BVH does not turn; what hangs from it turns with it
        # (the BVH gives Spine1, Neck and Head no rotation of their own, so their world rotation is the spine's).
        for joint in ("pelvis", "spine_01", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "foot_r"):
            self.assertLess(self.world_change(joint)[0], 1.0, joint)
        for joint in ("spine_03", "neck_01", "Head"):
            angle, axis = self.world_change(joint)
            self.assertAlmostEqual(angle, SPINE_DEGREES, delta=2.0, msg=joint)
            self.assertGreater(axis[0], 0.998, joint)

    def test_root_translation_scales_by_hip_height(self):
        target_hip = gltf_inspect.joint_positions(self.target_j)["pelvis"][1]
        scale = target_hip / HIPS_HEIGHT
        start, end = position_of(self.first["pelvis"]), position_of(self.last["pelvis"])
        self.assertAlmostEqual((end[2] - start[2]) / (TRAVEL * scale), 1.0, delta=0.02)
        self.assertAlmostEqual(end[0] - start[0], 0.0, delta=0.005)
        self.assertAlmostEqual(end[1] - start[1], 0.0, delta=0.005)
        self.assertAlmostEqual(end[1] / (HIPS_HEIGHT * scale), 1.0, delta=0.01, msg="pelvis rides at his hip height")

    def test_frame_zero_is_the_t_pose_reference(self):
        # The BVH's first frame has no rotation, so every joint is where the reference puts it.
        for joint, want in self.reference.items():
            self.assertLess(degrees_between(rotation_of(self.first[joint]), want), 0.5, joint)

    def test_the_reference_is_a_t_pose(self):
        # Checked on the output's own joints: his arms stretch out sideways along +X (left) and -X (right).
        for side, sign in (("l", 1.0), ("r", -1.0)):
            reach = [self.first[f"hand_{side}"][r][3] - self.first[f"upperarm_{side}"][r][3] for r in range(3)]
            length = math.sqrt(sum(v * v for v in reach))
            self.assertGreater(sign * reach[0] / length, 0.99, f"arm_{side} points out sideways")
            self.assertLess(abs(reach[1] / length), 0.1, f"arm_{side} is level")

    def test_unmapped_bones_keep_reference_pose(self):
        # A bone the BVH does not drive keeps the pose it has in the reference relative to its parent, in
        # every frame: the fingers stay on the hand and the scarf on the neck, wherever the spine goes.
        names = gltf_inspect.joint_names(self.j)
        unmapped = [n for n in names if n not in self.mapped]
        self.assertEqual(len(unmapped), 69 - len(self.mapped))
        self.assertTrue({"root", "index_02_l", "thumb_01_r", "clavicle_l", "hand_r", "ball_leaf_l", "scarf_04"}
                        <= set(unmapped))
        parents = gltf_inspect.joint_parents(self.j)
        for frame, matrices in (("first", self.first), ("last", self.last)):
            for name in unmapped:
                parent = parents[name]
                if parent is None:
                    continue
                local = mul(transpose(rotation_of(matrices[parent])), rotation_of(matrices[name]))
                want = mul(transpose(self.reference[parent]), self.reference[name])
                self.assertLess(degrees_between(local, want), 0.5, f"{name}, {frame} frame")

    def test_the_arms_follow_the_spine_when_it_turns(self):
        # Unmapped in this BVH, so they keep their pose relative to spine_03, which turned 30 degrees.
        angle, _ = self.world_change("hand_l")
        self.assertAlmostEqual(angle, SPINE_DEGREES, delta=2.0)

    def test_same_input_gives_the_same_bytes(self):
        again = self.dir / "again.glb"
        status, output = run_cli(self.bvh, again)
        self.assertEqual(status, 0, output)
        self.assertEqual(again.read_bytes(), self.path.read_bytes())


class Handedness(unittest.TestCase):
    """Left and right, and the direction of a turn, are not swapped on the way: a BVH with the left leg out,
    the head turned to the left and the hips moving to the left (+X, as in the BVH and the glTF)."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        bvh = Path(cls.tmp.name) / "sideways.bvh"
        bvh.write_text(bvh_text(motion=sideways_motion))
        cls.path = Path(cls.tmp.name) / "out.glb"
        status, output = run_cli(bvh, cls.path)
        if status != 0:
            cls.tmp.cleanup()
            raise AssertionError(f"retarget.py failed (exit {status}):\n{output}")
        j = gltf_inspect.load(cls.path)
        tracks = gltf_inspect.animation_tracks(j, cls.path, CLIP)
        target_j = gltf_inspect.load(TARGET)
        rest = {n: rotation_of(m) for n, m in gltf_inspect.joint_world_matrices(target_j).items()}
        cls.reference = t_pose_reference(target_j, rest)
        cls.first = gltf_inspect.joint_world_matrices(j, tracks, 0)
        cls.last = gltf_inspect.joint_world_matrices(j, tracks, -1)
        cls.pelvis = gltf_inspect.joint_positions(target_j)["pelvis"]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_left_leg_swings_out_to_the_left(self):
        for joint in ("thigh_l", "calf_l", "foot_l"):
            angle, axis = world_change(self.last, self.reference, joint)
            self.assertAlmostEqual(angle, LEG_DEGREES, delta=1.0, msg=joint)
            self.assertGreater(axis[2], 0.998, f"{joint}: about +Z, not {axis}")
        for joint in ("thigh_r", "foot_r", "pelvis"):
            self.assertLess(world_change(self.last, self.reference, joint)[0], 1.0, joint)
        foot = [self.last["foot_l"][r][3] - self.first["foot_l"][r][3] for r in range(3)]
        self.assertGreater(foot[0], 0.2, "the left foot is out to +X")

    def test_head_turns_towards_the_left_shoulder(self):
        angle, axis = world_change(self.last, self.reference, "Head")
        self.assertAlmostEqual(angle, TURN_DEGREES, delta=1.0)
        self.assertGreater(axis[1], 0.998, f"about +Y, not {axis}")
        self.assertLess(world_change(self.last, self.reference, "neck_01")[0], 1.0)

    def test_hips_travel_to_the_left(self):
        scale = self.pelvis[1] / HIPS_HEIGHT
        start, end = position_of(self.first["pelvis"]), position_of(self.last["pelvis"])
        self.assertAlmostEqual((end[0] - start[0]) / (SIDE_TRAVEL * scale), 1.0, delta=0.02)
        self.assertAlmostEqual(end[2] - start[2], 0.0, delta=0.005)

    def test_the_pelvis_starts_where_it_rests_whatever_the_bvh_starts_at(self):
        # Only the root's travel from its first frame is applied in the ground plane (the BVH starts at
        # x = 1.5, z = -2); its height is its own.
        start = position_of(self.first["pelvis"])
        for got, want in zip(start, self.pelvis):
            self.assertAlmostEqual(got, want, delta=0.005)


class OtherReference(unittest.TestCase):
    """The reference is whatever the clip says, not always the rest pose: with the first frame of the
    mannequin's Idle_Loop (arms hanging at his sides) every joint ends up where the clip's world rotation
    changes put it, as an independent reading of the glTF files works out; and the BVH's rotation still
    comes on top of it, in world space."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        bvh = Path(cls.tmp.name) / "probe.bvh"
        bvh.write_text(bvh_text())
        cls.path = Path(cls.tmp.name) / "out.glb"
        status, output = run_cli(bvh, cls.path, tpose_clip="Idle_Loop")
        if status != 0:
            cls.tmp.cleanup()
            raise AssertionError(f"retarget.py failed (exit {status}):\n{output}")
        j = gltf_inspect.load(cls.path)
        target_j = gltf_inspect.load(TARGET)
        rest = {n: rotation_of(m) for n, m in gltf_inspect.joint_world_matrices(target_j).items()}
        cls.reference = t_pose_reference(target_j, rest, "Idle_Loop")
        cls.rest = rest
        tracks = gltf_inspect.animation_tracks(j, cls.path, CLIP)
        cls.first = gltf_inspect.joint_world_matrices(j, tracks, 0)
        cls.last = gltf_inspect.joint_world_matrices(j, tracks, -1)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_frame_zero_is_the_clips_first_frame(self):
        for joint, want in self.reference.items():
            self.assertLess(degrees_between(rotation_of(self.first[joint]), want), 0.5, joint)

    def test_it_is_not_the_rest_pose(self):
        moved = [joint for joint, want in self.reference.items() if degrees_between(self.rest[joint], want) > 10.0]
        self.assertTrue({"upperarm_l", "upperarm_r"} <= set(moved), moved)
        reach = [self.first["hand_l"][r][3] - self.first["upperarm_l"][r][3] for r in range(3)]
        self.assertLess(reach[1], -0.2, "his left hand hangs below his shoulder")

    def test_the_bvh_rotation_comes_on_top_of_the_reference_in_world_space(self):
        # The spine of Idle_Loop's first frame is not the rest pose, so the order of the two rotations shows.
        angle, axis = world_change(self.last, self.reference, "spine_02")
        self.assertAlmostEqual(angle, SPINE_DEGREES, delta=2.0)
        self.assertGreater(axis[0], 0.998, f"about the world X axis, not {axis}")


class BoneMap(unittest.TestCase):
    def test_the_cmu_map_is_the_one_in_the_brief(self):
        mapping = retarget.load_bonemap(BONEMAP)
        want = {
            "Hips": "pelvis", "LowerBack": "spine_01", "Spine": "spine_02", "Spine1": "spine_03",
            "Neck": "neck_01", "Head": "Head",
        }
        for side, suffix in (("Left", "l"), ("Right", "r")):
            want.update({
                f"{side}Shoulder": f"clavicle_{suffix}", f"{side}Arm": f"upperarm_{suffix}",
                f"{side}ForeArm": f"lowerarm_{suffix}", f"{side}Hand": f"hand_{suffix}",
                f"{side}UpLeg": f"thigh_{suffix}", f"{side}Leg": f"calf_{suffix}",
                f"{side}Foot": f"foot_{suffix}", f"{side}ToeBase": f"ball_{suffix}",
            })
        self.assertEqual(mapping, want)
        self.assertEqual(len(mapping), 22)

    def test_load_bonemap_rejects_what_is_not_a_map(self):
        with tempfile.TemporaryDirectory() as tmp:
            def load(text):
                path = Path(tmp) / "map.json"
                path.write_text(text)
                return retarget.load_bonemap(path)

            self.assertEqual(load('{"A": "a", "B": "b"}'), {"A": "a", "B": "b"})
            for bad in ("[]", '{"A": 1}', '{"A": ""}', '{"A": "x", "B": "x"}', "{not json"):
                with self.assertRaises(retarget.RetargetError, msg=bad):
                    load(bad)
            with self.assertRaises(retarget.RetargetError):
                retarget.load_bonemap(Path(tmp) / "missing.json")


class BvhFile(unittest.TestCase):
    def parse(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "t.bvh"
            path.write_text(text)
            return retarget.parse_bvh(path)

    def test_hierarchy_frames_and_rest_height(self):
        bvh = self.parse(bvh_text())
        self.assertEqual([j.name for j in bvh.joints], BVH_JOINTS)
        self.assertEqual(len(bvh.frames), FRAMES)
        self.assertAlmostEqual(bvh.frame_time, 1.0 / FPS, places=6)
        self.assertAlmostEqual(bvh.hip_height(), HIPS_HEIGHT, places=6)

    def test_rotation_channels_compose_in_the_order_they_are_listed(self):
        # Zrotation 90, Yrotation 0, Xrotation 90 means R = Rz(90) Rx(90): it takes +Y to +Z (Rx) and then
        # +Z stays (Rz), and takes +X to +X (Rx) and then +Y (Rz).
        text = bvh_text(frames=1).split("MOTION")[0] + "MOTION\nFrames: 1\nFrame Time: 0.033333\n"
        values = [0.0] * (6 + 3 * 13)  # the root's six values, then three per other joint in listing order
        index = 6 + 3 * (BVH_JOINTS.index("Spine") - 1)
        values[index], values[index + 1], values[index + 2] = 90.0, 0.0, 90.0
        bvh = self.parse(text + " ".join(str(v) for v in values) + "\n")
        world = bvh.world_rotations(0)["Spine"]
        for vector, want in (((0, 1, 0), (0, 0, 1)), ((1, 0, 0), (0, 1, 0))):
            got = world @ Vector(vector)
            self.assertLess((got - Vector(want)).length, 1e-6, f"{vector} -> {tuple(got)}")

    def test_a_different_channel_order_is_honoured(self):
        text = bvh_text(frames=1).replace("CHANNELS 3 Zrotation Yrotation Xrotation",
                                          "CHANNELS 3 Xrotation Zrotation Yrotation", 1)
        bvh = self.parse(text.split("MOTION")[0] + "MOTION\nFrames: 1\nFrame Time: 0.033333\n"
                         + " ".join(["0"] * (6 + 3 * 13)) + "\n")
        self.assertEqual(bvh.joints[1].rotation_order, "XZY")

    def test_malformed_files_are_refused(self):
        good = bvh_text(frames=2)
        for name, text in (
            ("no motion", good.split("MOTION")[0]),
            ("short frame", good.rsplit("\n", 2)[0] + "\n0 0 0\n"),
            ("frame count", good.replace("Frames: 2", "Frames: 3")),
            ("no frame time", good.replace("Frame Time: 0.033333", "Frame Time: 0")),
            ("no hierarchy", "MOTION\nFrames: 1\nFrame Time: 0.03\n0\n"),
            ("two joints of a name", good.replace("JOINT Spine1", "JOINT Spine", 1)),
        ):
            with self.assertRaises(retarget.RetargetError, msg=name):
                self.parse(text)


class Refusals(unittest.TestCase):
    def test_a_map_naming_a_bone_abarax_lacks_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            bvh = Path(tmp) / "probe.bvh"
            bvh.write_text(bvh_text(frames=2))
            mapping = dict(retarget.load_bonemap(BONEMAP), Spine="spine_99")
            with self.assertRaisesRegex(retarget.RetargetError, "spine_99"):
                retarget.retarget(bvh, mapping, TARGET, ual1_glb(), "A_TPose", Path(tmp) / "out.glb", CLIP)
            self.assertFalse((Path(tmp) / "out.glb").exists())

    def test_a_tpose_clip_the_file_lacks_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            bvh = Path(tmp) / "probe.bvh"
            bvh.write_text(bvh_text(frames=2))
            with self.assertRaisesRegex(retarget.RetargetError, "No_Such_Clip"):
                retarget.retarget(bvh, retarget.load_bonemap(BONEMAP), TARGET, ual1_glb(), "No_Such_Clip",
                                  Path(tmp) / "out.glb", CLIP)

    def test_a_bvh_whose_root_is_not_mapped_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            bvh = Path(tmp) / "probe.bvh"
            bvh.write_text(bvh_text(frames=2))
            mapping = {k: v for k, v in retarget.load_bonemap(BONEMAP).items() if k != "Hips"}
            with self.assertRaisesRegex(retarget.RetargetError, "Hips"):
                retarget.retarget(bvh, mapping, TARGET, ual1_glb(), "A_TPose", Path(tmp) / "out.glb", CLIP)

    def test_command_line_reports_a_refusal_and_exits_1(self):
        with tempfile.TemporaryDirectory() as tmp:
            bvh = Path(tmp) / "probe.bvh"
            bvh.write_text("not a bvh")
            status, output = run_cli(bvh, Path(tmp) / "out.glb")
            self.assertEqual(status, 1, output)
            self.assertIn("retarget.py:", output)
            self.assertNotIn("Traceback", output)


if __name__ == "__main__":
    unittest.main()
