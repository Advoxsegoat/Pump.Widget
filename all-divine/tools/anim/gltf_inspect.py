#!/usr/bin/env python3
"""Reads glTF 2.0 files (.gltf with its buffers, or .glb) for tests and checks. Standard library only.

    load(path) -> dict                     the glTF JSON
    joint_names(j) -> list[str]            the joints of every skin, in skin order, each once
    joint_parents(j) -> dict[str, str|None]  each joint's parent joint (None for a skin's root)
    joint_positions(j) -> dict[str, tuple] each joint's rest position in glTF space (Y up, +Z front)
    triangle_count(j) -> int               triangles drawn by the mesh nodes
    uv2_slots(j, path, mesh=None) -> set[int]  the palette slots in TEXCOORD_1 (UV2)

Palette slots are stored as UV2.x = (slot + 0.5) / 16. uv2_slots reports -1 for a value that is not
a slot centre and for a primitive with no TEXCOORD_1, so `uv2_slots(...) <= set(range(9))` fails
on either.

    python3 -I tools/anim/gltf_inspect.py <file>   prints joints, triangles and slots per mesh
"""
import json
import math
import struct
import sys
from pathlib import Path

PALETTE_SIZE = 16
SLOT_TOLERANCE = 1e-3  # in slots; 16-bit normalized UVs are off by at most 16 / 65535

_GLB_MAGIC = b"glTF"
_JSON_CHUNK = 0x4E4F534A
_BIN_CHUNK = 0x004E4942
_COMPONENTS = {  # componentType: (struct format, bytes, divisor when normalized)
    5120: ("b", 1, 127.0),
    5121: ("B", 1, 255.0),
    5122: ("h", 2, 32767.0),
    5123: ("H", 2, 65535.0),
    5125: ("I", 4, 4294967295.0),
    5126: ("f", 4, None),
}
_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
_TRIANGLES, _TRIANGLE_STRIP, _TRIANGLE_FAN = 4, 5, 6


def _chunks(data):
    """The (json bytes, bin bytes or None) of a GLB."""
    if len(data) < 20:
        raise ValueError("too short to be a GLB")
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != _GLB_MAGIC or version != 2 or length > len(data):
        raise ValueError("not a glTF 2.0 binary")
    text = binary = None
    offset = 12
    while offset + 8 <= length:
        size, kind = struct.unpack_from("<II", data, offset)
        body = data[offset + 8:offset + 8 + size]
        if kind == _JSON_CHUNK and text is None:
            text = body
        elif kind == _BIN_CHUNK and binary is None:
            binary = body
        offset += 8 + size
    if text is None:
        raise ValueError("a GLB with no JSON chunk")
    return text, binary


def load(path):
    """The glTF JSON of a .gltf or .glb file, as a dict."""
    data = Path(path).read_bytes()
    if data[:4] == _GLB_MAGIC:
        text, _ = _chunks(data)
        return json.loads(text)
    return json.loads(data)


def _buffers(j, path):
    """The bytes of each buffer: the GLB's BIN chunk for a uri-less buffer, or the file the uri names."""
    path = Path(path)
    data = path.read_bytes()
    binary = _chunks(data)[1] if data[:4] == _GLB_MAGIC else None
    found = []
    for buffer in j.get("buffers", []):
        uri = buffer.get("uri")
        if uri is None:
            if binary is None:
                raise ValueError("a buffer with no uri outside a GLB")
            found.append(binary)
        elif uri.startswith("data:"):
            raise ValueError("data: URIs are not supported")
        else:
            found.append((path.parent / uri).read_bytes())
    return found


def _read_accessor(j, buffers, index):
    """An accessor's values as a list of tuples (floats if normalized, else as stored)."""
    accessor = j["accessors"][index]
    width = _WIDTH[accessor["type"]]
    fmt, size, divisor = _COMPONENTS[accessor["componentType"]]
    count = accessor["count"]
    if "bufferView" not in accessor:
        return [(0,) * width for _ in range(count)]
    view = j["bufferViews"][accessor["bufferView"]]
    data = buffers[view["buffer"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride") or width * size
    values = []
    for i in range(count):
        item = struct.unpack_from("<" + fmt * width, data, start + i * stride)
        if accessor.get("normalized") and divisor:
            item = tuple(max(v / divisor, -1.0) for v in item)
        values.append(item)
    return values


def joint_names(j):
    names = []
    for skin in j.get("skins", []):
        for index in skin["joints"]:
            name = _name(j, index)
            if name not in names:
                names.append(name)
    return names


def _parents(j):
    return {child: i for i, node in enumerate(j["nodes"]) for child in node.get("children", [])}


def _name(j, index):
    return j["nodes"][index].get("name", f"node{index}")


def joint_parents(j):
    joints = [index for skin in j.get("skins", []) for index in skin["joints"]]
    parents = _parents(j)
    found = {}
    for index in joints:
        parent = parents.get(index)
        found.setdefault(_name(j, index), _name(j, parent) if parent in joints else None)
    return found


def _local_matrix(node):
    if "matrix" in node:
        m = node["matrix"]  # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    sx, sy, sz = node.get("scale", [1.0, 1.0, 1.0])
    tx, ty, tz = node.get("translation", [0.0, 0.0, 0.0])
    rot = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    scale = (sx, sy, sz)
    return [[rot[r][c] * scale[c] for c in range(3)] + [(tx, ty, tz)[r]] for r in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def _multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def _global_matrices(j):
    parents = _parents(j)
    cache = {}

    def matrix(index):
        if index not in cache:
            local = _local_matrix(j["nodes"][index])
            cache[index] = _multiply(matrix(parents[index]), local) if index in parents else local
        return cache[index]

    return matrix


def joint_positions(j):
    matrix = _global_matrices(j)
    found = {}
    for skin in j.get("skins", []):
        for index in skin["joints"]:
            m = matrix(index)
            found[_name(j, index)] = (m[0][3], m[1][3], m[2][3])
    return found


def _primitive_triangles(j, primitive):
    mode = primitive.get("mode", _TRIANGLES)
    if "indices" in primitive:
        count = j["accessors"][primitive["indices"]]["count"]
    else:
        count = j["accessors"][primitive["attributes"]["POSITION"]]["count"]
    if mode == _TRIANGLES:
        return count // 3
    if mode in (_TRIANGLE_STRIP, _TRIANGLE_FAN):
        return max(count - 2, 0)
    return 0


def triangle_count(j):
    """Triangles drawn by every node that has a mesh (a mesh used by two nodes counts twice)."""
    total = 0
    for node in j.get("nodes", []):
        if "mesh" in node:
            total += sum(_primitive_triangles(j, p) for p in j["meshes"][node["mesh"]]["primitives"])
    return total


def slot_of(u):
    """The palette slot a UV2.x value stands for, or -1 if it is not a slot centre."""
    at = u * PALETTE_SIZE - 0.5
    slot = round(at)
    return slot if abs(at - slot) <= SLOT_TOLERANCE else -1


def uv2_slots(j, path, mesh=None):
    """Every palette slot found in TEXCOORD_1 of the meshes (only the mesh named `mesh`, if given).
    -1 stands for a value off a slot centre or a primitive without TEXCOORD_1."""
    buffers = _buffers(j, path)
    slots = set()
    for m in j.get("meshes", []):
        if mesh is not None and m.get("name") != mesh:
            continue
        for primitive in m["primitives"]:
            index = primitive["attributes"].get("TEXCOORD_1")
            if index is None:
                slots.add(-1)
                continue
            slots.update(slot_of(uv[0]) for uv in _read_accessor(j, buffers, index))
    return slots


def main(argv):
    if len(argv) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path = argv[0]
    j = load(path)
    print(f"{path}: {triangle_count(j)} triangles, {len(joint_names(j))} joints, "
          f"materials {[m.get('name') for m in j.get('materials', [])]}, images {len(j.get('images', []))}")
    meshes = {i: m for i, m in enumerate(j.get("meshes", []))}
    for node in j.get("nodes", []):
        if "mesh" in node:
            m = meshes[node["mesh"]]
            tris = sum(_primitive_triangles(j, p) for p in m["primitives"])
            print(f"  {m.get('name')}: {tris} triangles, slots {sorted(uv2_slots(j, path, mesh=m.get('name')))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
