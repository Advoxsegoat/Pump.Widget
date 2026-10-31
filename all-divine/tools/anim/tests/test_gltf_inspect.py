"""Tests for tools/anim/gltf_inspect.py on small glTF files written here. Standard library only."""
import json
import math
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gltf_inspect  # noqa: E402

FLOAT, USHORT = 5126, 5123


class Writer:
    """Collects buffer data and accessors for a one-buffer glTF."""

    def __init__(self):
        self.blob = bytearray()
        self.views, self.accessors = [], []

    def accessor(self, fmt, values, component, kind, normalized=False):
        while len(self.blob) % 4:
            self.blob.append(0)
        data = struct.pack("<" + fmt * len(values), *values)
        self.views.append({"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)})
        self.blob += data
        per = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[kind]
        accessor = {"bufferView": len(self.views) - 1, "componentType": component, "count": len(values) // per, "type": kind}
        if normalized:
            accessor["normalized"] = True
        self.accessors.append(accessor)
        return len(self.accessors) - 1


def slot_u(slot):
    return (slot + 0.5) / 16


def sample():
    """A skin of two joints (root, then `arm` one metre up and turned 90° about Z, then `hand` one
    metre along arm's +X), a mesh `body` with an indexed primitive (2 triangles, slots 0, 3 and 8 as
    floats) and a plain one (1 triangle, slot 5 as normalized unsigned shorts), a mesh `bad` (1
    triangle, one UV2 off a slot centre) and a mesh `bare` (1 triangle, no TEXCOORD_1)."""
    w = Writer()
    quad = w.accessor("f", [0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0], FLOAT, "VEC3")
    tri = w.accessor("f", [0, 0, 0, 1, 0, 0, 0, 1, 0], FLOAT, "VEC3")
    indices = w.accessor("H", [0, 1, 2, 0, 2, 3], USHORT, "SCALAR")
    quad_uv2 = w.accessor("f", [slot_u(0), 0.5, slot_u(3), 0.5, slot_u(8), 0.5, slot_u(8), 0.5], FLOAT, "VEC2")
    short_uv2 = w.accessor("H", [round(slot_u(5) * 65535), 0] * 3, USHORT, "VEC2", normalized=True)
    off_uv2 = w.accessor("f", [slot_u(1), 0.5, slot_u(1) + 0.01, 0.5, slot_u(1), 0.5], FLOAT, "VEC2")
    s = math.sqrt(0.5)
    j = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [
            {"name": "Armature", "children": [1, 4, 5, 6]},
            {"name": "root", "children": [2]},
            {"name": "arm", "translation": [0, 1, 0], "rotation": [0, 0, s, s], "children": [3]},
            {"name": "hand", "translation": [1, 0, 0]},
            {"name": "body", "mesh": 0, "skin": 0},
            {"name": "bad", "mesh": 1, "skin": 0},
            {"name": "bare", "mesh": 2, "skin": 0},
        ],
        "skins": [{"joints": [1, 2, 3]}],
        "meshes": [
            {"name": "body", "primitives": [
                {"attributes": {"POSITION": quad, "TEXCOORD_1": quad_uv2}, "indices": indices},
                {"attributes": {"POSITION": tri, "TEXCOORD_1": short_uv2}},
            ]},
            {"name": "bad", "primitives": [{"attributes": {"POSITION": tri, "TEXCOORD_1": off_uv2}}]},
            {"name": "bare", "primitives": [{"attributes": {"POSITION": tri}}]},
        ],
        "accessors": w.accessors,
        "bufferViews": w.views,
        "buffers": [{"byteLength": len(w.blob)}],
    }
    return j, bytes(w.blob)


def glb_bytes(j, blob):
    text = json.dumps(j).encode()
    text += b" " * (-len(text) % 4)
    blob += b"\0" * (-len(blob) % 4)
    body = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(blob), b"BIN\0") + blob
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


class GltfInspect(unittest.TestCase):
    def setUp(self):
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.dir = Path(holder.name)
        self.j, self.blob = sample()
        self.glb = self.dir / "sample.glb"
        self.glb.write_bytes(glb_bytes(self.j, self.blob))

    def test_load_reads_glb_and_gltf_with_an_external_buffer(self):
        self.assertEqual(gltf_inspect.load(self.glb)["meshes"][0]["name"], "body")
        j = dict(self.j, buffers=[{"byteLength": len(self.blob), "uri": "sample.bin"}])
        (self.dir / "sample.bin").write_bytes(self.blob)
        (self.dir / "sample.gltf").write_text(json.dumps(j))
        loaded = gltf_inspect.load(self.dir / "sample.gltf")
        self.assertEqual(gltf_inspect.uv2_slots(loaded, self.dir / "sample.gltf", mesh="body"), {0, 3, 5, 8})

    def test_load_rejects_a_file_that_is_not_gltf(self):
        bad = self.dir / "bad.glb"
        bad.write_bytes(b"glTF" + b"\0" * 4)
        with self.assertRaises(ValueError):
            gltf_inspect.load(bad)

    def test_joints_their_parents_and_rest_positions(self):
        j = gltf_inspect.load(self.glb)
        self.assertEqual(gltf_inspect.joint_names(j), ["root", "arm", "hand"])
        self.assertEqual(gltf_inspect.joint_parents(j), {"root": None, "arm": "root", "hand": "arm"})
        at = gltf_inspect.joint_positions(j)
        for name, want in {"root": (0, 0, 0), "arm": (0, 1, 0), "hand": (0, 2, 0)}.items():
            for got, expected in zip(at[name], want):
                self.assertAlmostEqual(got, expected, places=6, msg=name)

    def test_triangle_count_counts_indexed_and_plain_primitives(self):
        self.assertEqual(gltf_inspect.triangle_count(gltf_inspect.load(self.glb)), 2 + 1 + 1 + 1)

    def test_uv2_slots_reads_floats_and_normalized_shorts(self):
        j = gltf_inspect.load(self.glb)
        self.assertEqual(gltf_inspect.uv2_slots(j, self.glb, mesh="body"), {0, 3, 5, 8})

    def test_uv2_slots_marks_values_off_a_slot_centre_and_missing_uv2_with_minus_one(self):
        j = gltf_inspect.load(self.glb)
        self.assertEqual(gltf_inspect.uv2_slots(j, self.glb, mesh="bad"), {1, -1})
        self.assertEqual(gltf_inspect.uv2_slots(j, self.glb, mesh="bare"), {-1})
        self.assertEqual(gltf_inspect.uv2_slots(j, self.glb), {0, 1, 3, 5, 8, -1})
        self.assertFalse(gltf_inspect.uv2_slots(j, self.glb) <= set(range(9)))


if __name__ == "__main__":
    unittest.main()
